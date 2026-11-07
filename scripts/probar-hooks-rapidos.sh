#!/bin/bash
# Banco de los dos arreglos de tiempo del 7-nov-2026:
#   - hooks/userpromptsubmit-contexto.sh: el cálculo en Python va en segundo plano y la marca
#     de «ya avisado» solo se escribe cuando el aviso sale de verdad.
#   - hooks/sessionstart-leer.sh: la parte local de la sección 2c se cachea por ficheros.
#
# Todo en un HOME de mentira y con un `python` falso delante en el PATH: no toca ni las
# marcas, ni la caché, ni los transcripts reales, y no depende de que exista una sesión
# grande en el disco.
#
#   bash scripts/probar-hooks-rapidos.sh

set -uo pipefail

AQUI="$(cd "$(dirname "$0")" && pwd)"
CTX="$AQUI/../hooks/userpromptsubmit-contexto.sh"
ARR="$AQUI/../hooks/sessionstart-leer.sh"

TMP=$(mktemp -d 2>/dev/null) || { echo "mktemp -d falló" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

N=0; PASA=0; FALLA=0
ok()  { N=$((N+1)); PASA=$((PASA+1));   printf '  ok   %2d. %s\n' "$N" "$1"; }
mal() { N=$((N+1)); FALLA=$((FALLA+1)); printf '  MAL  %2d. %s\n' "$N" "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; return 0; }
si()  { if eval "$2"; then ok "$1"; else mal "$1" "falló: $2"; fi; }

# --- python falso: cifra fija, o punto de corte fijo; FALSO_PY_TARDA lo hace lento ---
mkdir -p "$TMP/bin"
cat > "$TMP/bin/python" <<'EOF'
#!/bin/bash
sleep "${FALSO_PY_TARDA:-0}"
case " $* " in *" --cifra "*) printf '12.34\r\n' ;; *) printf 'CORTE-DE-PRUEBA compensa a partir de 7 turnos\r\n' ;; esac
EOF
chmod +x "$TMP/bin/python"
export PATH="$TMP/bin:$PATH"

# --- una sesión de 250k tokens en el HOME de mentira ---
export HOME="$TMP/home"
SES="00000000-0000-0000-0000-000000000001"
mkdir -p "$HOME/.claude/projects/p"
printf '%s\n' '{"type":"assistant","message":{"model":"claude-prueba","usage":{"input_tokens":10,"cache_creation_input_tokens":1000,"cache_read_input_tokens":249000,"output_tokens":5,"output_tokens_details":{}}}}' \
  > "$HOME/.claude/projects/p/$SES.jsonl"
MARCAS="$HOME/.claude/bitacora-contexto-visto"
CALC="$MARCAS.calculo"

ctx() { # ejecuta el hook de contexto; deja la salida en $TMP/o y el tiempo en $MS
  local s=$EPOCHREALTIME e
  printf '{"session_id":"%s"}' "$SES" | bash "$CTX" > "$TMP/o" 2>/dev/null
  e=$EPOCHREALTIME; MS=$(( (${e/./} - ${s/./}) / 1000 ))
}
json_ok() { python_real -c 'import json,sys; json.load(open(sys.argv[1], encoding="utf-8"))' "$TMP/o" 2>/dev/null; }
python_real() { local p; p=$(type -ap python | grep -v "^$TMP/" | head -1); [ -n "$p" ] && "$p" "$@"; }
marcado() { grep -qx "$SES	aviso" "$MARCAS" 2>/dev/null; }
reinicia() { rm -rf "$MARCAS" "$CALC"; }

echo "── contexto: cálculo rápido ──"
reinicia; ctx
si "sale el aviso en el mismo mensaje"           'grep -q "DATO DE COSTE" "$TMP/o"'
si "lleva el gasto y el punto de corte"          'grep -q "Van 12.34" "$TMP/o" && grep -q "CORTE-DE-PRUEBA" "$TMP/o"'
si "JSON válido (el CRLF de Python no se cuela)" 'json_ok'
si "marca escrita"                               'marcado'
si "no deja restos en .calculo"                  '[ -z "$(ls -A "$CALC" 2>/dev/null)" ]'
ctx
si "el 2.º mensaje no repite el aviso"           '[ ! -s "$TMP/o" ]'

