#!/usr/bin/env python3
"""Auditoria heurística de XSS para os fronts do NastaDesk (HTML/JS sem build).

Procura sinks de HTML (`.innerHTML`, `.outerHTML`, `insertAdjacentHTML`,
`document.write`) e sinaliza interpolações `${...}` de template literals na
vizinhança do sink que referenciam campos com cara de dado-de-usuário
(nome, whatsapp, observações...) SEM passar pelo escaper (`esc()` /
`escapeHtml()`).

É heurístico de propósito: falsos positivos conhecidos ficam registrados no
baseline (.github/xss-baseline.json). O job de CI só falha quando aparece um
achado NOVO que não está no baseline — ou seja, quando alguém introduz uma
interpolação suspeita nova.

Uso:
  python3 .github/scripts/xss_audit.py            # audita (falha se houver achado novo)
  python3 .github/scripts/xss_audit.py --update   # regrava o baseline com os achados atuais
"""
import glob
import json
import os
import re
import sys

BASELINE = os.path.join(os.path.dirname(__file__), '..', 'xss-baseline.json')

SINK_RE = re.compile(r'\.(innerHTML|outerHTML)\s*[+]?=|insertAdjacentHTML\s*\(|document\.write\s*\(')
INTERP_RE = re.compile(r'\$\{([^{}]*)\}')
# Campos que costumam carregar dado digitado por usuário/paciente
SENSITIVE_FIELD_RE = re.compile(
    r'\.(nome|email|whatsapp|telefone|observaco\w*|anamnese|queixa|motivo|comentario'
    r'|descricao|texto|endereco|responsavel|convenio|local|unidade|categoria|preferencia)\b')
# Wrappers que tornam a interpolação segura (ou claramente não-string-de-usuário)
SAFE_WRAPPERS = ('esc(', 'escapeHtml(', 'escAttr(', 'encodeURIComponent(',
                 'Number(', 'fmtBRL(', 'parseInt(', 'parseFloat(')
WINDOW = 3000  # chars após o sink considerados parte do mesmo statement/render


def find(path):
    src = open(path, encoding='utf-8').read()
    results = []
    for m in SINK_RE.finditer(src):
        window = src[m.end():m.end() + WINDOW]
        # corta no fim do statement (heurística: ; no começo de linha)
        cut = re.search(r';\s*\n', window)
        if cut:
            window = window[:cut.end()]
        for im in INTERP_RE.finditer(window):
            expr = im.group(1).strip()
            if any(w in expr for w in SAFE_WRAPPERS):
                continue
            if not SENSITIVE_FIELD_RE.search(expr):
                continue
            line = src[:m.start()].count('\n') + 1
            results.append({'file': os.path.basename(path), 'sink_line': line,
                            'expr': expr[:120]})
    return results


def main():
    findings = []
    for path in sorted(glob.glob('*.html')):
        findings.extend(find(path))
    # dedup
    seen, uniq = set(), []
    for f in findings:
        key = (f['file'], f['expr'])
        if key in seen:
            continue
        seen.add(key)
        uniq.append(f)

    if '--update' in sys.argv:
        with open(BASELINE, 'w', encoding='utf-8') as fh:
            json.dump(uniq, fh, indent=2, ensure_ascii=False)
        print(f'baseline atualizado com {len(uniq)} entradas -> {BASELINE}')
        return 0

    baseline = []
    if os.path.exists(BASELINE):
        baseline = json.load(open(BASELINE, encoding='utf-8'))
    known = {(b['file'], b['expr']) for b in baseline}
    new = [f for f in uniq if (f['file'], f['expr']) not in known]

    print(f'{len(uniq)} interpolações suspeitas ({len(new)} novas fora do baseline)')
    for f in new:
        print(f"  NOVO  {f['file']}:{f['sink_line']}  ${{{f['expr']}}}")
    if new:
        print('\nFalha: interpolação nova sem esc()/escapeHtml() perto de um sink de HTML.')
        print('Corrija envolvendo com esc(...) — ou, se for comprovadamente constante,')
        print('rode: python3 .github/scripts/xss_audit.py --update e commit o baseline.')
        return 1
    print('OK: nenhum achado novo.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
