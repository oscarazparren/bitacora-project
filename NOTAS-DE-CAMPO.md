# Notas de campo

Lo aprendido usando esto de verdad, no diseñándolo. Se escribe aquí para que la
próxima persona no vuelva a pagarlo — que es exactamente lo que hace una bitácora.

---

## Un monorepo apaga la bitácora de sus propias carpetas — y una cabecera sin fecha vacía la del repo entero

Dos bugs reales, encontrados el 22-ago-2026 trabajando dentro de `agentes-lizar`
(monorepo con 22+ agentes, cada uno con su propio slug bajo `agentes/`).

**1. La sección 1 solo mira `git rev-parse --show-toplevel`.** En un repo de un solo
proyecto eso es la raíz correcta. En un monorepo NO: si la convención del propio repo
dice que cada agente lleva su `agentes/<slug>/BITACORA.md` de detalle (como decía la
cabecera de `agentes-lizar/BITACORA.md` desde el 20-ago), esa bitácora se escribía con
disciplina y **jamás se leía** — la sesión siempre arrancaba con la del repo entero,
nunca con la de la carpeta donde de verdad se estaba trabajando. Arreglado: nueva
sección 1b, sube desde `$PWD` hasta `$RAIZ` buscando la BITACORA.md más cercana.

**2. Al probarlo en Windows/Git Bash salió un tercer bug, de comparación de rutas:**
`git rev-parse --show-toplevel` devuelve `C:/Users/...`, pero `$PWD` (y `dirname` a
partir de ahí) da `/c/Users/...`. Comparar esas dos cadenas con `!=` nunca es igual
aunque sea la MISMA carpeta — el bucle de la sección 1b se pasaba de la raíz sin
darse cuenta y duplicaba la bitácora del repo como si fuera "de una carpeta". Arreglado
con `-ef` (compara dispositivo+inodo, no texto) para el corte del bucle, y
`RAIZ=$(cd "$RAIZ" && pwd)` justo al calcularla, para que el resto de comparaciones de
texto contra `$RAIZ` en todo el script (básicamente todas) dejen de depender del estilo
de ruta que use `git` en esa plataforma.

**3. El de verdad grave, y no tiene nada que ver con monorepos:** probando lo de
arriba salió que **la bitácora RAÍZ de `agentes-lizar` llevaba desde el 20-ago
leyéndose como "vacía todavía"**, en TODAS las sesiones, silenciosamente. Motivo: el
`awk` de `entradas_recientes()` corta por `/^## /` a secas -- cualquier cabecera que
empiece por `## ` cuenta como el principio de una entrada, no solo las fechadas. El
20-ago se añadió una nota permanente (`## Dónde va cada cosa (desde 2026-08-20)`)
ANTES del separador `---`, y esa cabecera se colaba como si fuera "la entrada más
reciente": consumía el hueco (con `INDICE_TECHO=2` en esa máquina, se comía la MITAD
del presupuesto) con una "fecha" que en realidad era el texto `Dónde va c` (el
`substr($0,4,10)` de esa línea) -- y como esa cadena tiene espacios, el nombre del
fichero temporal también, lo que rompe el `for f in $(ls "$dir")` sin comillas de más
abajo (word-splitting: un fichero se convierte en tres "palabras" que no existen).
Entre el hueco desperdiciado y el bucle roto, el resultado neto era cero entradas
reales leídas. **Arreglado anclando el patrón a fecha:** `/^## [0-9]{4}-[0-9]{2}-[0-9]{2}/`.
Cualquier cabecera de sección que no sea una entrada fechada, antes o después del
`---`, ahora se ignora en vez de romper el conteo.

**Lección que vale para los tres:** un fallo que se cala en silencio (bitácora "vacía"
en vez de un error visible) es el peor de los tres modos de fallo de esta herramienta,
y ya van dos veces en el mismo proyecto (la primera fue el truncado por líneas, ver
más abajo). Cualquier cambio a `entradas_recientes()` o a lo que la rodea debería
probarse contra un fichero real, no solo contra el caso feliz inventado para la prueba.

**Y un techo nuevo, con la misma lección de los techos de arriba:** la sección 1b
necesitó DOS límites, no uno -- `BITACORA_CARPETA_TECHO` (entradas) Y
`BITACORA_CARPETA_MAX_CHARS` (caracteres), porque 3 entradas de
`agentes/informes/BITACORA.md` sumaron 16.413 caracteres, más del doble del límite de
10.000 de todo el hook junto. Un número fijo de entradas no basta cuando las entradas
no pesan igual entre carpetas -- exactamente lo que ya decía la nota de más abajo
sobre `INDICE_TECHO`, ahora repetido en un sitio nuevo.

---

## El hook `Stop` no sirve para avisar al terminar

**Probado y retirado el mismo día.** `Stop` no se dispara al terminar la sesión: se
dispara **cada vez que el agente termina de responder**. El aviso salía en todos los
turnos y se leía como una tarea pendiente que nunca se cerraba.

Si hace falta avisar «al terminar», el evento es `SessionEnd`.

---

## Escribir al cerrar sesión es el peor momento posible