echo "── contexto: Python lento (9 s) ──"
reinicia; FALSO_PY_TARDA=9 ctx
si "el hook vuelve antes de 10 s ($MS ms)"       '[ "$MS" -lt 9500 ]'
si "sin salida en ese mensaje"                   '[ ! -s "$TMP/o" ]'
si "y SIN marca (si no, el aviso se perdería)"   '! marcado'
sleep 22
ctx
si "el mensaje siguiente trae el aviso con cifras" 'grep -q "Van 12.34" "$TMP/o"'
si "y ahora sí marca"                            'marcado'

echo "── contexto: cálculo muerto ──"
reinicia; mkdir -p "$CALC"; touch -d '-5 minutes' "$CALC/$SES.aviso.en-marcha"; ctx
si "sale el aviso sin cifras"                    'grep -q "no se pudo calcular" "$TMP/o"'
si "JSON válido"                                 'json_ok'
si "marca escrita"                               'marcado'

echo "── contexto: resultado viejo de otro contexto ──"
reinicia; mkdir -p "$CALC"; printf '99.99\nVIEJO\n' > "$CALC/$SES.aviso"; touch -d '-30 minutes' "$CALC/$SES.aviso"; ctx
si "no se sirven las cifras viejas"              '! grep -q "99.99" "$TMP/o"'
si "se recalcula"                                'grep -q "Van 12.34" "$TMP/o"'

echo "── contexto: sin sitio donde escribir el cálculo ──"
reinicia; : > "$CALC"    # un FICHERO donde iría la carpeta: mkdir -p falla
ctx
si "el aviso sale igual, sin cifras"             'grep -q "no se pudo calcular" "$TMP/o"'
si "y sin esperar ($MS ms)"                      '[ "$MS" -lt 5000 ]'
rm -f "$CALC"

echo "── contexto: bajo el umbral ──"
reinicia; sed -i 's/249000/9000/' "$HOME/.claude/projects/p/$SES.jsonl"; ctx
si "no dice nada"                                '[ ! -s "$TMP/o" ]'
si "ni lanza el cálculo"                         '[ ! -d "$CALC" ]'

echo "── arranque: caché de la sección 2c ──"
mkdir -p "$TMP/cwd"
CONF_P="$TMP/conf"; printf 'BITACORA_ETIQUETA=prueba\n' > "$CONF_P"
arr() { (cd "$TMP/cwd" && printf '{"source":"startup"}' | BITACORA_CONF="$CONF_P" bash "$ARR" 2>/dev/null) > "$TMP/a$1"; }
CACHE="$HOME/.claude/bitacora-cache-2c"
arr 1
si "primer arranque crea la caché"               '[ -s "$CACHE" ]'
arr 2
si "segundo arranque, salida idéntica"           'cmp -s "$TMP/a1" "$TMP/a2"'
# Prueba de que el segundo camino LEE la caché: se le mete una marca con la misma clave.
{ head -1 "$CACHE"; printf 'MARCA-DE-CACHE\n'; } > "$CACHE.n" && mv "$CACHE.n" "$CACHE"
arr 3
si "con la clave igual, se usa la caché"         'grep -q "MARCA-DE-CACHE" "$TMP/a3"'
sleep 1; printf 'BITACORA_MAX_LINEAS=5\n' >> "$CONF_P"
arr 4
si "al cambiar la conf se recalcula"             '! grep -q "MARCA-DE-CACHE" "$TMP/a4" && grep -q "BITACORA_MAX_LINEAS" "$TMP/a4"'
sleep 1; printf 'BITACORA_ETIQUETA=prueba\n' > "$CONF_P"
arr 5
si "y al quitarlo, el aviso desaparece"          '! grep -q "BITACORA_MAX_LINEAS" "$TMP/a5"'

echo
echo "casos: $N — pasan: $PASA — fallan: $FALLA"
[ "$FALLA" -eq 0 ]
