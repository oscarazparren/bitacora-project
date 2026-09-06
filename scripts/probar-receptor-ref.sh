#!/bin/bash
# Bitácora — BANCO DE PRUEBAS de servidor/receptor-webhook.py: qué pushes entran
# en estado.txt y qué se guarda de ellos.
#
# ============================================================================
# POR QUÉ EXISTE ESTE FICHERO
# ============================================================================
#
# Hasta el 6-sep-2026 el receptor guardaba `after` de CUALQUIER push y no miraba
# nunca `ref`. Un push a una rama de trabajo pisaba el SHA del repo igual que uno
# a main, y desde ese mismo día el índice del arranque compara ese SHA contra el
# .git del clon: salía un falso "al día" con main por detrás, o un PENDIENTE que
# ningún `git pull` apaga. Lo segundo es lo peor, porque el índice ya no consume
# el aviso a propósito y un renglón inapagable enseña a no leer la lista entera.
#
# El clasificador del cliente ya tenía banco (probar-indice-clon.sh) y el
# receptor no tenía ninguno — y es el que se DESPLIEGA A UN SERVIDOR, donde un
# fallo no se ve: no hay pantalla, el journal no lo lee nadie de madrugada, y el
# síntoma aparece días después y en otra máquina.
#
# SE PRUEBA EL RECEPTOR DE VERDAD, arrancado en un puerto libre, con su fichero
# de estado y su secreto en un temporal, y hablándole por HTTP con firmas HMAC
# como las de GitHub. No se importa una copia de sus funciones: si el fallo
# estuviera en el orden de las comprobaciones o en el reparto de las cabeceras,
# una prueba de laboratorio no lo vería.
#
# Uso:
#   scripts/probar-receptor-ref.sh                     # el de servidor/
#   scripts/probar-receptor-ref.sh /ruta/receptor.py   # otra copia
# Sale 0 si todo pasa. No toca nada fuera de su temporal, ni la red, ni el servidor.

set -uo pipefail

AQUI="$(cd "$(dirname "$0")" && pwd)"
RECEPTOR="${1:-$AQUI/../servidor/receptor-webhook.py}"
SEMBRADOR="$AQUI/sembrar-estado.sh"
[ -f "$RECEPTOR" ] || { echo "no encuentro el receptor: $RECEPTOR" >&2; exit 2; }

PY=python3
command -v python3 >/dev/null 2>&1 || PY=python
command -v "$PY" >/dev/null 2>&1 || { echo "hace falta python" >&2; exit 2; }

TMP=$(mktemp -d 2>/dev/null) || { echo "mktemp -d falló" >&2; exit 2; }
PID=""
limpiar() {
  if [ -n "$PID" ]; then kill "$PID" 2>/dev/null; wait "$PID" 2>/dev/null; fi
  rm -rf "$TMP"
}
trap limpiar EXIT

ESTADO="$TMP/estado.txt"
SECRETO="del-banco-no-es-el-de-produccion"
printf '%s' "$SECRETO" > "$TMP/secreto"

# --- El cliente: firma como GitHub y lee el fichero resultante ---------------
cat > "$TMP/cliente.py" <<'FINPY'
import hashlib, hmac, io, socket, sys, time, json
import urllib.error, urllib.request

TAB = chr(9)


def esperar(puerto):
    for _ in range(100):
        s = socket.socket()
        s.settimeout(0.2)
        try:
            s.connect(("127.0.0.1", puerto))
            s.close()
            return 0
        except OSError:
            time.sleep(0.1)
    return 1


def push(puerto, secreto, repo, sha, ref, rama, firmar):
    payload = {"ref": ref, "after": sha, "repository": {"name": repo}}
    if rama != "-":
        payload["repository"]["default_branch"] = rama
    cuerpo = json.dumps(payload).encode("utf-8")
    if firmar:
        firma = "sha256=" + hmac.new(secreto.encode("utf-8"), cuerpo, hashlib.sha256).hexdigest()
    else:
        firma = "sha256=" + "0" * 64
    pet = urllib.request.Request(
        "http://127.0.0.1:%d/" % puerto,
        data=cuerpo,
        headers={
            "Content-Type": "application/json",
            "X-GitHub-Event": "push",
            "X-Hub-Signature-256": firma,
        },
    )
    try:
        with urllib.request.urlopen(pet, timeout=5) as r:
            print("%d %s" % (r.status, r.read().decode("utf-8")))
    except urllib.error.HTTPError as e:
        print("%d %s" % (e.code, e.read().decode("utf-8")))
    return 0


def _filas(estado):
    try:
        texto = io.open(estado, encoding="utf-8").read()
    except OSError:
        return {}, ""
    filas = {}
    cabecera = ""
    for linea in texto.split(chr(10)):
        if not linea:
            continue
        if linea.startswith("#"):
            cabecera = cabecera or linea
            continue
        partes = linea.split(TAB)
        filas[partes[0]] = partes
    return filas, cabecera


