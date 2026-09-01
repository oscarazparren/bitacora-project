#!/bin/bash
# Bitácora — BORRADOR LOCAL de una sesión. Materia prima, no una entrada.
#
# Redacta mecánicamente —sin modelo, sin coste, sin red— lo que se puede saber de una
# sesión leyendo su transcript y el `git log` del repo. Es la pieza que faltaba del
# diseño del 1-sep-2026: `auditar-sesiones.sh` dice QUÉ sesión cerró sin anotar, y esto
# pone delante el material para reconstruirla.
#
# ============================================================================
# LO QUE ESTE FICHERO NO HACE, Y ES LA MITAD DEL DISEÑO
# ============================================================================
#
# NO ESCRIBE EN BITACORA.md. Nunca, ni una línea. Los hooks ejecutan comandos, no
# redactan (NOTAS-DE-CAMPO.md), y este repo es PÚBLICO: un borrador hecho del
# transcript lleva prompts literales, rutas, nombres de máquinas y qué corre dónde —
# el "mapa operativo" que la misma nota avisa que NO es una credencial y que por eso se
# cuela entero por el filtro de secretos de anotar.sh. Auto-commitear eso a un repo
# público sería el peor fallo disponible aquí, y encima automático.
#
# NO REDACTA LA ENTRADA. Ordena materia prima y la etiqueta como tal. Quien decide qué
# de todo esto es una DECISIÓN es el agente, leyendo esto, en la sesión siguiente.
#
# NO INVENTA `descartado`. Lo que se descartó no está en ningún sitio del que se pueda
# derivar: no hay commit de lo que no se hizo. El borrador deja el hueco señalado y
# vacío en vez de rellenarlo con algo verosímil, que es la forma exacta de los cuatro
# fallos silenciosos de este proyecto.
#
# ============================================================================
# POR QUÉ VIVE FUERA DEL REPO ($HOME/.claude/), Y NO DETRÁS DE UN .gitignore
# ============================================================================
#
# 1. "Nunca commiteado" tiene que ser ESTRUCTURAL, no una línea de .gitignore. Una
#    línea la borra un editor descuidado, la salta un `git add -f`, y no existe en una
#    copia recién clonada. Fuera del árbol de trabajo no hay nada que fallar. Es el
#    criterio del propio CLAUDE.md: si cumplir la regla exige acordarse -> mecanismo.
# 2. NO AÑADE EXPOSICIÓN NUEVA. El borrador es una vista derivada del transcript, que
#    ya está en $HOME/.claude/projects/ con el mismo contenido y las mismas
#    protecciones. Ponerlo en el repo sería meter el mapa operativo dentro de un árbol
#    de trabajo de git por primera vez. Aquí no se mueve de donde ya estaba.
# 3. Es donde vive el resto del estado de este sistema (bitacora-sesiones,
#    bitacora-visto, bitacora-leido, bitacora-rutas).
#
# ============================================================================
# POR QUÉ node Y NO awk
# ============================================================================
#
# El resto del proyecto evita dependencias a propósito. Aquí no se añade ninguna:
# `node` ya es requisito documentado (INSTALAR.md) y sessionstart-leer.sh no puede
# emitir su JSON sin él. A cambio se gana lo único que de verdad importa de este
# fichero: LOS PROMPTS LITERALES. Desescapar JSON a mano en awk (\", \\, \n, \uXXXX)
# corrompería en silencio justo el campo que no se puede reconstruir de ningún otro
# sitio. Y el coste no manda: esto corre solo cuando hay deuda, que casi nunca la hay.
#
# DOS PROCESOS node, NI UNO MÁS. La primera versión pedía a node cada campo y cada
# sección por separado: ocho arranques, 3,5 s. En Git Bash sobre Windows arrancar un
# proceso cuesta más que el trabajo que hace — la misma lección que bajó el auditor de
# 9,7 s a 3,8 s. Ahora: uno extrae, otro compone.
#
# Uso:
#   borrador-sesion.sh <transcript.jsonl> [ruta-repo] [--rehacer]
#
# Salida: la RUTA del borrador por stdout y NADA MÁS (el hook la usa tal cual).
# Los diagnósticos van por stderr. Código de salida siempre 0: es material de apoyo,
# no una comprobación que deba tumbar un arranque.
set -uo pipefail

