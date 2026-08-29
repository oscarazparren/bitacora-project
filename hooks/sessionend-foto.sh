#!/bin/bash
# SessionEnd: rehace la foto de configuración de esta máquina en el servidor.
#
# POR QUÉ AL CIERRE Y NO SOLO AL ARRANQUE. Lo levantó Oscar el 29-ago-2026: si cambias
# la configuración A MITAD de sesión, la foto del arranque es anterior al cambio y la
# otra máquina no lo ve hasta que ESTA vuelva a arrancar. Un retraso de una sesión
# entera, justo en el dato que sirve para detectar descuadres.
#
# POR QUÉ NO SOLO AL CIERRE. `SessionEnd` no siempre dispara: si se cierra la ventana
# con la X, el proceso muere o se va la luz, no salta. Si la foto dependiera solo de
# esto, se quedaría vieja SIN QUE NADIE SEPA QUE ESTÁ VIEJA -- el fallo silencioso de
# siempre. Por eso hay dos disparos: el del arranque garantiza que la foto acabe
# llegando, y este quita el retraso cuando el cierre es limpio.
#
# NO redacta nada ni necesita contexto: copia dos ficheros de configuración. Es una
# tarea mecánica, así que no le aplica la nota de campo sobre por qué escribir la
# BITÁCORA al cerrar sesión es mala idea -- eso va de pedirle PROSA a un modelo con el
# contexto ya compactado. Esto no le pide nada a nadie.
#
# Instalación en ~/.claude/settings.json:
#   "SessionEnd": [
#     { "hooks": [ { "type": "command",
#                    "command": "bash \"$HOME/repos/bitacora-project/hooks/sessionend-foto.sh\" 2>/dev/null || true",
#                    "timeout": 10 } ] }
#   ]
set -uo pipefail

FOTO_SH=""
for f in "$HOME/repos/bitacora-project/scripts/foto-config.sh" \
         "$(dirname "$0")/../scripts/foto-config.sh"; do
  [ -f "$f" ] && { FOTO_SH="$f"; break; }
done
[ -z "$FOTO_SH" ] && exit 0

# Tope corto y duro: al cerrar sesión nadie está mirando, y un hook de cierre colgado
# es peor que una foto con un arranque de retraso. Si no da tiempo, la del próximo
# arranque lo recoge igual -- que es exactamente para lo que está el otro disparo.
BITACORA_FOTO_MOMENTO=cierre timeout 8 bash "$FOTO_SH" >/dev/null 2>&1 || true
exit 0
