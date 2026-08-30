// DRILL 8B — METHODOLOGY: Bottom-Up (Code → Concept)
// =============================================================================
// Timer: 30 min | Focus: HOW to audit starting from code
// =============================================================================
//
// WHY BOTTOM-UP:
// - No documentation? No problem.
// - Catch bugs that exist regardless of spec
// - Discover what the code DOES (vs what it SHOULD do)
//
// STEPS:
//
// PHASE 1: BUILD THE MAP (15 min)
// ─────────────────────────────────
// 1. List all EXTERNAL/PUBLIC functions
// 2. List all STATE VARIABLES (storage layout)
// 3. List all EVENTS emitted
// 4. List all MODIFIERS
// 5. List all INHERITED contracts
//
// PHASE 2: TRACE EACH FUNCTION (10 min)
// ─────────────────────────────────
// For each external function, document:
// - Who can call it? (modifier, msg.sender checks)
// - What state does it READ?
// - What state does it WRITE?
// - What external calls does it make?
// - What events does it emit?
//
// Output: a "function card" for each entry point
//
// PHASE 3: LOOK FOR ANOMALIES (5 min)
// ─────────────────────────────────
// - Functions that read but don't write (suspicious views)
// - Functions that write but don't read (suspicious initializers)
// - Functions with no access control
// - Functions that emit no event (silent state changes)
// - Functions that make external calls (reentrancy risk)
//
// QUESTIONS TO ASK:
// ─────────────────────────────────
// 1. What is this function trying to do? (guess intent)
// 2. Does the code actually do that?
// 3. What state is left implicit?
// 4. What could go wrong in sequence?
// 5. What's missing from this function?
//
// EXAMPLE BUGS CAUGHT BY BOTTOM-UP:
// ─────────────────────────────────
// - Parity Wallet: function `initWallet` had no access control
// - Beauty Chain (BEC): integer overflow in batchTransfer
// - Poly Network: cross-chain message verification missing
//
// WHEN TO USE:
// - Undocumented / poorly documented protocols
// - When you want to understand actual behavior
// - When looking for "weird code" that smells
//
// WHEN NOT TO USE:
// - When time is limited (slow process)
// - When you already understand the code
//
// RELATED DRILLS:
// - Drill 8A (Top-Down) — opposite approach
// - Drill 8D (Invariant-First) — combine with this
// =============================================================================
