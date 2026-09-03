#!/bin/bash
# Bitácora — BANCO DE PRUEBAS de la sección 1d de hooks/sessionstart-leer.sh
# (deriva del CLAUDE.md: tu copia local contra la canónica compartida).
#
# ============================================================================
# POR QUÉ EXISTE ESTE FICHERO
# ============================================================================
#
# La sección 1d se estrenó el 1-sep-2026 con un banco de 13 casos que NUNCA se
# commiteó: era un directorio de usar y tirar y desapareció. El 3-sep el hook
# recomendó EN VIVO la dirección destructiva (copiar el canónico viejo encima
# del local, que habría borrado de toda la flota la regla de PowerShell) porque
# la rama "no aparece en la historia" decidía con el MTIME, que responde "cuál
# se tocó al final" y no "quién tiene contenido que al otro le falta".
#
# El arreglo sustituyó el mtime por el RECUENTO DE LÍNEAS del diff. Este banco
# queda commiteado para que ese arreglo no se pueda romper en silencio: el hook
# corre en CADA arranque de sesión en las dos máquinas, así que una regresión
# aquí rompe el arranque en las dos.
#
# ============================================================================
# CÓMO PRUEBA SIN DUPLICAR EL CÓDIGO
# ============================================================================
#
# Extrae EN VIVO el bloque de la sección 1d del hook real (entre sus marcadores
# "# ---------- 1d." y "# ---------- 2.") y lo ejecuta con stubs mínimos para
# hay_tiempo()/tope()/saltado() y con CLAUDE_LOCAL/CLAUDE_CANONICO apuntando a
# un fixture. Si alguien edita la 1d, el banco prueba la versión nueva sin que
# haya que tocar este fichero.
#
# Fixture: un repo git "canónico" de mentira con historia real (c1 -> c2 -> c3),
# y un fichero "local" distinto por caso. Cero red.
#
# Se ejecuta a mano:  bash scripts/probar-1d-deriva.sh
# Corre en Git Bash y en el servidor Linux de flota (usa git, awk, diff, grep,
# printf, touch -d; el hook de dentro usa además stat, date -d, timeout).

set -uo pipefail

AQUI="$(cd "$(dirname "$0")" && pwd)"
HOOK="${1:-$AQUI/../hooks/sessionstart-leer.sh}"
[ -f "$HOOK" ] || { echo "no encuentro el hook: $HOOK" >&2; exit 2; }

# --- Extraer el bloque 1d del hook real -------------------------------------
BLOQUE=$(awk '
  /^# ---------- 1d\./ { f=1 }
  f && /^# ---------- 2\./ { exit }
  f { print }
' "$HOOK")
[ -n "$BLOQUE" ] || { echo "no encuentro la sección 1d en $HOOK" >&2; exit 2; }
case "$BLOQUE" in
  *'if [ -n "$CLAUDE_CANONICO" ]; then'*) : ;;
  *) echo "el bloque 1d extraído no tiene la pinta esperada" >&2; exit 2 ;;
esac

