#!/usr/bin/env python3
# Bitácora -- CONTABLE: qué costó cada sesión, cada modelo y cada día.
#
# Es el mismo lector de ~/.claude/projects/*/*.jsonl que calibrar-umbral.py, con una
# diferencia que lo cambia todo: calibrar-umbral.py mira el usage del ÚLTIMO mensaje,
# porque lo que le interesa es el TAMAÑO DEL CONTEXTO en ese instante. Aquí se suman las
# cuatro clases de token de CADA mensaje del assistant, cada una a su tarifa. Un número
# es una foto; el otro es la factura.
#
# EL CONTABLE NO ES QUIEN GASTA -- misma doctrina que auditar-sesiones.sh. Este script
# no escribe en ningún repo, no toca los transcripts, no llama a ninguna API y SALE
# SIEMPRE CON 0: es un informe, no una comprobación que deba tumbar nada.
#
# Y NO SE ENGANCHA A NINGÚN HOOK, a propósito. Ejecutarlo cuesta cero tokens: lee
# ficheros locales. Lo que cuesta es su SALIDA cuando entra en el contexto de una
# sesión, porque a partir de ahí se paga en cada turno. Inyectar ~300 tokens de resumen
# en cada prompt de una sesión de 200 turnos se acumula hasta millones de tokens de
# relectura -- del orden de 3 $ por sesión, más que el gasto que pretendería vigilar.
# Por eso imprime a stdout bajo demanda y el JSON va a FICHERO, no a la conversación.
#
# CUATRO CLASES DE TOKEN, CUATRO TARIFAS. No es un detalle contable: el 58 % del gasto
# medido en agosto de 2026 fue cache_read, o sea reenviar lo ya dicho. Un total de
# "tokens" a secas mezcla lo que cuesta 25 $/MTok (salida de Opus) con lo que cuesta
# 0,50 $ (lectura de caché), un factor 50x, y el resultado no sirve para decidir nada.
#
# LAS ESCRITURAS DE CACHÉ SE SEPARAN POR TTL. Medido el 4-sep-2026 sobre los 135
# transcripts de esta máquina: el 96,8 % de los 59,5M de tokens escritos en caché son de
# TTL de 1 hora (2x la tarifa base), no de 5 minutos (1,25x). Valorarlo todo a 1,25x
# subestimaría esa partida en un 60 %. El desglose viene en usage.cache_creation
# (ephemeral_5m_input_tokens / ephemeral_1h_input_tokens) y estaba completo en el 100 %
# de las escrituras; cuando falte, se supone 5m -- el TTL por defecto y, además, el
# supuesto que INFRAVALORA, o sea el error en la dirección visible.
#
# DOS TRAMPAS DEL FORMATO, LAS DOS MEDIDAS ANTES DE ESCRIBIR ESTO:
#
#   1. El top-level de usage NO SIEMPRE ES EL TOTAL. Cuando existe usage.iterations,
#      manda la SUMA de las iteraciones. De 11.572 mensajes únicos en disco, dos lo
#      demuestran: uno con una iteración de tipo 'fallback_message' cuyo top-level
#      declara 129.803 tokens de lectura mientras las iteraciones suman 290.849; y otro
#      cuyo top-level está TODO A CERO mientras su única iteración declara 919.625
#      tokens de lectura -- casi medio dólar invisible. Los 11.515 restantes con una
#      sola iteración coinciden exactamente con su top-level, así que sumar iteraciones
#      no cambia el caso normal y arregla el raro. Sin 'iterations' (56 mensajes, de
#      formato antiguo) se cae al top-level.
#
#   2. UN MISMO MENSAJE APARECE EN VARIOS FICHEROS. 2.016 message.id repartidos por 55
#      ficheros están duplicados: al reanudar o bifurcar una sesión, Claude Code copia
#      la historia anterior al .jsonl nuevo, con su usage intacto. Sumar por fichero
#      cuenta dos y tres veces peticiones que se facturaron UNA. Aquí se deduplica por
#      message.id en TODA la carpeta y cada mensaje se atribuye a su aparición más
#      antigua, que es la sesión que de verdad lo pagó. El recuento de duplicados
#      suprimidos se imprime: "no lo sé" y "no hay nada" no se leen igual.
#
# TRES ESTADOS PARA LAS TARIFAS, NUNCA COLAPSADOS. Un modelo con tarifa conocida se
# valora; uno desconocido va a un cubo aparte, con sus tokens a la vista y coste None
# -- jamás cero, que se lee como "gratis"; los mensajes sintéticos de Claude Code
# (model '<synthetic>', sin petición a la API detrás) se descartan y se cuentan.
#
# Sin dependencias fuera de la librería estándar, igual que calibrar-umbral.py, para que
# corra en las dos máquinas y en el servidor sin instalar nada.
#
# Uso:
#   coste-sesiones.py                      # todo lo que haya en disco
#   coste-sesiones.py --dias 7             # última semana
#   coste-sesiones.py --proyecto bitacora  # filtra por nombre de proyecto
#   coste-sesiones.py --resumen            # solo totales (la salida más barata)
#   coste-sesiones.py --json coste.json    # además, vuelca el detalle a un fichero

