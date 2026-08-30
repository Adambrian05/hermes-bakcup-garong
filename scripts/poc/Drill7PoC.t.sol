// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";

/**
 * DRILL 7 PoC - ProtocolX CRITICAL accounting drift
 * Bug #1: totalDebt -= repayAmt - fee is WRONG.
 *   totalDebt seharusnya dikurangi SEBESAR PRINCIPAL.
 *   Tapi dikurangi repayAmt (principal+bunga) - fee.
 *   Akibat: totalDebt undercount = pool terlihat sehat padahal insolvent.
 *
 * Bug #2: Kalo Alice satu2nya borrower dan full repay, arithmetic underflow
 *   karena 500e18 - (525e18 - fee) = NEGATIF. Ini PANIC di Solidity 0.8.
 *   Di 0.7.x ini silent underflow - totalDebt = type(uint256).max - ~10^77
 */

contract MockToken {
    string public name; uint256 public totalSupply;
    mapping(address=>uint256) public balanceOf;
    mapping(address=>mapping(address=>uint256)) public allowance;
    constructor(string memory _n){ name=_n; }
    function mint(address t,uint256 a)external{totalSupply+=a;balanceOf[t]+=a;}
    function transfer(address t,uint256 a)external returns(bool){
        require(balanceOf[msg.sender]>=a);balanceOf[msg.sender]-=a;balanceOf[t]+=a;return true;}
    function transferFrom(address f,address t,uint256 a)external returns(bool){
        require(balanceOf[f]>=a&&allowance[f][msg.sender]>=a);
        allowance[f][msg.sender]-=a;balanceOf[f]-=a;balanceOf[t]+=a;return true;}
    function approve(address s,uint256 a)external returns(bool){allowance[msg.sender][s]=a;return true;}
}

contract ProtocolX {
    MockToken public collateralToken;
    MockToken public debtToken;

    mapping(address=>uint256)public collateral;
    mapping(address=>uint256)public debt;
    uint256 public totalCollateral;
    uint256 public totalDebt;
    uint256 public borrowRate=5e16;

    mapping(address=>uint256)public staked;
    uint256 public totalStaked;
    uint256 public rewardPerTokenStored;
    mapping(address=>uint256)public userRewardPerTokenPaid;
    mapping(address=>uint256)public rewards;
    uint256 public lastUpdateTime;
    uint256 public rewardRate=0;

    uint256 public protocolFee=1000;
    uint256 public accumulatedFees;

    uint256 public interestIndex=1e18;
    uint256 public lastInterestUpdate;
    mapping(address=>uint256)public userInterestIndex;

    constructor(address _coll,address _debt){
        collateralToken=MockToken(_coll);debtToken=MockToken(_debt);
        lastUpdateTime=block.timestamp;lastInterestUpdate=block.timestamp;
    }

    function depositCollateral(uint256 a)external{
        _accrueInterest();collateralToken.transferFrom(msg.sender,address(this),a);
        collateral[msg.sender]+=a;totalCollateral+=a;
    }
    function borrow(uint256 a)external{
        _accrueInterest();
        require(collateral[msg.sender]*2>=(debt[msg.sender]+a)*3,"LTV");
        debt[msg.sender]+=a;totalDebt+=a;
        userInterestIndex[msg.sender]=interestIndex;
        debtToken.transfer(msg.sender,a);
    }
    function repay(uint256 amount)external{
        _accrueInterest();
        uint256 currentDebt=_currentDebt(msg.sender);
        uint256 repayAmt=amount>currentDebt?currentDebt:amount;
        debtToken.transferFrom(msg.sender,address(this),repayAmt);
        uint256 interestPortion=currentDebt-debt[msg.sender];
        uint256 fee=interestPortion*protocolFee/10000;
        debt[msg.sender]=currentDebt-repayAmt;
        totalDebt-=repayAmt-fee;   // <-- THE BUG
        accumulatedFees+=fee;
        userInterestIndex[msg.sender]=interestIndex;
    }
    function _accrueInterest()internal{
        if(totalDebt==0){lastInterestUpdate=block.timestamp;return;}
        uint256 e=block.timestamp-lastInterestUpdate;
        uint256 rps=borrowRate/365 days;
        interestIndex+=interestIndex*rps*e/1e18;
        lastInterestUpdate=block.timestamp;
    }
    function _currentDebt(address u)internal view returns(uint256){
        if(userInterestIndex[u]==0)return debt[u];
        return debt[u]*interestIndex/userInterestIndex[u];
    }
}

