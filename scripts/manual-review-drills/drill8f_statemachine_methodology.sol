// DRILL 8F — METHODOLOGY: State Machine (Valid Transitions)
// =============================================================================
// Timer: 30 min | Focus: Model protocol as state machine, find invalid transitions
// =============================================================================
//
// WHY STATE MACHINE:
// - Every protocol has implicit states
// - Each function transitions between states
// - Invalid transitions = bugs
//
// STEPS:
//
// PHASE 1: IDENTIFY STATES (10 min)
// ─────────────────────────────────
// What are the discrete states of the protocol?
//
// Example — Loan Protocol:
//   - State: COLLATERAL_DEPOSIT
//   - State: BORROWED
//   - State: UNDERWATER
//   - State: LIQUIDATED
//   - State: CLOSED
//
// Example — Governance:
//   - State: PENDING
//   - State: ACTIVE
//   - State: QUEUED
//   - State: EXECUTED
//   - State: CANCELED
//
// Example — Vault:
//   - State: PAUSED
//   - State: ACTIVE
//   - State: EMERGENCY
//   - State: DEPRECATED
//
// PHASE 2: IDENTIFY TRANSITIONS (10 min)
// ─────────────────────────────────
// For each function:
//   - From which state can it be called?
//   - To which state does it transition?
//   - What conditions enable the transition?
//
// Example:
//   deposit():     ANY_STATE → ACTIVE
//   withdraw():    ACTIVE → ANY_STATE (if balance > 0)
//   emergency():   ACTIVE → PAUSED (onlyOwner)
//   resume():      PAUSED → ACTIVE (onlyOwner)
//
// PHASE 3: ENUMERATE INVALID PATHS (10 min)
// ─────────────────────────────────
// For each state + function combination:
//   - Function callable from this state?
//   - Function makes sense at this state?
//   - Function leaves state consistent?
//
// Example bugs:
//   - withdraw() called when PAUSED
//   - liquidate() called when state is COLLATERAL_DEPOSIT
//   - emergency() called when state is DEPRECATED
//
// QUESTIONS TO ASK:
// ─────────────────────────────────
// 1. What states can exist?
// 2. What transitions are valid?
// 3. Are state checks (require state == X) enforced?
// 4. Can I jump between non-adjacent states?
// 5. Can I call function in WRONG state?
//
// EXAMPLE STATE MACHINE BUGS:
// ─────────────────────────────────
// - Compound COMP: liquidate without checking borrow state
// - Uniswap V3 NFT: burn without checking liquidity state
// - ERC-4626: deposit when paused
// - Governance: queue without checking vote completion
//
// TOOLS:
// - State variable analysis
// - Foundry stateful tests
// - Echidna (state coverage)
//
// WHEN TO USE:
// - Lifecycle protocols (loans, vaults, auctions)
// - Governance systems
// - Multi-phase operations
//
// RELATED DRILLS:
// - Drill 21 (Governance Race) — state machine for proposals
// =============================================================================
