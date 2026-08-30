// SPDX-License-Identifier: MIT
// DRILL 8F PoC — State Machine Methodology
// Functions callable from wrong state
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

/* STATES:
   0 = INITIALIZED
   1 = ACTIVE (deposits enabled)
   2 = PAUSED (no deposits, withdrawals OK)
   3 = CLOSED (no operations)
   4 = EMERGENCY (only admin can withdraw)
*/

contract StateMachineVault {
    IERC20 public token;

    uint256 public state; // 0,1,2,3,4
    mapping(address => uint256) public balances;
    address public admin;

    constructor(address _token) { token = IERC20(_token); state = 1; admin = msg.sender; }

    // BUG 8F-1: deposit() should fail in PAUSED state, doesn't
    function deposit(uint256 amount) external {
        // Should check: require(state == 1, "not active");
        // Missing!
        require(token.transferFrom(msg.sender, address(this), amount), "xfer");
        balances[msg.sender] += amount;
    }

    function withdraw(uint256 amount) external {
        // BUG 8F-2: withdraw allowed in EMERGENCY state (should be admin-only)
        require(balances[msg.sender] >= amount, "insuf");
        balances[msg.sender] -= amount;
        token.transfer(msg.sender, amount);
    }

    function emergencyPause() external {
        require(msg.sender == admin, "not admin");
        state = 2;
    }

    function emergencyClose() external {
        require(msg.sender == admin, "not admin");
        state = 4;
    }

    // BUG 8F-3: resume() can be called even after EMERGENCY_CLOSE
    function resume() external {
        require(msg.sender == admin, "not admin");
        state = 1; // Should check current state!
    }
}
