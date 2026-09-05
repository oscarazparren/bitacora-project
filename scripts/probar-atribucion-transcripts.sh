#!/bin/bash
# Bitácora — BANCO DE PRUEBAS de la atribución de transcripts en
# scripts/auditar-sesiones.sh (qué carpetas de ~/.claude/projects son de este repo).
#
# ============================================================================
# POR QUÉ EXISTE ESTE FICHERO
# ============================================================================
#
# El auditor buscaba las carpetas por PREFIJO -- '<patron>' y '<patron>-*' --. Cuando
# el nombre de un repo es prefijo del de otro, se llevaba las sesiones ajenas, las
# juzgaba contra la BITACORA.md equivocada y cantaba deuda falsa. Medido el 4-sep en
# la primera ejecución de sueno.sh: proponía reconstruir 7 sesiones "de bitacora" que
# eran de 'bitacora-flota' y 'bitacora-project'.
#
# El comodín no se puede quitar a secas: los WORKTREES de Claude
# ('<repo>--claude-worktrees-*') son el MISMO repo y la MISMA bitácora, así que sus
# sesiones sí son de aquí. Medido el 5-sep en el PC viejo: 4 carpetas de worktree
# (agentes-lizar x2, kangurea-web, lizar-informes) y CERO carpetas que sean subcarpeta
# real de un repo, pese a lo que decía el comentario del propio script.
#
# El auditor corre en CADA arranque de sesión en las dos máquinas: una regresión aquí
# las rompe las dos. Es la lección del 3-sep, la que hizo que se commiteara el banco
# de la sección 1d. Por eso este fichero se commitea con el arreglo, no después.
#
# ============================================================================
# CÓMO PRUEBA SIN DUPLICAR EL CÓDIGO
# ============================================================================
#
# Extrae EN VIVO el bloque "Localizar los transcripts de este repo" del auditor real
# y lo ejecuta con $RAIZ y $PROYECTOS apuntando a un fixture de carpetas vacías. Si
# alguien edita ese bloque, el banco prueba la versión nueva sin tocar este fichero.
#
# El fixture NO fabrica nombres de carpeta a mano: los deriva de la ruta temporal con
# la misma transformación que usa Claude Code, porque lo que se prueba es la DECISIÓN
# (qué carpetas se aceptan), no cómo se escribe un nombre.
#
# Se ejecuta a mano:  bash scripts/probar-atribucion-transcripts.sh
# Cero red, cero git, cero ficheros del usuario. Solo mkdir y bash.

set -uo pipefail

AQUI="$(cd "$(dirname "$0")" && pwd)"
AUDITOR="${1:-$AQUI/auditar-sesiones.sh}"
[ -f "$AUDITOR" ] || { echo "no encuentro el auditor: $AUDITOR" >&2; exit 2; }

# --- Extraer el bloque del auditor real -------------------------------------
BLOQUE=$(awk '
  /^# ---------- Localizar los transcripts de este repo ----------/ { f=1 }
  f && /^ahora=\$\(date \+%s\)/ { exit }
  f { print }
' "$AUDITOR")
[ -n "$BLOQUE" ] || { echo "no encuentro el bloque de localización en $AUDITOR" >&2; exit 2; }
case "$BLOQUE" in
  *'patron='*) : ;;
  *) echo "el bloque extraído no tiene la pinta esperada (falta 'patron=')" >&2; exit 2 ;;
esac

