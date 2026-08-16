# Bitácora — bitacora-project

Registro de decisiones de este repositorio. Lo más reciente arriba.
Se lee sola al empezar sesión; hay que anotar antes de terminar y **hacer commit**,
que es lo que la lleva a los demás dispositivos.

Aquí van decisiones **de producto**. La infraestructura de quien lo usa va a su propio
registro privado — ver el aviso del README.

Formato: `## AAAA-MM-DD — [dispositivo] titular`

---

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
