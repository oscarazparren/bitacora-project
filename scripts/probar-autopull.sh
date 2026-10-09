#!/bin/bash
# Bitácora — BANCO DE PRUEBAS de sincronizar_clon() de hooks/sessionstart-leer.sh
# (la auto-actualización de clones atrasados de la sección 0).
#
# POR QUÉ EXISTE: el 9-oct-2026 el PC viejo tenía lizar-clon 47 commits por detrás y el
# hook solo avisaba. Ahora actualiza, y una función que ESCRIBE en los repos de Oscar en
# cada arranque tiene que demostrar dos cosas: que actualiza lo que debe, y SOBRE TODO que
# no toca nada más (ni siquiera un fichero IGNORADO, que git pisa sin avisar). Cada caso comprueba el estado final del clon, no solo lo que dice la
# función.
#
# LO QUE SE PRUEBA ES EL HOOK REAL: la función se extrae en vivo del fichero.
#
# Uso:  scripts/probar-autopull.sh [/ruta/al/hook.sh]      Sale 0 si todo pasa.
# No toca nada fuera de su directorio temporal.

set -uo pipefail
AQUI="$(cd "$(dirname "$0")" && pwd)"
HOOK="${1:-$AQUI/../hooks/sessionstart-leer.sh}"
[ -f "$HOOK" ] || { echo "no encuentro el hook: $HOOK" >&2; exit 2; }

FUNC=$(awk '/^sincronizar_clon\(\) \{/ {f=1} f {print} f && /^}/ {exit}' "$HOOK")
[ -n "$FUNC" ] || { echo "no encuentro sincronizar_clon en $HOOK" >&2; exit 2; }
tope() { printf '10'; }                       # el reloj global del hook no existe aquí
eval "$FUNC"

T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
G() { git -C "$1" "${@:2}" >/dev/null 2>&1; }

OK=0; MAL=0
# esperar <nombre> <estado esperado> <HEAD debe ser: igual|avanzado> <clon> <HEAD antes>
verifica() {
  local nombre="$1" esperado="$2" cabeza="$3" d="$4" antes="$5" r est ahora
  r=$(sincronizar_clon "$d"); est="${r%%$'\t'*}"; ahora=$(git -C "$d" rev-parse HEAD)
  if [ "$est" != "$esperado" ]; then echo "  MAL  $nombre: dijo $est, esperaba $esperado"; MAL=$((MAL+1)); return 1; fi
  if [ "$cabeza" = igual ] && [ "$ahora" != "$antes" ]; then echo "  MAL  $nombre: HEAD se movió y no debía"; MAL=$((MAL+1)); return 1; fi
  if [ "$cabeza" = avanzado ] && [ "$ahora" = "$antes" ]; then echo "  MAL  $nombre: HEAD NO avanzó"; MAL=$((MAL+1)); return 1; fi
  echo "  ok   $nombre  ($r)" | tr '\t' ' '; OK=$((OK+1)); return 0
}

# Un remoto con 3 commits y, por caso, un clon 2 commits por detrás.
nuevo_caso() {   # $1 = nombre del caso; deja $T/$1/{remoto.git,clon,avanza}
  local c="$T/$1"; mkdir -p "$c"
  git init -q --bare -b main "$c/remoto.git"
  git clone -q "$c/remoto.git" "$c/avanza" 2>/dev/null
  G "$c/avanza" checkout -q -b main
  echo uno > "$c/avanza/a.txt"; G "$c/avanza" add .; G "$c/avanza" commit -qm uno
  G "$c/avanza" push -q origin main
  git clone -q "$c/remoto.git" "$c/clon" 2>/dev/null
  echo dos > "$c/avanza/b.txt"; G "$c/avanza" add .; G "$c/avanza" commit -qm dos
  echo tres > "$c/avanza/c.txt"; G "$c/avanza" add .; G "$c/avanza" commit -qm tres
  G "$c/avanza" push -q origin main
}
cabeza() { git -C "$1/clon" rev-parse HEAD; }

echo "Banco de sincronizar_clon  ($HOOK)"

nuevo_caso limpio;  H=$(cabeza "$T/limpio")
verifica "limpio y solo por detrás -> se actualiza" ACTUALIZADO avanzado "$T/limpio/clon" "$H"
[ "$(git -C "$T/limpio/clon" rev-parse HEAD)" = "$(git -C "$T/limpio/avanza" rev-parse HEAD)" ] \
  && { echo "  ok   quedó EXACTAMENTE en la punta del remoto"; OK=$((OK+1)); } \
  || { echo "  MAL  no quedó en la punta del remoto"; MAL=$((MAL+1)); }
verifica "ya al día -> sin cambio" SINCAMBIO igual "$T/limpio/clon" "$(cabeza "$T/limpio")"

nuevo_caso sucio; H=$(cabeza "$T/sucio"); echo "mi cambio" >> "$T/sucio/clon/a.txt"
verifica "fichero versionado modificado -> NO se toca" SUCIO igual "$T/sucio/clon" "$H"
[ "$(tail -1 "$T/sucio/clon/a.txt")" = "mi cambio" ] \
  && { echo "  ok   el cambio local sigue intacto"; OK=$((OK+1)); } \
  || { echo "  MAL  se perdió el cambio local"; MAL=$((MAL+1)); }

nuevo_caso indice; H=$(cabeza "$T/indice"); echo "x" > "$T/indice/clon/z.txt"; G "$T/indice/clon" add z.txt
verifica "cambio ya en el índice (git add) -> NO se toca" SUCIO igual "$T/indice/clon" "$H"

