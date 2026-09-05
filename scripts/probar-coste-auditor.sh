#!/bin/bash
# Bitácora — BANCO DE COSTE del auditor: cuántos procesos lanza POR SESIÓN.
#
# ============================================================================
# POR QUÉ EXISTE ESTE FICHERO
# ============================================================================
#
# El hook de arranque corre scripts/auditar-sesiones.sh con 'timeout 8', y no cabía.
# Medido el 5-sep-2026 en los 9 repos grandes del PC viejo: pasaba de 8 s en CINCO
# (lizar-informes 36 s con la caché fría, lizar-correo 14,7, lizar-flota 14,5,
# kangurea-web 14,4, bitacora-project 8,7).
#
# Y el modo de fallo es el peor de los posibles: cuando 'timeout' lo mata, lo ya escrito
# en stdout SÍ ha salido, así que el hook recibe una auditoría PARCIAL y la trata como
# entera. Medido: lizar-flota, kangurea-web y lizar-informes tenían 2 SIN-ANOTAR cada uno
# en la ejecución completa y CERO en la de 8 s. Seis deudas reales que el arranque no
# enseñaba, sin decir que no las había mirado. Es la forma exacta del fallo que persigue
# este repo, cometida por la pieza que viene a impedirlo.
#
# ============================================================================
# QUÉ SE MIDE, Y POR QUÉ NO SE MIDEN SEGUNDOS
# ============================================================================
#
# Un banco que dijera "el auditor tiene que tardar menos de X segundos" mediría la
# MÁQUINA, no el código: X vale una cosa con la caché caliente y otra con la fría (36 s
# y 13,2 s el mismo repo en dos días), y otra distinta en el PC Nuevo. Un número así se
# pone en verde bajando el umbral, que es justo lo contrario de una prueba.
#
# Lo que se fija aquí es la CAUSA medida, que no depende de la máquina: el coste eran
# PROCESOS POR SESIÓN, no trabajo. Perfilado el 5-sep-2026 en bitacora-project (11,3 s
# en total): pasada 1 = 3,67 s, pasada 2 = 5,85 s, y todo lo demás 1,7 s. Esas dos
# pasadas lanzaban CINCO procesos por sesión -- dos 'date -d' en la primera, y en la
# segunda un 'date -d' más dos 'date -u -d' más un 'git log | wc -l'. Medido aquí:
# 'date -d' cuesta 90 ms y 'git log | wc -l' 219, o sea ~0,7 s por sesión. Con 14
# sesiones son ~10 s de los 11,3. El trabajo de verdad -- el awk sobre los 53 MB de las
# carpetas ancestro -- tarda 0,42 s.
#
# Así que la prueba es de FORMA y no de reloj: se corre el auditor sobre 3 sesiones y
# sobre 15, contando cuántas veces invoca 'date' y 'git', y se exige que el número NO
# CREZCA. Es determinista, da la misma respuesta en las dos máquinas, y hoy falla por
# unas sesenta llamadas de diferencia.
#
# ============================================================================
# Y LA MITAD DE ARRIBA NO VALE SIN LA DE ABAJO
# ============================================================================
#
# Acelerar aquí significa convertir fechas en otro sitio, y eso puede cambiar los
# VEREDICTOS sin que nadie se entere. El riesgo es concreto y no teórico: 'mktime' de
# awk interpreta en HORA LOCAL salvo que se le pase el flag UTC, y en esta máquina eso
# son dos horas de deriva sobre la ventana de 14 días que decide si una sesión es deuda.
# Una sesión pasaría de juzgada a invisible sin una sola línea de aviso.
#
# Por eso los casos 1-7 clavan el juicio contra un fixture de respuestas conocidas, e
# incluyen A PROPÓSITO una sesión a UNA HORA del borde de la ventana: cualquier deriva
# de dos horas la tira fuera y el banco lo canta. Y el caso 3 compara la fecha impresa
# con la que da 'date' de verdad, que es la otra mitad del mismo error.
#
# Se ejecuta a mano:  bash scripts/probar-coste-auditor.sh
# Usa git (crea un repo de mentira en un temporal) y no toca nada del usuario: ni sus
# repos, ni ~/.claude, ni la red.

set -uo pipefail