import argparse
import json
import os
import sys
from datetime import datetime, timedelta
from pathlib import Path

# ---------------------------------------------------------------------------
# TARIFAS. Dólares por millón de tokens, API de primera parte, tal y como las publica
# https://platform.claude.com/docs/en/about-claude/pricing -- consultada el 2026-09-04.
# Se guardan las CINCO columnas publicadas en vez de derivar las de caché con los
# multiplicadores 1,25x / 2x / 0,1x, porque hay excepciones: la lectura de caché de
# Claude Fable 5.1 es 0,025x (0,25 $) y no 0,1x. Derivar habría multiplicado por cuatro
# esa fila sin que nada avisara.
#
# NO cubierto a propósito, porque no aparece en estos transcripts (comprobado: los
# 27.822 mensajes están en service_tier 'standard' y speed 'standard'): el descuento del
# 50 % de la Batch API y el multiplicador 1,1x de residencia de datos (inference_geo
# 'us'). El modo rápido SÍ está contemplado más abajo, porque /fast se usa a diario.
TARIFAS = {
    # id de modelo         entrada  escr.5m  escr.1h  lectura  salida
    "claude-fable-5-1":    (10.00, 12.50, 20.00, 0.25, 50.00),
    "claude-mythos-5-1":   (10.00, 12.50, 20.00, 0.25, 50.00),
    "claude-fable-5":      (10.00, 12.50, 20.00, 1.00, 50.00),
    "claude-mythos-5":     (10.00, 12.50, 20.00, 1.00, 50.00),
    "claude-opus-5":       (5.00, 6.25, 10.00, 0.50, 25.00),
    "claude-opus-4-8":     (5.00, 6.25, 10.00, 0.50, 25.00),
    "claude-opus-4-7":     (5.00, 6.25, 10.00, 0.50, 25.00),
    "claude-opus-4-6":     (5.00, 6.25, 10.00, 0.50, 25.00),
    "claude-opus-4-5":     (5.00, 6.25, 10.00, 0.50, 25.00),
    "claude-opus-4-1":     (15.00, 18.75, 30.00, 1.50, 75.00),
    "claude-opus-4":       (15.00, 18.75, 30.00, 1.50, 75.00),
    "claude-sonnet-5":     (2.00, 2.50, 4.00, 0.20, 10.00),
    "claude-sonnet-4-6":   (3.00, 3.75, 6.00, 0.30, 15.00),
    "claude-sonnet-4-5":   (3.00, 3.75, 6.00, 0.30, 15.00),
    "claude-sonnet-4":     (3.00, 3.75, 6.00, 0.30, 15.00),
    "claude-haiku-4-5":    (1.00, 1.25, 2.00, 0.10, 5.00),
    "claude-haiku-3-5":    (0.80, 1.00, 1.60, 0.08, 4.00),
}

# Modo rápido (/fast). Solo existe en Opus 5 y Opus 4.8, solo en la API de primera
# parte, y factura entrada/salida a 10/50 $ en vez de 5/25. Los multiplicadores de caché
# se aplican SOBRE esa base (1,25x / 2x / 0,1x), como dice la página de precios.
TARIFAS_RAPIDO = {
    "claude-opus-5":   (10.00, 12.50, 20.00, 1.00, 50.00),
    "claude-opus-4-8": (10.00, 12.50, 20.00, 1.00, 50.00),
}

CLASES = ("entrada", "escritura_5m", "escritura_1h", "lectura", "salida")


def tarifa_de(modelo, veloz):
    """Tarifa del modelo, o None si no se conoce. El id que escriben los transcripts
    puede llevar sufijo de fecha ('claude-haiku-4-5-20251001'), así que tras fallar la
    coincidencia exacta se busca el prefijo conocido más largo -- el más largo y no el
    primero, para que 'claude-opus-4-5' no se coma a un futuro 'claude-opus-4-5-1'."""
    tabla = TARIFAS_RAPIDO if veloz else TARIFAS
    if modelo in tabla:
        return tabla[modelo]
    candidatos = [k for k in tabla if modelo.startswith(k)]
    if candidatos:
        return tabla[max(candidatos, key=len)]
    # Un modelo en modo rápido que no esté en la tabla de rápido no es "sin tarifa":
    # es un modelo normal al que /fast no se le aplica. Se valora a tarifa estándar.
    return tarifa_de(modelo, False) if veloz else None


