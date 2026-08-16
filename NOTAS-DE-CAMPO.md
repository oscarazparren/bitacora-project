# Notas de campo

Lo aprendido usando esto de verdad, no diseñándolo. Se escribe aquí para que la
próxima persona no vuelva a pagarlo — que es exactamente lo que hace una bitácora.

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
