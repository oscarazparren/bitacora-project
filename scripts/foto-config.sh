#!/bin/bash
# Deja en el servidor una FOTO de la configuración de esta máquina, y (si se le pide)
# devuelve las de las demás.
#
# Por qué existe: `~/.claude/settings.json` y `~/.claude/bitacora.conf` NO viajan por
# git. Un `git pull` trae el script nuevo y deja la conf vieja, y como todas las
# variables tienen valor por defecto, el hook sigue funcionando SIN DECIR NADA. Pasó
# tres veces en un solo día (29-ago-2026) en la misma máquina.
#
# Se llama desde DOS sitios a propósito:
#   - SessionStart (sección 2c del hook): siempre dispara, es el suelo fiable.
#   - SessionEnd: recoge lo que se haya cambiado DURANTE la sesión, que el arranque no
#     puede ver. No basta por sí solo -- si la ventana se cierra con la X o el proceso
#     muere, SessionEnd no salta y la foto se quedaría vieja sin que nadie lo supiera.
# Por eso van las dos: una garantiza que la foto acaba llegando, la otra quita el
# retraso cuando el cierre es limpio.
#
# Uso:  foto-config.sh [--con-otras]
#       --con-otras : además de dejar la propia, imprime las de las demás máquinas.
set -uo pipefail

CONF="${BITACORA_CONF:-$HOME/.claude/bitacora.conf}"
[ -f "$CONF" ] && . "$CONF"

ETIQUETA="${BITACORA_ETIQUETA:-sin-etiqueta}"
FLOTA_SSH="${BITACORA_FLOTA_SSH:-}"
MOMENTO="${BITACORA_FOTO_MOMENTO:-arranque}"   # arranque | cierre
DESTINO="/opt/bitacora/estado/maquinas"

[ -z "$FLOTA_SSH" ] && exit 0

# Los hooks se sacan con grep y no con un parser de JSON a propósito: aquí solo hacen
# falta los NOMBRES de los eventos cableados. El primer intento usaba python con un
# escapado de rutas de Windows, falló, y escribió "no-legible" en la foto -- o sea, se
# equivocó EN SILENCIO y con aspecto de dato. Un dato que puede salir mal tiene que
# salir mal de forma visible, o no salir.
SETTINGS="$HOME/.claude/settings.json"
if [ -f "$SETTINGS" ]; then
  HOOKS=$(grep -oE '"(SessionStart|SessionEnd|UserPromptSubmit|PreCompact|Stop|PreToolUse|PostToolUse)"[[:space:]]*:' "$SETTINGS" 2>/dev/null \
    | tr -d '":' | sed 's/[[:space:]]*$//' | sort -u | tr '\n' ',' | sed 's/,$//')
  [ -z "$HOOKS" ] && HOOKS="ninguno"
else
  HOOKS="sin settings.json"
fi

# La FECHA es obligatoria y va la primera. Sin ella, quien lee la foto no puede
# distinguir una de hace cinco minutos de una de hace cinco días -- y una foto vieja
# leída como actual es peor que no tener foto. Es el mismo fallo que "leer una bitácora
# obsoleta es peor que no leer ninguna", en versión configuración.
FOTO="maquina: $ETIQUETA
foto tomada: $(date '+%Y-%m-%d %H:%M:%S %z') (al $MOMENTO de sesion)
hooks: $HOOKS
$(grep -E '^[A-Z_]+=' "$CONF" 2>/dev/null | sed 's/[[:space:]]*#.*$//; s/[[:space:]]*$//; s/^/conf /' | sort)"

# NO se manda settings.json entero A PROPÓSITO: es un sitio legítimo donde meter claves
# de API en variables de entorno, y un fichero con una clave dentro subido a un sitio
# compartido se queda ahí. Solo van los nombres de los eventos. De bitacora.conf sí van
# nombre y valor, que por diseño no lleva secretos -- pero se comprueba igualmente
# antes de mandarlo, porque "por diseño no lleva" es una suposición y esto sale de la
# máquina.
if printf '%s\n' "$FOTO" | grep -Eqi '(sk-|ghp_|xox[baprs]-|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----|(api[_-]?key|secret|password|token)[[:space:]]*=[[:space:]]*["'"'"']?[A-Za-z0-9_/+.-]{16,})'; then
  echo "BLOQUEADO: la foto parece contener una credencial. No se manda nada." >&2
  exit 2
fi

if [ "${1:-}" = "--con-otras" ]; then
  printf '%s\n' "$FOTO" | ssh -o ConnectTimeout=4 -o BatchMode=yes "$FLOTA_SSH" \
    "mkdir -p '$DESTINO' && cat > '$DESTINO/$ETIQUETA.txt' && grep -H '' '$DESTINO'/*.txt 2>/dev/null"
else
  printf '%s\n' "$FOTO" | ssh -o ConnectTimeout=4 -o BatchMode=yes "$FLOTA_SSH" \
    "mkdir -p '$DESTINO' && cat > '$DESTINO/$ETIQUETA.txt'"
fi
