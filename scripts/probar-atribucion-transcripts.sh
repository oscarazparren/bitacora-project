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
# El auditor de verdad no imprime aquí las "sesiones de fuera": las calcula y las dice
# MÁS TARDE, para que bajo un 'timeout' sobreviva antes la deuda. El banco las provoca
# llamando a la misma función que llama él, que es lo que hay que probar.
declare -F decir_sueltas >/dev/null 2>&1 && decir_sueltas
# Los ANCESTROS van antes que los DIRS a propósito: 'aceptadas' se queda con todo lo
# que viene DESPUÉS de ###DIRS###, así que el marcador de dirs tiene que ser el último.
printf '###ANCESTROS###\n'
if declare -p ancestros 2>/dev/null | grep -q 'declare -a'; then
  [ "${#ancestros[@]}" -gt 0 ] && for d in "${ancestros[@]}"; do printf '%s\n' "${d##*/}"; done
fi
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
  printf '%s' "$(win_de "$1")" | sed 's#[:/\\ .]#-#g'
}
win_de() {     # win_de <dir> -> la ruta tal y como la ve Windows ('C:/Users/...')
  (cd "$1" && pwd -W 2>/dev/null) || printf '%s' "$1"
}

# La barra invertida NO se escribe literal en este fichero, y no es manía: se construye
# desde su código. Al medir esto el 5-sep-2026, un filtro con barras invertidas llegó
# a la herramienta con la mitad comidas, no casó nada y devolvió una lista vacía que se
# lee EXACTAMENTE igual que un "no hay nada". Es la forma del fallo que persigue este
# repo, cometido con la herramienta de medir. Aquí no puede repetirse porque no hay
# ninguna que comerse.
BS=$(awk 'BEGIN{printf "%c", 92}')

cwd_escapado() {  # 'C:/a/b' -> 'C:\\a\\b', que es como el JSON del transcript lo guarda
  local resto="$1" out="" pieza
  while case "$resto" in */*) : ;; *) false ;; esac; do
    pieza=${resto%%/*}; resto=${resto#*/}
    out="$out$pieza$BS$BS"
  done
  printf '%s%s' "$out" "$resto"
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

# transcript <carpeta> <sid> <turnos> <turnos-aquí> <ruta-repo> [escapado]
# Un .jsonl de mentira con la forma que importa: 'type' y 'cwd' en cada apunte de
# asistente. Con 'escapado' escribe el cwd con barras invertidas dobles, que es como lo
# guarda el JSON de verdad; sin él, con '/', que es como lo guardaría un Linux. Las dos
# formas tienen que casar, así que se prueban las dos.
transcript() {
  local dir="$PROY/$1" sid="$2" tot="$3" aqui="$4" repo="$5" esc="${6:-}" i c f dentro fuera
  mkdir -p "$dir"; f="$dir/$sid.jsonl"; : > "$f"
  dentro=$(win_de "$repo"); fuera="C:/"
  if [ -n "$esc" ]; then dentro=$(cwd_escapado "$dentro"); fuera=$(cwd_escapado "C:/"); fi
  i=1
  while [ "$i" -le "$tot" ]; do
    if [ "$i" -le "$aqui" ]; then c="$dentro"; else c="$fuera"; fi
    printf '{"type":"assistant","cwd":"%s","timestamp":"2026-09-01T10:0%s:00.000Z"}\n' \
      "$c" "$((i % 10))" >> "$f"
    i=$((i + 1))
  done
}

# Las variables que el bloque necesita se pasan explícitas y con los valores por defecto
# del auditor: si el bloque empieza a usar una que no esté aquí, 'set -u' lo tumba y se
# ve, en vez de leer una cadena vacía y decidir con ella.
correr() {   # correr <ruta-repo> -> salida cruda del bloque
  RAIZ="$1" PROYECTOS="$PROY" BLOQUE_FILE="$TMP/bloque.sh" \
  DIAS=14 UMBRAL_TURNOS=10 RECIENTE_MIN=30 EXCLUIR="" \
    bash "$TMP/runner.sh" 2>/dev/null
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

# Lo que el bloque dijo por su cuenta, antes del primer marcador.
dicho_de() { printf '%s' "${1%%###ANCESTROS###*}"; }

# Las carpetas ANCESTRO que encontró: las de los directorios que CONTIENEN al repo.
ancestros_de() {
  case "$1" in
    *'###ANCESTROS###'*) printf '%s\n' "${1#*###ANCESTROS###}" \
                           | sed -n '1,/###DIRS###/p' | sed '/###DIRS###/d;/^$/d' | sort ;;
    *) : ;;
  esac
}

