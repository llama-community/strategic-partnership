// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.11;

import {ERC20} from "@openzeppelin/token/ERC20/ERC20.sol";
import {FixedPointMathLib} from "@solmate/utils/FixedPointMathLib.sol";

/*///////////////////////////////////////////////////////////////
                            ERRORS
//////////////////////////////////////////////////////////////*/

error AllocationCannotBeZero();
error AlreadyDeposited();
error PartnerPeriodEnded();
error PartnershipNotStarted();
error OnlyDepositor();
error OnlyPartner();
error OnlyPartnersWithBalance();
error PartnerAlreadyFunded();
error BeforeCliff();

/// @title Strategic Partnership
/// @author Austin Green
/// @notice Create a Strategic Partnership.
contract Partnership {
    using FixedPointMathLib for uint256;

    /*///////////////////////////////////////////////////////////////
                               EVENTS
    //////////////////////////////////////////////////////////////*/

    event Deposited(address indexed depositor, uint256 depositTokenAmount);
    event PartnershipFormed(address indexed partner, uint256 exchangeTokenAmount);
    event FundingReceived(address indexed depositor, uint256 exchangeTokenAmount, uint256 depositTokenAmount);
    event DepositTokenClaimed(address indexed partner, uint256 depositTokenAmount);

    /*///////////////////////////////////////////////////////////////
                               IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice The depositor deposits this token.
    ERC20 public immutable depositToken;

    /// @notice Partners enter partnerships by providing this token for a claim on depositTokens.
    ERC20 public immutable exchangeToken;

    /// @notice The length of time in which partners can enter partnerships.
    uint256 public immutable partnerPeriod;

    /// @notice The length of time between partnershipStartedAt and the vesting cliff.
    uint256 public immutable cliffPeriod;

    /// @notice The length of time between the vesting cliff and end of vesting.
    uint256 public immutable vestingPeriod;

    /// @notice Number of exchangeTokens required for 1 depositToken.
    /// @dev A fixed point number multiplied by 100 to avoid decimals (for example 20 is 20_00).
    uint256 public immutable exchangeRate;

    /// @notice The entity depositing the depositToken.
    address public immutable depositor;

    /// @notice Sum of depositTokens allocated to partners.
    uint256 public immutable totalAllocated;

    /// @notice Base unit for fixed point math. Accounts for difference in decimals between deposit and exchange tokens.
    uint256 public immutable BASE_UNIT;

    /*///////////////////////////////////////////////////////////////
                               STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice Approved partners for strategic partnership.
    address[] public partners;

    /// @notice The number of exchangeTokens allocated per partner (matched by index).
    uint256[] public allocations;

    /// @notice A partner's exchange token allocation.
    mapping(address => uint256) public partnerExchangeAllocations;

    /// @notice A partner's remaing balance of allocated but not claimed depositTokens.
    mapping(address => uint256) public partnerBalances;

    /// @notice Initially set at partnershipStartedAt and is updated every time partner successfully claims.
    mapping(address => uint256) public lastWithdrawnAt;

    /// @notice When the partnership begins. Equal to the time of deposit + partnerPeriod.
    uint256 public partnershipStartedAt;

    /// @notice Sum of exchangeTokens sent during partnerPeriod.
    uint256 public totalExchanged;

    /*///////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Creates a new Strategic Partnership contract.
    /// @param _depositToken The token that is being exchanged.
    /// @param _exchangeToken The token partners exchange for the depositToken.
    /// @param _exchangeRate Number of exchangeTokens required for 1 depositToken
    /// @param _partnerPeriod The length of time in which partners can enter partnerships.
    /// @param _cliffPeriod The length of time between partnershipStartedAt and the vesting cliff.
    /// @param _vestingPeriod The length of time between the vesting cliff and end of vesting.
    /// @param _partners Addresses approved for strategic partnerships.
    /// @param _allocations Number of exchangeTokens allocated to each partner.
    /// @param _depositor Address that will be depositing the native token.
    /// @dev Partners and amounts are matched by index
    constructor(
        ERC20 _depositToken,
        ERC20 _exchangeToken,
        uint256 _exchangeRate,
        uint256 _partnerPeriod,
        uint256 _cliffPeriod,
        uint256 _vestingPeriod,
        address[] memory _partners,
        uint256[] memory _allocations,
        address _depositor
    ) {
        require(partners.length == allocations.length, "Partners and allocations must have same length");

        depositToken = _depositToken;
        exchangeToken = _exchangeToken;
        exchangeRate = _exchangeRate;
        partnerPeriod = _partnerPeriod;
        cliffPeriod = _cliffPeriod;
        vestingPeriod = _vestingPeriod;
        partners = _partners;
        allocations = _allocations;
        depositor = _depositor;

        // Used to calculate the base unit for fixed point math
        // Needed because native and funding tokens could have different decimals
        unchecked {
            uint256 z = depositToken.decimals() - exchangeToken.decimals();
            if (z > depositToken.decimals()) {
                z = exchangeToken.decimals() - depositToken.decimals();
            }

            // add 2 to properly account for exchangeRate decimals
            BASE_UNIT = 10**(z + 2);
        }

        // Assign totalAllocated and partnerExchangeAllocations
        uint256 sum = 0;
        uint256 length = partners.length;
        for (uint256 i = 0; i < length; i++) {
            if (allocations[i] == 0) revert AllocationCannotBeZero();
            partnerExchangeAllocations[partners[i]] = allocations[i];
            sum += allocations[i];
        }
        totalAllocated = exchangeToDeposit(sum);
    }

    /*///////////////////////////////////////////////////////////////
                              MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyDepositor() {
        if (msg.sender != depositor) revert OnlyDepositor();
        _;
    }

    modifier onlyPartners() {
        if (partnerExchangeAllocations[msg.sender] == 0) revert OnlyPartner();
        _;
    }

    /*///////////////////////////////////////////////////////////////
                           VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function exchangeToDeposit(uint256 _exchangeTokens) private view returns (uint256) {
        return _exchangeTokens.fdiv(exchangeRate, BASE_UNIT);
    }

    /// @notice Calculate amount of depositTokens that a partner has available to claim.
    function _getClaimableTokens(address _partner) private view returns (uint256) {
        if (partnerExchangeAllocations[_partner] == 0 || partnerBalances[_partner] == 0) return 0;
        uint256 startingDate = lastWithdrawnAt[_partner];
        if (block.timestamp < startingDate + cliffPeriod) return 0;

        uint256 fullyVested = partnershipStartedAt + cliffPeriod + vestingPeriod;
        uint256 endDate = fullyVested > block.timestamp ? block.timestamp : fullyVested;
        uint256 timeVested = endDate - startingDate;
        uint256 lengthOfVesting = cliffPeriod + vestingPeriod;

        uint256 pctVested = timeVested.fdiv(lengthOfVesting, 10**depositToken.decimals());
        uint256 claimableAmount = exchangeToDeposit(partnerExchangeAllocations[_partner]);
        return claimableAmount.fmul(pctVested, 10**depositToken.decimals());
    }

    function getClaimableTokens(address _partner) public view returns (uint256) {
        return _getClaimableTokens(_partner);
    }

    /*///////////////////////////////////////////////////////////////
                              FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Depositor calls this function to deposit native tokens and begin the funding period. Can only be called once.
    /// @dev Assumes depositor has called approve on the depositToken with this contract's address and depositAmount.
    function deposit() external onlyDepositor {
        if (partnershipStartedAt != 0) revert AlreadyDeposited();

        partnershipStartedAt = block.timestamp + partnerPeriod;
        depositToken.transferFrom(depositor, address(this), totalAllocated);

        emit Deposited(msg.sender, totalAllocated);
    }

    /// @notice For partners to provide their allocated amount of the exchangeToken between when the deposit is made and partnershipStartedAt.
    /// @dev Assumes partner has called approve on the exchangeToken with this contract's address and their allocation amount.
    function enterPartnership() external onlyPartners {
        if (block.timestamp >= partnershipStartedAt) revert PartnerPeriodEnded();
        if (partnerBalances[msg.sender] != 0) revert PartnerAlreadyFunded();

        uint256 fundingAmount = partnerExchangeAllocations[msg.sender];
        totalExchanged += fundingAmount;
        partnerBalances[msg.sender] = exchangeToDeposit(fundingAmount);
        lastWithdrawnAt[msg.sender] = partnershipStartedAt;

        exchangeToken.transferFrom(msg.sender, address(this), fundingAmount);

        emit PartnershipFormed(msg.sender, fundingAmount);
    }

    /// @notice Sends unallocated depositTokens and all exchangeTokens to the depositor.
    function claimExchangeTokens() external {
        if (block.timestamp < partnershipStartedAt) revert PartnershipNotStarted();

        uint256 amount = exchangeToken.balanceOf(address(this));
        uint256 unfundedAmount = totalAllocated - exchangeToDeposit(totalExchanged);

        if (unfundedAmount != 0) {
            depositToken.transfer(depositor, unfundedAmount);
        }
        exchangeToken.transfer(depositor, amount);

        emit FundingReceived(depositor, amount, unfundedAmount);
    }

    /// @notice For partners to claim vested depositTokens
    function claimDepositTokens() external onlyPartners {
        uint256 cliffAt = partnershipStartedAt + cliffPeriod;
        if (block.timestamp < cliffAt) revert BeforeCliff();
        if (partnerBalances[msg.sender] == 0) revert OnlyPartnersWithBalance();

        uint256 amountClaimable = _getClaimableTokens(msg.sender);
        partnerBalances[msg.sender] -= amountClaimable;
        lastWithdrawnAt[msg.sender] = block.timestamp;
        depositToken.transfer(msg.sender, amountClaimable);

        emit DepositTokenClaimed(msg.sender, amountClaimable);
    }
}
