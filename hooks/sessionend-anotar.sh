#!/bin/bash
# SessionEnd: deja UNA línea diciendo que esta sesión cerró, y cómo. Nada más.
#
# QUÉ NO HACE, Y ES LO IMPORTANTE. No juzga si la sesión anotó, no llama a git, no toca
# el repo, no escribe bitácora. Eso lo hace `scripts/auditar-sesiones.sh` al arrancar la
# sesión siguiente, que es donde hay presupuesto y donde alguien puede leer el resultado.
#
# POR QUÉ ESA SEPARACIÓN. Es la lección nº4 del proyecto, aplicada de frente: el hook que
# murió por timeout escribía su propia línea de éxito 22 s después de estar muerto, y por
# eso los números cuadraban y no llegaba nada. La conclusión fue que quien mide no puede
# ser quien ejecuta. Aquí: **este fichero no es la fuente de verdad de nada**. El auditor
# comprueba el ARTEFACTO (el commit que toca la BITACORA.md) y el transcript del disco;
# esta línea solo ENRIQUECE, aportando el motivo del cierre, que no está en ningún otro
# sitio. Si este hook no llega a correr, el auditor funciona igual -- y de hecho la
# AUSENCIA de línea es en sí misma el dato más útil: la sesión no cerró limpio.
#
# POR QUÉ NO SE CUELGA DE sessionend-foto.sh. Los hooks de SessionEnd COMPARTEN un
# presupuesto de 1,5 s (elevable con `timeout` propio). La foto hace `ssh` con tope de
# 8 s: colgar de ella este registro sería dejar que un problema de red se lleve por
# delante el apunte. Y sus semánticas de fallo son opuestas -- la foto es idempotente y
# el arranque siguiente la rehace; el momento de una sesión que se cierra no vuelve.
#
# POR ESO NO HAY NI UN SUBPROCESO EN EL CAMINO NORMAL: ni cat, ni sed, ni date. Todo con
# builtins de bash ($EPOCHSECONDS, printf %(...)T, expansión de parámetros). En Git Bash
# sobre Windows lanzar un proceso cuesta más que el trabajo que hace -- ya está medido en
# la cabecera de sessionstart-leer.sh -- y aquí el presupuesto es de 1,5 s compartidos.
#
# Instalación en ~/.claude/settings.json: una entrada PROPIA bajo SessionEnd, junto a la
# de la foto (los hooks del mismo evento corren en paralelo, así que no se esperan):
#   { "type": "command",
#     "command": "bash \"$HOME/repos/bitacora-project/hooks/sessionend-anotar.sh\" 2>/dev/null || true",
#     "timeout": 5 }
set -uo pipefail

CONF="${BITACORA_CONF:-$HOME/.claude/bitacora.conf}"
# shellcheck disable=SC1090
[ -f "$CONF" ] && . "$CONF"

REGISTRO="${BITACORA_REGISTRO_SESIONES:-$HOME/.claude/bitacora-sesiones}"

# Sin 'cat': read es builtin. La entrada del hook es una línea de JSON.
IFS= read -r entrada || exit 0
[ -n "$entrada" ] || exit 0

# Sin 'sed': expansión de parámetros. Devuelve vacío si la clave no está, que es lo que
# queremos -- adivinar sería peor que dejar el campo en blanco.
extraer() {
  local clave="$1" resto
  resto="${entrada#*\"$clave\":\"}"
  [ "$resto" = "$entrada" ] && { printf ''; return; }
  printf '%s' "${resto%%\"*}"
}

sesion=$(extraer session_id)
[ -n "$sesion" ] || exit 0

motivo=$(extraer reason);          [ -n "$motivo" ] || motivo="sin-motivo"
cwd=$(extraer cwd);                [ -n "$cwd" ]    || cwd="?"
transcript=$(extraer transcript_path)

# $EPOCHSECONDS y printf %(...)T son builtins (bash 5.0+ y 4.2+). El respaldo a `date`
# NO es adorno: en un bash sin ellos la línea saldría con la fecha vacía y el auditor
# leería basura. Comprobado el 29-ago que las dos máquinas llevan 5.3.15; el respaldo se
# queda por si aparece una tercera.
epoch=${EPOCHSECONDS:-}
if [ -n "$epoch" ]; then
  printf -v fecha '%(%Y-%m-%d %H:%M:%S)T' "$epoch"
else
  epoch=$(date +%s); fecha=$(date '+%Y-%m-%d %H:%M:%S')
fi

# Las barras invertidas de las rutas de Windows se dejan tal cual: el auditor no las
# interpreta, y "arreglarlas" aquí sería inventarse un formato que nadie ha pedido.
printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
  "$epoch" "$fecha" "$sesion" "$motivo" "$cwd" "$transcript" >> "$REGISTRO" 2>/dev/null

exit 0
