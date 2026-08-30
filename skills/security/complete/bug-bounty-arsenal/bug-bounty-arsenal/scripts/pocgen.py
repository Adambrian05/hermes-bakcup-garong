#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
pocgen.py — PoC Report Generator (format HackerOne/Bugcrowd siap submit)
Usage:
  python pocgen.py <hunter_results.json> [--outdir poc_reports] [--program "Nama Program"]
  python pocgen.py --demo            (contoh laporan kosong)
No-arg = help. Setiap finding CRIT/HIGH/MED jadi satu file markdown.
"""
import sys, os, json, re, time

HERE = os.path.dirname(os.path.abspath(__file__))

SEV_SCORE = {
    "CRIT": (9.8, "Critical"),
    "HIGH": (8.5, "High"),
    "MED": (6.5, "Medium"),
    "LOW": (3.5, "Low"),
    "INFO": (1.0, "Informational"),
}

SEV_REWARD = {
    "CRIT": "$5,000 - $50,000+",
    "HIGH": "$1,000 - $10,000",
    "MED": "$200 - $2,500",
    "LOW": "$50 - $500",
    "INFO": "$0 - $100 (jarang dibayar)",
}

CVSS_VECTOR = {
    "CRIT": "CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:C/C:H/I:H/A:H",
    "HIGH": "CVSS:3.1/AV:N/AC:L/PR:N/UI:R/S:C/C:H/I:L/A:N",
    "MED":  "CVSS:3.1/AV:N/AC:L/PR:L/UI:N/S:U/C:L/I:L/A:N",
    "LOW":  "CVSS:3.1/AV:N/AC:H/PR:L/UI:R/S:U/C:L/I:N/A:N",
    "INFO": "CVSS:3.1/AV:N/AC:H/PR:H/UI:R/S:U/C:N/I:N/A:N",
}

REMEDIATION = {
    "xss": "1. Encode semua output (context-aware: HTML/JS/attribute encoding).\n2. Terapkan CSP dengan 'self' + nonce, tanpa 'unsafe-inline'.\n3. Sanitasi input pakai library (DOMPurify, bleach).",
    "sqli": "1. Pakai parameterized query / prepared statement 100%.\n2. Jangan concat string ke query.\n3. WAF + input validation sebagai lapis tambahan.",
    "ssrf": "1. Whitelist domain + resolve DNS dulu, tolak IP privat.\n2. Blok protokol selain http/https.\n3. Redirect policy ketat (jangan follow ke internal).",
    "ssti": "1. Jangan render user input sebagai template.\n2. Sandbox template engine / pakai allowlist fungsi.",
    "traversal": "1. Normalisasi + canonical path, tolak '..'.\n2. Whitelist file yang boleh diakses.\n3. Jangan pakai input user untuk path file.",
    "idor": "1. Cek otorisasi per objek (ownership) di server, bukan cuma auth.\n2. Pakai UUID acak, bukan sequential ID.\n3. Row-level security di DB.",
    "jwt": "1. Fix alg: server wajib whitelist algoritma.\n2. Ganti secret dengan key random 256-bit.\n3. Validasi exp/nbf/aud/iss.",
    "cors": "1. Whitelist origin eksplisit, bukan reflect/wildcard.\n2. Jangan pakai ACAO:* kalau ada credentials.",
    "exposed": "1. Blok dotfiles di web server (nginx: deny \\.).\n2. Pindahkan backup/env keluar webroot.\n3. Rotate semua secret yang bocor.",
    "redirect": "1. Whitelist URL tujuan / hanya path internal.\n2. Tolak '//', '\\', javascript: scheme.",
    "crlf": "1. Encode/strip \\r\\n dari semua input header.\n2. Framework versi terbaru.",
    "xxe": "1. Disable external entity resolution.\n2. Pakai JSON kalau bisa.",
    "nosqli": "1. Validasi tipe input (harus string, tolak $/operators).\n2. Pakai ODM dengan casting ketat.",
    "hostheader": "1. Whitelist host yang valid.\n2. Jangan pakai Host header untuk generate URL (pakai konfigurasi).",
    "cachepoison": "1. Strip header forward yang ga dipakai (X-Forwarded-*).\n2. Cache key berbasis full URL + host whitelist.",
    "graphql": "1. Disable introspection di production.\n2. Query depth limit + rate limit.\n3. Field-level authorization.",
    "rate": "1. Rate limit per IP + per akun.\n2. Lockout setelah N gagal.",
    "oauth": "1. Exact-match redirect_uri whitelist.\n2. Bind authorization code ke client + PKCE.",
    "massassign": "1. Whitelist field yang boleh di-set user.\n2. DTO per role.",
    "upload": "1. Whitelist ekstensi + MIME + magic bytes.\n2. Simpan di luar webroot, random filename.\n3. Scan malware.",
    "default": "1. Perbaiki sesuai root cause di atas.\n2. Re-test setelah patch untuk verifikasi.",
}

IMPACT = {
    "CRIT": "Attacker dapat mengambil alih akun/data/sistem secara penuh tanpa interaksi user. Potensi data breach massal, kerugian finansial langsung, dan kerusakan reputasi.",
    "HIGH": "Attacker dapat mengakses data sensitif milik user lain atau melakukan aksi dengan hak lebih tinggi. Satu langkah lagi menuju takeover penuh.",
    "MED": "Attacker dapat memanipulasi data/aksi dalam scope terbatas, atau kombinasi dengan bug lain menghasilkan impact besar.",
    "LOW": "Informasi tambahan yang memperluas attack surface. Nilai kecil sendiri, besar saat di-chain.",
}


def slugify(s):
    s = re.sub(r"[^a-z0-9]+", "-", s.lower()).strip("-")
    return s[:60] or "finding"


def generate_report(target, finding, program="", outdir="poc_reports", idx=1):
    sev = finding.get("severity", "LOW").upper()
    score, sev_name = SEV_SCORE.get(sev, SEV_SCORE["LOW"])
    module = finding.get("module", "unknown")
    title = finding.get("title", "Finding")
    detail = finding.get("detail", "")
    poc = finding.get("poc", "")
    rem = REMEDIATION.get(module, REMEDIATION["default"])
    imp = IMPACT.get(sev, IMPACT["LOW"])

    # generated poc steps from stored poc command
    steps = ""
    if poc:
        steps = f"""### Langkah Reproduksi