def tokens_de_usage(usage):
    """Las cinco cifras de tokens de un usage, sumando iterations cuando las haya. Ver
    la trampa nº1 de la cabecera: el top-level puede quedarse corto o venir a cero."""
    trozos = usage.get("iterations")
    if not isinstance(trozos, list) or not trozos:
        trozos = [usage]
    t = dict.fromkeys(CLASES, 0)
    for tr in trozos:
        if not isinstance(tr, dict):
            continue
        t["entrada"] += tr.get("input_tokens", 0) or 0
        t["lectura"] += tr.get("cache_read_input_tokens", 0) or 0
        t["salida"] += tr.get("output_tokens", 0) or 0
        escritas = tr.get("cache_creation_input_tokens", 0) or 0
        desglose = tr.get("cache_creation")
        if isinstance(desglose, dict):
            e5 = desglose.get("ephemeral_5m_input_tokens", 0) or 0
            e1 = desglose.get("ephemeral_1h_input_tokens", 0) or 0
            # Si el desglose no cuadra con el escalar, manda el escalar y la diferencia
            # se imputa al TTL barato: infravalorar es el error visible, no el silencioso.
            if e5 + e1 != escritas:
                e5 = max(escritas - e1, 0)
            t["escritura_5m"] += e5
            t["escritura_1h"] += e1
        else:
            t["escritura_5m"] += escritas
    return t


def coste_de(tokens, tarifa):
    """Dólares de un paquete de tokens. None si no hay tarifa: cero se lee como gratis."""
    if tarifa is None:
        return None
    return sum(tokens[c] * tarifa[i] for i, c in enumerate(CLASES)) / 1_000_000


def dia_local(marca):
    """Fecha local (AAAA-MM-DD) de una marca ISO en UTC. Local y no UTC porque los días
    de trabajo de la bitácora son días de reloj de pared, no de meridiano."""
    if not marca:
        return "?"
    try:
        return datetime.fromisoformat(marca.replace("Z", "+00:00")).astimezone().strftime("%Y-%m-%d")
    except ValueError:
        return "?"


def recolectar(carpeta_proyectos):
    """Un registro por mensaje de assistant ÚNICO en toda la carpeta. Devuelve también
    el recuento de lo descartado, que se imprime en vez de callarse."""
    mensajes = {}
    duplicados = sinteticos = ilegibles = 0
    for jsonl in sorted(Path(carpeta_proyectos).glob("*/*.jsonl")):
        try:
            f = open(jsonl, encoding="utf-8", errors="replace")
        except OSError:
            continue
        with f:
            for linea in f:
                # Filtro barato antes de parsear: la inmensa mayoría de las líneas son
                # del usuario o resultados de herramienta y no llevan usage. Con 286 MB
                # en disco, esto es la diferencia entre segundos y minutos.
                if '"usage"' not in linea:
                    continue
                try:
                    obj = json.loads(linea)
                except json.JSONDecodeError:
                    ilegibles += 1
                    continue
                if obj.get("type") != "assistant":
                    continue
                mensaje = obj.get("message")
                if not isinstance(mensaje, dict):
                    continue
                usage = mensaje.get("usage")
                if not isinstance(usage, dict):
                    continue
                modelo = mensaje.get("model") or "?"
                if modelo == "<synthetic>":
                    sinteticos += 1
                    continue
                clave = mensaje.get("id") or obj.get("requestId") or obj.get("uuid")
                marca = obj.get("timestamp") or ""
                previo = mensajes.get(clave)
                if previo is not None:
                    duplicados += 1
                    # Se queda la aparición más antigua: es la sesión que lo pagó.
                    if marca and marca < previo["marca"]:
                        previo.update(marca=marca, dia=dia_local(marca),
                                      sesion=jsonl.stem, proyecto=jsonl.parent.name)
                    continue
                mensajes[clave] = {
                    "sesion": jsonl.stem,
                    "proyecto": jsonl.parent.name,
                    "marca": marca,
                    "dia": dia_local(marca),
                    "modelo": modelo,
                    "veloz": usage.get("speed") == "fast",
                    "tokens": tokens_de_usage(usage),
                }
    return list(mensajes.values()), {
        "duplicados_suprimidos": duplicados,
        "sinteticos_descartados": sinteticos,
        "lineas_ilegibles": ilegibles,
    }


