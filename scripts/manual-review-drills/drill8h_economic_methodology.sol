// DRILL 8H — METHODOLOGY: Economic / Game-Theory (Incentive Analysis)
// =============================================================================
// Timer: 30 min | Focus: Can attacker profit? Is attack economical?
// =============================================================================
//
// WHY ECONOMIC:
// - Bugs without economic impact are LOW severity
// - Even valid bugs may not be exploitable due to cost
// - Severity assessment REQUIRES economic reasoning
//
// STEPS:
//
// PHASE 1: IDENTIFY VALUE FLOWS (10 min)
// ─────────────────────────────────
// Map money flow:
//   - Where does value ENTER?
//   - Where does value EXIT?
//   - Where does value SIT?
//   - Who gets paid?
//   - Who pays?
//
// PHASE 2: COST ANALYSIS (10 min)
// ─────────────────────────────────
// For each potential attack:
//   - Gas cost (estimate at current gas price)
//   - Flash loan fee (Aave: 0.09%, dYdX: 0)
//   - Oracle costs (Chainlink VRF, etc.)
//   - Capital lockup
//   - Opportunity cost
//
// PHASE 3: PROFIT ANALYSIS (10 min)
// ─────────────────────────────────
//   - Direct profit (tokens extracted)
//   - Indirect profit (state manipulation benefit)
//   - Long-term profit (sustained attack)
//
// ATTACK IS REAL IF: profit > cost
//
// QUESTIONS TO ASK:
// ─────────────────────────────────
// 1. How much does this attack cost in gas?
// 2. Does attacker need capital? How much?
// 3. Can attacker use flash loan to avoid capital lockup?
// 4. What's the minimum profit threshold?
// 5. Does attacker risk getting front-run themselves?
// 6. Can attack be sustained / repeated?
//
// ECONOMIC THRESHOLDS:
// ─────────────────────────────────
// - Profit < $10K → often not worth attacking (too much risk)
// - Profit $10K-$100K → marginal, depends on protocol size
// - Profit $100K+ → likely targeted
// - Profit $1M+ → almost certainly targeted
//
// SEVERITY ASSESSMENT:
// ─────────────────────────────────
// Severity = impact × likelihood × economic viability
//
// impact: scope of damage (full pool loss > partial)
// likelihood: how often can attack happen (always > once)
// economic: is it profitable (high gas protocol = less likely)
//
// Example:
//   - Bug exists, but profit = $5K, cost = $10K → NOT a real bug
//   - Bug exists, profit = $1M, cost = $10K → CRITICAL
//   - Bug exists, profit = $0 (only grief) → MEDIUM
//
// EXAMPLE ECONOMIC ANALYSIS:
// ─────────────────────────────────
// - bZx: $8M profit, $1M cost → REAL BUG, executed
// - LinearUnlocker: profit = total locked tokens (admin-only path)
//   → REAL BUG but admin-gated (lower likelihood)
// - Compound: COMP distribution bug, profit minimal → reported but not exploited
//
// WHEN TO USE:
// - Severity assessment (always!)
// - Deciding what to report
// - Understanding attack likelihood
//
// RELATED DRILLS:
// - Drill 8 (0-Day Hunt) — Phase 5
// - Severity framework in MEMORY
// =============================================================================
