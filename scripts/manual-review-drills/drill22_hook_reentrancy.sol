// SPDX-License-Identifier: MIT
// =============================================================================
// DRILL 22 — Hook Reentrancy — Cross-Contract Callback Chaos
// =============================================================================
pragma solidity ^0.8.20;

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

// Mock token
contract MockERC20 is IERC20 {
    mapping(address => uint256) public override balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external { balanceOf[to] += amount; }
    function transfer(address to, uint256 amount) external override returns (bool) {
        require(balanceOf[msg.sender] >= amount, "insuf");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

// =============================================================================
// MaliciousHook — attacker contract that re-enters on token receive
// =============================================================================
contract MaliciousHook {
    Vault public vault;
    uint256 public reenterCount;
    uint256 public maxReenters;
    bool public attacking;

    constructor(Vault _vault) { vault = _vault; }

    // Re-enters vault.deposit when receiving tokens
    function attack() external {
        attacking = true;
        vault.deposit(100); // triggers withdraw flow
        attacking = false;
    }

    function tokenReceived(address, uint256 amount) external {
        if (attacking && reenterCount < maxReenters) {
            reenterCount++;
            // Re-enter during the callback
            vault.emergencyWithdraw(amount);
        }
    }
}

// =============================================================================
// Vault — main contract with hook callback
// =============================================================================
contract Vault {
    IERC20 public token;
    mapping(address => uint256) public deposited;
    uint256 public totalDeposited;

    address public hook; // Optional hook for notifications

    constructor(address _token) { token = IERC20(_token); }

    function setHook(address _hook) external {
        hook = _hook;
    }

    function deposit(uint256 amount) external {
        require(token.transfer(msg.sender, address(this), amount), "xfer");
        deposited[msg.sender] += amount;
        totalDeposited += amount;
    }

    // BUG 22-A: Reentrancy via external call + state changes AFTER
    // state.deposited[user] is decreased AFTER the transfer
    function emergencyWithdraw(uint256 amount) external {
        require(deposited[msg.sender] >= amount, "insuf");
        // State change AFTER external call - reentrancy possible!
        token.transfer(msg.sender, amount);  // <-- external call
        deposited[msg.sender] -= amount;     // <-- state change after!
        totalDeposited -= amount;
    }

    // BUG 22-B: hook callback with msg.value assumptions
    function notifyHook(uint256 amount) external {
        require(deposited[msg.sender] >= amount, "insuf");
        deposited[msg.sender] -= amount;
        totalDeposited -= amount;

        if (hook != address(0)) {
            // External call BEFORE state finalization
            (bool ok,) = hook.call(abi.encodeWithSignature("tokenReceived(address,uint256)", msg.sender, amount));
            require(ok, "hook fail");

            // BUG: state could be re-modified during hook callback
            // and we don't re-check deposited[msg.sender]
        }
    }
}

/*
=== HINTS ===
Hint 1: emergencyWithdraw() — does it follow checks-effects-interactions?
        What happens if token.transfer triggers a callback?

Hint 2: notifyHook() — what if the hook re-enters and modifies state?

Hint 3: Look at the order of operations in emergencyWithdraw and
        notifyHook — state updates vs external calls.

=== ANSWER KEY ===

BUG 22-A (CRITICAL): Reentrancy via emergencyWithdraw
  emergencyWithdraw() transfers tokens BEFORE updating deposited mapping.
  If token has a callback (e.g., ERC777-style), attacker re-enters and
  withdraws again with the same "deposited" balance still showing funds.
  Result: drain entire vault.

BUG 22-B (HIGH): Reentrancy via hook callback
  notifyHook() calls external hook BEFORE state is finalized.
  Malicious hook can re-enter and drain vault through multiple paths.

BUG 22-C (MEDIUM): Cross-function reentrancy
  emergencyWithdraw + deposit can be combined. After emergencyWithdraw
  sends tokens, re-enter via deposit (which transfers MORE tokens in),
  then withdraw again. State accounting gets confused.
*/
