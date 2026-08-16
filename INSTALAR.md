# Instalar Bitácora en un dispositivo

Son tres pasos y no toca producción.

## El problema que resuelve

Cuando se trabaja con agentes desde varias máquinas o varias cuentas, **la memoria de
cada agente es local a su máquina y no se sincroniza**. Uno despliega algo y el otro no
se entera — y lo afirma con seguridad, que es lo peligroso.

Pasó de verdad: se desplegó un servicio desde un dispositivo y el agente del otro seguía
afirmando que ese servicio no existía.

## Cómo funciona

Un hook decide solo qué enseñar al empezar cada sesión, según dónde estés:

| Dónde estás | Qué te enseña |
|---|---|
| Un repo con bitácora | El registro de ese repo (**lo crea si no existe**) |
| Un repo de flota, o fuera de un repo | El registro de flota del servidor |
| Una carpeta ignorada (`repos/`, `tools/`, `node_modules/`) | Nada, y no crea ficheros |

Dos ámbitos porque cubren cosas distintas: el **del repo** viaja por git con el
proyecto; el **de flota** vive aparte porque la infraestructura abarca varios servidores
y varios repos, y no cabe en ninguno.

## Requisitos

- `bash`, `git` y `node` en el PATH
- Para la bitácora de flota: acceso SSH sin contraseña al servidor
  (`ssh <alias> "hostname"` debe responder)

---

## Paso 1 — copiar el hook y configurar la máquina

```bash
cp hooks/sessionstart-leer.sh ~/.claude/
chmod +x ~/.claude/sessionstart-leer.sh
cp bitacora.conf.example ~/.claude/bitacora.conf
```

Edita `~/.claude/bitacora.conf`. Lo mínimo es la etiqueta, que identifica quién escribe
cada entrada — usa algo distinto en cada máquina (`portatil`, `sobremesa`, `mac`):

```sh
BITACORA_ETIQUETA="portatil"
```

Si vas a usar bitácora de flota, rellena además `BITACORA_FLOTA_SSH`,
`BITACORA_FLOTA_RUTA` y `BITACORA_FLOTA_REPOS`. Si no, déjalos vacíos.

## Paso 2 — registrar el hook

Lee primero `~/.claude/settings.json` y **fusiona** — no lo sobrescribas, puede tener
modelo, permisos u otros hooks. Añade dentro de `"hooks"` (créalo si no existe):

```json
"SessionStart": [
  {
    "hooks": [
      {
        "type": "command",
        "statusMessage": "Leyendo bitácora...",
        "timeout": 20,
        "command": "bash \"$HOME/.claude/sessionstart-leer.sh\" 2>/dev/null || true"
      }
    ]
  }
]
```

### ⚠️ No instales un hook `Stop`

Se probó y se retiró el mismo día. `Stop` **no** se dispara al terminar la sesión: se
dispara **cada vez que el agente termina de responder**, así que el aviso sale en todos
los turnos y se lee como una tarea pendiente que nunca se cierra.

Si algún día hace falta avisar «al terminar», el evento es `SessionEnd`.

## Paso 3 — verificar de verdad, no darlo por hecho

Ejecuta el hook a mano desde dos sitios distintos y comprueba que cambia:

```bash
cd ~ && bash ~/.claude/sessionstart-leer.sh | head -c 300
```

Debe imprimir un JSON que empieza por `{"systemMessage":`. Si sale vacío estando en un
repo, algo falla: revisa la configuración y que `node` esté en el PATH. Si esperabas la
bitácora de flota y no aparece, comprueba que el SSH funciona desde esta máquina.

Los hooks `SessionStart` no pueden dispararse dentro de la sesión actual: hay que
reiniciarla una vez para que se cargue.

## Paso 4 — anotar que lo instalaste

Es la primera entrada y sirve de prueba de que el ciclo completo funciona:

```bash
printf -- "- Bitácora instalada también en este dispositivo.\n" | ssh <servidor> "bash /ruta/anotar.sh '[TU-ETIQUETA] bitácora instalada'"
```

O, si es la bitácora de un repo, añade la entrada bajo el `---` de su `BITACORA.md` y haz
commit.

---

## Cómo anotar en el día a día

Hazlo **sin esperar a que nadie lo pida**, siempre que la sesión toque algo que otro
dispositivo deba saber. Un hook no puede hacerlo por ti: los hooks ejecutan comandos, no
redactan.

**Infraestructura** (despliegues, contenedores, dominios, DNS, altas de cliente):

```bash
printf -- "- Qué hice, con rutas y puertos concretos.\n- Qué hay que vigilar después.\n" | ssh <servidor> "bash /ruta/anotar.sh '[TU-ETIQUETA] titular corto'"
```

**Trabajo dentro de un repo:** añade la entrada bajo el `---` del `BITACORA.md` de ese
repo y **haz commit** — el commit es lo que la lleva a los demás dispositivos.

Nunca metas credenciales. `anotar.sh` rechaza las que reconoce, pero no puede reconocerlas
todas, y una bitácora es un fichero compartido y versionado: lo que entra, se queda.
