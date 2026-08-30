// SPDX-License-Identifier: MIT
// DRILL 8B PoC — Bottom-Up Methodology
// Undocumented contract — bugs found by reading code, not docs
pragma solidity ^0.8.20;

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

contract MockToken is IERC20 {
    mapping(address => uint256) public override balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    function mint(address to, uint256 amount) external { balanceOf[to] += amount; }
    function approve(address spender, uint256 amount) external override returns (bool) { allowance[msg.sender][spender] = amount; return true; }
    function transfer(address to, uint256 amount) external override returns (bool) {
        require(balanceOf[msg.sender] >= amount, "insuf");
        balanceOf[msg.sender] -= amount; balanceOf[to] += amount; return true;
    }
    function transferFrom(address from, address to, uint256 amount) external override returns (bool) {
        require(allowance[from][msg.sender] >= amount, "allowance");
        require(balanceOf[from] >= amount, "insuf");
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount; balanceOf[to] += amount; return true;
    }
}

/// @notice NO DOCS — auditor must read code
contract MysteryVault {
    IERC20 public token;

    mapping(address => uint256) public deposited;
    mapping(address => uint256) public rewardDebt;
    mapping(address => uint256) public lastUpdate;

    uint256 public accRewardPerShare;
    uint256 public totalDeposited;

    uint256 public REWARD_PER_BLOCK = 100;
    uint256 public lastRewardBlock;

    address public admin;

    constructor(address _token) { token = IERC20(_token); admin = msg.sender; lastRewardBlock = block.number; }

    // BUG 8B-1: No access control — anyone can set admin
    function setAdmin(address _admin) external { admin = _admin; }

    // BUG 8B-2: REWARD_PER_BLOCK can be set to 0 right before users claim
    function setRewardRate(uint256 rate) external { REWARD_PER_BLOCK = rate; }

    function deposit(uint256 amount) external {
        updatePool();
        require(token.transferFrom(msg.sender, address(this), amount), "xfer");
        deposited[msg.sender] += amount;
        totalDeposited += amount;
        rewardDebt[msg.sender] = (deposited[msg.sender] * accRewardPerShare) / 1e18;
    }

    function withdraw(uint256 amount) external {
        updatePool();
        require(deposited[msg.sender] >= amount, "insuf");
        uint256 owed = (deposited[msg.sender] * accRewardPerShare) / 1e18 - rewardDebt[msg.sender];
        deposited[msg.sender] -= amount;
        totalDeposited -= amount;
        rewardDebt[msg.sender] = (deposited[msg.sender] * accRewardPerShare) / 1e18;
        token.transfer(msg.sender, amount);
        // BUG 8B-3: rewards never actually transferred to user
    }

    function claimRewards() external {
        updatePool();
        uint256 owed = (deposited[msg.sender] * accRewardPerShare) / 1e18 - rewardDebt[msg.sender];
        rewardDebt[msg.sender] = (deposited[msg.sender] * accRewardPerShare) / 1e18;
        // BUG 8B-3: owed is computed but no transfer
    }

    function updatePool() public {
        if (block.number <= lastRewardBlock) return;
        uint256 blocks = block.number - lastRewardBlock;
        uint256 reward = blocks * REWARD_PER_BLOCK;
        if (totalDeposited > 0) {
            accRewardPerShare += (reward * 1e18) / totalDeposited;
        }
        lastRewardBlock = block.number;
    }

    // BUG 8B-4: mystery function with no natspec, callable by anyone
    function skim(address to) external {
        require(token.transfer(to, token.balanceOf(address(this))), "xfer");
    }
}
