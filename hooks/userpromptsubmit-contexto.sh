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
# Medido el 28-ago-2026 en kangurea-web: una sesión de trabajo real pesaba 2,5 MB
# de transcript, y todo lo que valía la pena de ella cabía en las dos entradas de
# bitácora que generó -- unos 4 KB. Compresión ~600:1. Lo que se tira es ruido
# (comandos fallidos, salidas largas, rodeos), no señal.
#
# Y NO ES SOLO DINERO: con el contexto cargado el agente falla más -- olvidos de
# rutina, conclusiones dadas por verificadas sin estarlo. En esa misma sesión
# pasaron las dos cosas. Un arranque limpio leyendo la bitácora tiene la misma
# información útil con muchísimo menos ruido donde despistarse.
#
# QUÉ HACE Y QUÉ NO. Mide y avisa; no decide. El umbral es una heurística, no una
# fórmula: para calcular el punto exacto haría falta saber cuántos turnos quedan,
# y eso no lo sabe nadie. Da los datos (peso, turnos, modelo en uso) e inyecta la
# sugerencia; el agente decide si tiene sentido cortar AHÍ y si al abrir la nueva
# conviene mantener o cambiar de modelo -- eso depende del trabajo que venga, que
# el hook no puede saber.
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

# Umbrales de peso del transcript, en bytes. Calibrados con sesiones reales de
# kangurea-web: 734 KB (corta, cómoda), 2,5 MB (larga, ya con despistes), 4,3 MB
# (muy pasada). Se avisa ANTES de llegar a incómodo, no cuando ya duele.
AVISO="${BITACORA_CONTEXTO_AVISO:-2000000}"        # ~2 MB: conviene ir cerrando
URGENTE="${BITACORA_CONTEXTO_URGENTE:-3500000}"    # ~3,5 MB: cerrar ya
# Para no repetir el aviso en cada mensaje una vez cruzado el umbral: se recuerda
# a qué escalón se avisó por última vez en esta sesión.
MARCAS="${BITACORA_CONTEXTO_MARCAS:-$HOME/.claude/bitacora-contexto-visto}"

entrada=$(cat)

# El id de sesión viene en el JSON de stdin. Sin jq: se saca con sed, y si no
# aparece no se hace nada (mejor callar que adivinar).
sesion=$(printf '%s' "$entrada" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
[ -n "$sesion" ] || exit 0

# El transcript se busca por nombre en vez de derivar la carpeta desde el cwd:
# el nombre de proyecto lleva una transformación de la ruta que puede cambiar, y
# un `find` acotado no se equivoca.
transcript=$(find "$HOME/.claude/projects" -maxdepth 2 -name "$sesion.jsonl" -type f 2>/dev/null | head -1)
[ -n "$transcript" ] && [ -f "$transcript" ] || exit 0

peso=$(wc -c < "$transcript" 2>/dev/null | tr -d ' ')
[ -n "$peso" ] || exit 0

if   [ "$peso" -ge "$URGENTE" ]; then escalon="urgente"
elif [ "$peso" -ge "$AVISO" ];   then escalon="aviso"
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
peso_mb=$(( peso / 100000 ))
peso_mb="$(( peso_mb / 10 )),$(( peso_mb % 10 )) MB"

if [ "$escalon" = "urgente" ]; then
  cabecera="Esta sesión ya es MUY larga ($peso_mb, $turnos turnos). Cortar aquí sale claramente a cuenta."
else
  cabecera="Esta sesión se está haciendo larga ($peso_mb, $turnos turnos). Es buen momento para cortar."
fi

# Instrucción para el agente, no texto para repetir literalmente.
printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"AVISO DE CONTEXTO (bitacora-project, no lo ha escrito el usuario). %s Modelo en uso: %s. Responde primero a lo que te ha preguntado el usuario, con normalidad; y AL FINAL, en un apartado breve y aparte, sugiérele cerrar esta sesión y abrir otra: anotas en la bitácora del repo lo que haga falta, y la sesión nueva arranca leyéndola. Di también si al abrirla conviene mantener el modelo actual o cambiarlo, razonándolo con el trabajo que venga ahora (cortar tira la caché igualmente, así que cambiar de modelo en ese momento no cuesta nada). Si el usuario está a mitad de algo que no conviene interrumpir, dilo y propón cerrar al terminarlo. No repitas este aviso si ya lo has dado."}}\n' "$cabecera" "$modelo"
exit 0