1. Jalankan request berikut:
```bash
{poc}
```
2. Perhatikan response — data/efek yang seharusnya tidak bisa diakses muncul.
3. Ulangi dengan session user biasa untuk membuktikan ini bukan akses admin.
"""

    md = f"""# {title}

| Field | Value |
|---|---|
| **Program** | {program or target} |
| **Target** | `{target}` |
| **Severity** | {sev_name} ({score}/10) |
| **CVSS v3.1** | `{CVSS_VECTOR.get(sev)}` |
| **Estimasi Bounty** | {SEV_REWARD.get(sev)} |
| **Kategori** | {module.upper()} (CWE-{ {"xss":79,"sqli":89,"ssrf":918,"ssti":94,"traversal":22,"idor":639,"jwt":287,"cors":942,"exposed":200,"redirect":601,"crlf":93,"xxe":611,"nosqli":943,"hostheader":437,"cachepoison":444,"graphql":639,"rate":307,"oauth":601,"massassign":915,"upload":434,"headers":693,"admin":306,"methods":436,"clickjack":1021,"info":200,"https":319,"proto":1321,"hpp":235,"ldap":90,"deser":502,"2fa":287,"subtakeover":404,"websocket":345,"cachepoison":444,"timing":203,"xxe":611,"default":200}.get(module, 200) }) |
| **Ditemukan** | {time.strftime('%Y-%m-%d')} |

## Ringkasan

{imp}

**Detail teknis:** {detail or title}

{steps}
## Impact

{imp}

### Dampak bisnis
- **Data:** potensi akses data user lain / data internal
- **Finansial:** kerugian langsung via penyalahgunaan fitur
- **Reputasi:** pelanggaran privasi user, sanksi regulator (UU PDP, GDPR)

## Remediasi

{rem}

## Referensi

- OWASP Top 10: https://owasp.org/www-project-top-ten/
- CWE: https://cwe.mitre.org/data/definitions/{ {"xss":79,"sqli":89,"ssrf":918,"ssti":94,"traversal":22,"idor":639,"jwt":287,"cors":942,"exposed":200,"redirect":601,"crlf":93,"xxe":611,"nosqli":943,"hostheader":437,"cachepoison":444,"graphql":639,"rate":307,"oauth":601,"massassign":915,"upload":434,"headers":693,"admin":306,"methods":436,"clickjack":1021,"info":200,"https":319,"proto":1321,"hpp":235,"ldap":90,"deser":502,"2fa":287,"subtakeover":404,"websocket":345,"cachepoison":444,"timing":203,"xxe":611,"default":200}.get(module, 200) }.html

---
*Generated by bb-arsenal pocgen — verifikasi PoC sebelum submit. Jangan submit tanpa reproduksi manual.*
"""
    os.makedirs(outdir, exist_ok=True)
    fname = os.path.join(outdir, f"{idx:02d}-{sev.lower()}-{slugify(title)}.md")
    with open(fname, "w", encoding="utf-8") as f:
        f.write(md)
    return fname


def demo():
    print("""
Contoh struktur laporan bug bounty (yang dibayar mahal):

# Account Takeover via IDOR di /api/users/{id}

## Ringkasan
Endpoint /api/users/{id} tidak memvalidasi kepemilikan objek.
User A bisa akses (dan edit) data user B hanya dengan mengganti ID.

## Langkah Reproduksi
1. Login sebagai user A
2. GET /api/users/1 → data sendiri
3. GET /api/users/2 → DATA USER LAIN (tanpa izin!)
4. PUT /api/users/2 → bisa ubah email user B → reset password → takeover

## Impact
5 juta user terekspos. Attacker bisa takeover semua akun.

## Remediasi
Cek ownership per objek di server, bukan cuma session valid.

## PoC
curl -H "Authorization: Bearer $TOKEN_A" https://target.com/api/users/2

Yang BIKIN report dibayar:
- PoC reproducibel 1 command
- Impact nyata (data siapa, berapa user)
- Remediasi jelas
- Ga ada drama / ga overclaim severity
""")


def main():
    args = sys.argv[1:]
    if not args:
        print(__doc__)
        sys.exit(0)
    if args[0] == "--demo":
        demo()
        return
    src = args[0]
    outdir = "poc_reports"
    program = ""
    i = 1
    while i < len(args):
        if args[i] == "--outdir":
            outdir = args[i + 1]; i += 2
        elif args[i] == "--program":
            program = args[i + 1]; i += 2
        else:
            i += 1
    with open(src, "r", encoding="utf-8") as f:
        data = json.load(f)
    target = data.get("target", "unknown")
    findings = data.get("findings", [])
    print(f"[*] target: {target}")
    print(f"[*] {len(findings)} temuan → {outdir}/")
    files = []
    for idx, finding in enumerate(findings, 1):
        f = generate_report(target, finding, program, outdir, idx)
        files.append(f)
        sev = finding.get("severity", "LOW").upper()
        print(f"  {idx:02d}. [{sev}] {f}")
    print(f"\n[*] {len(files)} laporan siap. Review + verifikasi manual sebelum submit ke program.")


if __name__ == "__main__":
    main()
