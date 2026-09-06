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

# ============================================================================
# LA COLUMNA DEL REF (6-sep-2026, tarde)
# ============================================================================
# Hasta hoy el receptor guardaba el SHA de CUALQUIER push y nunca miraba
# datos["ref"], así que un push a una rama de trabajo pisaba el SHA del repo
# igual que uno a main. Con la comparación contra el clon eso da dos fallos: un
# falso "al día" (si tu HEAD está en esa rama) y, peor, un PENDIENTE que ningún
# `git pull` apaga -- y un renglón inapagable enseña a no leer la lista.
#
# El arreglo de verdad está en el servidor (solo entra el push a la rama por
# defecto). Lo que se prueba AQUÍ es la otra mitad: que el cliente sepa DE QUÉ
# RAMA es el SHA que le dan, en vez de suponer que es main o master.
#
# EL CONTRATO, y es raro a propósito: las columnas extra se identifican POR SU
# VALOR, no por su posición. La 4.ª ya la ocupaba el literal 'sembrado' en 24
# filas vivas cuando esto se escribió, y los dos escritores (el receptor en el
# servidor, sembrar-estado.sh desde cualquiera de los dos PCs) se despliegan por
# separado. La que empieza por refs/heads/ es el ref; lo demás son etiquetas.

# --- 16. rama por defecto que no es main ni master ---------------------------
# El caso que la columna existe para arreglar. Repo cuya rama por defecto es
# `trunk`, con una rama de trabajo encima: no hay main ni master locales, así
# que sin el ref no hay con qué comparar y el repo se queda en un PENDIENTE
# perpetuo que ningún pull apaga.
S16=$(crear "$R/repos/trunkrepo")
git -C "$R/repos/trunkrepo" branch -m trunk
git -C "$R/repos/trunkrepo" checkout -q -b faena
git -C "$R/repos/trunkrepo" commit -q --allow-empty -m "en la faena"
O=$(printf 'E trunkrepo %s 2026-09-06T12:00:00+00:00\nL trunkrepo\n' "$S16" | clasifica)
espera "16a sin ref: rama por defecto rara -> PENDIENTE inapagable" \
  "PENDIENTE${TAB}trunkrepo${TAB}$R/repos/trunkrepo" "$O"
O=$(printf 'E trunkrepo %s 2026-09-06T12:00:00+00:00 refs/heads/trunk\nL trunkrepo\n' "$S16" | clasifica)
espera "16b con ref: se compara contra la rama que dice el servidor -> AL DÍA" \
  "ALDIA${TAB}trunkrepo" "$O"

# --- 17. el ref NO puede fabricar un "al día" --------------------------------
# La ampliación es un candidato más, no una barra libre: si la rama que nombra
# el servidor está por detrás en el clon, sigue siendo PENDIENTE.
O=$(printf 'E trunkrepo 2222222222222222222222222222222222222222 2026-09-06T12:00:00+00:00 refs/heads/trunk\nL trunkrepo\n' | clasifica)
espera "17a ref conocido pero SHA que no está -> PENDIENTE" \
  "PENDIENTE${TAB}trunkrepo${TAB}$R/repos/trunkrepo" "$O"
espera_no "17b y no cuela un AL DÍA" "ALDIA" "$O"

# --- 18. 'sembrado' en la 4.ª columna NO es un ref ---------------------------
# 24 de las 45 filas vivas tenían esa marca cuando esto se escribió. Un lector
# que leyera la 4.ª columna a ciegas la tomaría por un nombre de rama.
S18=$(crear "$R/repos/consembrado")
O=$(printf 'E consembrado %s 2026-09-01T21:08:54+00:00 sembrado\nL consembrado\n' "$S18" | clasifica)
espera "18a fila sembrada al día -> AL DÍA (main, como siempre)" "ALDIA${TAB}consembrado" "$O"
O=$(printf 'E consembrado 1111111111111111111111111111111111111111 2026-09-01T21:08:54+00:00 sembrado\nL consembrado\n' | clasifica)
espera "18b fila sembrada por detrás -> PENDIENTE" \
  "PENDIENTE${TAB}consembrado${TAB}$R/repos/consembrado" "$O"

# --- 19. las dos marcas a la vez (el formato que siembra desde hoy) ----------
O=$(printf 'E trunkrepo %s 2026-09-06T12:00:00+00:00 refs/heads/trunk sembrado\nL trunkrepo\n' "$S16" | clasifica)
espera "19a ref y la marca juntos: manda el valor, no la posición" "ALDIA${TAB}trunkrepo" "$O"
O=$(printf 'E trunkrepo %s 2026-09-06T12:00:00+00:00 sembrado refs/heads/trunk\nL trunkrepo\n' "$S16" | clasifica)
espera "19b y en el orden contrario, igual" "ALDIA${TAB}trunkrepo" "$O"

# --- 20. solo refs/heads/: un ref REMOTO en la columna no vale --------------
# Aceptar refs/remotes/origin/* reintroduce el fallo entero: un fetch sin merge
# los deja al día con el árbol por detrás. Vale para lo que el awk lee del .git
# y vale también para lo que le manden por la columna.
O=$(printf 'E fetchado %s 2026-09-06T12:00:00+00:00 refs/remotes/origin/main\nL fetchado\n' "$S6" | clasifica)
espera "20a ref remoto en la columna -> PENDIENTE" \
  "PENDIENTE${TAB}fetchado${TAB}$R/repos/fetchado" "$O"
