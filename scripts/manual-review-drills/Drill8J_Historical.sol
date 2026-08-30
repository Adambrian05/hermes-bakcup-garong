// SPDX-License-Identifier: MIT
// DRILL 8J PoC — Historical Exploit Variants
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
    function transfer(address to, uint256 amount) external override returns (bool) {
        require(balanceOf[msg.sender] >= amount, "insuf");
        balanceOf[msg.sender] -= amount; balanceOf[to] += amount; return true;
    }
    function transferFrom(address from, address to, uint256 amount) external override returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount; balanceOf[to] += amount; return true;
    }
}

contract LendingWithReentrancy {
    IERC20 public token;
    mapping(address => uint256) public balances;
    constructor(address _token) { token = IERC20(_token); }

    function withdraw(uint256 amount) external {
        require(balances[msg.sender] >= amount, "insuf");
        require(token.transfer(msg.sender, amount), "xfer");
        balances[msg.sender] -= amount;
    }
}

contract PriceOracle {
    uint256 public price;
    function setPrice(uint256 _price) external { price = _price; }
}

contract LendingWithOracleManipulation {
    PriceOracle public immutable oracle;
    mapping(address => uint256) public collateral;
    mapping(address => uint256) public debt;
    constructor(address _oracle) { oracle = PriceOracle(_oracle); }

    function isSolvent(address user) external view returns (bool) {
        uint256 price = oracle.price();
        uint256 value = (collateral[user] * price) / 1e18;
        return value >= debt[user] * 150 / 100;
    }
}

contract VaultWithCrossFunction {
    IERC20 public token;
    mapping(address => uint256) public deposited;
    mapping(address => uint256) public borrowed;
    constructor(address _token) { token = IERC20(_token); }

    function deposit(uint256 amount) external {
        require(token.transferFrom(msg.sender, address(this), amount), "xfer");
        deposited[msg.sender] += amount;
    }

    function borrow(uint256 amount) external {
        borrowed[msg.sender] += amount;
        require(token.transfer(msg.sender, amount), "xfer");
    }
}
