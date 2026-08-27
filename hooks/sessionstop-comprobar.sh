#!/bin/bash
# Bitácora — hook Stop: bloquea el final de turno si hay trabajo sin anotar.
#
# Compañero de sessionstart-leer.sh, que solo LEE. Este solo fuerza ESCRIBIR: no
# toca el fichero, pero no deja terminar el turno si, en el repo donde se está
# trabajando,
#   1. hay cambios sin commitear, o
#   2. hay commits posteriores al último que tocó la bitácora del repo que
#      tocan otros ficheros (es decir: se subió algo y no se anotó).
#
# Nace de un caso real, 27-ago-2026, kangurea-web: tres commits de contenido
# seguidos sin ninguna entrada en BITACORA.md, hasta que Oscar preguntó por qué
# no había un trigger. La lectura siempre fue automática (este hook lleva
# semanas funcionando); la escritura, para la bitácora DE UN REPO, siempre fue
# manual — lo dice el propio comentario de scripts/anotar.sh. Nunca hubo nada
# que la forzara. Esto lo pone.
#
# Silencioso si: no estamos en un repo git, la carpeta está en BITACORA_IGNORAR,
# o el repo no tiene bitácora propia (no se le impone la convención).
#
# No mira lo que dice el usuario ni cuenta preguntas ni turnos: mira el estado
# de git después de cada uno. Por eso vale igual para "cerramos", "hemos
# terminado por hoy" o cualquier otra frase que corte la sesión con trabajo
# sin anotar — no hace falta reconocer la frase.
#
# No usa jq: no se puede dar por instalado en todas las máquinas (no lo estaba
# en el Git Bash de Windows donde se escribió esto). El JSON de salida se
# construye a mano; el mensaje no lleva comillas dobles, así que no hace falta
# escapar nada.
#
# Configuración: la misma ~/.claude/bitacora.conf que sessionstart-leer.sh —
# ver bitacora.conf.example. Solo usa BITACORA_FICHERO y BITACORA_IGNORAR.

set -uo pipefail

CONF="${BITACORA_CONF:-$HOME/.claude/bitacora.conf}"
# shellcheck disable=SC1090
[ -f "$CONF" ] && . "$CONF"

FICHERO="${BITACORA_FICHERO:-BITACORA.md}"
IGNORAR="${BITACORA_IGNORAR:-*/node_modules/*|*/.claude/*}"

# Misma lógica que sessionstart-leer.sh: carpetas de solo lectura o de
# terceros donde el sistema no debe opinar.
es_carpeta_ignorada() {
  local ruta="$1" patron
  local IFS='|'
  for patron in $IGNORAR; do
    # shellcheck disable=SC2254
    case "$ruta" in $patron) return 0 ;; esac
  done
  return 1
}

RAIZ=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
cd "$RAIZ" 2>/dev/null || exit 0
es_carpeta_ignorada "$RAIZ" && exit 0

# Repo sin bitácora: no es su convención, no se la imponemos desde aquí.
[ -f "$FICHERO" ] || exit 0

uncommitted=$(git status --porcelain 2>/dev/null)

undocumented_count=0
ultimo_commit_bitacora=$(git log -1 --format=%H -- "$FICHERO" 2>/dev/null)
if [ -n "$ultimo_commit_bitacora" ]; then
  undocumented_count=$(git log --format=%H "$ultimo_commit_bitacora"..HEAD -- . ":!$FICHERO" 2>/dev/null | grep -c .)
fi

if [ -z "$uncommitted" ] && [ "$undocumented_count" -eq 0 ]; then
  exit 0
fi

repo_nombre=$(basename "$RAIZ")
msg="$FICHERO sin actualizar en $repo_nombre."
if [ "$undocumented_count" -gt 0 ]; then
  msg="$msg $undocumented_count commit(s) desde la última entrada que no la tocan."
fi
if [ -n "$uncommitted" ]; then
  msg="$msg Hay cambios sin commitear."
fi
msg="$msg Antes de terminar: añade una entrada en $FICHERO (## AAAA-MM-DD — [dispositivo] titular) resumiendo el trabajo y haz commit."

printf '{"decision":"block","reason":"%s"}\n' "$msg"
exit 0
