#!/bin/bash
# Bitácora — AUDITOR: ¿qué sesiones de este repo terminaron sin anotar?
#
# Es la pieza que faltaba, y no escribe nada: solo mira y dice. Hasta hoy nadie —ni el
# sistema ni nosotros— podía responder a "¿esta sesión anotó?" sin un bucle a mano. Se
# comprobó a mano el 1-sep-2026 y salió 15 de 16; el punto es que el sistema no lo sabía.
#
# POR QUÉ EL AUDITOR NO ES QUIEN ESCRIBE. Es la lección nº4 del proyecto, literal: el hook
# que moría por timeout escribía su propia línea de éxito 22 segundos después de estar
# muerto, así que los números cuadraban y no llegaba nada. Aquí la consecuencia es
# concreta: este script NO lee ninguna marca de "hecho" dejada por el hook de cierre.
# Lee el ARTEFACTO — el commit que toca la BITACORA.md — y el transcript del disco. Si
# `sessionend-anotar.sh` no llegó a correr (la X, un kill, la luz), la deuda se
# reconstruye igual. El registro de cierre solo ENRIQUECE (aporta el motivo del cierre);
# nunca es la fuente de verdad.
#
# QUÉ CUENTA COMO "ANOTADA". Existe un commit que toca el fichero de bitácora del repo
# dentro de la ventana de la sesión. Ni "el hook corrió", ni "el agente dijo que anotó" —
# esa distinción es justo la que casi me como el 1-sep: di por perdida una sesión de
# 4.112 turnos que SÍ había anotado, por mirar el mtime del .jsonl en vez de los commits.
#
# TRES ESTADOS, NUNCA COLAPSADOS. ANOTADA / SIN-ANOTAR / NO-SE-PUDO-COMPROBAR. El tercero
# grita más que el segundo: "no lo sé" y "no hay nada" se han leído igual demasiadas
# veces en este proyecto, y esa confusión es la forma de los cuatro fallos silenciosos.
#
# Uso:
#   auditar-sesiones.sh [ruta-del-repo] [session-id-a-excluir]
#
# Salida: una línea por sesión juzgada, más un resumen. Código de salida siempre 0 —
# es un informe, no una comprobación que deba tumbar nada.
set -uo pipefail

# ---------- La marca de que esta salida está ENTERA ----------
# El hook de arranque corre este script con 'timeout 8'. Cuando lo mata, lo ya escrito en
# stdout SÍ ha salido, así que quien lo lee recibe una auditoría A MEDIAS y no tiene forma
# de distinguirla de una completa: los dos casos son texto con veredictos dentro. Medido el
# 5-sep-2026, antes de acelerar el script: lizar-informes cantaba 2 SIN-ANOTAR enteros y
# CERO bajo el timeout, sin una sola línea que dijera que faltaba algo.
#
# La marca la imprime la ÚLTIMA línea de todas y por todas las salidas, así que si no está,
# es que este script no llegó al final. Se emite explícitamente en cada 'fin' y NO con un
# 'trap EXIT' a propósito: un trap también se dispara cuando a uno lo matan, o sea que
# firmaría como completa justo la salida truncada que viene a delatar.
MARCA_FIN="--- fin de la auditoría (salida completa) ---"
fin() { echo "$MARCA_FIN"; exit 0; }

CONF="${BITACORA_CONF:-$HOME/.claude/bitacora.conf}"
# shellcheck disable=SC1090
[ -f "$CONF" ] && . "$CONF"

FICHERO="${BITACORA_FICHERO:-BITACORA.md}"
PROYECTOS="${BITACORA_PROYECTOS:-$HOME/.claude/projects}"
REGISTRO="${BITACORA_REGISTRO_SESIONES:-$HOME/.claude/bitacora-sesiones}"

# Suelo de ruido: por debajo de esto no hay nada que anotar y avisar sería peor que
# callar. No es un número redondo por gusto -- medido el 1-sep: la sesión más corta que
# SÍ produjo entrada tenía 9 turnos, y la única sin entrada de la semana tenía 0.
UMBRAL_TURNOS="${BITACORA_AUDITORIA_UMBRAL_TURNOS:-10}"

# Cuánto hacia atrás se mira. Más allá, la deuda ya no es accionable: el transcript sigue
# ahí pero nadie va a reconstruir una sesión de hace un mes.
DIAS="${BITACORA_AUDITORIA_DIAS:-14}"

# Una sesión cuyo último apunte es de hace menos de esto puede estar VIVA en otra ventana.
# Juzgarla sería acusarla de no haber hecho algo que todavía puede hacer.
RECIENTE_MIN="${BITACORA_AUDITORIA_RECIENTE_MIN:-30}"

# Ventana hacia atrás desde el FIN de la sesión donde se busca el commit de bitácora.
# No se usa la sesión entera a propósito: una sesión de varios días (las hay: una de
# 26-ago a 31-ago) daría por suya cualquier anotación de otra sesión intermedia, y eso
# INFRAVALORA la deuda -- que es la dirección silenciosa, justo la que este proyecto
# persigue. Con la ventana atada al cierre, el error posible es sobrar deuda: ruidoso,
# pero visible y corregible.
VENTANA_H="${BITACORA_AUDITORIA_VENTANA_HORAS:-6}"

