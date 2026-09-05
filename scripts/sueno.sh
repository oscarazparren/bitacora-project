#!/bin/bash
# Bitácora -- EL SUEÑO: repasa lo de ayer y PROPONE. No ejecuta nada.
#
# Hermano de auditar-sesiones.sh, y la misma doctrina llevada un paso más allá. El
# auditor responde a UNA pregunta (¿esta sesión anotó?) sobre UN repo, y lo hace en el
# arranque, cuando hay 25 segundos de presupuesto. El sueño corre de noche, sin prisa y
# sin nadie mirando: recorre TODOS los repos, cruza lo que ya saben las piezas sueltas
# --el auditor, el contable, git-- y escribe una lista de propuestas para el humano.
#
# EL QUE SUEÑA NO EJECUTA. Es la lección nº4 del proyecto otra vez: el hook que moría
# por timeout escribía su propia línea de éxito 22 segundos después de estar muerto. Un
# proceso que se arregla a sí mismo por la noche y deja escrito que lo hizo es esa misma
# avería con más superficie. Aquí no se anota, no se commitea, no se sube, no se borra
# nada. Se escribe UN fichero, fuera de todo repo, y se dice lo que habría que hacer.
#
# LAS PROPUESTAS VAN EN POWERSHELL AUNQUE ESTO SEA BASH. El script corre en Git Bash;
# quien pega los comandos es Oscar, y Oscar ejecuta en PowerShell. Son dos cosas
# distintas y confundirlas ya costó un error real (un 'git commit && git push' que en
# PowerShell 5.1 ni siquiera se analiza). Regla del CLAUDE.md global, aplicada aquí.
#
# NO SE ENGANCHA A NINGÚN HOOK, por lo mismo que el contable: ejecutarlo cuesta cero
# tokens, pero su salida inyectada en cada arranque se paga en cada turno posterior. Va
# al Programador de tareas, y lo que se lee es el FICHERO. Ver "Cómo dejarlo corriendo"
# al final de esta cabecera.
#
# TRES ESTADOS, NUNCA COLAPSADOS -- otra vez, y por la misma razón de siempre:
#   PROPUESTA              hay algo que hacer, con su evidencia y su comando.
#   NADA-QUE-PROPONER      se miró y está limpio.
#   NO-SE-PUDO-COMPROBAR   no se pudo mirar. Grita más que el segundo: "no lo sé" y "no
#                          hay nada" se han leído igual demasiadas veces en este
#                          proyecto, y esa confusión es la forma de los cuatro fallos
#                          silenciosos.
#
# LAS PROPUESTAS SE ACUERDAN DE SÍ MISMAS. Cada una lleva una clave estable y se guarda
# en un estado local. Si mañana vuelve a salir la misma, sale numerada: "3.er día". Una
# propuesta que lleva una semana repitiéndose ya no es una propuesta, es un dato sobre
# el sistema -- o no se ve, o no se puede hacer, o no importa. Sin esa cuenta, un
# informe diario es indistinguible de un informe diario que nadie lee.
#
# LO QUE SÍ SE MIRA, Y CON QUÉ UMBRAL (medido el 4-sep-2026, no elegido a ojo):
#
#   1. Deuda de bitácora en TODOS los repos. El hook Stop retirado solo miraba el repo
#      desde el que se abrió la sesión: avisaba de uno y callaba de los demás. Esto lo
#      arregla por la vía de recorrerlos todos.
#   2. Sesiones que terminaron por encima del umbral duro de contexto. Se usa el MISMO
#      umbral que userpromptsubmit-contexto.sh (BITACORA_CONTEXTO_URGENTE_TOKENS,
#      400.000) a propósito: dos umbrales distintos para la misma pregunta se
#      contradirían delante del humano. Medido: 6 de 95 sesiones de la última semana
#      (6 %) acabaron ahí, o sea ~1 al día. Accionable.
#   3. Sesiones caras. El umbral por defecto son 20 $ porque ahí está el codo: en la
#      última semana marcaba 12 sesiones de 84 (14 %) que se llevaban el 55 % del gasto.
#      A 30 $ se cae al 42 % del gasto; a 10 $ salen 22 sesiones y deja de ser una lista
#      que alguien mire.
#   4. Trabajo hecho y no subido. Dos máquinas sobre los mismos repos: un commit que
#      solo existe en una es un conflicto en diferido. Ya pasó (29-ago-2026).
#
# LO QUE NO MIRA, Y CONVIENE SABERLO:
#   - Si el REMOTO va por delante. Eso necesita red; con --fetch se comprueba, y
#     entonces --fetch es lo ÚNICO de todo el script que toca la red. No modifica el
#     árbol de trabajo ni en ese caso.
#   - Repos de la cuenta sin clonar (necesita 'gh' y credenciales).
#   - La deriva del CLAUDE.md local contra el canónico: ya la canta el arranque, en la
#     sección 1d de sessionstart-leer.sh. Repetirla aquí sería dos voces sobre lo mismo.
#
# COSTE: lo que tarda el auditor por repo, más una pasada de Python sobre los
# transcripts. Medido el 4-sep-2026 en esta máquina: **141-180 s con 41 repos** y 286 MB de
# transcripts. Es de noche y no hay nadie esperando; por eso esto puede permitirse lo
# que el hook de arranque no (allí el presupuesto son 25 s y el plazo duro 45).
#
# Uso:
#   sueno.sh                       # repasa los últimos 2 días y escribe el informe
#   sueno.sh --dias 7              # ventana más ancha
#   sueno.sh --raiz /c/Users/x/repos
#   sueno.sh --fetch               # además, comprueba si algún remoto va por delante
#   sueno.sh --silencioso          # solo imprime la ruta del informe (para el cron)
#
# Salida: el informe por stdout y una copia en $BITACORA_SUENOS/AAAA-MM-DD.md.
# Código de salida SIEMPRE 0: es un informe, no una comprobación que deba tumbar nada.
#
# Cómo dejarlo corriendo a diario (PowerShell, como administrador no hace falta):
#   $a = New-ScheduledTaskAction -Execute 'C:\Program Files\Git\bin\bash.exe' `
#        -Argument '-lc "~/repos/bitacora-project/scripts/sueno.sh --silencioso"'
#   $t = New-ScheduledTaskTrigger -Daily -At 7:00
#   Register-ScheduledTask -TaskName 'bitacora-sueno' -Action $a -Trigger $t
# (comprobar antes la ruta real de bash.exe con: (Get-Command bash).Source)

