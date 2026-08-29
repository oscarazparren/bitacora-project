#!/usr/bin/env python3
# Bitácora — regenera la distribución MB-vs-tokens que justificó el cambio de
# métrica en hooks/userpromptsubmit-contexto.sh (29-ago-2026).
#
# El hook avisaba de cuándo cortar la sesión mirando el PESO en bytes del
# transcript .jsonl. Medido ese día sobre 56 sesiones reales: el umbral de 2 MB
# correspondía a sesiones de entre 58k y 394k tokens de contexto según el caso
# -- un factor 6,8x de un lado a otro del mismo umbral, con rho(MB, tokens) =
# 0,927 (hay correlación, pero no la precisión que hace falta para un umbral).
# La causa: el peso en bytes mezcla bloques de pensamiento y salidas de
# herramientas -- que engordan el fichero pero no todos entran en el contexto
# que se reenvía -- con los tokens que sí se facturan y se reenvían cada turno.
#
# Este script reproduce esa medición sobre las sesiones que haya en disco en
# cada momento, para poder recalibrar los umbrales si hace falta en vez de
# fiarse de un número escrito una vez en un comentario.
#
# Sin dependencias fuera de la librería estándar: nada de numpy/scipy para no
# exigir un entorno que puede no estar instalado en la máquina donde se corra.

import argparse
import json
import os
import sys
from pathlib import Path


def ultima_usage(ruta):
    """Usage del último mensaje assistant con 'usage' en el transcript, o None."""
    ultimo = None
    with open(ruta, encoding="utf-8", errors="replace") as f:
        for linea in f:
            linea = linea.strip()
            if not linea:
                continue
            try:
                obj = json.loads(linea)
            except json.JSONDecodeError:
                continue
            mensaje = obj.get("message")
            if isinstance(mensaje, dict) and isinstance(mensaje.get("usage"), dict):
                ultimo = mensaje["usage"]
    return ultimo


def recolectar(carpeta_proyectos):
    filas = []
    for jsonl in Path(carpeta_proyectos).glob("*/*.jsonl"):
        try:
            peso = jsonl.stat().st_size
        except OSError:
            continue
        usage = ultima_usage(jsonl)
        if usage is None:
            continue
        entrada = usage.get("input_tokens", 0) or 0
        cache_creacion = usage.get("cache_creation_input_tokens", 0) or 0
        cache_lectura = usage.get("cache_read_input_tokens", 0) or 0
        filas.append(
            {
                "sesion": jsonl.stem,
                "proyecto": jsonl.parent.name,
                "bytes": peso,
                "tokens": entrada + cache_creacion + cache_lectura,
                "input_tokens": entrada,
            }
        )
    return filas


def spearman(xs, ys):
    """Correlación de rango de Spearman. Sin numpy/scipy: rangos a mano, con
    empates repartidos por su rango promedio (el método estándar 'midrank')."""

    def rangos(vals):
        orden = sorted(range(len(vals)), key=lambda i: vals[i])
        r = [0.0] * len(vals)
        i = 0
        while i < len(orden):
            j = i
            while j + 1 < len(orden) and vals[orden[j + 1]] == vals[orden[i]]:
                j += 1
            promedio = (i + j) / 2.0 + 1
            for k in range(i, j + 1):
                r[orden[k]] = promedio
            i = j + 1
        return r

    rx, ry = rangos(xs), rangos(ys)
    n = len(xs)
    media_x, media_y = sum(rx) / n, sum(ry) / n
    cov = sum((a - media_x) * (b - media_y) for a, b in zip(rx, ry))
    var_x = sum((a - media_x) ** 2 for a in rx)
    var_y = sum((b - media_y) ** 2 for b in ry)
    if var_x == 0 or var_y == 0:
        return float("nan")
    return cov / (var_x * var_y) ** 0.5


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument(
        "--carpeta-proyectos",
        default=os.path.expanduser("~/.claude/projects"),
        help="raíz donde viven los <proyecto>/<sesion>.jsonl (por defecto ~/.claude/projects)",
    )
    ap.add_argument(
        "--umbral-mb",
        type=float,
        default=2.0,
        help="umbral de bytes, en MB, a examinar (por defecto 2.0, el antiguo umbral retirado)",
    )
    ap.add_argument(
        "--tolerancia-mb",
        type=float,
        default=0.2,
        help="banda +/- alrededor de --umbral-mb, en MB",
    )
    args = ap.parse_args()

    filas = recolectar(args.carpeta_proyectos)
    if not filas:
        print(f"No se encontraron sesiones con \"usage\" en {args.carpeta_proyectos}", file=sys.stderr)
        return 1

    bytes_ = [f["bytes"] for f in filas]
    tokens = [f["tokens"] for f in filas]
    rho = spearman(bytes_, tokens)

    total_tokens = sum(tokens)
    total_input = sum(f["input_tokens"] for f in filas)
    pct_input = (100.0 * total_input / total_tokens) if total_tokens else 0.0

    centro = args.umbral_mb * 1_000_000
    tolerancia = args.tolerancia_mb * 1_000_000
    en_banda = [f for f in filas if abs(f["bytes"] - centro) <= tolerancia]

    print(f"Sesiones analizadas: {len(filas)}")
    print(f"rho(bytes, tokens) = {rho:.3f}")
    print(f"input_tokens / tokens de contexto total = {pct_input:.1f}%")
    print()

    if en_banda:
        toks_banda = [f["tokens"] for f in en_banda]
        factor = max(toks_banda) / max(min(toks_banda), 1)
        print(f"Sesiones dentro de +/-{args.tolerancia_mb} MB de {args.umbral_mb} MB: {len(en_banda)}")
        print(f"  tokens de contexto: min={min(toks_banda):,} max={max(toks_banda):,} (factor {factor:.1f}x)")
    else:
        print(f"Ninguna sesión cae dentro de +/-{args.tolerancia_mb} MB de {args.umbral_mb} MB.")
    print()

    print(f"{'sesion':<38} {'proyecto':<38} {'MB':>7} {'tokens':>10}")
    for f in sorted(filas, key=lambda f: f["tokens"], reverse=True):
        print(f"{f['sesion']:<38} {f['proyecto'][:38]:<38} {f['bytes'] / 1_000_000:>7.2f} {f['tokens']:>10,}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