REPO="${1:-$PWD}"
EXCLUIR="${2:-}"

# ---------- Localizar el repo y su bitácora ----------
if ! RAIZ=$(git -C "$REPO" rev-parse --show-toplevel 2>/dev/null); then
  echo "NO-APLICA: $REPO no está dentro de una copia de trabajo de git."
  fin
fi
# El estilo de ruta que devuelve git ('C:/Users/...') no es el de $PWD ('/c/Users/...').
# Compararlas como texto nunca da igual aunque sean la misma carpeta: ya costó un bug en
# la sección 1b del hook de arranque (NOTAS-DE-CAMPO, 22-ago). Se normaliza aquí.
RAIZ=$(cd "$RAIZ" && pwd)
BITACORA="$RAIZ/$FICHERO"

if [ ! -f "$BITACORA" ]; then
  echo "NO-APLICA: $RAIZ no tiene $FICHERO. No hay dónde anotar."
  fin
fi

# ---------- Lo que este script le pide a awk, comprobado y no supuesto ----------
# Desde el 5-sep-2026 las fechas se convierten DENTRO de awk en vez de llamando a 'date'
# una vez por sesión. Eso es lo que hace que este script quepa en el 'timeout 8' del hook
# de arranque (ver la cabecera de la pasada 1), pero mete una dependencia nueva: mktime()
# y strftime(), que son de gawk, y el FLAG UTC de mktime, que es de gawk 4.2 en adelante.
#
# SE COMPRUEBA PORQUE LOS DOS MODOS DE FALLO SON MUDOS. Un awk sin mktime aborta el
# programa entero, así que la pasada 1 devolvería CERO líneas -- y ahí abajo eso se lee
# exactamente igual que "no hay sesiones que juzgar". Y un awk que aceptara el flag y lo
# IGNORARA daría epochs corridos las horas del huso (dos en esta máquina), lo bastante
# para sacar de la ventana de 14 días sesiones que están dentro. Ninguno de los dos se
# vería: son la forma de fallo que persigue este repo.
#
# Por eso la prueba compara contra un número CONCRETO y no se conforma con que la función
# exista: 2026-01-02T03:04:05Z son 1767323045 segundos, y un awk que interprete esa fecha
# en hora local da otro. Cuesta un proceso (~80 ms) UNA vez, no uno por sesión, y cambia
# un fallo mudo por el tercer estado.
if ! awk 'BEGIN { exit !(mktime("2026 01 02 03 04 05", 1) == 1767323045 && strftime("%Y", 0, 1) == "1970") }' 2>/dev/null; then
  echo "NO-SE-PUDO-COMPROBAR: el 'awk' de esta máquina no convierte fechas como hace falta."
  echo "  Hacen falta mktime() y strftime() con el flag UTC (gawk 4.2 o posterior)."
  echo "  Sin eso las fechas saldrían corridas y la deuda se calcularía mal EN SILENCIO."
  echo "  Prefiero no decir nada a decir algo falso: esto no es 'no hay deuda'."
  fin
fi

