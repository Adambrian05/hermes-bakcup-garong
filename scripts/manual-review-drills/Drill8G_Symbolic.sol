// SPDX-License-Identifier: MIT
// DRILL 8G PoC — Symbolic Methodology
// Edge cases: amount=0, MAX_UINT, address(0), etc
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

contract EdgeCaseVault {
    receive() external payable {}
    

    mapping(address => uint256) public balances;
    uint256 public totalBalance;

    uint256 public constant MAX_DEPOSIT = 1000 ether;

    // BUG 8G-1: amount=0 deposit still costs gas and may affect accounting
    function deposit() external payable {
        balances[msg.sender] += msg.value;
        totalBalance += msg.value;
    }
    function depositERC(uint256 amount) external {
        require(amount > 0, "zero"); // OK, but check other paths
        require(amount <= MAX_DEPOSIT, "exceeds");
        require(payable(msg.sender).send(amount), "send");
        balances[msg.sender] += amount;
        totalBalance += amount;
    }

    // BUG 8G-2: amount=MAX_UINT causes underflow
    function withdraw(uint256 amount) external {
        require(balances[msg.sender] >= amount, "insuf"); // OK
        balances[msg.sender] -= amount;
        totalBalance -= amount; // underflow if amount > totalBalance
        payable(msg.sender).send(amount);
    }

    // BUG 8G-3: address(0) check missing
    function transferOut(address to, uint256 amount) external {
        // No require(to != address(0))
        payable(to).transfer(amount);
    }

    // BUG 8G-4: division by zero possible
    function shareValue(uint256 totalShares) external view returns (uint256) {
        return address(this).balance / totalShares; // reverts if 0
    }

    // BUG 8G-5: multiplication overflow in unchecked block
    function calculateReward(uint256 rate, uint256 duration) external pure returns (uint256) {
        unchecked {
            return rate * duration; // overflow if both large
        }
    }
}
