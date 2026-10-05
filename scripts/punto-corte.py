#!/usr/bin/env python3
"""Punto de corte de una sesión: a partir de cuántos turnos de trabajo PENDIENTE sale a cuenta
cortar y abrir chat nuevo. Lo llama hooks/userpromptsubmit-contexto.sh; también se puede correr a mano.

    python scripts/punto-corte.py --sesion <id>

POR QUÉ EXISTE (5-oct-2026, Oscar, con razón): el aviso del hook decía «es buen momento para
cortar» al pasar de ~200k tokens, sin cuentas, y las sesiones lo repetían. Resultado: 16 chats en
un mismo repo, cada uno pagando su arranque y su relectura. Comparar UN turno contra el arranque
tampoco sirve (casi siempre gana seguir), y hablar del ahorro acumulado sin saber cuánto trabajo
queda tampoco. La cuenta correcta compara el TRAMO QUE QUEDA:

    seguir:  N turnos × contexto_actual × lectura_caché
    cortar:  arranque × escritura_caché_1h  +  N turnos × arranque × lectura_caché

(el crecimiento del contexto turno a turno es el mismo en los dos lados y se cancela). Igualando:

    N* = arranque × escritura_1h / ((contexto_actual − arranque) × lectura)

Si quedan más de N* turnos, cortar ahorra; si quedan menos, seguir es más barato.

ARRANQUE MEDIDO, NO SUPUESTO: es el contexto de esta misma sesión en su respuesta número 15,
cuando ya leyó CLAUDE.md, la bitácora y los documentos. Una sesión nueva en el mismo repo tiene
que volver a leer eso mismo; el primer turno solo (~90k) lo infravalora.
Con otro modelo al cortar, el arranque se paga a la tarifa del modelo nuevo y el seguir a la del
actual: el corte es el único momento en que cambiar de modelo no añade peaje.

Precios: la tabla TARIFAS de coste-sesiones.py (única fuente). Sin tarifa conocida -> no imprime
nada y sale con 1 (un número inventado es peor que ninguno).
"""
import argparse
import importlib.util
import json
import os
import sys

AQUI = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location("coste_sesiones", os.path.join(AQUI, "coste-sesiones.py"))
cs = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(cs)

RESPUESTA_ARRANQUE = 15
OTROS = ("claude-sonnet-5", "claude-opus-5", "claude-haiku-4-5")


def contextos(transcript):
    """[(modelo, contexto)] por respuesta con uso registrado, sin repetir id de mensaje."""
    vistos, filas = set(), []
    with open(transcript, encoding="utf-8") as f:
        for linea in f:
            try:
                obj = json.loads(linea)
            except json.JSONDecodeError:
                continue
            msg = obj.get("message") or {}
            u = msg.get("usage")
            if not u or msg.get("id") in vistos:
                continue
            vistos.add(msg.get("id"))
            ctx = u.get("input_tokens", 0) + u.get("cache_creation_input_tokens", 0) + u.get("cache_read_input_tokens", 0)
            filas.append((msg.get("model") or "", ctx))
    return filas


def euros(x):
    return f"{x:.2f}".replace(".", ",") + " $"


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--sesion", required=True)
    ap.add_argument("--carpeta-proyectos", default=os.path.expanduser("~/.claude/projects"))
    a = ap.parse_args()

    ruta = None
    for d in os.listdir(a.carpeta_proyectos):
        p = os.path.join(a.carpeta_proyectos, d, a.sesion + ".jsonl")
        if os.path.isfile(p):
            ruta = p
            break
    if not ruta:
        return 1
    filas = contextos(ruta)
    if len(filas) < RESPUESTA_ARRANQUE + 1:
        return 1
    modelo, actual = filas[-1]
    arranque = filas[RESPUESTA_ARRANQUE - 1][1]
    t = cs.tarifa_de(modelo, False)
    if not t or actual <= arranque:
        return 1
    lectura, escr1h = t[3] / 1e6, t[2] / 1e6

    turno_aqui = actual * lectura
    n_mismo = arranque * escr1h / ((actual - arranque) * lectura)
    partes = [
        f"contexto {actual // 1000}k con {cs.corto(modelo) if hasattr(cs, 'corto') else modelo}: "
        f"cada turno más aquí ≈ {euros(turno_aqui)}",
        f"abrir chat nuevo con el mismo modelo ≈ {euros(arranque * escr1h)} de arranque "
        f"(arranque medido en esta sesión: {arranque // 1000}k) y luego ≈ {euros(arranque * lectura)} por turno",
        f"CORTAR SOLO COMPENSA SI QUEDAN MÁS DE {round(n_mismo)} TURNOS de trabajo en este repo",
    ]
    for otro in OTROS:
        if modelo.startswith(otro):
            continue
        to = cs.tarifa_de(otro, False)
        ahorro = turno_aqui - arranque * to[3] / 1e6
        if ahorro > 0:
            partes.append(f"cortando y pasando a {otro}: compensa a partir de {round(arranque * to[2] / 1e6 / ahorro)} turnos")
    print("; ".join(partes) + ".")
    return 0


if __name__ == "__main__":
    sys.exit(main())
