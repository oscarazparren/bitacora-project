#!/bin/bash
# Bitácora — hook UserPromptSubmit: avisa cuando sale a cuenta cortar la sesión.
#
# La tercera pieza. Las otras dos miran el contenido; esta mira el COSTE:
#   sessionstart-leer.sh      -> lee la bitácora al abrir      (no perder contexto)
#   sessionstop-comprobar.sh  -> exige anotar antes de cerrar  (no perder trabajo)
#   ESTA                      -> avisa de cuándo conviene cerrar (no pagar de más)
#
# POR QUÉ EXISTE. NOTAS-DE-CAMPO.md razona el momento de anotar sobre un solo eje:
# la PÉRDIDA (de ahí que PreCompact sea el disparo bueno). Falta el otro eje: el
# COSTE. Cada turno reenvía toda la conversación, así que el precio por turno crece
# sin parar, mientras que escribir una entrada de bitácora cuesta siempre lo mismo.
# Llega un punto en que arrastrar el historial cuesta más de lo que aporta, y ahí
# lo rentable es cortar: volcar a la bitácora y abrir sesión nueva leyéndola.
#
# MÉTRICA: TOKENS, NO MEGABYTES. Hasta el 29-ago-2026 el umbral era el peso en
# bytes del fichero .jsonl (2 MB / 3,5 MB). Calibrado ese día sobre 56 sesiones
# reales: el corte de 2 MB correspondía a contextos de entre 58k y 394k tokens
# según la sesión -- un factor 6,8x de un lado a otro del mismo umbral. La razón
# es que el peso en bytes mezcla dos cosas que no pesan igual: bloques de
# pensamiento y resultados de herramientas (que sí engordan el fichero pero no
# todos entran en el contexto que se reenvía) frente a los tokens de entrada que
# de verdad se facturan y se reenvían cada turno. rho(MB, tokens) = 0,927 en esa
# muestra: hay correlación, pero no la precisión que hacía falta para un umbral.
#
# La métrica correcta es la que ya reporta la API en cada turno: el campo "usage"
# del ÚLTIMO mensaje de assistant con uso registrado. Se suman:
#   cache_read_input_tokens + cache_creation_input_tokens + input_tokens
# que es el contexto real que se reenvía en el turno siguiente. output_tokens NO
# cuenta -- no se reenvía. Y input_tokens por sí solo es ruido: en la misma
# muestra de 56 sesiones era el 0,0% del total, todo el peso está en los dos
# campos de caché. scripts/calibrar-umbral.py regenera esta distribución sobre
# las sesiones que haya en el disco en cada momento.
#
# Y NO ES SOLO DINERO: con el contexto cargado el agente falla más -- olvidos de
# rutina, conclusiones dadas por verificadas sin estarlo.
#
# QUÉ HACE Y QUÉ NO. Mide y avisa; no decide. El umbral es una heurística, no una
# fórmula: para calcular el punto exacto haría falta saber cuántos turnos quedan,
# y eso no lo sabe nadie. Da los datos (tokens de contexto, turnos, modelo en uso)
# e inyecta la sugerencia; el agente decide si tiene sentido cortar AHÍ y si al
# abrir la nueva conviene mantener o cambiar de modelo -- eso depende del trabajo
# que venga, que el hook no puede saber.
#
# REGALO DEL CORTE: cambiar de modelo tiene un peaje (se pierde la caché de
# prompt, que va ligada al modelo). Cortar la sesión tira esa caché igualmente,
# así que EN EL INSTANTE DEL CORTE cambiar de modelo sale gratis. Por eso el aviso
# lleva el modelo en uso: es el único momento en que esa decisión no cuesta nada.
#
# Configuración: ~/.claude/bitacora.conf (las mismas de siempre, más las de aquí).
# Sin dependencias: wc, grep y sed. Nada de jq ni node -- no se pueden dar por
# instalados (jq no lo estaba en el Git Bash donde se escribió esto).

set -uo pipefail

CONF="${BITACORA_CONF:-$HOME/.claude/bitacora.conf}"
# shellcheck disable=SC1090
[ -f "$CONF" ] && . "$CONF"

# Umbrales de TOKENS de contexto (no bytes). Calibrados el 29-ago-2026 sobre 56
# sesiones reales -- ver la cabecera de este fichero para el porqué del cambio
# de métrica, y scripts/calibrar-umbral.py para reproducir la calibración.
AVISO="${BITACORA_CONTEXTO_AVISO_TOKENS:-250000}"     # ~250k: conviene ir cerrando
URGENTE="${BITACORA_CONTEXTO_URGENTE_TOKENS:-400000}" # ~400k: cerrar ya
# Para no repetir el aviso en cada mensaje una vez cruzado el umbral: se recuerda
# a qué escalón se avisó por última vez en esta sesión.
MARCAS="${BITACORA_CONTEXTO_MARCAS:-$HOME/.claude/bitacora-contexto-visto}"

entrada=$(cat)

