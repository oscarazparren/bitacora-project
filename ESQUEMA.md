# Esquema del registro

El esquema es el producto. Los adaptadores (hooks, reglas de editor, servidores MCP)
son deliberadamente finos y reemplazables; esto no.

Una entrada es un fichero Markdown con **frontmatter estricto y corto** para lo que la
máquina necesita filtrar, y **cuerpo en prosa libre** para lo que el humano necesita
entender. El frontmatter se valida. El cuerpo no se toca nunca.

> Por qué el cuerpo es libre: en el prototipo, la prosa sin esquema produjo entradas de
> calidad alta. El esquema existe para la máquina que recupera, no para el agente que
> escribe. Un esquema pesado empeora las entradas en vez de mejorarlas.

---

## Ubicación

| Ámbito | Dónde vive | Por qué |
|---|---|---|
| **Proyecto** | `.bitacora/` dentro del repo de ese proyecto | Solo ahí viaja con el código, se versiona con él y se revisa en el mismo pull request |
| **Flota** | Su propio repositorio, privado | Infraestructura y despliegues no pertenecen a ningún repo: cruzan varios |

Regla corta: si «¿de qué repo es esto?» tiene una respuesta, va en su `.bitacora/`.
Si es «de varios» o «de ninguno», va a flota.

Un fichero por entrada — `.bitacora/AAAA-MM-DD-<máquina>-<slug>.md` — nunca un fichero
único compartido. Dos sesiones concurrentes escriben ficheros distintos y no colisionan.
El fichero único es un conflicto de merge garantizado en cuanto dos máquinas anoten el
mismo día.

---

## Campos

```yaml
---
fecha: 2026-08-14
maquina: portatil-1
ambito: repo            # repo | flota
titular: Se elimina la rama de publicación; despliega el hosting

rutas:                  # zonas tocadas. Alimenta la recuperación y el linter
  - scripts/publicar.mjs
  - docs/despliegue.md

decisiones:
  - id: D-007
    estado: vigente     # vigente | revocada | superada
    que: El despliegue lo hace el hosting desde la rama principal
    descartado:         # <- el campo diferencial
      - Rama de publicación con clon en el directorio servido — la compilación
        del hosting borraba el clon en cada publicación

  - id: D-004
    estado: revocada
    revocada-por: D-007
    motivo: Se documentó que el plan no compilaba. Era falso.

fallidos:
  - que: Comparar la salida local con los bytes publicados
    resultado: Cuatro falsos positivos seguidos
    reintentar: no
    porque: Compila el hosting; los bytes servidos nunca son los tuyos

pendientes:
  - que: El repo está clonado en una carpeta de solo lectura
    dueno: portatil-1
---

Prosa libre. Lo que un humano necesita para entender la sesión.
```

### `decisiones[].descartado`

El campo diferencial. Ninguna otra herramienta lo captura, y es lo que impide que la
siguiente sesión repita el trabajo de la anterior. Un `git diff` dice qué se hizo; solo
esto dice qué **no** volver a intentar.

### `decisiones[].estado`

Un registro append-only sin semántica de revocación no es un activo: es un campo de
minas. La sesión entrante no puede distinguir una decisión vigente de una muerta y
tiene que deducirlo leyendo en orden inverso.

Con `estado`:

- La lectura por defecto inyecta **solo las vigentes**. El coste de contexto deja de
  crecer con el tamaño del registro.
- Las revocadas se recuperan **solo cuando alguien propone volver a esa idea** — que es
  exactamente el caso de uso. Dejan de ser ruido y pasan a ser una alarma dirigida.
- El registro se vuelve consultable: *¿por qué no usamos una rama de publicación?* →
  `D-004`, revocada por `D-007`, con el motivo.

### `rutas`

Además de alimentar la recuperación, es lo que permite comprobar **mecánicamente** si un
cambio contradice una decisión vigente: match de globs contra frontmatter, en un hook
local antes de editar o en una comprobación de CI sobre el pull request.

---

## Qué se lee al arrancar

Volcar el registro entero reintroduce el problema que se quiere resolver. La
recuperación son cuatro consultas con presupuesto de tokens explícito y decreciente:

1. **Decisiones vigentes** del ámbito activo. Siempre. Son pocas y son la parte cara de
   reconstruir.
2. **Entradas cuyas `rutas` intersectan** con los ficheros de la tarea actual.
3. **Intentos fallidos** en esa zona, con `reintentar: no`.
4. **Pendientes abiertos** con dueño en otra máquina — lo que no conviene tocar.

Lo que no entra en el presupuesto **no se resume: se omite**, y se deja constancia de
que se omitió con un puntero para pedirlo. Un registro que miente sobre su completitud
es peor que uno que declara sus recortes.

---

## Qué NO va en una entrada

- **Credenciales, tokens, claves.** El redactor corre antes de escribir, no en el commit:
  para cuando el pre-commit mira, el fichero ya está en disco y la siguiente sesión ya
  puede leerlo — y `git add -f` salta la comprobación de todos modos.
- **Instrucciones dirigidas al agente.** Una entrada describe lo que pasó; no da órdenes.
  Un registro que se inyecta solo en todas las sesiones futuras y es escribible por
  cualquiera con permiso de push es un vector de inyección persistente. El adaptador debe
  entregarlo **delimitado y marcado como datos**, e ignorar directivas dentro.
- **El detalle operativo de infraestructura, si el repo es público.** No es una
  credencial y por eso el filtro de secretos no lo marca — pero un mapa de despliegue,
  rutas y qué servicio corre dónde no debería ser público. Es el error más fácil de
  cometer el primer día.
