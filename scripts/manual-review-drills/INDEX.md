# MANUAL REVIEW DRILL SERIES — COMPLETE
# 8 Drills | 7 Levels | From Amatir → Ahli

## FILES
```
drill1.sol  — Level 1: YieldVault (single contract, inflation + double-count)
drill2.sol  — Level 1: LendingPool (multi-actor, self-liquidation)
drill3.sol  — Level 2: StakingVault (MasterChef pattern, oracle manipulation)
drill4.sol  — Level 3: VaultManager + PriceFeed (cross-contract, TWAP)
drill5.sol  — Level 4: EpochVault (multi-tx timing, epoch boundary)
drill6.sol  — Level 5: GovToken + Staking + Treasury (governance + economic)
drill7.sol  — Level 6: ProtocolX (real audit patterns, accounting drift)
drill8_methodology.sol — Level 7: 0-Day Hunt Framework (no code, pure method)
```

## PROGRESSION MAP
```
Level 1 (drill 1-2): "Apa yang salah di 1 kontrak?"
  → Baca fungsi, trace state, cek invariant dasar
  → Skill: follow the money, access control check

Level 2 (drill 3): "Apakah ini beneran bug atau false alarm?"
  → Kenal pattern yang udah proven (MasterChef)
  → Skill: dismiss false alarms fast, focus on what's DIFFERENT

Level 3 (drill 4): "Apa yang terjadi di ANTARA 2 kontrak?"
  → Cross-contract state, oracle dependency, callback
  → Skill: draw money flow diagram, check trust boundaries

Level 4 (drill 5): "Apa yang terjadi kalau waktu berlalu?"
  → Multi-tx, epoch boundary, timing window
  → Skill: trace state across MULTIPLE transactions

Level 5 (drill 6): "Bagaimana governance bisa disalahgunakan?"
  → Governance attack, economic incentive misalignment
  → Skill: think like attacker with voting power

Level 6 (drill 7): "Bisa nemu bug yang diterima C4/Sherlock?"
  → Real patterns from accepted reports
  → Skill: accounting consistency, interest+fee interaction

Level 7 (drill 8): "Bisa nemu 0-day di protocol live?"
  → Full methodology, no code, pure framework
  → Skill: 6-phase hunt, PoC writing, profit calculation
```

## SKILL TREE
```
AMATIR (checklist mindset):
  □ Cek reentrancy
  □ Cek overflow
  □ Cek access control
  □ Cek signature replay
  → Result: "Semua safe" (karena bugnya bukan di pattern umum)

MENENGAH (hypothesis mindset):
  □ Trace money flow (masuk → keluar → di mana?)
  □ Cek accounting consistency (totalX == sum X?)
  □ Cek stale state (variabel mana yang ga update?)
  □ Kalkulasi profit (berapa untung attacker?)
  → Result: Nemu 1-2 bug per audit

AHLI (nose mindset):
  □ Baca 50 line → "bau bug"
  □ Trace 5 contract dalam 1 tx flow
  □ Pikir seperti attacker (bukan defender)
  □ Tulis PoC sebelum submit
  □ 80% false alarm, 20% real → tapi yang 20% itu CRITICAL
  → Result: Nemu bug yang orang lain miss
```

## DAILY ROUTINE (mulai besok)
```
07:00 — Baca 1 accepted bug report (C4/Sherlock/Immunefi)
        Reconstruct attack di kepala. "Would I find this?"

09:00 — Pick 1 contract from live bounty
        Apply 6-phase framework (drill 8)
        Write findings

12:00 — Run tools to verify manual findings
        Compare: manual vs tool. What did I miss? What did tool miss?

15:00 — Drill 1 contract from this series (re-do, timed)
        Target: beat your previous time

18:00 — Update pattern library
        New bug pattern? Add to list.
        False alarm? Why? What should I have seen?

Weekly: Submit 1 report minimum. Track acceptance rate.
```

## METRICS
```
Week 1:  0 findings submitted (learning phase)
Week 2:  1 LOW submitted (practice writing)
Week 3:  1 MEDIUM submitted (real finding)
Week 4:  2 findings submitted (building speed)
Month 2: 1 HIGH submitted (breakthrough)
Month 3: Consistent 1-2 findings per audit
Month 6: Expert nose. 0-day capability.
```