def campo(estado, repo, n):
    filas = _filas(estado)[0]
    if repo not in filas:
        print("(sin fila)")
        return 0
    partes = filas[repo]
    print(partes[n - 1] if 0 < n <= len(partes) else "(sin campo)")
    return 0


def ncampos(estado, repo):
    filas = _filas(estado)[0]
    print(len(filas[repo]) if repo in filas else 0)
    return 0


def cabecera_del_sembrador(ruta):
    for linea in io.open(ruta, encoding="utf-8").read().split(chr(10)):
        if linea.lstrip().startswith("printf ") and "# nombre" in linea:
            crudo = linea.split(chr(39))[1]
            print(crudo.replace(chr(92) + "t", TAB).replace(chr(92) + "n", ""))
            return 0
    print("(no encuentro el printf de la cabecera en " + ruta + ")")
    return 1


if __name__ == "__main__":
    orden = sys.argv[1]
    if orden == "esperar":
        sys.exit(esperar(int(sys.argv[2])))
    if orden == "push":
        sys.exit(push(int(sys.argv[2]), sys.argv[3], sys.argv[4], sys.argv[5],
                      sys.argv[6], sys.argv[7], len(sys.argv) < 9))
    if orden == "campo":
        sys.exit(campo(sys.argv[2], sys.argv[3], int(sys.argv[4])))
    if orden == "ncampos":
        sys.exit(ncampos(sys.argv[2], sys.argv[3]))
    if orden == "cabecera":
        print(_filas(sys.argv[2])[1])
        sys.exit(0)
    if orden == "cabecera-sembrador":
        sys.exit(cabecera_del_sembrador(sys.argv[2]))
    print("orden desconocida: " + orden)
    sys.exit(2)
FINPY

PUERTO=$("$PY" -c "import socket; s=socket.socket(); s.bind(('127.0.0.1',0)); print(s.getsockname()[1]); s.close()")

BITACORA_ESTADO="$ESTADO" BITACORA_WEBHOOK_SECRETO="$TMP/secreto" BITACORA_WEBHOOK_PUERTO="$PUERTO" \
  "$PY" "$RECEPTOR" > "$TMP/journal" 2>&1 &
PID=$!
"$PY" "$TMP/cliente.py" esperar "$PUERTO" || {
  echo "el receptor no llegó a escuchar en 127.0.0.1:$PUERTO" >&2
  echo "--- su salida ---" >&2
  cat "$TMP/journal" >&2
  exit 2
}

push()    { "$PY" "$TMP/cliente.py" push "$PUERTO" "$SECRETO" "$@"; }
campo()   { "$PY" "$TMP/cliente.py" campo "$ESTADO" "$1" "$2"; }
ncampos() { "$PY" "$TMP/cliente.py" ncampos "$ESTADO" "$1"; }

PASA=0
FALLA=0
espera() {  # <nombre> <esperado> <obtenido>
  if [ "$2" = "$3" ]; then
    printf '  ok    %s\n' "$1"; PASA=$((PASA + 1))
  else
    printf '  FALLA %s\n        esperaba: %s\n        salio:    %s\n' "$1" "$2" "$3"
    FALLA=$((FALLA + 1))
  fi
}
contiene() {  # <nombre> <trozo> <texto>
  case "$3" in
    *"$2"*) printf '  ok    %s\n' "$1"; PASA=$((PASA + 1)) ;;
    *) printf '  FALLA %s\n        esperaba que contuviera: %s\n        salio: %s\n' "$1" "$2" "$3"
       FALLA=$((FALLA + 1)) ;;
  esac
}

echo
echo "Banco del receptor de webhooks (que pushes entran y que se guarda)"
echo "Receptor: $RECEPTOR"
echo "Puerto de usar y tirar: $PUERTO"
echo

A=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
B=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
C=cccccccccccccccccccccccccccccccccccccccc
CEROS=0000000000000000000000000000000000000000

# --- 1. el caso normal ------------------------------------------------------
R=$(push repo1 "$A" refs/heads/main main)
contiene "1a push a la rama por defecto -> 200 ok" "200 ok" "$R"
espera   "1b se guarda el SHA"   "$A"              "$(campo repo1 2)"
espera   "1c y se guarda el ref" "refs/heads/main" "$(campo repo1 4)"
espera   "1d cuatro columnas"    "4"               "$(ncampos repo1)"

# --- 2. EL FALLO DEL 6-SEP: una rama de trabajo NO es la punta del repo ------
R=$(push repo1 "$B" refs/heads/faena main)
contiene "2a push a una rama de trabajo -> ignorado" "ignorado" "$R"
espera   "2b y NO pisa el SHA de la rama por defecto" "$A" "$(campo repo1 2)"

# --- 3. las etiquetas tampoco -----------------------------------------------
R=$(push repo1 "$B" refs/tags/v1.0 main)
contiene "3a push de una etiqueta -> ignorado" "ignorado" "$R"
espera   "3b y no pisa nada"                   "$A"       "$(campo repo1 2)"

