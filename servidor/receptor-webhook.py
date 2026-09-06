#!/usr/bin/env python3
"""Bitácora — receptor de avisos de GitHub.

POR QUÉ EXISTE. Hasta el 29-ago-2026 el índice del arranque lo calculaba CADA cliente:
un `git ls-remote` por repo vigilado, contra GitHub, en cada sesión que se abría. Medido
ese día: 45 s en el PC viejo (Windows) para 10 repos, y el mismo trabajo en este
servidor, en serie y sin paralelismo, 2 s. Lo caro no era la red: era Windows creando un
proceso por repo y negociando un TLS por hijo. Peor aún, el coste crecía con el número
de repos, así que ampliar el catálogo rompía el arranque.

Idea de Oscar: que el trabajo lo haga UNA vez el servidor y el cliente solo lea el
resultado. Esto es la mitad del servidor.

POR QUÉ WEBHOOK Y NO UN TOKEN. La alternativa era que el servidor preguntara a GitHub,
y para repos privados eso pide un token guardado aquí. Se descartó: este servidor ya
guarda los .env de todos los agentes, y añadir una credencial que permita LEER 10 repos
amplía el botín de quien entre. Con webhook el flujo se invierte —GitHub avisa, el
servidor no pregunta— y el único secreto es el de firma, que solo sirve para verificar
que un aviso viene de GitHub. Filtrarlo permitiría enviar avisos falsos de "algo ha
cambiado"; no permite leer una sola línea de código.

QUÉ NO HACE. No consulta a GitHub, no clona nada, no guarda contenido de commits: solo
el SHA de la punta. El "desde tu última sesión" NO se calcula aquí — eso es de cada
máquina, que compara este fichero contra su propio marcador local. Este servidor publica
el estado del mundo, no el estado de nadie.

QUÉ RAMA SE SIGUE — AÑADIDO EL 6-SEP-2026, Y ES UN CAMBIO DE SIGNIFICADO.
Hasta ese día se guardaba `after` de CUALQUIER push sin mirar nunca `ref`, así que un
push a una rama de trabajo pisaba el SHA del repo igual que uno a main. Eso le daba dos
fallos al índice del arranque, que desde ese mismo día compara ese SHA contra el .git del
clon: un falso "al día" con main por detrás (si tu HEAD estaba en esa rama), y un
PENDIENTE que ningún `git pull` apaga — que es el peor de los dos, porque el índice ya no
consume el aviso a propósito y un renglón inapagable enseña a no leer la lista.
  Ahora solo entra el push a la RAMA POR DEFECTO del repo, que viene en el propio payload
(`repository.default_branch`); no se fija {main,master} a mano porque eso congelaría la
fila de cualquier repo cuya rama por defecto sea otra, y una fila congelada se lee igual
que un dato fresco. Lo demás se responde 200 y se anota en el journal: ignorar en
silencio es justo el fallo que este proyecto persigue.
  EL SIGNIFICADO QUE CAMBIA: la 3.ª columna ya no es "cuándo se tocó este repo" sino
"cuándo se movió su rama por defecto". Es la pregunta que hace el índice.
  Y se guarda el REF en una columna más, para que el fichero diga de qué rama es cada
SHA en vez de que haya que saberse esta regla de memoria. Ver actualizar_estado().

ARRANQUE EN FRÍO. Los webhooks solo avisan de pushes FUTUROS, así que estado.txt empieza
vacío y se va llenando según se toca cada repo. Es deliberado: la alternativa (rellenarlo
de golpe) exigiría justo el token que se está evitando. Un repo que aún no aparece se
informa como "sin datos todavía", nunca como "sin cambios" — decir "sin cambios" sin
saberlo es el fallo silencioso que este proyecto lleva un mes persiguiendo.
"""

import hashlib
import hmac
import json
import os
import sys
import tempfile
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, HTTPServer

