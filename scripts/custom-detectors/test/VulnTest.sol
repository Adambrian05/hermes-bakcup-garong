// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/// @notice Vulnerable ERC4626 vault for testing custom detectors
contract VulnVault {
    mapping(address => uint256) public balanceOf;
    mapping(address => uint256) public allowance;
    uint256 public totalSupply;
    uint256 public totalAssets;

    // VULN #1: No virtual offset → inflation attack
    function convertToShares(uint256 assets) public view returns (uint256) {
        if (totalSupply == 0) return assets;
        return (assets * totalSupply) / totalAssets;
    }

    function convertToAssets(uint256 shares) public view returns (uint256) {
        if (totalSupply == 0) return shares;
        return (shares * totalAssets) / totalSupply;
    }

    function deposit(uint256 assets, address receiver) external returns (uint256 shares) {
        shares = convertToShares(assets);
        balanceOf[receiver] += shares;
        totalSupply += shares;
        totalAssets += assets;
    }

    function withdraw(uint256 assets, address receiver) external returns (uint256 shares) {
        shares = convertToShares(assets);
        balanceOf[msg.sender] -= shares;
        totalSupply -= shares;
        totalAssets -= assets;
    }

    function redeem(uint256 shares, address receiver) external returns (uint256 assets) {
        assets = convertToAssets(shares);
        balanceOf[msg.sender] -= shares;
        totalSupply -= shares;
        totalAssets -= assets;
    }
}

/// @notice Vulnerable oracle consumer
interface IAggregator {
    function latestRoundData() external view returns (
        uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound
    );
}

contract VulnOracle {
    IAggregator public priceFeed;

    constructor(address _feed) {
        priceFeed = IAggregator(_feed);
    }

    // VULN #2: No staleness check
    function getPrice() public view returns (int256) {
        (, int256 answer,,,) = priceFeed.latestRoundData();
        return answer;
    }

    // VULN #3: Division before multiplication
    function calculateInterest(uint256 principal, uint256 rate, uint256 time) public pure returns (uint256) {
        uint256 dailyRate = rate / 365;  // truncation!
        return principal * dailyRate * time;
    }
}

/// @notice Vulnerable governance
interface IERC20 {
    function balanceOf(address) external view returns (uint256);
}

contract VulnGovernor {
    IERC20 public token;
    mapping(uint256 => mapping(address => bool)) public hasVoted;
    uint256 public proposalCount;

    constructor(address _token) {
        token = IERC20(_token);
    }

    // VULN #4: Flash loan voting — uses balanceOf directly
    function castVote(uint256 proposalId, bool support) external {
        require(!hasVoted[proposalId][msg.sender], "Already voted");
        uint256 votingPower = token.balanceOf(msg.sender);  // no snapshot!
        require(votingPower > 0, "No voting power");
        hasVoted[proposalId][msg.sender] = true;
    }

    function propose(string calldata) external {
        uint256 votingPower = token.balanceOf(msg.sender);  // no snapshot!
        require(votingPower > 1000e18, "Need 1000 tokens");
        proposalCount++;
    }
}

/// @notice Vulnerable bridge with signature replay
contract VulnBridge {
    mapping(bytes32 => bool) public processed;
    bytes32 public DOMAIN_SEPARATOR;

    constructor() {
        // VULN #5: No chainId in domain separator
        DOMAIN_SEPARATOR = keccak256(abi.encode(
            keccak256("EIP712Domain(string name,string version)"),
            keccak256("VulnBridge"),
            keccak256("1")
        ));
    }

    function relay(
        address token,
        uint256 amount,
        address recipient,
        uint8 v, bytes32 r, bytes32 s
    ) external {
        bytes32 digest = keccak256(abi.encodePacked(
            "\x19\x01",
            DOMAIN_SEPARATOR,
            keccak256(abi.encode(token, amount, recipient))
        ));
        address signer = ecrecover(digest, v, r, s);
        require(signer != address(0), "Invalid signature");
        // No nonce check → replayable!
        // No chainId → cross-chain replayable!
    }
}
