#!/bin/bash
# Bitácora — pone al día los webhooks de GitHub que alimentan el índice del arranque.
#
# POR QUÉ EXISTE. Un webhook es POR REPO. Al montar esto (29-ago-2026) había que lanzar
# un comando por cada uno, y cada repo nuevo que se diera de alta después quedaba mudo
# hasta que alguien se acordara de repetirlo. Eso es exactamente el modo de fallo que
# este proyecto lleva un mes persiguiendo: algo deja de funcionar y NADIE se entera,
# porque depende de que una persona recuerde un paso.
#
# Este script quita el "acordarse": lo ejecutas y deja todos los repos al día. Es
# idempotente — el que ya tiene webhook no se toca, así que se puede lanzar las veces
# que haga falta sin duplicar nada.
#
# NO ES EL ARREGLO DEFINITIVO, y conviene decirlo aquí para que no se venda como tal:
# sigue habiendo que EJECUTARLO. El arreglo de verdad es una GitHub App instalada en la
# cuenta con acceso a "All repositories": esa cubre los repos futuros sola, sin que nadie
# lance nada. Requiere unos clics en la web de GitHub que no se pueden hacer por API.
# Mientras eso no exista, esto es un paso manual menos frágil que diez.
#
# USO:
#   bash scripts/sincronizar-webhooks.sh            # los repos del índice (repos.txt)
#   bash scripts/sincronizar-webhooks.sh --todos    # TODOS los repos de la cuenta
#   bash scripts/sincronizar-webhooks.sh --revisar  # solo informa, no crea nada
#
# Necesita `gh` autenticado EN ESTA MÁQUINA (no dentro del servidor: allí no hay gh) y
# acceso ssh al servidor para leer el secreto de firma. El secreto nunca se imprime.

set -uo pipefail

SERVIDOR="${BITACORA_FLOTA_SSH:-lizar}"
INDICE="${BITACORA_INDICE_REPOS:-/opt/bitacora/repos.txt}"
SECRETO_REMOTO="${BITACORA_WEBHOOK_SECRETO:-/opt/bitacora/config/webhook.secret}"
URL="${BITACORA_WEBHOOK_URL:-https://n8n.lizaraia.com/gh-bitacora/}"
CUENTA="${BITACORA_CUENTA_GITHUB:-oscarazparren}"

MODO="indice"
REVISAR=no
for arg in "$@"; do
  case "$arg" in
    --todos)   MODO="todos" ;;
    --revisar) REVISAR=si ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
    *) echo "opción desconocida: $arg (usa --todos, --revisar o --help)" >&2; exit 2 ;;
  esac
done

command -v gh >/dev/null 2>&1 || {
  echo "ERROR: no encuentro 'gh' aquí." >&2
  echo "       Si el prompt pone root@... estás DENTRO del servidor, donde no hay gh." >&2
  echo "       Sal con 'exit' y vuelve a lanzarlo desde tu PC." >&2
  exit 1
}
gh auth status >/dev/null 2>&1 || { echo "ERROR: gh no está autenticado (gh auth login)." >&2; exit 1; }

# El secreto se lee en una variable y no se imprime nunca. Si el servidor no contesta se
# aborta: crear un webhook con secreto vacío daría avisos que el receptor rechazaría, y
# el fallo aparecería mucho después y lejos de aquí.
SECRETO=$(ssh -o ConnectTimeout=8 -o BatchMode=yes "$SERVIDOR" "cat '$SECRETO_REMOTO'" 2>/dev/null)
[ -n "$SECRETO" ] || { echo "ERROR: no pude leer el secreto de firma en $SERVIDOR." >&2; exit 1; }

if [ "$MODO" = "todos" ]; then
  REPOS=$(gh repo list "$CUENTA" --limit 500 --json name --jq '.[].name' 2>/dev/null)
else
  REPOS=$(ssh -o ConnectTimeout=8 -o BatchMode=yes "$SERVIDOR" \
    "grep -vE '^[[:space:]]*#|^[[:space:]]*\$' '$INDICE' | awk '{print \$1}'" 2>/dev/null)
fi
[ -n "$REPOS" ] || { echo "ERROR: no obtuve ninguna lista de repos." >&2; exit 1; }

echo "URL destino: $URL"
echo "modo: $MODO$([ "$REVISAR" = si ] && echo ' (solo revisar)')"
echo

CREADOS=0; YA=0; FALLOS=0
for R in $REPOS; do
  EXISTE=$(gh api "repos/$CUENTA/$R/hooks" --jq '[.[] | select(.config.url != null and (.config.url | contains("gh-bitacora")))] | length' 2>/dev/null)
  if [ -z "$EXISTE" ]; then
    echo "  $R: NO PUDE CONSULTARLO (sin permiso o no existe)"
    FALLOS=$((FALLOS+1)); continue
  fi
  if [ "$EXISTE" -gt 0 ]; then
    echo "  $R: ya avisa"
    YA=$((YA+1)); continue
  fi
  if [ "$REVISAR" = si ]; then
    echo "  $R: LE FALTA (no se crea, modo revisar)"
    CREADOS=$((CREADOS+1)); continue
  fi
  CUERPO=$(SEC="$SECRETO" U="$URL" python -c "import json,os;print(json.dumps({'name':'web','active':True,'events':['push'],'config':{'url':os.environ['U'],'content_type':'json','secret':os.environ['SEC'],'insecure_ssl':'0'}}))" 2>/dev/null)
  [ -n "$CUERPO" ] || { echo "  $R: no pude construir la petición (¿falta python?)"; FALLOS=$((FALLOS+1)); continue; }
  if printf '%s' "$CUERPO" | gh api -X POST "repos/$CUENTA/$R/hooks" --input - >/dev/null 2>/tmp/bitacora-hook-err; then
    echo "  $R: CREADO"
    CREADOS=$((CREADOS+1))
  else
    echo "  $R: FALLÓ -> $(head -c 160 /tmp/bitacora-hook-err | tr '\n' ' ')"
    FALLOS=$((FALLOS+1))
  fi
done
rm -f /tmp/bitacora-hook-err

echo
echo "creados: $CREADOS | ya estaban: $YA | fallos: $FALLOS"
# Los fallos salen por código de retorno, no solo por pantalla: si algún día esto corre
# desatendido, un repo que se quedó mudo tiene que poder detectarse sin leer el texto.
[ "$FALLOS" -gt 0 ] && exit 1
exit 0
