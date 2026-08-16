#!/bin/bash
# Bitácora — añade una entrada a la bitácora de flota.
#
# Vive en el servidor de flota, junto al fichero de registro. Se invoca por SSH
# desde cualquier dispositivo:
#
#   printf -- "- lo que hice\n" | ssh <servidor> "bash /ruta/anotar.sh '[dispositivo] titular'"
#
# La entrada nueva se inserta arriba del todo (lo más reciente primero).
#
# Para la bitácora de un repo NO se usa esto: allí se añade un fichero a
# .bitacora/ y se hace commit, que es lo que la lleva a los demás dispositivos.

set -euo pipefail

F="${BITACORA_FLOTA_RUTA:-$(dirname "$0")/BITACORA.md}"
TITULAR="${1:-}"

if [ -z "$TITULAR" ]; then
  echo "ERROR: falta el titular. Uso: anotar.sh '[dispositivo] titular'" >&2
  exit 1
fi

if [ ! -f "$F" ]; then
  echo "ERROR: no existe el fichero de bitácora: $F" >&2
  exit 1
fi

CUERPO=$(mktemp)
TMP=$(mktemp)
trap 'rm -f "$CUERPO" "$TMP"' EXIT
cat > "$CUERPO"

if [ ! -s "$CUERPO" ]; then
  echo "ERROR: no llegó cuerpo por stdin. Pásalo con un pipe." >&2
  exit 1
fi

# Rechazo de secretos ANTES de escribir, no en el commit: para cuando el
# pre-commit mira, el fichero ya está en disco y la siguiente sesión ya lo lee.
if grep -Eqi '(api[_-]?key|secret|password|passwd|token|authorization|bearer|private[_-]?key)[[:space:]]*[:=]|-----BEGIN [A-Z ]*PRIVATE KEY-----|gh[pousr]_[A-Za-z0-9]{20,}|sk-[A-Za-z0-9]{20,}|xox[baprs]-[A-Za-z0-9-]{10,}' "$CUERPO"; then
  echo "BLOQUEADO: la entrada parece contener una credencial. Reescríbela sin el secreto." >&2
  echo "Una bitácora es un fichero compartido y versionado: lo que entra, se queda." >&2
  exit 2
fi

# Insertar justo después del primer '---' (separador de la cabecera).
LINEA=$(grep -n '^---$' "$F" | head -1 | cut -d: -f1)
if [ -z "$LINEA" ]; then
  echo "ERROR: no encuentro el separador '---' en $F" >&2
  exit 1
fi

{
  head -n "$LINEA" "$F"
  echo
  echo "## $(date +%Y-%m-%d) — $TITULAR"
  echo
  cat "$CUERPO"
  tail -n +$((LINEA + 1)) "$F"
} > "$TMP"

cp "$F" "$F.bak"          # respaldo antes de pisar
mv "$TMP" "$F"
chmod 644 "$F"

echo "Anotado en la bitácora: ## $(date +%Y-%m-%d) — $TITULAR"
