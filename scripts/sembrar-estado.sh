#!/bin/bash
# Bitácora — siembra estado.txt UNA VEZ con la punta actual de cada repo.
#
# POR QUÉ EXISTE. Los webhooks solo avisan de pushes FUTUROS, así que estado.txt nace
# vacío y se llena repo a repo según alguien los va tocando. Mientras tanto el índice
# del arranque dice "SIN DATOS TODAVÍA" de ellos — que es honesto, pero es un agujero
# que puede durar meses: un repo que nadie toca no se llena NUNCA. El 1-sep-2026 eran
# 27 de 40 vigilados, y el titular del índice llegó a tranquilizar sobre repos de los
# que no sabía nada. Esto cierra el agujero de golpe.
#
# EL TOKEN NO SE MUEVE DE AQUÍ, Y ESO ES EL DISEÑO ENTERO.
# receptor-webhook.py explica por qué el servidor NO pregunta a GitHub: guardar allí un
# token con permiso de lectura sobre todos los repos amplía el botín de quien entre, y
# ese servidor ya guarda los .env de todos los agentes. Ese razonamiento sigue en pie y
# este script no lo toca: la API de GitHub se consulta DESDE TU PC, con el `gh` que ya
# tienes autenticado, y al servidor solo le llega una lista de nombre+SHA por SSH. En el
# servidor no queda ninguna credencial nueva, ni siquiera de paso.
#
# NO PISA LO QUE ESCRIBIERON LOS WEBHOOKS. Solo AÑADE los repos que no tienen fila. Un
# repo del que el servidor ya sabe algo tiene un dato mejor que el nuestro (viene de un
# push real, con su hora); el nuestro es una foto de ahora mismo.
#
# SÍ SIEMBRA LOS ARCHIVADOS, al revés que sincronizar-webhooks.sh, y no es una
# incoherencia: allí se saltan porque GitHub no deja ponerles webhook. Justo por eso hay
# que sembrarlos AQUÍ — si no, nunca recibirán un push, nunca se llenará su fila, y se
# quedarían en "no se sabe" de por vida cuando en realidad sabemos que no se pueden
# mover. Sembrado, el índice dice de ellos la verdad: sin movimiento.
#
# USO:
#   bash scripts/sembrar-estado.sh              # siembra
#   bash scripts/sembrar-estado.sh --revisar    # dice qué haría, no escribe nada
#
# Necesita `gh` autenticado EN ESTA MÁQUINA (en el servidor no hay gh) y acceso ssh.
# Es idempotente: lanzarlo dos veces no cambia nada la segunda.

set -uo pipefail

SERVIDOR="${BITACORA_FLOTA_SSH:-lizar}"
ESTADO="${BITACORA_ESTADO_REMOTO:-/opt/bitacora/estado/estado.txt}"
INDICE="${BITACORA_INDICE_REPOS:-/opt/bitacora/repos.txt}"
CUENTA="${BITACORA_CUENTA_GITHUB:-oscarazparren}"
# Usuario del servicio (ver bitacora-receptor.service). El fichero tiene que quedar
# suyo: si lo dejamos de root, el receptor no podría reemplazarlo en el próximo push y
# el índice se congelaría en la foto de hoy sin que nadie se entere.
DUENO="${BITACORA_ESTADO_DUENO:-bitacora:bitacora}"

REVISAR=no
for arg in "$@"; do
  case "$arg" in
    --revisar) REVISAR=si ;;
    -h|--help) sed -n '2,33p' "$0"; exit 0 ;;
    *) echo "opción desconocida: $arg (usa --revisar o --help)" >&2; exit 2 ;;
  esac
done

command -v gh >/dev/null 2>&1 || {
  echo "ERROR: no encuentro 'gh' aquí." >&2
  echo "       Si el prompt pone root@... estás DENTRO del servidor, donde no hay gh." >&2
  exit 1
}
gh auth status >/dev/null 2>&1 || { echo "ERROR: gh no está autenticado (gh auth login)." >&2; exit 1; }

