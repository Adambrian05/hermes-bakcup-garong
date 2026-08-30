# CHANGELOG — SUPERAGENT OPENCLAW EDITION

Version history. Baseline **v3.1** (2026-05-25) → **v4.0** (2026-06-03) → **v4.1** (2026-06-04).

---

## v4.1 — CAPABILITY EXPANSION (2026-06-04)

Rilis aditif. Identitas inti **tetap crypto + dev** (IRONCLAW); semua yang baru = **modul opsional** yang load on-trigger dan gak ganggu karakter utama. Safety machinery v4.0 (Spend Governor, FROZEN_PATHS, SKILLS.lock, reflection gate) **utuh & diperluas**. 7 skill + 6 tool baru.

### 🧠 Self-improvement & eval (extend x-cluster)
- **x5 — Agentic Eval & Self-Critique**: eval terstruktur (Case/assert), **variance testing** (jalanin task N× → ukur konsistensi; <0.95 = jangan otomasi), self-critique adversarial sebelum output berisiko. → `skills/x5.md`, `tools/eval.py`
- **x6 — Systematic Debugging**: 4-fase RCA → Pattern → Hypothesis → Fix + **auto-debug loop** (rank hipotesis by likelihood×murah-diuji, uji, bantah, ulang). Untuk bug yang gak ada di pustaka x3. → `skills/x6.md`
- **Instinct extraction** (x4): lesson berulang-&-kebukti dipadatkan jadi reflex; dikawal eval (variance jelek → gak boleh jadi reflex). → `skills/x4.md`

### 🎨 Creative & media (m18)
- ComfyUI (API/headless, graph patch), **Manim** animasi math, **Excalidraw** diagram programmatic, ASCII/retro video (chafa+ffmpeg), web design systems (Stripe/Linear/Vercel token), Felo-style content→deck, **aesthetic judgment** checklist. → `skills/m18.md`, `tools/scene_prep.py`

### 🤖 Desktop & physical (m19)
- **macOS native control — background-first, NO cursor steal** (AppleScript/Accessibility, gak ngerebut pointer/fokus operator). NVIDIA **Isaac Sim/Omniverse** (headless), **scene preparation** (USD assembly + domain randomization), mobility (Isaac Lab/ROS2; real-robot = R9 gate). → `skills/m19.md`, `tools/desktop_control.py`

### ✍️ Humanizer & brand voice (m20)
- AI-tell detector (heuristik keyless) + rewrite deterministik + brand voice adaptation. Jujur soal batas (bukan alat ngecoh detektor akademik). → `skills/m20.md`, `tools/humanizer.py`

### 🛡 Enterprise & defensive (m21)
- **Azure/KQL** troubleshooting (Log Analytics/Sentinel, read-only investigasi), **Mini-HIDS** auto-firewall dari log (allowlist + TTL + dry-run + alert; R9 gate aktivasi). Defensif murni. → `skills/m21.md`, `tools/hids.py`

### 🧭 Soft & human-level (x7)
- **Problem shaping** (tujuan kabur → subtask presisi), **brainstorming + sign-off** workflow, **decision support dengan ketidakpastian** (known/assumed/unknown + confidence + one-way vs two-way door), context design. Sengaja memperlambat HANYA saat kabur/taruhan tinggi. → `skills/x7.md`

### 🧩 Orchestration
- **Skill marketplace (skills.sh)** — `tools/skill_market.py`: unduh ke **quarantine**, WAJIB audit (m11), operator pindah + re-lock. Tidak pernah auto-install+auto-activate (friksi = fitur).
- Multi-agent orchestration & role specialization sudah ada di v4.0 (`swarm.py`/m17) — tetap.

### 🔒 Safety
- `FROZEN_PATHS` diperluas: `hids.py`, `desktop_control.py`, `skill_market.py` (surface OS/firewall/desktop/marketplace) gak bisa diedit loop self-improve.
- Aksi baru yang nyentuh OS/desktop/robot fisik/firewall → **R9 gate** (terpisah dari governor dana).
- `SKILLS.lock` diregenerasi (version 4.1, file_count baru). Semua tool baru import-clean (Python 3.9+, `from __future__ import annotations`).

### Expansion wave 2 — meta, scientific, product & enterprise

Penambahan lanjutan (tetap v4.1, tetap modul opsional crypto-first). 5 skill + 3 tool + 1 doc meta.