espera_ancestros() {  # <nombre> <salida> <nombres-esperados...>
  local nombre="$1" salida="$2"; shift 2
  local queria obtenido
  queria=$(printf '%s\n' "$@" | sed '/^$/d' | sort)
  obtenido=$(ancestros_de "$salida")
  if [ "$queria" = "$obtenido" ]; then
    printf '  ok    %s\n' "$nombre"; PASA=$((PASA + 1))
  else
    printf '  FALLA %s\n        esperaba: %s\n        obtuvo:   %s\n' \
      "$nombre" "$(resumen_de "$queria")" "$(resumen_de "$obtenido")"
    FALLA=$((FALLA + 1))
  fi
}

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

# =========================================================================
# LAS SESIONES QUE NO PERTENECEN A UN SOLO REPO
# =========================================================================
# Medido el 5-sep-2026 en el PC viejo: las carpetas 'C--' y 'C--Users-Oscar' -- sesiones
# abiertas en 'C:\' o en el home -- guardan 7 sesiones que trabajaron dentro de repos con
# bitácora, y eran INVISIBLES para el auditor y para el sueño. El nombre de su carpeta es
# correcto, así que ningún arreglo de la transformación las alcanza.
#
# SE DECLARAN, NO SE REPARTEN, y la razón es que el auditor NO PUEDE saber. Su prueba de
# "anotada" es "hay un commit que toca ESTA bitácora en la ventana", y eso no distingue
# "anotó donde tocaba" de "no anotó": una sesión que tocó seis repos y dejó UNA entrada
# correcta saldría ANOTADA en uno y SIN-ANOTAR en cinco. Eso es deuda falsa por sesión, y
# la deuda falsa se deja de leer -- momento en el cual la deuda de verdad también es
# silenciosa. Es el fallo de siempre, alcanzado por el lado ruidoso.
#
# Y los números lo rematan: en las 7, la MAYORÍA de los turnos no está en ningún repo
# (268 de 328, 88 de 264, 99 de 194, 49 de 59). Las colas por repo son minúsculas -- la
# sesión de 230 turnos tocó 'lizar-asistente-aula' UN turno y 'AlcoholTax-IA' dos.
# Repartir cobraría a seis bitácoras una entrada por eso.
#
# El umbral que decide si se NOMBRA es el UMBRAL_TURNOS que ya existe, no uno nuevo: su
# significado ("por debajo de esto no hay nada que anotar") es exactamente el que hace
# falta aquí, y ya está calibrado.
R_ANC=$(repo con-ancestro)
carpeta "$R_ANC"
CARPETA_ANC=$(patron_de "$REPOS")   # la carpeta de proyecto del directorio que los contiene
carpeta "$REPOS"

espera_ancestros "12a ve la carpeta del directorio que lo contiene" \
  "$(correr "$R_ANC")" "$CARPETA_ANC"

# Un repo sin ninguna carpeta ancestro en disco no inventa ninguna. Vive en otro árbol a
# propósito: bajo "$REPOS" la carpeta ancestro ya existe, así que probarlo ahí no probaría
# nada. Y se comprueba, porque el bucle sube hasta la raíz del disco y ahí es donde una
# comprobación floja convertiría a 'C--' en ancestro de todo.
mkdir -p "$TMP/aparte/aislado"
espera_ancestros "12b sin carpetas ancestro -> ninguna" "$(correr "$TMP/aparte/aislado")" ""

# Sesión de la carpeta ancestro que trabajó AQUÍ por encima del umbral: se nombra.
transcript "$CARPETA_ANC" "aaaa1111-de-fuera" 40 12 "$R_ANC" escapado
O12=$(correr "$R_ANC")
espera "13a la sesión de fuera se declara" "NO-SE-PUDO-COMPROBAR (sesiones de fuera)" "$(dicho_de "$O12")"
espera "13b y se la nombra"                "aaaa1111-de-fuera"     "$(dicho_de "$O12")"
espera "13c con cuántos turnos fueron aquí" "12 de 40"             "$(dicho_de "$O12")"

