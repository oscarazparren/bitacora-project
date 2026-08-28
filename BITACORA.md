# Bitácora — bitacora-project

Registro de decisiones de este repositorio. Lo más reciente arriba.
Se lee sola al empezar sesión; hay que anotar antes de terminar y **hacer commit**,
que es lo que la lleva a los demás dispositivos.

Aquí van decisiones **de producto**. La infraestructura de quien lo usa va a su propio
registro privado — ver el aviso del README.

Formato: `## AAAA-MM-DD — [dispositivo] titular`

---

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