TMP=$(mktemp -d) || exit 1
trap 'rm -rf "$TMP"' EXIT

# ---------- 1. Lo que hay ahora en el servidor ----------
# Se trae el estado, su huella y la lista de vigilados en UNA conexión. La huella es
# el seguro contra pisar un webhook que llegue mientras tanto (ver punto 4).
ssh -o ConnectTimeout=8 -o BatchMode=yes "$SERVIDOR" \
  "md5sum < '$ESTADO' 2>/dev/null || echo 'VACIO -'; echo '###ESTADO###'; cat '$ESTADO' 2>/dev/null; echo '###INDICE###'; cat '$INDICE' 2>/dev/null" > "$TMP/remoto" 2>/dev/null
[ -s "$TMP/remoto" ] || { echo "ERROR: no pude leer el estado en $SERVIDOR." >&2; exit 1; }

HUELLA=$(head -1 "$TMP/remoto" | awk '{print $1}')
sed -n '/^###ESTADO###$/,/^###INDICE###$/p' "$TMP/remoto" | sed '1d;$d' > "$TMP/estado.viejo"
sed -n '/^###INDICE###$/,$p'                "$TMP/remoto" | sed '1d'    > "$TMP/indice"

grep -v '^#' "$TMP/estado.viejo" | cut -f1 | grep -v '^$' | sort -u > "$TMP/con-datos"
grep -vE '^[[:space:]]*#|^[[:space:]]*$' "$TMP/indice" | awk '{print $1}' | sort -u > "$TMP/vigilados"

echo "servidor: $SERVIDOR:$ESTADO"
echo "  filas ahora: $(wc -l < "$TMP/con-datos") | vigilados en el índice: $(wc -l < "$TMP/vigilados")"

# ---------- 2. La punta de cada repo, en UNA llamada ----------
# GraphQL y no un GET por repo a propósito: 42 repos son 42 peticiones REST, y esto es
# una sola paginada. No está en el presupuesto del hook (esto se lanza a mano), pero un
# script que tarda un minuto se lanza la mitad de veces que uno que tarda ocho segundos.
gh api graphql --paginate -f login="$CUENTA" -f query='
query($login:String!, $endCursor:String) {
  repositoryOwner(login:$login) {
    repositories(first:100, after:$endCursor, ownerAffiliations:OWNER) {
      pageInfo { hasNextPage endCursor }
      nodes { name defaultBranchRef { target { oid } } }
    }
  }
}' --jq '.data.repositoryOwner.repositories.nodes[] | select(.defaultBranchRef != null) | [.name, .defaultBranchRef.target.oid] | @tsv' > "$TMP/github" 2>"$TMP/gh.err"
[ -s "$TMP/github" ] || {
  echo "ERROR: GitHub no devolvió repos -> $(head -c 200 "$TMP/gh.err" | tr '\n' ' ')" >&2
  exit 1
}
echo "  GitHub: $(wc -l < "$TMP/github") repos con rama por defecto"

# ---------- 3. Qué se añade ----------
AHORA=$(date -u '+%Y-%m-%dT%H:%M:%S+00:00')
# La 4ª columna marca de dónde salió la fila. No estorba: el cliente solo lee nombre y
# SHA, y el receptor conserva las columnas extra tal cual — así que la marca desaparece
# sola en cuanto ese repo reciba su primer push de verdad. Sirve para saber, mirando el
# fichero, qué es dato real y qué es foto de arranque.
awk -F'\t' -v ahora="$AHORA" '
  NR==FNR { ya[$1]=1; next }
  !($1 in ya) { print $1 "\t" $2 "\t" ahora "\tsembrado" }
' "$TMP/con-datos" "$TMP/github" | sort > "$TMP/nuevas"

NUEVAS=$(wc -l < "$TMP/nuevas")
if [ "$NUEVAS" -eq 0 ]; then
  echo "  nada que sembrar: todos los repos de GitHub ya tienen fila."