# En subdirectorio propio, no suelto en /opt/bitacora: el servicio solo tiene permiso de
# escritura sobre esta carpeta, así que BITACORA.md queda fuera de su alcance.
ESTADO = os.environ.get("BITACORA_ESTADO", "/opt/bitacora/estado/estado.txt")
SECRETO_FICHERO = os.environ.get(
    "BITACORA_WEBHOOK_SECRETO", "/opt/bitacora/config/webhook.secret"
)
PUERTO = int(os.environ.get("BITACORA_WEBHOOK_PUERTO", "8011"))
# Un payload de push normal no llega a 100 KB. El tope evita que alguien que descubra
# el endpoint nos haga tragar memoria; se comprueba ANTES de leer el cuerpo.
MAX_CUERPO = 1_000_000


def log(msg):
    """A stdout: systemd lo recoge en el journal. Sin fichero propio que rotar."""
    print(f"{datetime.now(timezone.utc).isoformat(timespec='seconds')} {msg}", flush=True)


def leer_secreto():
    try:
        with open(SECRETO_FICHERO, "r", encoding="utf-8") as f:
            return f.read().strip()
    except OSError as e:
        log(f"FATAL no se puede leer el secreto: {e}")
        sys.exit(1)


SECRETO = leer_secreto()


def firma_valida(cuerpo, cabecera):
    """HMAC-SHA256 como manda GitHub. compare_digest para no filtrar por tiempo."""
    if not cabecera or not cabecera.startswith("sha256="):
        return False
    esperado = "sha256=" + hmac.new(
        SECRETO.encode("utf-8"), cuerpo, hashlib.sha256
    ).hexdigest()
    return hmac.compare_digest(esperado, cabecera)


def refs_que_se_siguen(datos):
    """Los refs cuyo push actualiza la fila del repo. Pura: entra el payload, sale lista.

    Normalmente uno solo: la rama por defecto que declara el propio payload. El respaldo
    a {main, master} es para el día que GitHub deje de mandar ese campo — preferimos
    seguir la rama equivocada en un repo raro antes que dejar de seguir ninguna en todos,
    que es la avería que no se ve.
    """
    repositorio = datos.get("repository") or {}
    rama = repositorio.get("default_branch") or repositorio.get("master_branch") or ""
    if rama:
        return ["refs/heads/" + rama]
    return ["refs/heads/main", "refs/heads/master"]


