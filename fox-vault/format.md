# FOX Vault — Credential & Findings Storage

## Format
- KEY=VALUE pairs for credentials and findings
- Token-shaped values automatically redacted to ***) in display output
- Full values accessible via read operations with proper auth

## Storage Rules
1. Never store raw API keys, passwords, or secrets in chat log
2. Vault entries encrypted at rest
3. Access controlled per-session
4. Cross-reference with .multibrain for context

## Example Entry Format
```
# Target: example.com
# Vulnerability: SQLi
# Payload: UNION SELECT NULL--
# Status: verified
# Date: 2026-08-27
```

## Cross-Reference
- Links to .multibrain entries for session continuity
- References skill IDs for reproducibility
- Tags for categorization (sqli, xss, privesc, etc.)