nuevo_caso sinseguir; H=$(cabeza "$T/sinseguir"); echo "x" > "$T/sinseguir/clon/ajeno.txt"
verifica "fichero sin seguir que no estorba -> se actualiza" ACTUALIZADO avanzado "$T/sinseguir/clon" "$H"
[ -f "$T/sinseguir/clon/ajeno.txt" ] && { echo "  ok   el fichero sin seguir sigue ahí"; OK=$((OK+1)); } || { echo "  MAL  desapareció"; MAL=$((MAL+1)); }

nuevo_caso estorba; H=$(cabeza "$T/estorba"); echo "MIO" > "$T/estorba/clon/b.txt"
verifica "fichero sin seguir que PISARÍA el avance -> NO se toca" PISARIA igual "$T/estorba/clon" "$H"
[ "$(cat "$T/estorba/clon/b.txt")" = "MIO" ] && { echo "  ok   el fichero sin seguir conserva su contenido"; OK=$((OK+1)); } || { echo "  MAL  se pisó el fichero"; MAL=$((MAL+1)); }

nuevo_caso diverge; echo propio > "$T/diverge/clon/p.txt"; G "$T/diverge/clon" add .; G "$T/diverge/clon" commit -qm propio; H=$(cabeza "$T/diverge")
verifica "divergido -> NO se toca" DIVERGE igual "$T/diverge/clon" "$H"

nuevo_caso adelante; G "$T/adelante/clon" pull -q --ff-only; echo propio > "$T/adelante/clon/p.txt"; G "$T/adelante/clon" add .; G "$T/adelante/clon" commit -qm propio; H=$(cabeza "$T/adelante")
verifica "solo adelantado (sin subir) -> avisa" ADELANTE igual "$T/adelante/clon" "$H"

nuevo_caso suelto; G "$T/suelto/clon" checkout -q --detach; H=$(cabeza "$T/suelto")
verifica "HEAD desprendido -> NO se toca" DESPRENDIDO igual "$T/suelto/clon" "$H"

nuevo_caso sinup; G "$T/sinup/clon" checkout -q -b local; H=$(cabeza "$T/sinup")
verifica "rama sin upstream -> NO se toca" SINUPSTREAM igual "$T/sinup/clon" "$H"

nuevo_caso caido; H=$(cabeza "$T/caido"); rm -rf "$T/caido/remoto.git"
verifica "remoto inalcanzable -> NO se toca, y lo dice" FETCHFALLO igual "$T/caido/clon" "$H"

nuevo_caso barra
G "$T/barra/avanza" checkout -q -b feature/x; echo f > "$T/barra/avanza/f.txt"; G "$T/barra/avanza" add .; G "$T/barra/avanza" commit -qm f; G "$T/barra/avanza" push -q origin feature/x
G "$T/barra/clon" fetch -q; G "$T/barra/clon" checkout -q -b feature/x origin/feature/x
G "$T/barra/avanza" checkout -q feature/x; echo g > "$T/barra/avanza/g.txt"; G "$T/barra/avanza" add .; G "$T/barra/avanza" commit -qm g; G "$T/barra/avanza" push -q origin feature/x
H=$(cabeza "$T/barra")
verifica "rama con barra (origin/feature/x) -> se actualiza" ACTUALIZADO avanzado "$T/barra/clon" "$H"

# El caso destructivo que halló la auditoría: un .env IGNORADO que el avance crearía versionado.
nuevo_caso ignorado
echo ".env" >> "$T/ignorado/clon/.git/info/exclude"      # ignorado sin commitear nada
G "$T/ignorado/avanza" pull -q --ff-only; echo "PLANTILLA=0" > "$T/ignorado/avanza/.env"; G "$T/ignorado/avanza" add -f .env; G "$T/ignorado/avanza" commit -qm env; G "$T/ignorado/avanza" push -q origin main
echo "SECRETO_LOCAL=1" > "$T/ignorado/clon/.env"; H=$(cabeza "$T/ignorado")
verifica "fichero IGNORADO que el avance pisaría -> NO se toca" PISARIA igual "$T/ignorado/clon" "$H"
[ "$(cat "$T/ignorado/clon/.env")" = "SECRETO_LOCAL=1" ] && { echo "  ok   el .env ignorado conserva su contenido"; OK=$((OK+1)); } || { echo "  MAL  SE PISÓ EL .env IGNORADO"; MAL=$((MAL+1)); }

# Un hook post-merge del clon NO debe ejecutarse durante el arranque.
nuevo_caso gancho; H=$(cabeza "$T/gancho"); mkdir -p "$T/gancho/clon/.git/hooks"
printf '#!/bin/sh\ntouch "%s/EJECUTADO"\n' "$T/gancho" > "$T/gancho/clon/.git/hooks/post-merge"; chmod +x "$T/gancho/clon/.git/hooks/post-merge"
verifica "con hook post-merge en el clon -> se actualiza" ACTUALIZADO avanzado "$T/gancho/clon" "$H"
[ ! -e "$T/gancho/EJECUTADO" ] && { echo "  ok   el post-merge NO se ejecutó"; OK=$((OK+1)); } || { echo "  MAL  se ejecutó el post-merge del clon"; MAL=$((MAL+1)); }

# Ruta con espacios.
nuevo_caso "con espacios"; H=$(cabeza "$T/con espacios")
verifica "ruta con espacios -> se actualiza" ACTUALIZADO avanzado "$T/con espacios/clon" "$H"

echo; echo "$OK bien, $MAL mal"
[ "$MAL" -eq 0 ]