set -uo pipefail

CONF="${BITACORA_CONF:-$HOME/.claude/bitacora.conf}"
# shellcheck disable=SC1090
[ -f "$CONF" ] && . "$CONF"

AQUI=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

SUENOS="${BITACORA_SUENOS:-$HOME/.claude/bitacora-suenos}"
RAIZ_REPOS="${BITACORA_SUENO_REPOS:-$HOME/repos}"
IGNORAR="${BITACORA_IGNORAR:-*/repos/referencia/*|*/repos/archivo/*|*/tools/*|*/node_modules/*|*/.claude/*}"
DIAS="${BITACORA_SUENO_DIAS:-2}"
COSTE_AVISO="${BITACORA_SUENO_COSTE_SESION:-20}"
URGENTE="${BITACORA_CONTEXTO_URGENTE_TOKENS:-400000}"
PROYECTOS="${BITACORA_PROYECTOS:-$HOME/.claude/projects}"
ESTADO="${BITACORA_SUENO_ESTADO:-$SUENOS/propuestas.tsv}"
# Más allá de esto, una propuesta vieja deja de arrastrarse en el estado: si lleva un
# mes sin volver a salir, ya no describe nada del presente.
OLVIDO_DIAS="${BITACORA_SUENO_OLVIDO_DIAS:-30}"