# NO es deuda. Meterla en SIN-ANOTAR o en PENDIENTES sería colapsar "no lo sé" con "no
# hay nada", que es justo lo que la cabecera del auditor prohíbe -- y además el sueño la
# pasaría por su filtro de dueño, que no reconoce estas carpetas y la tiraría en silencio.
espera_no "13d no se cuenta como deuda"    "SIN-ANOTAR"  "$(dicho_de "$O12")"
espera_no "13e ni entra en PENDIENTES"     "PENDIENTES"  "$(dicho_de "$O12")"

# Y no se lleva por delante lo que sí es suyo.
espera_dirs "13f la carpeta propia sigue aceptándose" "$O12" "=" "$R_ANC"

# El cwd con '/' (un Linux) tiene que casar igual que el escapado de Windows.
transcript "$CARPETA_ANC" "bbbb2222-con-barras" 30 15 "$R_ANC"
espera "14 el cwd con '/' casa igual que el escapado" "bbbb2222-con-barras" \
  "$(dicho_de "$(correr "$R_ANC")")"

# Por debajo del umbral no se nombra: el auditor corre en CADA arranque y una nota que
# sale siempre deja de leerse. Un turno de paso no es trabajo que deba anotarse.
transcript "$CARPETA_ANC" "cccc3333-de-paso" 40 3 "$R_ANC"
espera_no "15a un roce por debajo del umbral no se nombra" "cccc3333-de-paso" \
  "$(dicho_de "$(correr "$R_ANC")")"

# Una sesión de la carpeta ancestro que nunca pisó este repo no es asunto suyo.
transcript "$CARPETA_ANC" "dddd4444-ajena" 50 0 "$R_ANC"
espera_no "15b una sesión que no pisó el repo no se nombra" "dddd4444-ajena" \
  "$(dicho_de "$(correr "$R_ANC")")"

# Y un repo hermano no hereda las sesiones del otro por estar bajo el mismo ancestro:
# el cotejo es contra la ruta del repo, no contra la carpeta.
espera_no "15c el hermano no hereda esas sesiones" "aaaa1111-de-fuera" \
  "$(dicho_de "$(correr "$R_KW")")"

# =========================================================================
# LOS TRES SITIOS QUE CONSUMEN LA SALIDA DEL AUDITOR
# =========================================================================
# Mismo argumento que el caso 11, un piso más arriba: el auditor puede decir algo nuevo y
# los dos que le leen seguir sin enterarse. El hook de arranque filtra por '^SIN-ANOTAR '
# y el sueño por el bloque PENDIENTES; si ninguno conoce este marcador, el auditor lo dice
# y NADIE lo oye -- que es peor que no decirlo, porque parece cubierto.
# El marcador es específico y no el 'NO-SE-PUDO-COMPROBAR:' a secas: esa cadena ya la usa
# el auditor para otra cosa distinta ("no encuentro transcripts"), y un consumidor que
# filtrara por ella confundiría dos avisos que piden mirar sitios distintos.
MARCA='NO-SE-PUDO-COMPROBAR (sesiones de fuera)'
faltan=""
for pieza in scripts/auditar-sesiones.sh scripts/sueno.sh hooks/sessionstart-leer.sh; do
  # Se quitan las barras invertidas antes de comparar: quien lo emite lo escribe tal cual,
  # y quien lo lee tiene que escapar los paréntesis para su regex. Son la misma cadena y
  # tienen que contar como tal, o el banco obligaría a una de las dos a estar mal.
  tr -d '\134' < "$RAIZ_REPO/$pieza" 2>/dev/null | grep -qF -- "$MARCA" || faltan="$faltan $pieza"
done
if [ -z "$faltan" ]; then
  printf '  ok    %s\n' "16 los 3 que leen al auditor conocen el marcador nuevo"; PASA=$((PASA + 1))
else
  printf '  FALLA %s\n        no lo conocen:%s\n' \
    "16 los 3 que leen al auditor conocen el marcador nuevo" "$faltan"
  FALLA=$((FALLA + 1))
fi

echo
echo "  $PASA ok, $FALLA falla(s)"
[ "$FALLA" -eq 0 ]
