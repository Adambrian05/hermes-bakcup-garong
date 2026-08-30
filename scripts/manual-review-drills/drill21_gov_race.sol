// SPDX-License-Identifier: MIT
// =============================================================================
// DRILL 21 — Governance Timing Window — No Grace Period Execution Race
// =============================================================================
pragma solidity ^0.8.20;

// Simplified mock governance token
contract GovernanceToken {
    string public name = "StarDAO";
    string public symbol = "STAR";
    uint8 public decimals = 18;
    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    mapping(address => uint256) public nonces;

    // Vote tracking
    mapping(address => uint256) public votes;
    mapping(address => uint256) public lastUpdate;
    uint256 public totalVotes;

    // Snapshots
    struct Checkpoint {
        uint256 fromBlock;
        uint256 votes_;
    }
    mapping(address => Checkpoint[]) public checkpoints;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
        _moveVotes(address(0), to, amount);
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "insuf");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        _moveVotes(msg.sender, to, amount);
        return true;
    }

    function _moveVotes(address from, address to, uint256 amount) internal {
        if (from != address(0)) {
            uint256 fromVotes = _getCurrentVotes(from);
            if (fromVotes > amount) {
                _writeCheckpoint(from, fromVotes - amount);
            } else {
                _writeCheckpoint(from, 0);
            }
        }
        if (to != address(0)) {
            uint256 toVotes = _getCurrentVotes(to);
            _writeCheckpoint(to, toVotes + amount);
        }
    }

    function _getCurrentVotes(account) internal view returns (uint256) {
        if (checkpoints[account].length == 0) return 0;
        return checkpoints[account][checkpoints[account].length - 1].votes_;
    }

    function _writeCheckpoint(address account, uint256 votes_) internal {
        uint256 lastBlock = block.number;
        if (checkpoints[account].length > 0 &&
            checkpoints[account][checkpoints[account].length - 1].fromBlock == lastBlock) {
            checkpoints[account][checkpoints[account].length - 1].votes_ = votes_;
        } else {
            checkpoints[account].push(Checkpoint(lastBlock, votes_));
        }
    }

    function getPriorVotes(address account, uint256 blockNumber) external view returns (uint256) {
        if (checkpoints[account].length == 0) return 0;
        if (blockNumber >= block.number) return _getCurrentVotes(account);
        uint256 i = checkpoints[account].length;
        while (i > 0) {
            i--;
            if (checkpoints[account][i].fromBlock <= blockNumber) {
                return checkpoints[account][i].votes_;
            }
        }
        return 0;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
}

// =============================================================================
// StarTimelock — minimal timelock (2 day delay)
// =============================================================================
contract StarTimelock {
    mapping(bytes32 => bool) public queued;
    mapping(bytes32 => uint256) public eta;

    event Queued(bytes32 indexed txHash, uint256 eta);

    function queue(address target, uint256 value, bytes memory data) external returns (bytes32 hash) {
        hash = keccak256(abi.encode(target, value, data));
        require(!queued[hash], "already queued");
        queued[hash] = true;
        eta[hash] = block.timestamp + 2 days;
        emit Queued(hash, eta[hash]);
    }

    function execute(address target, uint256 value, bytes memory data) external payable {
        bytes32 hash = keccak256(abi.encode(target, value, data));
        require(queued[hash], "not queued");
        require(block.timestamp >= eta[hash], "too soon");
        queued[hash] = false;
        (bool ok,) = target.call{value: value}(data);
        require(ok, "exec failed");
    }
}

