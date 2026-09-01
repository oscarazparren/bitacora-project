#!/usr/bin/env node
// Bitácora — lector de transcripts y compositor del borrador. Solo lee y ordena.
//
// POR QUÉ ESTO ES UN FICHERO Y NO UN `node -e` DENTRO DEL .sh. Porque lleva comillas
// dobles, simples, barras invertidas y backticks a la vez, y meterlo en una cadena de
// shell obliga a escapar los tres niveles. Este proyecto ya se comió una entrada
// mutilada por un `%` mal escapado en un printf (NOTAS-DE-CAMPO, 18-ago) y el script
// reportó éxito igual. Un fichero aparte no tiene ese problema y se puede probar solo:
//   node borrador-leer-transcript.js --datos <transcript.jsonl>
//
// DOS MODOS, Y SON EXACTAMENTE DOS POR EL COSTE DE LOS PROCESOS:
//   --datos  <transcript.jsonl> <salida.json>
//        Recorre el transcript UNA vez, deja el JSON en <salida.json> y escupe por
//        stdout una sola línea con  inicio<TAB>fin<TAB>turnos  para el shell.
//   --cuerpo <datos.json>
//        Compone el borrador ENTERO en Markdown. Lo que el shell sabe y node no
//        (commits, git status, motivo de cierre) entra por variables de entorno.
//
// La primera versión repartía esto en ocho llamadas a node —una por sección más una
// por campo— y tardaba 3,5 s. En Git Bash sobre Windows arrancar un proceso cuesta más
// que el trabajo que hace: la misma lección que ya bajó el auditor de 9,7 s a 3,8 s.
// Y aquí no es cosmética: esto se llama desde un hook cuyo presupuesto ya se pasa de
// vez en cuando (30 s medidos contra 25 el 1-sep).

'use strict';

const fs = require('fs');

const ESCRITURA = /^(Write|Edit|MultiEdit|NotebookEdit)$/;
const SHELL = /^(Bash|PowerShell)$/;

// ---------------------------------------------------------------------------
// Modo --datos: recorrer el transcript una sola vez
// ---------------------------------------------------------------------------
function extraer(ruta, salida) {
  const maxPrompts = +(process.env.BORRADOR_MAX_PROMPTS || 60);
  const maxChars = +(process.env.BORRADOR_MAX_CHARS_PROMPT || 4000);
  const maxComandos = +(process.env.BORRADOR_MAX_COMANDOS || 80);

  let texto;
  try {
    texto = fs.readFileSync(ruta, 'utf8');
  } catch (e) {
    process.stderr.write('no pude leer ' + ruta + ': ' + e.message + '\n');
    process.exit(3);
  }

  let min = null, max = null, turnos = 0, ilegibles = 0;
  let promptsTotales = 0, comandosTotales = 0;
  const prompts = [], comandos = [];
  const ficheros = new Map(), herramientas = new Map();

  for (const linea of texto.split('\n')) {
    if (!linea.trim()) continue;
    let o;
    // Una línea rota no puede tumbar el borrador entero: se cuenta y se DICE en el
    // fichero. Saltarla en silencio sería el quinto fallo silencioso, cometido por la
    // pieza que existe para impedir los otros cuatro.
    try { o = JSON.parse(linea); } catch (e) { ilegibles++; continue; }

    // EL TRANSCRIPT NO ESTÁ ORDENADO POR FECHA (una sesión reanudada escribe la marca
    // nueva arriba y copia la historia vieja debajo; medido el 1-sep en 427e04d6:
    // línea 1 = 14:04:21, línea 3 = 13:32:17). Mínimo y máximo, nunca head/tail.
    // ISO 8601 ordena como texto, así que comparar cadenas basta.
    const ts = o.timestamp;
    if (typeof ts === 'string' && ts) {
      if (min === null || ts < min) min = ts;
      if (max === null || ts > max) max = ts;
    }

    if (o.type === 'assistant') {
      turnos++;
      const c = o.message && o.message.content;
      if (!Array.isArray(c)) continue;
      for (const b of c) {
        if (!b || b.type !== 'tool_use') continue;
        herramientas.set(b.name, (herramientas.get(b.name) || 0) + 1);
        const inp = b.input || {};
        // Solo herramientas que ESCRIBEN. Read también lleva file_path, y meterlo aquí
        // convertiría "ficheros tocados" en "ficheros mirados": el agente leería que se
        // tocó algo que no se tocó, y eso es peor que no tener la sección.
        if (ESCRITURA.test(b.name)) {
          const fp = inp.file_path || inp.notebook_path;
          if (fp) ficheros.set(fp, (ficheros.get(fp) || 0) + 1);
        }
        if (SHELL.test(b.name)) {
          comandosTotales++;
          if (comandos.length < maxComandos) {
            const cmd = String(inp.command || '').split('\n')[0].slice(0, 200).trim();
            if (cmd) comandos.push(cmd);
          }
        }
      }
      continue;
    }

    if (o.type !== 'user') continue;
    const c = o.message && o.message.content;
    // Un turno de usuario DE VERDAD trae texto. Los que traen tool_result son la
    // respuesta de una herramienta disfrazada de mensaje de usuario: no son la
    // intención de nadie, y meterlos aquí ahogaría los prompts reales — que son lo
    // único de este fichero que no se puede sacar de ningún otro sitio.
    let t = '';
    if (typeof c === 'string') t = c;
    else if (Array.isArray(c)) t = c.filter(x => x && x.type === 'text').map(x => x.text).join('\n');
    if (!t || !t.trim()) continue;

    promptsTotales++;
    if (prompts.length >= maxPrompts) continue;
    let cola = '';
    if (t.length > maxChars) {
      cola = '\n[CORTADO: ' + (t.length - maxChars) + ' caracteres más, en el transcript]';
      t = t.slice(0, maxChars);
    }
    prompts.push({ ts: ts || '?', texto: t + cola });
  }

  const porUso = (m) => [...m.entries()].sort((a, b) => b[1] - a[1]);
  fs.writeFileSync(salida, JSON.stringify({
    min, max, turnos, ilegibles, promptsTotales, comandosTotales,
    prompts, comandos,
    ficheros: porUso(ficheros),
    herramientas: porUso(herramientas)
  }));

  // Una línea, tres campos, separados por tabulador: lo que el shell necesita para
  // decidir el nombre del fichero y la ventana de commits, sin volver a arrancar node.
  process.stdout.write((min || '') + '\t' + (max || '') + '\t' + turnos + '\n');
}