- **m22 — Scientific & Deep Research**: dispatcher riset AI-Q (report bersitasi), scientific tool workflows (ToolUniverse-style), hypothesis generation & experimental design. Privasi: query ke server eksternal → sanitize. → `skills/m22.md`, `tools/research_q.py`
- **m23 — Executive Function & Neurodivergent**: task breakdown anti-overwhelm (ADHD-style), context-switch + breadcrumb resume (via memory_engine), prioritization saat overwhelmed. Grounded di executive-function, bukan motivational fluff. → `skills/m23.md`
- **m24 — MCP-Builder & Prompt Engineering**: scaffold MCP server (Python FastMCP / TS sdk) dgn best practices, prompt auditor (deteksi+fix masalah prompt, eval-driven). → `skills/m24.md`, `tools/mcp_builder.py`
- **m25 — Compliance, CI/CD & Code Migration**: regulatory review (advisory, bukan legal advice), brand-guidelines enforcement, CI/CD pipeline, code-migrator antar bahasa/framework (test-first). → `skills/m25.md`
- **m26 — Product & Spec Workflows**: Grill-Me (idea kabur→tajam), To-PRD, To-Issues, TDD superpower, internal-comms. → `skills/m26.md`, `tools/prd.py`
- **Extend**: x5 + `eval.py` → **LLM-as-judge** production-grade (rubrik + panel + judge variance-check); m19 → **Cosmos Physical AI** + **meta-actions** (STOP > deselerasi > perintah, refleks keselamatan fisik); m18 → canvas design & visual art (Pillow/SVG); x7 → handoff Grill-Me ke m26; x4 → instinct extraction (wave 1).
- **`STANDARD.md`** (baru): membakukan emerging meta trends yang **sudah** jadi sifat sistem — progressive disclosure, open SKILL.md format, cross-platform (Claude/Cursor/Codex/Gemini), marketplace. Bukan fitur baru, dokumentasi prinsip.
- **`panduan.md`**: section baru "Skill non-crypto (v4.1)" + cheat-sheet rows untuk semua skill v4.1.

### Expansion wave 3 — content, social media & marketing

Domain marketing/konten sosial (proposal kategori 18–24) + pendalaman sains & embodied AI (16–17). 3 skill + 1 tool + extends. Tetap v4.1, tetap opsional crypto-first.

- **m27 — Content Strategy & Social Media**: content pillars/audience/positioning, content calendar generator, platform-specific adapter (X/LinkedIn/IG/TikTok), viral hook & scroll-stopper, caption+hashtag optimizer, thread/carousel/reels writer. → `skills/m27.md`, `tools/content.py`
- **m28 — Copywriting & Writing Mastery**: frameworks (AIDA/PAS/BAB/4P/CHEF/70-20-10), SEO writer, storytelling/narrative, multilingual & localization (termasuk RTL). → `skills/m28.md`
- **m29 — Content Research, Analytics & Pipeline**: trend/competitor research, audience insight & social listening, performance analyzer, A/B variant, best-time-to-post, engagement handler, **full content pipeline** (research→draft→visual→schedule→analyze) + cross-platform publisher + human-in-the-loop + repurposing. → `skills/m29.md`, `tools/content.py`
- **Extend m22** — scientific domain library dispatch (genomics/docking/MD/geospatial/time-series via library tervalidasi, bukan reimplementasi), Hugging Science (HF Hub discovery), multi-step pipeline literature→paper drafting, K-Dense BYOK (local co-scientist).
- **Extend m19** — **VLA** (Vision-Language-Action: perceive→reason→act), multimodal reasoning (text+vision+audio+action), scene understanding/object manipulation — semua di bawah meta-action safety.
- **Extend m18** — content repurposing, infographic/carousel design, image-prompt engineer (Midjourney/Flux/Canva).
- **`content.py`** — scaffolder deterministik (kalender, adapt, thread/carousel/reels, repurpose); analitik/best-time bertanda 'estimate' kalau tanpa data real (jujur, gak ngarang angka).
- **`panduan.md`** — section "Konten & social media (v4.1)" + cheat-sheet rows m27–m29.
- **Kejujuran desain**: "141+ scientific tools" = dispatch ke library matang + verifikasi, BUKAN klaim built-in palsu. Analitik konten butuh data real platform; tanpa itu heuristik bertanda estimasi.

### Ringkasan angka
- 37 skill (m0–m29 + x1–x7), 28 tool, 15 reference Hermes (tak berubah dari v4.0), +`STANDARD.md`.
- Semua skill baru = modul opsional, on-trigger; always-on token budget tetap ~3.5k (progressive disclosure).

---

## v4.0 — OPENCLAW EDITION (2026-06-03)

Major release. Dari baseline v3.1, v4.0 nambahin lapisan keamanan/governance penuh, kemampuan belajar sendiri, suite asisten harian, tooling smart-contract lengkap (baca/tulis/deploy), manajemen LLM dinamis, "power pack" orkestrasi, dan skill software-engineering umum. Semua aksi yang nyentuh dana lewat **Spend Governor**; file kritis dijaga **FROZEN_PATHS**.