El hook garantiza el *disparo*, no el *contenido*: quien redacta sigue siendo el agente.
Y al cerrar sesión está en su peor momento — el contexto se ha compactado una o varias
veces, y el detalle de por qué se descartó un enfoque tres horas antes ya se resumió o
se perdió. Se le pide precisión justo cuando menos la tiene.

El disparo que importa es **`PreCompact`**: es el único instante en que el sistema sabe
con certeza que el contexto está a punto de perderse, y ocurre justo antes de la
pérdida. En sesiones largas —las que más contexto valioso generan— salta varias veces;
`SessionEnd` salta una.

Diseño correcto, de más a menos importante:

1. `PreCompact` — vuelca decisiones e intentos fallidos antes de que se pierdan.
2. Captura en caliente — un comando que el agente emite en el momento de descartar algo.
3. `SessionEnd` — **solo consolida** lo ya capturado y añade estado y pendientes. Deja de
   ser una tarea de memoria y pasa a ser una de formato, que no puede fallar por
   contexto agotado.

---

## Un fichero único es un conflicto de merge garantizado

Insertar entradas al principio de un `BITACORA.md` monolítico funciona mientras escribe
una sola máquina. En cuanto dos anotan el mismo día, colisionan — en el fichero que
precisamente debía reducir fricción.

Un fichero por entrada (`.bitacora/AAAA-MM-DD-<máquina>-<slug>.md`) lo elimina por
construcción. Y el estado consolidado se **regenera, no se versiona**: un derivado
commiteado conflicta en cada push.

En una bitácora de flota sobre un servidor el problema no aparece, porque el servidor
serializa las escrituras. Es fácil concluir de ahí que el diseño es correcto. No lo es:
solo está oculto.

---

## `head -40` no es lectura selectiva

Truncar por fecha inyecta lo más reciente, no lo más relevante — incluida
infraestructura que no tiene nada que ver con la tarea. Reintroduce por la puerta de
atrás el problema que la bitácora dice resolver, y **empeora con cada entrada**.

La recuperación real está descrita en [ESQUEMA.md](ESQUEMA.md): decisiones vigentes,
entradas cuyas rutas intersectan con la tarea, fallidos en esa zona, pendientes de otros.

**Medido el 2026-08-18: ya no es hipotético.** Una bitácora con **dos días** de vida
eran 12.687 caracteres, y el arranque inyectaba 2.829: **se leía el 22 %**. Una sola
entrada larga escrita esa noche empujó fuera del recorte la entrada del día anterior —
la que explicaba cómo se contabiliza el gasto y qué trampa tiene la facturación del
proveedor. No se perdió del fichero: dejó de leerse, que para quien arranca es lo mismo.
Dos días. La nota decía «empeora con cada entrada» y se quedaba corta: empeora rápido.

**Pero el recorte no es el fallo. El fallo es que no avisa.** Corta y calla. Quien lee
no sabe que hay más, así que no va a buscarlo — y actúa creyendo que tiene el cuadro
completo, que es peor que saber que no lo tienes. Anunciarlo («omitidas N entradas
anteriores a AAAA-MM-DD») cuesta tres líneas y convierte una pérdida silenciosa en un
puntero. Es lo mínimo viable mientras no haya recuperación por relevancia, y no debería
esperar a ella.

**La unidad del recorte también está mal.** Cortar por LÍNEAS parte entradas por la
mitad; la unidad natural del documento es la ENTRADA. Y en cuanto el arranque sabe la
fecha de la última visita de esa máquina, hay un límite mejor que cualquier número fijo:
**las entradas escritas desde entonces, enteras**, más una línea diciendo cuántas quedan
detrás. Lo que no cabe no hace falta inyectarlo: el fichero está en el repo y el agente
puede abrirlo si le hace falta. Lo inyectado es un **aviso**, no el archivo.

**Implementado el 2026-08-18.** `entradas_recientes()` en `hooks/sessionstart-leer.sh`
corta por entrada completa y avisa de lo omitido (`BITACORA_MAX_ENTRADAS`, antes
`BITACORA_MAX_LINEAS` — que se conserva solo para la bitácora de flota, que sí puede
ser corta sin coste).

**La parte por FECHA, resuelta el mismo día, unas horas después.** El índice de
cambios (ver más abajo, "Un aviso que se consume al leerlo no es un aviso") se llevó
a este repo — antes vivía solo como fork en la máquina de quien lo probó. Con el
índice activo (`BITACORA_INDICE_REPOS` configurado), la sección 1 ya no cuenta
entradas: usa la fecha de la última vez que ESTA máquina vio ESTE repo, con
`BITACORA_INDICE_TECHO` como límite de seguridad si ha pasado mucho tiempo. Sin
índice configurado, sigue el corte por número (`BITACORA_MAX_ENTRADAS`) — el
mecanismo se degrada solo, no se rompe.

---

## Sin ciclo de vida, el registro se vuelve un campo de minas

Un registro append-only acumula decisiones revocadas junto a las vigentes sin
distinguirlas. La sesión entrante tiene que deducir cuál sigue en pie leyendo en orden
inverso y confiando en su criterio.

