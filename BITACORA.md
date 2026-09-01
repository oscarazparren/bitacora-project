# Bitácora — bitacora-project

Registro de decisiones de este repositorio. Lo más reciente arriba.
Se lee sola al empezar sesión; hay que anotar antes de terminar y **hacer commit**,
que es lo que la lleva a los demás dispositivos.

Aquí van decisiones **de producto**. La infraestructura de quien lo usa va a su propio
registro privado — ver el aviso del README.

Formato: `## AAAA-MM-DD — [dispositivo] titular`

---

## 2026-09-01 — [PC Nuevo] El borrador mecánico existe, vive FUERA del repo, y `SessionStart(compact)` ya lo entrega

La pieza que quedaba del diseño de esta mañana: `scripts/borrador-sesion.sh` +
`scripts/borrador-leer-transcript.js`. Redacta —sin modelo, sin coste, sin red— la
materia prima de una sesión leyendo su transcript y el `git log`. **En ningún
`BITACORA.md` escribe nada, nunca.**

### La decisión que más se pensó: dónde vive

En `$HOME/.claude/bitacora-borradores/`, **fuera de cualquier árbol de trabajo de git**,
y no en el repo detrás de un `.gitignore`. Tres razones, en orden de peso:

1. **«Nunca commiteado» tiene que ser estructural, no una línea.** Una línea de
   `.gitignore` la borra un editor descuidado, la salta un `git add -f`, y no existe en
   una copia recién clonada. Es el criterio del propio `CLAUDE.md`: si cumplir la regla
   exige acordarse, mecanismo. Fuera del árbol no hay nada que fallar.
2. **No añade exposición nueva.** El borrador es una vista derivada del transcript, que
   ya está en `$HOME/.claude/projects/` con el mismo contenido y las mismas
   protecciones. Dejarlo ahí no mueve nada de sitio; **meterlo en el repo sería la
   primera vez que el mapa operativo entra en un árbol de trabajo de git.**
3. Es donde ya vive el resto del estado del sistema (`bitacora-sesiones`,
   `bitacora-visto`, `bitacora-leido`, `bitacora-rutas`).

En el `.gitignore` hay igualmente una línea `bitacora-borradores/`, **etiquetada como
cinturón y no como mecanismo**: solo cubre que alguien apunte `BITACORA_BORRADORES`
dentro de un repo.

### Qué lleva, y el hueco que se deja vacío a propósito

Seis secciones: identidad de la sesión (con **¿anotó? medido contra el artefacto**),
**los prompts del usuario literales**, ficheros escritos, comandos ejecutados, commits
de la ventana y estado del repo. Y la sexta es `descartado`, **vacía y explicando por
qué lo está**: lo que se descartó no deja artefacto —no hay commit de lo que no se
hizo— y rellenarlo con algo verosímil es la forma exacta de los cuatro fallos
silenciosos. El borrador señala el hueco; no lo finge.

**Dos correcciones al diseño de esta mañana, las dos por no poder cumplirlo tal cual:**

- El diseño pedía «lo que queda sucio **al cerrar**». **Eso no se puede tener**: el
  borrador se escribe después, y `git status` solo sabe de ahora. En vez de colar el
  estado de hoy como si fuera el del cierre, la sección lleva la edad de la sesión y
  **avisa en grande cuando pasan de 15 minutos**. Un dato correcto presentado como
  respuesta a otra pregunta es el fallo de siempre.
- El diseño decía «ficheros tocados, de los `Edit`/`Write` del transcript». Contra
  ficheros reales eso **miente por omisión**: la sesión de esta mañana hizo 57 llamadas
  a `Bash` y solo 7 a `Edit`, o sea que casi todo su trabajo era invisible. Se añade la
  lista de comandos (primera línea de cada uno) **y el hueco se dice dentro del propio
  borrador**, junto a la sección que lo tiene.

### Los dos disparos

- **Arranque (sección 1c).** Cuando el auditor canta `SIN-ANOTAR`, se prepara el
  borrador de esa sesión y **se inyecta solo la RUTA, nunca el contenido**: el borrador
  ocupa decenas de KB y pasarse de `MAX_CHARS_TOTAL` descarta el envío ENTERO sin
  avisar. La ruta del transcript se lee del bloque `PENDIENTES` del auditor en vez de
  reconstruirla: dos sitios calculando la misma ruta se separan en cuanto uno cambie, y
  entonces el borrador describiría una sesión distinta de la que el auditor acusa.
- **`SessionStart(compact)`**, que es el punto que quedó marcado con un comentario en el
  hook. Y ahí está su valor de verdad: **la compactación se lleva por delante justo el
  detalle que hace falta para anotar**, mientras que el transcript sigue entero en
  disco. Se escribe el borrador (`--rehacer`: la sesión sigue viva y su transcript
  crece) y se inyectan 1.352 bytes con la ruta. **Sigue sin reinyectarse la bitácora y
  sin tocarse `$VISTO` ni `$LEIDO`** — comprobado por `mtime` antes y después.

### `node`, y no `awk`

