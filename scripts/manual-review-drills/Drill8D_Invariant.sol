// SPDX-License-Identifier: MIT
// DRILL 8D PoC — Invariant-First Methodology
// Define invariants, find what breaks them
pragma solidity ^0.8.20;

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address) external view returns (uint256);
    function approve(address, uint256) external returns (bool);
    function transferFrom(address, address, uint256) external returns (bool);
}

contract MockToken is IERC20 {
    mapping(address => uint256) public override balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    function mint(address to, uint256 amount) external { balanceOf[to] += amount; }
    function approve(address spender, uint256 amount) external override returns (bool) { allowance[msg.sender][spender] = amount; return true; }
    function transfer(address to, uint256 amount) external override returns (bool) { balanceOf[msg.sender] -= amount; balanceOf[to] += amount; return true; }
    function transferFrom(address from, address to, uint256 amount) external override returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount; balanceOf[to] += amount; return true;
    }
}

/* INVARIANTS for a lending protocol:
   1. sum(collateral) >= sum(borrows)  [solvency]
   2. contract token balance >= totalDeposited  [backing]
   3. user.deposited == user's deposits - withdrawals  [accounting]
*/

contract LendingWithBrokenInvariant {
    IERC20 public token;

    mapping(address => uint256) public deposited;
    mapping(address => uint256) public borrowed;
    uint256 public totalDeposited;
    uint256 public totalBorrowed;

    constructor(address _token) { token = IERC20(_token); }

    function deposit(uint256 amount) external {
        require(token.transferFrom(msg.sender, address(this), amount), "xfer");
        deposited[msg.sender] += amount;
        totalDeposited += amount;
    }

    function borrow(uint256 amount) external {
        require(deposited[msg.sender] > 0, "no collateral");
        // BUG 8D-1: NO collateral check vs borrow amount
        // Invariant broken: borrowed > deposited[user]
        borrowed[msg.sender] += amount;
        totalBorrowed += amount;
        token.transfer(msg.sender, amount);
    }

    function withdraw(uint256 amount) external {
        // BUG 8D-2: No check that remaining collateral covers debt
        require(deposited[msg.sender] >= amount, "insuf");
        deposited[msg.sender] -= amount;
        totalDeposited -= amount;
        token.transfer(msg.sender, amount);
        // After this: borrowed > collateral → user underwater
    }

    // INVARIANT CHECK (for demo only):
    function invariant_solvent(address user) external view returns (bool) {
        return borrowed[user] <= deposited[user] * 2; // 50% LTV
    }
}
