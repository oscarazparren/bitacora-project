# Bitácora

**Capa de continuidad de contexto para equipos que trabajan con agentes.**

El contexto de trabajo no viaja. Viaja el código, viajan los ficheros, viaja el historial
de Git — pero la razón por la que se tomó una decisión, lo que se intentó y falló, y el
estado real de lo que está a medias, muere cuando se cierra la sesión.

Esto era menor cuando quien escribía código era una persona que se acordaba. Con agentes
deja de serlo: cada sesión arranca en cero, y el coste de reconstruir el contexto crece
con el número de sesiones y de agentes implicados.

Bitácora es un registro de estado y decisiones, escrito a mano y versionado junto al
código, que viaja entre las máquinas de quien trabaja sobre los mismos repos. Al abrir
sesión un hook **no lo inyecta**: avisa de lo que no cuadra entre máquinas y apunta al
fichero, para que lo abra quien lo necesite.

> **No es memoria: es trazabilidad de intención.**
>
> Y tampoco es continuidad entre sesiones. Se intentó, se midió lo que costaba, y salía
> más caro que el problema que resolvía — ver **Estado**, más abajo.

---

## Qué captura que otras herramientas no

Un `git diff` responde *qué* cambió. No responde lo que bloquea a la siguiente sesión:

- Por qué se eligió este enfoque y **cuáles se descartaron**.
- Qué se probó ya y no funcionó — el coste más caro es repetir un callejón sin salida.
- Qué está a medias y qué está terminado, distinción que el código no expresa.
- **Qué decisiones siguen vigentes y cuáles se revocaron.**

El campo diferencial es `descartado`. Ninguna otra herramienta lo captura, y es lo que
impide que la siguiente sesión repita el trabajo de la anterior. El esquema completo está
en **[ESQUEMA.md](ESQUEMA.md)**.

| Alternativa | Dónde falla |
|---|---|
| Ficheros de instrucciones (`CLAUDE.md`, reglas de editor) | Estáticos. Describen *cómo* trabajar, no *qué ha pasado* |
| Memoria del proveedor | Atada a una cuenta y una conversación. No cruza cuentas, equipos, máquinas ni modelos |
| Servidores MCP de memoria | Sin esquema compartido: la recuperación es imprevisible |
| Resúmenes de sesión | Narran la conversación. Se pierde lo descartado |
| ADRs | Ceremonia alta, escritos a posteriori, sin estado ni revocación. Nadie los lee al arrancar |

---

## Dónde vive cada bitácora

| Ámbito | Dónde | Por qué |
|---|---|---|
| **Proyecto** | `.bitacora/` dentro del repo de ese proyecto | Solo ahí viaja con el código, se versiona con él y se revisa en el mismo pull request |
| **Flota** | Su propio repositorio, **privado** | Infraestructura y despliegues no pertenecen a ningún repo: cruzan varios |

Regla corta: si «¿de qué repo es esto?» tiene una respuesta, va en su `.bitacora/`.
Si es «de varios» o «de ninguno», va a flota.

⚠️ **Los registros no son públicos.** Este repositorio contiene el producto, no
registros de nadie. Un registro real contiene el mapa operativo de tu infraestructura —
proveedor, despliegues, rutas, qué corre dónde. Nada de eso es una credencial, y
precisamente por eso es fácil publicarlo sin darse cuenta.

---

## Estado

> ### ⚠️ El 7 de septiembre de 2026 este proyecto se replegó, a propósito
>
> Se midió lo que costaba (la fase de medición del plan, pendiente desde agosto) y el
> número no justificaba seguir construyendo:
>
> - La maquinaria había costado **~160 $ en 5 días** de trabajo, contra **~700 $** de
>   todos los repos que dan dinero en el mismo periodo. Era la 3.ª partida más cara de
>   la flota, por delante de cualquier aplicación real por separado.
> - El techo de lo que la lectura selectiva podía ahorrar eran **15-25 $ en dos meses**.
>   La mejora costaba varios múltiplos de su propio beneficio máximo.
> - Las últimas 12 entradas de esta bitácora eran 12 de 12 sobre su propia fontanería.
>
> **La bitácora dejó de ser canal entre sesiones y se quedó como canal entre máquinas.**
> El hook ya no inyecta ningún registro: avisa de descuadres y **apunta** al fichero. El
> sobre de arranque pasó de 16.364 bytes a 3.541.
>
> El razonamiento entero, con las tablas, está en la entrada del 2026-09-07 de
> [BITACORA.md](BITACORA.md). **Si vienes buscando el sistema jerárquico que describen
> los documentos de diseño, no se construyó y no se va a construir.**