espera_no "20b y nunca AL DÍA" "ALDIA" "$O"

# --- 21. la guarda de NO SE SABE, por sus dos lados ---------------------------
# 21a: un ref que tampoco se puede leer no salva un .git ilegible. OJO: aquí NO
# vale poner refs/heads/main, que es lo que ponía la primera versión de este caso:
# main es literalmente m1, así que pasaba igual con la guarda nueva y sin ella.
# Tiene que ser una rama que no sea ninguno de los tres candidatos de siempre.
O=$(printf 'E roto 1111111111111111111111111111111111111111 2026-09-06T12:00:00+00:00 refs/heads/trunk\nL roto\n' | clasifica)
espera "21a ref ilegible y .git sin refs -> NO SE SABE" "NOSESABE${TAB}roto${TAB}$R/repos/roto" "$O"

# 21b: y el otro lado, que es el que la guarda existe para PERMITIR. HEAD apunta a
# una rama que no existe y no hay main ni master, así que h, m1 y m2 son los tres
# vacíos: lo único legible es la rama que nombra el servidor. Sin el término
# `rs == ""` en la guarda, esto saldría NO SE SABE teniendo el dato delante.
S21=$(crear "$R/repos/solotrunk")
git -C "$R/repos/solotrunk" branch -m trunk
printf 'ref: refs/heads/noexiste\n' > "$R/repos/solotrunk/.git/HEAD"
O=$(printf 'E solotrunk %s 2026-09-06T12:00:00+00:00 refs/heads/trunk\nL solotrunk\n' "$S21" | clasifica)
espera "21b HEAD roto y sin main, pero el ref del servidor sí se lee -> AL DÍA" "ALDIA${TAB}solotrunk" "$O"

# --- 22. el ref no puede sacar la lectura de su .git -------------------------
# El valor llega por la red. Un ref con '..' compone una ruta hacia arriba, y
# leer1() lee ficheros a pelo: si al otro lado hay 40 hex, sale un AL DÍA
# fabricado. Un nombre de rama de git nunca lleva '..', así que se descarta por
# la forma. Hoy hace falta una firma HMAC válida para llegar hasta aquí; el
# cerrojo cuesta una comparación.
S22=$(crear "$R/repos/escape")
printf '%s\n' "$S22" > "$R/repos/escape/trampa"
git -C "$R/repos/escape" commit -q --allow-empty -m "el clon avanza"
# Y con aserción POSITIVA, no solo con la negativa: `espera_no` da verde si el awk
# no imprime NADA, así que el caso más sensible del banco pasaría en verde ante
# cualquier cosa que tumbase el awk entero. Lo señaló la auditoría del 6-sep.
O=$(printf 'E escape %s 2026-09-06T12:00:00+00:00 refs/heads/../../../trampa\nL escape\n' "$S22" | clasifica)
espera "22a ref con .. no lee fuera del .git" "PENDIENTE${TAB}escape${TAB}$R/repos/escape" "$O"
espera_no "22b y nunca AL DÍA" "ALDIA" "$O"

# --- 23. dos filas del mismo repo: el ref no se queda pegado -----------------
# `est` se sobrescribe en cada linea `E` y `refsrv` solo cuando la linea trae ref.
# Sin el `delete refsrv[$2]`, el ref de la primera fila se empareja con el SHA de
# la segunda, y aqui eso sale como un AL DIA fabricado: la segunda fila no dice de
# que rama es su SHA, pero se compara contra la rama que decia la primera.
# Ningun escritor de hoy puede repetir un repo; el caso existe porque TODO el
# cambio se apoya en que el ref y el SHA vengan del MISMO push.
O=$(printf 'E solotrunk %s f refs/heads/trunk\nE solotrunk %s f\nL solotrunk\n' "$S21" "$S21" | clasifica)
espera "23  ref de una fila + SHA de otra -> NO SE SABE, no AL DIA"   "NOSESABE${TAB}solotrunk${TAB}$R/repos/solotrunk" "$O"

# --- 24. coste: ni un proceso por repo ---------------------------------------
# La sección 0 se reescribió una vez porque costaba 41 s con 40 repos lanzando
# dos awk por repo. Aquí se comprueba que sigue siendo UNA pasada.
{ printf 'E aldia %s\n' "$S1"; for i in $(seq 1 60); do printf 'L aldia\n'; done; } > "$TMP/muchos"
INI=$(date +%s)
awk -v home="$R" -f "$TMP/indice.awk" "$TMP/muchos" > /dev/null
SEGS=$(( $(date +%s) - INI ))
if [ "$SEGS" -le 5 ]; then
  printf '  ok    24 60 repos en %ss (una sola pasada de awk)\n' "$SEGS"; PASA=$((PASA + 1))
else
  printf '  FALLA 24 60 repos tardaron %ss: eso huele a un proceso por repo\n' "$SEGS"
  FALLA=$((FALLA + 1))
fi

echo
echo "  $PASA ok, $FALLA falla(s)"
[ "$FALLA" -eq 0 ]