CONF="${BITACORA_CONF:-$HOME/.claude/bitacora.conf}"
# shellcheck disable=SC1090
[ -f "$CONF" ] && . "$CONF"

FICHERO="${BITACORA_FICHERO:-BITACORA.md}"
REGISTRO="${BITACORA_REGISTRO_SESIONES:-$HOME/.claude/bitacora-sesiones}"
BORRADORES="${BITACORA_BORRADORES:-$HOME/.claude/bitacora-borradores}"

# Ventana hacia atrás desde el fin de la sesión donde se buscan sus commits. La MISMA
# que usa el auditor para decidir si anotó, y a propósito: si las dos ventanas no
# coincidieran, el borrador enseñaría commits que el auditor no contó (o al revés) y
# las dos piezas se contradirían delante del agente.
VENTANA_H="${BITACORA_AUDITORIA_VENTANA_HORAS:-6}"

# Techos. No son estética: un prompt puede ser un log pegado de 300 KB, y un borrador
# que no cabe en pantalla no lo lee nadie — que es la misma avería que el truncamiento
# ciego de lectura, en el otro extremo del tubo. Cuando se recorta, SE DICE dentro del
# propio fichero, con el número de lo que falta y la variable que lo sube.
export BORRADOR_MAX_PROMPTS="${BITACORA_BORRADOR_MAX_PROMPTS:-60}"
export BORRADOR_MAX_CHARS_PROMPT="${BITACORA_BORRADOR_MAX_CHARS_PROMPT:-4000}"
export BORRADOR_MAX_COMANDOS="${BITACORA_BORRADOR_MAX_COMANDOS:-80}"

LECTOR="$(dirname "$0")/borrador-leer-transcript.js"
[ -f "$LECTOR" ] || { echo "borrador-sesion: falta $LECTOR" >&2; exit 0; }

TRANSCRIPT="${1:-}"
REPO="${2:-$PWD}"
REHACER="${3:-}"

[ -n "$TRANSCRIPT" ] || { echo "borrador-sesion: falta el transcript." >&2; exit 0; }

# Las rutas que da Claude Code vienen en estilo Windows, y en el registro de cierre
# además con las barras escapadas ('C:\\Users\\...'). Git Bash no abre eso. Se
# normaliza aquí, y solo aquí.
TRANSCRIPT="${TRANSCRIPT//\\\\//}"
TRANSCRIPT="${TRANSCRIPT//\\//}"
case "$TRANSCRIPT" in
  [A-Za-z]:/*) TRANSCRIPT="/${TRANSCRIPT%%:*}${TRANSCRIPT#*:}" ;;
esac

[ -f "$TRANSCRIPT" ] || { echo "borrador-sesion: no existe $TRANSCRIPT" >&2; exit 0; }

if ! RAIZ=$(git -C "$REPO" rev-parse --show-toplevel 2>/dev/null); then
  echo "borrador-sesion: $REPO no está en una copia de trabajo de git." >&2; exit 0
fi
RAIZ=$(cd "$RAIZ" && pwd)   # 'C:/Users/...' -> '/c/Users/...', ver auditar-sesiones.sh

SID=${TRANSCRIPT##*/}; SID=${SID%.jsonl}
SID8=${SID:0:8}

mkdir -p "$BORRADORES" 2>/dev/null || { echo "borrador-sesion: no puedo crear $BORRADORES" >&2; exit 0; }