def acumular(destino, clave, registro):
    fila = destino.get(clave)
    if fila is None:
        fila = destino[clave] = {
            "mensajes": 0, "coste": 0.0, "sin_tarifa": 0, "modelos": set(),
            "dia_min": registro["dia"],
            "tokens": dict.fromkeys(CLASES, 0),
        }
    fila["mensajes"] += 1
    fila["modelos"].add(registro["modelo"])
    fila["dia_min"] = min(fila["dia_min"], registro["dia"])
    for c in CLASES:
        fila["tokens"][c] += registro["tokens"][c]
    if registro["coste"] is None:
        fila["sin_tarifa"] += 1
    else:
        fila["coste"] += registro["coste"]
    return fila


def corto(nombre):
    """'C--Users-Oscar-repos-bitacora-project' -> 'bitacora-project'."""
    for prefijo in ("C--Users-Oscar-repos-", "c--Users-Oscar-repos-",
                    "C--Users-Oscar-", "c--Users-Oscar-"):
        if nombre.startswith(prefijo):
            return nombre[len(prefijo):] or "(raiz)"
    return nombre


def miles(n):
    return f"{n:,}".replace(",", ".")


def dinero(fila):
    """Coste de una fila, SIN colapsar 'no lo se' en 'cero'. Una fila entera sin tarifa
    no vale 0,00 $: vale un valor desconocido, y se escribe como tal. Si solo parte de
    la fila tiene tarifa, el numero lleva un '+?' que dice que hay mas por debajo."""
    if fila["sin_tarifa"] == fila["mensajes"]:
        return "s/tarifa"
    if fila["sin_tarifa"]:
        return f"{fila['coste']:.2f}+?"
    return f"{fila['coste']:.2f}"


