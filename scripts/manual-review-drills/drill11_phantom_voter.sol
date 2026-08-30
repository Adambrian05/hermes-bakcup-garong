// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * DRILL 11: THE PHANTOM VOTER
 * Difficulty: HARD+
 * Focus: Access control bypass, reentrancy, governance manipulation
 * 
 * THIS DRILL HAS A REAL BUG. Actually TWO.
 * 
 * RULES:
 * - No tools.
 * - Bug #1: Governance manipulation (steal voting power)
 * - Bug #2: Fund extraction (drain treasury)
 * - They COMPOSE into a single attack.
 * - Show exact tx sequence + numbers.
 */

// ============================================================
// CONTRACT 1: StakingToken (veToken-like staking)
// ============================================================
contract StakingToken {
    string public name = "Staked GOV";
    uint256 public totalStaked;
    
    mapping(address => uint256) public balanceOf;
    mapping(address => uint256) public stakedAmount;
    mapping(address => uint256) public stakeTimestamp;
    
    // Voting power = staked * time_weight
    // time_weight: 0-100% based on how long staked (max at 30 days)
    uint256 public constant MAX_LOCK = 30 days;
    
    function stake(uint256 amount) external {
        require(amount > 0, "zero");
        // In real code: IERC20(govToken).transferFrom(msg.sender, address(this), amount);
        
        // If already staked, claim pending rewards first (implicit)
        if (stakedAmount[msg.sender] > 0) {
            _claimRewards(msg.sender);
        }
        
        stakedAmount[msg.sender] += amount;
        balanceOf[msg.sender] += amount;
        totalStaked += amount;
        stakeTimestamp[msg.sender] = block.timestamp; // ← LOOK AT THIS
    }
    
    function unstake(uint256 amount) external {
        require(amount > 0 && amount <= stakedAmount[msg.sender], "bad");
        
        _claimRewards(msg.sender);
        
        stakedAmount[msg.sender] -= amount;
        balanceOf[msg.sender] -= amount;
        totalStaked -= amount;
        
        // In real code: IERC20(govToken).transfer(msg.sender, amount);
    }
    
    function getVotingPower(address user) public view returns (uint256) {
        if (stakedAmount[user] == 0) return 0;
        
        uint256 elapsed = block.timestamp - stakeTimestamp[user];
        uint256 timeWeight = elapsed >= MAX_LOCK ? 1e18 : elapsed * 1e18 / MAX_LOCK;
        
        return stakedAmount[user] * timeWeight / 1e18;
    }
    
    function getTotalVotingPower() external view returns (uint256) {
        // Simplified: sum of all voting powers
        // In real code this would iterate or use a global accumulator
        return totalStaked; // ← AND THIS
    }
    
    // Internal reward logic (simplified)
    uint256 public rewardPerToken;
    mapping(address => uint256) public rewardCheckpoint;
    mapping(address => uint256) public pendingRewards;
    
    function _claimRewards(address user) internal {
        uint256 earned = stakedAmount[user] * (rewardPerToken - rewardCheckpoint[user]) / 1e18;
        pendingRewards[user] += earned;
        rewardCheckpoint[user] = rewardPerToken;
        // In real code: transfer rewards
    }
    
    function claimRewards() external {
        _claimRewards(msg.sender);
        uint256 rewards = pendingRewards[msg.sender];
        pendingRewards[msg.sender] = 0;
        // In real code: IERC20(rewardToken).transfer(msg.sender, rewards);
    }
}

