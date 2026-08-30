# File Index

## Core (always loaded)
- `AGENTS.md` — router + rules R1-R10 + keyword weights
- `IDENTITY.md` — voice, speed tiers, character modes
- `SOUL.md` — flexibility doctrine, hard stops, operational rails
- `TIME.md` — 5-layer time awareness (system inject → tool call → cache → infer → disclose)
- `HEARTBEAT.md` — session continuity, time refresh, token discipline
- `TOOLS.md` — execution surface map, time tool specs
- `USER.md` — operator profile (customize)
- `MEMORY.md` — compaction rules
- `README.md` — install + overview
- `CONTRIBUTORS.md` — credits
- `CHANGELOG.md` — version history (v3.1 baseline → v4.0)
- `panduan.md` — operator usage guide (real-world examples)
- `DEPLOY.md` — VPS deployment guide (supersedes README quick-start) *(v4.0)*
- `STANDARD.md` — open SKILL.md format, progressive disclosure, cross-platform compat *(v4.1)*

## Skills — modular (load on trigger)
### Operational
- `skills/m0.md` — skill registry, reflection loop, escape hatch
- `skills/m1.md` — monetization, business ops, pricing
- `skills/m2.md` — VPS, deployment, nginx, pm2, screen, tmux
- `skills/m3.md` — content, copywriting, Indonesian voice, airdrop templates
- `skills/m4.md` — Telegram bots, anti-duplicate, webhook, multi-bot
- `skills/m5.md` — data handling, O(1) lookups, chunked reads
- `skills/m6.md` — integrations, webhooks, Midtrans, Xendit, WA Cloud
- `skills/m7.md` — AI multi-provider, streaming, fallback, tool use, caching
- `skills/m8.md` — DOCX/XLSX/PPTX/PDF, ReportLab, image processing
- `skills/m9.md` — frontend, Tailwind, Web3 connect, AOS/Framer
- `skills/m10.md` — Web3 ops, RPC fallback, mass wallets, mint, airdrop check
- `skills/m11.md` — security audit, skill safety, secret scan
- `skills/m12.md` — batch ops, parallel exec, rate-limit, resume-from-failure
- `skills/m13.md` — universal NFT minter, OpenSea/Manifold/Zora/Seadrop, auto-gas
- `skills/m14.md` — daily assistant: briefing & alert engine *(v4.0)*
- `skills/m15.md` — daily assistant II: watchdog, vault, multimodal, triage *(v4.0)*
- `skills/m16.md` — software engineering & general coding (backend/db/testing/scaffold) *(v4.0)*
- `skills/m17.md` — power pack: planner, swarm, automation, backtest, dashboard, voice, explain *(v4.0)*
- `skills/m18.md` — creative & media: ComfyUI, Manim, Excalidraw, ASCII video, design systems, slides, aesthetic judgment *(v4.1)*
- `skills/m19.md` — desktop & physical: macOS bg control (no cursor steal), Isaac Sim/Omniverse, scene prep, mobility *(v4.1)*
- `skills/m20.md` — humanizer & brand voice: AI-tell removal, brand voice adaptation *(v4.1)*
- `skills/m21.md` — enterprise & defensive: Azure/KQL troubleshooting, Mini-HIDS auto-firewall *(v4.1)*
- `skills/m22.md` — scientific & deep research: AI-Q dispatch, tool workflows, hypothesis/experiment design *(v4.1)*
- `skills/m23.md` — executive function & neurodivergent: task breakdown, context-switch, prioritization *(v4.1)*
- `skills/m24.md` — MCP-builder + prompt engineering: scaffold MCP server, audit/fix prompts *(v4.1)*
- `skills/m25.md` — compliance, CI/CD & code migration: regulatory review, pipelines, language porting *(v4.1)*
- `skills/m26.md` — product & spec workflows: Grill-Me, To-PRD, To-Issues, TDD, internal-comms *(v4.1)*
- `skills/m27.md` — content strategy & social media: pillars, calendar, platform adapter, hooks, thread/carousel/reels *(v4.1)*
- `skills/m28.md` — copywriting & writing mastery: AIDA/PAS/CHEF frameworks, SEO, storytelling, localization/RTL *(v4.1)*
- `skills/m29.md` — content research, analytics & pipeline: trend/competitor, social listening, A/B, full pipeline *(v4.1)*

