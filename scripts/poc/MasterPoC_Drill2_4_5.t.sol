// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";

// --- MOCK TOKEN ---
contract MockToken {
    string public name; uint256 public totalSupply;
    mapping(address=>uint256) public balanceOf;
    mapping(address=>mapping(address=>uint256)) public allowance;
    constructor(string memory _n){ name=_n; }
    function mint(address t,uint256 a)external{totalSupply+=a;balanceOf[t]+=a;}
    function transfer(address t,uint256 a)external returns(bool){
        require(balanceOf[msg.sender]>=a, "MockToken: insufficient balance");
        balanceOf[msg.sender]-=a;balanceOf[t]+=a;return true;}
    function transferFrom(address f,address t,uint256 a)external returns(bool){
        require(balanceOf[f]>=a, "MockToken: insufficient balance");
        if(f!=msg.sender && allowance[f][msg.sender]!=type(uint256).max) {
             require(allowance[f][msg.sender]>=a, "MockToken: insufficient allowance");
             allowance[f][msg.sender]-=a;
        }
        balanceOf[f]-=a;balanceOf[t]+=a;return true;}
    function approve(address s,uint256 a)external returns(bool){allowance[msg.sender][s]=a;return true;}
}

// --- DRILL 2: LendingPool Oracle Rate ---
contract LendingPool {
    struct Loan { uint256 principal; uint256 startTime; }
    mapping(address => Loan) public loans;
    MockToken public token;
    address public oracle;

    constructor(address _t, address _o) { token = MockToken(_t); oracle = _o; }

    function borrow(uint256 amount) external {
        token.transfer(msg.sender, amount);
        loans[msg.sender] = Loan(amount, block.timestamp);
    }

    function repay() external {
        Loan storage loan = loans[msg.sender];
        uint256 rate = IOracle(oracle).getRate();
        uint256 elapsed = block.timestamp - loan.startTime;
        // BUG: Potential overflow (principal * rate * elapsed)
        uint256 interest = (loan.principal * rate * elapsed) / (365 days * 1e18);
        token.transferFrom(msg.sender, address(this), loan.principal + interest);
        delete loans[msg.sender];
    }
}

interface IOracle { function getRate() external view returns (uint256); }

// --- DRILL 4: VaultManager Liquidation ---
contract VaultManager {
    mapping(address => uint256) public collateral;
    mapping(address => uint256) public debt;
    MockToken public stable;

    constructor(address _s) { stable = MockToken(_s); }

    function deposit() external payable { collateral[msg.sender] += msg.value; }
    function borrow(uint256 amount) external {
        debt[msg.sender] += amount;
        stable.mint(msg.sender, amount);
    }

    function liquidate(address target) external {
        require(collateral[target] * 2000 < debt[target] * 120, "healthy"); 
        uint256 d = debt[target];
        stable.transferFrom(msg.sender, address(this), d);
        uint256 c = collateral[target];
        collateral[target] = 0; debt[target] = 0;
        payable(msg.sender).transfer(c);
    }
}

// --- DRILL 5: EpochVault DivByZero ---
contract EpochVault {
    MockToken public asset;
    uint256 public totalDeposits;
    mapping(address => uint256) public deposits;
    uint256 public lastEpochYield = 100e18;

    constructor(address _a) { asset = MockToken(_a); }

    function deposit(uint256 a) external {
        asset.transferFrom(msg.sender, address(this), a);
        deposits[msg.sender] += a; totalDeposits += a;
    }

    function withdraw(uint256 a) external {
        deposits[msg.sender] -= a; totalDeposits -= a;
        asset.transfer(msg.sender, a);
    }

    function claim() external view returns (uint256) {
        return (deposits[msg.sender] * 1e18 / totalDeposits) * lastEpochYield / 1e18;
    }
}

// --- TEST SUITE ---
contract MasterPoC is Test {
    function setUp() public {}

    function test_Drill2_OracleOverflow() public {
        MockToken t = new MockToken("T");
        address mockOracle = address(0xBAD);
        LendingPool pool = new LendingPool(address(t), mockOracle);
        
        address user = address(0x1);
        t.mint(address(pool), 100e18);
        vm.prank(user);
        pool.borrow(100e18);
        
        vm.warp(block.timestamp + 1 days);
        // Rate = 1e60 will overflow 256-bit (100e18 * 1e60 * 1 day)
        vm.mockCall(mockOracle, abi.encodeWithSignature("getRate()"), abi.encode(1e60)); 
        
        vm.prank(user);
        vm.expectRevert(stdError.arithmeticError); 
        pool.repay();
    }

    function test_Drill4_LiquidationOverpay() public {
        MockToken s = new MockToken("S");
        VaultManager vmgr = new VaultManager(address(s));
        address alice = address(0x1);
        address bob = address(0x2);
        
        vm.deal(alice, 10e18);
        vm.prank(alice);
        vmgr.deposit{value: 10e18}();
        vm.prank(alice);
        vmgr.borrow(200000e18); 
        
        s.mint(bob, 200000e18);
        vm.prank(bob);
        s.approve(address(vmgr), type(uint256).max);
        
        uint256 before = bob.balance;
        vm.prank(bob);
        vmgr.liquidate(alice);
        
        assertEq(bob.balance - before, 10e18);
    }

    function test_Drill5_DivByZero() public {
        MockToken a = new MockToken("A");
        EpochVault vault = new EpochVault(address(a));
        address alice = address(0x1);
        
        a.mint(alice, 100e18);
        vm.startPrank(alice);
        a.approve(address(vault), 100e18);
        vault.deposit(100e18);
        vault.withdraw(100e18);
        
        vm.expectRevert(stdError.divisionError); 
        vault.claim();
        vm.stopPrank();
    }
}