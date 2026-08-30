// DRILL 8G — METHODOLOGY: Symbolic Execution (Input Space Exploration)
// =============================================================================
// Timer: 30 min | Focus: Explore all possible inputs to find edge cases
// =============================================================================
//
// WHY SYMBOLIC:
// - Manual review can miss edge cases
// - Symbolic execution explores ALL paths
// - Catches math bugs, boundary conditions, overflow
//
// STEPS:
//
// PHASE 1: PICK FUNCTIONS (10 min)
// ─────────────────────────────────
// - Math-heavy functions
// - Functions with require()/assert()
// - Functions with multiple branches
// - Cross-contract calls
//
// PHASE 2: DEFINE SYMBOLIC INPUTS (5 min)
// ─────────────────────────────────
// Use symbolic variables:
//   uint256 amount;        // any uint
//   address user;          // any address
//   uint256 price;         // any price
//   bool support;          // any bool
//
// PHASE 3: EXPLORE PATHS (15 min)
// ─────────────────────────────────
// For each path through the function:
//   - What input values reach this path?
//   - Can this path violate an invariant?
//   - Can this path overflow/underflow?
//   - Can this path revert unexpectedly?
//
// Examples to explore:
//   - amount = 0
//   - amount = 1
//   - amount = type(uint256).max
//   - amount = balance / 2
//   - user = address(0)
//   - user = contract itself
//
// QUESTIONS TO ASK:
// ─────────────────────────────────
// 1. What if amount == 0?
// 2. What if amount == MAX_UINT?
// 3. What if balance == 0?
// 4. What if timestamp == 0?
// 5. What if user == address(this)?
// 6. What if user == msg.sender?
// 7. What if price == 0?
// 8. What if delta > balance?
//
// EXAMPLE EDGE CASES FOUND:
// ─────────────────────────────────
// - YAM bug: rebasing overflow at large supply
// - Compound: cToken exchange rate underflow
// - Uniswap V2: division by zero in price oracle
// - ERC-20: approve to current value (race condition)
//
// TOOLS:
// - Halmos (symbolic execution for Solidity)
// - Mythril (path exploration)
// - KEVM (formal verification)
//
// WHEN TO USE:
// - Math-heavy contracts
// - When you suspect overflow/underflow
// - When you want to explore all inputs
//
// WHEN NOT TO USE:
// - State-heavy protocols (state explosion)
// - When time is limited
//
// LIMITATIONS:
// - State space explosion for complex protocols
// - External calls are hard to symbolize
// - Loop unrolling has limits
//
// RELATED DRILLS:
// - Drill 19 (MEV Lending) — math bugs in oracle calcs
// - Drill 8I (Fuzz-Driven) — similar exploration
// =============================================================================
