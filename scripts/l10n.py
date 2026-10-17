#!/usr/bin/env python3
"""Traductions de Cliché.

  scripts/l10n.py extract   Extrait les textes de Sources/Cliche et réécrit la référence fr.lproj (texte = clé).
  scripts/l10n.py check     Vérifie chaque langue : mêmes clés que le code, mêmes paramètres (%@, %lld),
                            pas de valeur vide, pas de texte resté en français. Code de sortie 1 si un écart.

Le français est la langue de développement : les clés sont les textes français du code
(String(localized:) et littéraux SwiftUI). Les paramètres \\(…) deviennent %lld (Int(…)) ou %@.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "Sources", "Cliche")
RES = os.path.join(ROOT, "Resources")
LANGS = ["en", "de", "es", "it", "pt-BR", "ja", "zh-Hans"]

# Appels dont le premier argument littéral est une clé de traduction.
CALLS = re.compile(r'(?:String\(localized:\s*|\b(?:Text|Toggle|Button|Link|Label|LabeledContent|Section|Card|Row)\(\s*'
                   r'|\.help\(\s*|\b(?:title|detail):\s*)"')
# Textes identiques dans toutes les langues (noms propres, unités, nombres).
SAME_EVERYWHERE = {"Cliché", "%lld px", "4 s", "6 s", "10 s", "v%@", "OK", "PNG", "JPEG", "OCR",
                   "cliche://grab/area · grab/fullscreen · grab/window · grab/scrolling · grab/area/repeat · ocr · load/clipboard"}
# Mots identiques au français dans une langue donnée (vérifiés un par un, pas un joker).
SAME_IN = {"en": {"Capture", "Double", "Format", "Image", "Rectangle"}, "it": {"Ovale"}}


def read_literal(s, i):
    """Lit un littéral Swift commençant après le guillemet ouvrant en s[i]. Renvoie (clé, fin)."""
    out, j = [], i
    while j < len(s):
        c = s[j]
        if c == '"':
            return "".join(out), j + 1
        if c == "\\" and s[j + 1] == "(":
            depth, k = 1, j + 2
            while depth:
                if s[k] == "(":
                    depth += 1
                elif s[k] == ")":
                    depth -= 1
                k += 1
            expr = s[j + 2:k - 1].strip()
            out.append("%lld" if expr.startswith("Int(") else "%@")
            j = k
            continue
        if c == "\\":
            out.append(s[j:j + 2])
            j += 2
            continue
        if c == "%":
            out.append("%%")
            j += 1
            continue
        out.append(c)
        j += 1
    raise ValueError("littéral non fermé")


def extract():
    keys = {}
    for name in sorted(os.listdir(SRC)):
        if not name.endswith(".swift"):
            continue
        text = open(os.path.join(SRC, name), encoding="utf-8").read()
        for m in CALLS.finditer(text):
            key, _ = read_literal(text, m.end())
            if key.strip() and re.search(r"[A-Za-zÀ-ÿ]", key):
                line = text.count("\n", 0, m.start()) + 1
                keys.setdefault(key, f"{name}:{line}")
    return keys


def parse_strings(path):
    pairs = {}
    if not os.path.exists(path):
        return pairs
    text = open(path, encoding="utf-8").read()
    for m in re.finditer(r'^"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)";', text, re.M):
        pairs[m.group(1)] = m.group(2)
    return pairs


def placeholders(s):
    """Types des paramètres, positions ignorées (%1$@ et %@ sont équivalents)."""
    return sorted(re.sub(r"\d+\$", "", p) for p in re.findall(r"%(?:\d+\$)?(?:lld|@|d|f|lf)", s))


def cmd_extract():
    keys = extract()
    os.makedirs(os.path.join(RES, "fr.lproj"), exist_ok=True)
    with open(os.path.join(RES, "fr.lproj", "Localizable.strings"), "w", encoding="utf-8") as f:
        f.write("/* Référence : français, langue de développement. Généré par scripts/l10n.py extract. */\n\n")
        for k, where in keys.items():
            f.write(f'/* {where} */\n"{k}" = "{k}";\n\n')
    print(f"{len(keys)} textes → Resources/fr.lproj/Localizable.strings")


def cmd_check():
    keys = extract()
    errors = 0
    ref = parse_strings(os.path.join(RES, "fr.lproj", "Localizable.strings"))
    if set(ref) != set(keys):
        print(f"fr : référence périmée ({len(set(keys) - set(ref))} manquantes, {len(set(ref) - set(keys))} en trop) → scripts/l10n.py extract")
        errors += 1
    for lang in LANGS:
        tr = parse_strings(os.path.join(RES, f"{lang}.lproj", "Localizable.strings"))
        missing, extra = set(keys) - set(tr), set(tr) - set(keys)
        for k in sorted(missing):
            print(f"{lang} : manquant  {k!r}  ({keys[k]})"); errors += 1
        for k in sorted(extra):
            print(f"{lang} : en trop   {k!r}"); errors += 1
        for k in sorted(set(keys) & set(tr)):
            v = tr[k]
            if not v.strip():
                print(f"{lang} : vide      {k!r}"); errors += 1
            elif placeholders(k) != placeholders(v):
                print(f"{lang} : paramètres {placeholders(k)} ≠ {placeholders(v)}  {k!r}"); errors += 1
            elif v == k and k not in SAME_EVERYWHERE | SAME_IN.get(lang, set()) and re.search(r"[A-Za-zÀ-ÿ]{4,}", k):
                print(f"{lang} : non traduit {k!r}"); errors += 1
    print(f"{len(keys)} textes × {len(LANGS)} langues : {'OK' if not errors else f'{errors} écart(s)'}")
    return 1 if errors else 0


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "check"
    sys.exit(cmd_check() if cmd == "check" else cmd_extract() or 0)