Pasó en el prototipo: contenía la decisión de crear una rama de publicación y, más
abajo, la de eliminarla. Nada en el formato las diferenciaba.

El campo `estado: vigente | revocada | superada` lo resuelve, y además hace medible la
reincidencia — sin él hay que etiquetarla a mano.

---

## Leer una bitácora obsoleta es peor que no leer ninguna

El fallo es silencioso: crees que estás al día. Si el registro vive en un repo, el hook
tiene que comprobar si el local va por detrás del remoto y avisar.

Sobre un servidor compartido esto no pasa, porque solo hay una copia. Al pasar el
registro a un repositorio hay que resolverlo a propósito.

---

## El detalle de infraestructura no es una credencial, y por eso se escapa

Un filtro de secretos busca claves y tokens. No marca «el hosting compila desde la rama
principal y sirve desde este directorio», ni las rutas del sistema, ni qué servicio corre
en qué máquina. Todo eso junto es un mapa operativo.

Si el registro va a un repositorio público, ese es el error más probable del primer día:
**el código del producto puede ser público; los registros que produce, no.**

---

## Los hooks ejecutan comandos, no redactan

Es la limitación de fondo y conviene tenerla presente al leer cualquier promesa de
«escritura automática». Se puede garantizar que algo se dispare; no se puede garantizar
que lo que escriba valga. Todo el diseño de §7 existe para reducir esa brecha, no para
fingir que no está.

---

## El registro se comió medio hallazgo y respondió que todo bien

**Pasó el 2026-08-18.** La ayuda del propio proyecto decía de invocar `anotar.sh` así:

    printf -- "- lo que hice\n" | ssh <servidor> "bash /ruta/anotar.sh '[disp] titular'"

Una entrada contenía un `%` (era una medición: «se lee el 22 % del fichero»). `printf`
lo tomó por especificador de formato, abortó ahí y mandó por la tubería solo el prefijo.
El script guardó ese prefijo, lo commiteó, lo subió y respondió **«Anotado en la
bitácora»** y **«Subido a GitHub. 28 entradas»**. Éxito reportado sobre un dato mutilado.

Es el mismo fallo que el truncamiento de lectura, en el otro extremo del tubo: **cortar
sin decirlo**. Y es peor al escribir, porque al leer al menos el fichero sigue entero;
aquí lo que se pierde no existe en ningún sitio.

Dos arreglos, los dos aplicados:

1. **El cuerpo va por heredoc entrecomillado** (`<<'EOF'`), que no interpreta nada.
   Corregido en la ayuda del script y en la que imprime el hook, que era de donde se
   copiaba la invocación.
2. **`anotar.sh` rechaza entradas que parecen truncadas, ANTES de escribir** (salida 3,
   no escribe nada). Dos señales, las dos presentes en el incidente: el cuerpo no acaba
   en salto de línea, y hay un número impar de `**`. Con escape por
   `PERMITIR_ENTRADA_RARA=si`. Y al aceptar, informa de cuántas líneas y caracteres
   guardó, para que el que llama pueda comparar.

La lección general: **un mecanismo de registro no puede reportar éxito sin comprobar qué
guardó.** El «OK» es la parte que la gente cree, y por eso es la que hay que ganarse.

---

## Un aviso que se consume al leerlo no es un aviso

El índice de arranque compara el estado de los repos contra un marcador por máquina, y
ese marcador **se actualiza al leer**, no al cerrar. Se hizo así a propósito: si
dependiera del cierre, una sesión que muere de mala manera dejaría el marcador mintiendo.

El precio se vio el mismo día. La sesión se reanudó por la tarde, el arranque disparó, el
índice se calculó, **el marcador se actualizó — y nadie llegó a leer el aviso**. Quedó
consumido. La segunda vez que se miró, ya no había nada que contar: había que reconstruir
el estado anterior a mano para saber qué se había perdido.

Las dos opciones tienen coste, y conviene elegirlo a sabiendas:

- **Marcar al leer**: robusto ante sesiones que mueren; el aviso se lo lleva quien
  arranque primero, lo lea o no.
- **Marcar cuando el aviso se ha usado de verdad**: no se pierde, pero exige un acuse
  que el hook no puede dar por sí solo, porque él ejecuta, no lee.

Un punto intermedio barato: **no consumir el marcador hasta que el índice diga algo**, y
conservar el aviso anterior sin borrar mientras siga sin acusarse. Un aviso repetido
molesta; uno perdido no molesta a nadie, que es justo el problema. **No implementado
todavía** — sigue marcando al leer, sin ese punto intermedio.

**Implementado el 2026-08-18, más tarde el mismo día.** El índice vivía solo como
prueba en la máquina de quien lo probó; se generalizó y se trajo a este repo
(`hooks/sessionstart-leer.sh`, sección 0), configurable vía `BITACORA_FLOTA_SSH` +
`BITACORA_INDICE_REPOS`. Sigue con el compromiso de "marcar al leer" descrito arriba,
sin resolver todavía. Y de paso resolvió el pendiente de la nota anterior (corte por
fecha real, no solo por número) para quien lo configure.
