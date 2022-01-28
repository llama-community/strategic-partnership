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
error FundingNotBegun();
error VestingCliffNotMet();
error AllocationCannotBeZero();

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

    /// @notice Remaining balance in native token
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
        require(partners.length == allocations.length, "Partners and allocations must have same length");

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
            if (allocations[i] == 0) revert AllocationCannotBeZero();
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
                           HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function convertFundingToNativeToken(uint256 fundingAmount) private view returns (uint256) {
        return fundingAmount.fdiv(exchangeRate, calculateBaseUnit(nativeToken.decimals(), fundingToken.decimals()));
    }

    /// @notice Used to calculate the base unit for fixed point math
    /// @dev Needed because native and funding tokens could have different decimals
    /// @return Documents the return variables of a contract’s function state variable
    function calculateBaseUnit(uint256 tokenADecimals, uint256 tokenBDecimals) private pure returns (uint256) {
        unchecked {
            uint256 z = tokenADecimals - tokenBDecimals;
            if (z > tokenADecimals) {
                z = tokenBDecimals - tokenADecimals;
            }
            return 10**z;
        }
    }

    /*///////////////////////////////////////////////////////////////
                              FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Depositor calls this function to deposit native tokens and begin the funding period. Can only be called once.
    /// @dev Assumes depositor has called approve on the nativeToken with this contract's address and depositAmount.
    function initializeDeposit() external onlyDepositor {
        if (vestingStartDate != 0) revert AlreadyDeposited();
        vestingStartDate = block.timestamp + fundingPeriod;
        uint256 depositAmount = convertFundingToNativeToken(totalAllocated);
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
        partnerBalances[msg.sender] = convertFundingToNativeToken(fundingAmount);
        partnerLastWithdrawalDate[msg.sender] = vestingStartDate;
        hasPartnerInvested[msg.sender] = true;

        fundingToken.transferFrom(msg.sender, address(this), fundingAmount);
        emit PartnershipFormed(msg.sender, fundingAmount);
    }

    function claimFunding() external {
        if (block.timestamp <= vestingStartDate) revert FundingPeriodNotFinished();

        uint256 fundingAmount = fundingToken.balanceOf(address(this));
        uint256 uninvestedAmount = totalAllocated - totalInvested;
        if (uninvestedAmount > 0) {
            uint256 unallocatedNativeToken = convertFundingToNativeToken(uninvestedAmount);
            nativeToken.transfer(depositor, unallocatedNativeToken);
        }
        fundingToken.transfer(depositor, fundingAmount);
        emit FundingReceived(depositor, fundingAmount);
    }

    function getClaimableTokens(address _partner) public view returns (uint256) {
        if (partnerFundingAllocations[_partner] == 0) revert OnlyPartner();
        uint256 startingDate = partnerLastWithdrawalDate[_partner];
        if (startingDate == 0 || block.timestamp < startingDate + timeUntilCliff) {
            return 0;
        }

        uint256 fullyVested = vestingStartDate + timeUntilCliff + vestingPeriod;
        uint256 vestEnd = fullyVested > block.timestamp ? block.timestamp : fullyVested;

        uint256 timeVested = vestEnd - startingDate;
        uint256 lengthOfVesting = timeUntilCliff + vestingPeriod;

        uint256 pctVested = timeVested.fdiv(lengthOfVesting, 10**nativeToken.decimals());
        uint256 fullyVestedNativeToken = convertFundingToNativeToken(partnerFundingAllocations[_partner]);
        return fullyVestedNativeToken.fmul(pctVested, 1e18);
    }

    function claimTokens() external onlyPartners {
        if (vestingStartDate == 0) revert FundingNotBegun();
        uint256 cliffDate = vestingStartDate + timeUntilCliff;
        if (block.timestamp < cliffDate) revert VestingCliffNotMet();

        uint256 amountClaimable = getClaimableTokens(msg.sender);
        partnerBalances[msg.sender] -= amountClaimable;
        partnerLastWithdrawalDate[msg.sender] = block.timestamp;
        nativeToken.transfer(msg.sender, amountClaimable);
    }
}
