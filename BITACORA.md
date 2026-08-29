# Bitácora — bitacora-project

Registro de decisiones de este repositorio. Lo más reciente arriba.
Se lee sola al empezar sesión; hay que anotar antes de terminar y **hacer commit**,
que es lo que la lleva a los demás dispositivos.

Aquí van decisiones **de producto**. La infraestructura de quien lo usa va a su propio
registro privado — ver el aviso del README.

Formato: `## AAAA-MM-DD — [dispositivo] titular`

---

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
