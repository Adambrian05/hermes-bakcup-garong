// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import {StakeToken, RewardToken, StakingPool} from "../src/drill18_broken_harvest.sol";

/**
 * DRILL 18 PoC - THE BROKEN HARVEST
 *
 * PoC #1: Empty-pool reward gap + rate truncation
 * PoC #2: emergencyWithdraw reward loss - MEDIUM
 * PoC #3: Reward extension - HONEST NEGATIVE (designed behavior)
 */
contract Drill18PoC is Test {
    StakeToken stk;
    RewardToken rwd;
    StakingPool pool;

    address admin   = address(0xDAD);
    address alice   = address(0xACE);
    address bob     = address(0xB0B);
    address charlie = address(0xCAB);

    uint256 constant STAKE_AMT = 1000e18;
    uint256 constant REWARD_AMT = 10_000e18;
    uint256 constant DURATION = 100_000; // seconds

    function setUp() public {
        vm.warp(0); // force block.timestamp = 0 for exact math

        stk  = new StakeToken();
        rwd  = new RewardToken();
        pool = new StakingPool(address(stk), address(rwd));

        // Fund users with stake tokens
        stk.mint(alice, STAKE_AMT);
        stk.mint(bob, STAKE_AMT);
        stk.mint(charlie, STAKE_AMT);

        // Fund admin with reward tokens
        rwd.mint(admin, REWARD_AMT * 3);

        // Approvals
        vm.prank(alice);   stk.approve(address(pool), type(uint256).max);
        vm.prank(bob);     stk.approve(address(pool), type(uint256).max);
        vm.prank(charlie); stk.approve(address(pool), type(uint256).max);
        vm.prank(admin);   rwd.approve(address(pool), type(uint256).max);
    }

    // ============================================================
    // PoC #1: Reward gap when pool is empty + rewardRate truncation
    // ============================================================
    function test_PoC1_EmptyPoolRewardGap() public {
        // Admin adds rewards BEFORE anyone stakes
        vm.prank(admin);
        pool.notifyRewardAmount(REWARD_AMT, DURATION);
        // rewardRate = 10_000e18 / 100_000 = 1e17 wei/sec

        // Warp forward 50,000 seconds (50% of period) - NO stakers yet
        vm.warp(50_000);

        // Alice stakes NOW. She MISSES the first 50% of rewards.
        vm.prank(alice);
        pool.stake(STAKE_AMT);

        // Warp remaining 50,000 seconds
        vm.warp(100_000);

        // Alice claims - what does she get?
        vm.prank(alice);
        pool.getReward();
        uint256 aliceGot = rwd.balanceOf(alice);

        // EXPECTED: Alice staked for 50% of time, should get ~50% of total reward
        // BUT: totalStaked during gap was 0 → all gap rewards are PERMANENTLY LOST
        // Alice only earns from t=50k to t=100k, on 1000e18 staked
        uint256 expectedMax = REWARD_AMT / 2; // at most half (if she's the only staker)
        // Actual: she gets ~(1000/1000) * remaining reward = 5000e18
        assertEq(aliceGot, 5_000e18, "BUG #1: gap rewards evaporated - Alice only gets 50%");

        // The other 5000e18 RWD sit in the contract, unassigned to anyone
        uint256 remainingReward = rwd.balanceOf(address(pool));
        assertEq(remainingReward, 5_000e18, "BUG #1: 5000e18 RWD permanently locked - no staker during gap");

        console.log("[PoC #1] Empty-pool reward gap: MEDIUM");
        console.log("  total reward emitted: ", REWARD_AMT);
        console.log("  alice earned:         ", aliceGot, "(50% - should be 50% if she was 50% of time, but gap rewards unrecoverable)");
        console.log("  stuck in contract:    ", remainingReward, "(50% of total - orphaned)");
    }

    function test_PoC1b_RateZero_Truncation() public {
        // Edge case: reward < duration → rewardRate = 0
        vm.prank(admin);
        pool.notifyRewardAmount(100 wei, 10_000 seconds);
        assertEq(pool.rewardRate(), 0, "BUG #1b: rewardRate truncated to ZERO when reward < duration");

        // Warp forward - no rewards accrue
        vm.warp(10_000);

        vm.prank(alice);
        pool.stake(STAKE_AMT);
        vm.warp(20_000);
        vm.prank(alice);
        pool.getReward();
        assertEq(rwd.balanceOf(alice), 0, "BUG #1b: Alice earned ZERO - rewardRate was 0");

        // admin CAN fix by re-notifying with proper params
        vm.prank(admin);
        pool.notifyRewardAmount(REWARD_AMT, DURATION);
        assertGt(pool.rewardRate(), 0, "admin can re-notify - old dust + new rewards included");

        console.log("[PoC #1b] rewardRate integer truncation: LOW");
        console.log("  rewardRate = 100/10000 = 0 (integer division)");
        console.log("  recoverable by admin re-notify");
    }

    // ============================================================
    // PoC #2: emergencyWithdraw silently forfeits user's rewards
    // ============================================================
    function test_PoC2_EmergencyWithdraw_RewardLoss() public {
        // Alice and Bob both stake
        vm.prank(alice);
        pool.stake(STAKE_AMT);
        vm.prank(bob);
        pool.stake(STAKE_AMT);
        // totalStaked = 2000e18

        // Admin adds rewards
        vm.prank(admin);
        pool.notifyRewardAmount(REWARD_AMT, DURATION);

        // Warp full duration - all rewards accrued
        vm.warp(block.timestamp + DURATION);

        // BOB claims normally - gets his 5000e18 (half the pool)
        vm.prank(bob);
        pool.getReward();
        uint256 bobEarned = rwd.balanceOf(bob);
        assertEq(bobEarned, 5_000e18, "Bob gets his fair 50% share");

        // ALICE calls emergencyWithdraw WITHOUT claiming
        uint256 aliceStkBefore = stk.balanceOf(alice);
        vm.prank(alice);
        pool.emergencyWithdraw();

        // Alice gets her stake back...
        assertEq(stk.balanceOf(alice), aliceStkBefore + STAKE_AMT, "Alice got stake back");
        // ...but ZERO rewards
        assertEq(rwd.balanceOf(alice), 0, "BUG #2: Alice forfeited ALL 5000e18 rewards");

        // The 5000e18 RWD that should have been Alice's is NOW STUCK FOREVER
        uint256 orphaned = rwd.balanceOf(address(pool));
        assertEq(orphaned, 5_000e18, "BUG #2: Alice's 5000e18 permanently locked in contract");
        // Alice can NEVER claim them - her balanceOf is 0, earned() returns 0
        vm.prank(alice);
        pool.getReward();
        assertEq(rwd.balanceOf(alice), 0, "BUG #2: Alice can NEVER recover - earned() = 0 after emergencyWithdraw");

        // Bob also can't double-claim - his earned() is 0 because userRewardPerShare = current
        vm.prank(bob);
        pool.getReward();
        assertEq(rwd.balanceOf(bob), bobEarned, "Bob cannot steal Alice's rewards - they're orphaned, not redistributed");

        console.log("[PoC #2] emergencyWithdraw reward loss: MEDIUM");
        console.log("  bob earned:    ", bobEarned);
        console.log("  alice earned:   0 (forfeited)");
        console.log("  orphaned RWD:   ", orphaned, "(permanently locked)");
    }

    // ============================================================
    // PoC #3: Reward extension - HONEST ON THE PATTERN, BUT...
    //         notifyRewardAmount skips reward snapshot → gap LOST
    // ============================================================
    function test_PoC3_RewardExtension_GapLoss() public {
        // Alice stakes
        vm.prank(alice);
        pool.stake(STAKE_AMT);

        // First reward period: 3600e18 over 1 hour (3600 sec)
        vm.prank(admin);
        pool.notifyRewardAmount(3600e18, 3600);
        uint256 rate1 = pool.rewardRate(); // 3600/3600 = 1e18/sec

        // Warp 1800 seconds (Alice's rewards should be accumulating)
        vm.warp(1800);

        // Admin extends: notifyRewardAmount does NOT snapshot rewardPerShareStored first!
        // The 1800 seconds * 1e18/sec = 1800e18 accrued rewards are LOST
        vm.prank(admin);
        pool.notifyRewardAmount(3600e18, 3600);
        uint256 rate2 = pool.rewardRate();
        assertEq(rate2, rate1 * 3 / 2, "extension math: rate = 1.5e18/sec - this part is fine");

        // Warp to end
        vm.warp(5400); // start=0, first half=1800, extended=3600 → end=5400

        vm.prank(alice);
        pool.getReward();
        uint256 aliceGot = rwd.balanceOf(alice);

        // Total reward emitted to contract: 7200e18 (3600 + 3600)
        // Alice SHOULD get 7200e18 (she's the only staker all along)
        // BUT: notifyRewardAmount overwrites lastUpdateTime WITHOUT snapshotting
        //      the rewardPerShare for t=0 to t=1800.
        //      So Alice only earns from t=1800 to t=5400 (3600 sec @ 1.5e18)
        //      = 5400e18. The first 1800e18 is PERMANENTLY LOST.
        assertEq(aliceGot, 5400e18, "BUG #3: gap rewards LOST - Alice should get 7200, only gets 5400");

        uint256 lost = 7200e18 - aliceGot;
        assertEq(lost, 1800e18, "BUG #3: 1800e18 vanished - notifyRewardAmount has no rewardPerShare snapshot");

        console.log("[PoC #3] notifyRewardAmount gap loss: MEDIUM");
        console.log("  total emitted to contract: 7200e18");
        console.log("  alice SHOULD receive:      7200e18 (only staker)");
        console.log("  alice ACTUALLY received:    ", aliceGot, "(missing 1800e18)");
        console.log("  => notifyRewardAmount must snapshot rewardPerShare before reset");
    }

    function test_PoC3b_ExtensionPattern_IsFine() public {
        // If Alice claims BEFORE extension, no loss - pattern is fine
        vm.prank(alice);
        pool.stake(STAKE_AMT);

        vm.prank(admin);
        pool.notifyRewardAmount(3600e18, 3600);

        vm.warp(1800);

        // Alice claims BEFORE extension
        vm.prank(alice);
        pool.getReward();
        uint256 firstClaim = rwd.balanceOf(alice);
        assertEq(firstClaim, 1800e18, "Alice claims 1800e18 from first period");

        // NOW extend
        vm.prank(admin);
        pool.notifyRewardAmount(3600e18, 3600);

        vm.warp(5400);
        vm.prank(alice);
        pool.getReward();
        uint256 secondClaim = rwd.balanceOf(alice) - firstClaim;
        assertEq(secondClaim, 5400e18, "Alice claims 5400e18 from extended period");

        uint256 total = rwd.balanceOf(alice);
        assertEq(total, 7200e18, "HONEST: total = 7200e18 - extension pattern works IF users claim first");

        console.log("[PoC #3b] Reward extension pattern: NOT A BUG when users claim promptly");
        console.log("  total earned: ", total, "(= 7200e18, no loss)");
    }
}
