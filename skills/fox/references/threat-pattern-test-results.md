# Threat Pattern Test Results

## Overview
Hermes Agent has input scanning via `threat_patterns.py` that detects prompt injection, C2 frameworks, and exfiltration attempts.

## Test Results (2026-08-27)
- **Detection Rate:** 96.7% (29/30 test cases)
- **Missed Case:** `deception_hide` pattern with "mention" instead of "tell"

## Pattern Categories

### Scope: "all" (always applied)
- `prompt_injection` — "ignore previous instructions"
- `sys_prompt_override` — "system prompt override"
- `disregard_rules` — "disregard your rules"
- `bypass_restrictions` — "act as if you have no restrictions"
- `html_comment_injection` — HTML comment injection
- `hidden_div` — hidden div injection
- `translate_execute` — translate and execute
- `deception_hide` — "do not tell the user" (misses "mention")

### Scope: "context" (context files + tool results)
- `role_hijack` — "you are now a..."
- `role_pretend` — "pretend to be..."
- `leak_system_prompt` — "output system prompt"
- `remove_filters` — "respond without restrictions"
- `fake_update` — "you have been updated to"
- `identity_override` — "name yourself X"

### Scope: "strict" (memory writes + skill installs)
- `hardcoded_secret` — api_key/token/secret with 20+ char value
- `ssh_backdoor` — authorized_keys, .ssh paths
- `hermes_env` — .hermes/.env references
- `agent_config_mod` — AGENTS.md/CLAUDE.md modifications

## Evasion Resistance
- **Filler words:** `(?:\w+\s)*` between key tokens catches "ignore xxx all instructions"
- **Case variation:** `re.IGNORECASE` flag handles "IGNORE", "Ignore", etc.
- **Invisible Unicode:** Separate detection via `INVISIBLE_CHARS` set (16 chars)
- **Token splitting:** `hardcoded_secret` requires 20+ consecutive chars

## Rate Limiting
- APIs like binlist.net, chkr.cc have rate limits
- Use local database first, API fallback
- Cache results 24h to reduce calls

## WAF Detection
- Some targets block direct HTTP/HTTPS requests
- Check for Cloudflare, Akamai, Incapsula headers
- Use passive recon when active scanning blocked