FETCH=no
SILENCIOSO=no
while [ $# -gt 0 ]; do
  case "$1" in
    --dias) DIAS="${2:-$DIAS}"; shift 2 ;;
    --raiz) RAIZ_REPOS="${2:-$RAIZ_REPOS}"; shift 2 ;;
    --fetch) FETCH=si; shift ;;
    --silencioso) SILENCIOSO=si; shift ;;
    -h|--help) sed -n '2,90p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "sueno: opción desconocida '$1' (--help para la lista)" >&2; exit 0 ;;
  esac
done

HOY=$(date +%F)
INICIO=$(date +%s)
mkdir -p "$SUENOS" 2>/dev/null || { echo "sueno: no puedo crear $SUENOS" >&2; exit 0; }
INFORME="$SUENOS/$HOY.md"

CUERPO=$(mktemp) || { echo "sueno: sin fichero temporal." >&2; exit 0; }
NUEVAS=$(mktemp) || { rm -f "$CUERPO"; exit 0; }
PATRONES=""
trap 'rm -f "$CUERPO" "$NUEVAS" "$CUERPO.tmp" "$CUERPO.cabecera" ${PATRONES:+"$PATRONES"}' EXIT

N_PROP=0; N_LIMPIO=0; N_DUDOSO=0

# ---------- Utilidades ----------

# Ruta de Git Bash a ruta de Windows, para que los comandos propuestos se puedan pegar
# en PowerShell tal cual. cygpath viene con Git Bash; si faltara, se apaña a mano.
a_windows() {
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -w "$1" 2>/dev/null && return
  fi
  printf '%s' "$1" | sed 's#^/\([a-zA-Z]\)/#\U\1:\\#; s#/#\\#g'
}

ignorado() {
  local ruta="$1" patron
  local IFS='|'
  for patron in $IGNORAR; do
    [ -n "$patron" ] || continue
    # shellcheck disable=SC2254
    case "$ruta" in $patron) return 0 ;; esac
  done
  return 1
}

# Devuelve la coletilla de reincidencia de una propuesta y anota que hoy volvió a salir.
# El estado se lee del fichero VIEJO y se escribe en uno nuevo al final: así una caída a
# mitad de informe no deja el recuento a medias.
reincidencia() {
  local clave="$1" linea primera veces ultima
  # La comparación es por CAMPO ENTERO, no por prefijo. Con 'grep -F' habría que anclar
  # con un tabulador, y $(printf '...\t') lo pierde: la sustitución de comandos se come
  # el espacio en blanco final. Así "deuda:foo" habría casado con "deuda:foobar".
  if [ -f "$ESTADO" ] && linea=$(awk -F'\t' -v k="$clave" '$1==k{print; exit}' "$ESTADO" 2>/dev/null) && [ -n "$linea" ]; then
    primera=$(printf '%s' "$linea" | cut -f2)
    veces=$(printf '%s' "$linea" | cut -f3)
    ultima=$(printf '%s' "$linea" | cut -f4)
    veces=$(printf '%s' "${veces:-1}" | tr -dc '0-9'); veces=${veces:-1}
    # Dos ejecuciones el mismo día no son dos días.
    if [ "$ultima" != "$HOY" ]; then veces=$((veces + 1)); fi
    printf '%s\t%s\t%s\t%s\n' "$clave" "$primera" "$veces" "$HOY" >> "$NUEVAS"
    if [ "$veces" -gt 1 ]; then
      printf ' _(%sº día que se propone, desde el %s)_' "$veces" "$primera"
    fi
  else
    printf '%s\t%s\t%s\t%s\n' "$clave" "$HOY" 1 "$HOY" >> "$NUEVAS"
  fi
}

propuesta() {   # propuesta <clave> <titular>
  N_PROP=$((N_PROP + 1))
  printf '\n### PROPUESTA -- %s%s\n\n' "$2" "$(reincidencia "$1")" >> "$CUERPO"
}

limpio() { N_LIMPIO=$((N_LIMPIO + 1)); printf '\nNADA-QUE-PROPONER -- %s\n' "$1" >> "$CUERPO"; }
dudoso() { N_DUDOSO=$((N_DUDOSO + 1)); printf '\nNO-SE-PUDO-COMPROBAR -- %s\n' "$1" >> "$CUERPO"; }