AQUI="$(cd "$(dirname "$0")" && pwd)"
AUDITOR="${1:-$AQUI/auditar-sesiones.sh}"
[ -f "$AUDITOR" ] || { echo "no encuentro el auditor: $AUDITOR" >&2; exit 2; }

# Las rutas REALES se capturan antes de envenenar el PATH: los contadores de más abajo
# se llaman 'date' y 'git', así que sin esto se llamarían a sí mismos para siempre.
REAL_DATE=$(command -v date) || { echo "no encuentro 'date'" >&2; exit 2; }
REAL_GIT=$(command -v git)  || { echo "no encuentro 'git'" >&2; exit 2; }

TMP=$(mktemp -d 2>/dev/null) || { echo "mktemp -d falló" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

# --- Los contadores ---------------------------------------------------------
# Un envoltorio por orden: apunta la llamada y cede el sitio al binario de verdad. No
# altera ni argumentos ni salida ni código de retorno, así que el auditor corre igual
# que siempre; lo único que cambia es que queda constancia de cada invocación.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/date" <<'STUB'
#!/bin/bash
printf 'date\n' >> "$CONTADOR"
exec "$REAL_DATE_BIN" "$@"
STUB
cat > "$TMP/bin/git" <<'STUB'
#!/bin/bash
printf 'git\n' >> "$CONTADOR"
exec "$REAL_GIT_BIN" "$@"
STUB
chmod +x "$TMP/bin/date" "$TMP/bin/git"

# --- El repo de mentira -----------------------------------------------------
REPO="$TMP/repo"
mkdir -p "$REPO"
"$REAL_GIT" -C "$REPO" init -q 2>/dev/null || { echo "git init falló" >&2; exit 2; }
"$REAL_GIT" -C "$REPO" config user.name  "banco"
"$REAL_GIT" -C "$REPO" config user.email "banco@ejemplo.invalido"

commitar() {  # commitar <epoch> <texto>
  printf '%s\n' "$2" >> "$REPO/BITACORA.md"
  "$REAL_GIT" -C "$REPO" add -A
  GIT_AUTHOR_DATE="@$1 +0000" GIT_COMMITTER_DATE="@$1 +0000" \
    "$REAL_GIT" -C "$REPO" commit -q -m "$2"
}

# La misma transformación que usa Claude Code para nombrar la carpeta de proyecto. Aquí
# SOLO sirve para construir el fixture: lo que se prueba es el coste y el veredicto, no
# cómo se escribe un nombre -- de eso ya responde probar-atribucion-transcripts.sh.
patron_de() { printf '%s' "$1" | sed 's#[:/\\ .]#-#g'; }
RUTA_WIN=$( (cd "$REPO" && pwd -W 2>/dev/null) || printf '%s' "$REPO" )
PATRON=$(patron_de "$RUTA_WIN")

# sesion <dir-proyectos> <sid> <turnos> <fin-epoch> <duracion-seg>
#
# Un .jsonl con la única forma que la pasada 1 del auditor mira: una línea de asistente
# por turno, cada una con su marca de tiempo. Se generan TODAS de una vez con un awk, y
# no con un 'date' por turno, porque el fixture de 15 sesiones costaría 180 procesos y
# tardaría más que lo que viene a medir.
#
# El mtime se pone en el fin de la sesión porque el auditor descarta por mtime antes de
# leer nada ('find -newermt'): un fichero recién creado con marcas de hace veinte días
# pasaría ese filtro y no probaría el caso de fuera de ventana.
sesion() {
  local proy="$1" sid="$2" turnos="$3" fin="$4" dur="$5" dir f
  dir="$proy/$PATRON"
  mkdir -p "$dir"
  f="$dir/$sid.jsonl"
  awk -v n="$turnos" -v fin="$fin" -v dur="$dur" -v cwd="$RUTA_WIN" 'BEGIN {
    q = sprintf("%c", 34)
    for (i = 0; i < n; i++) {
      e = fin - dur + (n > 1 ? int(dur * i / (n - 1)) : 0)
      printf "{%stype%s:%sassistant%s,%scwd%s:%s%s%s,%stimestamp%s:%s%s.000Z%s}\n", \
        q,q,q,q, q,q,q,cwd,q, q,q,q, strftime("%Y-%m-%dT%H:%M:%S", e, 1), q
    }
  }' > "$f"
  touch -d "@$fin" "$f" 2>/dev/null
}

