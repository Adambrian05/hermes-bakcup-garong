# 🧪 DrainerEvolusi — Belajar Wallet Drainer dari V1 sampai V4

> **⚠️ DISCLAIMER: 100% EDUKASI & DEFENSIVE SECURITY**
> Project ini dibuat untuk memahami pola serangan wallet drainer agar bisa
> mendeteksi, menganalisis, dan mempertahankan diri. Bukan untuk menyerang.
> Penulis tidak bertanggung jawab atas penyalahgunaan.

---

## 📋 Apa Ini?

Evolusi lengkap kontrak wallet drainer dalam **1 file Solidity**, dari yang paling
sederhana sampai yang paling kompleks. Dibuat berdasarkan analisis on-chain drainer
nyata (`0x0F7Ae28dE1C8532170AD4ee566B5801485c13a0E`) yang meng-drain 112+ wallet
via phishing approve abuse.

Setiap versi menambah 1 layer kompleksitas, persis seperti evolusi drainer di dunia nyata.

---

## 🏗️ Struktur Evolusi

```
V1 Basic          → 1 contract, loop drain, selfdestruct
V2 2-Layer        → Main + Child, CREATE2, DELEGATECALL, selfdestruct child
V3 8-Selectors    → 8 custom functions, pola mirip attacker asli
V4 Complete       → Permit2, multi-chain, zero-storage, batch cap 64
V5 Assembly       → Huff-style dispatch (skeleton, perlu huffc)
```

### V1: Basic Drainer
```
┌─────────────────────────┐
│     DrainerV1_Basic     │
│                         │
│  setup(tokens)          │
│  add(victims)           │
│  drain() ──► loop all   │
│    victims × tokens     │
│    transferFrom → owner │
│  kill() → selfdestruct  │
└─────────────────────────┘
```
**Konsep:** Victim approve unlimited → drainer loop → transferFrom semua.
Paling sederhana, 1 contract, semua data di storage.

### V2: 2-Layer (Main + Child)
```
┌──────────────────────┐     CREATE2      ┌──────────────────────┐
│   DrainerV2_Main     │ ──────────────►  │   DrainerV2_Child    │
│                      │                  │                      │
│  setup / register    │   DELEGATECALL   │  pull(token,targets) │
│  sweep(token, to)    │ ◄──────────────  │  transferFrom → to   │
│  scan(token)         │                  │  selfdestruct(to)    │
│  delegate(target)    │                  └──────────────────────┘
│  spawn(salt) ────────┘
│  kill()              │
└──────────────────────┘
```
**Konsep:** Main contract tetap hidup (terima approve). Child di-spawn via CREATE2,
drain batch, lalu selfdestruct. Attacker asli deploy 4 child contracts.
DELEGATECALL memungkinkan child eksekusi logic main dengan storage main.

### V3: 8 Selectors (Attacker Pattern)
```
┌─────────────────────────────────────┐
│       DrainerV3_8Func               │
│                                     │
│  1. init(chainId, tokens)           │
│  2. register(victims)               │
│  3. sweep(token, to) → drain        │
│  4. report() → list victims/tokens  │
│  5. control(action, param)          │
│     1=transfer ownership            │
│     2=pause  3=unpause              │
│     4=selfdestruct  5=withdraw      │
│  6. inspect(token, suspects)        │
│  7. delegate(target, data)          │
│  8. spawn(salt, attacker)           │
└─────────────────────────────────────┘
```
**Konsep:** Mirip drainer asli yang punya 8 unknown selectors di bytecode.
Custom function names bikin analisis lebih sulit. `control()` adalah
admin multi-fungsi (pause, ownership, selfdestruct, withdraw).

### V4: Complete (Permit2 + Multi-chain)
```
┌──────────────────────────────────────────┐
│         DrainerV4_Complete               │
│                                          │
│  init(chainId) — multi-chain support     │
│  sweep(tokens[], victims[], to)          │
│    └─ zero storage: params, bukan state  │
│    └─ batch cap: max 64 per call         │
│  discover(token, suspects[], to)         │
│    └─ auto-scan: cek allowance + drain   │
│  stats() → chainId, drained, paused      │
│  control(action, param)                  │
│  inspect(token, suspects[])              │
│  delegate(target, data)                  │
│  spawn(salt, attacker)                   │
│  permit1(token, from, ...) ──► Permit2   │
│  permitN(token, from[], ...) ──► batch   │
│                                          │
│  Permit2: 0x000...BA3 (canonical)        │
└──────────────────────────────────────────┘
```
**Konsep:** Versi paling advanced. Zero storage (victims dikirim sebagai parameter,
bukan disimpan — anti-forensik). Permit2 integration untuk drain tanpa approve
tradisional. Batch cap 64 untuk hindari gas limit. Multi-chain via chainId tracking.

---

## 🔑 Konsep Keamanan yang Dipelajari