# ---------- Localizar los repos ----------
REPOS=""
if [ -d "$RAIZ_REPOS" ]; then
  for d in "$RAIZ_REPOS"/*/; do
    d=${d%/}
    [ -d "$d/.git" ] || continue
    ignorado "$d" && continue
    REPOS="$REPOS $d"
  done
fi

# NO BASTA CON QUE EL NOMBRE EXISTA: hay que EJECUTARLO. En este Windows, 'python3'
# resuelve a C:\...\WindowsApps\python3, el alias del Microsoft Store, que existe, está
# en el PATH y al invocarlo escupe "no se encontró Python" y sale con 49. La primera
# versión de esto se fio de 'command -v' y el revisor de gasto salió
# NO-SE-PUDO-COMPROBAR sin que nadie supiera por qué. Se prueba con -c, que es barato.
PY=""
for cand in python3 python py; do
  command -v "$cand" >/dev/null 2>&1 || continue
  "$cand" -c 'import sys' >/dev/null 2>&1 || continue
  PY="$cand"; break
done

{
  echo "# Sueño del $HOY"
  echo
  echo "Repaso automático de los últimos $DIAS día(s). **Nadie ha ejecutado nada**: esto"
  echo "es lo que un humano tendría que decidir. Los comandos van en PowerShell."
} > "$CUERPO.cabecera"

# =========================================================================
# REVISOR 1 -- Deuda de bitácora, en TODOS los repos
# =========================================================================
printf '\n## 1. Sesiones que cerraron sin anotar\n' >> "$CUERPO"
printf '\n_Ventana propia del auditor (`BITACORA_AUDITORIA_DIAS`), no la de `--dias`: la\ndeuda de anotar no caduca a los dos días._\n' >> "$CUERPO"

AUDITOR="$AQUI/auditar-sesiones.sh"

# CADA TRANSCRIPT TIENE UN SOLO DUEÑO. El auditor buscaba las carpetas por PREFIJO
# abierto y, cuando el nombre de un repo era prefijo del de otro, se llevaba las sesiones
# ajenas: preguntado por '~/repos/bitacora' devolvía también las de 'bitacora-flota' y
# 'bitacora-project'. Medido en la primera ejecución de este script: proponía reconstruir
# 7 sesiones "de bitacora" que eran de otros dos repos.
#
# ARREGLADO EN EL AUDITOR el 5-sep-2026, con su banco de pruebas
# (scripts/probar-atribucion-transcripts.sh): ahora solo acepta la coincidencia exacta y
# los worktrees de Claude, y NOMBRA lo que descarta. Medido después: las 8 deudas falsas
# de '~/repos/bitacora' pasaron a 0.
#
# ESTE FILTRO SE QUEDA, como segunda línea y no como el arreglo. Razón concreta: el sueño
# invoca al auditor que encuentre en el disco, que puede ser una copia vieja —otra
# máquina, o el servidor de flota— y entonces la deuda falsa volvería sin que nada la
# frene. Aquí sale gratis: la lista de repos ya está delante, que es justo lo que al
# auditor le falta. Asigna cada transcript al repo cuyo patrón case MÁS LARGO, el más
# específico.
PATRONES=$(mktemp)
for repo in $REPOS; do
  rw=$(cd "$repo" && pwd -W 2>/dev/null || echo "$repo")
  printf '%s\t%s\t%s\n' "${#rw}" "$(printf '%s' "$rw" | sed 's#[:/\\]#-#g')" "$repo" >> "$PATRONES"
done
sort -rn -o "$PATRONES" "$PATRONES" 2>/dev/null

duena_de() {   # duena_de <nombre-de-carpeta-de-proyecto> -> ruta del repo, o vacío
  local dir="$1" _len patron repo
  while IFS=$'\t' read -r _len patron repo; do
    [ -n "$patron" ] || continue
    case "$dir" in "$patron"|"$patron"-*) printf '%s' "$repo"; return 0 ;; esac
  done < "$PATRONES"
  return 1
}
if [ ! -x "$AUDITOR" ]; then
  dudoso "no encuentro $AUDITOR, que es quien sabe responder a esto."
elif [ -z "$REPOS" ]; then
  dudoso "no encuentro repos en $RAIZ_REPOS (¿es la raíz correcta? se ajusta con --raiz)."
else
  hubo_deuda=no
  for repo in $REPOS; do
    nombre=${repo##*/}
    # El auditor tiene su propia ventana (BITACORA_AUDITORIA_DIAS); no se le pisa desde
    # aquí a propósito -- si las dos ventanas discreparan, una pieza contaría deuda que
    # la otra no y el humano no sabría cuál creer.
    salida=$(BITACORA_CONF="$CONF" "$AUDITOR" "$repo" 2>/dev/null)
    pendientes=$(printf '%s\n' "$salida" | sed -n '/^PENDIENTES DE ANOTAR:/,$p' | sed '1d' | sed '/^[[:space:]]*$/d')
    [ -n "$pendientes" ] || continue

    # Se quedan solo las sesiones de las que ESTE repo es el dueño más específico.
    mias=""
    while IFS= read -r linea; do
      tr=$(printf '%s' "$linea" | grep -oE '/[^ ]*\.jsonl$')
      [ -n "$tr" ] || continue
      carpeta=${tr%/*}; carpeta=${carpeta##*/}
      [ "$(duena_de "$carpeta")" = "$repo" ] || continue
      mias="$mias$linea