# correr <dir-proyectos> <fichero-contador> -> salida del auditor
#
# BITACORA_CONF apunta a un fichero que no existe A PROPÓSITO: el auditor SOURCEA la
# conf antes de leer el entorno, así que con la conf de verdad delante las variables de
# aquí abajo no mandarían y el banco estaría midiendo los transcripts del usuario.
correr() {
  : > "$2"
  PATH="$TMP/bin:$PATH" \
  CONTADOR="$2" REAL_DATE_BIN="$REAL_DATE" REAL_GIT_BIN="$REAL_GIT" \
  BITACORA_CONF="$TMP/esta-conf-no-existe" \
  BITACORA_PROYECTOS="$1" \
  BITACORA_REGISTRO_SESIONES="$TMP/este-registro-no-existe" \
    bash "$AUDITOR" "$REPO" 2>/dev/null
}

cuenta() {  # cuenta <fichero-contador> <orden>
  grep -c "^$2\$" "$1" 2>/dev/null || printf '0'
}

PASA=0; FALLA=0
resumen_de() { printf '%s' "$1" | tr '\n' '|' | cut -c1-260; }

espera() {  # <nombre> <trozo> <salida>
  if printf '%s' "$3" | grep -qF -- "$2"; then
    printf '  ok    %s\n' "$1"; PASA=$((PASA + 1))
  else
    printf '  FALLA %s\n        esperaba contener: %s\n        salida: %s\n' \
      "$1" "$2" "$(resumen_de "$3")"
    FALLA=$((FALLA + 1))
  fi
}

espera_no() {  # <nombre> <trozo-prohibido> <salida>
  if printf '%s' "$3" | grep -qF -- "$2"; then
    printf '  FALLA %s\n        NO debía contener: %s\n        salida: %s\n' \
      "$1" "$2" "$(resumen_de "$3")"
    FALLA=$((FALLA + 1))
  else
    printf '  ok    %s\n' "$1"; PASA=$((PASA + 1))
  fi
}

echo "Banco de coste — auditar-sesiones.sh"
echo "auditor: $AUDITOR"
echo

# =========================================================================
# EL JUICIO, CONTRA RESPUESTAS CONOCIDAS
# =========================================================================
# Estos casos ya pasan hoy: no describen un arreglo, describen lo que el auditor tiene
# que seguir diciendo DESPUÉS de acelerarlo. Sin ellos, cambiar dónde se convierten las
# fechas puede mover un veredicto y el banco de coste se pondría verde igual.
AHORA=$("$REAL_DATE" +%s)
DIA=86400

# El commit fundacional se fecha VIEJO para que no caiga dentro de la ventana de ninguna
# sesión: si cayera, todas saldrían ANOTADAS y los casos de deuda no probarían nada.
commitar $(( AHORA - 20 * DIA )) "arranque"

PJ="$TMP/proyectos-juicio"

# Anotada: hay un commit que toca la bitácora dentro de su ventana.
FIN_A=$(( AHORA - 3 * DIA ))
sesion "$PJ" "aaaa1111-anotada" 20 "$FIN_A" 3600
commitar $(( FIN_A - 600 )) "entrada de la sesion A"

# Deuda: ningún commit cerca.
FIN_B=$(( AHORA - 5 * DIA ))
sesion "$PJ" "bbbb2222-sin-anotar" 20 "$FIN_B" 3600

# Por debajo del suelo de turnos: no se juzga, se cuenta como corta.
sesion "$PJ" "cccc3333-corta" 5 $(( AHORA - 6 * DIA )) 600

# A UNA HORA DE DENTRO DEL BORDE. Es el caso que caza la deriva de zona horaria: si las
# marcas del transcript se interpretan en hora local en vez de en UTC, el fin de esta
# sesión se calcula dos horas antes de lo que es, cae fuera de la ventana de 14 días y
# desaparece sin decir nada. Una hora de margen es a propósito: con tres, la deriva
# cabría dentro y el banco daría verde.
FIN_E=$(( AHORA - 14 * DIA + 3600 ))
sesion "$PJ" "eeee5555-al-borde" 20 "$FIN_E" 1800

# Y a una hora de fuera: tiene que no aparecer.
sesion "$PJ" "dddd4444-pasada" 20 $(( AHORA - 14 * DIA - 3600 )) 1800

