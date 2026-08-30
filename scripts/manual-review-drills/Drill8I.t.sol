// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "forge-std/Test.sol";
import "../src/Drill8I_FuzzDriven.sol";

contract Drill8I_Test is Test {
    ToolFlaggedContract target;
    MockToken token;
    address user = address(0xAA);

    function setUp() public {
        token = new MockToken();
        target = new ToolFlaggedContract(address(token));
        token.mint(user, 1000 ether);
    }

    function test_ToolFlagged_SetHookAnyone() public {
        // Slither would flag: missing access control
        target.setHook(address(0xBAD));
        assertEq(target.hook(), address(0xBAD));
    }

    function test_ToolFlagged_SetAdminZero() public {
        // Slither would flag: missing zero-address check
        target.setAdmin(address(0));
        assertEq(target.admin(), address(0), "admin is zero - locks contract");
    }

    function test_ToolFlagged_EmergencyWithdraw() public {
        // Slither would flag: arbitrary-send
        token.mint(address(target), 100 ether);
        target.emergencyWithdraw(address(0xBAD));
        // Token gone
    }
}