TMP=$(mktemp -d 2>/dev/null) || { echo "mktemp -d falló" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT
printf '%s\n' "$BLOQUE" > "$TMP/bloque-1d.sh"

# El runner que ejecuta el bloque con el entorno de un caso. Recibe todo por
# variables de entorno para no pelearse con el quoting.
cat > "$TMP/runner.sh" <<'RUNNER'
set -uo pipefail
SALIDA=""
DEGRADADO=""
if [ "${CON_TIEMPO:-si}" = "si" ]; then
  hay_tiempo() { return 0; }
else
  hay_tiempo() { return 1; }
fi
tope() { printf '%s' "${1:-4}"; }
saltado() { DEGRADADO="${DEGRADADO}${1}"$'\n'; }
# shellcheck disable=SC1090
. "$BLOQUE_1D_FILE"
printf '%s' "$SALIDA"
printf '\n###DEGRADADO###%s' "$DEGRADADO"
RUNNER

GIT="git -c user.email=t@t -c user.name=t -c init.defaultBranch=main -c commit.gpgsign=false -c core.autocrlf=false"

# Tres versiones del canónico, cada una añade una sección sobre la anterior.
BASE=$'# CLAUDE.md\n\n## Regla uno\nTexto de la regla uno.\n\n## Regla dos\nTexto de la regla dos.\n\n## Regla tres\nTexto de la regla tres.\n'
V1="$BASE"
V2="$BASE"$'\n## Regla cuatro\nAñadida en c2.\n'
V3="$V2"$'\n## Regla cinco\nAñadida en c3.\n'

# construir_canon <dir>  -> repo git con config/CLAUDE.md e historia c1->c2->c3
construir_canon() {
  local d="$1"
  mkdir -p "$d/config"
  ( cd "$d" && $GIT init -q )
  printf '%s' "$V1" > "$d/config/CLAUDE.md"; ( cd "$d" && $GIT add -A && $GIT commit -qm c1 )
  printf '%s' "$V2" > "$d/config/CLAUDE.md"; ( cd "$d" && $GIT add -A && $GIT commit -qm c2 )
  printf '%s' "$V3" > "$d/config/CLAUDE.md"; ( cd "$d" && $GIT add -A && $GIT commit -qm c3 )
}

correr_1d() {  # <local_md> <canon_md> [con_tiempo]
  CLAUDE_LOCAL="$1" CLAUDE_CANONICO="$2" CON_TIEMPO="${3:-si}" \
  BLOQUE_1D_FILE="$TMP/bloque-1d.sh" \
    bash "$TMP/runner.sh" 2>/dev/null
}

PASA=0
FALLA=0

# El veredicto SÍ está.
espera() {  # <nombre> <trozo_esperado> <salida>
  local nombre="$1" trozo="$2" salida="$3"
  if printf '%s' "$salida" | grep -qF -- "$trozo"; then
    printf '  ok    %s\n' "$nombre"; PASA=$((PASA + 1))
  else
    printf '  FALLA %s\n        esperaba contener: %s\n        salida: %s\n' \
      "$nombre" "$trozo" "$(printf '%s' "$salida" | tr '\n' '|' | cut -c1-200)"
    FALLA=$((FALLA + 1))
  fi
}

# El veredicto NO está (para blindar contra la rama equivocada).
espera_no() {  # <nombre> <trozo_prohibido> <salida>
  local nombre="$1" trozo="$2" salida="$3"
  if printf '%s' "$salida" | grep -qF -- "$trozo"; then
    printf '  FALLA %s\n        NO debía contener: %s\n        salida: %s\n' \
      "$nombre" "$trozo" "$(printf '%s' "$salida" | tr '\n' '|' | cut -c1-200)"
    FALLA=$((FALLA + 1))
  else
    printf '  ok    %s\n' "$nombre"; PASA=$((PASA + 1))
  fi
}

# Silencio: ningún "===" en la parte de SALIDA (antes del marcador de DEGRADADO).
espera_silencio() {  # <nombre> <salida>
  local nombre="$1" salida="$2"
  local s="${salida%%###DEGRADADO###*}"
  if printf '%s' "$s" | grep -q '==='; then
    printf '  FALLA %s\n        esperaba silencio, salida: %s\n' \
      "$nombre" "$(printf '%s' "$s" | tr '\n' '|' | cut -c1-200)"
    FALLA=$((FALLA + 1))
  else
    printf '  ok    %s\n' "$nombre"; PASA=$((PASA + 1))
  fi
}

echo "Banco de pruebas — sección 1d (deriva del CLAUDE.md)"
echo "hook: $HOOK"
echo

# --- 1. iguales: local == canónico HEAD, limpio -> silencio ----------------
construir_canon "$TMP/c1"
printf '%s' "$V3" > "$TMP/l1"
espera_silencio "1  iguales -> no dice nada" "$(correr_1d "$TMP/l1" "$TMP/c1/config/CLAUDE.md")"

# --- 2. local == c1 -> va por detrás (3 commits) ---------------------------
construir_canon "$TMP/c2"
printf '%s' "$V1" > "$TMP/l2"
espera "2  local en c1 -> VA POR DETRÁS" "VA POR DETRÁS DEL CANÓNICO" "$(correr_1d "$TMP/l2" "$TMP/c2/config/CLAUDE.md")"

# --- 3. local == c2 -> va por detrás, 1 commit más ------------------------
construir_canon "$TMP/c3"
printf '%s' "$V2" > "$TMP/l3"
O3=$(correr_1d "$TMP/l3" "$TMP/c3/config/CLAUDE.md")
espera "3a local en c2 -> VA POR DETRÁS"      "VA POR DETRÁS DEL CANÓNICO" "$O3"
espera "3b local en c2 -> lleva 1 commit más" "lleva 1 commit(s) más"       "$O3"

# --- 4. superconjunto estricto, local RECIÉN tocado -> manda el tuyo ------
construir_canon "$TMP/c4"
printf '%s' "$V3"$'\n## Nota local\nSolo en mi máquina.\n' > "$TMP/l4"
touch -d '2099-01-01' "$TMP/l4"
O4=$(correr_1d "$TMP/l4" "$TMP/c4/config/CLAUDE.md")
espera    "4a superconjunto -> VA POR DELANTE"      "VA POR DELANTE DEL CANÓNICO" "$O4"
espera_no "4b superconjunto -> NO dice divergido"   "HAN DIVERGIDO"               "$O4"

# --- 4c. superconjunto estricto, pero local ANTIGUO y canónico recién   ---
#     commiteado. Con el mtime esto caía en "han cambiado los dos" (falso).
construir_canon "$TMP/c4c"
printf '%s' "$V3"$'\n## Nota local\nSolo aquí.\n' > "$TMP/l4c"
touch -d '2000-01-01' "$TMP/l4c"
O4c=$(correr_1d "$TMP/l4c" "$TMP/c4c/config/CLAUDE.md")
espera    "4c superconjunto con local ANTIGUO -> sigue mandando el tuyo" "VA POR DELANTE DEL CANÓNICO" "$O4c"
espera_no "4c NO dice divergido pese al mtime viejo"                     "HAN DIVERGIDO"               "$O4c"

# --- 5. EL CASO DEL 3-SEP: los dos han cambiado, local recién tocado -----
#     canónico avanza con c4 (línea propia); local añade OTRA línea distinta.
construir_canon "$TMP/c5"
printf '%s' "$V3"$'\n## Regla canónica nueva\nDesde otra máquina.\n' > "$TMP/c5/config/CLAUDE.md"
( cd "$TMP/c5" && $GIT add -A && $GIT commit -qm c4 )
printf '%s' "$V3"$'\n## Nota local propia\nSolo mía.\n' > "$TMP/l5"
touch -d '2099-01-01' "$TMP/l5"   # local MÁS NUEVO que el commit c4: el confound del mtime
O5=$(correr_1d "$TMP/l5" "$TMP/c5/config/CLAUDE.md")
espera    "5a los-dos-cambiaron -> HAN DIVERGIDO"           "HAN DIVERGIDO"                "$O5"
espera    "5b los-dos-cambiaron -> manda funde a mano"      "funde a mano"                 "$O5"
espera_no "5c NO recomienda copiar el local encima (bug 3-sep)" "VA POR DELANTE DEL CANÓNICO" "$O5"

# --- 6. local QUITA un bloque que el canónico conserva -> divergido ------
#     cp canónico->local resucitaría lo borrado; cp local->canónico lo
#     borraría de la flota. Tiene que ser funde-a-mano.
construir_canon "$TMP/c6"
printf '%s' "$V3" | sed '/^## Regla tres$/d; /^Texto de la regla tres\.$/d' > "$TMP/l6"
touch -d '2099-01-01' "$TMP/l6"
O6=$(correr_1d "$TMP/l6" "$TMP/c6/config/CLAUDE.md")
espera    "6a local-quita-bloque -> HAN DIVERGIDO"            "HAN DIVERGIDO"               "$O6"
espera_no "6b local-quita-bloque -> NO dice manda el tuyo"    "VA POR DELANTE DEL CANÓNICO" "$O6"

# --- 7. canónico ausente -------------------------------------------------
construir_canon "$TMP/c7"
rm "$TMP/c7/config/CLAUDE.md"
printf '%s' "$V3" > "$TMP/l7"
espera "7  canónico ausente" "NO ENCUENTRO LA COPIA CANÓNICA" "$(correr_1d "$TMP/l7" "$TMP/c7/config/CLAUDE.md")"

# --- 8. local ausente --------------------------------------------------
construir_canon "$TMP/c8"
espera "8  local ausente" "ESTA MÁQUINA NO TIENE CLAUDE.md" "$(correr_1d "$TMP/no-existe-l8" "$TMP/c8/config/CLAUDE.md")"

# --- 9. canónico fuera de git ----------------------------------------
mkdir -p "$TMP/nogit/config"
printf '%s' "$V3" > "$TMP/nogit/config/CLAUDE.md"
printf '%s' "$V3"$'\nlocal distinto\n' > "$TMP/l9"
espera "9  canónico fuera de git -> dirección SIN CONFIRMAR" "SIN CONFIRMAR" "$(correr_1d "$TMP/l9" "$TMP/nogit/config/CLAUDE.md")"

# --- 10. canónico sucio + local por detrás de verdad ---------------
construir_canon "$TMP/c10"
printf '%s' "$V1" > "$TMP/l10"
printf 'edición sin commitear\n' >> "$TMP/c10/config/CLAUDE.md"
O10=$(correr_1d "$TMP/l10" "$TMP/c10/config/CLAUDE.md")
espera "10a sucio+pordetrás -> VA POR DETRÁS" "VA POR DETRÁS DEL CANÓNICO" "$O10"
espera "10b sucio+pordetrás -> avisa del árbol sucio" "SIN COMMITEAR" "$O10"

# --- 11. canónico a medio editar, local == último commit ----------
construir_canon "$TMP/c11"
printf '%s' "$V3" > "$TMP/l11"
printf 'a medio editar\n' >> "$TMP/c11/config/CLAUDE.md"
espera "11 canónico a medio editar, local=HEAD" "A MEDIO EDITAR" "$(correr_1d "$TMP/l11" "$TMP/c11/config/CLAUDE.md")"

# --- 12. clon con commits ya traídos y sin fusionar --------------
$GIT init -q --bare "$TMP/origin.git"
$GIT clone -q "$TMP/origin.git" "$TMP/c12" 2>/dev/null
mkdir -p "$TMP/c12/config"
printf '%s' "$V1" > "$TMP/c12/config/CLAUDE.md"; ( cd "$TMP/c12" && $GIT add -A && $GIT commit -qm c1 )
printf '%s' "$V2" > "$TMP/c12/config/CLAUDE.md"; ( cd "$TMP/c12" && $GIT add -A && $GIT commit -qm c2 )
printf '%s' "$V3" > "$TMP/c12/config/CLAUDE.md"; ( cd "$TMP/c12" && $GIT add -A && $GIT commit -qm c3 && $GIT push -q -u origin main )
printf '%s' "$V3"$'\n## En origin, sin fusionar aquí.\n' > "$TMP/c12/config/CLAUDE.md"
( cd "$TMP/c12" && $GIT add -A && $GIT commit -qm c4 && $GIT push -q origin main && $GIT reset -q --hard HEAD~1 )
printf '%s' "$V3" > "$TMP/l12"   # local == canónico EN DISCO (c3)
espera "12 clon con commits sin fusionar" "NO ES LA ÚLTIMA" "$(correr_1d "$TMP/l12" "$TMP/c12/config/CLAUDE.md")"

# --- 13. canónico sin configurar -> la sección no hace nada -------
espera_silencio "13 CLAUDE_CANONICO vacío -> silencio" "$(correr_1d "$TMP/l1" "")"

# --- 14. sin presupuesto de tiempo -> saltado() -----------------
O14=$(correr_1d "$TMP/l5" "$TMP/c5/config/CLAUDE.md" no)
espera "14a sin presupuesto -> lo dice en DEGRADADO" "sin presupuesto de tiempo" "${O14#*###DEGRADADO###}"
espera_silencio "14b sin presupuesto -> sin veredicto" "$O14"

echo
echo "  $PASA ok, $FALLA falla(s)"
[ "$FALLA" -eq 0 ]
