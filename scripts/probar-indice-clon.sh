#!/bin/bash
# Bitácora — BANCO DE PRUEBAS del clasificador de la sección 0 de
# hooks/sessionstart-leer.sh (el índice de cambios: ¿está este clon en la punta
# que vio el servidor?).
#
# ============================================================================
# POR QUÉ EXISTE ESTE FICHERO
# ============================================================================
#
# El 6-sep-2026 la sección 0 dejó de comparar contra un marcador ("esto ya te lo
# enseñé") y pasó a comparar contra el .git del clon. El motivo era un fallo
# silencioso: con el marcador, un repo por detrás avisaba UNA vez y luego callaba
# para siempre — y "sin movimiento en 43 repos" se lee exactamente igual que la
# buena noticia.
#
# El mismo día, la auditoría encontró que el clasificador nuevo tenía su propia
# puerta al mismo silencio: si el SHA del servidor llegaba VACÍO (una lectura
# cortada del fichero de estado), la comparación `est == m2` era `"" == ""` y el
# repo salía AL DÍA sin haberse comparado nada. Se encontró extrayendo el awk y
# corriéndolo con una entrada preparada. En dos comandos.
#
# De ahí este banco. El clasificador es una función pura —líneas E/R/L y los
# ficheros de .git entran, un estado por repo sale— y por tanto es lo más barato
# de probar que hay en este repo. El hook corre en CADA arranque de sesión en las
# dos máquinas: una regresión aquí no rompe una pantalla, apaga un aviso.
#
# LO QUE SE PRUEBA ES EL HOOK REAL, no una copia. El awk se extrae EN VIVO del
# fichero, igual que hace probar-1d-deriva.sh con la sección 1d: si alguien lo
# edita, este banco prueba la versión nueva, no una que se quedó aquí pegada.
#
# Uso:
#   scripts/probar-indice-clon.sh                  # contra hooks/sessionstart-leer.sh
#   scripts/probar-indice-clon.sh /ruta/al/hook.sh # contra otra copia
# Sale 0 si todo pasa. No toca nada fuera de su directorio temporal.

set -uo pipefail

AQUI="$(cd "$(dirname "$0")" && pwd)"
HOOK="${1:-$AQUI/../hooks/sessionstart-leer.sh}"
[ -f "$HOOK" ] || { echo "no encuentro el hook: $HOOK" >&2; exit 2; }

# --- Extraer el clasificador del hook real ----------------------------------
BLOQUE=$(awk '
  !f && index($0, "awk -v home=") > 0 { f=1; next }
  f && index($0, "\"$TMPD/todo\" > \"$TMPD/salida\"") > 0 { exit }
  f { print }
' "$HOOK")
[ -n "$BLOQUE" ] || { echo "no encuentro el awk de la sección 0 en $HOOK" >&2; exit 2; }
for pieza in 'function refsha(' 'function packed(' 'PENDIENTE' 'SINDATOS' 'NOSESABE'; do
  case "$BLOQUE" in
    *"$pieza"*) : ;;
    *) echo "el awk extraído no tiene la pinta esperada (falta: $pieza)" >&2; exit 2 ;;
  esac
done

