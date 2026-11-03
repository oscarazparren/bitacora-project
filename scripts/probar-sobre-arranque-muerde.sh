#!/bin/bash
# Bitácora — ¿MUERDE probar-sobre-arranque.sh? Se rompe el hook a propósito, de siete
# maneras distintas, y se mira qué casos caen.
#
# POR QUÉ EXISTE. Un banco en verde no prueba que el banco sirva: prueba que hoy no falla.
# La única forma de saber si un candado es un candado es ponerle delante la avería que dice
# parar. Este repo ya se comió un caso que daba verde con el arreglo deshecho (el de "Lo de
# arriba", 6-sep-2026) y otro cuyo comentario prometía una protección que no existía (el del
# titular hostil, 7-sep, encontrado con este mismo script: la mutación M2 NO tumbaba nada).
#
# LO QUE SE ESPERA, y si cambia hay que mirar por qué:
#   M1 el cuerpo vuelve al sobre .................. cae 55
#   M2 el titular pierde la sangría ............... cae el caso de la sangría
#   M3 el aviso de corte dice que es releíble ..... caen 43, 44
#   M4 el systemMessage no avisa del recorte ...... caen 47, 67
#   M5 el recuento se olvida de la forma 'AVISO' .. cae 37
#   M6 el bloque degradado vuelve al FINAL ........ caen 12, 30
#   M7 la rama de bitácora vacía se colapsa ....... caen las de bitácora vacía
#
# Uso:  scripts/probar-sobre-arranque-muerde.sh
# No toca el hook: trabaja sobre copias en un directorio temporal que borra al salir.
set -uo pipefail

AQUI="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$AQUI/.." && pwd)"
HOOK="$REPO/hooks/sessionstart-leer.sh"
BANCO="$REPO/scripts/probar-sobre-arranque.sh"
[ -f "$HOOK" ]  || { echo "no encuentro el hook: $HOOK" >&2; exit 2; }
[ -f "$BANCO" ] || { echo "no encuentro el banco: $BANCO" >&2; exit 2; }

MUT=$(mktemp -d 2>/dev/null) || { echo "mktemp -d falló" >&2; exit 2; }
trap 'rm -rf "$MUT"' EXIT

# M1 — el cuerpo de la bitácora vuelve al sobre (deshace el repliegue entero)
awk '/^# ---------- 1d\. CLAUDE\.md/ && !d {
  print "[ -n \"${RAIZ:-}\" ] && [ -f \"$RAIZ/$FICHERO\" ] && SALIDA=\"${SALIDA}=== CUERPO ==="
  print "$(cat \"$RAIZ/$FICHERO\")"
  print "\""
  d=1 } { print }' "$HOOK" > "$MUT/m1.sh"

# M2 — se quita la sangría del titular en el puntero
sed 's/^  \$TIT_BIT$/$TIT_BIT/' "$HOOK" > "$MUT/m2.sh"

# M3 — el aviso de corte vuelve a decir que lo perdido es releíble
sed 's/^AVISOS de estado, y NO están escritos en ningún otro sitio: compruébalos a mano$/lo que falta esta en la BITACORA.md del repo, abrela con Read./' "$HOOK" > "$MUT/m3.sh"

# M4 — el systemMessage deja de avisar de que la lectura llegó recortada
grep -v 'OJO: la lectura llegó recortada' "$HOOK" > "$MUT/m4.sh"

# M5 — el recuento de avisos se olvida de la forma 'AVISO' y solo cuenta '=== '
sed "s|grep -c '\^\\\\(=== \\\\\|AVISO\\\\)'|grep -c '^=== '|" "$HOOK" > "$MUT/m5.sh"

# M6 — el bloque degradado vuelve al final (la avería fundacional del 6-sep-2026)
sed 's|printf .%s%s%s%s. "\$BLOQUE_DEGRADADO" "\$CABECERA" "\$SALIDA" "\$PIE"|printf "%s%s%s%s" "$CABECERA" "$SALIDA" "$BLOQUE_DEGRADADO" "$PIE"|' "$HOOK" > "$MUT/m6.sh"

# M7 — la rama de "bitácora vacía" se colapsa con la del puntero
sed 's/if \[ "${N_BIT:-0}" -gt 0 \] 2>\/dev\/null; then/if [ "${N_BIT:-0}" -ge 0 ] 2>\/dev\/null; then/' "$HOOK" > "$MUT/m7.sh"

# UNA MUTACIÓN QUE NO MUTA ES UN FALSO VERDE: el banco daría "no cae nada" y se leería
# como "el candado no muerde", cuando lo que pasa es que el sed no ha casado. Se comprueba.
FALLO=0
for m in 1 2 3 4 5 6 7; do
  if cmp -s "$HOOK" "$MUT/m$m.sh"; then
    echo "!!!!!! M$m NO HA CAMBIADO NADA -- la mutación no se aplicó (¿cambió el hook?)" >&2
    FALLO=1
  fi
done
[ "$FALLO" -eq 0 ] || echo

prueba() {
  echo "############ $1"
  bash "$BANCO" "$MUT/$2" 2>&1 | grep -E '^  MAL|^casos:' | sed 's/^/   /'
  echo
}

prueba "M1: el CUERPO de la bitácora vuelve al sobre"          m1.sh
prueba "M2: el titular pierde la sangría de dos espacios"      m2.sh
prueba "M3: el aviso de corte dice que lo perdido es releíble" m3.sh
prueba "M4: el systemMessage no avisa del recorte"             m4.sh
prueba "M5: el recuento de avisos se olvida de la forma AVISO" m5.sh
prueba "M6: el bloque degradado vuelve al FINAL"               m6.sh
prueba "M7: la rama de bitácora vacía se colapsa"              m7.sh
