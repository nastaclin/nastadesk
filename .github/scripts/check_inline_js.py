#!/usr/bin/env python3
"""Extrai os <script> inline de cada *.html e valida a sintaxe com `node --check`.

O front do NastaDesk não tem build/CI de JS — um erro de sintaxe num script
inline só apareceria em produção. Este check reproduz no CI o `node --check`
que já era rodado manualmente nas sessões de desenvolvimento.
"""
import glob
import re
import subprocess
import sys
import tempfile

SCRIPT_RE = re.compile(r'<script((?![^>]*\bsrc=)[^>]*)>(.*?)</script>', re.S | re.I)

fail = False
for path in sorted(glob.glob('*.html')):
    src = open(path, encoding='utf-8').read()
    for i, m in enumerate(SCRIPT_RE.finditer(src), 1):
        attrs, body = m.group(1), m.group(2)
        if not body.strip():
            continue
        # só pula tipos não-JS declarados NA TAG (ex.: type="application/ld+json")
        if 'application/json' in attrs or 'ld+json' in attrs:
            continue
        with tempfile.NamedTemporaryFile('w', suffix='.js', delete=False,
                                         encoding='utf-8') as tmp:
            tmp.write(body)
            name = tmp.name
        r = subprocess.run(['node', '--check', name], capture_output=True, text=True)
        if r.returncode != 0:
            fail = True
            print(f'ERRO de sintaxe em {path} (script inline #{i}):')
            print(r.stderr)
        else:
            print(f'OK  {path} script #{i}')
sys.exit(1 if fail else 0)
