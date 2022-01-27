// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.11;

import {ERC20} from "@openzeppelin/token/ERC20/ERC20.sol";
import {FixedPointMathLib} from "@solmate/utils/FixedPointMathLib.sol";

error AlreadyDeposited();
error OnlyDepositor();
error FundingPeriodFinished();
error FundingPeriodNotFinished();
error PartnerAlreadyFunded();
error OnlyPartner();

/// @title Strategic Partnership
/// @author Austin Green
/// @notice Factory for creating and managing Strategic Partnerships.
contract Partnership {
    using FixedPointMathLib for uint256;

    /*///////////////////////////////////////////////////////////////
                               EVENTS
    //////////////////////////////////////////////////////////////*/

    event Deposited();
    event PartnershipFormed(address indexed investor, uint256 amount);
    event FundingReceived(address indexed depositor, uint256 fundingAmount);

    /*///////////////////////////////////////////////////////////////
                               IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice The token that is being exchanged.
    ERC20 public immutable nativeToken;

    /// @notice The token partners exchange for the nativeToken.
    ERC20 public immutable fundingToken;

    /// @notice The time period in which partners can invest.
    uint256 public immutable fundingPeriod;

    /// @notice Amount of time after vestingStartDate when vesting begins.
    uint256 public immutable timeUntilCliff;

    /// @notice The duration of vesting from timeUntilCliff to fully vested.
    uint256 public immutable vestingPeriod;

    /// @notice Number of fundingTokens required for 1 nativeToken
    /// @dev A fixed point number multiplied by 100 to avoid decimals (for example 20 is 20_00).
    uint256 public immutable exchangeRate;

    /// @notice DAO selling the token
    address public immutable depositor;

    /// @notice Sum of amounts
    uint256 public immutable totalAllocated;

    /*///////////////////////////////////////////////////////////////
                               STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice Approved partners
    address[] public partners;

    /// @notice Amount allocated per partner
    uint256[] public allocations;

    /// @notice Amount allocated per partner
    mapping(address => uint256) public partnerFundingAllocations;

    /// @notice Remaining balance
    mapping(address => uint256) public partnerBalances;

    /// @notice Did partner invest
    mapping(address => bool) public hasPartnerInvested;

    /// @notice Starts at vesting date and is reset every time partner withdrawals
    mapping(address => uint256) public partnerLastWithdrawalDate;

    /// @notice When funding ends
    uint256 public vestingStartDate;

    /// @notice The total that was actually invested
    uint256 public totalInvested;

    /*///////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Creates a new Strategic Partnership contract.
    /// @param _nativeToken The token that is being exchanged.
    /// @param _fundingToken The token partners exchange for the nativeToken.
    /// @param _exchangeRate Number of fundingTokens required for 1 nativeToken
    /// @param _fundingPeriod The time period in which partners can invest.
    /// @param _timeUntilCliff The duration between fundingDeadline and vesting cliff.
    /// @param _vestingPeriod The duration between vesting cliff and fully vested.
    /// @param _partners Addresses that can participate.
    /// @param _allocations Max amount that partners can invest.
    /// @param _depositor Account that will be depositing the native token.
    /// @dev Partners and amounts are matched by index
    constructor(
        ERC20 _nativeToken,
        ERC20 _fundingToken,
        uint256 _exchangeRate,
        uint256 _fundingPeriod,
        uint256 _timeUntilCliff,
        uint256 _vestingPeriod,
        address[] memory _partners,
        uint256[] memory _allocations,
        address _depositor
    ) {
        require(
            partners.length == allocations.length,
            "Partners and allocations must have same length"
        );

        nativeToken = _nativeToken;
        fundingToken = _fundingToken;
        exchangeRate = _exchangeRate;
        fundingPeriod = _fundingPeriod;
        timeUntilCliff = _timeUntilCliff;
        vestingPeriod = _vestingPeriod;
        partners = _partners;
        allocations = _allocations;
        depositor = _depositor;

        uint256 sum = 0;
        uint256 length = partners.length;
        for (uint256 i = 0; i < length; i++) {
            partnerFundingAllocations[partners[i]] = allocations[i];
            sum += allocations[i];
        }

        totalAllocated = sum;
    }

    /*///////////////////////////////////////////////////////////////
                              MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyDepositor() {
        if (msg.sender != depositor) revert OnlyDepositor();
        _;
    }

    modifier onlyPartners() {
        if (partnerFundingAllocations[msg.sender] == 0) revert OnlyPartner();
        _;
    }

    /*///////////////////////////////////////////////////////////////
                              FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Used to calculate the base unit for fixed point math
    /// @dev Needed because native and funding tokens could have different decimals
    /// @return Documents the return variables of a contract’s function state variable
    function calculateBaseUnit(uint256 tokenADecimals, uint256 tokenBDecimals)
        private
        pure
        returns (uint256)
    {
        unchecked {
            uint256 z = tokenADecimals - tokenBDecimals;
            if (z > tokenADecimals) {
                z = tokenBDecimals - tokenADecimals;
            }
            return 10**z;
        }
    }

    /// @notice Depositor calls this function to deposit native tokens and begin the funding period. Can only be called once.
    /// @dev Assumes depositor has called approve on the nativeToken with this contract's address and depositAmount.
    function initializeDeposit() external onlyDepositor {
        if (vestingStartDate != 0) revert AlreadyDeposited();
        vestingStartDate = block.timestamp + fundingPeriod;
        uint256 depositAmount = totalAllocated.fdiv(
            exchangeRate,
            calculateBaseUnit(nativeToken.decimals(), fundingToken.decimals())
        );
        nativeToken.transferFrom(depositor, address(this), depositAmount);
        emit Deposited();
    }

    /// @notice Partners call this during the funding period to provide their allocated amount of the fundingToken
    /// @dev Assumes partner has called approve on the fundingToken with this contract's address and their allocation amount.
    function enterPartnership() external onlyPartners {
        if (block.timestamp >= vestingStartDate) revert FundingPeriodFinished();
        if (hasPartnerInvested[msg.sender]) revert PartnerAlreadyFunded();
        uint256 fundingAmount = partnerFundingAllocations[msg.sender];
        totalInvested += fundingAmount;
        partnerBalances[msg.sender] = fundingAmount;
        partnerLastWithdrawalDate[msg.sender] = vestingStartDate;
        hasPartnerInvested[msg.sender] = true;

        fundingToken.transferFrom(msg.sender, address(this), fundingAmount);
        emit PartnershipFormed(msg.sender, fundingAmount);
    }

    function claimFunding() external {
        if (block.timestamp <= vestingStartDate)
            revert FundingPeriodNotFinished();

        uint256 fundingAmount = fundingToken.balanceOf(address(this));
        uint256 uninvestedAmount = totalAllocated - totalInvested;
        if (uninvestedAmount > 0) {
            uint256 unallocatedNativeToken = uninvestedAmount.fdiv(
                exchangeRate,
                calculateBaseUnit(
                    nativeToken.decimals(),
                    fundingToken.decimals()
                )
            );
            nativeToken.transfer(depositor, unallocatedNativeToken);
        }
        fundingToken.transfer(depositor, fundingAmount);
        emit FundingReceived(msg.sender, fundingAmount);
    }

    function getVestedTokens(address _partner) public view returns (uint256) {
        require(hasPartnerInvested[_partner], "Account is not a partner.");
        uint256 startingDate = partnerLastWithdrawalDate[_partner];
        require(startingDate != 0, "Funding has not begun.");
        if (block.timestamp < timeUntilCliff + startingDate) return 0;
        uint256 timeVested = block.timestamp - startingDate;
        uint256 lengthOfVesting = timeUntilCliff + vestingPeriod;
        uint256 pctVested = timeVested.fdiv(lengthOfVesting, 1e18);
        return partnerFundingAllocations[_partner].fmul(pctVested, 1e18);
    }

    function withdrawalVestedTokens() external onlyPartners {
        require(vestingStartDate != 0, "Funding has not begun.");
        require(
            block.timestamp > timeUntilCliff + vestingStartDate,
            "Cliff has not been met"
        );
        if (
            block.timestamp > vestingStartDate + timeUntilCliff + vestingPeriod
        ) {
            uint256 remainingBalance = partnerBalances[msg.sender];
            partnerLastWithdrawalDate[msg.sender] = block.timestamp;
            partnerBalances[msg.sender] = 0;
            nativeToken.transfer(msg.sender, remainingBalance);
        } else {
            uint256 amountVested = getVestedTokens(msg.sender);
            partnerBalances[msg.sender] -= amountVested;
            partnerLastWithdrawalDate[msg.sender] = block.timestamp;
            nativeToken.transfer(msg.sender, amountVested);
        }
    }
}
