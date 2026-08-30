// DRILL 8I — METHODOLOGY: Fuzz-Driven (Tool-First, Manual-Second)
// =============================================================================
// Timer: 30 min | Focus: Use tools to find candidates, verify manually
// =============================================================================
//
// WHY FUZZ-DRIVEN:
// - Tools find things humans miss
// - Fast iteration loop
// - Validates invariants automatically
//
// STEPS:
//
// PHASE 1: SETUP TOOLS (10 min)
// ─────────────────────────────────
// Run full tool matrix:
//   - Slither (default detectors)
//   - Slither (custom detectors)
//   - Aderyn (fast static analysis)
//   - Semgrep (pattern matching)
//   - Mythril (symbolic + taint)
//   - Echidna (property-based fuzzing)
//   - Medusa (parallel fuzzing)
//   - Foundry invariant tests
//   - Halmos (symbolic)
//   - Z3 (SMT prover)
//
// PHASE 2: COLLECT FINDINGS (10 min)
// ─────────────────────────────────
// Aggregate all tool outputs:
//   - High confidence → report
//   - Medium confidence → manual verify
//   - Low confidence → may be FP, still check
//
// Tool output categories:
//   - Confirmed bug (Slither + manual verify)
//   - False positive (manual verify = benign)
//   - Edge case (tool uncertain, manual needed)
//
// PHASE 3: MANUAL VERIFY (10 min)
// ─────────────────────────────────
// For each finding:
//   - Read the code path flagged
//   - Understand why tool flagged
//   - Determine if real bug
//   - Determine impact
//   - Determine severity
//
// Don't blindly trust tools. Don't blindly ignore them.
//
// TOOL OUTPUT → MANUAL ACTION:
// ─────────────────────────────────
//
// Slither "reentrancy-eth":
//   - Read flagged function
//   - Trace state updates vs external calls
//   - Confirm or reject
//
// Echidna "invariant X violated":
//   - Read counterexample sequence
//   - Replay manually
//   - Determine exploitability
//
// Mythril "integer overflow":
//   - Solidity 0.8.x → automatic revert
//   - But unchecked blocks → manual verify
//   - Cast operations → verify safety
//
// WHEN TO USE:
// - Always (per Rule #4: run all tools)
// - When time-constrained (tools are fast)
// - When you want confidence in findings
//
// TOOL LIMITATIONS:
// ─────────────────────────────────
// - Each tool has blind spots
// - Some bugs require SEMANTIC understanding
// - Tools report patterns, not intent
// - Custom detectors needed for novel bugs
//
// REAL BUGS CAUGHT BY FUZZ:
// ─────────────────────────────────
// - Yield protocol: rounding bug in reward calc
// - Lending: liquidation threshold manipulation
// - AMM: slippage calculation overflow
//
// RELATED DRILLS:
// - All drills benefit from fuzz verification
// - Drill 22 (Reentrancy) — often found via Slither
// - Drill 19 (MEV Lending) — math bugs found via Halmos
// =============================================================================