TMP=$(mktemp -d 2>/dev/null) || { echo "mktemp -d falló" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT
printf '%s\n' "$BLOQUE" > "$TMP/bloque.sh"

# El runner ejecuta el bloque y normaliza su resultado. Acepta que 'dirs' sea cadena
# (versión vieja) o array (versión nueva) A PROPÓSITO: así el mismo banco corre contra
# las dos y se puede VER fallar antes del arreglo, que es lo único que demuestra que
# el banco prueba algo.
cat > "$TMP/runner.sh" <<'RUNNER'
set -uo pipefail
# shellcheck disable=SC1090
. "$BLOQUE_FILE"
printf '###DIRS###\n'
if declare -p dirs 2>/dev/null | grep -q 'declare -a'; then
  [ "${#dirs[@]}" -gt 0 ] && for d in "${dirs[@]}"; do printf '%s\n' "${d##*/}"; done
else
  # shellcheck disable=SC2086
  for d in $dirs; do printf '%s\n' "${d##*/}"; done
fi
RUNNER

# La transformación que hace Claude Code al nombrar la carpeta de proyecto. NO se copia
# del auditor: se dedujo el 5-sep-2026 de pares (carpeta observada, cwd real) leídos de
# los propios transcripts, que llevan el 'cwd' dentro y son la verdad de campo:
#
#   C:\Users\Oscar\LIZAR AEO                        -> C--Users-Oscar-LIZAR-AEO
#   C:\Users\Oscar\repos\CSV Generator              -> C--Users-Oscar-repos-CSV-Generator
#   C:\Users\Oscar\repos\z-api Whatsapp             -> C--Users-Oscar-repos-z-api-Whatsapp
#   C:\Users\Oscar\Desktop\Kangurea MATERIAL WEB    -> c--Users-...-Kangurea-MATERIAL-WEB
#   ...\agentes-lizar\.claude\worktrees\clever-...  -> ...-agentes-lizar--claude-worktrees-clever-...
#
# El último par es el que explica el doble guion de los worktrees: no es un nombre
# especial, es '\' + '.'. Espacio y punto van a '-' igual que ':', '/' y '\'.
# NO hay evidencia observada para '_', '(' ni '[', así que no se tocan.
#
# Se usa SOLO para construir el fixture, nunca para decidir.
patron_de() {  # patron_de <dir> -> nombre de carpeta de proyecto
  local rw; rw=$(cd "$1" && pwd -W 2>/dev/null || printf '%s' "$1")
  printf '%s' "$rw" | sed 's#[:/\\ .]#-#g'
}

PROY="$TMP/proyectos"
REPOS="$TMP/repos"
mkdir -p "$PROY" "$REPOS"

repo() {   # repo <nombre> -> crea el repo de mentira y devuelve su ruta
  mkdir -p "$REPOS/$1"; printf '%s' "$REPOS/$1"
}
carpeta() {  # carpeta <ruta-repo> [sufijo] -> crea la carpeta de proyecto
  mkdir -p "$PROY/$(patron_de "$1")${2:-}"
}

correr() {   # correr <ruta-repo> -> salida cruda del bloque
  RAIZ="$1" PROYECTOS="$PROY" BLOQUE_FILE="$TMP/bloque.sh" bash "$TMP/runner.sh" 2>/dev/null
}

PASA=0; FALLA=0
resumen_de() { printf '%s' "$1" | tr '\n' '|' | cut -c1-260; }

# Las carpetas aceptadas, una por línea y ordenadas. Sin marcador = el bloque salió
# antes de llegar a él (su rama "no encuentro transcripts"), o sea CERO carpetas: hay
# que distinguirlo, porque '${x#*marca}' sobre una cadena sin la marca la devuelve
# entera y eso leería la queja del bloque como si fuera una lista de carpetas.
aceptadas() {
  case "$1" in
    *'###DIRS###'*) printf '%s\n' "${1#*###DIRS###}" | sed '/^$/d' | sort ;;
    *) : ;;
  esac
}

# Lo que el bloque dijo por su cuenta, antes del marcador.
dicho_de() { printf '%s' "${1%%###DIRS###*}"; }

espera_dirs() {  # <nombre> <salida> <sufijos-esperados> <ruta-repo>   ('=' = la exacta)
  local nombre="$1" salida="$2" esperados="$3" raiz="$4" base obtenido queria s
  base=$(patron_de "$raiz")
  queria=$(for s in $esperados; do
             if [ "$s" = "=" ]; then printf '%s\n' "$base"; else printf '%s\n' "$base$s"; fi
           done | sed '/^$/d' | sort)
  obtenido=$(aceptadas "$salida")
  if [ "$queria" = "$obtenido" ]; then
    printf '  ok    %s\n' "$nombre"; PASA=$((PASA + 1))
  else
    printf '  FALLA %s\n        esperaba: %s\n        obtuvo:   %s\n' \
      "$nombre" "$(resumen_de "$queria")" "$(resumen_de "$obtenido")"
    FALLA=$((FALLA + 1))
  fi
}

espera_ninguna() {  # <nombre> <salida>
  espera_dirs "$1" "$2" "" "$REPOS"
}

espera() {  # <nombre> <trozo> <salida>
  if printf '%s' "$3" | grep -qF -- "$2"; then
    printf '  ok    %s\n' "$1"; PASA=$((PASA + 1))
  else
    printf '  FALLA %s\n        esperaba contener: %s\n        salida: %s\n' "$1" "$2" "$(resumen_de "$3")"
    FALLA=$((FALLA + 1))
  fi
}

espera_no() {  # <nombre> <trozo-prohibido> <salida>
  if printf '%s' "$3" | grep -qF -- "$2"; then
    printf '  FALLA %s\n        NO debía contener: %s\n        salida: %s\n' "$1" "$2" "$(resumen_de "$3")"
    FALLA=$((FALLA + 1))
  else
    printf '  ok    %s\n' "$1"; PASA=$((PASA + 1))
  fi
}

