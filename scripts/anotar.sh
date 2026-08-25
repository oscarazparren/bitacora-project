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
# Si el fichero vive en una copia de trabajo de git, la entrada se commitea y se
# sube al remoto en la misma llamada. Sin eso el registro se queda en una máquina
# y no llega a las demás — que es exactamente el fallo que este proyecto existe
# para eliminar («commit automático obligatorio», regla de oro 4). Configurable:
#
#   BITACORA_FLOTA_RUTA   ruta del BITACORA.md      (por defecto: junto a este script)
#   BITACORA_FLOTA_REPO   raíz de la copia de trabajo (por defecto: la carpeta del fichero)
#   BITACORA_SIN_GIT=si   no tocar git aunque lo haya (queda dicho en la salida)
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

# ---------- ¿Se puede sincronizar con el remoto? Se decide ANTES de escribir ----------
# El estado de git se comprueba de verdad en vez de darlo por supuesto: en uso real
# hay rebase a medias, HEAD desacoplado y ramas sin remoto. Si no se puede commitear,
# la entrada se escribe igual —no se pierde— pero la salida lo dice. Nunca se reporta
# "anotado" a secas sobre algo que no ha salido de este disco.
REPO="${BITACORA_FLOTA_REPO:-$(cd "$(dirname "$F")" && pwd)}"
GIT_LISTO=no
GIT_MOTIVO=""
RAMA=""

if [ "${BITACORA_SIN_GIT:-no}" = "si" ]; then
  GIT_MOTIVO="sincronización desactivada con BITACORA_SIN_GIT=si"
elif ! git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1; then
  GIT_MOTIVO="$REPO no es una copia de trabajo de git"
else
  GITDIR=$(git -C "$REPO" rev-parse --absolute-git-dir 2>/dev/null || echo "")
  if [ -d "$GITDIR/rebase-merge" ] || [ -d "$GITDIR/rebase-apply" ]; then
    GIT_MOTIVO="hay un rebase a medias en $REPO"
  elif [ -f "$GITDIR/MERGE_HEAD" ]; then
    GIT_MOTIVO="hay un merge a medias en $REPO"
  elif [ -f "$GITDIR/CHERRY_PICK_HEAD" ]; then
    GIT_MOTIVO="hay un cherry-pick a medias en $REPO"
  elif ! RAMA=$(git -C "$REPO" symbolic-ref --short -q HEAD); then
    GIT_MOTIVO="HEAD está desacoplado en $REPO"
  else
    GIT_LISTO=si
  fi
fi

# Serializa escrituras concurrentes: dos sesiones SSH anotando a la vez leen
# el mismo fichero y la segunda en escribir pisa la entrada de la primera.
# El lock se libera solo al salir del script (se cierra el descriptor 9).
#
# Git Bash en Windows no trae 'flock'. Sin esta salvaguarda el script moría ahí
# mismo con código 127 y sin escribir nada — inservible en la máquina que, tras la
# migración prevista, tendría que anotar en local. Se degrada a no bloquear, pero
# se DICE: perder la serialización en silencio es justo el modo de fallo que este
# proyecto persigue.
if command -v flock >/dev/null 2>&1; then
  exec 9>"$F.lock"
  flock -x 9
else
  echo "AVISO: no hay 'flock' en este sistema; se anota SIN bloqueo." >&2
  echo "Si dos procesos anotan a la vez, uno puede pisar la entrada del otro." >&2
fi

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
# Se ignora lo que va entre comillas invertidas: una entrada que HABLA de las marcas
# (esta misma comprobacion, sin ir mas lejos) descuadraba la cuenta y se auto-bloqueaba.
# Falso positivo encontrado usandolo, el mismo dia que se escribio.
MARCAS=$( { sed 's/`[^`]*`//g' "$CUERPO" | grep -o '\*\*' || true; } | wc -l )
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

# Traer antes lo que haya subido otro dispositivo, para no divergir. Va aquí, con el
# lock ya tomado y las validaciones pasadas: si la entrada iba a ser rechazada, no
# tiene sentido haber tocado el repositorio.
if [ "$GIT_LISTO" = "si" ]; then
  git -C "$REPO" pull --quiet --rebase --autostash 2>/dev/null || \
    echo "AVISO: no se pudo actualizar desde el remoto. Se anota igualmente en local." >&2
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

# ---------- Commit y subida ----------
# Sin esto la entrada se queda en una máquina: escribir en disco no es anotar, y
# decir "anotado" sin más sobre algo que no ha viajado es la misma clase de fallo
# que reportar éxito sobre una entrada truncada. Cada salida de aquí abajo dice
# exactamente hasta dónde llegó la entrada.
if [ "$GIT_LISTO" != "si" ]; then
  {
    echo ""
    echo "AVISO: la entrada está SOLO EN ESTE DISCO ($GIT_MOTIVO)."
    echo "No llegará a las demás máquinas hasta que se commitee y se suba."
  } >&2
  exit 0
fi

# Se cuentan solo las cabeceras FECHADAS. Contar '^## ' a secas incluye las notas
# permanentes de la cabecera del fichero, y esa misma confusión ya dejó una bitácora
# entera leyéndose como vacía sin avisar (NOTAS-DE-CAMPO.md, 22-ago-2026).
N=$(grep -cE '^## [0-9]{4}-[0-9]{2}-[0-9]{2}' "$F" || true)

# Solo el fichero de bitácora, nunca 'git add -A': el commit del registro no debe
# arrastrar cambios de código sueltos en la copia de trabajo.
git -C "$REPO" add -- "$F" 2>/dev/null || true

if git -C "$REPO" diff --cached --quiet 2>/dev/null; then
  {
    echo ""
    echo "AVISO: la entrada se escribió pero NO HAY NADA QUE COMMITEAR."
    echo "Lo más probable es que $F esté en .gitignore. No viajará a las demás máquinas."
  } >&2
  exit 0
fi

if ! git -C "$REPO" commit --quiet -m "$TITULAR

$N entradas." 2>/dev/null; then
  {
    echo ""
    echo "AVISO: la entrada se escribió pero el COMMIT FALLÓ."
    echo "Comprueba user.name/user.email y los hooks de pre-commit de $REPO."
  } >&2
  exit 0
fi

# El push puede fallar (red, remoto caído). La entrada ya está escrita y commiteada,
# así que NO se sale con error: hacerlo haría que quien llamó creyera que la anotación
# falló y la repitiera, duplicándola. Un reintento con rebase por si otro dispositivo
# subió mientras tanto; si vuelve a fallar, se dice exactamente qué pasó.
if git -C "$REPO" push --quiet origin "$RAMA" 2>/dev/null; then
  echo "Subido al remoto ($RAMA). $N entradas en total."
elif git -C "$REPO" pull --quiet --rebase 2>/dev/null && \
     git -C "$REPO" push --quiet origin "$RAMA" 2>/dev/null; then
  echo "Subido al remoto ($RAMA) tras rebase. $N entradas en total."
else
  {
    echo ""
    echo "AVISO: la entrada se guardó y se commiteó, pero el PUSH FALLÓ."
    echo "Está solo en esta copia. Se reintentará en la próxima anotación, o fuérzalo con:"
    echo "  git -C $REPO push origin $RAMA"
  } >&2
fi
