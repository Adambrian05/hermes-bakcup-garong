// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "forge-std/Test.sol";
import "../src/Drill8F_StateMachine.sol";

contract Drill8F_Test is Test {
    StateMachineVault vault;
    MockToken token;
    address user = address(0xAA);
    address admin;

    function setUp() public {
        token = new MockToken();
        vault = new StateMachineVault(address(token));
        admin = vault.admin();  // capture admin from constructor
        token.mint(user, 100 ether);
    }

    function test_BugF1_DepositInPausedState() public {
        // Pause
        vm.prank(admin);
        vault.emergencyPause();
        assertEq(vault.state(), 2);

        // BUG: deposit should fail but doesn't
        vm.startPrank(user);
        token.approve(address(vault), type(uint256).max);
        vault.deposit(50 ether);
        vm.stopPrank();

        assertEq(vault.balances(user), 50 ether, "deposited in paused state!");
    }

    function test_BugF2_WithdrawInEmergency() public {
        vm.startPrank(user);
        token.approve(address(vault), type(uint256).max);
        vault.deposit(100 ether);
        vm.stopPrank();

        // Admin closes (emergency state)
        vm.prank(admin);
        vault.emergencyClose();

        // BUG: user can still withdraw
        vm.prank(user);
        vault.withdraw(100 ether);
        assertEq(vault.balances(user), 0, "withdrew in emergency state!");
    }

    function test_BugF3_ResumeAfterClose() public {
        vm.prank(admin);
        vault.emergencyClose();
        assertEq(vault.state(), 4);

        // BUG: resume() works from any state
        vm.prank(admin);
        vault.resume();
        assertEq(vault.state(), 1, "resumed from closed state!");
    }
}
