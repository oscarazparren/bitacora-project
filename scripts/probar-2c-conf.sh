#!/bin/bash
# Bitácora — BANCO DE PRUEBAS del comparador de configuración (sección 2c del arranque).
#
# POR QUÉ EXISTE
# =============
# El 7-sep-2026 se arregló un FALSO POSITIVO que llevaba desde el 30-ago saliendo en cada
# arranque de las dos máquinas: el filtro que decide si una clave ausente de tu
# bitacora.conf «cambia algo de verdad» comparaba el default del código con el valor del
# .example COMO TEXTO PLANO. Cuando el default pasa por una variable local del script
# —BITACORA_SUENO_ESTADO cae en la ruta de SUENOS, y el .example la documenta ya
# expandida— las dos partes dicen lo mismo con letras distintas, y el comparador cantaba
# diferencia. Era el ÚNICO renglón que sobrevivía al filtro: el aviso salía siempre para
# decir una sola cosa, y esa cosa era falsa.
#
# La sección 2c era la única del hook sin banco, y el arreglo mete heurística nueva
# (resolver variables locales) de la que nadie podría demostrar nada. Las dos funciones
# son PURAS —entra cadena, sale cadena— así que no hay excusa.
#
# Como probar-1d-deriva.sh y probar-indice-clon.sh: las funciones se EXTRAEN EN VIVO del
# hook, no se copian aquí. Así se prueba la versión que haya, no una copia que se quedó
# pegada el día que se escribió el banco.
#
# USO:
#   bash scripts/probar-2c-conf.sh                 # contra hooks/sessionstart-leer.sh
#   bash scripts/probar-2c-conf.sh /ruta/hook.sh   # contra otra copia

set -uo pipefail

AQUI="$(cd "$(dirname "$0")" && pwd)"
HOOK="${1:-$AQUI/../hooks/sessionstart-leer.sh}"
[ -f "$HOOK" ] || { echo "no encuentro el hook: $HOOK" >&2; exit 2; }

# --- Extraer las dos funciones del hook real --------------------------------
BLOQUE=$(awk '
  /^  quedan_vars\(\) \{/ { f=1 }
  f { print }
  f && /^  \}$/ && seen { exit }
  f && /^  resolver_locales\(\) \{/ { seen=1 }
' "$HOOK")
[ -n "$BLOQUE" ] || { echo "no encuentro quedan_vars/resolver_locales en $HOOK" >&2; exit 2; }
case "$BLOQUE" in
  *'resolver_locales() {'*) : ;;
  *) echo "el bloque extraído no trae resolver_locales" >&2; exit 2 ;;
esac

TMP=$(mktemp -d 2>/dev/null) || { echo "mktemp -d falló" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/base/hooks" "$TMP/base/scripts" "$TMP/base/servidor"
printf '%s\n' "$BLOQUE" > "$TMP/funciones.sh"

N=0; PASA=0; FALLA=0
ok()  { N=$((N+1)); PASA=$((PASA+1));   printf '  ok   %2d. %s\n' "$N" "$1"; }
mal() { N=$((N+1)); FALLA=$((FALLA+1)); printf '  MAL  %2d. %s\n' "$N" "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; return 0; }

# Corre una función del hook con BASE_DIR apuntando al árbol de mentira.
# El argumento viaja como PARÁMETRO POSICIONAL, nunca interpolado en el texto del script:
# si se interpola, el shell expande el propio "$SUENOS" del caso antes de que la función
# lo vea, y el banco mide su propia comilla en vez del hook.
corre() { # $1 = función, $2 = argumento literal
  bash -c '
    set -uo pipefail
    BASE_DIR="$1"
    . "$2"
    "$3" "$4"
  ' _ "$TMP/base" "$TMP/funciones.sh" "$1" "$2"
}
# Deja un fichero de definiciones locales en el árbol de mentira.
defs() { printf '%s\n' "$2" > "$TMP/base/scripts/$1"; }
limpia() { rm -f "$TMP"/base/scripts/* "$TMP"/base/hooks/* "$TMP"/base/servidor/*; }

echo "── quedan_vars: qué cuenta como 'sin resolver' ──"

esp() { # caso, cadena, esperado(si/no)
  local r; corre quedan_vars "$2" >/dev/null 2>&1; r=$?
  local got=no; [ $r -eq 0 ] && got=si
  [ "$got" = "$3" ] && ok "$1" || mal "$1" "esperaba $3, salió $got"
}
esp "\$HOME solo -> no queda nada por resolver"        '$HOME/.claude/x' no
esp "ruta literal -> no queda nada"                    '/opt/bitacora/x' no
esp "cadena vacía -> no queda nada"                    ''                no
esp "número suelto -> no queda nada"                   '20'              no
esp "variable local -> SÍ queda"                       '$SUENOS/x'       si
esp "\${VAR} con llaves -> SÍ queda"                   '${SUENOS}/x'     si
esp "\$HOME y otra detrás -> SÍ queda (no se para en \$HOME)" '$HOME/$OTRA/x' si

echo "── resolver_locales: expansión de variables locales ──"

res() { # caso, entrada, esperado
  local got; got=$(corre resolver_locales "$2")
  [ "$got" = "$3" ] && ok "$1" || mal "$1" "esperaba [$3], salió [$got]"
}

limpia
defs sueno.sh 'SUENOS="${BITACORA_SUENOS:-$HOME/.claude/bitacora-suenos}"'
res "el caso que motivó el arreglo: \$SUENOS se resuelve" \
    '$SUENOS/propuestas.tsv' '$HOME/.claude/bitacora-suenos/propuestas.tsv'
res "\$HOME se deja SIN expandir, a propósito" \
    '$HOME/.claude/x' '$HOME/.claude/x'
res "cadena sin variables pasa tal cual" '/opt/x' '/opt/x'
res "cadena vacía no revienta" '' ''
res "token sin definición se deja como está" '$NOEXISTE/x' '$NOEXISTE/x'

limpia
defs a.sh 'UNO="${BITACORA_UNO:-$DOS/final}"'
defs b.sh 'DOS="${BITACORA_DOS:-$HOME/medio}"'
res "encadenado de dos saltos" '$UNO' '$HOME/medio/final'

limpia
defs ciclo.sh 'X="${BITACORA_X:-$Y/a}"
Y="${BITACORA_Y:-$X/b}"'
got=$(corre resolver_locales '$X'); rc=$?
[ $rc -eq 0 ] && ok "ciclo X->Y->X: termina, no se cuelga" || mal "ciclo X->Y->X: termina" "rc=$rc"
if corre quedan_vars "$got" >/dev/null 2>&1; then
  ok "ciclo: queda sin resolver -> se dirá como indecidible"
else
  mal "ciclo: queda sin resolver" "resolvió [$got], que no podía saber"
fi

echo "── colisión de nombres: no inventarse la respuesta ──"
limpia
defs uno.sh 'ESTADO="${BITACORA_A:-/opt/uno.txt}"'
defs dos.sh 'ESTADO="${BITACORA_B:-/opt/dos.txt}"'
res "dos definiciones DISTINTAS del mismo nombre -> sin resolver" '$ESTADO' '$ESTADO'
limpia
defs uno.sh 'ESTADO="${BITACORA_A:-/opt/igual.txt}"'
defs dos.sh 'ESTADO="${BITACORA_A:-/opt/igual.txt}"'
res "dos definiciones IDÉNTICAS -> sí se resuelve" '$ESTADO' '/opt/igual.txt'

echo
echo "casos: $N — pasan: $PASA — fallan: $FALLA"
[ "$FALLA" -eq 0 ]