def main():
    ap = argparse.ArgumentParser(
        description="Coste en dolares de las sesiones de Claude Code, por sesion, modelo y dia.")
    ap.add_argument("--carpeta-proyectos", default=os.path.expanduser("~/.claude/projects"),
                    help="raiz de los <proyecto>/<sesion>.jsonl (por defecto ~/.claude/projects)")
    ap.add_argument("--proyecto", help="filtra por subcadena del nombre de proyecto")
    ap.add_argument("--dias", type=int, help="solo los ultimos N dias")
    ap.add_argument("--desde", help="fecha minima inclusive, AAAA-MM-DD")
    ap.add_argument("--hasta", help="fecha maxima inclusive, AAAA-MM-DD")
    ap.add_argument("--top", type=int, default=15,
                    help="cuantas sesiones listar, las mas caras primero (0 = ninguna)")
    ap.add_argument("--resumen", action="store_true",
                    help="solo los totales: la salida mas barata de meter en un chat")
    ap.add_argument("--json", metavar="RUTA",
                    help="ademas, vuelca el detalle a ese fichero ('-' para stdout)")
    args = ap.parse_args()

    if hasattr(sys.stdout, "reconfigure"):
        # La consola de Windows no siempre habla UTF-8; que un acento no tumbe el informe.
        sys.stdout.reconfigure(errors="replace")

    registros, descartes = recolectar(args.carpeta_proyectos)
    if not registros:
        print(f'No se encontraron mensajes con "usage" en {args.carpeta_proyectos}', file=sys.stderr)
        return 0

    desde = args.desde
    if args.dias:
        limite = (datetime.now() - timedelta(days=args.dias)).strftime("%Y-%m-%d")
        desde = max(desde, limite) if desde else limite

    filtrados = []
    for r in registros:
        if args.proyecto and args.proyecto.lower() not in r["proyecto"].lower():
            continue
        if desde and r["dia"] < desde:
            continue
        if args.hasta and r["dia"] > args.hasta:
            continue
        r["tarifa"] = tarifa_de(r["modelo"], r["veloz"])
        r["coste"] = coste_de(r["tokens"], r["tarifa"])
        filtrados.append(r)

    if not filtrados:
        print("Ningun mensaje pasa los filtros indicados.", file=sys.stderr)
        return 0

    por_sesion, por_modelo, por_dia = {}, {}, {}
    envoltorio = {}
    for r in filtrados:
        acumular(por_sesion, (r["proyecto"], r["sesion"]), r)
        acumular(por_modelo, r["modelo"] + (" (rapido)" if r["veloz"] else ""), r)
        acumular(por_dia, r["dia"], r)
        acumular(envoltorio, "total", r)
    total = envoltorio["total"]

    tok_total = sum(total["tokens"].values())
    dias = sorted(por_dia)

    # El porcentaje que importa es el del GASTO, no el de los tokens: es el numero que
    # justifica cortar la sesion (58 % medido en agosto de 2026).
    coste_lectura = sum(r["tokens"]["lectura"] * r["tarifa"][3] / 1_000_000
                        for r in filtrados if r["tarifa"])
    pct_lectura = (100.0 * coste_lectura / total["coste"]) if total["coste"] else 0.0

    print(f"Periodo:   {dias[0]} .. {dias[-1]}  ({len(dias)} dia(s) con actividad)")
    print(f"Sesiones:  {len(por_sesion)}   mensajes del assistant: {miles(total['mensajes'])}")
    print(f"Tokens:    {miles(tok_total)}   COSTE: {total['coste']:.2f} $")
    print(f"  de los cuales, releer contexto ya enviado (cache_read): {coste_lectura:.2f} $"
          f" = {pct_lectura:.0f} % del gasto")
    if total["sin_tarifa"]:
        print(f"  ATENCION: {total['sin_tarifa']} mensaje(s) de modelo SIN TARIFA CONOCIDA."
              f" Sus tokens estan contados pero su coste NO: el total va por debajo del real.")
    partes = [f"{k}={miles(v)}" for k, v in descartes.items() if v]
    if partes:
        print("  descartes: " + "  ".join(partes))
    print()

    if not args.resumen:
        fmt = "{:<26} {:>9} {:>12} {:>12} {:>12} {:>13} {:>12} {:>10}"
        print(fmt.format("modelo", "mensajes", "entrada", "escr.5m", "escr.1h",
                         "lectura", "salida", "coste $"))
        print("-" * 111)
        for modelo, fila in sorted(por_modelo.items(), key=lambda kv: -kv[1]["coste"]):
            t = fila["tokens"]
            print(fmt.format(modelo[:26], miles(fila["mensajes"]), miles(t["entrada"]),
                             miles(t["escritura_5m"]), miles(t["escritura_1h"]),
                             miles(t["lectura"]), miles(t["salida"]), dinero(fila)))
        print()

        fmt_d = "{:<12} {:>9} {:>14} {:>10}   {}"
        print(fmt_d.format("dia", "mensajes", "tokens", "coste $", "modelos"))
        print("-" * 90)
        for dia in dias:
            fila = por_dia[dia]
            print(fmt_d.format(dia, miles(fila["mensajes"]), miles(sum(fila["tokens"].values())),
                               dinero(fila),
                               ", ".join(sorted(m.replace("claude-", "") for m in fila["modelos"]))[:38]))
        print()

        if args.top:
            fmt_s = "{:<10} {:<26} {:<12} {:>9} {:>14} {:>10}"
            print(fmt_s.format("sesion", "proyecto", "dia", "mensajes", "tokens", "coste $"))
            print("-" * 85)
            caras = sorted(por_sesion.items(), key=lambda kv: -kv[1]["coste"])[:args.top]
            for (proyecto, sesion), fila in caras:
                print(fmt_s.format(sesion[:8], corto(proyecto)[:26], fila["dia_min"],
                                   miles(fila["mensajes"]), miles(sum(fila["tokens"].values())),
                                   dinero(fila)))
            if len(por_sesion) > args.top:
                print(f"... y {len(por_sesion) - args.top} sesion(es) mas"
                      f" (--top 0 quita la tabla, --top {len(por_sesion)} las saca todas)")
            print()

    if args.json:
        def limpia(d):
            return {("|".join(k) if isinstance(k, tuple) else k):
                    {**v, "modelos": sorted(v["modelos"]),
                     "coste_incompleto": bool(v["sin_tarifa"])} for k, v in d.items()}
        salida = {
            "generado": datetime.now().astimezone().isoformat(timespec="seconds"),
            "carpeta_proyectos": str(args.carpeta_proyectos),
            "tarifas_consultadas": "2026-09-04 platform.claude.com/docs/en/about-claude/pricing",
            "filtros": {"proyecto": args.proyecto, "desde": desde, "hasta": args.hasta},
            "descartes": descartes,
            "total": {**limpia(envoltorio)["total"], "coste_cache_read": round(coste_lectura, 6)},
            "por_modelo": limpia(por_modelo),
            "por_dia": limpia(por_dia),
            "por_sesion": limpia(por_sesion),
        }
        texto = json.dumps(salida, indent=1, ensure_ascii=False)
        if args.json == "-":
            print(texto)
        else:
            Path(args.json).write_text(texto, encoding="utf-8")
            print(f"Detalle en JSON escrito en {args.json}")

    # Informe, no comprobacion: nunca tumba nada.
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
