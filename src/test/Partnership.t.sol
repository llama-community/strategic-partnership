// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.11;

import {ERC20} from "@solmate/tokens/ERC20.sol";

import "ds-test/test.sol";
import {console} from "./utils/console.sol";
import "../Partnership.sol";

interface Vm {
    function expectEmit(
        bool,
        bool,
        bool,
        bool
    ) external;

    function startPrank(address) external;

    function stopPrank() external;
}

contract PartnershipTest is DSTest {
    event TokenDeposited();

    ERC20 public constant GTC =
        ERC20(0xDe30da39c46104798bB5aA3fe8B9e0e1F348163F);
    ERC20 public constant USDC =
        ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    address public constant GTC_TIMELOCK =
        0x57a8865cfB1eCEf7253c27da6B4BC3dAEE5Be518;
    uint256 public constant EXCHANGE_RATE = 20;
    uint256 public constant FUNDING_PERIOD = 14 days;
    uint256 public constant CLIFF = 183 days;
    uint256 public constant VEST_PERIOD = 183 days;
    Vm vm = Vm(HEVM_ADDRESS);

    Partnership partnership;

    function setUp() public {
        address[] memory partners = new address[](1);
        partners[0] = 0xab3B229eB4BcFF881275E7EA2F0FD24eeaC8C83a;

        uint256[] memory allocations = new uint256[](1);
        allocations[0] = 1000;

        partnership = new Partnership(
            GTC,
            USDC,
            EXCHANGE_RATE,
            FUNDING_PERIOD,
            CLIFF,
            VEST_PERIOD,
            partners,
            allocations,
            GTC_TIMELOCK
        );

        vm.startPrank(GTC_TIMELOCK);
        GTC.approve(address(this), 20000e18);
        vm.stopPrank();
    }

    function testInitializeDeposit() public {
        vm.expectEmit(false, false, false, false);
        emit TokenDeposited();
        partnership.initializeDeposit();
    }
}
