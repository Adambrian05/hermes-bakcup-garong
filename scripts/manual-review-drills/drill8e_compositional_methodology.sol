// DRILL 8E — METHODOLOGY: Compositional (Multi-Call Attack Chains)
// =============================================================================
// Timer: 30 min | Focus: How multiple functions combine into exploit
// =============================================================================
//
// WHY COMPOSITIONAL:
// - Single functions look safe in isolation
// - Attackers COMBINE multiple calls
// - Flash loans enable this in 1 transaction
//
// STEPS:
//
// PHASE 1: IDENTIFY PRIMITIVES (10 min)
// ─────────────────────────────────
// List functions that can be chained:
// - "Set" functions (configure parameters)
// - "Get" functions (read state)
// - "Move" functions (transfer value)
// - "Inversion" functions (reverse operations)
//
// Example primitives:
//   - approve(spender, amount) → set allowance
//   - transferFrom(from, amount) → move tokens
//   - deposit() / withdraw() → in/out of vault
//   - swap() → change balances
//   - flashLoan() → get temporary capital
//
// PHASE 2: LOOK FOR CHAINABLE COMBOS (15 min)
// ─────────────────────────────────
// Patterns to seek:
//   A. set_X() → exploit_X()
//      Configure parameter to vulnerable value, then exploit
//
//   B. get_state() → external_action() → return_to_state()
//      Use view function to time action (front-running)
//
//   C. function_A() + function_B() in single tx
//      A's side effect enables B's exploit
//
//   D. role_grant() + role_use()
//      Permission escalation via admin path
//
//   E. reentrancy_chain()
//      Function A calls hook → re-enter A or B
//
// PHASE 3: ESTIMATE PROFIT (5 min)
// ─────────────────────────────────
// - Cost of attack (gas, flash loan fee)
// - Profit from exploit (extracted value)
// - Net profit positive? → REAL BUG
//
// QUESTIONS TO ASK:
// ─────────────────────────────────
// 1. Can I do this in a single transaction?
// 2. Does any function leave the system in a "weird state"?
// 3. What if I CALL THIS 5 TIMES IN A ROW?
// 4. What if I call functions in DIFFERENT ORDER?
// 5. What if I sandwich my call between two others?
//
// EXAMPLE COMPOSITIONAL BUGS:
// ─────────────────────────────────
// - bZx: borrow → manipulate oracle → liquidate → repay → profit
// - Cream: deposit → use as collateral → borrow → swap → repeat
// - Rari: reentrancy via cross-function deposit/withdraw
// - Nomad: initialize → process messages → drain bridge
//
// TOOLS:
// - Foundry (sequence test calls)
// - Halmos (symbolic multi-call)
// - Manual derivation
//
// WHEN TO USE:
// - DeFi protocols with flash loans
// - Cross-contract interactions
// - Complex governance systems
//
// WHEN NOT TO USE:
// - Single-function protocols (rare in DeFi)
//
// RELATED DRILLS:
// - Drill 8 (0-Day Hunt) — Phase 4-5 use this
// - Drill 22 (Reentrancy) — reentrancy is compositional
// - Drill 21 (Governance) — multi-call attack on governance
// =============================================================================
