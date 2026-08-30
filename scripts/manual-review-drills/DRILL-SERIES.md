# MANUAL REVIEW DRILL SERIES
# From Checklist Mindset → Hypothesis Mindset → Expert Nose
# Rules: NO TOOLS. Otak + kertas only. Timer per drill.

## PROGRESSION
```
Level 1: Single contract, 1 bug, obvious pattern     (5 min)
Level 2: Single contract, multi-actor, economic       (10 min)
Level 3: Two contracts, cross-contract state          (15 min)
Level 4: Multi-contract, multi-tx, timing             (20 min)
Level 5: Full protocol, governance + economic + cross (30 min)
Level 6: Real audit code (C4/Sherlock accepted bugs)  (30 min)
Level 7: 0-day hunt on live protocol                  (60 min)
```

## METHODOLOGY (per drill)
```
1. READ (2 min): Skim semua fungsi. Siapa actors? Uang flow ke mana?
2. SNIFF (3 min): "Bau" apa yang lo cium? Tulis hipotesis SEBELUM buktiin.
3. TRACE (5 min): Trace 1 transaction end-to-end. State before → after.
4. BREAK (5 min): Coba pecahkan invariant lo sendiri.
5. CALCULATE (3 min): Kalau exploit ada, berapa profit? Gas cost?
6. VERIFY (2 min): Sekarang boleh pake tool buat konfirmasi.
```

## SCORING
```
+3  Nemu bug tanpa hint
+2  Nemu bug dengan hint
+1  Nemu bug setelah dikasih tau
 0  Ga nemu

Bonus:
+1  Nemu severity yang tepat
+1  Bisa kalkulasi profit
+1  Nemu >1 bug
+2  Nemu bug yang ga ada di answer key
```