// ---------------------------------------------------------------------------
// Modo --cuerpo: componer el borrador entero
// ---------------------------------------------------------------------------

// Un prompt puede contener ``` (se pegan bloques de código constantemente). Sin esto,
// el primero rompe el bloque y el resto del borrador se renderiza como Markdown suelto
// — o sea, el fichero se lee mal justo cuando más largo es. Se cuela un espacio de
// ancho cero: no cambia el texto para quien lo lee, y desarma el delimitador.
function neutralizarVallas(s) {
  return String(s).replace(/```/g, '`​``');
}

function e(nombre, porDefecto) {
  const v = process.env[nombre];
  return (v === undefined || v === '') ? (porDefecto || '') : v;
}

function componer(rutaDatos) {
  let o;
  try {
    o = JSON.parse(fs.readFileSync(rutaDatos, 'utf8'));
  } catch (err) {
    process.stderr.write('no pude releer ' + rutaDatos + '\n');
    process.exit(3);
  }

  const out = [];
  const w = (s) => out.push(s);

  w('<!-- BORRADOR MECÁNICO — NO ES UNA ENTRADA DE BITÁCORA — NO COMMITEAR -->\n');
  w('# Borrador de la sesión `' + e('B_SID8') + '` — ' + e('B_REPO_NOMBRE') + '\n\n');

  w('> **Esto es MATERIA PRIMA, no una entrada.** Lo ha compuesto un script leyendo el\n');
  w('> transcript y el `git log`. **No hay modelo detrás: nadie ha decidido todavía qué\n');
  w('> de esto importa.** No lo pegues en la bitácora tal cual.\n');
  w('>\n');
  w('> **No lo commitees, ni aquí ni en ningún sitio.** Lleva prompts literales, rutas y\n');
  w('> nombres de máquinas: el «mapa operativo» que NO es una credencial y por eso pasa\n');
  w('> entero por el filtro de secretos. Por eso este fichero vive fuera del árbol de\n');
  w('> trabajo de git, y no detrás de una línea de `.gitignore`.\n');
  w('>\n');
  w('> Cuando hayas escrito la entrada de verdad, borra este fichero.\n\n');

  w('| | |\n|---|---|\n');
  w('| Sesión | `' + e('B_SID') + '` |\n');
  w('| Repo | `' + e('B_RAIZ') + '` |\n');
  w('| Inicio → fin | ' + (o.min || '?') + ' → ' + (o.max || '?') + ' |\n');
  w('| Turnos del agente | ' + o.turnos + ' |\n');
  w('| Cierre | ' + e('B_CIERRE') + ' |\n');
  w('| ¿Anotó? (artefacto) | ' + e('B_ANOTO') + ' |\n');
  w('| Borrador generado | ' + e('B_AHORA') + ' |\n\n');

  // ---- 1. Prompts -----------------------------------------------------------
  w('---\n\n## 1. Lo que se pidió, literal\n\n');
  w('Es lo único de este fichero que no se deriva de ningún otro sitio: la intención y\n');
  w('las correcciones. Los commits dicen qué se hizo; esto dice qué se quería, y qué se\n');
  w('cambió de opinión por el camino.\n\n');
  if (!o.prompts.length) {
    w('_(ningún mensaje de usuario con texto en este transcript)_\n\n');
  } else {
    o.prompts.forEach((p, i) => {
      w('### #' + (i + 1) + ' — ' + p.ts + '\n\n```text\n' + neutralizarVallas(p.texto) + '\n```\n\n');
    });
    if (o.promptsTotales > o.prompts.length) {
      w('_[CORTADO: ' + (o.promptsTotales - o.prompts.length) +
        ' mensaje(s) más. Sube `BITACORA_BORRADOR_MAX_PROMPTS` y rehaz el borrador.]_\n\n');
    }
  }

  // ---- 2. Ficheros escritos -------------------------------------------------
  w('---\n\n## 2. Ficheros que la sesión ESCRIBIÓ (según el transcript)\n\n');
  if (!o.ficheros.length) w('_(ninguna llamada a Write/Edit/MultiEdit/NotebookEdit)_\n');
  else o.ficheros.forEach(([f, n]) => w('- `' + f + '` — ' + n + ' escritura(s)\n'));
  w('\nHerramientas usadas: ' +
    (o.herramientas.map(([h, n]) => h + '×' + n).join(', ') || 'ninguna') + '.\n\n');
  w('> **HUECO CONOCIDO, y se dice en vez de taparlo:** aquí solo salen los ficheros\n');
  w('> tocados con las herramientas de edición. **Lo que se editó desde `Bash`** (un\n');
  w('> `sed -i`, un heredoc, un `>`) **no aparece**, y hay sesiones que trabajan así de\n');
  w('> principio a fin. Por eso va debajo la lista de comandos: es el respaldo de esta\n');
  w('> sección, no un adorno. Y los commits de la sección 4 son la verdad de lo que quedó.\n\n');

  // ---- 3. Comandos ----------------------------------------------------------
  w('---\n\n## 3. Comandos ejecutados (primera línea de cada uno)\n\n');
  if (!o.comandos.length) {
    w('_(ninguno)_\n\n');
  } else {
    w('```text\n' + o.comandos.map(neutralizarVallas).join('\n') + '\n```\n');
    if (o.comandosTotales > o.comandos.length) {
      w('\n_[CORTADO: ' + (o.comandosTotales - o.comandos.length) +
        ' comando(s) más. Sube `BITACORA_BORRADOR_MAX_COMANDOS` y rehaz el borrador.]_\n');
    }
    w('\n');
  }

  // ---- 4. Commits (el artefacto) --------------------------------------------
  w('---\n\n## 4. Commits en la ventana de la sesión (' + e('B_VENTANA_H', '6') + 'h antes del cierre)\n\n');
  w('Esto es el ARTEFACTO: lo que de verdad quedó escrito. Es la misma ventana que usa\n');
  w('`auditar-sesiones.sh` para decidir si la sesión anotó — si no coincidieran, las dos\n');
  w('piezas se contradirían delante de ti.\n\n');
  w('```text\n' + neutralizarVallas(e('B_COMMITS', '(ningún commit en la ventana)')) + '\n```\n\n');

  // ---- 5. Estado del repo ---------------------------------------------------
  w('---\n\n## 5. Estado del repo AHORA (' + e('B_AHORA') + ')\n\n');
  w(e('B_NOTA_SUCIO') + '\n\n');
  w('```text\n' + neutralizarVallas(e('B_SUCIO', '(limpio)')) + '\n```\n\n');

  // ---- 6. El hueco que no se rellena ----------------------------------------
  w('---\n\n## 6. `descartado` — HUECO, a rellenar por quien lea esto\n\n');
  w('Aquí no hay nada, y no lo va a haber: **lo que se descartó no deja artefacto.** No\n');
  w('hay commit de lo que no se hizo, ni fichero de la opción que se miró y se tiró. Un\n');
  w('script no puede sacarlo del transcript sin inventárselo, y rellenar este hueco con\n');
  w('algo verosímil es la forma exacta de los cuatro fallos silenciosos del proyecto.\n\n');
  w('Si al leer los prompts de la sección 1 reconoces una alternativa descartada, **esa\n');
  w('es la parte de la entrada que solo puedes escribir tú.**\n');

  if (o.ilegibles > 0) {
    w('\n> **AVISO:** ' + o.ilegibles + ' línea(s) del transcript no eran JSON válido y se\n');
    w('> saltaron. Lo que llevaran dentro NO está en este borrador.\n');
  }

  process.stdout.write(out.join(''));
}

// ---------------------------------------------------------------------------
const a = process.argv.slice(2);
if (a[0] === '--datos' && a[1] && a[2]) extraer(a[1], a[2]);
else if (a[0] === '--cuerpo' && a[1]) componer(a[1]);
else {
  process.stderr.write('uso: borrador-leer-transcript.js --datos <transcript.jsonl> <salida.json>\n');
  process.stderr.write('     borrador-leer-transcript.js --cuerpo <datos.json>\n');
  process.exit(2);
}