# ---------- Localizar los transcripts de este repo ----------
# Claude Code nombra la carpeta de proyecto transformando la ruta: 'C:\Users\Oscar\repos\x'
# -> 'C--Users-Oscar-repos-x'.
#
# QUÉ CARACTERES SE TRADUCEN, Y CÓMO SE SUPO. No se deduce del nombre: cada transcript
# lleva dentro el 'cwd' que lo generó, así que la correspondencia (carpeta, ruta real) se
# LEE. Medido el 5-sep-2026 sobre las 23 carpetas de esta máquina:
#
#   C:\Users\Oscar\LIZAR AEO                       -> C--Users-Oscar-LIZAR-AEO
#   C:\Users\Oscar\repos\CSV Generator             -> C--Users-Oscar-repos-CSV-Generator
#   C:\Users\Oscar\repos\z-api Whatsapp            -> C--Users-Oscar-repos-z-api-Whatsapp
#   C:\Users\Oscar\Desktop\Kangurea MATERIAL WEB   -> c--Users-...-Kangurea-MATERIAL-WEB
#   ...\agentes-lizar\.claude\worktrees\clever-... -> ...-agentes-lizar--claude-worktrees-clever-...
#
# O sea: el ESPACIO y el PUNTO también van a '-'. Hasta hoy solo se traducían ':', '/' y
# '\', y eso dejaba '~/repos/CSV Generator' entero invisible -- un repo de 44, siempre
# NO-SE-PUDO-COMPROBAR. El punto además explica el doble guion de los worktrees: no es un
# nombre especial, es '\' + '.'; sin traducirlo, auditar DESDE dentro de un worktree
# calculaba un patrón con un '.' que ninguna carpeta tiene.
#
# NO se generaliza a "todo lo no alfanumérico". De '_', '(' y '[' no hay ni un par
# observado, y ampliar el sed a ojo arriesga los 43 repos que hoy sí casan a cambio de un
# caso imaginario: sería cambiar un fallo ruidoso (NO-SE-PUDO-COMPROBAR, que se ve) por
# uno silencioso. Si algún día aparece uno, se mide igual que éstos y se añade aquí.
#
# SOLO SE ACEPTA LO QUE SE RECONOCE. Hasta el 5-sep-2026 esto casaba por prefijo abierto
# ('$patron' y '$patron'-*), y el comentario que lo justificaba hablaba de sesiones
# abiertas en una SUBCARPETA del repo, "el caso monorepo de agentes-lizar". Ese caso NO
# EXISTE: medido el 5-sep en el PC viejo, cero carpetas de transcripts son subcarpeta
# real de un repo. La frase venía de este mismo comentario y se copió a una entrada de
# bitácora como si fuera un dato -- exactamente lo que persigue la regla "verificar antes
# de afirmar", cometido dentro del fichero que predica mirar el artefacto.
#
# Lo que el prefijo abierto SÍ hacía era llevarse las sesiones de OTRO repo cuando un
# nombre es prefijo de otro: preguntado por '~/repos/bitacora' devolvía también las de
# 'bitacora-flota' y 'bitacora-project', las juzgaba contra la BITACORA.md equivocada y
# cantaba deuda falsa. Medido: 7 sesiones en la primera ejecución de sueno.sh el 4-sep, y
# un solo repo afectado de 44 (bitacora) al comparar todos los nombres de ~/repos.
#
# Lo que sí hay que seguir cubriendo son los WORKTREES de Claude, con nombre propio y
# doble guion: '$patron--claude-worktrees-*'. Un worktree es el mismo repo y la misma
# bitácora, así que atribuirle sus sesiones al repo principal es correcto. En el PC viejo
# son 4 carpetas (agentes-lizar x2, kangurea-web, lizar-informes).
#
# SE ELIGE ESTA REGLA Y NO "RECHAZAR EL SUFIJO QUE SEA OTRO REPO" porque no depende de
# qué repos existan en la máquina: da la misma respuesta en las dos, no hay que pasarle
# al auditor una lista de repos que ahora no tiene, y no se rompe cuando el repo hermano
# está clonado en un PC y en el otro no -- que es justo el caso en el que la alternativa
# volvería a absorber sesiones ajenas sin avisar.
#
# Y LO QUE SE DESCARTA SE DICE (ver más abajo). Es la única objeción seria a estrechar
# aquí: si alguna máquina tuviera sesiones en una subcarpeta, quedarían fuera EN
# SILENCIO, que es la dirección que este proyecto persigue. No quedan: se nombran.
#
# La transformación vive en UNA función y no repetida, porque aquí ya se usa dos veces:
# para el patrón de este repo y para el de cada carpeta ancestro (más abajo). Dos copias
# en el mismo fichero se separan igual de bien que dos copias en ficheros distintos.
patron_de() { printf '%s' "$1" | sed 's#[:/\\ .]#-#g'; }

ruta_win=$(cd "$RAIZ" && pwd -W 2>/dev/null || echo "$RAIZ")
patron=$(patron_de "$ruta_win")

# Array y no cadena: 'dirs' acaba en un 'for' sin comillas, y una ruta con espacio
# —'~/repos/CSV Generator' existe— se partiría en dos rutas rotas.
dirs=()
for d in "$PROYECTOS/$patron" "$PROYECTOS/$patron"--claude-worktrees-*; do
  [ -d "$d" ] && dirs+=("$d")
done

# Lo que casa por prefijo y no se reconoce. No se usa, pero tampoco se calla.
ajenas=()
for d in "$PROYECTOS/$patron"-*; do
  [ -d "$d" ] || continue
  case "${d##*/}" in "$patron"--claude-worktrees-*) continue ;; esac
  ajenas+=("${d##*/}")
done
if [ "${#ajenas[@]}" -gt 0 ]; then
  echo "NOTA: descarto ${#ajenas[@]} carpeta(s) que empiezan por el patrón de este repo pero no son suyas:"
  printf '  %s\n' "${ajenas[@]}"
  echo "  Se reconocen la coincidencia exacta y los worktrees ('$patron--claude-worktrees-*')."
  echo "  Si alguna de éstas fuera de verdad este repo, sus sesiones NO se están juzgando."
fi

