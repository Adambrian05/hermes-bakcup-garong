#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
md2py.py — Convert semua file .md jadi .py module (payload/documentation bank)
Usage:
  python md2py.py <dir>            # convert semua .md di <dir> (recursive)
  python md2py.py <file.md>        # convert 1 file
No-arg = help.

Output: <file>.py — konten md di-wrap jadi konstanta string, bisa di-import
atau di-run langsung (print isi).
"""
import sys, os, re

def slugify(name):
    """Nama file .md -> nama variabel Python valid."""
    s = os.path.splitext(os.path.basename(name))[0]
    s = re.sub(r'[^a-zA-Z0-9_]', '_', s)
    s = re.sub(r'_+', '_', s).strip('_')
    if not s:
        s = "payloads"
    if s[0].isdigit():
        s = "p_" + s
    return s.upper()

def convert_md_to_py(md_path):
    with open(md_path, "r", encoding="utf-8", errors="replace") as f:
        content = f.read()

    var_name = slugify(md_path)
    py_path = os.path.splitext(md_path)[0] + ".py"

    header = f'''#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Converted from {os.path.basename(md_path)} — import atau run buat baca payload."""

{var_name} = """\\'''

    # Escape triple quotes inside content biar string aman
    body = content.replace('"""', '\\"\\"\\"')

    footer = '"""\n\nSEARCHABLE = ' + var_name + '  # alias\n\ndef find(keyword):\n    """Cari payload/materi by keyword (case-insensitive)."""\n    out = []\n    for line in ' + var_name + '.split("\\n"):\n        if keyword.lower() in line.lower():\n            out.append(line)\n    return out\n\ndef grep(regex):\n    """Cari pake regex."""\n    import re as _re\n    return [l for l in ' + var_name + '.split("\\n") if _re.search(regex, l)]\n\ndef dump():\n    """Print semua isi."""\n    print(' + var_name + ')\n\nif __name__ == "__main__":\n    import sys as _s\n    if len(_s.argv) > 1:\n        for kw in _s.argv[1:]:\n            print(f"--- match: {kw} ---")\n            for line in find(kw):\n                print("  " + line)\n    else:\n        dump()\n'

    with open(py_path, "w", encoding="utf-8") as f:
        f.write(header + body + footer)
    return py_path, var_name

def main():
    args = sys.argv[1:]
    if not args:
        print(__doc__)
        sys.exit(0)

    target = args[0]
    converted = []

    if os.path.isdir(target):
        for root, dirs, files in os.walk(target):
            for f in files:
                if f.endswith(".md"):
                    md_path = os.path.join(root, f)
                    py_path, var = convert_md_to_py(md_path)
                    converted.append((md_path, py_path, var))
    elif target.endswith(".md"):
        py_path, var = convert_md_to_py(target)
        converted.append((target, py_path, var))
    else:
        print(f"[x] bukan .md / dir: {target}")
        sys.exit(1)

    print(f"[*] converted {len(converted)} file:")
    for md, py, var in converted:
        print(f"  {os.path.basename(md):45s} -> {os.path.basename(py):45s} (var: {var})")
    print("\n[*] done. Import module-nya atau run: python <file>.py <keyword>")

if __name__ == "__main__":
    main()
