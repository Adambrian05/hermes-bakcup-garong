// DRILL 8A — METHODOLOGY: Top-Down (Spec → Code)
// =============================================================================
// Timer: 30 min | Focus: HOW to audit starting from documentation
// =============================================================================
//
// WHY TOP-DOWN:
// - Find mismatches between spec and code
// - Catch "code does what it shouldn't" bugs
// - Identify missing features (code doesn't do what it should)
//
// STEPS:
//
// PHASE 1: READ DOCS (10 min)
// ─────────────────────────────────
// 1. Whitepaper / docs / README
// 2. NatSpec comments in code
// 3. NatSpec inheritance (parent contracts)
// 4. Test files (reveal expected behavior)
// 5. GitHub issues / discussions (known concerns)
//
// PHASE 2: EXTRACT INVARIANTS (10 min)
// ─────────────────────────────────
// For each function described:
//   - What is the PRECONDITION?
//   - What is the POSTCONDITION?
//   - What should NEVER happen?
//
// Example: deposit(uint256 amount)
//   Pre:  user has approved amount
//   Post: deposited[user] += amount, token balance += amount
//   Never: deposited[user] decreases without withdrawal
//
// PHASE 3: MATCH CODE TO SPEC (10 min)
// ─────────────────────────────────
// For each invariant, find the code that enforces it.
// - Is the invariant actually enforced?
// - Are there edge cases not covered?
// - Are there places where invariant is violated?
//
// QUESTIONS TO ASK:
// ─────────────────────────────────
// 1. What does the doc SAY happens?
// 2. What does the code ACTUALLY do?
// 3. Where do they diverge?
// 4. Is the divergence intentional?
// 5. Is the divergence exploitable?
//
// EXAMPLE BUGS CAUGHT BY TOP-DOWN:
// ─────────────────────────────────
// - Compound cToken: doc says "redeem underlying", code mints cTokens
// - Uniswap V3 oracle: doc says "time-weighted", code uses spot price
// - ERC-20 approve race: doc says "owner can change allowance",
//   code allows double-spend via in-flight transactions
//
// WHEN TO USE:
// - When protocol has good documentation
// - When you don't know what to look for
// - When audit time is short (catches obvious mismatches)
//
// WHEN NOT TO USE:
// - Undocumented protocols (need bottom-up instead)
// - When you already know the bug class (use targeted methodology)
//
// RELATED DRILLS:
// - Drill 8B (Bottom-Up) — opposite approach
// - Drill 8D (Invariant-First) — extracts invariants from spec
// - Drill 8J (Historical) — find variants of known exploits
// =============================================================================