# ---------- Las sesiones que NO pertenecen a un solo repo ----------
# Medido el 5-sep-2026 en el PC viejo: las carpetas 'C--' y 'C--Users-Oscar' -- las de las
# sesiones abiertas en la raíz del disco o en el home -- guardan 7 sesiones que trabajaron
# dentro de repos con bitácora, y eran INVISIBLES aquí y en el sueño. No las alcanza
# ningún arreglo de la transformación: el nombre de su carpeta es CORRECTO, la sesión
# empezó ahí. Lo que rompen es el modelo de raíz, que era "un transcript, un repo".
#
# SE DECLARAN, NO SE REPARTEN. La razón no es de gusto: el auditor NO PUEDE saber. Su
# prueba de ANOTADA es "hay un commit que toca ESTA bitácora en la ventana", y eso no
# distingue "anotó donde tocaba" de "no anotó". Una sesión que recorrió seis repos y dejó
# UNA entrada correcta saldría ANOTADA en uno y SIN-ANOTAR en los otros cinco: deuda falsa
# a razón de cinco por sesión. Y la deuda falsa se deja de leer -- momento en el cual la
# deuda de verdad también es silenciosa. Es el fallo de siempre, alcanzado por el lado
# ruidoso. "No lo sé" es aquí la respuesta VERDADERA, no la cómoda; para eso está el
# tercer estado.
#
# LOS NÚMEROS LO REMATAN. En las 7, la mayoría de los turnos no está en ningún repo: 268
# de 328, 88 de 264, 99 de 194, 49 de 59. Las colas por repo son minúsculas -- la sesión
# de 230 turnos pisó 'lizar-asistente-aula' UN turno y 'AlcoholTax-IA' dos. Repartir
# cobraría a seis bitácoras una entrada por eso.
#
# Y son, por construcción, las sesiones que incumplen "un chat por repo" del CLAUDE.md.
# El remedio de una sesión que tocó seis repos no son seis entradas: es no haberla tenido
# así. Un auditor que exigiera las seis convertiría el incumplimiento en rutina.
#
# DÓNDE SE BUSCAN, Y POR QUÉ SOLO AHÍ. En las carpetas ANCESTRO: las de los directorios
# que CONTIENEN a este repo ('C--Users-Oscar-repos', 'C--Users-Oscar', 'C--'). Es una
# prueba léxica sobre la misma ruta, no necesita la lista de repos de la máquina -- que
# aquí no hay-- y da la misma respuesta en las dos. No se barren TODAS las carpetas de
# proyecto a propósito: existe el mismo fenómeno en carpetas normales (medido: una sesión
# de 142 turnos de 'lizar-flota' pasó 29 turnos en 'bitacora-flota'), pero cubrirlo obliga
# a leer los transcripts de las 24 carpetas en CADA arranque, con 25 s de presupuesto y
# 45 de plazo duro. Así se reconstruye la avería del 28-ago. Ese caso necesita su propia
# decisión; queda dicho aquí y no fingido.
#
# EL UMBRAL PARA NOMBRARLAS ES EL QUE YA HAY. UMBRAL_TURNOS significa "por debajo de esto
# no hay nada que anotar", que es exactamente la pregunta, y está calibrado. Inventar aquí
# un número nuevo sería elegirlo a ojo.
#
# EL PATRÓN DEL ANCESTRO NO SE CALCULA: SE RECORTA. La transformación cambia un carácter
# por otro, así que CONSERVA LA LONGITUD, y el patrón de un directorio que contiene a
# éste es exactamente el prefijo de '$patron' con tantos caracteres como tiene su ruta.
# 'C:/Users/Oscar/repos' son 20 -> 'C--Users-Oscar-repos'. 'C:/' son 3 -> 'C--'.
#
# No es un atajo: es la forma de que aquí NO haya una segunda traducción que pueda
# separarse de la primera -- el fallo que vigila el caso 11 del banco, evitado por
# construcción en vez de por vigilancia.
#
# Y de paso quita ocho procesos. Medido en esta máquina el 5-sep-2026, un 'printf | sed'
# dentro de una sustitución de órdenes cuesta ~610 ms en Git Bash; las ocho llamadas que
# tenía la primera versión de este bucle costaban 5,5 s ELLAS SOLAS, en un script al que
# el hook de arranque le da 8 segundos entre todo. Este bucle ya no lanza ni uno.
ancestros=()
resto="$ruta_win"
while [ -n "$resto" ]; do
  padre=${resto%[/\\]*}
  [ "$padre" = "$resto" ] && break            # ya no queda separador que quitar
  [ -n "$padre" ] || padre="/"                # '/home' -> la raíz de un Unix
  raiz_alcanzada=no
  case "$padre" in
    ?:) padre="$padre/"; raiz_alcanzada=si ;; # 'C:' no es una ruta; 'C:/' sí, y da 'C--'
    /)  raiz_alcanzada=si ;;
  esac
  p=${patron:0:${#padre}}
  [ -d "$PROYECTOS/$p" ] && ancestros+=("$PROYECTOS/$p")
  [ "$raiz_alcanzada" = si ] && break
  resto="$padre"
done

n_sueltas=0
sueltas=""
if [ "${#ancestros[@]}" -gt 0 ]; then
  # La ruta con la que se compara va sin barras invertidas. No es cosmética: al medir esto
  # el 5-sep, un filtro con barras invertidas llegó con la mitad comidas, no casó nada y
  # devolvió una lista vacía -- que se lee IGUAL que un "no hay nada". El awk de abajo
  # tampoco escribe ninguna: construye la comilla y la barra desde su código.
  # Sustitución de bash, no 'tr': un proceso menos, por lo de arriba. 'pwd -W' ya devuelve
  # barras normales, así que esto solo cubre el caso raro en que $RAIZ llegue con las otras.
  raiz_cmp=${ruta_win//\\//}
  ahora_e=$(date +%s)
  # UN find Y UN awk PARA TODAS LAS CARPETAS, no uno por carpeta: en Git Bash sobre
  # Windows lanzar un proceso cuesta más que lo que hace, y es la misma lección que ya
  # tiene escrita la pasada 1. Medido aquí: el awk sobre los 53 MB de las dos carpetas
  # tarda 0,5 s; lo que sobraba eran los procesos.
  lista=$(find "${ancestros[@]}" -maxdepth 1 -name '*.jsonl' -newermt "-$DIAS days" 2>/dev/null)
  if [ -n "$lista" ]; then
    #
    # El cotejo es contra la RUTA del repo y con frontera: detrás del nombre tiene que
    # venir la comilla de cierre (el repo) o un separador (una subcarpeta suya). Sin la
    # frontera, 'bitacora' se llevaría los turnos de 'bitacora-project' -- el mismo fallo
    # de prefijo que se arregló arriba, reaparecido por otra puerta. Se aceptan las dos
    # formas del cwd: escapado con barras dobles (Windows) y con '/' (Unix).
    # El epoch del cierre lo calcula el awk de abajo, no un 'date' por sesión: la
    # conversión es la misma y aquí la línea ya está partida. Ver la pasada 1.
    while IFS=$'\t' read -r aqui tot fin_e fecha ruta; do
      [ -n "$ruta" ] || continue
      [ "$aqui" -ge "$UMBRAL_TURNOS" ] || continue
      sid=${ruta##*/}; sid=${sid%.jsonl}
      [ -n "$EXCLUIR" ] && [ "$sid" = "$EXCLUIR" ] && continue
      # Una sesión recién tocada puede estar VIVA en otra ventana, igual que en la pasada 2.
      # El '-1' es "no supe convertir la fecha", y entonces NO se descarta: dejarla fuera
      # por no saber fecharla sería callar una sesión por un fallo de la herramienta.
      if [ "$fin_e" -gt 0 ] 2>/dev/null; then
        [ $(( ahora_e - fin_e )) -lt $(( RECIENTE_MIN * 60 )) ] && continue
      fi
      carpeta=${ruta%/*}; carpeta=${carpeta##*/}
      n_sueltas=$((n_sueltas + 1))
      sueltas="$sueltas  $sid | $aqui de $tot turnos aquí | $fecha | $carpeta
"
    done <<EOF
$(awk -v raiz="$raiz_cmp" '
      function epoch_de(ts,   d) {
        if (length(ts) < 19) return -1
        d = substr(ts,1,4) " " substr(ts,6,2) " " substr(ts,9,2) " " \
            substr(ts,12,2) " " substr(ts,15,2) " " substr(ts,18,2)
        return mktime(d, 1)
      }
      BEGIN {
        bs = sprintf("%c", 92); q = sprintf("%c", 34)
        n = split(raiz, parte, "/")
        esc = parte[1]
        for (i = 2; i <= n; i++) esc = esc bs bs parte[i]
        n1 = q "cwd" q ":" q raiz; l1 = length(n1)
        n2 = q "cwd" q ":" q esc;  l2 = length(n2)
      }
      /"type":"assistant"/ {
        tot[FILENAME]++
        dentro = 0
        if ((p = index($0, n1)) > 0) { c = substr($0, p + l1, 1); if (c == q || c == "/") dentro = 1 }
        if (!dentro && (p = index($0, n2)) > 0) { c = substr($0, p + l2, 1); if (c == q || c == bs) dentro = 1 }
        if (dentro) aqui[FILENAME]++
      }
      {
        if (match($0, /"timestamp":"[^"]*"/)) {
          ts = substr($0, RSTART + 13, RLENGTH - 14)
          if (ts > mx[FILENAME]) mx[FILENAME] = ts
        }
      }
      END {
        for (f in aqui)
          print aqui[f] "\t" tot[f] "\t" epoch_de(mx[f]) "\t" substr(mx[f], 1, 10) "\t" f
      }
    ' $lista 2>/dev/null)
EOF
  fi
fi

# SE IMPRIME TARDE, Y NO ES COSMÉTICA. El hook de arranque corre este script con
# 'timeout 8'. Cuando lo mata, lo ya escrito en stdout SÍ ha salido y el hook lo trata
# como una auditoría entera, así que el orden de impresión decide qué sobrevive: la deuda
# (accionable, y con borrador detrás) tiene que ir por delante de esto, que es
# informativo. Puesto arriba, lo desplazaba.
#
# El 5-sep-2026 esto no era una precaución sino el caso normal: el auditor pasaba de 8 s
# en 5 de los 9 repos grandes. Ese mismo día se aceleró y quedaron todos entre 1,7 y 3,1 s
# (ver la pasada 1), o sea que hoy el truncamiento es latente y no vivo. El orden se
# mantiene por eso mismo: latente no es imposible, y este es el único sitio donde decidir
# qué se pierde primero cuesta cero.
decir_sueltas() {
  [ "${n_sueltas:-0}" -gt 0 ] || return 0
  echo "NO-SE-PUDO-COMPROBAR (sesiones de fuera): $n_sueltas sesión(es) trabajaron en este repo sin pertenecerle solo a él."
  printf '%s' "$sueltas"
  echo "  Se abrieron por encima del repo (la raíz del disco, o el home) y recorrieron"
  echo "  varios, así que su entrada puede estar en cualquiera de ellos, o en ninguno."
  echo "  NO se cuentan como deuda: la prueba de este auditor es 'hay un commit que toca"
  echo "  ESTA bitácora', y eso no distingue 'anotó donde tocaba' de 'no anotó'. Míralas"
  echo "  tú si reconoces alguna."
}

if [ "${#dirs[@]}" -eq 0 ]; then
  # Aquí sí va primero: no hay deuda que pueda desplazar, y sin esto el repo cuyas únicas
  # sesiones se abrieron por encima de él saldría como "no sé mirarlo" a secas, cuando
  # resulta que sí se ha visto algo y se puede decir qué.
  decir_sueltas
  echo "NO-SE-PUDO-COMPROBAR: no encuentro transcripts para $RAIZ"
  echo "  (buscaba $PROYECTOS/$patron y sus '--claude-worktrees-*')."
  echo "  No es lo mismo que 'no hay sesiones sin anotar': es que no sé mirarlo."
  fin
fi

ahora=$(date +%s)
limite=$(( ahora - DIAS * 86400 ))

# Minutos de gracia para considerar que otra sesión CONTINÚA a ésta. Ver el bloque de
# "cadenas" más abajo: sin esto, cortar la sesión —que es la disciplina que queremos—
# generaba una deuda falsa por cada corte.
GRACIA_MIN="${BITACORA_AUDITORIA_GRACIA_MIN:-5}"

TMP=$(mktemp) || { echo "NO-SE-PUDO-COMPROBAR: sin fichero temporal."; exit 0; }
trap 'rm -f "$TMP" "$TMP.crudo"' EXIT

# ---------- Pasada 1: recoger, sin juzgar ----------
# UN PROCESO POR CARPETA, NO POR FICHERO. La primera versión hacía grep+sed+sort+grep -c
# por transcript y tardaba 9,7 s en el repo más cargado; pasar a un awk por fichero la
# dejó en 6,2. Lo que quedaba no era el trabajo, eran los PROCESOS: en Git Bash sobre
# Windows lanzar uno cuesta más que lo que hace, y esto lanzaba tres por fichero.
#
# Y no es microoptimización: el hook de arranque tiene 25 s de presupuesto, la red ya se
# come 10-20, y su plazo duro son 45. Meter ahí 9,7 s habría reconstruido LITERALMENTE la
# avería del 28-ago —el cuarto fallo silencioso, el hook que moría por timeout— desde la
# pieza que viene a impedirla.
#
# NI UN PROCESO POR SESIÓN, y de ahí sale el resto. Hasta el 5-sep-2026 esa lección estaba
# aplicada a los FICHEROS y no a las SESIONES, y por eso volvió a pasar exactamente lo
# mismo un piso más arriba: el auditor llamaba a 'date' dos veces aquí y tres en la pasada
# 2, más un 'git log | wc -l' por sesión. Perfilado ese día en bitacora-project (11,3 s en
# total): pasada 1 = 3,67 s, pasada 2 = 5,85 s, todo lo demás 1,7 s. Con 'date -d' a 90 ms
# y 'git log | wc -l' a 219, son ~0,7 s por sesión, o sea ~10 s de los 11,3 en fechas. El
# trabajo de verdad —el awk sobre los 53 MB de las carpetas ancestro— tarda 0,42 s.
#
# La consecuencia era el fallo de siempre: con 'timeout 8' el hook mataba el script a
# medias, lo ya escrito en stdout SÍ había salido, y el hook trataba una auditoría PARCIAL
# como entera. Medido: lizar-flota, kangurea-web y lizar-informes tenían 2 SIN-ANOTAR cada
# uno en la ejecución completa y CERO en la de 8 s. Seis deudas reales invisibles, sin
# decir que no se habían mirado.
#
# Así que la conversión de fechas se hace DENTRO de este awk, que ya está leyendo la línea:
# mktime() con el flag UTC para el epoch (las marcas del transcript llevan 'Z', y sin el
# flag saldrían corridas las horas del huso), y strftime() para la fecha legible en hora
# local, que es la que se le enseña al usuario. Lo comprueba el banco
# scripts/probar-coste-auditor.sh, que no mide segundos —eso mediría la máquina— sino que
# corre el auditor sobre 3 y sobre 15 sesiones y exige que el número de 'date' y de 'git'
# NO CREZCA.
for d in "${dirs[@]}"; do
  # Un solo `find` por carpeta para el descarte por mtime. El mtime no sirve para FECHAR
  # una sesión (ese atajo me hizo dar por perdidas cuatro que sí habían anotado, la misma
  # mañana que escribí esto), pero sí para descartarla: un fichero no se toca antes de
  # escribirse, así que mtime viejo implica contenido viejo. La implicación solo vale en
  # esa dirección, y por eso aquí únicamente se EXCLUYE.
  lista=$(find "$d" -maxdepth 1 -name '*.jsonl' -newermt "@$limite" 2>/dev/null)
  [ -n "$lista" ] || continue

  # EL TRANSCRIPT NO ESTÁ ORDENADO CRONOLÓGICAMENTE. Una sesión REANUDADA escribe la
  # marca de reanudación arriba y copia la historia debajo, así que la línea 1 puede ser
  # posterior a la línea 3. Comprobado el 1-sep en 427e04d6: línea 1 = 14:04:21, línea 3
  # = 13:32:17. Con head/tail salía inicio == fin y la sesión se declaraba SIN-ANOTAR
  # siendo falso. Hay que recorrer entero y quedarse con el mínimo y el máximo -- ISO 8601
  # se ordena como texto, así que comparar cadenas basta y no hay que convertir fechas
  # dentro del bucle.
  #
  # Se usa la PRIMERA marca de cada línea a propósito: es la del propio apunte. Las que
  # vengan dentro de un resultado de herramienta son de otra cosa y no deben mover el
  # rango de la sesión.
  #
  # El awk devuelve YA CONVERTIDO lo que antes se le pedía a 'date' una vez por sesión:
  # el epoch de inicio y el de fin (mktime con el flag UTC, porque las marcas llevan 'Z'),
  # y la fecha legible en hora LOCAL, que es la que reconoce quien la lee. Un -1 en el
  # epoch significa "no supe convertirla", y lo recoge el bucle de abajo.
  #
  # NINGÚN COMENTARIO DENTRO DEL PROGRAMA AWK, y no es manía de estilo: el programa va
  # entre comillas SIMPLES del shell, así que un apóstrofo dentro -- el de un "no cabía",
  # o el de citar una orden entre comillas simples -- cierra la cadena y le entrega a awk
  # un programa truncado. Pasó escribiendo esto mismo el 5-sep-2026, y los dos guardias
  # que había miraron para otro lado: 'bash -n' da el visto bueno porque los apóstrofos se
  # emparejan entre ellos, y el '2>/dev/null' de aquí abajo se traga la queja de awk. El
  # resultado era CERO líneas, que doce líneas más abajo se lee igual que "no hay sesiones
  # que juzgar" -- el auditor entero mudo, con su mensaje normal. Lo cazó el banco.
  # shellcheck disable=SC2086
  awk '
    function epoch_de(ts,   d) {
      if (length(ts) < 19) return -1
      d = substr(ts,1,4) " " substr(ts,6,2) " " substr(ts,9,2) " " \
          substr(ts,12,2) " " substr(ts,15,2) " " substr(ts,18,2)
      return mktime(d, 1)
    }
    /"type":"assistant"/ { t[FILENAME]++ }
    {
      if (match($0, /"timestamp":"[^"]*"/)) {
        ts = substr($0, RSTART + 13, RLENGTH - 14)
        if (!(FILENAME in mn) || ts < mn[FILENAME]) mn[FILENAME] = ts
        if (ts > mx[FILENAME]) mx[FILENAME] = ts
      }
    }
    END {
      for (f in mn) {
        fin = epoch_de(mx[f]); ini = epoch_de(mn[f])
        if (ini <= 0) ini = fin
        print ini "\t" fin "\t" t[f] + 0 "\t" \
              (fin > 0 ? strftime("%Y-%m-%d %H:%M", fin) : "") "\t" f
      }
    }
  ' $lista 2>/dev/null > "$TMP.crudo"

  while IFS=$'\t' read -r ini_epoch fin_epoch turnos fecha_leg f; do
    [ -n "$f" ] || continue
    sid=${f##*/}; sid=${sid%.jsonl}
    [ -n "$EXCLUIR" ] && [ "$sid" = "$EXCLUIR" ] && continue

    # Sin fecha de cierre no hay nada que juzgar contra la ventana de commits, así que se
    # salta -- igual que antes saltaba cuando 'date -d' no sabía leer la marca.
    [ "$fin_epoch" -gt 0 ] 2>/dev/null || continue
    [ "$fin_epoch" -lt "$limite" ] && continue

    printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$ini_epoch" "$fin_epoch" "$turnos" "$fecha_leg" "$sid" "$f" >> "$TMP"
  done < "$TMP.crudo"
  rm -f "$TMP.crudo"
done

if [ ! -s "$TMP" ]; then
  decir_sueltas
  echo "Sin sesiones que juzgar en los últimos $DIAS días para $RAIZ."
  fin
fi

n_anotadas=0; n_deuda=0; n_dudosas=0; n_cortas=0; n_curso=0; n_cadena=0
deudas=""

# ---------- Los commits de la bitácora, UNA vez y no uno por sesión ----------
# La pregunta de la pasada 2 es, por cada sesión, "¿hay un commit que toque $FICHERO
# dentro de su ventana?", y se contestaba con un 'git log --since --until | wc -l' POR
# SESIÓN: 219 ms cada uno, medido el 5-sep-2026, más los dos 'date -u -d' que hacían
# falta solo para escribirle las fechas a git en ISO. Con 15 sesiones son 15 procesos de
# git y 30 de date para responder 15 veces a la misma consulta con otro recorte.
#
# Se traen de golpe los que caen en el tramo más ancho que cualquier ventana puede
# alcanzar —desde 'limite' menos la ventana, porque el borde bajo de una sesión que cerró
# justo en 'limite' es VENTANA_H horas antes— y luego se cuenta en aritmética de bash,
# que no lanza nada. La comparación es la misma: '--since/--until' filtra por fecha de
# COMMITTER, y '%ct' es esa misma fecha, así que el conjunto contado es idéntico.
#
# Son decenas de commits en 14 días, o sea que el bucle anidado de aquí abajo es
# irrelevante al lado de un solo proceso.
commits_ct=$(git -C "$RAIZ" log --since="@$(( limite - VENTANA_H * 3600 ))" \
               --format=%ct -- "$FICHERO" 2>/dev/null || true)
# shellcheck disable=SC2206
commits_ct=( $commits_ct )

# ---------- Pasada 2: juzgar ----------
while IFS=$'\t' read -r ini_epoch fin_epoch turnos fecha_leg sid f; do
  [ -n "$sid" ] || continue

  if [ $(( ahora - fin_epoch )) -lt $(( RECIENTE_MIN * 60 )) ]; then
    n_curso=$((n_curso + 1)); continue
  fi
  if [ "$turnos" -lt "$UMBRAL_TURNOS" ]; then
    n_cortas=$((n_cortas + 1)); continue
  fi

  # ---------- ¿La continúa otra sesión, o es la misma dos veces? ----------
  # CORTAR LA SESIÓN ES LA DISCIPLINA, NO UN FALLO. Medido el 1-sep: 2 de las 3 deudas
  # que cantó la primera versión eran conducta correcta, no descuidos.
  #
  # Son DOS fenómenos distintos y se distinguen a propósito. Meterlos en una sola
  # condición ("alguien seguía trabajando cuando acabé") era demasiado ancho: una sesión
  # larga y CONCURRENTE -- una que empezó días antes y sigue abierta -- absorbía a todas
  # las que solapaba y habría TAPADO deuda real. Tapar deuda es la dirección silenciosa,
  # que es justo la que este proyecto persigue, así que se afina:
  #
  #   CADENA      la siguiente ARRANCA donde ésta acaba (±gracia). Es un corte limpio:
  #               12:50 -> 12:51, medido en lizar-asistente-aula el 26-ago.
  #   REANUDADA   otro fichero con el MISMO arranque (±2 min) que termina más tarde: es
  #               la misma conversación escrita dos veces. Medido: dos ficheros de 142
  #               turnos con 55 ms de diferencia en su primer apunte.
  #
  # Ninguno de los dos se oculta: se cuentan y se dicen. Colapsarlos con ANOTADA sería
  # exactamente el fallo que este fichero existe para no repetir.
  continuada=no; nota=""
  while IFS=$'\t' read -r o_ini o_fin o_t o_fecha o_sid o_f; do
    [ "$o_sid" = "$sid" ] && continue
    dif_ini=$(( o_ini - ini_epoch )); [ "$dif_ini" -lt 0 ] && dif_ini=$(( -dif_ini ))
    dif_rel=$(( o_ini - fin_epoch )); [ "$dif_rel" -lt 0 ] && dif_rel=$(( -dif_rel ))
    if [ "$dif_rel" -le $(( GRACIA_MIN * 60 )) ] && [ "$o_fin" -gt "$fin_epoch" ]; then
      continuada=si; nota="corte limpio: la siguiente arranca donde ésta acaba"; break
    fi
    if [ "$dif_ini" -le 120 ] && [ "$o_fin" -ge "$fin_epoch" ]; then
      continuada=si; nota="reanudada: misma conversación en otro fichero"; break
    fi
  done < "$TMP"

  if [ "$continuada" = "si" ]; then
    n_cadena=$((n_cadena + 1))
    echo "CONTINUADA  | $fecha_leg | ${turnos}t | $sid | $nota"
    continue
  fi

  # ---------- La comprobación que importa: el ARTEFACTO ----------
  desde_epoch=$(( fin_epoch - VENTANA_H * 3600 ))
  [ "$ini_epoch" -gt "$desde_epoch" ] && desde_epoch=$ini_epoch
  hasta_epoch=$(( fin_epoch + 900 ))

  if [ -z "$fecha_leg" ]; then
    n_dudosas=$((n_dudosas + 1))
    echo "NO-SE-PUDO-COMPROBAR | $sid | no supe convertir las fechas"
    continue
  fi

  # Contra la lista traída arriba, sin lanzar nada.
  commits=0
  for ct in ${commits_ct[@]+"${commits_ct[@]}"}; do
    [ "$ct" -ge "$desde_epoch" ] || continue
    [ "$ct" -le "$hasta_epoch" ] || continue
    commits=$((commits + 1))
  done

  if [ "$commits" -gt 0 ]; then
    n_anotadas=$((n_anotadas + 1))
    echo "ANOTADA     | $fecha_leg | ${turnos}t | $sid"
  else
    n_deuda=$((n_deuda + 1))
    # El registro de cierre solo ENRIQUECE. Su ausencia es en sí misma un dato: la
    # sesión no cerró limpio, así que ningún hook de cierre pudo haber hecho nada.
    if [ -f "$REGISTRO" ] && linea=$(grep -m1 "	$sid	" "$REGISTRO" 2>/dev/null); then
      motivo=" | cierre=$(printf '%s' "$linea" | cut -f4)"
    else
      motivo=" | sin registro de cierre (no cerró limpio)"
    fi
    echo "SIN-ANOTAR  | $fecha_leg | ${turnos}t | $sid$motivo"
    deudas="$deudas  - $fecha_leg (${turnos} turnos) — $f
"
  fi
done < "$TMP"

decir_sueltas

echo
echo "--- resumen: $RAIZ ---"
echo "anotadas=$n_anotadas  SIN-ANOTAR=$n_deuda  continuadas=$n_cadena  no-comprobables=$n_dudosas  de-fuera=$n_sueltas  (descartadas: $n_cortas cortas, $n_curso en curso)"
echo "ventana ${VENTANA_H}h | suelo ${UMBRAL_TURNOS} turnos | gracia de cadena ${GRACIA_MIN} min | ${DIAS} días"

if [ "$n_deuda" -gt 0 ]; then
  echo
  echo "PENDIENTES DE ANOTAR:"
  printf '%s' "$deudas"
fi
fin