def actualizar_estado(repo, sha, ref):
    """Reescribe estado.txt entero con el repo actualizado.

    Se escribe a temporal y se renombra: os.replace es atómico en el mismo sistema de
    ficheros, así que un cliente que lea a la vez ve el fichero viejo o el nuevo, nunca
    uno a medias. Importa porque el lector es un `cat` por SSH que puede caer en
    cualquier instante.
    """
    filas = {}
    try:
        with open(ESTADO, "r", encoding="utf-8") as f:
            for linea in f:
                # Saltar la cabecera. Sin esto se reingería a sí misma: "# nombre" pasaba
                # el filtro de abajo (tiene 3 campos y el primero no está vacío), entraba
                # en el diccionario como si fuera un repo llamado "# nombre", y al
                # reescribir se le ponía OTRA cabecera encima. Resultado, visto en vivo el
                # 29-ago-2026 en el servidor: dos cabeceras y una fila basura permanente.
                # No crecía sin límite —está indexada por clave— pero cualquier cliente
                # que no saltara los '#' la habría leído como un repo más.
                if linea.startswith("#"):
                    continue
                partes = linea.rstrip("\n").split("\t")
                if len(partes) >= 2 and partes[0]:
                    filas[partes[0]] = partes[1:]
    except FileNotFoundError:
        pass  # primera vez: se crea abajo

    # La fila se sustituye ENTERA, así que un repo que llevaba la marca `sembrado`
    # (scripts/sembrar-estado.sh) la pierde en cuanto llega su primer push de verdad —
    # que es justo lo que esa marca quería decir. Las filas que NO se tocan conservan sus
    # columnas extra tal cual, arriba.
    filas[repo] = [sha, datetime.now(timezone.utc).isoformat(timespec="seconds"), ref]

    destino_dir = os.path.dirname(ESTADO) or "."
    fd, tmp = tempfile.mkstemp(dir=destino_dir, prefix=".estado.", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            # Cabecera literal, y la comparte scripts/sembrar-estado.sh: si las dos no
            # dicen lo mismo, el fichero cambia de cabecera según quién escribió el último.
            f.write(
                "# nombre\tsha\tvisto-utc\tref — lo escriben"
                " receptor-webhook.py y sembrar-estado.sh\n"
            )
            for nombre in sorted(filas):
                f.write("\t".join([nombre] + filas[nombre]) + "\n")
        # mkstemp crea con 0600 y os.replace conserva el modo del temporal, así que sin
        # esto el fichero solo lo puede leer el usuario 'bitacora'. Funcionaba de milagro:
        # el cliente entra por SSH como root, que lee igual. Esa es una dependencia oculta
        # —el día que alguien entre con otro usuario, el índice se queda sin datos y no
        # sabría por qué—. Aquí no hay nada secreto: nombres de repo y SHA públicos para
        # quien ya tiene acceso al repo. El secreto de firma vive en otro fichero.
        os.chmod(tmp, 0o644)
        os.replace(tmp, ESTADO)
    except Exception:
        os.unlink(tmp)
        raise


class Receptor(BaseHTTPRequestHandler):
    server_version = "bitacora-receptor"
    sys_version = ""  # no anunciar la versión de Python a quien sondee

    def responder(self, codigo, texto):
        cuerpo = texto.encode("utf-8")
        self.send_response(codigo)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(cuerpo)))
        self.end_headers()
        self.wfile.write(cuerpo)

    def do_POST(self):
        try:
            longitud = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            return self.responder(400, "longitud invalida")
        if longitud <= 0 or longitud > MAX_CUERPO:
            return self.responder(400, "longitud fuera de rango")

        cuerpo = self.rfile.read(longitud)

        if not firma_valida(cuerpo, self.headers.get("X-Hub-Signature-256")):
            # Sin detalle en la respuesta: a quien sondea no se le explica por qué falla.
            log(f"RECHAZADO firma invalida desde {self.client_address[0]}")
            return self.responder(401, "no")

        evento = self.headers.get("X-GitHub-Event", "")
        if evento == "ping":
            log("ping OK")
            return self.responder(200, "pong")
        if evento != "push":
            return self.responder(200, "ignorado")

        try:
            datos = json.loads(cuerpo)
            repo = datos["repository"]["name"]
            sha = datos["after"]
            ref = datos["ref"]
        except (ValueError, KeyError, TypeError) as e:
            log(f"ERROR payload de push ilegible: {e}")
            return self.responder(400, "payload ilegible")

        # Solo la rama por defecto. Un push a una rama de trabajo NO es la punta del
        # repo, y guardarlo como si lo fuera es la avería del 6-sep (ver la cabecera).
        # Se responde 200 —para GitHub la entrega fue bien y no hay nada que reintentar—
        # pero se deja dicho en el journal cuál se ignoró y cuál se sigue.
        seguidos = refs_que_se_siguen(datos)
        if ref not in seguidos:
            log(f"ignorado {repo} ref={ref or '(vacio)'} (se sigue {seguidos[0]})")
            return self.responder(200, "ignorado: no es la rama por defecto")

        # Un borrado de rama manda after = todo ceros: no es una punta nueva.
        if not sha or set(sha) == {"0"}:
            return self.responder(200, "sin sha")

        try:
            actualizar_estado(repo, sha, ref)
        except OSError as e:
            log(f"ERROR no se pudo escribir {ESTADO}: {e}")
            return self.responder(500, "error al guardar")

        log(f"OK {repo} {ref} -> {sha[:12]}")
        return self.responder(200, "ok")

    def do_GET(self):
        # Sirve para comprobar que el servicio está vivo sin mandar un webhook.
        self.responder(200, "receptor de bitacora vivo\n")

    def log_message(self, fmt, *args):
        pass  # el log lo llevamos nosotros; el de serie es ruido


if __name__ == "__main__":
    # Solo loopback a propósito: la puerta pública la pone nginx, que además termina el
    # TLS. Este proceso nunca debe escuchar en 0.0.0.0.
    servidor = HTTPServer(("127.0.0.1", PUERTO), Receptor)
    log(f"escuchando en 127.0.0.1:{PUERTO}, estado en {ESTADO}")
    servidor.serve_forever()