// ============================================================
// CONTRACT 2: Governance (proposal + voting)
// ============================================================
contract Governance {
    StakingToken public immutable staking;
    
    struct Proposal {
        address proposer;
        string description;
        uint256 forVotes;
        uint256 againstVotes;
        uint256 startTime;
        uint256 endTime;
        bool executed;
        address target;      // contract to call if passed
        bytes callData;      // data to call
    }
    
    mapping(uint256 => Proposal) public proposals;
    mapping(uint256 => mapping(address => bool)) public hasVoted;
    uint256 public proposalCount;
    
    uint256 public constant VOTING_PERIOD = 3 days;
    uint256 public constant PROPOSAL_THRESHOLD = 100e18; // need 100 voting power to propose
    uint256 public constant QUORUM = 1000e18; // need 1000 total votes
    
    constructor(address _staking) {
        staking = StakingToken(_staking);
    }
    
    function propose(address target, bytes calldata callData, string calldata desc) external returns (uint256) {
        uint256 votingPower = staking.getVotingPower(msg.sender);
        require(votingPower >= PROPOSAL_THRESHOLD, "below threshold");
        
        uint256 id = ++proposalCount;
        proposals[id] = Proposal({
            proposer: msg.sender,
            description: desc,
            forVotes: 0,
            againstVotes: 0,
            startTime: block.timestamp,
            endTime: block.timestamp + VOTING_PERIOD,
            executed: false,
            target: target,
            callData: callData
        });
        
        return id;
    }
    
    function vote(uint256 proposalId, bool support) external {
        Proposal storage p = proposals[proposalId];
        require(block.timestamp >= p.startTime && block.timestamp < p.endTime, "voting closed");
        require(!hasVoted[proposalId][msg.sender], "already voted");
        
        uint256 votingPower = staking.getVotingPower(msg.sender);
        require(votingPower > 0, "no voting power");
        
        hasVoted[proposalId][msg.sender] = true;
        
        if (support) {
            p.forVotes += votingPower;
        } else {
            p.againstVotes += votingPower;
        }
    }
    
    // Delegate vote to another address
    function delegateVote(uint256 proposalId, address delegate) external {
        Proposal storage p = proposals[proposalId];
        require(block.timestamp >= p.startTime && block.timestamp < p.endTime, "voting closed");
        require(!hasVoted[proposalId][msg.sender], "already voted");
        require(!hasVoted[proposalId][delegate], "delegate already voted");
        
        uint256 votingPower = staking.getVotingPower(msg.sender);
        require(votingPower > 0, "no voting power");
        
        hasVoted[proposalId][msg.sender] = true;
        hasVoted[proposalId][delegate] = true; // ← LOOK AT THIS
        
        p.forVotes += votingPower;
    }
    
    function execute(uint256 proposalId) external {
        Proposal storage p = proposals[proposalId];
        require(block.timestamp >= p.endTime, "voting not ended");
        require(!p.executed, "already executed");
        require(p.forVotes > p.againstVotes, "proposal rejected");
        require(p.forVotes >= QUORUM, "quorum not met");
        
        p.executed = true;
        
        // Execute the proposal
        (bool success,) = p.target.call(p.callData);
        require(success, "execution failed");
    }
}

// ============================================================
// CONTRACT 3: Treasury (holds funds, controlled by governance)
// ============================================================
contract Treasury {
    address public governance;
    uint256 public totalFunds;
    
    mapping(address => uint256) public allocations;
    mapping(address => bool) public claimed;
    
    constructor(address _governance) {
        governance = _governance;
    }
    
    // Receive funds
    receive() external payable {
        totalFunds += msg.value;
    }
    
    // Governance can allocate funds to addresses
    function allocate(address recipient, uint256 amount) external {
        require(msg.sender == governance, "not governance");
        require(amount <= totalFunds, "insufficient funds");
        
        allocations[recipient] += amount;
        totalFunds -= amount;
    }
    
    // Recipient claims allocated funds
    function claim() external {
        uint256 amount = allocations[msg.sender];
        require(amount > 0, "nothing to claim");
        require(!claimed[msg.sender], "already claimed");
        
        claimed[msg.sender] = true;
        allocations[msg.sender] = 0;
        
        (bool success,) = msg.sender.call{value: amount}("");
        require(success, "transfer failed");
    }
    
    // Emergency: governance can reclaim unclaimed allocations
    function reclaim(address recipient) external {
        require(msg.sender == governance, "not governance");
        require(!claimed[recipient], "already claimed");
        
        uint256 amount = allocations[recipient];
        allocations[recipient] = 0;
        totalFunds += amount;
    }
    
    // Batch execute (called by governance proposal)
    function batchAllocate(address[] calldata recipients, uint256[] calldata amounts) external {
        require(msg.sender == governance, "not governance");
        require(recipients.length == amounts.length, "length mismatch");
        
        for (uint256 i = 0; i < recipients.length; i++) {
            require(amounts[i] <= totalFunds, "insufficient");
            allocations[recipients[i]] += amounts[i];
            totalFunds -= amounts[i];
        }
    }
}

/**
 * TWO BUGS. THEY COMPOSE.
 * 
 * BUG #1 HINTS (Governance manipulation):
 * - Look at stakeTimestamp. What happens when you stake AGAIN?
 * - Look at delegateVote(). What does hasVoted[delegate] = true do?
 * - Can you vote with MORE power than you should have?
 * - Can you vote MULTIPLE times with the same stake?
 * 
 * BUG #2 HINTS (Fund extraction):
 * - Look at Treasury.claim(). What does the external call enable?
 * - Look at the order: claimed = true BEFORE the call. Safe?
 * - What if claim() is called from a CONTRACT with fallback?
 * - Can you claim, get re-entered, and claim AGAIN?
 *   (Wait... claimed is set before the call. So reentrancy on claim is blocked.)
 * - Then look ELSEWHERE. What about allocate() + reclaim()?
 * - What if governance executes a proposal that calls batchAllocate()
 *   to the attacker, then the attacker claims, then...?
 * 
 * COMPOSITION HINT:
 * - Use Bug #1 to pass a malicious proposal
 * - The proposal calls Treasury to extract funds
 * - But HOW do you get voting power without waiting 30 days?
 * 
 * ATTACK SCENARIO:
 * - Treasury has 10,000 ETH
 * - Attacker starts with 100 GOV tokens
 * - Show how attacker drains the treasury
 * - Exact tx sequence, exact numbers
 */
