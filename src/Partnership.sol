// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.11;

import {ERC20} from "@solmate/tokens/ERC20.sol";

/// @title Strategic Partnership
/// @author Austin Green
/// @notice Factory for creating and managing Strategic Partnerships.
contract Partnership {
    /*///////////////////////////////////////////////////////////////
                               EVENTS
    //////////////////////////////////////////////////////////////*/

    event TokenDeposited();

    /*///////////////////////////////////////////////////////////////
                               IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice The token that is being exchanged.
    ERC20 public immutable nativeToken;

    /// @notice The token partners exchange for the nativeToken.
    ERC20 public immutable fundingToken;

    /// @notice The time period in which partners can invest.
    uint256 public immutable fundingPeriod;

    /// @notice The timestamp when vesting begins.
    uint256 public immutable vestingCliff;

    /// @notice The duration of vesting.
    uint256 public immutable vestingPeriod;

    /// @notice Number of fundingTokens required for 1 nativeToken
    uint256 public immutable exchangeRate;

    /// @notice DAO selling the token
    address public immutable depositor;

    /// @notice Amount allocated per partner
    address[] public partners;

    /// @notice Amount allocated per partner
    uint256[] public amounts;

    /// @notice Amount allocated per partner
    mapping(address => uint256) public partnerAmounts;

    /// @notice Has the deposit already happened
    bool public hasDeposited;

    /// @notice When funding ends
    uint256 public fundingDeadline;

    /*///////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Creates a new Strategic Partnership contract.
    /// @param _nativeToken The token that is being exchanged.
    /// @param _fundingToken The token partners exchange for the nativeToken.
    /// @param _fundingPeriod The time period in which partners can invest.
    /// @param _vestingCliff The timestamp when vesting begins.
    /// @param _vestingPeriod The duration of vesting.
    /// @param _partners Addresses that can participate.
    /// @param _amounts Max amount that partners can invest.
    /// @param _exchangeRate Number of fundingTokens required for 1 nativeToken
    /// @dev Partners and amounts are matched by index
    constructor(
        ERC20 _nativeToken,
        ERC20 _fundingToken,
        uint256 _fundingPeriod,
        uint256 _vestingCliff,
        uint256 _vestingPeriod,
        address[] memory _partners,
        uint256[] memory _amounts,
        uint256 _exchangeRate
    ) {
        require(
            partners.length == amounts.length,
            "Partners and amounts must have same length"
        );

        nativeToken = _nativeToken;
        fundingToken = _fundingToken;
        fundingPeriod = _fundingPeriod;
        vestingCliff = _vestingCliff;
        vestingPeriod = _vestingPeriod;
        partners = _partners;
        amounts = _amounts;
        exchangeRate = _exchangeRate;
        depositor = msg.sender;

        for (uint256 i = 0; i < partners.length; i++) {
            partnerAmounts[partners[i]] = amounts[i];
        }
    }

    function depositNativeToken() external {
        require(msg.sender == depositor, "Only depositor can deposit");
        require(!hasDeposited, "Deposit already complete");

        hasDeposited = true;
        fundingDeadline = block.timestamp + fundingPeriod;
        // nativeToken.transferFrom(depositor, address(this), _amount);

        emit TokenDeposited();
    }
}
