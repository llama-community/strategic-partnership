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
    event PartnershipFormed(address indexed investor, uint256 amount);
    event FundingReceived(address indexed depositor, uint256 fundingAmount);

    Vm vm = Vm(HEVM_ADDRESS);

    ERC20 internal constant GTC = ERC20(0xDe30da39c46104798bB5aA3fe8B9e0e1F348163F);
    ERC20 internal constant USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    uint256 internal constant USDC_DECIMALS = 1e6;
    uint256 internal constant BASE_UNIT = 1e12;
    address internal constant GTC_TIMELOCK = 0x57a8865cfB1eCEf7253c27da6B4BC3dAEE5Be518;
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
        0x2Ae9781bc224caE1135bC9CC34B3664F16359036,
        0x075e72a5eDf65F0A5f44699c7654C1a76941Ddc8
    ];
    uint256[10] internal partnerAllocations = [
        10_000_000 * USDC_DECIMALS,
        5_000_000 * USDC_DECIMALS,
        2_000_000 * USDC_DECIMALS,
        1_000_000 * USDC_DECIMALS,
        1_000_000 * USDC_DECIMALS,
        300_000 * USDC_DECIMALS,
        250_000 * USDC_DECIMALS,
        250_000 * USDC_DECIMALS,
        100_000 * USDC_DECIMALS,
        100_000 * USDC_DECIMALS
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
            allocations[i] = partnerAllocations[i];
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

    // Helper function that approves and deposits GTC
    function approveAndInitialize() internal returns (uint256 gtcAmount) {
        vm.startPrank(GTC_TIMELOCK);
        // Amount of GTC sold is the USDC amount divided by exchange rate
        gtcAmount = myPartnership.totalAllocated();

        // Send tx's on behalf of the GTC treasury
        GTC.approve(address(myPartnership), gtcAmount);

        // Call initializeDeposit as depositor and ensure Deposted event emitted
        vm.expectEmit(false, false, false, false);
        emit Deposited();
        myPartnership.initializeDeposit();
        vm.stopPrank();
    }

    function convertFundingToNativeToken(uint256 fundingAmount) private pure returns (uint256) {
        return fundingAmount.fdiv(EXCHANGE_RATE, BASE_UNIT);
    }

    function testConstructor() public {
        // Calculate total USDC allocated
        uint256 usdcAmount = 0;
        uint256 length = partnerAllocations.length;
        for (uint256 i = 0; i < length; i++) {
            usdcAmount += partnerAllocations[i];
        }

        // Assert that this was summed correctly in the constructor
        assertEq(convertFundingToNativeToken(usdcAmount), myPartnership.totalAllocated());

        // Assert that this was assigned correctly in the constructor
        assertEq(partnerAllocations[4], myPartnership.partnerFundingAllocations(partnerAddresses[4]));
    }

    function testInitializeDeposit() public {
        // Approve and intialize as the GTC treasury
        uint256 gtcAmount = approveAndInitialize();

        // Assert funding deadline/vesting start date is calculated correctly
        assertEq(block.timestamp + FUNDING_PERIOD, myPartnership.vestingStartDate());

        // Assert contract has correct GTC amount
        assertEq(gtcAmount, GTC.balanceOf(address(myPartnership)));

        // Tests that the deposit can only be initialized once
        vm.startPrank(GTC_TIMELOCK);
        vm.expectRevert(abi.encodeWithSignature("AlreadyDeposited()"));
        myPartnership.initializeDeposit();
        // Stop spoofing as GTC treasury address
        vm.stopPrank();

        // Tests that only the depositor can call this function
        vm.expectRevert(abi.encodeWithSignature("OnlyDepositor()"));
        myPartnership.initializeDeposit();
    }

    function testEnterPartnership() public {
        // Approve and intialize as the GTC treasury
        approveAndInitialize();

        // Only partners can enter partnership
        vm.expectRevert(abi.encodeWithSignature("OnlyPartner()"));
        myPartnership.enterPartnership();

        // Three partners enter partnership
        for (uint256 i = 0; i < 3; i++) {
            address partner = partnerAddresses[i];
            uint256 allocation = partnerAllocations[i];

            vm.startPrank(partner);
            USDC.approve(address(myPartnership), allocation);

            vm.expectEmit(true, true, false, false);
            emit PartnershipFormed(partner, allocation);
            myPartnership.enterPartnership();

            assertEq(convertFundingToNativeToken(allocation), myPartnership.partnerBalances(partner));
            assertEq(myPartnership.vestingStartDate(), myPartnership.partnerLastWithdrawalDate(partner));
            vm.stopPrank();
        }

        // Contract has correct USDC balance
        uint256 usdcSum = partnerAllocations[0] + partnerAllocations[1] + partnerAllocations[2];
        assertEq(usdcSum, myPartnership.totalInvested());

        // Assert contract has correct USDC amount
        assertEq(usdcSum, USDC.balanceOf(address(myPartnership)));

        // Partners can only fund once
        vm.prank(partnerAddresses[0]);
        vm.expectRevert(abi.encodeWithSignature("PartnerAlreadyFunded()"));
        myPartnership.enterPartnership();

        // Fast forward a week
        vm.warp(block.timestamp + 7 days);

        // Next six partners enter partnership
        for (uint256 i = 3; i < 9; i++) {
            address partner = partnerAddresses[i];
            uint256 allocation = partnerAllocations[i];

            vm.startPrank(partner);
            USDC.approve(address(myPartnership), allocation);

            vm.expectEmit(true, true, false, false);
            emit PartnershipFormed(partner, allocation);
            myPartnership.enterPartnership();

            assertEq(convertFundingToNativeToken(allocation), myPartnership.partnerBalances(partner));
            assertEq(myPartnership.vestingStartDate(), myPartnership.partnerLastWithdrawalDate(partner));
            vm.stopPrank();
        }

        // Fast forward past the funding period
        vm.warp(block.timestamp + 10 days);

        vm.prank(partnerAddresses[9]);
        vm.expectRevert(abi.encodeWithSignature("FundingPeriodFinished()"));
        myPartnership.enterPartnership();
    }

    function testClaimFunding(uint256 x) public {
        // Fuzz test conditions when 0-10 partners enter
        uint256 funders = x % partnerAddresses.length;

        uint256 startingBalance = GTC.balanceOf(GTC_TIMELOCK);

        // Approve and intialize as the GTC treasury
        uint256 gtcAmount = approveAndInitialize();

        // Partners enter partnership
        uint256 amountFunded = 0;
        for (uint256 i = 0; i < funders; i++) {
            vm.startPrank(partnerAddresses[i]);
            USDC.approve(address(myPartnership), partnerAllocations[i]);
            myPartnership.enterPartnership();
            vm.stopPrank();

            amountFunded += partnerAllocations[i];
        }

        uint256 notFunded = myPartnership.totalAllocated() - convertFundingToNativeToken(amountFunded);

        // Cannot claim funding before funding period ends
        vm.expectRevert(abi.encodeWithSignature("FundingPeriodNotFinished()"));
        myPartnership.claimFunding();

        // Contract has correct amount of USDC
        assertEq(amountFunded, USDC.balanceOf(address(myPartnership)));

        // Fast forward past the funding period
        vm.warp(block.timestamp + 15 days);

        uint256 expectedUSDCTreasuryBalance = myPartnership.totalInvested();

        vm.expectEmit(true, true, false, false);
        emit FundingReceived(GTC_TIMELOCK, expectedUSDCTreasuryBalance);
        myPartnership.claimFunding();

        uint256 expectedGTCTreasuryBalance = startingBalance - gtcAmount + notFunded;

        // Unfunded GTC and USDC received is sent to GTC treasury
        assertEq(expectedGTCTreasuryBalance, GTC.balanceOf(GTC_TIMELOCK));
        assertEq(expectedUSDCTreasuryBalance, USDC.balanceOf(GTC_TIMELOCK));
    }

    function testGetClaimableTokens() public {
        vm.expectRevert(abi.encodeWithSignature("OnlyPartner()"));
        myPartnership.getClaimableTokens(address(this));

        // Approve and intialize as the GTC treasury
        approveAndInitialize();

        // Funding has not started so no claimable tokens
        assertEq(myPartnership.getClaimableTokens(partnerAddresses[0]), 0);

        for (uint256 i = 0; i < 8; i++) {
            vm.startPrank(partnerAddresses[i]);
            USDC.approve(address(myPartnership), partnerAllocations[i]);
            myPartnership.enterPartnership();
            vm.stopPrank();
        }

        // Past funding period but before cliff
        vm.warp(block.timestamp + 30 days);
        assertEq(myPartnership.getClaimableTokens(partnerAddresses[0]), 0);

        uint256 amtInGTC = partnerAllocations[0].fdiv(EXCHANGE_RATE, BASE_UNIT);
        uint256 halfAmtInGTC = amtInGTC.fdiv(2, 1);

        // Go to half way through
        vm.warp(block.timestamp + 167 days);
        assertEq(myPartnership.getClaimableTokens(partnerAddresses[0]), halfAmtInGTC);

        // Ensure claimable amount is capped
        vm.warp(block.timestamp + 500 days);
        assertEq(myPartnership.getClaimableTokens(partnerAddresses[0]), amtInGTC);
    }

    function testClaimTokens() external {
        // Approve and intialize as the GTC treasury
        approveAndInitialize();

        for (uint256 i = 0; i < 8; i++) {
            vm.startPrank(partnerAddresses[i]);
            USDC.approve(address(myPartnership), partnerAllocations[i]);
            myPartnership.enterPartnership();
            vm.stopPrank();
        }

        // Go to half way through
        vm.warp(block.timestamp + FUNDING_PERIOD + CLIFF);

        vm.prank(partnerAddresses[0]);
        myPartnership.claimTokens();

        assertEq(myPartnership.partnerBalances(partnerAddresses[0]), 250000000000000000000000);
    }
}