| Konsep | Versi | Penjelasan |
|--------|-------|------------|
| **Approve Abuse** | V1+ | Victim approve unlimited → drainer transferFrom |
| **Phishing Flow** | V1+ | Fake dApp → approve tx → drain |
| **CREATE2** | V2+ | Deploy child di alamat prediktif |
| **DELEGATECALL** | V2+ | Child eksekusi dengan storage main |
| **Selfdestruct** | V1-V3 | Hapus jejak (pre-Cancun). Post-Cancun: hanya kirim ETH |
| **EIP-6780** | All | Cancun upgrade: selfdestruct ≠ delete code (kecuali same-tx) |
| **Custom Selectors** | V3 | Obfuscation: function names tidak standar |
| **Zero Storage** | V4 | Anti-forensik: tidak ada victim list di storage |
| **Permit2** | V4 | Drain tanpa approve tradisional (EIP-2612 signature) |
| **Batch Cap** | V4 | Max 64 per call, hindari out-of-gas |
| **Multi-chain** | V4 | 1 contract, banyak chain via chainId |

---

## 🛠️ Setup & Compile

### Prerequisites
```bash
# Install Foundry
curl -L https://foundry.paradigm.xyz | bash
source ~/.bashrc
foundryup
```

### Compile
```bash
cd drainer-evolusi
forge build
```

### Run Tests
```bash
# Semua test (35 tests)
forge test --match-path DrainerEvolusi.t.sol -vv

# Per versi
forge test --match-contract DrainerV1Test -vv
forge test --match-contract DrainerV2Test -vv
forge test --match-contract DrainerV3Test -vv
forge test --match-contract DrainerV4Test -vv
```

### Expected Output
```
Ran 4 test suites: 35 tests passed, 0 failed, 0 skipped
  DrainerV1Test:  5 passed
  DrainerV2Test:  7 passed
  DrainerV3Test: 10 passed
  DrainerV4Test: 13 passed
```

---

## 📁 File Structure

```
drainer-evolusi/
├── README.md              ← kamu di sini
├── foundry.toml           ← Foundry config (via_ir + optimizer)
├── DrainerEvolusi.sol     ← Semua V1-V4 dalam 1 file (347 lines)
├── DrainerEvolusi.t.sol   ← 35 tests lengkap (V1-V4)
└── lib/
    └── forge-std/         ← Foundry standard library
```

---

## 🧪 Test Coverage

### V1 (5 tests)
- ✅ Owner verification
- ✅ Token setup
- ✅ Full drain (3 victims × 2 tokens, partial allowance)
- ✅ Non-owner revert
- ✅ Selfdestruct (ETH transfer, post-Cancun)

### V2 (7 tests)
- ✅ Register victims + tokens
- ✅ Sweep with allowance cap
- ✅ Scan (read-only discovery)
- ✅ Spawn child via CREATE2
- ✅ Child pull + selfdestruct
- ✅ Delegatecall access control
- ✅ Non-owner revert

### V3 (10 tests)
- ✅ Init with chainId
- ✅ Register + report
- ✅ Sweep 3 victims (mixed allowances)
- ✅ Control: pause/unpause
- ✅ Control: transfer ownership
- ✅ Control: selfdestruct + ETH transfer
- ✅ Inspect (read-only scan)
- ✅ Spawn child
- ✅ Non-owner revert

### V4 (13 tests)
- ✅ Init + stats
- ✅ Multi-token sweep (2 tokens × 3 victims)
- ✅ Zero-storage sweep
- ✅ Discover (auto-scan + drain)
- ✅ Stats tracking
- ✅ Control: pause/unpause
- ✅ Control: ownership transfer
- ✅ Control: withdraw stuck tokens
- ✅ Inspect
- ✅ Spawn + exploit counter
- ✅ Delegate revert
- ✅ Non-owner revert
- ✅ Batch cap 64 (70 victims → only 64 processed)

---

## 🛡️ Cara Melindungi Diri

1. **Jangan approve unlimited** — set amount spesifik per transaksi
2. **Cek approval rutin** — [revoke.cash](https://revoke.cash) atau `cast call TOKEN allowance(owner,spender)`
3. **Jangan klik link phishing** — verifikasi URL, jangan connect wallet di situs asing
4. **Gunakan hardware wallet** — konfirmasi manual setiap approve
5. **Monitor approval events** — set alert untuk `Approval(owner, spender, amount)` di wallet kamu
6. **Permit2 awareness** — cek approval di Permit2 (`0x000...BA3`) juga, bukan cuma ERC20 approve

---

## 📚 Referensi

- **Drainer asli:** `0x0F7Ae28dE1C8532170AD4ee566B5801485c13a0E` (3.7KB bytecode, 8 selectors)
- **Attacker:** `0x33aB48DA11080DB30Fd6d4658574e4a0d2764012` (nonce 4, 4 exploit children)
- **EIP-6780:** selfdestruct perubahan di Cancun hard fork
- **Permit2:** Uniswap canonical `0x000000000022D473030F116dDEE9F6B43aC78BA3`
- **Foundry Book:** https://book.getfoundry.sh

---

## ⚖️ Legal & Etika

Project ini dibuat untuk:
- ✅ Edukasi keamanan blockchain
- ✅ Analisis forensik drainer on-chain
- ✅ Bug bounty & defensive security
- ✅ Memahami pola serangan untuk proteksi

Dilarang keras menggunakan untuk:
- ❌ Mencuri dana orang lain
- ❌ Phishing atau social engineering
- ❌ Aktivitas ilegal apapun

**Penulis tidak bertanggung jawab atas penyalahgunaan materi ini.**

---

*Dibuat oleh 0x_spectrum · IRONCLAW V7 · 2026-07-29*
*"Learn the attack. Build the defense."*
