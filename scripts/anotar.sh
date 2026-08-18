#!/bin/bash
# Bitácora — añade una entrada a la bitácora de flota.
#
# Vive en el servidor de flota, junto al fichero de registro. Se invoca por SSH
# desde cualquier dispositivo:
#
#   ssh <servidor> "bash /ruta/anotar.sh '[dispositivo] titular'" <<'EOF'
#   - lo que hice
#   EOF
#
# El cuerpo va por heredoc ENTRECOMILLADO (<<'EOF'), que no interpreta nada. No uses
# printf: si el texto lleva un '%', printf lo toma por formato y corta la entrada ahi.
#
# La entrada nueva se inserta arriba del todo (lo más reciente primero).
#
# Para la bitácora de un repo NO se usa esto: allí se añade la entrada al
# BITACORA.md de ese repo y se hace commit, que es lo que la lleva a los demás
# dispositivos. (Fase 1 mueve esto a un fichero por entrada en .bitacora/,
# ver NOTAS-DE-CAMPO.md — no implementado todavía.)

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

# Serializa escrituras concurrentes: dos sesiones SSH anotando a la vez leen
# el mismo fichero y la segunda en escribir pisa la entrada de la primera.
# El lock se libera solo al salir del script (se cierra el descriptor 9).
exec 9>"$F.lock"
flock -x 9

CUERPO=$(mktemp)
TMP=$(mktemp)
trap 'rm -f "$CUERPO" "$TMP"' EXIT
cat > "$CUERPO"

if [ ! -s "$CUERPO" ]; then
  echo "ERROR: no llegó cuerpo por stdin. Pásalo con un pipe." >&2
  exit 1
fi

# Rechazo de entradas MUTILADAS, ANTES de escribir. Esto no es teorico: la ayuda de
# este script decia de invocarlo con printf, alguien anoto un hallazgo que contenia un
# '%', printf corto la cadena ahi mismo, y el script respondio "Anotado en la bitacora"
# y "Subido". Exito reportado sobre un dato mutilado. Un registro que se come medio
# hallazgo y da el OK es peor que no tener registro: te deja confiado.
# Dos senales, las dos presentes en aquel incidente:
#   - el cuerpo no acaba en salto de linea (printf aborto a mitad de cadena)
#   - numero impar de '**' (una negrita abierta y sin cerrar)
MOTIVO=""
if [ -n "$(tail -c 1 "$CUERPO")" ]; then
  MOTIVO="no termina en salto de linea"
fi
MARCAS=$( { grep -o '\*\*' "$CUERPO" || true; } | wc -l )
if [ $((MARCAS % 2)) -ne 0 ]; then
  MOTIVO="${MOTIVO:+$MOTIVO; }$MARCAS marcas '**', impar: una negrita sin cerrar"
fi
if [ -n "$MOTIVO" ] && [ "${PERMITIR_ENTRADA_RARA:-no}" != "si" ]; then
  echo "BLOQUEADO: la entrada parece TRUNCADA ($MOTIVO). No se ha escrito nada." >&2
  echo "Causa habitual: se paso por 'printf' y el texto lleva un '%'." >&2
  echo "Pasala con heredoc entrecomillado, que no interpreta nada:" >&2
  echo "  ssh <servidor> \"bash /ruta/anotar.sh '<titular>'\" <<'EOF'" >&2
  echo "  - lo que hice" >&2
  echo "  EOF" >&2
  echo "Si la entrada es asi de verdad, repite con PERMITIR_ENTRADA_RARA=si." >&2
  exit 3
fi

# Rechazo de secretos ANTES de escribir, no en el commit: para cuando el
# pre-commit mira, el fichero ya está en disco y la siguiente sesión ya lo lee.
if grep -Eqi '(api[_-]?key|secret|password|passwd|token|authorization|bearer|private[_-]?key)[[:space:]]*[:=]|-----BEGIN [A-Z ]*PRIVATE KEY-----|gh[pousr]_[A-Za-z0-9]{20,}|sk-[A-Za-z0-9]{20,}|xox[baprs]-[A-Za-z0-9-]{10,}|AKIA[0-9A-Z]{16}|eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}|[a-zA-Z][a-zA-Z0-9+.-]*://[^[:space:]/@]+:[^[:space:]/@]+@' "$CUERPO"; then
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
echo "Guardadas $(wc -l < "$CUERPO") lineas, $(wc -c < "$CUERPO") caracteres. Comprueba si esperabas mas."
