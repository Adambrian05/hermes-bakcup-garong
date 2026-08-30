// DRILL 8J — METHODOLOGY: Historical Exploit Variants (Pattern Memory)
// =============================================================================
// Timer: 30 min | Focus: Find variants of known exploits in new code
// =============================================================================
//
// WHY HISTORICAL:
// - Same bug patterns repeat across protocols
// - If Protocol X got hacked, Protocol Y (similar) likely has same bug
// - Pattern memory is auditor's competitive advantage
//
// FAMOUS EXPLOITS TO KNOW:
// ─────────────────────────────────
//
// 2016 — The DAO (Reentrancy)
//   Pattern: external call BEFORE state update
//   Variant search: any function that calls external before decrementing balance
//
// 2018 — Beauty Chain (Integer Overflow)
//   Pattern: multiplication overflow in batchTransfer
//   Variant search: any *_multiplier_amount pattern
//
// 2020 — bZx (Oracle Manipulation)
//   Pattern: single-block price manipulation via flash loan
//   Variant search: any spot price usage for high-value operations
//
// 2021 — Poly Network (Cross-chain Message Verification)
//   Pattern: insufficient signature verification
//   Variant search: any cross-chain message handler
//
// 2021 — Cream Finance (Multi-step Reentrancy)
//   Pattern: reentrancy via cross-function
//   Variant search: hooks/callbacks between deposit/withdraw
//
// 2022 — Wormhole (Signature Verification)
//   Pattern: guardian signature bypass via deprecated method
//   Variant search: signature schemes with admin paths
//
// 2022 — Ronin Bridge (Validator Compromise)
//   Pattern: insufficient validator threshold
//   Variant search: multi-sig with low threshold
//
// 2023 — Euler Finance (Liquidation Math)
//   Pattern: liquidation logic accounting error
//   Variant search: any lending liquidation math
//
// STEPS:
//
// PHASE 1: BUILD EXPLOIT DATABASE (continuous)
// ─────────────────────────────────
// For each major exploit, document:
//   - Pattern signature (code pattern)
//   - Variant signatures (how it might appear)
//   - Detection checklist
//
// PHASE 2: MATCH AGAINST NEW CODE (per audit)
// ─────────────────────────────────
// For each function in new protocol:
//   - Does it match any known pattern?
//   - Are mitigations present?
//   - Is mitigation complete?
//
// PHASE 3: INVESTIGATE VARIANTS (per audit)
// ─────────────────────────────────
// Each known exploit has VARIANTS:
//   - Different trigger (deposit vs withdraw vs liquidate)
//   - Different asset (ETH vs token vs LP)
//   - Different protocol (lending vs AMM vs vault)
//
// QUESTIONS TO ASK:
// ─────────────────────────────────
// 1. Has this PATTERN caused issues before?
// 2. Is this VARIANT of the pattern?
// 3. Has the protocol fixed all VARIANTS of similar past bugs?
// 4. What's the most creative way this pattern could be exploited HERE?
//
// VARIANT SEARCH EXAMPLE:
// ─────────────────────────────────
// Original: bZx flash-loan oracle manipulation
//
// Variants to search:
//   - Any protocol that uses Uniswap V2 spot price
//   - Any protocol that uses single-block price
//   - Any protocol that allows same-block borrow+swap
//   - Any protocol with oracle update + value action in same tx
//
// RELATED DRILLS:
// - All other drills are variants of historical exploits
// - Drill 22 (Reentrancy) — DAO variant
// - Drill 19 (MEV Lending) — bZx variant
//
// TOOLS:
// - CodeQL cross-pattern search
// - Slither custom detectors for known patterns
// - Manual pattern matching
//
// WHEN TO USE:
// - Always (pattern memory is built over time)
// - Especially for forked protocols
// - When unsure where to start
// =============================================================================
