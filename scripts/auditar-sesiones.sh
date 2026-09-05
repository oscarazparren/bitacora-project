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
  exit 0
fi
# El estilo de ruta que devuelve git ('C:/Users/...') no es el de $PWD ('/c/Users/...').
# Compararlas como texto nunca da igual aunque sean la misma carpeta: ya costó un bug en
# la sección 1b del hook de arranque (NOTAS-DE-CAMPO, 22-ago). Se normaliza aquí.
RAIZ=$(cd "$RAIZ" && pwd)
BITACORA="$RAIZ/$FICHERO"

if [ ! -f "$BITACORA" ]; then
  echo "NO-APLICA: $RAIZ no tiene $FICHERO. No hay dónde anotar."
  exit 0
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
ruta_win=$(cd "$RAIZ" && pwd -W 2>/dev/null || echo "$RAIZ")
patron=$(printf '%s' "$ruta_win" | sed 's#[:/\\ .]#-#g')

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

if [ "${#dirs[@]}" -eq 0 ]; then
  echo "NO-SE-PUDO-COMPROBAR: no encuentro transcripts para $RAIZ"
  echo "  (buscaba $PROYECTOS/$patron y sus '--claude-worktrees-*')."
  echo "  No es lo mismo que 'no hay sesiones sin anotar': es que no sé mirarlo."
  exit 0
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
  # shellcheck disable=SC2086
  awk '
    /"type":"assistant"/ { t[FILENAME]++ }
    {
      if (match($0, /"timestamp":"[^"]*"/)) {
        ts = substr($0, RSTART + 13, RLENGTH - 14)
        if (!(FILENAME in mn) || ts < mn[FILENAME]) mn[FILENAME] = ts
        if (ts > mx[FILENAME]) mx[FILENAME] = ts
      }
    }
    END { for (f in mn) print mn[f] "\t" mx[f] "\t" t[f] + 0 "\t" f }
  ' $lista 2>/dev/null > "$TMP.crudo"

  while IFS=$'\t' read -r ini fin turnos f; do
    [ -n "$f" ] || continue
    sid=${f##*/}; sid=${sid%.jsonl}
    [ -n "$EXCLUIR" ] && [ "$sid" = "$EXCLUIR" ] && continue

    fin_epoch=$(date -d "$fin" +%s 2>/dev/null) || continue
    ini_epoch=$(date -d "$ini" +%s 2>/dev/null) || ini_epoch=$fin_epoch
    [ "$fin_epoch" -lt "$limite" ] && continue

    printf '%s\t%s\t%s\t%s\t%s\n' "$ini_epoch" "$fin_epoch" "$turnos" "$sid" "$f" >> "$TMP"
  done < "$TMP.crudo"
  rm -f "$TMP.crudo"
done

if [ ! -s "$TMP" ]; then
  echo "Sin sesiones que juzgar en los últimos $DIAS días para $RAIZ."
  exit 0
fi

n_anotadas=0; n_deuda=0; n_dudosas=0; n_cortas=0; n_curso=0; n_cadena=0
deudas=""

# ---------- Pasada 2: juzgar ----------
while IFS=$'\t' read -r ini_epoch fin_epoch turnos sid f; do
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
  while IFS=$'\t' read -r o_ini o_fin o_t o_sid o_f; do
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

  fecha_leg=$(date -d "@$fin_epoch" '+%Y-%m-%d %H:%M' 2>/dev/null)

  if [ "$continuada" = "si" ]; then
    n_cadena=$((n_cadena + 1))
    echo "CONTINUADA  | $fecha_leg | ${turnos}t | $sid | $nota"
    continue
  fi

  # ---------- La comprobación que importa: el ARTEFACTO ----------
  desde_epoch=$(( fin_epoch - VENTANA_H * 3600 ))
  [ "$ini_epoch" -gt "$desde_epoch" ] && desde_epoch=$ini_epoch
  desde=$(date -u -d "@$desde_epoch" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)
  hasta=$(date -u -d "@$(( fin_epoch + 900 ))" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)

  if [ -z "$desde" ] || [ -z "$hasta" ]; then
    n_dudosas=$((n_dudosas + 1))
    echo "NO-SE-PUDO-COMPROBAR | $sid | no supe convertir las fechas"
    continue
  fi

  commits=$(git -C "$RAIZ" log --since="$desde" --until="$hasta" \
               --format=%h -- "$FICHERO" 2>/dev/null | wc -l)
  commits=$(printf '%s' "$commits" | tr -dc '0-9'); commits=${commits:-0}

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

echo
echo "--- resumen: $RAIZ ---"
echo "anotadas=$n_anotadas  SIN-ANOTAR=$n_deuda  continuadas=$n_cadena  no-comprobables=$n_dudosas  (descartadas: $n_cortas cortas, $n_curso en curso)"
echo "ventana ${VENTANA_H}h | suelo ${UMBRAL_TURNOS} turnos | gracia de cadena ${GRACIA_MIN} min | ${DIAS} días"

if [ "$n_deuda" -gt 0 ]; then
  echo
  echo "PENDIENTES DE ANOTAR:"
  printf '%s' "$deudas"
fi
exit 0