# El id de sesión viene en el JSON de stdin. Sin jq: se saca con sed, y si no
# aparece no se hace nada (mejor callar que adivinar).
sesion=$(printf '%s' "$entrada" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
[ -n "$sesion" ] || exit 0

# BITACORA_CONTEXTO_AVISO/URGENTE (en bytes) quedaron RETIRADAS con este cambio.
# Una variable que ya no hace nada tiene que decirlo -- ver la retirada de
# BITACORA_MAX_LINEAS para el motivo: quien la tenga puesta cree que sigue
# controlando el corte, y no controla nada. OJO: esto va por additionalContext
# (stdout), NO por stderr -- el wrapper de este hook en settings.json redirige
# stderr a /dev/null, así que un aviso por ahí no lo vería nunca nadie.
if [ -n "${BITACORA_CONTEXTO_AVISO:-}" ] || [ -n "${BITACORA_CONTEXTO_URGENTE:-}" ]; then
  if ! { [ -f "$MARCAS" ] && grep -qx "$sesion	config" "$MARCAS" 2>/dev/null; }; then
    printf '%s\t%s\n' "$sesion" "config" >> "$MARCAS" 2>/dev/null
    printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"AVISO DE CONFIGURACIÓN (bitacora-project, no lo ha escrito el usuario). BITACORA_CONTEXTO_AVISO/URGENTE (en bytes) ya no hacen nada -- las sustituyen BITACORA_CONTEXTO_AVISO_TOKENS y BITACORA_CONTEXTO_URGENTE_TOKENS en ~/.claude/bitacora.conf. Dile al usuario, de pasada y sin interrumpir lo que esté haciendo, que puede quitar las viejas de su bitacora.conf cuando tenga un momento."}}\n'
    exit 0
  fi
fi

# El transcript se busca por nombre en vez de derivar la carpeta desde el cwd:
# el nombre de proyecto lleva una transformación de la ruta que puede cambiar, y
# un `find` acotado no se equivoca.
transcript=$(find "$HOME/.claude/projects" -maxdepth 2 -name "$sesion.jsonl" -type f 2>/dev/null | head -1)
[ -n "$transcript" ] && [ -f "$transcript" ] || exit 0

# Último bloque "usage" del transcript: es el turno más reciente con coste
# registrado. Se acota entre "usage":{ y "output_tokens_details" -- los tres
# campos que hacen falta van siempre ahí delante, antes de esa clave, así que no
# hace falta parsear JSON de verdad (nada de jq/node, ver cabecera). El objeto
# "iterations" repite estos mismos nombres de campo más abajo en la misma línea,
# por eso se acota la ventana en vez de buscar en la línea entera.
ultima_usage=$(grep -oE '"usage":\{[^}]*"output_tokens_details"' "$transcript" 2>/dev/null | tail -1)
[ -n "$ultima_usage" ] || exit 0

campo() {
  printf '%s' "$ultima_usage" | sed -n "s/.*\"$1\":\([0-9]*\).*/\1/p"
}
in_tok=$(campo input_tokens)
cache_creacion=$(campo cache_creation_input_tokens)
cache_lectura=$(campo cache_read_input_tokens)
[ -n "$in_tok" ] && [ -n "$cache_creacion" ] && [ -n "$cache_lectura" ] || exit 0

tokens=$(( in_tok + cache_creacion + cache_lectura ))

if   [ "$tokens" -ge "$URGENTE" ]; then escalon="urgente"
elif [ "$tokens" -ge "$AVISO" ];   then escalon="aviso"
else exit 0
fi

# Un aviso por escalón y sesión: repetirlo en cada mensaje sería exactamente el
# error que ya está documentado en NOTAS-DE-CAMPO.md ("el aviso salía en todos los
# turnos y se leía como una tarea pendiente que nunca se cerraba").
if [ -f "$MARCAS" ] && grep -qx "$sesion	$escalon" "$MARCAS" 2>/dev/null; then
  exit 0
fi
printf '%s\t%s\n' "$sesion" "$escalon" >> "$MARCAS" 2>/dev/null

turnos=$(grep -c '"type":"assistant"' "$transcript" 2>/dev/null || echo 0)
modelo=$(grep -o '"model":"[^"]*"' "$transcript" 2>/dev/null | tail -1 | sed 's/.*:"//;s/"//')
[ -n "$modelo" ] || modelo="desconocido"
tokens_k="$(( tokens / 1000 ))k tokens"

if [ "$escalon" = "urgente" ]; then
  cabecera="Esta sesión ya es MUY larga ($tokens_k de contexto, $turnos turnos). Cortar aquí sale claramente a cuenta."
else
  cabecera="Esta sesión se está haciendo larga ($tokens_k de contexto, $turnos turnos). Es buen momento para cortar."
fi

# Instrucción para el agente, no texto para repetir literalmente.
printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"AVISO DE CONTEXTO (bitacora-project, no lo ha escrito el usuario). %s Modelo en uso: %s. Responde primero a lo que te ha preguntado el usuario, con normalidad; y AL FINAL, en un apartado breve y aparte, sugiérele cerrar esta sesión y abrir otra: anotas en la bitácora del repo lo que haga falta, y la sesión nueva arranca leyéndola. Di también si al abrirla conviene mantener el modelo actual o cambiarlo, razonándolo con el trabajo que venga ahora (cortar tira la caché igualmente, así que cambiar de modelo en ese momento no cuesta nada). Si el usuario está a mitad de algo que no conviene interrumpir, dilo y propón cerrar al terminarlo. No repitas este aviso si ya lo has dado."}}\n' "$cabecera" "$modelo"
exit 0