# ---------- Atajo: ¿ya existe el borrador de esta sesión? ----------
# El nombre definitivo lleva la FECHA de cierre, y esa la da node. Pero el id corto sale
# del nombre del transcript sin arrancar nada, así que un glob por id contesta antes de
# gastar un proceso. Importa: el hook de arranque llama a esto en CADA sesión, y sin el
# atajo cada arranque pagaría medio segundo por releer un transcript que no ha cambiado.
if [ "$REHACER" != "--rehacer" ]; then
  for previo in "$BORRADORES"/*-"$SID8".md; do
    [ -f "$previo" ] && { printf '%s\n' "$previo"; exit 0; }
  done
fi

DATOS=$(mktemp) || { echo "borrador-sesion: sin fichero temporal." >&2; exit 0; }
trap 'rm -f "$DATOS"' EXIT

# ---------- Proceso node nº1: recorrer el transcript ----------
# Devuelve una línea:  inicio<TAB>fin<TAB>turnos.  Inicio y fin salen del MÍNIMO y el
# MÁXIMO de las marcas de tiempo, no de head/tail: el transcript de una sesión
# reanudada no está en orden cronológico (ver la cabecera del lector).
RESUMEN=$(node "$LECTOR" --datos "$TRANSCRIPT" "$DATOS" 2>/dev/null) || RESUMEN=""
IFS=$'\t' read -r INI FIN TURNOS <<< "$RESUMEN"
TURNOS=${TURNOS:-0}

if [ -z "${FIN:-}" ]; then
  echo "borrador-sesion: $SID no tiene ni una marca de tiempo legible; no hay sesión que describir." >&2
  exit 0
fi

FIN_EPOCH=$(date -d "$FIN" +%s 2>/dev/null) || FIN_EPOCH=""
[ -n "$FIN_EPOCH" ] || { echo "borrador-sesion: no supe convertir las fechas de $SID." >&2; exit 0; }
INI_EPOCH=$(date -d "${INI:-$FIN}" +%s 2>/dev/null) || INI_EPOCH="$FIN_EPOCH"

DIA=$(date -d "@$FIN_EPOCH" +%Y-%m-%d 2>/dev/null)
NOMBRE_REPO=${RAIZ##*/}
DESTINO="$BORRADORES/$DIA-$NOMBRE_REPO-$SID8.md"

# IDEMPOTENTE. Esto se llama desde un hook con presupuesto: rehacer un borrador que ya
# existe es gastarle el tiempo a otra sección. Y el transcript de una sesión CERRADA no
# cambia, así que rehacerlo tampoco daría nada nuevo. La excepción es --rehacer, para
# la sesión VIVA (el caso `compact`), cuyo transcript sí sigue creciendo.
if [ -f "$DESTINO" ] && [ "$REHACER" != "--rehacer" ]; then
  printf '%s\n' "$DESTINO"; exit 0
fi

# ---------- El artefacto: qué commits hay en la ventana ----------
DESDE_EPOCH=$(( FIN_EPOCH - VENTANA_H * 3600 ))
[ "$INI_EPOCH" -gt "$DESDE_EPOCH" ] && DESDE_EPOCH=$INI_EPOCH
DESDE=$(date -u -d "@$DESDE_EPOCH" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)
HASTA=$(date -u -d "@$(( FIN_EPOCH + 900 ))" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)

B_COMMITS="(ningún commit en la ventana)"
B_ANOTO="(no se pudo comprobar: no supe construir la ventana de fechas)"
if [ -n "$DESDE" ] && [ -n "$HASTA" ]; then
  LOG=$(git -C "$RAIZ" log --since="$DESDE" --until="$HASTA" \
          --date=format:'%Y-%m-%d %H:%M' --format='%h %ad %an — %s' --name-only 2>/dev/null)
  [ -n "$LOG" ] && B_COMMITS="$LOG"
  N=$(git -C "$RAIZ" log --since="$DESDE" --until="$HASTA" --format=%h -- "$FICHERO" 2>/dev/null | wc -l)
  N=$(printf '%s' "$N" | tr -dc '0-9'); N=${N:-0}
  if [ "$N" -gt 0 ]; then
    B_ANOTO="SÍ — $N commit(s) tocan \`$FICHERO\` en la ventana."
  else
    B_ANOTO="NO — ningún commit toca \`$FICHERO\` en la ventana. Esto es la deuda."
  fi