### Hermes Crypto Agent (deep refs, loaded via H1-H7 dispatch)
- `skills/hermes/SKILL.md` — hermes principles + capability index
- `skills/hermes/DISPATCH.md` — bridge to v3 router, env var checklist, safety rails
- `skills/hermes/README.md` — install + dependency list
- `skills/hermes/references/wallets.md` — multi-chain wallet gen + import (EVM/Solana/Sui/Aptos/TON)
- `skills/hermes/references/swap.md` — 1inch + Jupiter + DEX router fallback
- `skills/hermes/references/nft.md` — Seaport / Blur / Reservoir / Magic Eden / Tensor
- `skills/hermes/references/sniping.md` — PairCreated listener + honeypot.is + GoPlus gate
- `skills/hermes/references/airdrop_automation.md` — multi-wallet runner + jitter + resume
- `skills/hermes/references/bridge.md` — LI.FI + Stargate + Across + native L1↔L2
- `skills/hermes/references/defi.md` — Aave V3 / Lido / GMX V2 / Hyperliquid / Pendle
- `skills/hermes/references/web3_connect.md` — SIWE / WalletConnect v2 / EIP-712 / EIP-1271 / ENS
- `skills/hermes/references/monitoring.md` — mempool + smart money + NFT whale + contract listener (12 sections)
- `skills/hermes/references/security.md` — encrypted vault (scrypt + Fernet)
- `skills/hermes/references/governor.md` — spend governor / circuit breaker *(v4.0)*
- `skills/hermes/references/browser.md` — Playwright dApp automation + governed signing *(v4.0)*
- `skills/hermes/references/contract_read.md` — universal multi-chain contract reader *(v4.0)*
- `skills/hermes/references/contract_write.md` — universal contract write, gated via governor *(v4.0)*
- `skills/hermes/references/deploy.md` — crypto dev: compile/test/deploy/verify, CREATE2 *(v4.0)*
- `skills/hermes/scripts/` — 10 Python templates (wallet_manager, swap_engine, nft_engine, bridge_engine, web3_connect, monitoring, monitoring_advanced, airdrop_runner, **governor**, **mev**, **browser_engine** *(v4.0)*)

### Meta
- `skills/x1.md` — self-audit, system refinement
- `skills/x2.md` — deep decomposition, strategy, pre-mortem
- `skills/x3.md` — debug, error pattern library
- `skills/x4.md` — self-improvement & autonomous problem-solving + instinct extraction *(v4.0, v4.1)*
- `skills/x5.md` — agentic eval, self-critique & variance testing *(v4.1)*
- `skills/x6.md` — systematic debugging (4-phase RCA→Pattern→Hypothesis→Fix) + auto-debug loop *(v4.1)*
- `skills/x7.md` — problem shaping, brainstorming sign-off, decision support w/ uncertainty *(v4.1)*

## Tools *(v4.0)*
- `tools/skill_integrity.py` — SHA-256 (+Ed25519) skill manifest generate/verify
- `tools/memory_engine.py` — compounding memory, keyless local recall *(v4.0)*
- `tools/reflection.py` — self-improvement loop: learn / auto-fix / gated proposals *(v4.0)*
- `tools/model_registry.py` — dynamic LLM model registry, encrypted keys, cascade *(v4.0, frozen)*
- `tools/planner.py` — NL workflow planner *(v4.0, frozen)*
- `tools/swarm.py` — multi-agent swarm orchestrator *(v4.0, frozen)*
- `tools/automation.py` — event-driven automation engine *(v4.0, frozen)*
- `tools/skill_forge.py` — self-extending skill proposals *(v4.0, frozen)*
- `tools/backtest.py` — strategy backtester *(v4.0)*
- `tools/dashboard.py` — live web dashboard generator *(v4.0)*
- `tools/voice.py` — voice conversation mode (STT→LLM→TTS) *(v4.0)*
- `tools/explain.py` — explainability / audit trail report *(v4.0)*
- `tools/briefing.py` — proactive daily briefing (composes memory/alerts/proposals) *(v4.0)*
- `tools/alerts.py` — conditional alert engine, persistent triggers + dedup *(v4.0)*
- `tools/watchdog.py` — self-healing process monitor, rate-limited restart *(v4.0, frozen)*
- `tools/vault.py` — snippet/address vault + macros *(v4.0, frozen)*
- `tools/multimodal.py` — voice transcription (Whisper) + screenshot vision *(v4.0)*
- `tools/triage.py` — inbox/notification triage & prioritization *(v4.0)*
- `tools/eval.py` — agentic eval, self-critique & variance testing *(v4.1)*
- `tools/humanizer.py` — AI-tell detector + deterministic rewriter + brand voice *(v4.1)*
- `tools/hids.py` — Mini-HIDS: log → detect → auto-firewall (allowlist+TTL) *(v4.1, frozen)*
- `tools/desktop_control.py` — macOS background control, no cursor steal *(v4.1, frozen)*
- `tools/scene_prep.py` — USD scene assembly + ComfyUI graph patch *(v4.1)*
- `tools/skill_market.py` — skills.sh marketplace → quarantine (audit before activate) *(v4.1, frozen)*
- `tools/mcp_builder.py` — scaffold MCP server (Python/TS) + prompt auditor *(v4.1)*
- `tools/prd.py` — To-PRD / To-Issues structurer *(v4.1)*
- `tools/research_q.py` — deep research dispatcher (AI-Q style, cited) *(v4.1)*
- `tools/content.py` — social content scaffolder: calendar, platform-adapt, thread/carousel/reels, repurpose *(v4.1)*
- `SKILLS.lock` — integrity manifest, verified at boot

## Memory
- `memory/YYYY-MM.md` — monthly rolling log
