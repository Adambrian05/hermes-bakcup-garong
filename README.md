# 🤖 Hermes Agent Backup

Personal backup of Hermes Agent configuration, skills, and tools.

## Contents

- `SOUL.md` - Agent persona and core identity
- `config.yaml` - Agent configuration (secrets redacted)
- `skills/` - All installed skills (SuperAgent v7, Fox, Security, etc.)
- `memories/` - Persistent memory (MEMORY.md, USER.md)
- `scripts/` - Custom scripts, tools, and reference docs
- `fox/` + `fox-vault/` - FOX hacker framework
- `superagent-v7/` - SuperAgent toolkit
- `openclaw*/` - OpenClaw variants
- `bin/` - Binary tools
- `hooks/` - Agent hooks

## Restoring

```bash
# Clone and copy back to ~/.hermes/
git clone https://github.com/Adambrian05/hermes-bakcup-garong.git
cp -r hermes-bakcup-garong/* ~/.hermes/

# Restore config (remove REDACTED values and add real secrets)
nano ~/.hermes/config.yaml

# Restore .env with real tokens
# ...
```

## Notes

- Secrets (bot tokens, API keys) are **redacted** in config.yaml
- `.env` file is NOT included (contains live tokens)
- Database files (state.db, sessions) are excluded
- Cache files are excluded
