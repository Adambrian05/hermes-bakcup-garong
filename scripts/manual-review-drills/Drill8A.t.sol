// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "forge-std/Test.sol";
import "../src/Drill8A_TopDown.sol";

contract Drill8A_Test is Test {
    StakingPool pool;
    MockToken staking;
    MockToken reward;

    function setUp() public {
        staking = new MockToken();
        reward = new MockToken();
        pool = new StakingPool(address(staking), address(reward));
        staking.mint(address(pool), 100 ether); // pool has token to give back
        reward.mint(address(pool), 100 ether); // also reward
        staking.mint(address(this), 1000 ether);
        staking.approve(address(pool), type(uint256).max);
        pool.deposit(100 ether);
    }

    function test_BugA1_RewardZero() public {
        // Doc says: "Returns principal + earned rewards"
        // Code: rewards calculated but reward token balance is 0
        // User calls withdraw, gets principal only, NO rewards
        uint256 balBefore = staking.balanceOf(address(this));
        pool.withdraw(50 ether);
        uint256 balAfter = staking.balanceOf(address(this));
        // Got back 50 principal but no rewards (despite doc promise)
        assertEq(balAfter - balBefore, 50 ether, "only principal, no rewards");
    }

    function test_BugA2_AdminRugHidden() public {
        // Doc doesn't mention emergencyWithdrawAll
        // Code: admin can drain all staking tokens
        assertEq(staking.balanceOf(address(pool)), 100 ether);
        pool.emergencyWithdrawAll(address(0xBAD));
        assertEq(staking.balanceOf(address(pool)), 0);
    }
}