| Pieza | Estado |
|---|---|
| Avisos de descuadre entre máquinas al arrancar (`SessionStart`) | ✅ Funciona — clones fuera de la punta del servidor, repo por detrás del remoto, trabajo sin subir, deriva del `CLAUDE.md`, descuadre de configuración |
| El hook **apunta** a la bitácora en vez de inyectarla | ✅ Desde el 2026-09-07 |
| Bitácora de repo + bitácora de flota, como ficheros en git | ✅ Funciona |
| Registro entregado como datos delimitados, no como instrucciones | ✅ Funciona |
| Rechazo de credenciales antes de escribir | ✅ En `anotar.sh` |
| Commit y subida automáticos al anotar | ✅ En `anotar.sh` desde el 2026-08-25 — antes escribía en local y decía «anotado» |
| Aviso de cuándo sale a cuenta cortar la sesión | ✅ `hooks/userpromptsubmit-contexto.sh`. Mide **tokens de contexto**, no bytes |
| Coste real por sesión, modelo y día | ✅ `scripts/coste-sesiones.py`. Suma las **cuatro clases de token de cada mensaje** a tarifas publicadas. Sumar las líneas del transcript sin más infla el gasto un 153 % |
| Auditoría de sesiones que cerraron sin anotar | 🔌 `scripts/auditar-sesiones.sh` **sigue existiendo pero ya no está cableado al arranque**. Se ejecuta a mano |
| Borrador mecánico de la sesión | 🔌 `scripts/borrador-sesion.sh`, igual: existe, se llama a mano, ya no corre solo |
| Repaso diario que propone y no ejecuta | 🔌 `scripts/sueno.sh`, igual. Escribe su informe; el arranque ya no lo anuncia |
| Esquema con ciclo de vida de decisiones | 📄 Especificado, sin validador. **Retirado del plan** |
| Que el agente escriba la entrada solo | ❌ **No implementado, y no por descuido.** `PreCompact` y `SessionEnd` no pueden hacer que el agente escriba (son *side-effect only*), y un hook no redacta. **La entrada la escribe el agente, a mano, y así se queda** |
| Un fichero por entrada (`.bitacora/`) | ❌ Sigue siendo un `BITACORA.md` único. **Retirado del plan** |
| Lectura selectiva por relevancia | ❌ **Retirada del plan el 2026-09-07**: costaba más de lo que podía ahorrar |
| Linter de decisiones (ruta → decisión vigente) | ❌ Diseñado, sin construir. **Retirado del plan** |

El porqué de cada hueco está en **[NOTAS-DE-CAMPO.md](NOTAS-DE-CAMPO.md)**, junto con
las cosas que se probaron y no funcionaron.

---

## Instalación

Requiere `bash`, `git` y `node` en el PATH. Ver **[INSTALAR.md](INSTALAR.md)** para el
detalle y la verificación.

```bash
git clone https://github.com/oscarazparren/bitacora-project.git
cp bitacora-project/hooks/sessionstart-leer.sh ~/.claude/
cp bitacora-project/bitacora.conf.example ~/.claude/bitacora.conf
```

Edita `~/.claude/bitacora.conf` —como mínimo `BITACORA_ETIQUETA`, que identifica a esta
máquina— y registra el hook en `~/.claude/settings.json`:

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

**Fusiona, no sobrescribas** — `settings.json` puede tener modelo, permisos u otros hooks.

No instales un hook `Stop` para avisar al terminar. Se probó y no hace lo que parece;
ver [NOTAS-DE-CAMPO.md](NOTAS-DE-CAMPO.md).

---

## Cómo se anota

**Dentro de un repo:** añade la entrada al `BITACORA.md` de ese repo y **haz commit** —
el commit es lo que la lleva a los demás dispositivos.

**Infraestructura (flota):** el cuerpo va por **heredoc entrecomillado**, que no
interpreta nada. Nunca por `printf`: un `%` en el texto lo corta ahí mismo y la entrada
se guarda a medias — pasó, y el script ahora lo rechaza en vez de tragárselo.

```bash
ssh <servidor> "bash /ruta/anotar.sh '[etiqueta] titular corto'" <<'EOF'
- Qué hice, con rutas y puertos concretos.
EOF
```

Si el fichero vive en una copia de trabajo de git, la misma llamada commitea y sube. Si
no puede (no es un repo, `.gitignore`, HEAD desacoplado, push rechazado), la entrada se
escribe igual y **la salida dice hasta dónde llegó**.

Hazlo sin esperar a que nadie lo pida, siempre que la sesión toque algo que otro
dispositivo deba saber. Un hook no puede hacerlo por ti: **los hooks ejecutan comandos,
no redactan.**

---

## Regla de fondo

La bitácora dice **qué mirar**; el estado real se comprueba siempre en vivo antes de
tocar producción. No te fíes de ella igual que no debes fiarte de la memoria local del
agente: ambas son fotos del pasado.

---

## Licencia

MIT. Ver [LICENSE](LICENSE).
