// DRILL 8 — Level 7: 0-Day Hunt Methodology
// Timer: 60 min | Focus: HOW to find bugs nobody else found
// This is NOT a code drill. This is a METHODOLOGY drill.
//
// Pick a LIVE protocol. Apply this framework.
//
// === THE 0-DAY HUNT FRAMEWORK ===
//
// PHASE 1: MAP THE MONEY (10 min)
// ─────────────────────────────────
// Don't read code yet. Answer these questions:
//
// 1. Where does money ENTER the system?
//    → deposit(), mint(), stake(), supply(), bridge()
//
// 2. Where does money EXIT the system?
//    → withdraw(), burn(), unstake(), borrow(), claim()
//
// 3. Where does money MOVE within the system?
//    → transfer between contracts, strategy calls, swaps
//
// 4. Who controls each exit?
//    → permissionless? admin? timelock? multi-sig?
//
// 5. What's the TRUST MODEL?
//    → What must be true for the system to be solvent?
//    → What assumptions does the code make?
//
// Draw a diagram. Boxes = contracts. Arrows = money flow.
// Label each arrow with the function name.
//
//
// PHASE 2: FIND THE LIES (15 min)
// ─────────────────────────────────
// Every protocol has INVARIANTS — things that must always be true.
// Find them, then try to BREAK them.
//
// Common invariants:
//   totalSupply == sum of all balances
//   totalDeposits == sum of all user deposits
//   poolBalance >= totalUserClaims
//   collateralValue >= debtValue * minRatio
//   shares * sharePrice == userAssets
//
// For each invariant, ask:
//   "Is there ANY sequence of transactions that breaks this?"
//
// The LIE is when the code VIOLATES its own invariant.
// Example: totalDebt -= repayAmount - fee (Drill 7)
//   → totalDebt should equal sum of all debt[user]
//   → But fee extraction breaks this
//   → THE CODE LIES ABOUT HOW MUCH IS OWED
//
//
// PHASE 3: FOLLOW THE STALE STATE (15 min)
// ─────────────────────────────────
// The #1 source of real bugs: STATE THAT SHOULD UPDATE BUT DOESN'T.
//
// For every state variable, ask:
//   "When SHOULD this update?"
//   "When DOES this update?"
//   "Is there a path where it SHOULD but DOESN'T?"
//
// Common stale state patterns:
//   - Interest index not updated before operation
//   - Reward accumulator not checkpointed
//   - Balance cached but underlying changed
//   - Oracle price stale (no freshness check)
//   - Epoch not settled before new deposit
//
// The bug is always: "I assumed X was up-to-date, but it wasn't."
//
//
// PHASE 4: BREAK THE COMPOSITION (10 min)
// ─────────────────────────────────
// Each contract might be safe alone. But what about TOGETHER?
//
// Ask:
//   "Can I call contract A, which calls contract B,
//    which changes state that contract A assumes is constant?"
//
// Common cross-contract bugs:
//   - Callback changes exchange rate mid-operation
//   - Reentrancy across contracts (A calls B calls A)
//   - Oracle manipulated between check and execution
//   - Flash loan changes supply between read and write
//   - Two contracts share a token, one's action affects other's accounting
//
//
// PHASE 5: THINK LIKE THE ATTACKER (10 min)
// ─────────────────────────────────
// You've been thinking like a DEFENDER ("is this safe?").
// Now think like an ATTACKER ("how do I profit?").
//
// The attacker's checklist:
//   1. Can I get something for nothing?
//      → Mint without deposit, claim without stake, borrow without collateral
//
//   2. Can I get something TWICE?
//      → Double claim, double spend, double withdraw
//
//   3. Can I make SOMEONE ELSE lose so I gain?
//      → Dilute other stakers, inflate share price, manipulate oracle
//
//   4. Can I do it in a FLASH LOAN?
//      → If the attack is profitable but needs capital,
//        can I borrow the capital for 1 block?
//
//   5. Can I do it REPEATEDLY?
//      → One-time exploit = MEDIUM
//      → Repeatable drain = CRITICAL
//
//   6. What's my PROFIT after gas?
//      → If profit < gas cost, it's not exploitable
//      → Calculate: profit = extracted - deposited - gas
//
//
// PHASE 6: WRITE THE PoC (10 min)
// ─────────────────────────────────
// For each finding:
//   1. Write the attack as a numbered list of transactions
//   2. For each step: what's the state before and after?
//   3. Calculate the profit
//   4. Identify the ROOT CAUSE (one sentence)
//   5. Suggest a FIX (one line of code change)
//
// If you can't write the PoC, it's not a real finding.
// "This might be exploitable" is NOT a finding.
// "Step 1: deposit X. Step 2: call Y. Step 3: withdraw Z. Profit = Z-X." IS.
//
//
// === SCORING RUBRIC FOR 0-DAY HUNT ===
//
// +5  Found a bug nobody else found (novel)
// +3  Found a known bug pattern in new context
// +2  Found a bug with clear PoC and profit calculation
// +1  Found a bug but couldn't calculate profit
// +0  Found only LOW/INFO issues
// -1  Submitted a false positive
// -2  Submitted a "by design" issue as a bug
//
// TARGET: +5 per hunt = expert level
// CURRENT: +0 to +1 = still learning
//
//
// === DAILY PRACTICE ROUTINE ===
//
// Morning (30 min):
//   Read 1 ACCEPTED bug report from C4/Sherlock
//   Don't just read — RECONSTRUCT the attack in your head
//   Ask: "Would I have found this? What would I have needed to see?"
//
// Afternoon (60 min):
//   Pick 1 contract from a LIVE bounty
//   Apply the 6-phase framework
//   Write findings (even if 0)
//
// Evening (30 min):
//   Review your findings against the answer key (if available)
//   Or: run tools to verify your manual findings
//   Update your pattern library
//
// Weekly:
//   Submit at least 1 report (even if LOW)
//   Track: submissions, acceptances, rejections, duplicates
//   Learn from rejections: WHY was it rejected?
//
//
// === PATTERN LIBRARY (build this over time) ===
//
// Every bug you find or study, add to this list:
//
// Pattern: [name]
// Trigger: [what code pattern causes it]
// Detection: [what to look for when reading code]
// Severity: [typical severity]
// Example: [link to real report]
//
// Start with these 10:
// 1. Accounting drift (totalX != sum of individual X)
// 2. Stale state (variable not updated before use)
// 3. Missing access control (function callable by anyone)
// 4. Rounding exploitation (dust accumulation → extraction)
// 5. Oracle manipulation (single source, no TWAP, no bounds)
// 6. Flash loan amplification (1-block capital → outsized impact)
// 7. Cross-contract reentrancy (A→B→A via callback)
// 8. Governance capture (voting power without commitment)
// 9. Epoch/timing manipulation (boundary conditions)
// 10. Donation/inflation attack (balance-based accounting)