# --- 4 y 5. rama por defecto que no es main ni master -----------------------
# Por esto se mira repository.default_branch y no se fija main/master a mano:
# con la lista fija, la fila de este repo no se actualizaria JAMAS, y una fila
# congelada se lee exactamente igual que un dato fresco.
R=$(push repo2 "$B" refs/heads/trunk trunk)
contiene "4a push a trunk, que es SU rama por defecto -> ok" "200 ok" "$R"
espera   "4b se guarda con su ref" "refs/heads/trunk" "$(campo repo2 4)"
R=$(push repo2 "$C" refs/heads/main trunk)
contiene "5a main NO es la rama por defecto de ese repo -> ignorado" "ignorado" "$R"
espera   "5b y no pisa a trunk" "$B" "$(campo repo2 2)"

# --- 6. borrado de la rama por defecto: after a ceros ------------------------
R=$(push repo1 "$CEROS" refs/heads/main main)
contiene "6a borrado de rama -> sin sha" "sin sha" "$R"
espera   "6b y la fila queda intacta"    "$A"      "$(campo repo1 2)"

# --- 7. firma invalida ------------------------------------------------------
R=$(push repo1 "$B" refs/heads/main main nofirma)
contiene "7a firma invalida -> 401"    "401" "$R"
espera   "7b y la fila queda intacta"  "$A"  "$(campo repo1 2)"

# --- 8. sin default_branch en el payload: respaldo a main/master ------------
R=$(push repo3 "$A" refs/heads/master -)
contiene "8a sin rama declarada, master -> ok" "200 ok" "$R"
R=$(push repo3 "$B" refs/heads/faena -)
contiene "8b sin rama declarada, faena -> ignorado" "ignorado" "$R"
espera   "8c y no pisa"                             "$A"       "$(campo repo3 2)"

# --- 9. las filas que NO se tocan conservan sus columnas extra ---------------
# La marca "sembrado" la escribe scripts/sembrar-estado.sh. Si el receptor la
# perdiera al reescribir el fichero entero, se borraria la marca de todas las
# filas sembradas cada vez que alguien empuja a un repo cualquiera.
printf 'viejo\t%s\t2026-09-01T21:08:54+00:00\tsembrado\n' "$C" >> "$ESTADO"
R=$(push repo1 "$B" refs/heads/main main)
contiene "9a otro push cualquiera -> ok" "200 ok"  "$R"
espera   "9b la fila sembrada sigue ahi" "$C"       "$(campo viejo 2)"
espera   "9c con su marca intacta"       "sembrado" "$(campo viejo 4)"

# --- 10. y la fila sembrada del propio repo se sustituye entera -------------
R=$(push viejo "$A" refs/heads/main main)
contiene "10a push sobre una fila sembrada -> ok"  "200 ok"          "$R"
espera   "10b pierde la marca y gana el ref"       "refs/heads/main" "$(campo viejo 4)"
espera   "10c y no arrastra columnas viejas"       "4"               "$(ncampos viejo)"

# --- 11. la cabecera es la MISMA que escribe el otro escritor ---------------
# Los dos escriben el fichero ENTERO. Si no dicen lo mismo, la cabecera cambia
# segun quien escribio el ultimo y deja de servir para saber que hay en cada
# columna. Se saca del printf del propio sembrador, no de una copia pegada aqui.
if [ -f "$SEMBRADOR" ]; then
  espera "11 la cabecera coincide con la de sembrar-estado.sh" \
    "$("$PY" "$TMP/cliente.py" cabecera-sembrador "$SEMBRADOR")" \
    "$("$PY" "$TMP/cliente.py" cabecera "$ESTADO")"
else
  echo "  (11 saltado: no encuentro $SEMBRADOR)"
fi

# --- 12. la doble entrega es idempotente ------------------------------------
# Cada push llega DOS veces: por la GitHub App de la cuenta y por el webhook del
# repo (BITACORA.md, 6-sep, [PC viejo]). Es a proposito, y tiene que dar lo mismo.
push repo9 "$A" refs/heads/main main > /dev/null
ANTES="$(campo repo9 2)|$(campo repo9 4)"
push repo9 "$A" refs/heads/main main > /dev/null
espera "12 el mismo push dos veces deja la misma fila" "$ANTES" "$(campo repo9 2)|$(campo repo9 4)"

# --- 13. lo ignorado se dice en el journal ----------------------------------
# Un push descartado en silencio es indistinguible de uno que nunca llego, y ese
# es justo el modo de fallo que este banco existe para que no vuelva.
IGNORADOS=$(grep -c "ignorado" "$TMP/journal" 2>/dev/null || true)
[ -n "$IGNORADOS" ] || IGNORADOS=0
if [ "$IGNORADOS" -ge 4 ]; then
  printf '  ok    13 los descartes quedan anotados (%s lineas)\n' "$IGNORADOS"; PASA=$((PASA + 1))
else
  printf '  FALLA 13 solo %s linea(s) de descarte en el journal; esperaba 4 o mas\n' "$IGNORADOS"
  FALLA=$((FALLA + 1))
fi

echo
echo "  $PASA ok, $FALLA falla(s)"
[ "$FALLA" -eq 0 ]