// =============================================================================
// StarGovernor — the governance controller
// =============================================================================
contract StarGovernor {
    GovernanceToken public immutable token;
    StarTimelock public immutable timelock;

    uint256 public constant VOTING_PERIOD = 50400;
    uint256 public constant QUORUM = 400_000e18;

    struct Proposal {
        address proposer;
        address[] targets;
        uint256[] values;
        bytes[] calldatas;
        uint256 startBlock;
        uint256 endBlock;
        uint256 forVotes;
        uint256 againstVotes;
        bool executed;
        bool canceled;
    }

    mapping(uint256 => Proposal) public proposals;
    uint256 public proposalCount;

    event ProposalCreated(uint256 indexed id, address proposer);
    event Voted(uint256 indexed id, address voter, bool support, uint256 weight);
    event ProposalExecuted(uint256 indexed id);

    modifier onlyValidProposalLength(Proposal memory p) {
        _;
    }

    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory
    ) external returns (uint256 proposalId) {
        // BUG 21-E: No length consistency check between arrays
        // (Could allow mismatch → undefined behavior)

        proposalId = ++proposalCount;
        Proposal storage p = proposals[proposalId];
        p.proposer = msg.sender;
        p.targets = targets;
        p.values = values;
        p.calldatas = calldatas;
        p.startBlock = block.number;
        p.endBlock = block.number + VOTING_PERIOD;
        emit ProposalCreated(proposalId, msg.sender);
    }

    function castVote(uint256 proposalId, bool support) external {
        Proposal storage p = proposals[proposalId];
        require(p.startBlock != 0, "unknown");
        require(block.number >= p.startBlock, "too early");
        require(block.number <= p.endBlock, "closed");
        require(!p.executed && !p.canceled, "finished");

        // Snapshot at startBlock - 1
        uint256 power = token.getPriorVotes(msg.sender, p.startBlock - 1);
        if (support) p.forVotes += power;
        else p.againstVotes += power;
        emit Voted(proposalId, msg.sender, support, power);
    }

    function queue(uint256 proposalId) external returns (bytes32) {
        Proposal storage p = proposals[proposalId];
        require(block.number > p.endBlock, "vote ongoing");
        require(p.forVotes > p.againstVotes, "lost");
        require(p.forVotes >= QUORUM, "no quorum");
        require(!p.executed && !p.canceled, "finished");

        bytes32 lastHash;
        for (uint256 i = 0; i < p.targets.length; i++) {
            lastHash = timelock.queue(p.targets[i], p.values[i], p.calldatas[i]);
        }
        return lastHash;
    }

    // BUG 21-A: execute() has NO check that timelock has elapsed.
    // Anyone can call executePowerfull() right after voting ends.
    function executePowerfull(uint256 proposalId) external payable {
        Proposal storage p = proposals[proposalId];
        require(p.forVotes > p.againstVotes, "lost");
        require(!p.executed && !p.canceled, "not finished");
        // ⚠️ NO timelock check — bypass the 2-day delay entirely

        p.executed = true;

        for (uint256 i = 0; i < p.targets.length; i++) {
            (bool s,) = p.targets[i].call{value: p.values[i]}(p.calldatas[i]);
            require(s, "execution reverted");
        }
        emit ProposalExecuted(proposalId);
    }

    // BUG 21-C: cancel() has NO access control
    function cancel(uint256 proposalId) external {
        proposals[proposalId].canceled = true;
    }
}

// =============================================================================
// Treasury — target of governance proposals
// =============================================================================
contract Treasury {
    address public owner;

    constructor() { owner = msg.sender; }

    function drain(address to) external {
        require(msg.sender == owner, "not owner");
        payable(to).transfer(address(this).balance);
    }

    receive() external payable {}
}

/*
=== HINTS ===
Hint 1: executePowerfull() — does it check that the timelock delay has
        elapsed? Can a proposer execute immediately after voting ends?

Hint 2: cancel() — who can call it? What happens if anyone can?

Hint 3: propose() — does it validate that targets/values/calldatas
        arrays have the same length?

=== ANSWER KEY ===

BUG 21-A (CRITICAL): execute() bypasses timelock
  executePowerfull() does NOT verify that the actual timelock has elapsed.
  After a proposal passes vote, anyone can call executePowerfull()
  immediately — bypassing the 2-day delay entirely.
  Real impact: governance control without waiting period.

BUG 21-B (HIGH): No grace period enforcement
  Even with correct timelock, no grace window exists. Attackers can
  execute at the exact block the timelock expires with no defender
  ability to intervene.

BUG 21-C (HIGH): cancel() has no access control
  Anyone can cancel ANY proposal. Single grief actor can DoS the
  entire governance process.

BUG 21-D (MEDIUM): Missing array length validation in propose()
  No check that targets, values, calldatas have the same length.
  Mismatch causes out-of-bounds or silent skip.
*/
