// DRILL 8C — METHODOLOGY: Differential (Compare Implementations)
// =============================================================================
// Timer: 30 min | Focus: HOW to find bugs via comparison
// =============================================================================
//
// WHY DIFFERENTIAL:
// - Two implementations of "same thing" rarely identical
// - Differences often hide bugs
// - Industry-standard protocols are templates — bugs replicate
//
// STEPS:
//
// PHASE 1: PICK PAIRS (5 min)
// ─────────────────────────────────
// - Protocol A vs Protocol B (e.g., Uniswap V2 vs SushiSwap)
// - Old version vs new version (audit for regression)
// - Fork vs upstream (Compound forks)
// - Library vs hand-rolled (OZ vs custom)
//
// PHASE 2: ALIGN (10 min)
// ─────────────────────────────────
// - Match function pairs (deposit → deposit)
// - Match state variables
// - Match modifiers
// - Identify scope differences
//
// PHASE 3: DIFF (15 min)
// ─────────────────────────────────
// For each aligned pair:
// - Same inputs → different outputs? BUG
// - Different access control? BUG
// - Different event emission? BUG
// - Different accounting? BUG
// - Same logic but different constants? INVESTIGATE
//
// QUESTIONS TO ASK:
// ─────────────────────────────────
// 1. Why was this function changed?
// 2. Is the change backward-compatible?
// 3. Does the change break invariants of the original?
// 4. Were tests updated to match?
// 5. Was the change audited?
//
// EXAMPLE BUGS CAUGHT BY DIFFERENTIAL:
// ─────────────────────────────────
// - CREAM/HOMERICE: Compound fork with broken Comptroller
// - SushiSwap MISO: auction logic diverged from docs
// - Numerous ERC20 forks with missing return values
//
// WHEN TO USE:
// - Forks of major protocols (Compound, Uniswap, Aave)
// - Protocol upgrades (v1 → v2)
// - Libraries from different sources
// - When you have reference implementation to compare
//
// WHEN NOT TO USE:
// - Truly novel protocols
// - Single-implementation systems
//
// TOOLS:
// - diff, git diff
// - semgrep with cross-file patterns
// - manual side-by-side review
//
// RELATED DRILLS:
// - Drill 8J (Historical Exploits) — find similar bugs
// =============================================================================
