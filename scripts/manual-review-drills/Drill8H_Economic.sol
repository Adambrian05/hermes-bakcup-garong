// SPDX-License-Identifier: MIT
// DRILL 8H PoC — Economic Methodology
// Bug exists but not economical → not a real bug
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

contract EconomicalVault {
    receive() external payable {}
    

    mapping(address => uint256) public balances;
    mapping(address => uint256) public borrowed;
    uint256 public totalBalance;
    uint256 public rewardPool;

    // BUG 8H-1: rounding error in reward distribution
    // Each user gets truncated reward → 1 wei dust accumulates
    function claimRewards() external {
        uint256 userShare = (balances[msg.sender] * 1e18) / totalBalance;
        uint256 reward = (userShare * rewardPool) / 1e18;
        rewardPool -= reward;
        // rewards not paid
        // Dust: 1 wei per user goes nowhere
    }

    // BUG 8H-2: rounding favors protocol over user
    // If rewardPool = 99 wei, user with 1 wei share gets 0
    // Total dust grows over time
    function tinyDeposit() external payable {
        // Accepts 1 wei deposits but no rewards ever paid out
    }

    // ECONOMIC ANALYSIS:
    // Bug exists: rounding accumulates ~1 wei per user per claim
    // Profit threshold: need 1000+ users to get ~$0.001 profit
    // Cost to attack: gas for 1000+ claims = ~$1+
    // Conclusion: NOT ECONOMICAL → not a real bug to report

    // Compare to BUG 8H-3: ACTUAL economic bug
    // BUG 8H-3: flash-loan withdraw attack
    // Deposit 0, borrow max, withdraw collateral → drain
    // Profit: significant ($1K+ easily)
    // This IS a real bug

    function deposit() external payable {
        balances[msg.sender] += msg.value;
        totalBalance += msg.value;
    }

    function borrow(uint256 amount) external {
        // BUG 8H-3: No collateral check
        borrowed[msg.sender] += amount;
        balances[msg.sender] += amount;
        totalBalance += amount;
        payable(msg.sender).send(amount);
    }

    function repay(uint256 amount) external {
        borrowed[msg.sender] -= amount;
        balances[msg.sender] -= amount;
        totalBalance -= amount;
    }
}