OJ=$(correr "$PJ" "$TMP/cont-juicio")

espera    "1  la sesión con commit en su ventana sale ANOTADA" "aaaa1111-anotada" "$OJ"
espera    "2  y la que no lo tiene sale SIN-ANOTAR"            "bbbb2222-sin-anotar" "$OJ"

# La fecha impresa es LOCAL y se compara con la que da 'date' de verdad. Es la otra mitad
# del error de zona horaria: la ventana puede estar bien y la fecha que se le enseña al
# usuario salir dos horas movida, que es una deuda que no cuadra con lo que él recuerda.
espera    "3  la fecha impresa coincide con la de 'date'" \
  "$("$REAL_DATE" -d "@$FIN_A" '+%Y-%m-%d %H:%M')" "$OJ"

espera_no "4  la sesión por debajo del suelo no se juzga"     "cccc3333-corta" "$OJ"
espera    "5  y se cuenta como corta"                         "1 cortas" "$OJ"
espera    "6  la sesión a una hora del borde SÍ se juzga"     "eeee5555-al-borde" "$OJ"
espera_no "7  la de una hora más allá del borde, no"          "dddd4444-pasada" "$OJ"

# El hook saca la ruta del transcript del bloque PENDIENTES con un sed. Si el bloque
# cambia de forma, el hook deja de encontrar el borrador y no lo dice: se queda sin
# borrador y culpa al script de borradores.
RUTAS=$(printf '%s\n' "$OJ" | sed -n 's/^  - .* — \(.*\.jsonl\)$/\1/p')
espera    "8  PENDIENTES trae la ruta del transcript, como la lee el hook" \
  "bbbb2222-sin-anotar.jsonl" "$RUTAS"

# =========================================================================
# EL COSTE: ni un proceso por sesión
# =========================================================================
# Se comparan dos fixtures idénticos salvo en el número de sesiones. Todas tienen que
# JUZGARSE de verdad: pasan el suelo de turnos, son viejas de sobra para no estar "en
# curso", y van separadas doce horas -- lo bastante para que ninguna sea CADENA ni
# REANUDADA de otra (saldrían por 'continue' antes del git log, y entonces el contador
# mediría de menos), y lo bastante poco para que las quince quepan dentro de la ventana
# de 14 días. Con un día de separación las dos últimas se salían y el caso 9 lo cazó.
fixture_coste() {  # fixture_coste <dir> <n-sesiones>
  local dir="$1" n="$2" i=0
  while [ "$i" -lt "$n" ]; do
    sesion "$dir" "$(printf 'f%04d-coste' "$i")" 15 $(( AHORA - (i + 1) * (DIA / 2) - 3600 )) 1800
    i=$((i + 1))
  done
}

P3="$TMP/proyectos-3";  fixture_coste "$P3" 3
P15="$TMP/proyectos-15"; fixture_coste "$P15" 15

O3=$(correr "$P3"  "$TMP/cont-3")
O15=$(correr "$P15" "$TMP/cont-15")

D3=$(cuenta "$TMP/cont-3" date);  D15=$(cuenta "$TMP/cont-15" date)
G3=$(cuenta "$TMP/cont-3" git);   G15=$(cuenta "$TMP/cont-15" git)

# Comprobación de la comprobación: si los dos fixtures no juzgaron 3 y 15 sesiones, los
# contadores no significan nada y el caso podría salir verde por vacío.
N3=$(printf '%s\n' "$O3"  | grep -c '^SIN-ANOTAR ' || true)
N15=$(printf '%s\n' "$O15" | grep -c '^SIN-ANOTAR ' || true)
if [ "$N3" = "3" ] && [ "$N15" = "15" ]; then
  printf '  ok    %s\n' "9  los dos fixtures juzgaron lo que debían (3 y 15)"; PASA=$((PASA + 1))
else
  printf '  FALLA %s\n        juzgadas: %s y %s (esperaba 3 y 15)\n' \
    "9  los dos fixtures juzgaron lo que debían (3 y 15)" "$N3" "$N15"
  FALLA=$((FALLA + 1))
fi