else
  echo "  a sembrar: $NUEVAS repo(s)"
  cut -f1 "$TMP/nuevas" | sed 's/^/    + /'
fi

# Vigilados que seguirán sin datos aunque siembre: no están en la cuenta de GitHub
# (otro dueño, o el nombre del índice no coincide). Se dicen SIEMPRE: son justo los que
# el índice seguirá informando como "no se sabe", y merecen una explicación.
cut -f1 "$TMP/nuevas" | cat - "$TMP/con-datos" | sort -u > "$TMP/tras-sembrar"
HUERFANOS=$(comm -23 "$TMP/vigilados" "$TMP/tras-sembrar")
if [ -n "$HUERFANOS" ]; then
  echo
  echo "  OJO: estos vigilados seguirán SIN DATOS (no aparecen en la cuenta $CUENTA):"
  printf '%s\n' "$HUERFANOS" | sed 's/^/    ? /'
  echo "  O el nombre del índice no coincide con el de GitHub, o el repo es de otro dueño."
fi

if [ "$REVISAR" = si ]; then
  echo
  echo "(modo revisar: no se ha escrito nada)"
  exit 0
fi
[ "$NUEVAS" -eq 0 ] && exit 0

# ---------- 4. Escribir, sin pisar a nadie ----------
# El fichero se arma AQUÍ y se instala allí de un solo golpe. El riesgo es que llegue un
# push justo entre la lectura del punto 1 y este momento: esa fila nueva se perdería.
# Por eso viaja la huella md5 y se vuelve a comprobar EN EL SERVIDOR, en el mismo comando
# que renombra; si no cuadra, no se escribe nada y se avisa de volver a lanzarlo. El
# renombrado es atómico (mismo sistema de ficheros), así que un cliente leyendo a la vez
# ve el fichero entero viejo o el entero nuevo, nunca uno a medias -- igual que hace
# receptor-webhook.py con os.replace.
{
  printf '# nombre\tsha\tvisto-utc — lo escribe receptor-webhook.py\n'
  { grep -v '^#' "$TMP/estado.viejo" | grep -v '^$'; cat "$TMP/nuevas"; } | sort
} > "$TMP/estado.nuevo"

TMP_REMOTO="$(dirname "$ESTADO")/.estado.semilla.$$"
ssh -o ConnectTimeout=8 -o BatchMode=yes "$SERVIDOR" \
  "AHORA=\$(md5sum < '$ESTADO' 2>/dev/null | awk '{print \$1}')
   [ -n \"\$AHORA\" ] || AHORA=VACIO
   if [ \"\$AHORA\" != '$HUELLA' ]; then echo CAMBIO_A_MEDIAS; exit 3; fi
   cat > '$TMP_REMOTO' || exit 1
   chown $DUENO '$TMP_REMOTO' 2>/dev/null || true
   chmod 644 '$TMP_REMOTO' || exit 1
   mv -f '$TMP_REMOTO' '$ESTADO' || exit 1
   echo INSTALADO" < "$TMP/estado.nuevo" > "$TMP/resultado" 2>"$TMP/ssh.err"
CODIGO=$?

if grep -q '^INSTALADO$' "$TMP/resultado" 2>/dev/null; then
  echo
  echo "sembrados $NUEVAS repo(s). El fichero pasa a tener $(( $(wc -l < "$TMP/con-datos") + NUEVAS )) filas."
  echo "Los webhooks siguen mandando: la primera vez que se empuje a uno de estos, su"
  echo "fila se sustituye por el dato real y pierde la marca 'sembrado'."
  exit 0
fi

if grep -q '^CAMBIO_A_MEDIAS$' "$TMP/resultado" 2>/dev/null; then
  echo "ABORTADO: llegó un webhook mientras se preparaba la siembra, así que el estado" >&2
  echo "          cambió bajo los pies. No se ha escrito nada; vuelve a lanzarlo." >&2
  exit 3
fi

echo "ERROR al instalar (código $CODIGO) -> $(head -c 200 "$TMP/ssh.err" | tr '\n' ' ')" >&2
exit 1