"
    done <<EOF
$pendientes
EOF
    pendientes=$(printf '%s' "$mias" | sed '/^[[:space:]]*$/d')
    [ -n "$pendientes" ] || continue
    hubo_deuda=si
    n=$(printf '%s\n' "$pendientes" | wc -l | tr -dc '0-9')
    propuesta "deuda:$nombre" "Anotar $n sesión(es) de \`$nombre\`"
    {
      echo "El auditor las da por SIN-ANOTAR: no hay ningún commit que toque su bitácora"
      echo "en la ventana de cierre. No es que el hook fallara -- es que el artefacto no está."
      echo
      echo '```'
      printf '%s\n' "$pendientes"
      echo '```'
      echo
      echo "Para reconstruir cada una sin pagar contexto, el borrador mecánico (prompts"
      echo "literales, ficheros tocados, comandos y commits) y luego abrir sesión ahí:"
      echo
      echo '```powershell'
      printf '%s\n' "$pendientes" | sed -n '1,3p' | while read -r linea; do
        tr=$(printf '%s' "$linea" | grep -oE '/[^ ]*\.jsonl$')
        [ -n "$tr" ] || continue
        echo "bash $(a_windows "$AQUI/borrador-sesion.sh" | sed 's#\\#/#g') '$tr' '$repo'"
      done
      echo "cd $(a_windows "$repo")"
      echo '```'
    } >> "$CUERPO"
  done
  [ "$hubo_deuda" = no ] && limpio "ningún repo tiene sesiones sin anotar en la ventana del auditor."
fi

# =========================================================================
# REVISOR 2 -- Sesiones que pasaron del umbral duro de contexto
# =========================================================================
printf '\n## 2. Sesiones que se pasaron del umbral de corte\n' >> "$CUERPO"

if [ ! -d "$PROYECTOS" ]; then
  dudoso "no existe $PROYECTOS; sin transcripts no hay nada que medir."