if [ "$D15" -le "$D3" ]; then
  printf '  ok    %s (%s con 3 sesiones, %s con 15)\n' \
    "10 'date' no crece con el número de sesiones" "$D3" "$D15"; PASA=$((PASA + 1))
else
  printf '  FALLA %s\n        %s llamadas con 3 sesiones y %s con 15: %s por sesión.\n' \
    "10 'date' no crece con el número de sesiones" "$D3" "$D15" \
    "$(( (D15 - D3) / 12 ))"
  FALLA=$((FALLA + 1))
fi

if [ "$G15" -le "$G3" ]; then
  printf '  ok    %s (%s con 3 sesiones, %s con 15)\n' \
    "11 'git' no crece con el número de sesiones" "$G3" "$G15"; PASA=$((PASA + 1))
else
  printf '  FALLA %s\n        %s llamadas con 3 sesiones y %s con 15: %s por sesión.\n' \
    "11 'git' no crece con el número de sesiones" "$G3" "$G15" \
    "$(( (G15 - G3) / 12 ))"
  FALLA=$((FALLA + 1))
fi

# =========================================================================
# LA MARCA DE FIN: distinguir una salida entera de una cortada a medias
# =========================================================================
# El hook corre el auditor con 'timeout 8'. Cuando lo mata, lo ya escrito en stdout SÍ
# salió, así que sin una marca de cierre una auditoría A MEDIAS es indistinguible de una
# completa: las dos son texto con veredictos dentro. Acelerar el auditor bajó eso de vivo
# a latente (3,1 s contra 8), pero latente no es imposible, y el día que vuelva a pasar el
# arranque volvería a enseñar media deuda con cara de deuda entera.
MARCA='--- fin de la auditoría (salida completa) ---'

ULTIMA=$(printf '%s\n' "$OJ" | tail -1)
if [ "$ULTIMA" = "$MARCA" ]; then
  printf '  ok    %s\n' "12 la salida completa termina con la marca de fin"; PASA=$((PASA + 1))
else
  printf '  FALLA %s\n        última línea: %s\n' \
    "12 la salida completa termina con la marca de fin" "$ULTIMA"
  FALLA=$((FALLA + 1))
fi

# Por TODAS las puertas, no solo por la principal. El auditor sale antes de tiempo en
# varios sitios legítimos -- no es un repo git, no hay bitácora, no hay transcripts -- y
# una de esas salidas sin marca haría que el hook cantara "truncada" cuando no lo está:
# ruido en la pieza que existe para que se lea el aviso de verdad.
SIN_TRANSCRIPTS=$(correr "$TMP/proyectos-vacios" "$TMP/cont-vacio")
espera "13 la salida corta (sin transcripts) también la lleva" "$MARCA" \
  "$(printf '%s\n' "$SIN_TRANSCRIPTS" | tail -1)"

NO_REPO=$( BITACORA_CONF="$TMP/esta-conf-no-existe" bash "$AUDITOR" "$TMP/bin" 2>/dev/null )
espera "14 y la de 'esto no es un repo git', igual" "$MARCA" \
  "$(printf '%s\n' "$NO_REPO" | tail -1)"

# LOS TRES QUE LEEN AL AUDITOR TIENEN QUE CONOCERLA. Es el mismo argumento del caso 16 del
# banco de atribución: el auditor puede decir algo nuevo y los que le leen seguir sin
# enterarse. Aquí duele por partida doble -- el hook tiene que EXIGIRLA para detectar el
# truncamiento, y el sueño tiene que QUITARLA para que no se le cuele como una pendiente.
RAIZ_REPO=$(cd "$AQUI/.." && pwd)
faltan=""
for pieza in scripts/auditar-sesiones.sh hooks/sessionstart-leer.sh scripts/sueno.sh; do
  grep -qF -- "$MARCA" "$RAIZ_REPO/$pieza" 2>/dev/null || faltan="$faltan $pieza"
done
if [ -z "$faltan" ]; then
  printf '  ok    %s\n' "15 los 3 que leen al auditor conocen la marca de fin"; PASA=$((PASA + 1))
else
  printf '  FALLA %s\n        no la conocen:%s\n' \
    "15 los 3 que leen al auditor conocen la marca de fin" "$faltan"
  FALLA=$((FALLA + 1))
fi

echo
echo "  $PASA ok, $FALLA falla(s)"
[ "$FALLA" -eq 0 ]