No añade dependencia: `node` ya es requisito documentado y `sessionstart-leer.sh` no
puede emitir su JSON sin él. A cambio se gana lo único irreemplazable del fichero: **los
prompts literales**. Desescapar JSON a mano en `awk` (`\"`, `\`, `\n`, `\uXXXX`)
corrompería en silencio justo el campo que no se puede reconstruir de ningún otro sitio.

**Y dos procesos, no ocho.** La primera versión pedía a `node` cada campo y cada sección
por separado: **3,5 s**. Uno extrae y otro compone: **1,1 s**, y **0,44 s** si el
borrador ya existe (atajo por glob del id corto, antes de arrancar nada). Es la lección
del auditor otra vez —lo caro no es el trabajo, son los procesos— y aquí no es
cosmética: el hook de arranque ya se pasó de presupuesto dos veces esta mañana.

### El bug que solo aparece en Windows

`MSYS2_ENV_CONV_EXCL='*'` en la llamada a `node`. Git Bash **traduce las variables de
entorno que parecen rutas POSIX** antes de dárselas a un binario de Windows, y
`node.exe` lo es: `B_RAIZ=/c/Users/…` le llegaba como `C:/Users/…`, y el borrador salía
con una ruta que el script nunca había escrito. Trivial en consecuencia, **idéntico en
mecanismo** a lo que este proyecto persigue: un dato transformado en silencio.

### Probado

Contra transcripts reales: las **dos deudas conocidas** (`AlcoholTax-IA` 25-ago, 335
turnos, 2,1 MB → borrador de 22 KB; `lizar-informes` 27-ago) y la sesión de esta mañana.
Degenerados: fichero vacío, basura sin JSON, sin marcas de tiempo, fuera de git, sin
argumentos, transcript inexistente — **todos salen con código 0, sin escribir y
diciendo por qué**. Y los casos que importan de verdad, con fixtures a medida:
`tool_result` NO se cuela como prompt, `Read` NO cuenta como fichero escrito, las
vallas ` ``` ` dentro de un prompt no rompen el bloque, los `\n` de un comando
multilínea no arrastran la segunda línea, y las líneas ilegibles **se cuentan y se
dicen** en vez de saltarse.

Las dos ramas de fallo del hook, provocadas a mano: sin `borrador-sesion.sh` dice que no
lo encuentra; con él pero sin borrador, dice que se intentó y no salió. **Ninguna de las
dos calla** — la diferencia entre «no hay nada» y «no lo sé» es medio proyecto.

Coste del arranque en el repo con deuda: **19 s / 25 s de presupuesto, `ok`**, con el
borrador nuevo incluido. Y el aviso de drift de la sección 2c volvió a hacer su trabajo:
cantó las 5 variables nuevas sin documentar en el mismo momento de estrenarlas.

### Se adelanta al plazo del propio diseño, y conviene decirlo

El diseño de esta mañana ponía el borrador **detrás de dos semanas midiendo**. Se
construye antes porque el auditor ya trajo el dato que faltaba —**dos deudas reales, de
hace días, que nadie sabía**— y porque esta pieza no puede causar el quinto fallo: no
escribe en ningún repo, no manda nada por red, y lo peor que hace es dejar un fichero de
20 KB en `$HOME` que nadie lee.

### Siguiente

Medir. Ahora hay las dos mitades —quién no anotó y con qué reconstruirlo— y **ninguna se
ha usado todavía en caliente**. Lo que falta saber es si el agente, al ver la ruta,
abre el borrador y escribe la entrada; y si el hueco de `descartado` se rellena o se
ignora. La pasada con modelo sigue fuera, y ahora sí se podrá decidir con números.

## 2026-09-01 — [PC Nuevo] El auditor ya está cableado al arranque, y `sessionstart-leer.sh` por fin distingue `source`

Los dos puntos de "Siguiente" de la entrada de abajo, hechos en el mismo cambio a
`hooks/sessionstart-leer.sh`.

### 1. `source=compact` ya no reinyecta nada

El hook no leía stdin: corría idéntico en `startup`, `clear`, `resume`, `compact` y
`fork`. En `compact` eso hacía daño y estaba diagnosticado — el evento salta JUSTO
DESPUÉS de compactar (contexto recién reducido a propósito por caro) y el hook le volvía
a meter encima hasta 10.000 caracteres de bitácora. Y peor: la sección 0 pisaba el
marcador del índice (`$VISTO`) y la sección 1 avanzaba el de lectura (`$LEIDO`), así que
**el siguiente arranque de verdad ya no veía lo que se había movido**.

Ahora se lee stdin con dos `sed` (sin `jq`, no se da por instalado) y **en `compact` el
hook sale antes de tocar nada** — deja una línea `SALTADO` en el log (un salto en
silencio es justo el fallo que este proyecto persigue) y nada más. `clear` NO entra en
el filtro a propósito: ahí el contexto se vació y reinyectar SÍ es lo correcto. `resume`
y `fork` se dejan como estaban — no eran el bug de hoy. Comprobado: `compact` sale con
código 0, stdout vacío, línea en el log; `startup`/`resume`/`clear` corren enteros.

Cuando exista la pieza de escritura automática, **este es el punto donde `compact` tiene
que enganchar** (ver la entrada de abajo). Hay un comentario en el hook que lo dice.

### 2. El auditor corre al arrancar (sección 1c), dentro del presupuesto

`scripts/auditar-sesiones.sh` se invoca desde la sección nueva 1c, con `$RAIZ` y
`$SESION_ID` (la sesión actual se excluye: sigue viva y puede anotar). **v1 SOLO
INFORMA**: si hay líneas `SIN-ANOTAR`, se inyecta un bloque con ellas; si no, silencio.
No escribe borradores, no toca ningún repo.

Respeta el presupuesto de la cabecera como pedía la entrada de abajo: `hay_tiempo 6`
antes de arrancarlo, `timeout "$(tope 8)"` al lanzarlo, y `saltado()` si no cabe — con
lo que la degradación aparece en el "ESTA LECTURA VA INCOMPLETA" del final. El auditor
es LOCAL (cero red) pero cuesta ~3,8 s medidos, y meterlos a ciegas en un hook con plazo
duro de 45 s es literalmente cómo murió el hook el 28-ago.

Probado de punta a punta: desde `bitacora-project` (sin deuda → silencio, 2,7 s el
auditor solo, 12 s el hook entero) y desde `AlcoholTax-IA` (deuda conocida del 25-ago,
335 turnos → el bloque `AUDITORÍA:` aparece con esa línea, hook a 16 s/25 s, `ok`).

### 3. De paso: el `.example` ya documenta las 7 variables del auditor

`bitacora-project@c6dad2a` añadió el auditor pero no documentó sus variables, así que la
sección 2c del propio hook cantaba "el CÓDIGO las lee pero el .example no las documenta"
**en cada arranque**. Añadidas a `bitacora.conf.example` con los defaults del 1-sep y su
porqué: `BITACORA_AUDITORIA_{UMBRAL_TURNOS,DIAS,RECIENTE_MIN,VENTANA_HORAS,GRACIA_MIN}`,
`BITACORA_PROYECTOS`, `BITACORA_REGISTRO_SESIONES`. El aviso de drift ya no sale.

### Siguiente

La escritura automática de verdad (el borrador local, nunca commiteado, que describe la
entrada de abajo). Los dos canales al agente —`SessionStart` y `UserPromptSubmit`— ya
están cableados; falta la pieza que redacta el borrador mecánico y el `SessionStart(compact)`
que lo entregue como deuda.

## 2026-09-01 — [PC Nuevo] El auditor ya corre y encuentra dos deudas reales — y de paso: el transcript NO está ordenado por fecha

Construido el paso 1 del diseño de la entrada anterior: **`scripts/auditar-sesiones.sh`**
(solo lee, no escribe nada en ningún repo) y **`hooks/sessionend-anotar.sh`** (una línea
por cierre). El registrador ya está cableado en `settings.json` como **entrada propia**
bajo `SessionEnd`, junto a la de la foto, no dentro de ella.

### Dos deudas reales, comprobadas contra el log de commits

- **`AlcoholTax-IA`, 25-ago, sesión de 335 turnos** cerrada a las 20:07. El último commit
  de bitácora de ese día fue a las 09:52. Nada entre medias.
- **`lizar-informes`, 27-ago, sesión de 43 turnos** cerrada a las 16:25. Último commit de
  bitácora, 10:07.

Las dos existían desde hace días y **nadie lo sabía**. Es exactamente el hueco que el
auditor viene a tapar: no que el agente se olvide mucho, sino que cuando se olvida no
queda rastro de que se olvidó.

### El bug que solo aparece contra ficheros reales

**El `.jsonl` de una sesión NO está en orden cronológico.** Una sesión REANUDADA escribe
arriba la marca de reanudación y copia debajo la historia previa. Medido en
`427e04d6`: **línea 1 = 14:04:21, línea 3 = 13:32:17.**

La primera versión sacaba inicio y fin con `head -1` / `tail -1`. Con eso, esa sesión
salía con **inicio == fin** y se declaraba `SIN-ANOTAR` siendo falso. Se arregla
recorriendo el fichero y quedándose con el mínimo y el máximo (ISO 8601 se ordena como
texto, así que comparar cadenas basta).

Es la lección de siempre, cobrada otra vez: **probar contra el caso feliz inventado no
sirve.** Contra los 64 transcripts del disco salió a la primera.

### Sesiones ≠ conversaciones, y esto corrige un número que di esta misma mañana

Al reanudar, Claude Code crea un fichero NUEVO con la conversación entera duplicada. En
`lizar-asistente-aula` había **8 ficheros pero solo 4 conversaciones**:

```
08-26 11:17 -> 08-26 12:50   2128db5b  ┐ misma conversación
08-26 11:17 -> 08-31 15:26   afec2dc1  ┘
08-31 15:32 -> 08-31 16:03   ef7ca647  ┐
08-31 15:32 -> 08-31 16:04   427e04d6  ├ misma conversación
08-31 15:32 -> 08-31 17:48   c48e0681  ┘
```

Así que el «39 sesiones» y el «15 de 16» de la entrada anterior **cuentan ficheros, no
conversaciones: el denominador está inflado.** La conclusión de fondo no cambia
(compactaciones = 0, y anotar funciona hoy por prosa), pero el dato hay que leerlo así.

### Cuatro estados, no tres

El diseño decía tres. Contra datos reales hizo falta un cuarto: **`CONTINUADA`**. Sin él
el auditor cantaba deuda **por cada corte de sesión** — o sea, castigaba justo la
disciplina que queremos. De las 3 deudas que dio la primera versión, **2 eran conducta
correcta**: un corte limpio (12:50 → 12:51) y una reanudación.

Se distinguen dos causas a propósito, porque meterlas en una sola condición («alguien
seguía trabajando cuando acabé») era tan ancha que una sesión larga y **concurrente**
absorbía a todas las que solapaba y **habría tapado deuda real** — la dirección
silenciosa. Ahora: `CADENA` = la siguiente arranca donde ésta acaba (±5 min);
`REANUDADA` = otro fichero con el mismo arranque (±2 min) que termina más tarde.

Y `CONTINUADA` se cuenta y se dice, no se esconde: colapsarla con `ANOTADA` sería el
fallo de siempre.

### El coste, que casi reconstruye la avería del 28-ago

Primera versión: **9,7 s** en el repo más cargado (grep+sed+sort+grep -c = tres procesos
por fichero). El hook de arranque tiene 25 s de presupuesto, la red ya se come 10-20 y el
plazo duro son 45. **Meter ahí 9,7 s habría recreado literalmente el cuarto fallo
silencioso desde la pieza que viene a impedirlo.**

Bajado a **3,8 s** pasando a **un proceso por CARPETA** (un `find` + un `awk` sobre la
lista entera) en vez de tres por fichero. Lo caro no era el trabajo, eran los procesos:
en Git Bash cuestan más que lo que hacen, cosa que ya estaba escrita en la cabecera de
`sessionstart-leer.sh` y que hubo que volver a aprender. **Los veredictos son idénticos
antes y después**, comprobado.

`sessionend-anotar.sh` va sin **un solo subproceso** en el camino normal (ni `cat`, ni
`sed`, ni `date`: `read`, expansión de parámetros, `$EPOCHSECONDS` y `printf %()T`).
Medido: **164 ms**, contra un presupuesto de `SessionEnd` que es de **1,5 s COMPARTIDOS**
entre todos sus hooks — dato nuevo, y es el argumento de por qué no se cuelga de la foto:
su `ssh` puede llevarse el presupuesto por delante.

### Probado

Auditor contra los 64 transcripts y las 13 bitácoras del disco; las dos deudas cotejadas
a mano contra `git log`. Registrador con `HOME` de mentira y cuatro entradas: normal,
sin campos, vacía y basura — las dos últimas salen con código 0 y **sin escribir**.
`settings.json` validado con `node` tras el cambio.

### Limitación conocida, y sale a la cara

`kangurea-web` responde **`NO-SE-PUDO-COMPROBAR`**: sus sesiones se abrieron desde `~`,
no desde el repo, así que no hay carpeta de transcripts que mirar. Es correcto y es el
tercer estado haciendo su trabajo — dice «no sé mirarlo», no «no hay nada». Y es la cara
visible de que **19 de 39 ficheros de sesión corren fuera de cualquier repo**: para ésos
el auditor por repo es ciego, y el arreglo no es código, es «un chat por repo».

### Siguiente

1. Cablear el auditor en `sessionstart-leer.sh`, **respetando su presupuesto** (`tope()`,
   `hay_tiempo()`, `saltado()` si no cabe) — 3,8 s no son gratis ahí.
2. Que ese hook distinga `source`: hoy no lo mira, y en `compact` reinyecta 10.000
   caracteres a un contexto recién compactado y consume el marcador del índice.

## 2026-09-01 — [PC Nuevo] La escritura automática NO se cuelga de `PreCompact`: ese evento lleva una semana muerto, y lo mató nuestra propia disciplina de corte

Diseño decidido, sin código todavía. **Contradice a NOTAS-DE-CAMPO.md**, que desde el
principio ordena los disparos poniendo `PreCompact` el primero. Esa nota se escribió
antes de que existiera la disciplina de cortar a 200.000 tokens; la disciplina funcionó,
y al funcionar dejó sin disparos al mecanismo que se iba a construir encima.

### Lo medido, que es lo que cambia el diseño

- **`PreCompact` dispararía ~nunca.** 27 compactaciones históricas en esta máquina, la
  última el **25-ago**. **Cero en las 39 sesiones desde el 26-ago.** Cortar antes de
  200k evita la compactación por construcción.
- **Anotar no está fallando hoy: 15 de 16.** Sesiones desde el 26-ago en repos con
  bitácora, cruzadas con las entradas del mismo día. La única sin entrada tiene **0
  turnos** (sesión abierta y cerrada). El agente se acuerda.
- **Pero se acuerda por PROSA, no por mecanismo** (CLAUDE.md + el empujón del hook de
  contexto). Por el criterio del propio CLAUDE.md —*si cumplir una regla exige detectar
  un momento → mecanismo*— esa es la configuración frágil. Y lo decisivo: **hoy no
  existe nada capaz de decir que una sesión terminó sin anotar.** Ese 15/16 lo he
  contado yo con un bucle a mano; el sistema no lo sabe.
- **19 de 39 sesiones corren fuera de cualquier repo** (`~`, `~/repos`, `C:\`). Ahí no
  falta memoria: falta destino.

### El error que cometí midiendo, que vale más que la medición

Primero crucé las sesiones con el **`mtime` del `.jsonl`** en vez de con los timestamps
de dentro. Salieron «4 sesiones sin entrada», entre ellas la de **4.112 turnos** de
`agentes-lizar` — y lo dije en voz alta antes de comprobarlo. Es falso: esa sesión anotó
(entrada del 25-ago y `docs(bitacora): cierre corto...` en el log). Su «todo guardado y
subido» era cierto.

**Estuve a punto de acusar de fallo silencioso a la única sesión que hizo las cosas
bien, en la sesión en que venía a diseñar el mecanismo que lo impide.** El fallo es el
de siempre —dar por bueno un indicador en vez de mirar el artefacto— y de ahí sale la
regla nº2 de abajo, que ya no es teórica.

### Restricciones comprobadas contra la documentación, no supuestas

- **`PreCompact` y `SessionEnd` son side-effect only**: no admiten `additionalContext`,
  no honran el código de salida 2, su stderr no llega al modelo. **No pueden hacer que
  el agente escriba.** Esto tumba el diseño obvio de raíz.
- Los únicos canales al agente son `SessionStart` y `UserPromptSubmit`, los dos ya
  cableados y funcionando.
- **`SessionStart` tiene matcher `compact`**: dispara justo DESPUÉS de compactar. Es el
  canal que `PreCompact` no tiene. **`sessionstart-leer.sh` no lee `source` hoy**: corre
  igual en `startup`, `resume`, `clear`, `compact` y `fork`.
- **Los hooks de `SessionEnd` comparten un presupuesto colectivo de 1,5 s**, elevable
  con `timeout` propio. El `ssh` de la foto puede dejar sin aire a cualquier otro hook
  de cierre.

De ahí la frase que ordena el diseño entero:

> **La escritura nunca puede dispararse en el momento en que hace falta. Solo un momento
> ANTES (`UserPromptSubmit`, con la sesión viva) o un momento DESPUÉS (`SessionStart`
> siguiente, como deuda).**

### El diseño

**Qué dispara — tres piezas, cada una haciendo solo lo que puede.**

1. **`SessionEnd` registra, no juzga.** Una línea en un registro local: sesión, cwd,
   repo, timestamps, turnos, tokens, si compactó. **Sin una sola llamada a `git`**: con
   1,5 s compartidos y un `ssh` al lado, cualquier subproceso es el quinto fallo
   silencioso — y en Git Bash lanzar un proceso ya cuesta más que el trabajo que hace.
2. **`SessionStart` audita y habla.** Decide si la sesión contó, comprobando el
   **artefacto**: ¿hay commit que toque ese `BITACORA.md` dentro de la ventana? Si no,
   inyecta la deuda. Local, sin red, dentro del `PRESUPUESTO` de 25 s ya existente.
3. **`UserPromptSubmit` avisa a tiempo.** El aviso de 200k ya dice «anota antes de
   cortar»; le falta el dato de si esta sesión **ya ha anotado o no**.

**`PreCompact` se cablea igual, pero como red de seguridad barata**, no como pieza
principal: cuatro líneas que marcan el registro, emparejadas con `SessionStart(compact)`
que sí puede hablar. Degrada a nada mientras no haya compactaciones, que es el caso.

**Qué escribe si el agente no ha dicho nada: en `BITACORA.md`, NADA. Nunca.** Los hooks
no redactan, y **este repo es PÚBLICO**: un borrador hecho del transcript lleva prompts
literales, rutas e infraestructura — el «mapa operativo» que NOTAS-DE-CAMPO ya avisa que
**no es una credencial y por eso se cuela por el filtro de secretos**. Auto-commitear eso
a un repo público sería el peor fallo disponible aquí, y automático.

Lo que sí: un **borrador local, nunca commiteado**, mecánico y sin coste de modelo —
commits de la ventana, ficheros tocados (de los `Edit`/`Write` del transcript), **los
prompts del usuario literales** (son la intención y las correcciones, y no se derivan de
ningún otro sitio) y lo que queda sucio al cerrar. Materia prima etiquetada como tal, no
una entrada. **`descartado` no se puede generar mecánicamente y no se va a fingir que
sí**: el borrador solo señala dónde estaría.

**La pasada con modelo queda fuera de la v1 a propósito**: cuesta ~0,3-0,6 $ por sesión,
exige guardia contra recursión (la subsesión dispara estos mismos hooks) y sobre todo
**no se puede evaluar sin el auditor que diga cuántas veces hace falta**. La semana
pasada: 1 vez de 16, y esa tenía 0 turnos.

### Cómo se evita el quinto fallo silencioso

Los cuatro anteriores comparten forma: **quien reporta el éxito es quien hizo el
trabajo, y reporta el intento en vez del artefacto.**

1. **Quien audita no es quien escribe.** La auditoría lee `git log` y el transcript del
   disco; **nunca una marca de «hecho» dejada por `SessionEnd`**. Si el cierre no llegó
   a correr —la X, un `kill`, la luz— reconstruye la deuda igual. Es la lección nº4
   literal: el log que medía el éxito lo escribió un proceso que ya estaba muerto.
2. **La evidencia es el artefacto**: «anotada» = existe commit que toca ese
   `BITACORA.md` en la ventana. Ni «el hook corrió» ni «el agente dijo que anotó».
3. **El plazo forma parte de la evidencia**: segundos contra presupuesto en cada línea.
4. **Tres estados, nunca colapsados**: `ANOTADA` / `SIN-ANOTAR` /
   `NO-SE-PUDO-COMPROBAR`. El tercero grita más que el segundo; hoy los tres se ven
   igual, que es por lo que nadie sabe si esto funciona.
5. **La deuda no se consume al leerla**: vive hasta que la resuelve un artefacto.
   Cierra por fin el pendiente de *«un aviso que se consume al leerlo no es un aviso»*.
6. **Se prueba contra los 64 transcripts y las 13 bitácoras reales del disco**, no
   contra el caso feliz. Es la prueba que habría cazado el `awk` y el `printf`/`%`.
7. **La v1 solo informa**: no escribe borradores ni toca ningún repo. Un auditor de solo
   lectura no puede causar un quinto fallo — lo peor que hace es equivocarse en voz alta.

### Va APARTE de `sessionend-foto.sh`, y el motivo es el presupuesto

No se cuelga de la foto. La foto es **idempotente y auto-reparable** (si se pierde el
disparo, el arranque siguiente la rehace); el registro es lo contrario, **su momento es
irrepetible**. Meter lo que no se puede perder detrás de un `timeout 8 ... || true`
pensado para lo que sí, es heredarle el manejo de errores flojo — y con 1,5 s
compartidos, el `ssh` de la foto puede matarlo. Hook propio, `timeout` propio; corren en
paralelo.

### Bug latente que este diseño destapa, aún sin arreglar

**`sessionstart-leer.sh` no mira `source`.** En cada compactación reinyecta hasta 10.000
caracteres de bitácora a un contexto **recién compactado por grande**, y consume el
marcador del índice — la avería de *«un aviso que se consume al leerlo»*, disparada por
un evento que el usuario no ha pedido. Hoy no hace daño porque no hay compactaciones;
en cuanto una sesión se escape del corte, sí.

### Orden de construcción

1. El auditor de solo lectura (`SessionEnd` registra + `SessionStart` audita e informa).
2. Que `sessionstart-leer.sh` distinga `source`.
3. Dos semanas midiendo. **Entonces** se decide si hace falta el borrador mecánico, con
   el número de fallos reales delante — no antes.

## 2026-09-01 — [PC Nuevo] El umbral de AVISO baja de 250.000 a 200.000 tokens: el hook se pone al día con CLAUDE.md

Quedaba **pendiente y anotado como tal** en la BITACORA.md de `lizar-asistente-aula`
(entrada del 1-sep): `CLAUDE.md` ya decía 200.000 desde el 31-ago, pero el hook seguía
avisando a 250.000. Un umbral en la prosa y otro en el mecanismo — la prosa manda, pero
el aviso automático llegaba tarde, que es justo para lo que existe el hook.

`hooks/userpromptsubmit-contexto.sh` línea 63: `BITACORA_CONTEXTO_AVISO_TOKENS` pasa de
`250000` a `200000`. **URGENTE se queda en 400.000**, que sigue viniendo de la
calibración del 29-ago sobre 56 sesiones; lo que se recalibró fue solo el primer escalón.

### Por qué 200.000, medido y no estimado

Los números salen de las 6 sesiones reales de `lizar-asistente-aula` (1.154 turnos,
26-31 ago), no de una intuición:

- **El 58 % del gasto de aquel repo era `cache_read`** — o sea, releerse a sí mismo:
  267 M tokens, 53,49 $ de los 92,35 $ del repo.
- **Cortar ahorra el 77 %.** Los mismos 1.154 turnos: **142,04 $** en una sola sesión
  frente a **36,70 $** cortando cada ~100 turnos.
- **Dónde cae cada umbral.** Al ritmo medido (~900 tokens de contexto nuevos por turno),
  250.000 equivalía al turno ~172 y 200.000 cae en el ~137.
- **Por qué no se baja más.** El óptimo económico está en ~150.000, pero la curva es
  plana entre 60 y 160 turnos, y por debajo de ~40 el **suelo de arranque** (~95.000
  tokens que se recachean, 0,159 $ por corte) se repaga tantas veces que vuelve a
  encarecer. 200.000 captura casi todo el ahorro sin entrar en ese tramo.

### Se cambia en el repo, no en `bitacora.conf`, y esto es lo importante

Tentación evidente: poner la variable en `~/.claude/bitacora.conf` y listo. **Sería
peor.** Arreglaría esta máquina y dejaría al PC viejo avisando a 250.000, y **dos
máquinas con umbrales distintos es peor que las dos con el umbral viejo** — el aviso
dejaría de significar lo mismo según dónde estés sentado. El valor por defecto del
script es lo único que viaja por git a las dos.

Consecuencia práctica: **el otro PC no tiene que hacer nada manual.** Con `git pull` el
umbral nuevo ya está activo. Solo hay que tocar `bitacora.conf` para querer un umbral
distinto del de serie.

### Cambios que acompañan

- **El comentario de la línea cuenta ahora el porqué nuevo**, con los números de arriba
  y de dónde salen. El de antes decía «calibrados el 29-ago sobre 56 sesiones» para los
  dos umbrales, y eso ya solo vale para URGENTE: dejarlo habría hecho que el siguiente
  que lo leyera atribuyera el 200.000 a una calibración que no lo produjo.
- **`bitacora.conf.example` pasa también a 200000.** Documenta el valor por defecto, y
  el `.example` es contra lo que la sección 2c de `sessionstart-leer.sh` compara la
  configuración de cada máquina: dejarlo en 250000 habría convertido el fichero de
  referencia en la fuente de una descuadre que el propio repo se dedica a detectar.
- **Y de paso, un desfase ajeno a este cambio, visto al pasar por el mismo fichero:**
  el `.example` seguía diciendo que el aviso de variables retiradas sale **por stderr**.
  Dejó de ser cierto el 30-ago (commit `b366d34`), que es justo cuando se descubrió que
  el `2>/dev/null` de `settings.json` se lo tragaba; la línea del `.example` se quedó
  sin actualizar. Corregida: ahora dice additionalContext y explica por qué no puede ser
  stderr. Es documentación de una trampa ya pisada una vez, así que costaba más dejarla.

### Comprobado, no supuesto

El hook se ejecutó con un `HOME` de mentira y transcripts sintéticos en cuatro escalones:
**190k calla, 200k avisa, 210k avisa, 410k da el aviso urgente.** El escalón de AVISO
dispara donde debe y URGENTE sigue intacto.

## 2026-08-30 — [PC viejo] La comprobación de configuración era ciega en una dirección

Diagnóstico hecho desde otra sesión (`LIZAR-AIA-WEB`) al ver que el hook avisaba de
**11 claves que faltan** en `~/.claude/bitacora.conf`. Comprobado una a una contra el
default del código: **10 de las 11 no cambiaban nada** (mismo valor que trae el
código por defecto). Solo `BITACORA_IGNORAR` era una diferencia real. Un aviso que
lista once cuando importa una entrena a ignorarlo — justo lo que este proyecto
existe para evitar.

**La causa de fondo**: la sección 2c (añadida el 29-ago) solo comparaba
`bitacora.conf` contra `bitacora.conf.example` en una dirección — qué le falta al
conf. Nunca miraba la contraria: qué lee el CÓDIGO que el `.example` no documenta.
Por ahí se coló `BITACORA_MAX_CHARS_TOTAL`, la palanca que de verdad acota el
tamaño total inyectado (comentario del PC viejo, `~/.claude/bitacora.conf`, ya
avisaba de haberse equivocado una vez confundiéndola con `MAX_ENTRADAS`) — sin
documentar desde que existe. Junto a ella: `BITACORA_REPO_MAX_CHARS`,
`BITACORA_SIN_GIT`, `BITACORA_CUENTA_GITHUB`, `BITACORA_WEBHOOK_URL` y
`BITACORA_WEBHOOK_SECRETO`.

**Arreglado en dos sitios:**

1. `bitacora.conf.example` documenta ahora esas seis claves.
2. `hooks/sessionstart-leer.sh`, sección 2c: la comparación de FALTAN ahora compara
   el default embebido en el código con el valor del `.example`, y solo avisa si
   DIFIEREN de verdad (antes avisaba de cualquier ausencia, sin mirar si cambiaba
   algo). Se añadió una comprobación nueva, código-vs-`.example`, que avisa cuando
   el código lee una clave que el `.example` no documenta — el hueco que dejó pasar
   `MAX_CHARS_TOTAL`. Verificado con una ejecución real del hook: antes de este
   cambio habría señalado 6 claves sin documentar; después, cero.

**Se excluyó a propósito de la comprobación nueva**: `BITACORA_FOTO_MOMENTO`.
Estaba en la lista de "importa documentar" del diagnóstico inicial, pero al mirar
el código sus dos únicos callers (`sessionstart-leer.sh` y `sessionend-foto.sh`)
SIEMPRE lo fijan por código (`arranque`/`cierre`) antes de invocar
`foto-config.sh` — ponerlo en `bitacora.conf` no tendría ningún efecto. Es plomería
interna, como `BITACORA_CONF`, `_LOG`, `_LEIDO`, `_CONTEXTO_MARCAS` y
`_FLOTA_REPO`, que por el mismo motivo tampoco se documentan.

**En la máquina (fuera del repo, no viaja por git):** `~/.claude/bitacora.conf`
(PC viejo) ya tenía el comentario de `BITACORA_INDICE_REPOS` podrido — decía
"DESACTIVADO DE URGENCIA" mientras el valor de la línea de abajo ya estaba activo
desde que la sección 0 pasó a leer `estado.txt` en una sola llamada SSH. Corregido
el comentario, y añadida `BITACORA_IGNORAR` con el valor completo del `.example`
(sin ella, abrir sesión en `repos/referencia/`, `repos/archivo/` o `tools/` habría
creado un `BITACORA.md` ahí — hoy sin daño porque esas carpetas no existían en esta
máquina, pero la trampa estaba armada). **Pendiente: repetir estos dos cambios de
conf en el PC Nuevo**, que tiene su propio fichero y no se ve desde aquí.

## 2026-08-30 — [PC viejo] El aviso de corte de sesión pasa de MB a tokens de contexto

`hooks/userpromptsubmit-contexto.sh` avisaba mirando el peso en bytes del `.jsonl`
(2 MB / 3,5 MB). Medido el 29-ago sobre 56 sesiones de la flota: ese umbral de 2 MB
correspondía a sesiones de entre 58k y 394k tokens de contexto según el caso — un
factor 6,8x de un lado a otro del mismo umbral (rho(MB, tokens) = 0,927: hay
correlación, pero no la precisión que hace falta para cortar en el momento justo).
La causa es que el peso en bytes mezcla bloques de pensamiento y salidas de
herramientas — que engordan el fichero pero no todos entran en el contexto que se
reenvía — con los tokens que sí se facturan cada turno.

**Ahora mide tokens de verdad**: suma `cache_read_input_tokens +
cache_creation_input_tokens + input_tokens` del último turno con `usage` en el
transcript (`output_tokens` no cuenta, no se reenvía). Umbrales nuevos, en
`BITACORA_CONTEXTO_AVISO_TOKENS` (250k) y `BITACORA_CONTEXTO_URGENTE_TOKENS`
(400k) — las viejas `BITACORA_CONTEXTO_AVISO`/`URGENTE` (bytes) quedan retiradas.
Documentado en `bitacora.conf.example`.

Nuevo `scripts/calibrar-umbral.py`: recorre `~/.claude/projects/*/*.jsonl` y
regenera esta distribución (Spearman a mano, sin numpy) para poder recalibrar sin
fiarse de un número escrito una vez en un comentario.

### Un fallo propio, cazado antes de que llegara a la otra máquina

La primera versión mandaba el aviso de "variable retirada" por `stderr`. **No lo
habría visto nadie nunca**: el wrapper de este hook en `settings.json` es
`... 2>/dev/null || true` — descarta stderr siempre, en las dos máquinas. Cualquier
aviso de un hook tiene que ir por `stdout` (el JSON de `additionalContext`), igual
que ya hace la sección 2c de `sessionstart-leer.sh` con sus avisos de configuración
descuadrada. Corregido: ahora usa el mismo canal, con su propio deduplicado por
sesión (una vez y calla, no en cada turno).

**Vale para cualquier hook nuevo de este repo**: si vas a avisar de algo, que sea
por el JSON de salida, nunca por stderr — se pierde en silencio y parece que
funciona porque el hook no falla, exit 0 y todo.

### Qué necesita el otro PC

**Nada manual.** Los umbrales nuevos son el valor por defecto del script; con
`git pull` ya están activos, sin tocar `bitacora.conf`. Solo hace falta editarlo si
se quiere un umbral distinto de 250k/400k (ver `bitacora.conf.example`), o si
`BITACORA_CONTEXTO_AVISO`/`URGENTE` (bytes) estuvieran puestas ahí — no era el
caso en ninguna de las dos máquinas al hacer este cambio, pero si aparecen, el
hook avisa una vez por sesión y toca borrarlas.

## 2026-08-29 — [PC Nuevo] Giro de posicionamiento: el producto es UNA máquina con VARIAS cuentas, no equipos. Y el INSTALAR.md describe un sistema que ya no existe

Conversación con Óscar al cerrar el día. Tres cosas, y la tercera cambia a quién se le
ofrece esto.

### 1. `INSTALAR.md` está desfasado, y es medible

Contado hoy sobre el fichero, no a ojo. Veces que aparece cada pieza construida en los
últimos dos días:

```
webhooks 0 · receptor 0 · foto-config 0 · UserPromptSubmit 0
ESTADO_REMOTO 0 · FLOTA_ENTRADAS 0 · PRESUPUESTO 0
```

**Las instrucciones describen un sistema que ya no existe.** Quien clone el repo hoy
instala la versión de hace dos semanas. Y aun estando al día harían falta SIETE pasos
manuales (clonar, crear la conf y editar la etiqueta, cablear tres hooks a mano en un
JSON, dar acceso SSH, copiar el `CLAUDE.md` canónico, darse de alta en el índice). **No
hay instalador.** Es el mismo modo de fallo de siempre —documentación que afirma algo que
ya no sostiene el código— y hoy se ha dado ya dos veces más: el comentario de
`MAX_LINEAS` en el `.example` y la contradicción del `CLAUDE.md` sobre el hook de
contexto. Van tres en un día.

### 2. Hipótesis sobre equipos: funciona a 5 personas, pero hoy se rompe justo ahí

Óscar pidió hipótesis, no «hasta que no se pruebe no se sabe». Va con su porqué.

**Lo que escala tal cual:** git ya resuelve N escritores; el índice por webhooks es O(1)
en número de máquinas; y —corrección suya, y tiene razón— **no hace falta meterle una IA:
cada usuario trae la suya**. El agente ES el lector. Decir que «necesita un agente
vigilando» como pega es falso: eso lo tiene todo el que use estas herramientas.

**Lo que se rompe, y son las dos piezas que llevan sin construirse desde el día uno:**

1. **Sigue siendo un `BITACORA.md` monolítico.** No existe `.bitacora/` en ningún repo.
   Con dos máquinas serializando contra un servidor aguanta; con 5 personas editando el
   mismo fichero es un conflicto de merge diario. `ESQUEMA.md` lo dice desde el principio.
2. **No hay lectura por relevancia.** Sigue siendo truncado por antigüedad contra un
   techo fijo de 10.000 caracteres.

**La consecuencia, que es lo que decide la hipótesis:** hoy **el valor por persona BAJA
según crece el equipo** — más gente, más entradas, más truncado, y cada uno lee una
proporción menor de lo suyo. Es lo contrario de lo que necesita una herramienta de
equipo, y falla en silencio: parece que funciona mientras cada uno recibe menos.

Con esas dos piezas construidas, la hipótesis es **sí, funciona bien a 5**. Sin ellas,
5 es exactamente donde empieza a doler.

### 3. EL GIRO: el caso bueno es UNA máquina con VARIAS cuentas

Idea de Óscar, y reordena la prioridad entera. El escenario: llegas al límite de uso de
una cuenta a media tarea, anotas, cierras, abres con otra cuenta (u otro proveedor) y la
sesión nueva continúa donde lo dejaste.

**Comprobado que funciona sin tocar nada:** `~/.claude/settings.json` y `bitacora.conf`
son del usuario del sistema operativo, no de la cuenta de Claude, y la bitácora vive en el
repo. Cambiar de cuenta no toca ninguna de las tres cosas.

**Y aquí está lo importante: ese caso usa solo la parte que YA funciona.**

```
hace falta:  hook SessionStart + una forma de anotar        <- construido y probado
NO hace falta: servidor, webhooks, receptor, SSH, estado.txt, fotos de config
```

Todo lo complejo y a medias existe para resolver VARIAS MÁQUINAS. Para una sola máquina
sobra el 70% del proyecto. Y los dos problemas del punto 2 **desaparecen**: sin escritores
simultáneos no hay conflicto de merge, y con un solo usuario el presupuesto sobra.

**Orden recomendado, y es un cambio respecto al dossier:**

- **1º Cuentas y proveedores.** Dolor diario y agudo, instalación de un hook, cero
  infraestructura, y mercado mucho más ancho que «equipos que ya usan varios agentes».
  La extensión a Claude + OpenAI + Qwen + Kimi es además **defendible**: ningún proveedor
  va a construir la continuidad hacia el de al lado, tienen el incentivo al revés. El
  formato ya es agnóstico (Markdown en el repo); falta un adaptador de lectura por
  herramienta, y para varias basta con que su fichero de instrucciones lo referencie.
- **2º Equipos.** Después, y con las dos piezas del punto 2 construidas.

**La pega honesta, dicha para no vendérnosla:** esto no se monetiza fácil. Es un hook y
una convención de Markdown, se copia en una tarde y aparecerán alternativas gratis.
Vender el script no va a funcionar. Lo realista: **regalarlo para ganar usuarios** —que es
justo lo que falta, hoy n=1 y el operador es el autor— y cobrar por lo que lo rodea (el
filtrado por relevancia bien hecho, los adaptadores, y más adelante la capa de equipo y
auditoría). **El caso de las dos cuentas no es el negocio: es el embudo.** Pero es el
correcto, porque es lo único que se le puede poner a alguien en la mano la semana que
viene sin que se caiga.

### Pendientes

1. **DESBLOQUEADO — `instalar.sh`.** Media tarde. Hace los siete pasos y **verifica que
   funcionan** (que el hook dispara, que el JSON es válido, que se puede anotar). Es lo
   que desbloquea a la vez el PC #3 y cualquier prueba con alguien de fuera: sin esto no
   hay nada que enseñar a nadie. No es funcionalidad nueva, es empaquetar lo que ya hay.
2. **DESBLOQUEADO — poner al día `INSTALAR.md`.** Documentación que miente; el congelado
   no cubre corregirla.
3. **EN ESPERA — un fichero por entrada (`.bitacora/`).** Condición para equipos.
   Funcionalidad, congelada.
4. **EN ESPERA — lectura por relevancia.** La otra condición, y probablemente *el*
   producto: «que los cinco sepan lo que ha hecho el otro» solo vale si «lo que ha hecho
   el otro» significa **lo que me afecta a mí**, no un volcado cronológico.
5. **EN ESPERA — adaptadores para otras herramientas.** Funcionalidad, congelada.

**Qué NO congela el congelado:** no congela empaquetar lo ya construido (el instalador),
ni corregir documentación falsa. Solo funcionalidad nueva.

## 2026-08-29 — [PC viejo] La bitácora de flota se corta por ENTRADAS enteras. Cerrado el último de los tres fallos abiertos

Era el que quedaba, y llevaba abierto desde el 28-ago. **`BITACORA_MAX_LINEAS` queda
retirada.**

### El fallo que cierra

El corte por líneas partía la última entrada a mitad de frase **y no lo decía**. El
28-ago costó un doble diagnóstico de la avería del operator: una máquina re-diagnosticó
desde cero algo que la otra ya había anotado esa mañana, porque la entrada caía fuera del
corte de 40. Subirlo a 80 solo movió dónde se parte.

### Cómo

El `awk` que elige las N entradas más recientes corre **en el servidor**, no aquí: es
Linux y es rápido (22× esta máquina para el mismo trabajo, medido el 29-ago), y así no se
trae por la red un fichero que solo va a recortarse. Devuelve además el TOTAL de entradas
que hay, para poder decir cuántas quedan fuera en vez de callarlo — antes ni siquiera se
sabía cuánto se estaba dejando.

Dos techos, no uno, por lo mismo que en las secciones 1 y 1b: las entradas no pesan
igual, así que contarlas no acota el tamaño. Si no caben, se sueltan **enteras**.

```
1 entrada de flota = 2.888 chars | 2 = 6.478 | 3 = 9.654   (techo total: 10.000)
```

`FLOTA_MAX_CHARS=5000` deja **el mismo presupuesto que daban las 80 líneas** (4.957): sin
regresión, pero ahora lo que llega son entradas completas. Es el intercambio deliberado —
menos entradas, pero ninguna partida, y se dice lo que falta.

**Probado el caso apretado**, que era el que podía romper: `agentes-lizar`, con las
secciones 1 y 2 a la vez → **9.638 chars, sin corte global**, y la salida termina en
`--- FIN DEL REGISTRO ---` en vez de a mitad de frase.

### Una variable retirada que lo dice

`BITACORA_MAX_LINEAS` ya no hace nada, así que **el hook avisa si la encuentra puesta** y
nombra a las dos que la sustituyen. Una opción que se ignora en silencio es el mismo modo
de fallo de siempre en versión configuración: quien la tenga creería estar controlando el
corte sin controlar nada. Actualizada también la conf de esta máquina y el `.example`.

Es además la lección del 29-ago aplicada («al quitar algo, enumerar lo que hacía y decir
quién lo hereda»), esta vez sin que haga falta que nadie se acuerde.

### Pendientes

**Ninguno de código en este repo.** Los tres fallos abiertos del proyecto están cerrados:
el silencio del hook (28-ago), el índice de coste lineal (29-ago) y este.

## 2026-08-29 — [PC viejo] El PC Nuevo contestó las tres, y la GitHub App ya está puesta: el rediseño de webhooks queda CERRADO

Las tres cosas que esta máquina dejó apuntadas por la mañana venían contestadas **en la
bitácora de FLOTA, no en la de este repo** — por eso `git` no traía nada y hubo que ir a
mirar allí. Anotado porque volverá a pasar: *el trabajo de la otra máquina no siempre
llega por donde lo esperas.*

- **La GitHub App sobre «All repositories» está instalada y FUNCIONANDO.** Era el único
  pendiente que ningún agente podía hacer. El PC Nuevo lo verificó **en el log del
  receptor, no en la pantalla de GitHub**: `ping OK` al instalarse y dos pushes reales de
  `kangurea-web` registrados solos. Los repos nuevos ya no nacen mudos, y
  `sincronizar-webhooks.sh` deja de hacer falta para los futuros.
- **La regla de «otra sesión viva en el repo» ya está en el `CLAUDE.md` canónico**
  (commit `51f0f54`, en `config/`). Esta máquina se la lleva con `git pull` + `cp`; no
  hay que reescribirla de memoria, que es como se desincronizaron antes.
- **`$EPOCHSECONDS`: vía libre confirmada.** Los CUATRO bash de cada máquina son
  5.3.15(1). Verificado aquí ejecutándolos, no de oídas.

### Aplicado: `restante()` y `tope()` dejan de lanzar procesos

`date +%s` se llamaba 8 veces por arranque. Sustituido por `${EPOCHSECONDS:-$(date +%s)}`.

**El respaldo no es adorno:** `$EPOCHSECONDS` existe desde bash 5.0 y en un bash 4.x
saldría VACÍO y la aritmética reventaría — o sea, ahorrar medio segundo aquí costaría el
hook entero en otra máquina. Hoy no se usa; se deja por si aparece una tercera.

```
8 forks de date, medidos aparte ...... 0,584s  (73 ms cada uno)
hook entero, media de 4 pasadas ...... 7,24s -> 6,67s  (0,57s menos)
```

Salida **idéntica byte a byte** (9.686), comprobado antes de mirar el reloj.

**Y un aviso sobre la medición, que es la lección del día otra vez:** con DOS pasadas el
resultado parecía cero (6,56/6,23 y 6,22/6,28: una a favor y otra en contra). Con cuatro
sale 0,57s, y coincide con los 0,584s medidos por separado. **Dos muestras no bastaban
para ver un efecto del tamaño del ruido**, y de haberme quedado ahí habría escrito «no
mejora nada», que era falso. Medir mal y medir poco fallan igual.

### Pendientes

1. **DESBLOQUEADO — cortar la bitácora de flota por ENTRADAS enteras** en vez de por
   líneas. Es lo ÚNICO de código que queda abierto en este repo. `MAX_LINEAS=80` sigue
   partiendo entradas a mitad de frase, que es lo que el 28-ago costó un doble
   diagnóstico. La sección del repo ya lo hace bien: es aplicarle lo mismo a la 2.
2. **CERRADO** — la GitHub App y `$EPOCHSECONDS`, los dos pendientes de la entrada de
   abajo.

## 2026-08-29 — [PC viejo] DOS SESIONES a la vez en este repo, y por poco escribo encima. Medido de dónde salen los 17s: la sección 0 ya no es el problema

Sesión abierta en paralelo a la que hizo `36ceedc`. El hallazgo del día no es código: es que
**`git status` limpio al arrancar era un dato correcto y caducado**, y nada avisó.

### El casi-fallo, que es el mismo mecanismo de siempre

Arranqué, leí la bitácora, elegí el pendiente DESBLOQUEADO (sección 0 → `estado.txt`) y
comprobé `git status`: **limpio**. Empecé a editar el hook. El editor avisó de que el
fichero había cambiado en disco.

Comprobado en vez de deducido: el árbol tenía **84 inserciones y 97 borrados sin
commitear** que yo no había escrito, y la sesión `bitacora-project-46` llevaba 1h abierta
con su transcript escrito **9 segundos antes** de mi comprobación. Su transcript menciona
`sessionstart-leer` 49 veces. Era ella.

Retiré mi línea —usaba `INDICE_ESTADO` y la suya `ESTADO_REMOTO`: habrían quedado **dos
variables de configuración para la misma ruta**, que es un fallo de verdad y silencioso.

**Lo que esto enseña:** «un chat por repo» acota *dónde* trabaja UNA sesión. No dice nada
de **dos sesiones a la vez en el mismo repo**, que es un eje tercero que no cubre ninguna
regla. `git status` no es un cerrojo: es una foto. Van seis variantes del mismo fallo, y
esta es la primera en que el dato caducado lo generó *otro agente nuestro*.

### Los 17s, desglosados (el commit `36ceedc` los dejaba «sin explicar»)

Medido con `$EPOCHREALTIME`, que es variable interna de bash y no hace fork:

```
sección 0 (índice, la recién arreglada) ....  4,82s
sección 1 (bitácora del repo) .............  8,75s   <- aquí está
sección 1b (carpeta) ......................  0,002s
sección 2 (flota, no aplica aquí) .........  0,32s
secciones 3-4 (log + JSON) ................  0,54s
```

**La sección 0 cuesta lo que debía. El problema ahora es la sección 1**, que nadie ha
tocado. Dentro de esos 8,75s: 4,44s antes de mirar la bitácora (fetch 1,2s + git local
0,6s + los `date` que forkean en `restante()`/`tope()`) y **4,85s en TRES llamadas a
`entradas_recientes()`** de ~1,5s cada una.

El bucle que encoge la salida hasta que cabe en `REPO_MAX_CHARS` **vuelve a partir los
85 KB enteros de `BITACORA.md` en 31 ficheros temporales desde cero en cada iteración**.
Es exactamente la forma de fallo que se acaba de arreglar en la sección 0 —coste lineal
en el tamaño del dato, repetido N veces— y **empeora sola, porque la bitácora solo
crece**. Hoy son 4,85s de 15s.

### Un error mío por el camino, que se anota porque es el de siempre

La primera medición usaba `PS4='+ $(date +%s%3N) '` con `bash -x`. Salían builtins como
`[ -f … ]` tardando 2,4s, que es imposible: **el `PS4` lanzaba un `date` por cada una de
las 376 líneas trazadas, así que medía mi propia instrumentación.** Descartada entera y
repetida con `$EPOCHREALTIME`. Versión-instrumento del fallo de siempre: **un número
salido de una medición mal montada tiene el mismo tono de dato que uno bueno.**

### Arreglado (y qué no)

1. **`bitacora.conf.example`: `BITACORA_ESTADO_REMOTO` no estaba documentada.** El hook la
   usa desde `36ceedc`; quien clone el repo no puede descubrirla. Documentada, con el
   arranque en frío y el aviso de que el índice necesita las dos mitades.
2. **El comentario de `MAX_LINEAS` deja de mentir.** Llevaba desde el 28-ago diciendo que
   la bitácora de flota «puede ser corta sin coste», que es justo lo que costó el doble
   diagnóstico del operator. Puesto el 80 medido y explicado por qué. Pendiente
   DESBLOQUEADO desde el 28-ago: cerrado.
3. **`receptor-webhook.py` reingería su propia cabecera.** `# nombre` pasaba el filtro
   (3 campos, primero no vacío) y entraba como un repo; luego se escribía otra cabecera
   encima. Visto en vivo: dos cabeceras y una fila basura permanente. **DESPLEGADO Y
   VERIFICADO** (ver abajo).
4. **`estado.txt` se escribía 0600**, así que solo funcionaba porque el cliente entra por
   SSH como root. Dependencia oculta —el día que alguien entrara con otro usuario, el
   índice se quedaría sin datos sin saber por qué—. Puesto `os.chmod(tmp, 0o644)`.

### Desplegado en LIZAR-1, con la verificación hecha allí

Autorizado por Oscar. Copia previa en `/root/receptor-webhook.py.bak-20260829-154447`,
md5 comparado a los dos lados y sintaxis validada con el `python3` del servidor antes de
instalar. Comprobado **después** del reinicio, con un aviso firmado desde dentro del
servidor usando el mismo repo y SHA que ya figuraban (idempotente, no falsea dato):

```
antes:   2 cabeceras + fila basura + repo-de-prueba   -rw------- (0600)
después: 1 cabecera  + 1 fila real                    -rw-r--r-- (0644)
```

El 0644 es justo lo que la prueba en Windows NO podía verificar. Se dijo que quedaba sin
verificar; ahora lo está.

**El circuito funciona solo:** el push de `ccd328e` de esta sesión llegó al servidor por
webhook sin lanzar nada, a la misma hora a la que se hizo.

### Y arreglado al final: la sección 1 baja a la mitad

Con la otra sesión 3h 30m en silencio y el árbol limpio, se pudo tocar el hook sin chocar.
`entradas_recientes()` parte ahora el fichero **una vez** y lo recuerda (`partir_una_vez`).

El hallazgo de verdad: **el culpable no era el `awk`, que cuesta 0,3s.** Era el enjambre de
procesos de alrededor —`mktemp`, `find`, `wc`, `tr`, `ls`, `sort`, un `cat` POR ENTRADA y
`rm`— repetido entero en cada llamada. Se quitaron casi todos: ordenar lo hace el glob de
bash (nombres con `%05d`, orden alfabético = numérico), contar es el tamaño de un array, y
leer una entrada es `$(<fichero)`, redirección interna. **`entradas_recientes()` ya no
lanza ni un proceso externo.**

```
sección 1:   8,75s -> 4,55s
hook entero: 15,7s -> 12,7s   (antes 15,7/14,5, después 12,7/11,4)
```

**Verificado que no cambia nada más:** las dos versiones, desde el mismo estado de
marcadores, dan **8.499 bytes idénticos byte a byte** (`cmp`). Se comprobó antes de mirar
el reloj: un arreglo rápido que cambia la salida no es un arreglo.

### Pendientes

1. **EN ESPERA — cortar la bitácora de flota por ENTRADAS enteras** en vez de por líneas.
   Sigue abierto desde el 29-ago; el 80 de `MAX_LINEAS` es un parche que aún parte frases.
2. **DESBLOQUEADO, pequeño — `restante()` y `tope()` lanzan un `date +%s` cada vez** que se
   las llama, y se las llama ~10 veces. `$EPOCHSECONDS` es variable interna de bash y las
   dejaría a coste cero. No se hizo aquí por una razón concreta: **existe desde bash 5.0 y
   no se ha comprobado qué bash tiene el PC Nuevo.** Si es anterior, la variable sale vacía
   y la aritmética revienta — o sea, cambiaría un segundo por un hook roto en la otra
   máquina. Hay que mirarlo allí antes, o dejar respaldo a `date`.
3. **DESBLOQUEADO — decirlo en `CLAUDE.md`: comprobar si hay otra sesión viva en el mismo
   repo antes de editar**, no solo que el árbol esté limpio. Es el hueco que abrió esta
   sesión y ninguna regla lo cubre. No se toca aquí porque `CLAUDE.md` es fichero de Oscar.
3. **CERRADO — el pendiente 1 de la entrada de abajo («averiguar los 17s»)** queda
   respondido por la medición de arriba: sección 0 = 4,82s, sección 1 = 8,75s. La sospecha
   que dejaba escrita («queda tiempo sin explicar en el resto del script») acertaba de
   pleno; el sitio concreto es el bucle de `entradas_recientes()`.

## 2026-08-29 — [PC viejo] La sección 0 ya lee estado.txt: 17s/25s con 40 repos, y el coste deja de crecer

Cierra el círculo de todo el día. **Con 40 repos vigilados el arranque va a 17s dentro
de un presupuesto de 25 y marca `ok`.** Con el código anterior habrían sido ~160s y no
habría entregado nada — de hecho no los entregó: rompió el arranque de un chat nuevo.

### El diseño lo simplificó Oscar, y esa es la razón de que sea barato

Su corrección: el índice no tiene que decir QUÉ se movió ni cuánto, solo EN QUÉ REPOS.
Si vas a trabajar en uno, entras y lees su bitácora allí. Eso permitió tirar el
`git fetch` + `rev-list --count` que daba el detalle — que era justo la parte que
reventó el plazo el 28-ago. **La sección no hace ya ni una sola llamada a git.**

### El error de en medio, que es el mismo peaje de siempre

Primera versión: una llamada SSH en vez de 40 `ls-remote`, y aun así **41s**. El bucle
hacía dos `awk` por repo — 80 procesos — y en Git Bash sobre Windows crear un proceso
cuesta ~0,4s. **Cambié red por subprocesos y no arreglé nada.** El peaje no era la red:
era crear procesos, lo mismo que descubrimos por la mañana con `ls-remote`.

Arreglado con UNA pasada de `awk` sobre los tres orígenes (estado del servidor, marcador
local, lista de vigilados), marcados con una letra por línea. `ruta_local` solo se llama
para los repos que han cambiado, no para los 40.

**La lección: que algo deje de tocar la red no lo hace constante. Lo que tiene que ser
constante es el número de PROCESOS.**

### Arranque en frío, comportándose como se diseñó

Sale «SIN DATOS TODAVÍA en 39 repo(s)», no «sin cambios». Los webhooks solo avisan de
pushes futuros, así que hasta que cada repo reciba el suyo no se sabe nada de él — y
decirlo así, en vez de callarlo, es justo lo contrario del fallo silencioso que este
repo persigue desde hace un mes. Se irá vaciando solo.

### Pendientes

1. **DESBLOQUEADO — averiguar los 17s.** La sección 0 es ahora una llamada SSH y la de
   flota otra: deberían ser ~4s, no 17. Queda tiempo sin explicar en el resto del script.
   No es urgente (entra en presupuesto y marca `ok`) pero está sin medir, y este repo ya
   sabe cómo acaban las cosas sin medir.
2. **EN ESPERA — la GitHub App** sobre «All repositories», para no tener que relanzar el
   sincronizador con cada repo nuevo.
3. **HECHO hoy y verificado**: receptor de webhooks, 40 repos avisando, hook de contexto
   restaurado, sincronizador idempotente, y esta sección 0.

## 2026-08-29 — [PC viejo] Los 42 repos avisan (40 vivos + 2 archivados que no aplican). Y el fallo lo vio Oscar, no el sistema

Cierre de la vía sin token. **Estado final verificado: 40 de 40 repos vivos con webhook,
2 archivados que no pueden tenerlo, 0 fallos, código de salida 0.**

### El fallo, que es del mismo tipo que llevamos todo el día cazando

Se crearon 9 webhooks y se dio por bueno. Oscar preguntó lo obvio: «¿por qué esos nueve
y no `lizar-correo`, que es un agente que está funcionando?». Medido entonces: **9 con
webhook, 33 sin él**, incluidos agentes en producción (`lizar-correo`, `lizar-clon`,
`lizar-recepcion247`, `lizar-auditoria`).

Nadie eligió esos 9. Eran los de `repos.txt`, lista escrita a mano cuando cada repo
vigilado costaba ~4s de arranque y había que racionarlos. **Esa razón desapareció con
los webhooks, se midió, y se escribió en esta bitácora la misma tarde** — y aun así el
script salió leyendo la lista vieja por defecto, con la opción `--todos` programada y
sin usar.

**Tener el dato no es lo mismo que usarlo.** Van cinco variantes del mismo fallo: el
silencio, el log que mentía, el freno falso, la función retirada sin que nadie lo note,
y ahora una premisa heredada que no se revisó porque no parecía haber nada que revisar.

### Arreglado donde no puede repetirse

1. **El defecto del script es ahora TODOS los repos** de la cuenta; `--indice` queda como
   opción rara. Antes había que acordarse de escribir `--todos` para hacer lo correcto;
   ahora hay que acordarse de escribir `--indice` para hacer lo raro.
2. **`repos.txt` regenerado desde GitHub**: de 10 a 40, excluyendo archivados.
3. **Los archivados dejan de contar como fallo.** GitHub rechaza webhooks en repos de
   solo lectura, y aunque los aceptara nunca dispararían. Contarlos como error habría
   hecho que el script terminara en error para siempre — **y una alarma que salta
   siempre deja de leerse.** Se saltan y se dicen, que no es lo mismo que callarlos.

### El criterio, otra vez, porque hoy se ha ganado tres veces

> **Un defecto que hay que acordarse de cambiar es un defecto mal puesto.**

Es el mismo principio que restaurar el hook de contexto: si algo depende de que alguien
lo recuerde, acabará fallando. Que lo recuerde el mecanismo.

### Pendientes

1. **DESBLOQUEADO, y es lo único que falta para cobrar todo esto — cambiar la sección 0
   del hook** para leer `estado.txt` en UNA llamada SSH en vez de N `ls-remote`. Hasta
   que se haga, el arranque sigue tardando ~45s aunque el servidor ya tenga los datos.
   Ojo: ahora `repos.txt` tiene 40 repos, así que **con el código viejo el arranque
   costaría ~160s y no entregaría nada**. Es el paso que cierra el círculo, no un extra.
2. **EN ESPERA — la GitHub App** sobre «All repositories», que haría innecesario volver
   a lanzar el sincronizador cuando se cree un repo nuevo. Necesita clics en la web.
3. **EN ESPERA — arranque en frío**: `estado.txt` solo se llena con pushes futuros, así
   que un repo sin tocar aún no aparece. Debe informarse como «sin datos todavía», nunca
   como «sin cambios».

## 2026-08-29 — [PC viejo] De vuelta a mecanismo: hook restaurado y los webhooks dejan de depender de que alguien se acuerde

Decisión de Oscar: «muévelo a mecanismo, todo lo que se pueda». Hecho lo que se puede
hoy, y dicho claramente lo que sigue sin poderse.

### 1. `userpromptsubmit-contexto.sh` restaurado

Recuperado del historial (`3a2569b^`), sintaxis validada, y vuelto a enganchar en
`~/.claude/settings.json`. Hooks activos ahora: `SessionStart` + `UserPromptSubmit`.
`Stop` sigue retirado, y esa retirada sí era correcta (se disparaba en cada turno).

### 2. Los webhooks dejan de ser un paso que hay que recordar

Lo detectó Oscar preguntando: «¿y si mañana doy de alta un repo nuevo?». Tenía razón y
era un agujero: **un webhook es POR REPO**, así que cada repo futuro nacía mudo hasta
que alguien repitiera el comando. Mismo modo de fallo de siempre — depende de que una
persona se acuerde.

`scripts/sincronizar-webhooks.sh` (nuevo): idempotente, informa de lo que hace, no
duplica nada, y devuelve código de error si algún repo se queda mudo. Modos: por defecto
los del índice, `--todos` para los 42 de la cuenta, `--revisar` para no tocar nada.

Probado en `--revisar`: detecta correctamente 1 puesto y 9 sin poner, 0 fallos.

### 3. Lo que NO se ha podido mover a mecanismo, dicho sin adornos

**El script sigue habiendo que ejecutarlo.** No es el arreglo definitivo. El arreglo de
verdad es una **GitHub App instalada en la cuenta con acceso a «All repositories»**: esa
cubre los repos futuros sola, sin que nadie lance nada nunca más. Requiere unos clics en
la web de GitHub que no se pueden dar por API. **Queda anotado para no venderlo como
resuelto**, que es justo lo que este repo lleva un mes aprendiendo a no hacer.

### El criterio que sale de todo esto, y que vale más que el código

> **Si cumplir una regla exige detectar un momento → mecanismo, no prosa.**
> **Si la regla describe cómo hacer algo que ya estás haciendo → prosa vale.**

Hoy se incumplieron tres reglas escritas (verificar antes de afirmar ×3, un chat por
repo, y el aviso de coste). Las tres exigían notar un momento. Ninguna de las que
describen *cómo* trabajar falló. Ayer se cambió un mecanismo por prosa y **la prosa
aguantó menos de 24 horas**.

### Números de coste, medidos hoy (para no volver a discutirlo a ojo)

Opus 5 $5/$25 por millón, Sonnet 5 $2/$10, lectura de caché 0,1×, escritura 2× (TTL 1h).
Esta sesión: 222 peticiones, **232.049 tokens de contexto**, **$28,40** gastados.

```
seguir en Opus aquí .......... $0,116/turno y subiendo
cambiar a Sonnet SIN cortar .. $0,928 el turno del cambio   <- LA PEOR
chat nuevo en Sonnet ......... $0,060 y luego ~$0,005/turno <- la buena
chat nuevo en Opus ........... $0,150 y luego ~$0,012/turno
```

**Lo que ahorra cortar no es la caché: es tirar 232.000 tokens de contexto y arrancar
con 15.000.** El peaje del cambio de modelo es calderilla al lado. Se anota porque en
esta sesión se recomendó primero la opción peor.

### Pendientes

1. **DESBLOQUEADO — lanzar `scripts/sincronizar-webhooks.sh`** para los 9 que faltan.
   Desde el PC, no dentro del servidor.
2. **EN ESPERA — la GitHub App** que haga innecesario el script. Necesita acción de
   Oscar en la web de GitHub.
3. **DESBLOQUEADO — cambiar la sección 0 del hook** para leer `estado.txt` en una sola
   llamada SSH. Es lo que queda para cobrar el beneficio entero.

## 2026-08-29 — [PC viejo] Al retirar el tercer hook se perdió una función y NADIE lo notó. La justificación de la retirada era falsa, y esta sesión lo demuestra

Lo levantó Oscar, no yo, y llevaba un día activo.

### Qué se perdió

Ayer se retiraron tres hooks y se dijo que la regla «un chat por repo» los sustituía. Es
verdad para `sessionstop-comprobar.sh`. **Es falso para `userpromptsubmit-contexto.sh`**,
que hacía algo que ninguna regla nueva cubre: medir el peso de la sesión y avisar de
cuándo sale a cuenta cortar, con dos umbrales calibrados (2 MB / 3,5 MB).

Los hooks cubrían **dos ejes distintos**:

- *dónde* trabajar → un chat por repo. **Trasladado ayer.**
- *cuánto* aguantar antes de cortar → umbrales de peso. **Perdido ayer, sin sustituto.**

Al escribir la entrada de ayer se trataron como si fueran el mismo eje.

### La justificación era falsa, y se puede demostrar

Ayer se escribió: «un chat por repo se mantiene corto solo, sin necesitar esa heurística
de megabytes». **Esta misma sesión la desmiente**: 0,9 MB y 208 turnos **sin salir de
`bitacora-project` ni una sola vez**. La regla del repo nunca se disparó porque nunca
hubo motivo, y aun así la sesión creció. Un chat por repo acota el eje equivocado.

Que todavía no haya cruzado el umbral de 2 MB es suerte: **no había nadie mirando**.

### El daño concreto, en esta sesión

Le recomendé a Oscar «baja a Sonnet ahora». Con el razonamiento que el propio hook
retirado llevaba escrito, ese consejo es **caro**: cambiar de modelo pierde la caché de
prompt, y cortar la sesión la pierde igualmente, así que cambiar ahora paga el peaje dos
veces. Lo correcto es cortar y cambiar en el mismo gesto. **La función perdida no era
solo un aviso: era la que hacía correcto el consejo de modelo.**

### Arreglado

Sección nueva en `CLAUDE.md`, «Cuándo sale a cuenta cortar la sesión», con los dos
umbrales, la orden para medir, y el REGALO DEL CORTE explícito. Incluye por qué se
escribe: que la justificación de ayer era falsa y qué sesión lo demostró.

### La lección, que es la quinta variante del mismo fallo

Van: el silencio (el sistema sabe algo y no lo dice), el log que mentía, el FRENO FALSO
(una entrada correcta que paró trabajo bueno), y ahora **la retirada que se lleva por
delante una función que nadie echa en falta porque nadie la estaba mirando**. Al quitar
algo hay que enumerar TODO lo que hacía y decir, pieza por pieza, quién lo hereda. Ayer
se enumeró una de dos y la otra se dio por cubierta sin comprobarlo.

**Y no lo detectó el sistema: lo detectó Oscar acordándose.** Esa es la parte incómoda.

### Pendiente

1. **DESBLOQUEADO — `CLAUDE.md` de esta máquina ya tiene la sección; la del PC Nuevo
   no.** El PC Nuevo reconstruyó ayer sus secciones a mano desde esta bitácora, así que
   esta le va a faltar igual. Que la copie de aquí, no de memoria.

## 2026-08-29 — [PC viejo] CIRCUITO CERRADO: GitHub avisa y el servidor se entera. Y el fallo de en medio fue pegar el comando en la máquina equivocada

El webhook de `bitacora-project` está creado (id `671838034`, activo, entrega `200`) y el
receptor registró el `ping` real de GitHub a las 11:03:09, distinto de la prueba local de
las 10:44. **La vía sin token funciona de punta a punta.**

### El fallo de en medio, que merece quedar escrito

El primer intento no creó nada. Diagnostiqué «le falta el scope `admin:repo_hook`» a
partir de los scopes del token. **Era falso.** Lo que había pasado es que Oscar hizo
`ssh lizar` y pegó el comando **dentro del servidor**, donde no hay `gh` ni existe el
alias `lizar`.

Dos lecciones, y la segunda es la buena:

1. El comando necesitaba las DOS máquinas a la vez (`gh` habla con GitHub desde Windows;
   el `$(ssh lizar …)` va a buscar el secreto al servidor). Eso no se lo dije al darlo, y
   es justo la clase de detalle que hace que un comando correcto falle.
2. **Teoricé una causa en vez de pedir la salida.** Tenía delante un `[]` que solo decía
   «no hay webhooks», y de ahí salté a una explicación concreta y equivocada. La salida
   real lo aclaró en dos segundos. Es el mismo mecanismo de siempre en este repo: dar
   tono de dato a una deducción.

### Estado

Funcionando: receptor, servicio endurecido, nginx, secreto, y **1 de 10 webhooks**.

### Pendientes

1. **DESBLOQUEADO — crear los 9 webhooks restantes**, una vez validado el circuito con
   el primero. Mismo comando, cambiando el nombre del repo, y **desde PowerShell, no
   desde dentro del servidor**.
2. **DESBLOQUEADO — cambiar la sección 0 del hook** para leer `estado.txt` en una
   llamada SSH. Ya no está en espera: el circuito está probado.
3. **EN ESPERA — ampliar `repos.txt`.** Medido hoy: 42 repos en la cuenta, 45 carpetas
   locales, **10 vigilados**. La lista era corta porque cada repo costaba ~4s de
   arranque; con webhooks el coste es constante, así que **la razón para tenerla corta
   ha desaparecido**. Decisión de Oscar, no técnica.

## 2026-08-29 — [PC viejo] CONSTRUIDA la vía sin token: receptor de webhooks vivo en LIZAR-1. Falta el último paso, que lo tiene que autorizar Oscar

Oscar eligió la vía de webhooks y levantó el congelado para esto. **La mitad del
servidor está hecha, probada y en marcha; el paso que sale hacia fuera está parado.**

### Hecho y verificado

1. **`servidor/receptor-webhook.py`** (nuevo en el repo, desplegado en
   `/opt/bitacora/receptor-webhook.py`). Escucha en `127.0.0.1:8011`, verifica la firma
   HMAC-SHA256 de GitHub, y ante un `push` escribe `nombre → SHA` en
   `/opt/bitacora/estado/estado.txt`. Escritura atómica (temporal + `os.replace`), que
   importa porque el lector es un `cat` por SSH que puede caer en cualquier momento.
2. **`servidor/bitacora-receptor.service`** (nuevo). Corre como usuario de sistema
   `bitacora`, NO como root, y con `ProtectSystem=strict`. Lo único que puede escribir
   es `/opt/bitacora/estado`: **no se le dio `/opt/bitacora` entero a propósito**, para
   que un proceso que escucha de internet no pueda tocar `BITACORA.md`.
3. **Secreto de firma** generado en el servidor (`openssl rand -hex 32`),
   `root:bitacora 640`. No ha salido de la máquina más que para registrarlo en GitHub.
4. **nginx**: `location /gh-bitacora/` añadido al bloque de `n8n.lizaraia.com` (elección
   de Oscar: sin DNS ni certificado nuevos). Copia de seguridad previa en
   `/root/lizar-paneles.bak-20260829-104513`, `nginx -t` antes de recargar.

**Probado, no supuesto:** firma inválida → 401; sin firma → 401; `ping` con firma
válida → `pong`; `push` con firma válida → `estado.txt` escrito correctamente. Y tras
recargar nginx: `n8n.lizaraia.com` 200, `panel.lizaraia.com` 307, `lizaraia.com` 200 —
o sea, no se rompió nada de lo que ya servía. El endpoint responde desde fuera con TLS.

### Parado, y por qué

Crear los 10 webhooks en los repos de GitHub **lo bloqueó el clasificador de auto mode**,
y hace bien: es la única acción que modifica configuración persistente fuera de esta
máquina. Queda para que lo autorice Oscar. Sin ese paso `estado.txt` no se llena, así
que **el hook cliente NO se ha tocado todavía**: cambiarlo ahora degradaría el índice a
«sin datos» y rompería algo que hoy funciona, aunque sea lento.

### Pendientes

1. **DESBLOQUEADO — crear los 10 webhooks** (comando ya preparado, lo lanza Oscar).
2. **EN ESPERA hasta el punto 1 — cambiar la sección 0 del hook** para leer
   `estado.txt` en UNA llamada SSH en vez de 10 `ls-remote`. Es el cambio que convierte
   el arranque de ~45s en ~2s y de coste lineal a constante.
3. **EN ESPERA — que un repo sin datos en `estado.txt` se informe como «sin datos
   todavía», nunca como «sin cambios».** Está así en el diseño del receptor y hay que
   respetarlo en el cliente: decir «sin cambios» sin saberlo es exactamente el fallo
   silencioso que este repo lleva un mes persiguiendo.

## 2026-08-29 — [PC viejo] El token del servidor: qué es LIZAR-1 de verdad, y por qué el riesgo no es «que nos entren»

Análisis para decidir el punto 2 de la entrada de abajo. Datos del servidor medidos hoy,
no supuestos. **No se ha creado ningún token ni se ha tocado nada del servidor.**

### Qué es `lizar` realmente (y una corrección mía)

Escribí abajo «una credencial en una máquina compartida». **Es falso, y lo escribí sin
mirar.** Comprobado:

```
LIZAR-1, entro como root. Únicos usuarios con shell real: root (y sync, de sistema).
SSH: solo clave. passwordauthentication=no, permitrootlogin=without-password.
fail2ban activo, ufw activo.
Expuesto a internet: 22, 80, 443 (nginx). Todo lo demás en 127.0.0.1.
14 contenedores en marcha: operator, panel, recepcion247, correo, informes,
  auditoria, turnosmart, demora, clon, geoscanner, transcriptor, asisteweb,
  n8n, postgres.
Ya hay 3 ficheros .env, entre ellos /opt/agents/agentes-lizar/.env.
```

No es una máquina compartida: es **el servidor de producción de LIZAR entero**, de un
solo usuario, razonablemente endurecido.

### El punto que cambia la pregunta

La pregunta era «¿tenemos riesgo de que nos entren por tener el token?». **No.** Un
fichero con una credencial no escucha en ningún puerto ni acepta conexiones: no abre
ninguna puerta nueva. No cambia la probabilidad de intrusión, cambia **el botín** si
alguien ya entró.

Y el botín ya es grande sin el token: ese servidor guarda los `.env` de los agentes
(Supabase, WhatsApp Business, etc.), la base de datos y n8n. **Quien consiga root ahí ya
tiene el negocio.** Un token de GitHub de SOLO LECTURA acotado a 17 repos le añadiría
poder leer ese código. Es un incremento real pero pequeño frente a lo que ya hay, y no
permite escribir, ni borrar, ni tocar ajustes.

### La distinción que sí es crítica

- **Fine-grained, Contents: Read-only, 17 repos, con caducidad** → incremento pequeño.
- **Classic token con scope `repo`** → lectura Y ESCRITURA sobre TODOS los repos, incluso
  los que no están en el índice. Con eso se puede hacer push a `kangurea-web`, que
  publica al sitio vivo. Eso ya no es filtración: es cadena de suministro. **Nunca.**

### Alternativa que no necesita token (mejor, y más trabajo)

**Webhooks:** que GitHub avise al servidor cuando un repo cambia, en vez de que el
servidor pregunte. El servidor no necesita credencial de lectura ninguna; nginx ya está
en el 443. El secreto pasa a ser el de firma del webhook, que solo sirve para falsificar
avisos de «ha cambiado algo» — no para leer código. Invierte el riesgo. Cuesta
configurar 17 webhooks y un endpoint.

### Y un aviso que este repo debería saber mejor que nadie

Un token caduca. El día que caduque, el índice pasará a «no se pudo consultar» y seguirá
arrancando **como si no pasara nada**. Es exactamente el modo de fallo que llevamos un
mes cazando. Si se pone token, la caducidad tiene que doler: aviso explícito y distinto
de «sin red», no un silencio más.

### Pendientes

1. **DESBLOQUEADO (decisión de Oscar, no técnica) — elegir vía: fine-grained read-only
   o webhooks.** Ninguna se implementa: la implementación es funcionalidad y la cubre el
   congelado. Solo hay que decidir cuál, para no diseñar dos veces.
2. **EN ESPERA — que el fallo por token caducado sea ruidoso.** Va con la
   implementación, congelada.

## 2026-08-29 — [PC viejo] DISEÑO (de Oscar): que el índice lo calcule el servidor, no cada cliente. El coste pasa de lineal en N a constante

Idea de Oscar al leer la medición de la entrada de abajo, y es la buena. No se
construye: es funcionalidad nueva y **la cubre el congelado**. Se anota entera para que
al levantarlo esté decidida y no haya que volver a pensarla.

### Lo que hace hoy la sección 0, dicho sin adornos

No lee 45 repos, ni lee ningún repo: por cada línea del índice (**17**, no 45) lanza un
`git ls-remote URL HEAD` contra GitHub para traerse **un SHA**, y lo compara con el
marcador local `~/.claude/bitacora-visto`. Distinto SHA = ha cambiado. El 45 de la
entrada de abajo era una prueba de esfuerzo, no lo que corre a diario.

O sea: **17 conexiones de red desde el cliente para traer 17 líneas de texto.**

### La medición que lo cierra

Los MISMOS 17 repos, en el servidor de flota, **en serie y sin paralelismo ninguno**:

```
PC viejo (Windows, 17 en "paralelo") ...... 45s
servidor lizar (Linux, 17 en serie) ....... 2s
un ls-remote suelto en el servidor ........ <1s
```

**22 veces más rápido haciendo el trabajo de la forma tonta.** Confirma la causa de la
entrada de abajo: lo caro no es la red ni GitHub, es **Windows creando procesos y cada
hijo negociando su propio TLS**. La misma tarea en una máquina Linux no tiene ese peaje.

*Honestidad sobre ese 2s:* la mayoría de esos 17 fallan rápido en el servidor por falta
de credenciales (ver obstáculo), así que el 2s no es un camino de éxito limpio y el
número real será algo mayor. La conclusión estructural no cambia: el orden de magnitud
es segundos, no decenas de segundos.

### El diseño

La «carpetita central» que propone Oscar **ya existe**: es `lizar`. Ya guarda
`repos.txt`, ya guarda la bitácora de flota, y el hook ya habla con él en 2s. Lo único
que le falta es guardar **los SHA**.

1. Un `cron` en el servidor refresca `/opt/bitacora/estado.txt` (nombre → SHA actual).
   El trabajo se hace **una vez para toda la flota**, no una vez por máquina y arranque.
2. El cliente hace **UNA** llamada SSH, se trae el fichero entero y lo compara contra su
   marcador local.

El «desde tu última sesión» sigue siendo local y por máquina — cada PC tiene su
`bitacora-visto` — y eso es correcto y gratis: el servidor publica el estado del mundo,
no el estado de nadie.

**Lo que se gana no es velocidad, es la pendiente.** Hoy el arranque cuesta lineal en el
número de repos (~2,65s cada uno) y por eso crecer el catálogo rompe el arranque. Con
esto cuesta **lo mismo con 17 que con 45 que con 200**: una llamada. Mata el fallo de
raíz en vez de acotarlo.

Deja además obsoleto el pendiente de «acotar la etapa de `ls-remote`»: no hay que acotar
una etapa que desaparece.

### El obstáculo, medido y sin resolver

**El servidor NO tiene credenciales para los repos privados.** Comprobado contra
`agentes-lizar` (privado): falla. Hoy solo vería los públicos, que es justo lo contrario
de lo que hace falta. Requiere un token de solo-lectura en el servidor: hay que decidir
alcance y dónde vive. **No se toca en esta sesión.**

*(Corregido el mismo día: aquí puse «una credencial en una máquina compartida». Es
falso y lo escribí sin comprobarlo — en `lizar` solo `root` tiene shell. El análisis
real, con los datos del servidor medidos, en la entrada de arriba.)*

Es también, en pequeño, el mecanismo que `CLAUDE.md` dejó pendiente el 18-ago
(«detección automática contra la API de GitHub»). Mismo sitio, mismo token.

### Pendientes

1. **EN ESPERA (congelado) — construir el `estado.txt` + cron + la lectura en el hook.**
   Es el arreglo bueno de la grieta del presupuesto. Diseño ya decidido, arriba.
2. **EN ESPERA — el token de solo-lectura en el servidor.** Bloquea al punto 1 y es
   decisión de Oscar por ser una credencial, no una preferencia técnica.

## 2026-08-29 — [PC viejo] MEDIDA la grieta del presupuesto: el paralelo NO es paralelo. 45 repos que tardan 1s cada uno tardan 129s juntos

Ejecutado el pendiente DESBLOQUEADO del 28-ago (medir, que nunca estuvo congelado) y el
punto 4 del PC Nuevo. La hipótesis acertaba el sitio y se quedaba corta en el motivo.

### El punto 4 del PC Nuevo, hecho

`BITACORA_MAX_LINEAS=80` puesto en el `bitacora.conf` de esta máquina. **No estaba
escrito antes**: esta máquina corría con el defecto del script (40), así que la frase
«el PC viejo sigue con MAX_LINEAS=40» era cierta de efecto pero no de fichero — no
había línea que cambiar, había línea que añadir. Las dos máquinas vuelven a coincidir.

### La medición, y por qué la hipótesis se quedaba corta

El 28-ago se supuso: «la etapa de `ls-remote` lanza 17 procesos git y espera a los 17,
y esa espera no está acotada». El sitio es ese. El motivo es peor:

```
ssh índice ....................  2s
ssh flota .....................  2s
ls-remote de UN repo ..........  1s
ls-remote de 45 repos EN PARALELO ... 129s   <- aquí está todo
```

**45 procesos de 1s no tardan 1s: tardan 129.** Salen ~2,9s por repo amortizado, o sea
que lanzarlos «en paralelo» cuesta casi lo mismo que lanzarlos en serie. En Git Bash
sobre Windows el `&` no compra concurrencia real cuando cada hijo abre su propia
conexión TLS a GitHub: lo que domina es crear el proceso y el handshake, y eso se
serializa solo.

Cuadra con el hook real: los 45s medidos con presupuesto libre (cierre limpio, 6.568
chars) son ~41s de esta etapa una vez descontados los dos SSH. El escalado es lineal con
el número de repos, no plano como se creía al escribir «en paralelo».

*(Corregido el mismo día: aquí puse «el índice tiene 17 repos» y son **10**. Conté con
`grep -c .`, que incluye las 7 líneas de comentario de `repos.txt`. Mismo fallo de
siempre: dar por dato un número que no se miró bien. La conclusión estructural no
cambia; el coste por repo real es mayor, ~4s, no 2,65s.)*

**La consecuencia de diseño:** el coste del arranque crece con el catálogo de repos. El
28-ago se razonaba sobre 17; hoy hay **45 carpetas en `~/repos`**. El día que el índice
pase de 17 a 45, el arranque se va a 129s y no entrega nada. La grieta no es un pico
esporádico por arranques solapados: es una cuesta con pendiente conocida.

### Daño visto hoy, sin buscarlo

El arranque de esta misma sesión (10:12:50) fue `42s/25s | FUERA-DE-PRESUPUESTO`, y el
registro llegó **incompleto**: se quedó sin leer el detalle de commits de este repo. Y
la primera prueba que lancé se quedó sin flota por lo mismo. El log de hoy: cuatro
FUERA-DE-PRESUPUESTO y tres DEGRADADO en doce arranques. Ya no falla en silencio —
esto se ve— pero falla a menudo.

### Pendientes

1. **EN ESPERA — acotar la ETAPA de `ls-remote`**, no cada hijo: pasado el plazo, dejar
   de esperar y usar lo que haya llegado, marcando FALLIDOS los que no contestaron. Es
   el arreglo bueno y ahora está medido, pero **es funcionalidad: lo cubre el
   congelado**. No se toca.
2. **DESBLOQUEADO — decidir el número de `BITACORA_PRESUPUESTO`.** Estaba EN ESPERA
   *solo* por falta de medición, y la medición ya está. Ojo: **subirlo no arregla nada**
   (el techo duro es el `timeout: 45` del hook en `settings.json`, y ya se roza), y
   bajarlo solo degrada antes. La palanca real que queda sin tocar código es **cuántos
   repos hay en el índice**, porque el coste es lineal en N. Decisión de Oscar, no mía:
   no la tomo yo por iniciativa propia porque cambia lo que él ve al arrancar.
3. **DESBLOQUEADO — el comentario de `MAX_LINEAS` en `bitacora.conf.example`** sigue
   mintiendo (pendiente 1 del PC Nuevo). Allí se dejó EN ESPERA por si el arreglo bueno
   cambiaba el número; el arreglo bueno está congelado, así que esperar a él es esperar
   indefinidamente. Documentación falsa, y el congelado dice explícitamente que no
   cubre corregir documentación falsa.

**Qué NO congela esto:** igual que arriba — medir no está congelado, corregir
documentación no está congelado, cambiar números locales no está congelado. Solo
funcionalidad nueva.

## 2026-08-29 — [PC Nuevo] El .example sigue vendiendo el consejo que el 28-ago quedó desmentido; y esta máquina llevaba 10 commits sin enterarse de nada

Sesión de puesta al día de esta máquina. Dos hallazgos de producto y una medición.

### 1. `bitacora.conf.example` documenta lo contrario de lo que se aprendió (SIN ARREGLAR)

El comentario de `BITACORA_MAX_LINEAS` sigue diciendo, hoy, palabra por palabra:

> «Esta sí puede ser corta sin coste: solo dice DÓNDE mirar, no el porqué, así que
> no sufre igual el truncado por líneas.»

La entrada del 28-ago de este mismo fichero lo desmiente con daño medido: el PC viejo
re-diagnosticó desde cero la avería del operator porque la entrada que el PC nuevo había
escrito esa mañana caía fuera del corte de 40 líneas. Dos diagnósticos, dos facturas.

**El producto sigue repartiendo el consejo que su propio registro de campo ya tumbó.**
Quien clone el repo hoy se lleva el valor 40 y la explicación de por qué está bien. Es el
mismo modo de fallo que `anotar.sh` sin `git` (25-ago): la documentación afirma algo que
el código y los hechos ya no sostienen, y nadie lo nota porque nada falla ruidosamente.

### 2. La medición que faltaba para elegir el número (no había ninguna)

El 28-ago se dejó anotado que 40 era un parche sin medir. Medido hoy contra la bitácora
de flota real:

```
40 líneas = 2.486 chars →  2 entradas (la 2ª cortada a mitad de frase)
80 líneas = 4.957 chars →  3 entradas
120 líneas = 7.333 chars → 4 entradas, pero con la sección de repo llena (6.000)
                            se pasa de MAX_CHARS_TOTAL=10000 → Claude Code
                            DESCARTA EL ENVÍO ENTERO
```

Ese último dato es el que acota de verdad: el techo no es estético, pasarse cuesta la
inyección completa. **80 es el mayor valor con margen seguro.** Aplicado solo en la
config local de esta máquina, no en el `.example` (ver pendientes).

Verificado ejecutando el hook de verdad desde fuera de un repo, que es el caso en que
se inyecta flota: 5.875 chars, 3 entradas, cierre limpio en `--- FIN DEL REGISTRO ---`
en vez de a mitad de frase. `9s/25s | ok` en el log.

### 3. Confirmado que el arreglo del timeout funciona fuera del PC viejo

El log de esta máquina llevaba hasta hoy el formato viejo (`bytes=2917`, sin tiempo) —
o sea, el que mentía. Tras el `git pull` la primera ejecución ya escribe
`bytes=5118 | 9s/25s | ok`. El cuarto fallo silencioso queda cerrado también aquí, y
esta vez comprobado en una segunda máquina, no solo donde se arregló.

### 4. Lo que NO viaja por git, y esta máquina demostró que importa

Esta máquina llevaba **10 commits de retraso** (27, 28 y 29-ago) y, además del código,
le faltaba todo lo que el `git pull` no trae:

- Las tres variables nuevas de `bitacora.conf` (`PRESUPUESTO`, `CARPETA_TECHO`,
  `CARPETA_MAX_CHARS`). El script tiene valores por defecto, así que **funcionaba sin
  avisar de que le faltaban** — no es un fallo, pero sí un punto ciego: la config no se
  compara nunca contra el `.example`.
- Las dos secciones nuevas de `CLAUDE.md` («Un chat por repo», «Verificar antes de
  afirmar»). Reconstruidas aquí a partir de esta bitácora, así que la redacción puede no
  ser idéntica a la del PC viejo.

Idea que sale de aquí, **sin construir y sin decidir**: el hook podría comparar las
claves de `bitacora.conf` contra las del `.example` de la versión que acaba de traerse y
decir «te faltan N variables nuevas». Es barato y ataca justo lo que hoy no avisa. No se
hace ahora: hay congelado de funcionalidad nueva (ver más abajo).

### Pendientes

1. **EN ESPERA — corregir el comentario de `MAX_LINEAS` en `bitacora.conf.example`** y
   decidir su valor por defecto. Es documentación que miente, no funcionalidad nueva,
   así que el congelado no lo cubre; se deja EN ESPERA solo porque el arreglo bueno
   (punto 2) puede cambiar el número, y no tiene sentido escribirlo dos veces.
2. **EN ESPERA — cortar la bitácora de flota por ENTRADAS enteras**, como ya hace la
   sección de repo, en vez de por líneas. Es el arreglo de verdad del fallo nº1 de los
   tres abiertos; 80 líneas solo es un parche que sigue cortando a mitad. Es
   funcionalidad, la cubre el congelado.
3. **EN ESPERA — el aviso de config desfasada** del punto 4. Funcionalidad nueva,
   congelada.
4. **DESBLOQUEADO — el PC viejo sigue con `MAX_LINEAS=40`.** Las dos máquinas difieren
   desde hoy a propósito. Subirlo allí es cambiar un número en un fichero local, no
   construir nada, y hasta que se haga el fallo que costó el doble diagnóstico sigue
   vivo en la máquina donde se manifestó. Anotado también en la bitácora de flota.

**Qué NO congela el congelado de una semana:** no congela corregir documentación falsa,
no congela cambiar números de configuración local, y no congela medir. Solo congela
funcionalidad NUEVA. Se dice explícito porque la última vez que no se dijo, una sesión
entera se quedó parada (ver la entrada del FRENO FALSO).

## 2026-08-28 — [PC viejo] Ejecutados los pasos 1 y 2 del rediseño: retirados los dos hooks, la regla pasó a CLAUDE.md

Continuación directa de la entrada del FRENO FALSO, de más abajo: esta sesión fue la
que se quedó parada leyendo mal el "no se toca hoy" y el orden del congelado. Tras la
corrección (numerado + DESBLOQUEADO/EN ESPERA explícito), quedaba ejecutar lo
desbloqueado. Hecho.

1. **Retirados `hooks/sessionstop-comprobar.sh` y `hooks/userpromptsubmit-contexto.sh`**
   del repo (`git rm`) y su wiring en `~/.claude/settings.json` (entradas `Stop` y
   `UserPromptSubmit`). Queda solo `SessionStart` -> `sessionstart-leer.sh`. JSON
   validado tras el cambio.
2. **Regla de redirección movida a `CLAUDE.md`** (sección nueva "Un chat por repo"):
   si el trabajo se va a otro repo a mitad de sesión, anotar y cortar en el de origen,
   abrir sesión nueva en el otro. Sustituye a lo que hacían los dos hooks retirados.
   *No* se tocó la sección "Verificar antes de afirmar" del mismo fichero, añadida hoy
   por otro motivo sin relación.
3. **EN ESPERA** (no tocado, y no le toca a este paso): medir la grieta del
   presupuesto (40s/25s, ver dos entradas más abajo) y el congelado de funcionalidad
   nueva de una semana, que empieza ahora que 1 y 2 están hechos.

Sin verificar todavía en vivo (haría falta una sesión nueva para comprobar que
`Stop` y `UserPromptSubmit` ya no disparan) — lo anoto aquí en vez de darlo por
bueno de memoria.

**Verificado**, mismo día: Oscar abrió sesión nueva (`b8e7e91c...`), se revisó su
transcript directamente (no el resumen que dio) y aparece `hookEvent: SessionStart`
tres veces, `Stop` y `UserPromptSubmit` cero. Retirada confirmada, no solo aplicada.

## 2026-08-28 — [PC viejo] MODO DE FALLO NUEVO: el FRENO FALSO. Una entrada bien escrita dejó parada a la sesión siguiente

Descubierto en caliente, media hora después de escribir las entradas de abajo, y es el
hallazgo más útil del día porque no lo estábamos buscando.

**Qué pasó.** Oscar abrió la sesión nueva para cerrar el trabajo pendiente. Esa sesión
leyó la bitácora, la entendió bien, y concluyó: *«la respuesta honesta a "¿tienes algo
que hacer?" es NO — lo que queda abierto está deliberadamente en espera»*. Citó las dos
frases correctas. Y se equivocó en las dos:

- Leyó **«no se toca hoy»** como «no tocar nada». Lo congelado era **bajar el número a
  ciegas**; el propio texto decía «hipótesis, SIN MEDIR TODAVÍA». **Medir estaba
  desbloqueado y era justo el siguiente paso.**
- Leyó el **congelado de una semana** como previo a todo. En el texto era el ÚLTIMO
  elemento de una lista en prosa corrida: «retirar X y Y; pasar la regla; y congelar».
  El congelado empieza DESPUÉS de retirar los hooks.

**Por qué importa, y por qué no es culpa del lector.** Su cautela fue la correcta:
respetó una decisión escrita en vez de tirar para adelante — exactamente lo que se le
pide a una sesión que hereda contexto. **El fallo es del texto, y el texto lo escribí
yo.** La prueba de que una entrada está mal es que un lector competente y prudente
saque de ella la conclusión contraria.

**El modo de fallo, que es nuevo aquí.** Este repo lleva un mes persiguiendo **el
silencio**: el sistema sabe algo y no lo dice (van cuatro casos). Esto es el espejo: **un
FRENO FALSO.** La bitácora dijo algo, se leyó bien, y **paró trabajo correcto**. Una
entrada que deja a la siguiente sesión sin poder avanzar ha fallado igual de grave que
una que no llega — y es peor de detectar, porque parece prudencia y se lee como
disciplina. Nadie sospecha de un agente que dice «esto está congelado, no lo toco».

**Regla que sale de aquí, y va a aplicarse a las entradas de este repo:**

1. **Un congelado tiene que decir qué NO congela.** «No se toca X» sin frontera se lee
   como «no se toca nada».
2. **Las listas de pendientes van numeradas, nunca en prosa corrida con puntos y coma.**
   Un «y congelar una semana» al final de una enumeración se lee como si gobernara la
   enumeración entera.
3. **Cada pendiente lleva su estado explícito: DESBLOQUEADO o EN ESPERA.** Que la
   siguiente sesión no tenga que deducirlo de la prosa; deducirlo es donde falla.

Corregidas ya las dos entradas de abajo con esos tres criterios. **Los pasos 1 y 2 del
rediseño (retirar los dos hooks, pasar la regla a `CLAUDE.md`) están DESBLOQUEADOS, y
medir la grieta del presupuesto también.** Lo único en espera es cambiar el número del
presupuesto sin medirlo antes, y el congelado de funcionalidad nueva, que empieza
después de esos dos pasos.

## 2026-08-28 — [PC viejo] VERIFICADO end-to-end el arreglo del timeout. Y queda UNA grieta: el presupuesto se escapa (40s de un tope de 25)

Nota corta de cierre del día. Léela junto a la entrada siguiente, que es la larga.

### Lo verificado, y cómo (no por informe: por transcript)

El ciclo completo funciona: **escribir → commit → push → una sesión NUEVA lo recibe.**
Comprobado sobre los ficheros, no sobre lo que dijo nadie:

```
iny=1  cancel=0   4756951c-...jsonl   <- sesión nueva: inyección real
iny=0  cancel=1   902f1450-...jsonl   <- la que murió por timeout
```

(`iny` = `"type":"hook_success"` con `"hookEvent":"SessionStart"`, que no se puede
falsificar desde un fichero, a diferencia de la frase «Bitácora leída».)

Se verificó **a pesar** de tener delante un resumen correcto de la sesión nueva, y
por un motivo que conviene no olvidar: el fallo de esta mañana ERA un informe de éxito
falso. Creer al informe habría cerrado el caso en falso por segunda vez en un día.

### La grieta que queda abierta (PENDIENTE, quinto de la lista)

El log del arranque de esa misma sesión:

```
21:16:53 | repo=ninguno      | 29s/25s | FUERA-DE-PRESUPUESTO
21:17:05 | bitacora-project  | 40s/25s | FUERA-DE-PRESUPUESTO
21:17:11 | bitacora-project  | 20s/25s | ok
```

**40 segundos con un tope de 25.** Entregó, porque 40 < 45, pero con 5 s de margen. El
fallo del timeout está **mitigado, no cerrado**: sin reloj habrían sido los 69 s de la
mañana y no habría llegado nada; con reloj llega por los pelos.

**Hipótesis, sin medir todavía:** el reloj acota cada llamada, pero la etapa de
`ls-remote` lanza 17 procesos git en paralelo y espera a los 17 (`wait`). Hubo tres
arranques en 18 segundos → ~51 procesos git simultáneos. En Windows, `timeout` acota lo
que tarda cada git, no lo que tarda el sistema en poder lanzarlos: **la cola de arranque
no está dentro de ningún reloj.**

**Arreglo propuesto:** acotar la ETAPA, no solo cada hijo. Pasado el plazo se deja de
esperar y se usa lo que haya llegado, en lugar de esperar a los 17. Los repos que no
contestaron ya tienen su camino: se marcan FALLIDOS y se conserva su marcador viejo.

**Por qué se puede dormir con esto abierto:** ya no falla en silencio. Una ejecución que
se pase deja `FUERA-DE-PRESUPUESTO` en el log y, si la matan, un `hook_cancelled` en el
transcript. Se ve. Eso era justo lo que faltaba esta mañana.

**No se toca hoy a propósito.** El presupuesto se deja en 25 sin bajarlo: bajarlo no
arregla la fuga (la espera sin acotar sigue ahí), solo cambiaría el número, y hacerlo
sin medir a las 21:20 es exactamente lo que este repo lleva un mes aprendiendo a no
hacer.

**Congelado está CAMBIAR EL NÚMERO a ciegas. MEDIR no: medir es el siguiente paso y
está desbloqueado.** Se dice explícito porque la primera sesión que leyó esto entendió
lo contrario — ver la entrada del freno falso, más abajo.

## 2026-08-28 — [PC viejo] CUARTO fallo silencioso, y el peor: el hook moría por TIMEOUT y su propio log cantaba éxito

Arreglado. La sesión empezó con Oscar preguntando si la bitácora entera es un error y
si le iría mejor borrándola. La respuesta corta, ya con números: **no**. La larga está
más abajo, porque la pregunta era buena y la primera respuesta que di era mala.

### El fallo

Esta sesión no recibió bitácora. El hook, sin embargo, dejó su línea de log de éxito:
`19:52:26 | bytes=3996`. La causa, en el transcript de la propia sesión:

```
"type": "hook_cancelled", "hookName": "SessionStart:startup",
"durationMs": 69515, "timedOut": true, "timeoutMs": 45000
```

**69,5 segundos contra un plazo de 45.** Claude Code lo mató y descartó la salida.

Y lo verdaderamente feo: el script escribió su línea de log a los ~67 s, cuando ya
llevaba 22 s muerto. **El mecanismo puesto para «poder demostrar que se dispara»
declaraba victoria justo en el caso en que fallaba.** Por eso el 28-ago por la mañana
los números cuadraban y no llegaba nada: se estaba leyendo un log que mentía.

### La causa raíz: timeouts locales, sin presupuesto global

Cada llamada de red tenía su timeout. La SUMA no tenía ninguno, y no está acotada:

```
8s (ssh índice) + 15s (ls-remote, en paralelo) + N×20s (fetch, EN SERIE) + 5s + 8s (ssh flota)
```

El `git fetch` de la sección 0 corre **una vez por repo cambiado, secuencialmente**. Con
un repo cambiado son 56 s; con dos, 76. Se midieron 69,5. Es decir: **cuanto más trabajo
hay que contarte, más probable es que muera antes de contártelo.** El fallo empeora
exactamente cuando más falta hace. Hoy hubo cinco arranques en 21 segundos (varias
ventanas a la vez, visible en el log) y eso lo remató.

Corrección a lo que pensé primero: los `ls-remote` sí van en paralelo, no eran 17×15 s.
El culpable era el fetch en serie.

### El arreglo

Un **reloj global** (`BITACORA_PRESUPUESTO`, 25 s por defecto) al que se someten las
cuatro llamadas de red. Al agotarse no se aborta: se abandona la red, **se entrega
igualmente lo local** —la bitácora del repo, que es lo que importa y no cuesta red— y
se DICE dentro del texto inyectado qué se quedó fuera. Lo que se sacrifica bajo carga
es el índice; la bitácora del repo llega siempre. Ese reparto es deliberado.

Y **el log deja de mentir**: ahora registra `22s/25s | ok`, `5s/5s | DEGRADADO` o
`FUERA-DE-PRESUPUESTO`. Una ejecución moribunda se ve de un vistazo.

Probado: normal (22 s, entrega, `ok`), presupuesto forzado a 5 s (6 s, **la bitácora del
repo llega igual**, log `DEGRADADO`, aviso visible en el texto), carpeta sin git, y los
tres JSON validados. Medido el reparto real con 17 repos: SSH 1,5 s + ls-remote 8 s +
fetches ~12 s.

**Lección, y van cuatro: el instrumento que mide el éxito tiene que medir también el
tiempo.** Un log que solo cuenta bytes no distingue «entregado» de «muerto justo
después de escribir esto». Si un hook tiene plazo, el plazo es parte del contrato y
tiene que estar en la evidencia.

### Y lo que descubrimos de paso: el sistema SÍ funciona, y más de lo que decía

Buscando la firma real de inyección (`hook_success` + `hookEvent: SessionStart`, que no
puede falsificarse desde un fichero) en los 48 transcripts de la máquina: **39 la
tienen**. El arreglo de esta mañana funcionó. La conclusión de la entrada anterior
(«cero, no ha llegado nunca») era cierta ANTES de ese arreglo, y ya no lo es.

**Y la nota del 18-ago se vendía barata.** Decía que «como argumento de ahorro de tokens
no se sostiene». La cuenta real: 2.500 tokens × ~70 sesiones ≈ 175.000 tokens, contra
179 MB de transcripts (~45M tokens) = **0,4 %**. Lo que compra ese 0,4 % no son tokens
sueltos, son **sesiones enteras que no se repiten**: una sola evitada de setenta paga el
sistema varias veces. Este repo es además el 0,4 % de las sesiones de la máquina (3 de
~70). La sensación de «llevo mucho insistiendo con esto» no está en el proyecto: está en
los hooks, que corren en las 70.

### Decidido: 3 hooks -> 1, y el diseño lo puso Oscar

Idea suya, y es mejor que lo construido: **abrir sesión en una carpeta -> leer su
bitácora; y si la conversación se va a otro repo, recomendar abrir otro chat allí.**
Eso resuelve dos de los tres fallos abiertos ELIMINANDO código:

- El nº2 (el hook `Stop` solo mira el repo de apertura) desaparece: no hay que rastrear
  qué repos tocó la sesión ni arriesgar ruido — te vas al repo, no traes el repo aquí.
- El nº3 (umbrales de contexto sin calibrar) se colapsa dentro del anterior: «corta la
  sesión» y «abre el chat en el repo que toca» son el MISMO consejo, y un chat por repo
  se mantiene corto solo, sin heurística de megabytes.

Pendiente, en ese orden — **los pasos 1 y 2 están DESBLOQUEADOS, hay que hacerlos ya**:

1. Retirar `sessionstop-comprobar.sh` (repite el error ya documentado el 16-ago:
   `Stop` se dispara en cada turno) y `userpromptsubmit-contexto.sh`.
2. Pasar la regla de redirección a `CLAUDE.md`, no a un hook.
3. **Y ENTONCES** congelar funcionalidad una semana, para usarlo en vez de construirlo.

El congelado es el paso 3: empieza **después** de 1 y 2, y afecta a funcionalidad
NUEVA. Retirar hooks no es construir, es lo contrario. Se numera porque escrito en
prosa corrida la primera sesión que lo leyó entendió que el congelado bloqueaba
también los pasos 1 y 2, y se quedó parada.

## 2026-08-28 — [PC viejo] TRES FALLOS ABIERTOS del propio sistema, uno con daño medido hoy. Punto de partida

Anotado al cerrar una sesión larga en kangurea-web, a petición de Oscar, que vio antes
que yo que lo importante de hoy no era el agente de correo sino esto. **Esta entrada es
el punto de partida del siguiente trabajo aquí.** Los tres están demostrados, no
sospechados.

### 1. El corte por líneas de la bitácora de FLOTA nos costó dinero hoy (el más grave)

`BITACORA_MAX_LINEAS` está en 40 para flota en el PC viejo. Consecuencia real, medida:

- Por la mañana, el **PC nuevo** diagnosticó una avería del operator (21 bind-mounts
  anidados ocultos bajo el montaje del padre tras los renombrados `.OLD-migrado-fase5`)
  y la anotó en flota.
- Por la tarde, el **PC viejo** diagnosticó **la misma avería desde cero**, sin verla,
  porque su entrada quedaba fuera del corte de 40 líneas. Mismo problema, misma causa,
  dos diagnósticos completos, dos facturas.

**Es exactamente el fallo que este proyecto existe para impedir, cometido por el propio
proyecto.** Y el modo de fallo es el ya conocido —truncado ciego en silencio, el mismo
que motivó pasar de cortar por líneas a cortar por entradas en la bitácora de repo—
pero la de FLOTA se quedó cortando por líneas. El comentario de `bitacora.conf.example`
dice que para flota el corte por líneas «no sufre igual» porque solo dice DÓNDE mirar;
hoy quedó demostrado que sí sufre: una sola entrada larga tapa todo lo demás.

Además, en el PC viejo `BITACORA_INDICE_TECHO=2` y `MAX_ENTRADAS=4` son un parche
anotado como tal («esto es un parche, no el arreglo… el arreglo de verdad es el filtro
por relevancia»). Sigue pendiente.

### 2. El hook Stop solo mira el repo desde el que se abrió la sesión

`sessionstop-comprobar.sh` (escrito esta misma mañana) hace `git rev-parse
--show-toplevel` y comprueba **ese** repo. Pero una sesión toca varios: la de hoy se
abrió en `kangurea-web` y modificó además `lizar-panel`, `lizar-correo` y este mismo
repo.

**Demostrado antes de anotar esto:** con un fichero sin trackear en `lizar-panel`, el
hook ejecutado desde `kangurea-web` no dijo nada. Hoy no se perdió trabajo porque se
fue commiteando sobre la marcha, pero eso es suerte, no diseño.

Idea (sin decidir): recordar los repos tocados durante la sesión —los `cwd` vistos, o
los repos bajo `~/repos` con cambios recientes— y comprobarlos todos, no solo el
actual. Cuidado con el ruido: avisar de repos que el usuario no ha tocado sería peor
que callar.

### 3. Los umbrales del hook de contexto están sin calibrar

`userpromptsubmit-contexto.sh` avisa a 2 MB y 3,5 MB de transcript. Calibrado con tres
sesiones sueltas (734 KB, 2,5 MB, 4,3 MB), no con uso real. Falta ver si avisa pronto o
tarde. El aviso disparó por primera vez en vivo hoy, a 2,6 MB / 498 turnos, y el
momento pareció razonable — pero es UNA muestra.

### Patrón transversal que salió hoy, y que quizá sea lo de fondo

Dos averías del mismo día, en sistemas distintos, con la misma forma:

- El panel sabía que el operator devolvía 404 y lo mostraba como «falta generar el
  token» — mandó a buscar el fallo en un dato que estaba correcto desde el 14-ago.
- El agente de correo sabe desde el 21-ago que el buzón de un cliente se está llenando
  y lo descarta en silencio, 93 veces en un día.

**El sistema sabe algo importante y no lo dice.** No es un bug de un repo: es una forma
de fallar. Merece pensar si la bitácora (o los hooks) pueden capturar esa clase de
señal, porque las dos se descubrieron de casualidad y las dos llevaban días o semanas
sonando sin que nadie las oyera.

## 2026-08-28 — [PC viejo] Tercer hook: avisar de cuándo sale a cuenta CORTAR la sesión (eje nuevo: el coste)

**IMPORTANTE PARA EL OTRO PC: hay que tocar `~/.claude/settings.json` a mano.** El
script llega con `git pull`, pero el registro del hook no viaja por git. Añadir un
bloque `UserPromptSubmit` igual que los de `SessionStart`/`Stop`, apuntando a
`hooks/userpromptsubmit-contexto.sh`, timeout 10.

**La idea, de Oscar.** Este proyecto razonaba el momento de anotar sobre un solo eje:
la PÉRDIDA — de ahí que NOTAS-DE-CAMPO.md elija `PreCompact` («el único instante en
que el sistema sabe con certeza que el contexto está a punto de perderse»). Falta el
otro eje: el COSTE. Cada turno reenvía toda la conversación, así que el precio por
turno crece sin parar, mientras que escribir una entrada de bitácora cuesta siempre lo
mismo. Llega un punto en que arrastrar el historial cuesta más de lo que aporta.

**La consecuencia, que es lo que hacía falta ver:** «¿cada cuánto guardo?» y «¿cuándo
abro otro chat?» son LA MISMA PREGUNTA. Sin bitácora, cortar es perder; con bitácora,
cortar es reciclar. Se guarda cuando se va a cortar, y se corta cuando el contexto ya
no compensa. Dicho de otra forma: **la bitácora no es documentación, es un compresor de
contexto**. Medido hoy en kangurea-web: 2,5 MB de transcript cuyo valor entero cabía en
las dos entradas que generó, ~4 KB. Compresión ~600:1, y lo que se tira es ruido.

**Y no es solo dinero.** Con el contexto cargado el agente falla más. En esa misma
sesión: olvidó anotar en la bitácora teniéndolo como norma, y dio por verificados unos
bind-mounts que no lo estaban. Fallos de atención, no de conocimiento — justo lo que le
pasa a un contexto sobrecargado. Arrancar limpio leyendo la bitácora tiene la misma
información útil con muchísimo menos ruido.

**Añadido `hooks/userpromptsubmit-contexto.sh`.** Se dispara al enviar el usuario un
mensaje (antes de que el agente responda), mide el transcript de la sesión y, si cruza
umbral, inyecta `additionalContext` para que el agente sugiera cortar AL FINAL de su
respuesta, sin interrumpir lo que se esté haciendo. Umbrales: 2 MB aviso, 3,5 MB
urgente, configurables (`BITACORA_CONTEXTO_AVISO` / `_URGENTE`). Un solo aviso por
escalón y sesión — repetirlo en cada turno es el error ya documentado aquí con el otro
hook. Sin jq ni node: wc, grep y sed.

**Regalo del corte, que resuelve una duda vieja:** cambiar de modelo tiene un peaje
(la caché de prompt va ligada al modelo), pero cortar la sesión tira esa caché
igualmente — así que EN EL INSTANTE DEL CORTE cambiar de modelo sale gratis. Por eso el
aviso incluye el modelo en uso. La respuesta a «¿bajo a Sonnet?» nunca fue sí ni no:
era «no a mitad de chat, sí al empezar el siguiente».

**Qué NO hace:** no calcula el punto exacto — haría falta saber cuántos turnos quedan.
Es una heurística con umbral. El hook mide (peso, turnos, modelo) y el agente juzga si
cortar ahí tiene sentido y qué modelo conviene después, que depende del trabajo que
venga y el hook no puede saberlo.

**Umbrales calibrados** con sesiones reales de kangurea-web: 734 KB (corta, cómoda),
2,5 MB (larga, ya con despistes), 4,3 MB (muy pasada). A revisar con uso real.

**Probado antes de commitear:** sesión de 2,5 MB (avisa, con datos correctos), misma
sesión otra vez (no repite), sesión de 734 KB (calla), sin `session_id` (calla),
`session_id` inexistente (calla), y el JSON de salida validado.

## 2026-08-28 — [PC viejo] El hook no había entregado NUNCA una bitácora: tres fallos en cadena

Oscar preguntó si esto servía para algo. Se buscó la firma de una inyección real
(`Bitácora leída: <número>`) en TODOS los transcripts de la máquina: **cero**. El hook se
disparaba, escribía su log y producía JSON válido de 19.550 bytes — y no llegaba nada.
Tres causas independientes, las tres silenciosas.

**1. Pasarse del techo no trunca: descarta el envío ENTERO.** `lizar-informes` no estaba
en `/opt/bitacora/repos.txt`, así que no tenía fecha en el índice y la sección 1 caía al
`else` con `MAX_ENTRADAS=4` en vez de `INDICE_TECHO=2`. Cuatro entradas = 15.113
caracteres, total 18.777. Claude Code no recorta: tira el envío completo y no deja rastro
ni en el transcript ni en el `systemMessage`. Añadido el repo al índice, pero eso era solo
el disparador.

**2. Los dos relojes compartían campo.** `$VISTO` guardaba a la vez «el índice consultó el
remoto» y «leíste esta bitácora». La sección 0 lo reescribe para TODOS los repos desde
CUALQUIER carpeta, así que abrir un chat en el escritorio marcaba como leído un repo que
no habías tocado en días: el corte salía casi siempre «hoy» y el filtro se lo comía todo.
Al meter el repo en el índice, el fallo 1 se convirtió en este — 19 entradas leyéndose
«vacía todavía». Separados en dos ficheros: `$VISTO` (SHA del índice) y `$LEIDO`
(lecturas, indexado por RUTA y escrito solo cuando esa bitácora se muestra de verdad).

**3. No había suelo.** Cualquier filtro que se pasara de listo daba cero entradas sin
decirlo. Ahora, si el fichero tiene entradas, se enseña al menos la más reciente y se
AVISA de cuántas quedan.

Añadidos dos techos de caracteres: 6.000 para la sección del repo (mismo motivo que ya
obligó a poner dos en 1b: las entradas no pesan igual) y 10.000 global, este último
cortando por líneas enteras con un `[CORTADO: ...]` visible.

El corte de fecha solo avanza cuando cambia el DÍA, a propósito: el hook se dispara dos
veces por sesión (medido, 11 s de diferencia) y si cada disparo moviera el corte, el
segundo se quedaría sin nada que enseñar.

**Lección, la misma y van tres:** lo que hay que perseguir en esta herramienta no es el
error, es el silencio. Los tres fallos eran invisibles desde dentro de la sesión — el
agente no puede echar en falta algo que nunca llegó, y el usuario acaba concluyendo que
el hook no existe. Cualquier límite nuevo tiene que fallar ruidosamente o no ponerse.

## 2026-08-27 — [PC viejo] Nuevo hook Stop: fuerza escribir, no solo leer

El producto llevaba semanas leyendo solo (`sessionstart-leer.sh`). Escribir la
bitácora de UN REPO siempre fue manual — lo dice el propio comentario de
`scripts/anotar.sh` ("Para la bitácora de un repo NO se usa esto"). Caso real
en kangurea-web, 27-ago-2026: tres commits de contenido seguidos sin ninguna
entrada, hasta que Oscar preguntó por qué no había un trigger. Lo había para
leer. No para escribir.

**Añadido `hooks/sessionstop-comprobar.sh`.** Se registra en el `Stop` del
`~/.claude/settings.json` global, junto al `SessionStart` de siempre. Al final
de cada turno, en el repo donde se esté trabajando: si hay cambios sin
commitear, o commits posteriores al último que tocó la bitácora del repo que
tocan otros ficheros, bloquea (`decision:block`) con el motivo. Se calla si no
hay repo git, la carpeta está en `BITACORA_IGNORAR`, o el repo no tiene
bitácora propia — no se le impone la convención.

Reutiliza `BITACORA_FICHERO` y `BITACORA_IGNORAR` de `~/.claude/bitacora.conf`,
el mismo fichero que ya usa la lectura — cero configuración nueva. No usa
`jq` (no estaba instalado en el Git Bash de Windows donde se escribió): el
JSON de salida se construye a mano con `printf`, sin comillas dobles en el
mensaje para no tener que escapar nada.

Importante para quien lo instale en otra máquina: **`~/.claude/settings.json`
no viaja por git** (es de fuera de este repo). Hay que añadir el bloque
`Stop` a mano, o copiarlo de una máquina que ya lo tenga — a diferencia del
script en sí, que sí llega solo con `git pull`.

Probado antes de commitear: kangurea-web limpio (calla), este mismo repo con
cambios sin commitear (bloquea, motivo correcto), un repo git real sin
`BITACORA.md` (calla), una carpeta sin git (calla).

## 2026-08-25 — [PC Nuevo] Revisión a fondo de una espec externa del propio sistema — 3 errores críticos, el más grave sobre Git

Óscar tenía en el Escritorio (`SISTEMA BITÁCORA/# ESPECIFICACIÓN TÉCNICA SISTEMA
BI.txt`, fuera de cualquier repo) una especificación completa del Sistema Bitácora
Jerárquico, escrita sin conocimiento de este repo — ni de `ESQUEMA.md` ni, sobre todo,
de `NOTAS-DE-CAMPO.md`. Pidió análisis a fondo y, después, una versión corregida
descargable. Contrastada línea a línea contra lo que este repo ya había aprendido a
base de fallos reales:

- **Crítico y factual:** la espec decía que un `git stash` hecho al cerrar sesión en
  un PC "se ve" en el otro tras `git pull`. Falso — los stashes son locales, nunca
  viajan por push/pull, y la Fase 3 entera de esa espec se apoyaba en esto. Sustituido
  por rama WIP empujada al remoto (`git push origin HEAD:wip/<maquina>-<tarea>`).
- **Crítico:** proponía un `INDEX.md` compartido y commiteado por sesión — exactamente
  el conflicto de merge de fichero único que este repo ya resolvió (`ESQUEMA.md`:
  "el estado consolidado se regenera, no se versiona"). Corregido: INDEX derivado,
  regenerado por el hook, en `.gitignore`.
- **Crítico:** proponía un wrapper que redacta la entrada de cierre invocando al LLM
  *después* de que el agente termine — el mismo diseño que este repo ya probó y
  descartó por escrito en NOTAS-DE-CAMPO ("Escribir al cerrar sesión es el peor
  momento posible"). Corregido: `PreCompact` + captura en caliente + `SessionEnd` que
  solo consolida.
- Huecos que la espec no mencionaba y este repo sí necesita: migración de los
  `BITACORA.md` monolíticos existentes, archivado, modo fuera del árbol para repos de
  cliente, concurrencia local (no solo por SSH), criterios de aceptación verificables
  por test en vez de aspiracionales, y el linter de decisiones movido a Fase 4 en vez
  de quedar como futurible — es la única pieza que da valor sin que nadie lea nada.

Versión corregida completa, con cada corrección citando la nota de campo que la
motiva: **[especificacion-tecnica-corregida-20260825.md](especificacion-tecnica-corregida-20260825.md)**.
Entregada a Óscar como descarga en la misma sesión; se commitea aquí para que quede
donde el próximo PC pueda encontrarla, no solo en su Descargas.

## 2026-08-22 — [PC Nuevo] La sección 1 lee la bitácora de la CARPETA activa en un monorepo — y de paso, un bug grave: una bitácora podía leerse "vacía" en silencio

Óscar lo pidió directo: en un monorepo (`agentes-lizar`, 22+ agentes bajo `agentes/`),
la bitácora de detalle de cada agente (`agentes/<slug>/BITACORA.md`) existía, se
escribía con disciplina, y el hook **jamás la leía** — solo miraba la raíz del repo
git. Detalle técnico completo (los tres bugs, uno de ellos grave y previo a esta
sesión) en **[NOTAS-DE-CAMPO.md](NOTAS-DE-CAMPO.md)**. En corto:

- **Nueva sección 1b** en `hooks/sessionstart-leer.sh`: sube desde `$PWD` hasta la
  raíz del repo buscando la BITACORA.md más cercana, y la añade a lo que ya se
  inyectaba. No crea nada si no existe — a diferencia de la raíz, que sí se
  autocrea. Con dos techos (entradas Y caracteres, `BITACORA_CARPETA_TECHO` /
  `BITACORA_CARPETA_MAX_CHARS`): probado en vivo que 3 entradas de una carpeta real
  sumaban 16.413 caracteres, más del doble del límite de todo el hook.
- **Bug de plataforma, encontrado al probar lo de arriba en Windows/Git Bash:**
  comparar rutas con `!=` fallaba en silencio (`git rev-parse` da `C:/...`, `$PWD` da
  `/c/...`). Arreglado con `-ef` y normalizando `$RAIZ` una vez, al calcularla.
- **El hallazgo más importante no era el que se estaba buscando:** la bitácora RAÍZ
  de `agentes-lizar` llevaba desde el 20-ago leyéndose como "vacía todavía" en TODAS
  las sesiones — una cabecera de sección sin fecha (`## Dónde va cada cosa`) antes
  del `---` rompía el `awk` de `entradas_recientes()`. Arreglado anclando el patrón a
  `## AAAA-MM-DD`. Este bug es independiente del punto 1: afecta a cualquier repo,
  tenga o no monorepo, con o sin la sección 1b.

**Probado contra ficheros reales**, no con casos inventados (la propia nota de campo
insiste en esto): `agentes-lizar` desde su raíz, desde `agentes/clon` (sin bitácora
propia — no añade nada, no duplica), y desde `agentes/informes` (con bitácora propia
— se recorta a 1 entrada para caber, avisando de las 10 que quedan fuera). Los tres
casos, sin errores en stderr, bajo los 10.000 caracteres.

**Sin resolver, y no es lo mismo que esto:** sigue sin existir la "recuperación por
relevancia" real (qué archivos tocó la tarea, no solo qué carpeta). Este cambio
resuelve el caso monorepo y dos bugs de fiabilidad — no sustituye esa pieza, que
sigue en el README como pendiente.

## 2026-08-18 — [PC viejo] Primer arranque real en esta máquina con las tres piezas de hoy

- **Sesión de verificación, sin cambios de producto.** No se tocó una línea de código: el
  repo quedó en `5d25cbb`, árbol limpio y sin commits por subir. Se anota igualmente
  porque el arranque es la única parte de esto que no tiene test — solo se comprueba
  usándola, y hoy era la primera vez en esta máquina con lo de hoy dentro.
- **Las tres piezas se estrenaron juntas y se comportaron:**
  - *Índice de cambios* — activo aquí, marcador al día (20:06), respuesta «sin movimiento
    en ninguno de los repos vigilados». Queda verificado el camino silencioso; el camino
    con commits nuevos no se ejercitó hoy en esta máquina.
  - *Aviso de truncamiento* — salió la línea «quedan 6 entrada(s) sin mostrar aquí, la más
    reciente del 2026-08-16 hacia atrás». La pérdida silenciosa que motivó
    `BITACORA_MAX_ENTRADAS` es ya un puntero, que era exactamente lo que se pedía.
  - *Aviso de trabajo sin subir* — calló, y callar era lo correcto: `git status
    --porcelain` vacío y `@{upstream}..HEAD` a 0, comprobado contra el estado real y no
    supuesto por no ver el mensaje.
- **El salto entre dispositivos tiene ya evidencia de los dos lados.** Esta máquina leyó al
  arrancar las entradas que el PC nuevo escribió hoy, sin que nadie las pasara a mano. Era
  la premisa del proyecto; hoy está vista funcionando en las dos direcciones.
- **Nada nuevo sobre los pendientes:** el aviso del índice se sigue consumiendo al leerse
  en vez de al leerlo alguien de verdad, y la fuente de verdad de `anotar.sh` sigue sin
  decidirse. Esta sesión no toca ninguno de los dos.

## 2026-08-18 — [PC Nuevo] Nuevo aviso: trabajo que solo existe en esta máquina

- **Pregunta de Oscar que lo motivó:** si se cierra sesión a medias, ¿puede el otro
  dispositivo terminar la tarea leyendo solo la bitácora? Respuesta corta: depende de si
  lo que falta está subido a git. Una nota, por detallada que sea, describe el código —
  no lo sustituye. Sin red compartida entre dispositivos, lo que no llega a git no existe
  para el otro.
- **Añadido en `hooks/sessionstart-leer.sh`, sección 1**, justo al lado del aviso ya
  existente de "repo por detrás del remoto" (misma idea, dirección contraria): si el repo
  actual tiene cambios sin guardar (`git status --porcelain`) o commits sin subir
  (`@{upstream}..HEAD`), lo dice explícitamente al arrancar sesión, sin esperar a que
  nadie se acuerde de comprobarlo.
- **No depende de que el fetch de arriba tenga éxito** (a diferencia del aviso de "por
  detrás"): comparar contra lo último que ya se sabía del remoto no necesita red.
- Probado con los 3 casos reales sobre `agentes-lizar` (repo limpio → silencio; un
  fichero sin guardar → avisa; un commit sin subir → avisa), deshaciendo cada prueba
  antes de la siguiente. El repo quedó exactamente en el mismo commit que antes de
  empezar (`2759c80`).

## 2026-08-18 — [PC Nuevo] `BITACORA_IGNORAR` de ejemplo excluía repos activos, no solo referencia

- **Bug de la plantilla, no del script.** El propio hook (línea 23) nunca excluyó
  `*/repos/*` por defecto — el `BITACORA_IGNORAR` de `bitacora.conf.example` sí lo traía,
  y es la línea que copia cada máquina a su `~/.claude/bitacora.conf`. Si alguien organiza
  sus proyectos activos dentro de `repos/` (no solo material de solo lectura), esa línea
  apaga la bitácora ahí sin avisar. Lo detecté porque `kangurea-web` vivía en
  `repos/kangurea-web` y nunca mostraba su bitácora al arrancar sesión ahí.
- **Corregido:** `BITACORA_IGNORAR="*/repos/referencia/*|*/repos/archivo/*|*/tools/*|..."`
  — excluye solo las subcarpetas que de verdad son de solo lectura o archivadas, no
  `repos/` entero.
- **`ruta_local()` también corregida:** ahora prueba también `$HOME/repos/$nombre` como
  ubicación por defecto (antes solo `$HOME/$nombre` y `$HOME/Desktop/$nombre`), para que
  el índice de cambios encuentre el clon local sin necesitar `bitacora-rutas` a mano.
- **⚠️ Esto NO se propaga solo.** `bitacora.conf.example` es una plantilla que cada
  máquina copia a su propio `~/.claude/bitacora.conf` — si esa máquina ya tenía el
  fichero copiado de antes, sigue con la línea vieja hasta que alguien la actualice a
  mano. El PC viejo ya tiene su config propio (ver su entrada del 18 ago): su
  `BITACORA_IGNORAR`, si lo copió de aquí, hay que revisarlo.

## 2026-08-18 — [PC viejo] El índice de cambios se vuelve producto: ya no es un fork

Resolución explícita de Oscar a una pregunta directa: "¿qué te queda pendiente?".
Había una divergencia real desde esta tarde — un índice de cambios probado y en uso
en la infraestructura de quien lo hizo, pero nunca traído aquí, que es donde vive el
diseño de este proyecto. Decisión, no mía: "si tú crees que es mejor, que vaya al
bitácora project".

**Qué es y qué contesta.** Al arrancar, antes de la bitácora de un repo, dice EN QUÉ
repos vigilados se ha movido algo desde la última vez que esa máquina miró — sin que
nadie lo escriba, derivado de `git ls-remote` contra un marcador local. Contesta
*dónde mirar*; la bitácora del repo sigue contestando *por qué*. Ver
[NOTAS-DE-CAMPO.md](NOTAS-DE-CAMPO.md).

**Generalizado al traerlo, no copiado tal cual.** La versión de origen llamaba a
`ssh lizar` y a rutas fijas a mano — específico de una infraestructura, justo lo que
la cabecera de este hook prohíbe ("si necesitas tocarlo para adaptarlo a tu entorno,
es un bug"). Aquí reutiliza `BITACORA_FLOTA_SSH` (ya existía) y añade
`BITACORA_INDICE_REPOS` (ruta remota a la lista de repos), `BITACORA_INDICE_TECHO`,
`BITACORA_VISTO` y `BITACORA_RUTAS`. Todo opcional: sin configurar, esta sección no
hace nada — ni un aviso, silencio limpio.

**De paso resuelve el pendiente de la nota anterior.** `entradas_recientes()` acepta
ahora una fecha opcional: con el índice activo, la sección 1 corta por la fecha real
de la última visita de esta máquina a ese repo, no por un número fijo. Sin índice,
sigue el corte por `BITACORA_MAX_ENTRADAS` de antes — se degrada, no se rompe.

**Probado contra infraestructura real**, no solo con ficheros de prueba: contra el
servidor de quien lo trajo, dentro de un repo real, con marcador viejo de verdad y
con marcador al día. Detectó correctamente commits nuevos, calculó cuántos, dijo si
la bitácora del repo se había actualizado, y resolvió la ruta local del repo en el
que se estaba ejecutando. Confirmada también la compatibilidad hacia atrás: sin
`BITACORA_INDICE_REPOS` configurado, el comportamiento es idéntico al de antes de
hoy.

**Un hallazgo de prueba, no de producto:** con `$HOME` forzado a un directorio falso
para aislar la prueba, el aviso de "repo detrás del remoto" (sección 1, ya existente)
dio un falso "no se pudo comprobar". No es un bug — `git fetch` no encontraba
configuración bajo el `$HOME` de mentira. Repetido con `$HOME` real: correcto.
Anotado por si alguien más repite el mismo tipo de prueba y se confunde igual.

**Lo que sigue sin resolver, y no se resuelve aquí:** el aviso del índice se consume
al leerse, no cuando alguien lo lee de verdad — ver la nota de campo. Y la migración
de quien usaba el fork suelto a esta versión configurable queda para otra entrada.

## 2026-08-18 — [PC viejo] Truncar en silencio, en los dos extremos del tubo

Un día de uso real ha dado tres notas de campo. Las tres son la misma familia de fallo:
**cortar sin decirlo**. Ver [NOTAS-DE-CAMPO.md](NOTAS-DE-CAMPO.md).

**Al leer.** La nota de `head -40` ya existía, pero hablaba de *relevancia*. Lo nuevo es
la medida: una bitácora de **dos días** ya se leía al **22 %**, y una entrada larga
expulsó del recorte a la del día anterior. Y lo que no estaba anotado: **no avisa**. Se
decide aquí que el aviso de truncamiento («omitidas N entradas anteriores a…») no espera
a la recuperación por relevancia — es tres líneas y convierte una pérdida silenciosa en
un puntero. **Pendiente de implementar.**

**Al escribir. Arreglado hoy, con prueba.** La ayuda del proyecto mandaba invocar
`anotar.sh` con `printf`. Una entrada con un `%` dentro se guardó a medias y el script
respondió «Anotado» y «Subido». Cambios en este repo:

- `scripts/anotar.sh` — el cuerpo va por heredoc entrecomillado en la ayuda, y hay
  rechazo de entradas que parecen truncadas **antes** de escribir (salida 3, no escribe
  nada; escape con `PERMITIR_ENTRADA_RARA=si`). Al aceptar, informa de líneas y
  caracteres guardados. Probado en Linux: rechaza el caso real y acepta el mismo texto
  enviado por heredoc con el `%` intacto.
- `hooks/sessionstart-leer.sh` — la ayuda que imprime ya no propone `printf`. Era la
  fuente de la que se copiaba la invocación, así que era el origen real del fallo.

**Fuente de verdad de `anotar.sh`:** sigue sin decidirse, y esta entrada no la decide. El
arreglo se ha aplicado a las dos copias divergentes para no dejar el fallo vivo en
ninguna; cuál manda es una decisión aparte y pendiente.

**Lo que este producto todavía no tiene, y ya funciona fuera:** un índice de arranque que
dice **en qué repos se ha movido algo desde la última sesión de esa máquina**, derivado
de `git ls-remote` contra un marcador local — sin que nadie lo escriba, así que no puede
mentir por olvido. Probado en una máquina real: anunció solo «7 commits nuevos,
BITACORA.md actualizada» sin que nadie se lo contara. Contesta *dónde mirar*, que es una
pregunta distinta de *por qué se hizo*, y hoy el esquema solo contempla la segunda. Su
sitio es este repo.

Su peaje también está medido: **~2.500 tokens fijos de entrada por sesión** entre el
registro central y el del repo. Como argumento de «ahorro de tokens» no se sostiene, y
conviene no venderlo así. Lo que sí se sostiene: trabajo que no se repite, y trampas que
no se vuelven a pagar.

## 2026-08-16 — [PC viejo] Revisión del plan de Fase 1: no hace falta migrar los cinco repos a la vez

Respuesta a la propuesta de arrancar Fase 1 completa. El plan es correcto en el fondo, pero una de sus premisas no lo es, y de ella salía la única parte cara: coordinar las dos máquinas a la vez y pedirle al humano que ejecutase comandos en la otra.

**La migración a `.bitacora/` no requiere simultaneidad.** El único estado peligroso es que una máquina *escriba* el formato nuevo mientras la otra solo sabe *leer* el viejo: la segunda se queda ciega a las entradas de la primera sin enterarse — el fallo silencioso que este proyecto dice combatir. Pero eso se disuelve separando lectura de escritura:

- Un hook que **lee los dos formatos** (si existe `.bitacora/`, lo lee; si además hay `BITACORA.md`, también) es retrocompatible. Instalarlo es inofensivo y se hace en una máquina hoy y en la otra cuando toque, en cualquier orden.
- Solo después se cambia la **escritura**, y se hace **repo por repo**, verificando cada uno. Cada paso es reversible y ninguno abre ventana de ceguera.

Descartado: la migración simultánea de los cinco repos («flag day»). Coste alto, sin vuelta atrás, y obliga a sincronizar dos máquinas y a un humano en el mismo instante. La retrocompatibilidad en lectura cuesta unas pocas líneas y elimina el problema por construcción.

**Antes de migrar nada, probar `PreCompact`.** Todo el diseño de fichero por entrada con frontmatter existe para alimentar la recuperación selectiva, y eso solo rinde si algo rellena esos campos de forma fiable. El lado de escritura sigue sin demostrarse, y este mismo repositorio ya documenta que *los hooks ejecutan comandos, no redactan*. Si `PreCompact` no puede hacer lo que el diseño asume, el esquema cambia — y se habrían migrado cinco repos a un formato que nadie rellena. Es la comprobación más barata del proyecto y desbloquea el resto de decisiones.

Orden recomendado: (1) prueba desechable de `PreCompact`; (2) hook que lee ambos formatos, en las dos máquinas; (3) fichero por entrada, repo a repo; (4) lectura selectiva al final, cuando ya haya datos en el formato nuevo que la justifiquen.

**Trabajo duplicado: el problema real de hoy, y no es de formato.** A las 22:19 se commiteó desde una máquina el arreglo de `flock` y los patrones de secreto que faltaban. A las 22:43, la otra máquina commiteó el mismo arreglo, con el mismo regex, sin saberlo. El mismo trabajo dos veces con veinte minutos de diferencia, en el proyecto cuyo propósito declarado es impedirlo.

La causa es que hoy se anota **lo que ya se hizo**. Eso sirve para el historial pero no evita la colisión, porque el aviso llega después del gasto. Propuesta: **anunciar en el registro lo que se empieza, antes de empezarlo** — una línea, y ahora que la sincronización es automática el coste es despreciable. Sin esto, Fase 1 con dos máquinas duplicará trabajo otra vez, y sobre código más caro que un `flock`.

**Fuente de verdad de `anotar.sh`.** Existen dos versiones divergentes: la del servidor de flota (con `pull --rebase` y push tolerante a fallos) y la de este repositorio. Hoy coinciden por casualidad, no por diseño. Debe decidirse cuál manda antes de que Fase 1 duplique más código; la propuesta es que mande el producto y que el servidor instale desde él, con lo específico del entorno en configuración y no en un fork.

**Aviso sobre el guardarraíl que se acaba de retirar.** Sacar `BITACORA.md` del `.gitignore` para que el producto se use a sí mismo es correcto y la entrada que lo justifica es buena. Pero esa línea era una protección **mecánica**, y lo que la sustituye es un comentario en prosa pidiendo que aquí solo entren decisiones de producto. Mientras tanto el hook sigue creando `BITACORA.md` solo en cualquier repositorio que se abra (`CREAR_SI_FALTA="si"` por defecto) y este repositorio es público. Es exactamente el error que las notas de campo llaman «el más fácil de cometer el primer día», y ahora mismo no tiene red debajo. Mínimo: `CREAR_SI_FALTA="no"` por defecto; mejor, una comprobación que rechace contenido con pinta operativa antes de commitear en un repositorio público.

## 2026-08-16 — [PC viejo] Cuatro fallos de la revisión inicial, corregidos

Revisión del primer commit desde la otra máquina (`4edb910`). Los cuatro eran reales y se anotan aquí para que no se reintroduzcan:

1. **El aviso de «registro obsoleto» no podía saltar nunca.** `rev-list HEAD..@{upstream}` compara contra lo que el repo local *ya sabía* del remoto, no contra su estado real. Sin un `fetch` previo el contador siempre daba 0. Corregido con `timeout 5 git fetch` y, si el fetch falla, un aviso explícito en vez de silencio. **La lección general:** una comprobación que no puede fallar nunca no está protegiendo nada, y da falsa confianza.
2. **Carrera en `anotar.sh`.** Dos sesiones SSH anotando a la vez leen el mismo fichero y la segunda pisa la entrada de la primera. Serializado con `flock`.
3. **Escape del sobre de datos.** Una entrada que contuviera la línea `--- FIN DEL REGISTRO ---` cerraba la delimitación antes de tiempo, y todo lo que viniera después dejaba de estar marcado como datos. Es una inyección contra el propio mecanismo de contención: se construyó el sobre y no se defendió el sobre. Neutralizado al renderizar las entradas.
4. **Faltaban patrones de secreto**: claves AWS (`AKIA…`), JWT y cadenas de conexión con credencial embebida (`proto://usuario:clave@`).

Además, `ESQUEMA.md` se marca como especificación de Fase 1 y no como lo implementado hoy — describía `.bitacora/`, frontmatter y `estado`, nada de lo cual existe todavía. Un documento de esquema que se lee como manual de uso desorienta.

## 2026-08-16 — [PC Nuevo] Este repositorio recupera su propia bitácora

- **Corregido un error de diseño del primer commit:** el `.gitignore` bloqueaba `BITACORA.md` y `.bitacora/` en este repositorio. La intención era evitar que se filtraran datos operativos a un repo público; el efecto fue que **el producto no se usaba a sí mismo**, que es la peor señal posible en un proyecto como este.
- **Decisión:** este repositorio sí lleva bitácora versionada, y contiene decisiones de producto. Lo que nunca entra es infraestructura — proveedor, despliegues, rutas, qué corre dónde. Eso no es una credencial y por eso el filtro de secretos no lo marca: es el error fácil del primer día, y va a un repositorio privado aparte.
- Sigue ignorado `ESTADO.md`, que es un derivado y se regenera al leer. Versionar un derivado conflicta en cada push.

## 2026-08-16 — [PC Nuevo] Decisiones de diseño de la v0.2

Las que se tomaron al auditar el prototipo contra el documento de proyecto. Se anotan aquí con lo descartado, que es lo que evita repetir el trabajo.

- **El disparo de escritura es `PreCompact`, no `SessionEnd`.**
  - Descartado: escribir al cerrar sesión. El hook garantiza el disparo, no el contenido — quien redacta sigue siendo el agente, y al cerrar está en su peor momento: el contexto ya se compactó y el porqué de lo descartado horas antes se perdió. `PreCompact` es el único instante en que el sistema sabe que el contexto va a morir. En sesiones largas salta varias veces; `SessionEnd` una.
  - `SessionEnd` se queda, pero solo para **consolidar** lo ya capturado. Pasa de ser tarea de memoria a tarea de formato, que no puede fallar por contexto agotado.

- **Frontmatter estricto y corto, cuerpo en prosa libre.**
  - Descartado: esquema obligatorio para todo el contenido. En el prototipo la prosa sin esquema produjo entradas de calidad alta. El esquema es para la máquina que recupera, no para el agente que escribe; uno pesado empeora las entradas.

- **Las decisiones llevan `estado: vigente | revocada | superada`.**
  - Sin ciclo de vida, un registro append-only acumula decisiones muertas junto a las vivas sin distinguirlas, y la sesión entrante tiene que deducirlo leyendo en orden inverso. Con `estado`, la lectura por defecto inyecta solo las vigentes y el coste de contexto deja de crecer con el tamaño del registro.

- **No comprimir: indexar.**
  - Descartado: compactación por capas resumiendo entradas antiguas. Resumir con un modelo introduce deriva justo en el activo del sistema, y el volumen no lo justifica — un registro real de meses son decenas de KB. El problema nunca va a ser el almacenamiento, es la recuperación.

- **El registro se entrega al modelo delimitado y marcado como DATOS.**
  - Un fichero que se inyecta solo en el arranque de todas las sesiones futuras y es escribible por cualquiera con permiso de push es un vector de inyección persistente: no requiere que la víctima visite nada. El adaptador marca la frontera e instruye ignorar directivas dentro.

- **Un fichero por entrada en `.bitacora/`.**
  - Descartado: el `BITACORA.md` único del prototipo. Funciona con un solo escritor; con dos máquinas anotando el mismo día es un conflicto de merge garantizado, en el fichero que debía reducir fricción. **Todavía no implementado** — hoy sigue siendo fichero único. Es Fase 1.

- **Rechazo de credenciales antes de escribir, no en pre-commit.**
  - En pre-commit llega tarde por dos motivos: el fichero ya está en disco y la siguiente sesión ya lo lee, y `git add -f` salta la comprobación.

## 2026-08-16 — [PC Nuevo] Primer commit: se consolida el prototipo

- Se publica el producto separado del registro que produce. El prototipo vivía disperso entre un servidor sin versionar y los hooks locales de cada máquina.
- Todo lo específico de una organización sale del código a `bitacora.conf`: alias SSH, rutas, patrones de repo y etiqueta de máquina. Mientras esos valores estén en el código no es un producto, es el script de alguien.
- El README declara explícitamente lo que **no** está implementado: escritura automática, fichero por entrada y lectura selectiva. Prometer de más en un repositorio público se paga caro.

## 2026-08-16 — [PC Nuevo] Retirado el hook `Stop`

- **Probado y descartado el mismo día.** `Stop` no se dispara al terminar la sesión: se dispara cada vez que el agente termina de responder. El aviso salía en todos los turnos y se leía como una tarea pendiente que nunca se cerraba.
- Si hace falta avisar «al terminar», el evento es `SessionEnd`. No reintentar con `Stop`.