contract Drill7PoC is Test {
    ProtocolX proto;
    MockToken coll; MockToken debtTok;
    address alice=address(0xA11CE);
    address bob=address(0xB0B);

    function setUp()public{
        coll=new MockToken("C");debtTok=new MockToken("D");
        proto=new ProtocolX(address(coll),address(debtTok));
        coll.mint(alice,10_000e18);coll.mint(bob,10_000e18);
        debtTok.mint(address(proto),100_000e18);
        debtTok.mint(alice,100_000e18);debtTok.mint(bob,100_000e18);
        vm.prank(alice);coll.approve(address(proto),type(uint256).max);
        vm.prank(alice);debtTok.approve(address(proto),type(uint256).max);
        vm.prank(bob);coll.approve(address(proto),type(uint256).max);
        vm.prank(bob);debtTok.approve(address(proto),type(uint256).max);
    }

    // Bug #1: Single borrower full repay = arithmetic underflow
    function test_PoC7_SingleRepayUnderflow() public {
        vm.prank(alice);
        proto.depositCollateral(1000e18);
        vm.prank(alice);
        proto.borrow(500e18);
        assertEq(proto.totalDebt(),500e18);

        vm.warp(block.timestamp+365 days); // 5% interest accrues

        // Alice repays everything - MUST revert due to checked arithmetic
        vm.prank(alice);
        vm.expectRevert(stdError.arithmeticError);
        proto.repay(type(uint256).max);
    }

    // Bug #2: Two borrowers - invariant BROKEN without overflow
    function test_PoC7_AccountingDrift_TwoUsers() public {
        // Alice borrows 500
        vm.prank(alice);
        proto.depositCollateral(1000e18);
        vm.prank(alice);
        proto.borrow(500e18);

        // Bob borrows 1000
        vm.prank(bob);
        proto.depositCollateral(2000e18);
        vm.prank(bob);
        proto.borrow(1000e18);

        uint256 totalBefore=proto.totalDebt();
        uint256 sumBefore=proto.debt(alice)+proto.debt(bob);
        assertEq(totalBefore,sumBefore,"invariant holds before repay");

        vm.warp(block.timestamp+365 days);

        // Bob repays full - fee reduces totalDebt wrongly
        vm.prank(bob);
        proto.repay(type(uint256).max);

        // INVARIANT CHECKED: totalDebt should equal sum of individual debts
        uint256 totalAfter=proto.totalDebt();
        uint256 sumAfter=proto.debt(alice)+proto.debt(bob);
        assertNotEq(totalAfter,sumAfter,"BUG: invariant broken - totalDebt != sum of debts");
        console.log("totalDebt:",totalAfter);
        console.log("sum(debt):",sumAfter);
        console.log("DRIFT:",sumAfter-totalAfter);
    }

    // Bug #3: Accounting drift leads to over-borrow capability
    function test_PoC7_OverBorrowAfterDrift() public {
        // Setup: two users, one repays creating drift
        vm.prank(alice);
        proto.depositCollateral(2000e18);
        vm.prank(alice);
        proto.borrow(500e18);

        vm.prank(bob);
        proto.depositCollateral(2000e18);
        vm.prank(bob);
        proto.borrow(500e18);

        vm.warp(block.timestamp+365 days);

        // Bob repays - creates drift in totalDebt
        vm.prank(bob);
        proto.repay(type(uint256).max);

        // Now totalDebt < sum(individual) - pool thinks it has capacity
        // Carol can borrow more than she should
        address carol=address(0xC0C0);
        coll.mint(carol,10_000e18);debtTok.mint(carol,10_000e18);
        vm.startPrank(carol);
        coll.approve(address(proto),type(uint256).max);
        debtTok.approve(address(proto),type(uint256).max);
        proto.depositCollateral(2000e18);
        proto.borrow(1000e18);
        vm.stopPrank();

        // Now check: totalDebt vs actual sum - drift persists
        uint256 totalNow=proto.totalDebt();
        uint256 sumNow=proto.debt(alice)+proto.debt(bob)+proto.debt(carol);
        assertNotEq(totalNow,sumNow,"drift persists after new borrow");
        console.log("After carol borrows: totalDebt:",totalNow,"sum(debt):",sumNow);
    }
}