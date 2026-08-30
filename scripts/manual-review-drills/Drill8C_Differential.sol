// SPDX-License-Identifier: MIT
// DRILL 8C PoC — Differential Methodology
// Compare two "identical" contracts, find the divergence bug
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

// "Reference" implementation — has CHECK
contract SafeLending {
    mapping(address => uint256) public borrowed;

    function borrow(uint256 amount) external {
        require(amount <= 1000 ether, "exceeds limit");
        borrowed[msg.sender] += amount;
    }

    function repay(uint256 amount) external {
        require(borrowed[msg.sender] >= amount, "overpay");
        borrowed[msg.sender] -= amount;
    }
}

// "Fork" implementation — MISSING check
contract UnsafeLending {
    mapping(address => uint256) public borrowed;

    // BUG 8C-1: Missing require for max borrow
    function borrow(uint256 amount) external {
        borrowed[msg.sender] += amount;
    }

    function repay(uint256 amount) external {
        require(borrowed[msg.sender] >= amount, "overpay");
        borrowed[msg.sender] -= amount;
    }
}