echo "Banco de pruebas — atribución de transcripts"
echo "auditor: $AUDITOR"
echo

# =========================================================================
# EL FALLO MEDIDO: 'bitacora' se llevaba 'bitacora-flota' y 'bitacora-project'
# =========================================================================
R_BIT=$(repo bitacora); R_FLO=$(repo bitacora-flota); R_PRO=$(repo bitacora-project)
carpeta "$R_BIT"; carpeta "$R_FLO"; carpeta "$R_PRO"

O1=$(correr "$R_BIT")
espera_dirs "1a bitacora se queda SOLO con la suya"    "$O1" "=" "$R_BIT"
espera_no   "1b bitacora NO se lleva bitacora-flota"   "$(patron_de "$R_FLO")" "$(aceptadas "$O1")"
espera_no   "1c bitacora NO se lleva bitacora-project" "$(patron_de "$R_PRO")" "$(aceptadas "$O1")"

# La dirección contraria nunca estuvo rota, pero se clava para que siga así.
espera_dirs "1d bitacora-project se queda con la suya" "$(correr "$R_PRO")" "=" "$R_PRO"

# =========================================================================
# LO QUE EL COMODÍN SÍ TIENE QUE SEGUIR CUBRIENDO: los worktrees de Claude
# =========================================================================
R_AGL=$(repo agentes-lizar)
carpeta "$R_AGL"
carpeta "$R_AGL" "--claude-worktrees-clever-cannon-668c9a"
carpeta "$R_AGL" "--claude-worktrees-interesting-panini-7b5967"
espera_dirs "2  repo + sus dos worktrees" "$(correr "$R_AGL")" \
  "= --claude-worktrees-clever-cannon-668c9a --claude-worktrees-interesting-panini-7b5967" "$R_AGL"

# Un worktree puede tener sesiones sin que el repo principal tenga carpeta propia.
R_SOL=$(repo solo-worktree)
carpeta "$R_SOL" "--claude-worktrees-strange-bohr-1dfebc"
O3=$(correr "$R_SOL")
espera_dirs "3  worktree sin carpeta propia del repo" "$O3" \
  "--claude-worktrees-strange-bohr-1dfebc" "$R_SOL"

# El caso combinado: nombre que es prefijo de otro repo Y con worktree propio.
R_KAN=$(repo kangurea); R_KW=$(repo kangurea-web)
carpeta "$R_KAN"; carpeta "$R_KW"
carpeta "$R_KAN" "--claude-worktrees-charming-chatelet-179416"
O4=$(correr "$R_KAN")
espera_dirs "4a kangurea: la suya y su worktree" "$O4" \
  "= --claude-worktrees-charming-chatelet-179416" "$R_KAN"
espera_no   "4b kangurea NO se lleva kangurea-web" "$(patron_de "$R_KW")" "$(aceptadas "$O4")"
# Worktree aceptado y hermano descartado a la vez: la nota nombra al hermano y no al
# worktree, o sea que las dos ramas conviven sin pisarse.
espera      "4c la nota nombra al hermano"  "$(patron_de "$R_KW")" "$(dicho_de "$O4")"
espera_no   "4d la nota NO nombra al worktree" \
  "  $(patron_de "$R_KAN")--claude-worktrees-charming-chatelet-179416" "$(dicho_de "$O4")"

# =========================================================================
# NO CALLARSE LO QUE SE DESCARTA
# =========================================================================
# La objeción de la entrada del 5-sep a este arreglo era que, si en alguna máquina
# hubiera sesiones abiertas en una SUBCARPETA de un repo, quedarían fuera EN SILENCIO
# -- la dirección mala de este proyecto. Se responde diciéndolo: lo que casa por
# prefijo y no se reconoce se nombra en la salida.
espera "5a lo descartado se dice"         "$(patron_de "$R_FLO")" "$(dicho_de "$O1")"
espera "5b y se dice qué sí se reconoce"  "worktree"              "$(dicho_de "$O1")"

# Y al revés: cuando no se descarta nada, ni una línea de ruido. El auditor corre en
# cada arranque; una nota que sale siempre deja de leerse.
espera_no "6a con worktree y sin ajenas -> sin nota" "descart" "$(dicho_de "$O3")"
R_LIM=$(repo limpio); carpeta "$R_LIM"
espera_no "6b repo aislado -> sin nota"              "descart" "$(dicho_de "$(correr "$R_LIM")")"

# =========================================================================
# NADA QUE MIRAR
# =========================================================================
R_NADA=$(repo sin-sesiones)
O7=$(correr "$R_NADA")
espera         "7a sin carpetas -> NO-SE-PUDO-COMPROBAR" "NO-SE-PUDO-COMPROBAR" "$O7"
espera_ninguna "7b sin carpetas -> cero carpetas"        "$O7"