### 🛡 Keamanan & governance
- **Spend Governor** — circuit breaker di tiap tx: cap per-tx / harian / sesi (USD), batas slippage, auto-HALT pas gas spike / rate-limit, simulation gate, kill-switch manual. `auto_confirm` matiin prompt, **bukan** governor. → `skills/hermes/references/governor.md`, `scripts/governor.py`
- **MEV protection** — swap & snipe lewat private relay (Flashbots Protect / MEV Blocker), bukan mempool publik; fallback-with-warning yang jujur. → `scripts/mev.py`
- **Skill integrity verify** — manifest SHA-256 (+ opsional Ed25519) dicek saat boot; file skill yang berubah/baru/hilang nahan operasi on-chain sampai diaudit. → `tools/skill_integrity.py`, `SKILLS.lock`
- **FROZEN_PATHS** — file kritis (SOUL, AGENTS, governor, integrity, reflection, vault, watchdog, model_registry, planner, swarm, automation, skill_forge) **gak bisa diedit** oleh loop self-improve. Di-enforce di kode (`guard_write`).

### 🧠 Self-improvement
- **Compounding memory** — recall lokal keyless (SQLite); memori berguna di-reinforce & makin sering muncul. → `tools/memory_engine.py`
- **Reflection loop (x4)** — belajar dari masalah berulang, auto-fix isu ops yang reversible (allowlist only), tulis *proposal* upgrade buat di-review operator; ada audit log. → `skills/x4.md`, `tools/reflection.py`

### 📅 Asisten harian (m14, m15)
- **Daily briefing** + **alert engine** kondisional (price/gas/wallet/claim, DexScreener keyless, cooldown-dedup). → `tools/briefing.py`, `tools/alerts.py`
- **Watchdog** self-healing, **vault** snippet/alamat + macro, input **voice** (Whisper lokal) + **screenshot** (vision), **triage** inbox. → `tools/watchdog.py`, `tools/vault.py`, `tools/multimodal.py`, `tools/triage.py`

### 🔗 Tooling smart-contract
- **Universal contract reader** — multi-chain, ABI auto-fetch (Sourcify/Blockscout, keyless), call read function apa pun, deteksi ERC-20/721/1155, resolve proxy EIP-1967. Read-only. → `references/contract_read.md`, `scripts/contract_reader.py`
- **Universal contract writer** — kirim tx ke fungsi apa pun, gated penuh (sim → screen → governor → konfirmasi → record). → `references/contract_write.md`, `scripts/contract_writer.py`
- **Crypto developer** — compile/test (Foundry), deploy (governor-gated), verify (Sourcify keyless), CREATE2 deterministic multi-chain. → `references/deploy.md`, `scripts/deploy_engine.py`

### 🧩 Manajemen LLM (m7 extended)
- **Dynamic model registry** — `add model` satu perintah (name/api_key/base_url/model/kind/priority); OpenAI-compatible + Anthropic; key dienkripsi (scrypt+Fernet), redacted, masuk cascade R7 dengan fallback otomatis. → `tools/model_registry.py`

### ⚙️ Power Pack (m17)
- **NL workflow planner** (tujuan → plan multi-step gated), **multi-agent swarm** (lane specialist paralel + pemisahan key), **skill forge** (draft skill baru → proposal), **automation engine** (WHEN/THEN), **backtester**, **live dashboard**, **voice conversation mode** (STT→LLM→TTS), **explainability**. → `skills/m17.md` + `tools/{planner,swarm,skill_forge,automation,backtest,dashboard,voice,explain}.py`

### 💻 Software engineering (m16)
- **Skill coding umum** — backend API (FastAPI/Express/Go/Django), database (skema/migration/ORM), testing default (pytest/vitest/go test), scaffolding (struktur + Dockerfile + CI), multi-bahasa (Python/TS/Go/Rust), refactoring & code review, CLI/library, git workflow. Komplemen m9 (frontend) + m2 (deploy) + x3 (debug) = full-stack. → `skills/m16.md`

### 🛠 Tooling & docs
- **`.env.example`** — semua env var (50+) dikelompokin, ditandain wajib/opsional/gratis/berbayar.
- **`DEPLOY.md`** — panduan deploy VPS yang akurat (menggantikan quick-start lama).

### Ringkasan angka
- 22 skill (m0–m17 + x1–x4), ~30+ script Python, 15 reference Hermes.
- Lapisan baru: governance, self-improve, daily assistant, contract read/write/deploy, model registry, power pack, software engineering.

---