else
  # La métrica es la del hook de contexto, no otra: input + cache_creation + cache_read
  # del ÚLTIMO usage, que es lo que se REENVÍA en el turno siguiente. output_tokens no
  # cuenta porque no se reenvía. Se acota la ventana del grep hasta
  # "output_tokens_details" porque el objeto "iterations" repite esos mismos nombres de
  # campo más abajo en la misma línea.
  pasadas=""
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    u=$(grep -oE '"usage":\{[^}]*"output_tokens_details"' "$f" 2>/dev/null | tail -1)
    [ -n "$u" ] || continue
    i=$(printf '%s' "$u" | sed -n 's/.*"input_tokens":\([0-9]*\).*/\1/p')
    c=$(printf '%s' "$u" | sed -n 's/.*"cache_creation_input_tokens":\([0-9]*\).*/\1/p')
    r=$(printf '%s' "$u" | sed -n 's/.*"cache_read_input_tokens":\([0-9]*\).*/\1/p')
    tot=$(( ${i:-0} + ${c:-0} + ${r:-0} ))
    [ "$tot" -gt "$URGENTE" ] || continue
    sid=${f##*/}; sid=${sid%.jsonl}
    proy=${f%/*}; proy=${proy##*/}
    turnos=$(grep -c '"type":"assistant"' "$f" 2>/dev/null | tr -dc '0-9')
    modelo=$(grep -oE '"model":"[^"]*"' "$f" 2>/dev/null | tail -1 | cut -d'"' -f4)
    pasadas="$pasadas${sid:0:8}|$proy|${turnos:-?}|$tot|$modelo
"
  done <<EOF
$(find "$PROYECTOS" -maxdepth 2 -name '*.jsonl' -newermt "-$DIAS days" 2>/dev/null)
EOF

  if [ -z "$pasadas" ]; then
    limpio "ninguna sesión terminó por encima de $(printf "%'d" "$URGENTE" 2>/dev/null || echo "$URGENTE") tokens de contexto."
  else
    n=$(printf '%s' "$pasadas" | sed '/^$/d' | wc -l | tr -dc '0-9')
    # La clave NO lleva la fecha, y es deliberado: si la llevara, cada día sería una
    # propuesta nueva y el contador de reincidencia no contaría nunca -- que es
    # exactamente el fallo que tuvo la primera versión de este script. Lo que interesa
    # recordar no es "esta sesión concreta", que ya pasó y no tiene arreglo, sino que la
    # SITUACIÓN se repite: tres días seguidos pasándose del umbral dicen algo del
    # sistema, no de la sesión.
    propuesta "contexto" "$n sesión(es) terminaron por encima del umbral duro de contexto"
    {
      echo "Umbral: **$URGENTE tokens** (\`BITACORA_CONTEXTO_URGENTE_TOKENS\`, el mismo que"
      echo "avisa en cada prompt). Pasar de ahí no solo cuesta dinero: con el contexto"
      echo "cargado se falla más -- olvidos de rutina y conclusiones dadas por verificadas"
      echo "sin estarlo."
      echo
      echo '```'
      printf 'sesion   proyecto                                 turnos     contexto  modelo\n'
      printf '%s' "$pasadas" | sed '/^$/d' | sort -t'|' -k4 -rn | while IFS='|' read -r s p t k m; do
        printf '%-8s %-40s %6s %12s  %s\n' "$s" "${p:0:40}" "$t" "$k" "${m#claude-}"
      done
      echo '```'
      echo
      echo "No hay comando que ejecutar: la acción es **cortar antes** la próxima vez. Y el"
      echo "instante del corte es el único en que cambiar de modelo sale gratis, porque la"
      echo "caché de prompt se pierde igualmente."
    } >> "$CUERPO"
  fi
fi

# =========================================================================
# REVISOR 3 -- Gasto
# =========================================================================
printf '\n## 3. Gasto\n' >> "$CUERPO"

CONTABLE="$AQUI/coste-sesiones.py"
JSON="$SUENOS/.coste-$HOY.json"
if [ -z "$PY" ]; then
  dudoso "no encuentro python en el PATH; el contable no puede correr."
elif [ ! -f "$CONTABLE" ]; then
  dudoso "no encuentro $CONTABLE."
elif ! "$PY" "$CONTABLE" --dias "$DIAS" --top 0 --resumen --json "$JSON" > "$CUERPO.tmp" 2>/dev/null; then
  dudoso "el contable falló al ejecutarse. Se puede reproducir a mano y ver qué dice."
else
  {
    echo
    echo '```'
    grep -v '^Detalle en JSON' "$CUERPO.tmp"
    echo '```'
  } >> "$CUERPO"

  # El JSON existe justamente para esto. Parsear la tabla humana del contable sería
  # frágil: el día que cambie una columna, el sueño empezaría a mentir en silencio.
  caras=$("$PY" - "$JSON" "$COSTE_AVISO" <<'PY' 2>/dev/null
import json, sys
try:
    d = json.load(open(sys.argv[1], encoding="utf-8"))
except Exception:
    sys.exit(1)
umbral = float(sys.argv[2])
filas = [(v["coste"], k, v) for k, v in d.get("por_sesion", {}).items() if v["coste"] > umbral]
for coste, clave, v in sorted(filas, reverse=True):
    proyecto, sesion = clave.split("|", 1)
    for p in ("C--Users-Oscar-repos-", "c--Users-Oscar-repos-", "C--Users-Oscar-", "c--Users-Oscar-"):
        if proyecto.startswith(p):
            proyecto = proyecto[len(p):] or "(raiz)"
            break
    print(f"{sesion[:8]}|{proyecto}|{v['dia_min']}|{v['mensajes']}|{coste:.2f}")
PY
)
  if [ -n "$caras" ]; then
    n=$(printf '%s\n' "$caras" | sed '/^$/d' | wc -l | tr -dc '0-9')
    propuesta "coste" "$n sesión(es) por encima de $COSTE_AVISO \$"
    {
      echo "No son necesariamente un error -- una tarde larga de trabajo real cuesta esto."
      echo "Merecen mirada porque ahí está el dinero: en la semana medida, las sesiones de"
      echo "más de 20 \$ eran el 14 % de las sesiones y el 55 % del gasto."
      echo
      echo '```'
      printf 'sesion   proyecto                       dia         mensajes   coste $\n'
      printf '%s\n' "$caras" | sed '/^$/d' | while IFS='|' read -r s p d m c; do
        printf '%-8s %-30s %-11s %8s %9s\n' "$s" "${p:0:30}" "$d" "$m" "$c"
      done
      echo '```'
      echo
      echo "Para ver en qué se fue una de ellas:"
      echo
      echo '```powershell'
      echo "python $(a_windows "$CONTABLE") --dias $DIAS --top 40"
      echo '```'
    } >> "$CUERPO"
  else
    limpio "ninguna sesión pasó de $COSTE_AVISO \$ en la ventana."
  fi
  rm -f "$JSON"
fi

# =========================================================================
# REVISOR 4 -- Trabajo hecho y no subido
# =========================================================================
printf '\n## 4. Trabajo sin subir\n' >> "$CUERPO"

if [ -z "$REPOS" ]; then
  dudoso "no encuentro repos en $RAIZ_REPOS."
else
  pendiente=""
  for repo in $REPOS; do
    nombre=${repo##*/}
    git -C "$repo" rev-parse --git-dir >/dev/null 2>&1 || continue
    [ "$FETCH" = si ] && git -C "$repo" fetch -q --all 2>/dev/null
    sube=$(git -C "$repo" rev-list --count '@{u}..HEAD' 2>/dev/null | tr -dc '0-9')
    baja=$(git -C "$repo" rev-list --count 'HEAD..@{u}' 2>/dev/null | tr -dc '0-9')
    sucio=$(git -C "$repo" status --porcelain 2>/dev/null | wc -l | tr -dc '0-9')
    if [ -z "$sube" ] && [ "${sucio:-0}" -eq 0 ]; then
      continue   # sin rama de seguimiento y sin cambios: nada que decir
    fi
    [ "${sube:-0}" -eq 0 ] && [ "${baja:-0}" -eq 0 ] && [ "${sucio:-0}" -eq 0 ] && continue
    pendiente="$pendiente$nombre|${sube:-?}|${baja:-?}|${sucio:-0}|$repo
"
  done

  if [ -z "$pendiente" ]; then
    limpio "todos los repos están limpios y con lo suyo subido."
  else
    n=$(printf '%s' "$pendiente" | sed '/^$/d' | wc -l | tr -dc '0-9')
    propuesta "sinsubir" "$n repo(s) con trabajo sin subir o sin commitear"
    {
      echo "Dos máquinas trabajan sobre los mismos repos. Un commit que solo existe en una"
      echo "no es un pendiente: es un conflicto en diferido, y ya pasó (29-ago-2026, un"
      echo "commit de dos días que solo existía en una máquina)."
      if [ "$FETCH" != si ]; then
        echo
        echo "La columna \`baja\` sale de la referencia local del remoto, que puede estar"
        echo "vieja: **sin \`--fetch\` esto NO comprueba si el remoto va por delante.**"
      fi
      echo
      echo '```'
      printf 'repo                           sube  baja  sucio\n'
      printf '%s' "$pendiente" | sed '/^$/d' | while IFS='|' read -r nm s b su ru; do
        printf '%-30s %5s %5s %6s\n' "${nm:0:30}" "$s" "$b" "$su"
      done
      echo '```'
      echo
      echo "Repo por repo (mirar el diff antes de commitear: aquí no se decide por nadie):"
      echo
      echo '```powershell'
      printf '%s' "$pendiente" | sed '/^$/d' | while IFS='|' read -r nm s b su ru; do
        echo "cd $(a_windows "$ru"); git status -sb"
      done
      echo '```'
    } >> "$CUERPO"
  fi
fi

# =========================================================================
# Cierre
# =========================================================================
SEGS=$(( $(date +%s) - INICIO ))
{
  echo
  echo "---"
  echo
  printf 'PROPUESTAS=%s  limpios=%s  NO-SE-PUDO-COMPROBAR=%s  |  %s repo(s), ventana %s día(s), %s s\n' \
    "$N_PROP" "$N_LIMPIO" "$N_DUDOSO" "$(printf '%s' "$REPOS" | wc -w | tr -dc '0-9')" "$DIAS" "$SEGS"
  if [ "$N_DUDOSO" -gt 0 ]; then
    echo
    echo "Hay $N_DUDOSO cosa(s) que NO se pudieron comprobar. Eso no es \"está limpio\":"
    echo "es que no se sabe, y se dice para que no se lea como lo otro."
  fi
} >> "$CUERPO"

# Estado de reincidencia: se reescribe entero, conservando las claves que hoy no han
# salido pero siguen siendo recientes. Una propuesta que lleva OLVIDO_DIAS sin repetirse
# se cae sola del recuento.
if [ -s "$NUEVAS" ]; then
  corte=$(date -d "-$OLVIDO_DIAS days" +%F 2>/dev/null || echo "0000-00-00")
  {
    cat "$NUEVAS"
    if [ -f "$ESTADO" ]; then
      while IFS=$'\t' read -r k p v u; do
        [ -n "$k" ] || continue
        awk -F'\t' -v k="$k" '$1==k{hallada=1} END{exit !hallada}' "$NUEVAS" && continue
        [ "$u" \< "$corte" ] && continue
        printf '%s\t%s\t%s\t%s\n' "$k" "$p" "$v" "$u"
      done < "$ESTADO"
    fi
  } | awk -F'\t' '!visto[$1]++' > "$ESTADO.tmp" 2>/dev/null && mv -f "$ESTADO.tmp" "$ESTADO"
  # awk y no 'sort -u': entre claves iguales, sort no promete quedarse con la primera
  # LÍNEA DEL FLUJO, y aquí eso decide si sobrevive el recuento de hoy o el de ayer.
fi

cat "$CUERPO.cabecera" "$CUERPO" > "$INFORME" 2>/dev/null
rm -f "$CUERPO.cabecera"

if [ "$SILENCIOSO" = si ]; then
  printf '%s\n' "$INFORME"
else
  cat "$INFORME"
  printf '\n(copia en %s)\n' "$INFORME"
fi

exit 0