TMP=$(mktemp -d 2>/dev/null) || { echo "mktemp -d falló" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT
printf '%s\n' "$BLOQUE" > "$TMP/indice.awk"

R="$TMP/repos"   # hace de $HOME: los repos se buscan en $HOME/<n> y $HOME/repos/<n>
mkdir -p "$R/repos"

# Un repo de usar y tirar con N commits vacíos. Devuelve el SHA de la punta.
crear() {  # <ruta> [n_commits]
  local ruta="$1" n="${2:-1}" i
  git init -q "$ruta" 2>/dev/null
  git -C "$ruta" config user.email banco@local >/dev/null
  git -C "$ruta" config user.name banco >/dev/null
  for i in $(seq 1 "$n"); do git -C "$ruta" commit -q --allow-empty -m "c$i"; done
  git -C "$ruta" rev-parse HEAD
}
rama_local() { git -C "$1" symbolic-ref --short HEAD 2>/dev/null || echo main; }

# El runner: monta el fichero de entrada y devuelve la clasificación.
clasifica() {  # <lineas de entrada por stdin> -> ESTADO<TAB>nombre[<TAB>ruta]
  cat > "$TMP/todo"
  awk -v home="$R" -f "$TMP/indice.awk" "$TMP/todo"
}

PASA=0
FALLA=0
espera() {  # <nombre> <linea_esperada_exacta> <salida>
  local nombre="$1" esperado="$2" salida="$3"
  if printf '%s\n' "$salida" | grep -qxF -- "$esperado"; then
    printf '  ok    %s\n' "$nombre"; PASA=$((PASA + 1))
  else
    printf '  FALLA %s\n        esperaba la línea: %s\n        salió: %s\n' \
      "$nombre" "$esperado" "$(printf '%s' "$salida" | tr '\n' '|' | cut -c1-220)"
    FALLA=$((FALLA + 1))
  fi
}
espera_no() {  # <nombre> <trozo_prohibido> <salida>
  local nombre="$1" trozo="$2" salida="$3"
  if printf '%s' "$salida" | grep -qF -- "$trozo"; then
    printf '  FALLA %s\n        NO debía aparecer: %s\n        salió: %s\n' \
      "$nombre" "$trozo" "$(printf '%s' "$salida" | tr '\n' '|' | cut -c1-220)"
    FALLA=$((FALLA + 1))
  else
    printf '  ok    %s\n' "$nombre"; PASA=$((PASA + 1))
  fi
}

echo
echo "Banco del índice de cambios (clasificador de la sección 0)"
echo "Hook: $HOOK"
echo

TAB=$(printf '\t')

# --- 1. el caso normal: el clon está donde dice el servidor ------------------
S1=$(crear "$R/repos/aldia")
O=$(printf 'E aldia %s\nL aldia\n' "$S1" | clasifica)
espera "1  clon en la punta -> AL DÍA" "ALDIA${TAB}aldia" "$O"

# --- 2. por detrás: lo que motivó todo el cambio -----------------------------
crear "$R/repos/detras" >/dev/null
O=$(printf 'E detras 1111111111111111111111111111111111111111\nL detras\n' | clasifica)
espera "2  clon por detrás -> PENDIENTE" "PENDIENTE${TAB}detras${TAB}$R/repos/detras" "$O"

# --- 3. refs empaquetados (ECC los tiene TODOS así) --------------------------
S3=$(crear "$R/repos/packed")
git -C "$R/repos/packed" pack-refs --all
O=$(printf 'E packed %s\nL packed\n' "$S3" | clasifica)
espera "3  packed-refs, sin ref suelto -> AL DÍA" "ALDIA${TAB}packed" "$O"

# --- 4. rama de trabajo abierta, con main en la punta (el caso ECC) ----------
# Comparar SOLO contra HEAD daría aquí un PENDIENTE que no se puede apagar
# mientras la rama siga viva, y un aviso perpetuo enseña a no leer los avisos.
S4=$(crear "$R/repos/conrama")
git -C "$R/repos/conrama" checkout -q -b fix/algo
git -C "$R/repos/conrama" commit -q --allow-empty -m "en la rama"
O=$(printf 'E conrama %s\nL conrama\n' "$S4" | clasifica)
espera "4  HEAD en una rama, main en la punta -> AL DÍA" "ALDIA${TAB}conrama" "$O"

# --- 5. HEAD desprendido, main en la punta -----------------------------------
S5=$(crear "$R/repos/desprendido" 2)
git -C "$R/repos/desprendido" checkout -q --detach HEAD~1
O=$(printf 'E desprendido %s\nL desprendido\n' "$S5" | clasifica)
espera "5  HEAD desprendido, main en la punta -> AL DÍA" "ALDIA${TAB}desprendido" "$O"

# --- 6. fetch SIN merge: los refs remotos NO cuentan -------------------------
# origin/main al día y el árbol por detrás es EXACTAMENTE el fallo que se está
# arreglando. Si algún día esto pasa a AL DÍA, el índice ha vuelto a mentir.
S6=$(crear "$R/repos/fetchado" 2)
git -C "$R/repos/fetchado" branch -f otra HEAD
git -C "$R/repos/fetchado" reset -q --hard HEAD~1
mkdir -p "$R/repos/fetchado/.git/refs/remotes/origin"
printf '%s\n' "$S6" > "$R/repos/fetchado/.git/refs/remotes/origin/main"
O=$(printf 'E fetchado %s\nL fetchado\n' "$S6" | clasifica)
espera "6a fetch sin merge -> PENDIENTE" "PENDIENTE${TAB}fetchado${TAB}$R/repos/fetchado" "$O"
espera_no "6b y NO dice AL DÍA por el ref remoto" "ALDIA" "$O"

# --- 7. worktree: .git es un FICHERO y los refs viven en el común ------------
S7=$(crear "$R/repos/conwt")
git -C "$R/repos/conwt" worktree add -q "$R/repos/wt" -b ramawt 2>/dev/null
O=$(printf 'E wt %s\nL wt\n' "$S7" | clasifica)
espera "7  worktree (.git como fichero) -> AL DÍA" "ALDIA${TAB}wt" "$O"

# --- 8. .git ilegible: NO es "al día", es "no se sabe" -----------------------
mkdir -p "$R/repos/roto/.git"
printf 'ref: refs/heads/main\n' > "$R/repos/roto/.git/HEAD"
O=$(printf 'E roto 1111111111111111111111111111111111111111\nL roto\n' | clasifica)
espera "8  .git sin refs -> NO SE SABE" "NOSESABE${TAB}roto${TAB}$R/repos/roto" "$O"

# --- 9. repo recién inicializado, sin ningún commit --------------------------
git init -q "$R/repos/vacio" 2>/dev/null
O=$(printf 'E vacio 1111111111111111111111111111111111111111\nL vacio\n' | clasifica)
espera "9  repo sin commits -> NO SE SABE" "NOSESABE${TAB}vacio${TAB}$R/repos/vacio" "$O"

# --- 10. vigilado y sin clonar aquí ------------------------------------------
O=$(printf 'E fantasma 1111111111111111111111111111111111111111\nL fantasma\n' | clasifica)
espera "10 sin clon local -> NO CLONADO" "NOCLON${TAB}fantasma" "$O"

# --- 11. el servidor no sabe nada de ese repo --------------------------------
O=$(printf 'L huerfano\n' | clasifica)
espera "11a sin fila en el estado -> SIN DATOS" "SINDATOS${TAB}huerfano" "$O"
espera_no "11b y no se anota su marca" "MARCA" "$O"

# --- 12. EL ROJO DE LA AUDITORÍA: SHA del servidor vacío ---------------------
# Una lectura cortada del estado deja la última línea sin SHA. Antes: "" == ""
# (refs/heads/master no existe) -> AL DÍA sin haber comparado nada.
O=$(printf 'E aldia\nL aldia\n' | clasifica)
espera "12a SHA del servidor vacío -> SIN DATOS" "SINDATOS${TAB}aldia" "$O"
espera_no "12b y NUNCA al día (regresión del 6-sep)" "ALDIA" "$O"

# --- 13. $RUTAS: carpeta que no se llama como el repo, y con espacios --------
S13=$(crear "$R/OpenCo Desing")
O=$(printf 'E openco %s\nR openco %s\nL openco\n' "$S13" "$R/OpenCo Desing" | clasifica)
espera "13a ruta por \$RUTAS con espacios -> AL DÍA" "ALDIA${TAB}openco" "$O"
git -C "$R/OpenCo Desing" commit -q --allow-empty -m otro
O=$(printf 'E openco %s\nR openco %s\nL openco\n' "$S13" "$R/OpenCo Desing" | clasifica)
espera "13b y la ruta sale ENTERA, sin cortar por el espacio" \
  "PENDIENTE${TAB}openco${TAB}$R/OpenCo Desing" "$O"

# --- 14. la lista de vigilados admite comentarios y líneas en blanco ---------
O=$(printf 'E aldia %s\nL # esto es un comentario\nL\nL aldia\n' "$S1" | clasifica)
espera "14a comentarios y blancos se saltan" "ALDIA${TAB}aldia" "$O"
espera_no "14b y el comentario no se toma por un repo" "#" "$O"

# --- 15. el contrato con los consumidores: separador TAB ---------------------
# La sección 0 los lee con awk -F'\t'. Si esto vuelve a ser un espacio, las rutas
# con espacios salen cortadas y se le da al agente una ruta que no existe.
O=$(printf 'E detras 1111111111111111111111111111111111111111\nL detras\n' | clasifica)
espera "15a el separador es TAB, no espacio" "PENDIENTE${TAB}detras${TAB}$R/repos/detras" "$O"
espera "15b y los consumidores lo parten bien" "$R/repos/detras" \
  "$(printf '%s\n' "$O" | awk -F'\t' '$1=="PENDIENTE" {print $3}')"

# --- 16. coste: ni un proceso por repo ---------------------------------------
# La sección 0 se reescribió una vez porque costaba 41 s con 40 repos lanzando
# dos awk por repo. Aquí se comprueba que sigue siendo UNA pasada.
{ printf 'E aldia %s\n' "$S1"; for i in $(seq 1 60); do printf 'L aldia\n'; done; } > "$TMP/muchos"
INI=$(date +%s)
awk -v home="$R" -f "$TMP/indice.awk" "$TMP/muchos" > /dev/null
SEGS=$(( $(date +%s) - INI ))
if [ "$SEGS" -le 5 ]; then
  printf '  ok    16 60 repos en %ss (una sola pasada de awk)\n' "$SEGS"; PASA=$((PASA + 1))
else
  printf '  FALLA 16 60 repos tardaron %ss: eso huele a un proceso por repo\n' "$SEGS"
  FALLA=$((FALLA + 1))
fi

echo
echo "  $PASA ok, $FALLA falla(s)"
[ "$FALLA" -eq 0 ]