## v3.1 — baseline (2026-05-25)

Rilis dasar yang jadi titik tolak v4.0.

### Headline changes
- 🆕 **3 new skills**: m10 Web3, m11 Security, m12 Batch
- 🆕 **NFT minter skill**: m13 (universal mint with auto-gas, OpenSea/Manifold/Zora)
- 🆕 **Hermes Crypto Agent absorbed**: full deep-crypto layer at `skills/hermes/` (10 refs + 8 Python templates)
- ⏰ **TIME.md** — 5-layer time-awareness architecture (system inject → tool → cache → infer → disclose). No more time-blind hallucination on deadlines/cron/vesting/claim windows.
- ⚡ **Smarter router**: priority-weighted keywords, multi-skill orchestration, H1-H7 hermes dispatch
- 🛠 **m4 Telegram** now production-grade (anti-duplicate, webhook mode, multi-bot)
- 🤖 **m7 AI** rewritten: streaming, function calling, provider fallback chain, cost tracking
- 🖥 **m2 VPS** expanded: systemd, tmux, nginx security headers, backup automation
- 🔐 **Tighter SOUL**: 2 hard stops only, permissive on grey-area + operational rails for crypto ops
- 🇮🇩 **m3 voice**: airdrop template now matches operator's exact format

### New files
| File | Why |
|---|---|
| `skills/m10.md` | Web3 ops: RPC fallback, BIP39 wallet gen, NonceManager, simulate→send→wait, eligibility O(1) checker, mass farming with p-limit, multicall, Solana basics. |
| `skills/m11.md` | Security audits: skill-file injection checklist, Solidity red flags, suspicious package signals, secret leak detection, OpenClaw-specific safety. |
| `skills/m12.md` | Batch patterns: p-limit, asyncio.gather, token bucket, progress tracking, resume-from-failure checkpoint. |
| `skills/m13.md` | **Universal NFT minter**: parse OpenSea/Manifold/Zora URL atau raw address, auto-detect mint fn + price, auto-gas, simulate→send→wait. Combo m12 buat mass mint. |
| `skills/hermes/*` | **Hermes Crypto Agent** — deep-crypto skill (SKILL.md + references + Python templates). H1-H7 dispatch (swap/bridge/defi/sniping/mempool/NFT/SIWE). EVM + Solana + Sui + Aptos + TON. |
| `TIME.md` | **5-layer time-awareness**. Solves LLM time-blindness. Strict mode buat crypto cron/deadline/vesting/claim. Contributor: 👁⃤Fiⱥnͥ.ⱥsͣsͫⱥn 𓂀 ([@fianassan25](https://t.me/fianassan25)). |
| `CONTRIBUTORS.md` | Credits — CVC Owner + Member contributions. |
| `panduan.md` | Operator usage guide (12 sections + cheat sheet) dengan contoh Hermes nyata. |
| `CHANGELOG.md` | This file. |
| `INDEX.md` | One-line index of all files. |

### Upgraded files (ringkas)
- **`AGENTS.md`** — rules R1-R10, provider cascade (R7), multi-skill orchestration (R8), token economy (R9), escape hatch (R10), weighted keyword table EN+ID, crypto trigger cluster.
- **`IDENTITY.md`** — 3 response speed tiers, Web3 operator voice, anti motivational filler.
- **`SOUL.md`** — 2 hard stops (CSAM, mass-casualty weapons), single risk gate, doktrin permisif buat crypto ops.
- **`HEARTBEAT.md`** — continuity triggers, token discipline (warn 60% / compact 80%), resume protocol.
- **`TOOLS.md`** — agent-side vs operator-side, OpenClaw streaming config bug (`streaming: false` boolean).
- **`USER.md`** — template fill-in + trigger phrases + domain focus.
- **`MEMORY.md`** — compact format (1 baris/entry), 30-day window, monthly compaction.
- **`skills/m0–m9, x1–x3`** — registry diperluas, reflection loop, escape hatch, crypto monetization (m1), VPS bootstrap (m2), airdrop template + CT voice (m3), Telegram rewrite anti-duplicate (m4), O(1) lookup (m5), circuit breaker (m6), AI rewrite + fallback (m7), PDF hyperlinks (m8), Web3 UI (m9), audits (x1), pre-mortem (x2), error library (x3).

### Known good combos (multi-skill load)
- "bikin bot Telegram + bayar TON" → m4 + m6 + m10
- "mass mint 300 wallet" → m13 + m12 + m10
- "swap 1000 USDC ke ETH di base" → H1 (hermes/swap.md) + m10
- "farming airdrop layerzero 50 wallet" → H2 + H1 + m12
- "buat landing page web3" → m9 + m10
