// SPDX-License-Identifier: MIT
// DRILL 8I PoC — Fuzz-Driven Methodology
// Tool-flagged findings → manual verify
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

/* Tools would flag:
   - Slither: "reentrancy-no-eth" on withdraw()
   - Slither: "arbitrary-send" on emergencyWithdraw()
   - Aderyn: missing zero-address check
   - Echidna: invariant totalDeposited == sum balances violated
*/
contract ToolFlaggedContract {
    IERC20 public token;

    mapping(address => uint256) public balances;
    uint256 public totalDeposited;
    address public admin;

    // HOOK: external contract can be called here
    address public hook;

    constructor(address _token) { token = IERC20(_token); admin = msg.sender; }

    function setHook(address _hook) external { hook = _hook; } // BUG: no access

    function deposit(uint256 amount) external {
        require(token.transferFrom(msg.sender, address(this), amount), "xfer");
        balances[msg.sender] += amount;
        totalDeposited += amount;
    }

    // TOOL FLAG: reentrancy-no-eth (after state update, hook called)
    function withdraw(uint256 amount) external {
        require(balances[msg.sender] >= amount, "insuf");
        balances[msg.sender] -= amount;
        totalDeposited -= amount;
        // After state update, hook called — NOT actual reentrancy
        if (hook != address(0)) {
            (bool ok,) = hook.call(abi.encodeWithSignature("onWithdraw(address,uint256)", msg.sender, amount));
            ok;
        }
        token.transfer(msg.sender, amount);
    }

    // TOOL FLAG: arbitrary-send
    function emergencyWithdraw(address to) external {
        require(msg.sender == admin, "not admin");
        token.transfer(to, token.balanceOf(address(this))); // OK if admin trusted
    }

    // TOOL FLAG: missing zero-address check
    function setAdmin(address newAdmin) external {
        require(msg.sender == admin, "not admin");
        admin = newAdmin; // Can be address(0) — locks contract
    }
}
