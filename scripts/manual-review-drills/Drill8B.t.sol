// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "forge-std/Test.sol";
import "../src/Drill8B_BottomUp.sol";

contract Drill8B_Test is Test {
    MysteryVault vault;
    MockToken token;
    address user = address(0xAA);

    function setUp() public {
        token = new MockToken();
        vault = new MysteryVault(address(token));
        token.mint(user, 1000 ether);
        vm.startPrank(user);
        token.approve(address(vault), type(uint256).max);
        vault.deposit(100 ether);
        vm.stopPrank();
    }

    function test_BugB1_SetAdminAnyone() public {
        // Anyone can change admin
        vault.setAdmin(address(0xBAD));
        assertEq(vault.admin(), address(0xBAD));
    }

    function test_BugB2_SetRewardRateAnyone() public {
        // Anyone can set reward rate to 0
        vault.setRewardRate(0);
        assertEq(vault.REWARD_PER_BLOCK(), 0);
    }

    function test_BugB3_RewardsNeverPaid() public {
        // claimRewards computes owed but doesn't transfer
        uint256 balBefore = token.balanceOf(user);
        vm.prank(user);
        vault.claimRewards();
        // User gets nothing
        assertEq(token.balanceOf(user), balBefore);
    }

    function test_BugB4_SkimAnyone() public {
        // skim is callable by anyone — drains contract
        vault.skim(address(0xBAD));
        assertEq(token.balanceOf(address(vault)), 0);
    }
}
