// SPDX-License-Identifier: MIT
// DRILL 8E PoC — Compositional Methodology
// Single calls are safe, multi-call exploits
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

contract VaultCompositional {
    IERC20 public token;

    mapping(address => uint256) public balances;
    uint256 public totalBalance;
    uint256 public rewardPerBlock = 10;

    address public feeRecipient;
    uint256 public feeBps = 100; // 1%

    uint256 public accRewards;
    mapping(address => uint256) public rewardDebt;

    constructor(address _token) { token = IERC20(_token); }

    function deposit(uint256 amount) external {
        require(token.transferFrom(msg.sender, address(this), amount), "xfer");
        balances[msg.sender] += amount;
        totalBalance += amount;
    }

    function withdraw(uint256 amount) external {
        require(balances[msg.sender] >= amount, "insuf");
        // BUG 8E-1: No fee check vs rewardDebt
        balances[msg.sender] -= amount;
        totalBalance -= amount;
        // BUG 8E-2: fee charged but feeRecipient can be self (no real distribution)
        uint256 fee = (amount * feeBps) / 10000;
        if (feeRecipient == address(0)) {
            feeRecipient = msg.sender; // <-- Self-claim!
        }
        token.transfer(feeRecipient, fee);
        token.transfer(msg.sender, amount - fee);
    }

    // BUG 8E-3: setFeeRecipient callable by anyone, then chain with withdraw
    function setFeeRecipient(address _r) external { feeRecipient = _r; }

    // COMPOSITIONAL ATTACK:
    // 1. setFeeRecipient(address(0))
    // 2. withdraw() — feeRecipient becomes msg.sender, gets fee back
    // 3. Net: no fee charged, but accounting still records the fee
    // Repeated: drain contract via fee loop
}