# Un repo SIN carpeta propia pero con hermanos que casan por prefijo tiene que salir
# como "no sé mirarlo", no como "no hay deuda": es la distinción de los tres estados
# que el auditor lleva en su cabecera.
R_SOLOPRE=$(repo solo); repo solo-otro >/dev/null; carpeta "$REPOS/solo-otro"
O8=$(correr "$R_SOLOPRE")
espera         "8a solo hermanos ajenos -> NO-SE-PUDO-COMPROBAR" "NO-SE-PUDO-COMPROBAR" "$O8"
espera_ninguna "8b solo hermanos ajenos -> cero carpetas"        "$O8"

# =========================================================================
# CARACTERES QUE EL NOMBRE DE CARPETA NO CONSERVA
# =========================================================================
# Medido el 5-sep leyendo el 'cwd' de los transcripts, no supuesto. Hasta entonces el
# auditor solo traducía ':', '/' y '\', así que para '~/repos/CSV Generator' calculaba
# un patrón con el espacio dentro, no encontraba nada y salía NO-SE-PUDO-COMPROBAR.
# Un repo entero invisible, de 44.
R_ESP=$(repo "CSV Generator")
carpeta "$R_ESP"
O9=$(correr "$R_ESP")
espera_dirs "9a repo con ESPACIO en el nombre" "$O9" "=" "$R_ESP"
espera_no   "9b y no se queja de no encontrarlo" "NO-SE-PUDO-COMPROBAR" "$O9"

# El punto importa por sí solo: si se audita DESDE dentro de un worktree,
# 'git rev-parse --show-toplevel' devuelve la ruta del worktree, que lleva '.claude'.
# Sin traducir el punto, el patrón salía con un '.' que ninguna carpeta tiene.
R_DEN=$(repo con-worktree)
DENTRO="$R_DEN/.claude/worktrees/clever-cannon-668c9a"
mkdir -p "$DENTRO"
carpeta "$DENTRO"
O10=$(correr "$DENTRO")
espera_dirs "10a auditar DESDE dentro de un worktree" "$O10" "=" "$DENTRO"
espera_no   "10b y no se queja de no encontrarlo"     "NO-SE-PUDO-COMPROBAR" "$O10"

# Y el nombre que sale de ahí es exactamente el que se ve en el disco real.
if [ "$(patron_de "$DENTRO")" = "$(patron_de "$R_DEN")--claude-worktrees-clever-cannon-668c9a" ]; then
  printf '  ok    %s\n' "10c el patrón del worktree coincide con el del repo + sufijo"; PASA=$((PASA + 1))
else
  printf '  FALLA %s\n        %s\n' "10c el patrón del worktree coincide con el del repo + sufijo" "$(patron_de "$DENTRO")"
  FALLA=$((FALLA + 1))
fi

# =========================================================================
# LOS TRES SITIOS QUE CALCULAN EL PATRÓN NO PUEDEN SEPARARSE
# =========================================================================
# El auditor no es el único que traduce una ruta a nombre de carpeta: sueno.sh lo hace
# para decidir de quién es cada transcript, y sessionstart-leer.sh para reconstruir la
# ruta del transcript actual cuando no le llega por stdin. Si uno cambia y los otros no,
# el sueño DESCARTA EN SILENCIO la deuda de una carpeta que el auditor sí encontró --
# la dirección mala. Se comprueba por texto, que es lo único que no se puede olvidar.
RAIZ_REPO="$(cd "$AQUI/.." && pwd)"
patrones_hallados=$(grep -rhoE "sed 's#\[[^]]*\]#-#g'" \
  "$RAIZ_REPO/scripts/auditar-sesiones.sh" \
  "$RAIZ_REPO/scripts/sueno.sh" \
  "$RAIZ_REPO/hooks/sessionstart-leer.sh" 2>/dev/null | sort -u)
n_distintos=$(printf '%s\n' "$patrones_hallados" | sed '/^$/d' | wc -l | tr -dc '0-9')
if [ "$n_distintos" = "1" ]; then
  printf '  ok    %s\n' "11 los 3 sitios usan la MISMA transformación"; PASA=$((PASA + 1))
else
  printf '  FALLA %s\n        se han separado, hay %s versiones:\n%s\n' \
    "11 los 3 sitios usan la MISMA transformación" "$n_distintos" \
    "$(printf '%s\n' "$patrones_hallados" | sed 's/^/          /')"
  FALLA=$((FALLA + 1))
fi

echo
echo "  $PASA ok, $FALLA falla(s)"
[ "$FALLA" -eq 0 ]