fi

# ---------- Motivo del cierre: ENRIQUECE, no decide ----------
# Lección nº4, literal: quien reporta el éxito no puede ser quien hizo el trabajo. Esta
# línea la escribió sessionend-anotar.sh y por tanto NO es evidencia de nada; solo
# aporta el motivo del cierre, que no está en ningún otro sitio. Su AUSENCIA sí dice
# algo, y bastante: la sesión no cerró limpio (la X, un kill, la luz).
B_CIERRE="sin registro de cierre — la sesión no cerró limpio (la X, un kill, un corte de luz)"
if [ -f "$REGISTRO" ] && LINEA=$(grep -m1 "	$SID	" "$REGISTRO" 2>/dev/null); then
  B_CIERRE="$(printf '%s' "$LINEA" | cut -f4) (registrado a las $(printf '%s' "$LINEA" | cut -f2))"
fi

B_AHORA=$(date '+%Y-%m-%d %H:%M:%S')
EDAD_MIN=$(( ( $(date +%s) - FIN_EPOCH ) / 60 ))
B_SUCIO=$(git -C "$RAIZ" status --porcelain 2>/dev/null | head -40)
[ -n "$B_SUCIO" ] || B_SUCIO="(limpio)"

# El diseño pedía "lo que queda sucio AL CERRAR", y eso NO se puede tener: el borrador
# se escribe después, y `git status` solo sabe de ahora. Así que se dice cuál de los dos
# es, en vez de dejar que se lea como el otro. Colar el estado de hoy como "lo que dejó
# a medias" hace tres días es exactamente el fallo que este proyecto persigue: un dato
# correcto presentado como si respondiera a otra pregunta.
if [ "$EDAD_MIN" -le 15 ]; then
  B_NOTA_SUCIO="La sesión acabó hace $EDAD_MIN min, así que esto se parece mucho a cómo la dejó."
else
  B_NOTA_SUCIO="**ATENCIÓN: la sesión acabó hace $EDAD_MIN min.** Esto es el estado de AHORA, no el del cierre. Entremedias ha podido pasar cualquier cosa: no lo leas como «lo que dejó a medias»."
fi

# ---------- Proceso node nº2: componer ----------
# Se escribe a un temporal y se mueve al final: un borrador a medias es peor que
# ninguno, porque parece completo. Un `mv` en el mismo directorio es atómico.
#
# MSYS2_ENV_CONV_EXCL='*' NO ES ADORNO. Git Bash traduce las variables de entorno que
# parecen rutas POSIX antes de entregárselas a un binario de Windows, y `node.exe` lo
# es: sin esto, `B_RAIZ=/c/Users/...` le llega a node como `C:/Users/...`. Salía en el
# borrador una ruta que el script nunca escribió — una transformación silenciosa de un
# dato, que es la avería que este proyecto persigue, en pequeño. Comprobado el 1-sep:
# con la variable puesta llega literal, y los valores multilínea (commits, git status)
# no se tocaban ni antes ni después.
TMP="$DESTINO.tmp.$$"
if MSYS2_ENV_CONV_EXCL='*' \
   B_SID="$SID" B_SID8="$SID8" B_RAIZ="$RAIZ" B_REPO_NOMBRE="$NOMBRE_REPO" \
   B_CIERRE="$B_CIERRE" B_ANOTO="$B_ANOTO" B_AHORA="$B_AHORA" \
   B_COMMITS="$B_COMMITS" B_SUCIO="$B_SUCIO" B_NOTA_SUCIO="$B_NOTA_SUCIO" \
   B_VENTANA_H="$VENTANA_H" \
   node "$LECTOR" --cuerpo "$DATOS" > "$TMP" 2>/dev/null && [ -s "$TMP" ]; then
  if mv "$TMP" "$DESTINO" 2>/dev/null; then
    printf '%s\n' "$DESTINO"
    exit 0
  fi
fi

rm -f "$TMP" 2>/dev/null
echo "borrador-sesion: no pude escribir $DESTINO" >&2
exit 0
