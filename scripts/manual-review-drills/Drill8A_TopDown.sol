// SPDX-License-Identifier: MIT
// DRILL 8A PoC — Top-Down Methodology
// Spec says X, code does Y — find the mismatch
pragma solidity ^0.8.20;

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address) external view returns (uint256);
}

contract MockToken is IERC20 {
    mapping(address => uint256) public override balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    function mint(address to, uint256 amount) external { balanceOf[to] += amount; }
    function approve(address spender, uint256 amount) external returns (bool) { allowance[msg.sender][spender] = amount; return true; }
    function transfer(address to, uint256 amount) external override returns (bool) {
        require(balanceOf[msg.sender] >= amount, "insuf");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

/// @title StakingPool
/// @notice Per docs: "Users can deposit tokens and earn 10% APY. Withdrawals
///                  are instant and return principal + rewards."
/// @dev BUG 8A-1: rewards are calculated but never minted/transferred
contract StakingPool {
    IERC20 public immutable stakingToken;
    IERC20 public immutable rewardToken;

    uint256 public constant REWARD_RATE_BPS = 1000; // 10% per period

    mapping(address => uint256) public staked;
    mapping(address => uint256) public depositTime;
    mapping(address => uint256) public claimedRewards;

    uint256 public totalStaked;

    constructor(address _staking, address _reward) {
        stakingToken = IERC20(_staking);
        rewardToken = IERC20(_reward);
        _owner = msg.sender;
    }

    function deposit(uint256 amount) external {
        // drill: just update accounting
        staked[msg.sender] += amount;
        depositTime[msg.sender] = block.timestamp;
        totalStaked += amount;
    }

    /// @notice Doc says: "Returns principal + all earned rewards"
    /// @dev BUG 8A-1: rewards calculated but contract has no rewardToken
    ///      balance. User's claimRewards() will revert on transfer.
    function withdraw(uint256 amount) external {
        require(staked[msg.sender] >= amount, "insuf");
        staked[msg.sender] -= amount;
        totalStaked -= amount;
        stakingToken.transfer(msg.sender, amount);

        // BUG: tries to pay rewards but never accumulates rewardToken
        uint256 rewards = pendingRewards(msg.sender);
        if (rewards > 0) {
            require(rewardToken.transfer(msg.sender, rewards), "rewards fail");
        }
    }

    /// @dev BUG 8A-1: this is calculated but never incremented/minted
    function pendingRewards(address user) public view returns (uint256) {
        uint256 duration = block.timestamp - depositTime[user];
        return (staked[user] * REWARD_RATE_BPS * duration) / (10000 * 365 days);
    }

    /// @notice Doc doesn't mention, code has this — admin can withdraw all
    /// @dev BUG 8A-2: admin rug pull not in spec
    function emergencyWithdrawAll(address to) external {
        require(msg.sender == _owner, "not owner");
        stakingToken.transfer(to, stakingToken.balanceOf(address(this)));
    }

    address private _owner;
}
