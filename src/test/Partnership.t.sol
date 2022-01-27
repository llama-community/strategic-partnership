// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.11;

import {FixedPointMathLib} from "@solmate/utils/FixedPointMathLib.sol";
import {ERC20} from "@openzeppelin/token/ERC20/ERC20.sol";
import "ds-test/test.sol";
import "./interfaces/Vm.sol";
import "../Partnership.sol";

contract PartnershipTest is DSTest {
    using FixedPointMathLib for uint256;
    event Deposited();

    Vm vm = Vm(HEVM_ADDRESS);

    ERC20 internal constant GTC =
        ERC20(0xDe30da39c46104798bB5aA3fe8B9e0e1F348163F);
    ERC20 internal constant USDC =
        ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    uint256 internal constant GTC_DECIMALS = 1e18;
    uint256 internal constant USDC_DECIMALS = 1e6;
    address internal constant GTC_TIMELOCK =
        0x57a8865cfB1eCEf7253c27da6B4BC3dAEE5Be518;
    uint256 internal constant EXCHANGE_RATE = 20;
    uint256 internal constant FUNDING_PERIOD = 14 days;
    uint256 internal constant CLIFF = 183 days;
    uint256 internal constant VEST_PERIOD = 183 days;
    address[10] internal partnerAddresses = [
        0x72A53cDBBcc1b9efa39c834A540550e23463AAcB,
        0x7E0188b0312A26ffE64B7e43a7a91d430fB20673,
        0x6BB273bF25220D13C9b46c6eD3a5408A3bA9Bcc6,
        0x0DAFB4114762bDf555d9c6BDa02f4ffEc89964ec,
        0xA522638540dC63AEBe0B6aae348617018967cBf6,
        0xF0b2E1362f2381686575265799C5215eF712162F,
        0xF3bE92B349CEfB671D4A6D4db6d814f9522712d1,
        0x7abE0cE388281d2aCF297Cb089caef3819b13448,
        0x738c59BFbf6e7fcCF359D0D92D61A09e73ebd674,
        0x075e72a5eDf65F0A5f44699c7654C1a76941Ddc8
    ];
    uint256[10] internal partnerAllocations = [
        10_000_000,
        5_000_000,
        2_000_000,
        1_000_000,
        1_000_000,
        300_000,
        250_000,
        250_000,
        100_000,
        100_000
    ];

    Partnership myPartnership;

    function setUp() public {
        address[] memory partners = new address[](10);
        uint256 addressLength = partnerAddresses.length;
        for (uint256 i = 0; i < addressLength; i++) {
            partners[i] = partnerAddresses[i];
        }

        uint256[] memory allocations = new uint256[](10);
        uint256 allocationLength = partnerAllocations.length;
        for (uint256 i = 0; i < allocationLength; i++) {
            allocations[i] = partnerAllocations[i] * USDC_DECIMALS;
        }

        myPartnership = new Partnership(
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
    }

    function testInitializeDeposit() public {
        // Calculate total USDC allocated
        uint256 usdcAmount = 0;
        uint256 length = partnerAllocations.length;
        for (uint256 i = 0; i < length; i++) {
            usdcAmount += partnerAllocations[i];
        }

        // Assert that this was summed correctly in the constructor
        assertEq(usdcAmount * USDC_DECIMALS, myPartnership.totalAllocated());

        // Amount of GTC sold is the USDC amount divided by exchange rate
        uint256 gtcAmount = myPartnership.totalAllocated().fdiv(
            EXCHANGE_RATE,
            1
        );

        // Send tx's on behalf of the GTC treasury
        vm.startPrank(GTC_TIMELOCK);
        GTC.approve(address(myPartnership), gtcAmount);

        vm.expectEmit(false, false, false, false);
        emit Deposited();
        myPartnership.initializeDeposit();

        assertEq(
            block.timestamp + FUNDING_PERIOD,
            myPartnership.vestingStartDate()
        );

        assertEq(gtcAmount, GTC.balanceOf(address(myPartnership)));

        // Tests that the deposit can only be initialized once
        vm.expectRevert(abi.encodeWithSignature("AlreadyDeposited()"));
        myPartnership.initializeDeposit();

        // Stop spoofing as GTC treasury address
        vm.stopPrank();

        // Tests that only the depositor can call this function
        vm.expectRevert(abi.encodeWithSignature("OnlyDepositor()"));
        myPartnership.initializeDeposit();
    }
}
