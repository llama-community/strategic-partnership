// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.11;

import {ERC20} from "@solmate/tokens/ERC20.sol";

import "ds-test/test.sol";
import "../Partnership.sol";

interface Vm {
    function expectEmit(
        bool,
        bool,
        bool,
        bool
    ) external;
}

contract PartnershipTest is DSTest {
    Partnership partnership;
    Vm vm = Vm(HEVM_ADDRESS);
    event TokenDeposited();

    function setUp() public {
        address[] memory partners = new address[](1);
        partners[0] = 0xab3B229eB4BcFF881275E7EA2F0FD24eeaC8C83a;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1000;

        partnership = new Partnership(
            ERC20(0xDe30da39c46104798bB5aA3fe8B9e0e1F348163F),
            ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48),
            7 days,
            8 weeks,
            24 weeks,
            partners,
            amounts,
            20
        );
    }

    function testDepositNativeToken() public {
        vm.expectEmit(true, true, false, true);
        emit TokenDeposited();
        partnership.depositNativeToken();
        assertTrue(partnership.hasDeposited());
    }
}
