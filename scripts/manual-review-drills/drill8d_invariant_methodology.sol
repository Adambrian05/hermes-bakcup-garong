// DRILL 8D — METHODOLOGY: Invariant-First (Define + Break)
// =============================================================================
// Timer: 30 min | Focus: Define what MUST be true, find what breaks it
// =============================================================================
//
// WHY INVARIANT-FIRST:
// - Powerful for complex protocols
// - Breaks down "what" before "how"
// - Catches bugs that don't fit common patterns
//
// STEPS:
//
// PHASE 1: DEFINE INVARIANTS (10 min)
// ─────────────────────────────────
// For a lending protocol:
//   1. sum(collateral) >= sum(borrows) at all times
//   2. sum(deposits) == contract token balance
//   3. user.deposited == sum of user's deposits - withdrawals
//   4. liquidator gets <= collateral value
//
// For an AMM:
//   1. x * y >= k (constant product)
//   2. reserve0 / reserve1 == price
//   3. sum(LP tokens) == totalSupply
//
// For a vault:
//   1. share price never decreases (unless strategy loss)
//   2. totalAssets >= totalSupply * sharePrice
//
// PHASE 2: FIND ENFORCEMENT (10 min)
// ─────────────────────────────────
// For each invariant, find the code that SHOULD enforce it:
// - require() statements
// - assert() statements
// - overflow/underflow checks
// - balance reconciliation
//
// PHASE 3: ATTEMPT TO BREAK (10 min)
// ─────────────────────────────────
// For each invariant + enforcement pair:
// - Can I bypass the require?
// - Can I trigger underflow?
// - Can I manipulate the inputs?
// - Can I cause temporary inconsistency?
//
// QUESTIONS TO ASK:
// ─────────────────────────────────
// 1. What MUST be true for this system to work?
// 2. What could temporarily violate this?
// 3. Is the invariant checked at every state transition?
// 4. Are there race conditions where invariant fails?
// 5. Can I profit by breaking it temporarily?
//
// EXAMPLE INVARIANT VIOLATIONS:
// ─────────────────────────────────
// - LinearUnlocker: invariant "lockedToken only locks, never recovers"
//   violated by recoverTokens() missing exclusion
// - CashbackRewards: invariant "totalRewarded <= maxCap"
//   violated by allocated not counted in SEND/DISTRIBUTE
// - bZx: invariant "margin trading is solvent"
//   violated by oracle manipulation in single block
//
// TOOLS:
// - Foundry invariants (stateful fuzzing)
// - Echidna (property-based)
// - Medusa (parallel fuzz)
// - Manual derivation
//
// WHEN TO USE:
// - Complex financial protocols
// - When pattern-recognition fails
// - When you have time to think deeply
//
// RELATED DRILLS:
// - Drill 8 (0-Day Hunt) — Phase 4 is this
// - Drill 22 (Reentrancy) — invariants break via reentrancy
// =============================================================================
