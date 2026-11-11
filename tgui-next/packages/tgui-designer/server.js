/**
 * The tgui designer's local server: `yarn designer` in tgui-next.
 *
 * Builds the designer page with webpack (and rebuilds it on changes),
 * serves it with the game's real tgui CSS and Font Awesome, and does what
 * a page can't: saves designs into the repo (the interface, its route, the
 * DM file and its .dme line), runs the tgui build and a side DM compile.
 *
 * Options: --port <n> (default 3535), --no-open (don't open a browser).
 */

/* eslint-disable no-console */

const crypto = require('crypto');
const fs = require('fs');
const http = require('http');
const path = require('path');
const { spawn, exec } = require('child_process');

// Webpack 4 hashes with md4, which OpenSSL 3 (Node 17+) dropped
const realCreateHash = crypto.createHash;
crypto.createHash = (alg, ...rest) => realCreateHash(
  alg === 'md4' ? 'sha256' : alg, ...rest);

const DESIGNER = __dirname;
const TGUI_NEXT = path.resolve(DESIGNER, '../..');
const REPO = path.resolve(TGUI_NEXT, '..');
const TGUI = path.resolve(DESIGNER, '../tgui');
const DESIGNS = path.join(DESIGNER, 'designs');
const INTERFACES = path.join(TGUI, 'interfaces');
const ROUTES = path.join(TGUI, 'routes.js');
const DME = path.join(REPO, 'hippiestation.dme');
const FA = path.join(REPO, 'html', 'font-awesome');
const HEADER_MARK = 'Made with the tgui designer';
const DM_EXE = process.env.BYOND_DM
  || 'C:/Program Files (x86)/BYOND/bin/dm.exe';

const args = process.argv.slice(2);
const argValue = name => {
  const i = args.indexOf(name);
  return i >= 0 ? args[i + 1] : undefined;
};
const PORT = Number(argValue('--port')) || 3535;
const OPEN = !args.includes('--no-open');

// -----------------------------------------------------------------------
// Files

const read = file => fs.readFileSync(file, 'utf8');
const exists = file => fs.existsSync(file);
const rel = file => path.relative(REPO, file).replace(/\\/g, '/');
const eolOf = text => (/\r\n/.test(text) ? '\r\n' : '\n');
const toLf = text => text.replace(/\r\n/g, '\n');
const hash = text => crypto.createHash('sha1').update(toLf(text))
  .digest('hex');

/** Writes text with the line endings the file already uses. */
const writeKeepingEol = (file, text, eol) => {
  const out = eol === '\r\n' ? toLf(text).replace(/\n/g, '\r\n') : toLf(text);
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, out);
};

/** Is `file` inside `base`? */
const within = (base, file) => {
  const r = path.relative(base, file);
  return !!r && !r.startsWith('..') && !path.isAbsolute(r);
};

// -----------------------------------------------------------------------
// routes.js

/** { routeKey: ComponentName } */
const parseRoutes = text => {
  const map = {};
  const re = /^ {2}([a-z0-9_]+): \{\n(?: {4}.*\n)*? {4}component: \(\) => (\w+),/gm;
  let m;
  while ((m = re.exec(toLf(text))) !== null) {
    map[m[1]] = m[2];
  }
  return map;
};

const routeBlockRe = key => new RegExp(
  '^ {2}' + key + ': \\{\\n(?: {4}.*\\n)*? {2}\\},\\n', 'm');

/** routes.js with the import and route for a design, old ones gone. */
const updateRoutes = (text, design, routeLines, old) => {
  let t = toLf(text);
  // Drop what an earlier save under another name or key wrote
  if (old.route && old.route !== design.route) {
    const block = t.match(routeBlockRe(old.route));
    if (block && block[0].includes('=> ' + (old.name || design.name) + ',')) {
      t = t.replace(routeBlockRe(old.route), '');
    }
  }
  if (old.name && old.name !== design.name) {
    t = t.replace(new RegExp('^import \\{ ' + old.name
      + ' \\} from \'\\./interfaces/' + old.name + '\';\\n', 'm'), '');
  }
  // The import
  const importLine = `import { ${design.name} } from './interfaces/`
    + `${design.name}';`;
  if (!new RegExp('from \'\\./interfaces/' + design.name + '\';')
    .test(t)) {
    const lines = t.split('\n');
    let at = lines.indexOf('// hippie end');
    if (at < 0) {
      at = lines.findIndex(l => !l.startsWith('import ') && l.trim());
    }
    lines.splice(at, 0, importLine);
    t = lines.join('\n');
  }
  // The route
  const block = routeLines.join('\n') + '\n';
  if (routeBlockRe(design.route).test(t)) {
    t = t.replace(routeBlockRe(design.route), block);
  }
  else {
    const lines = t.split('\n');
    let at = lines.indexOf('  // hippie end');
    if (at < 0) {
      at = lines.indexOf('};');
    }
    lines.splice(at, 0, ...routeLines);
    t = lines.join('\n');
  }
  return t;
};

/** routes.js without a design's import and route. */
const removeFromRoutes = (text, name, route) => {
  let t = toLf(text);
  const block = t.match(routeBlockRe(route));
  if (block && block[0].includes('=> ' + name + ',')) {
    t = t.replace(routeBlockRe(route), '');
  }
  t = t.replace(new RegExp('^import \\{ ' + name
    + ' \\} from \'\\./interfaces/' + name + '\';\\n', 'm'), '');
  return t;
};

// -----------------------------------------------------------------------
// The .dme

const dmeLine = file => '#include "' + file.replace(/\//g, '\\') + '"';

/** DM's own order: by folder, a folder's files before its subfolders. */
const dmePathCompare = (a, b) => {
  const pa = a.toLowerCase().split('\\');
  const pb = b.toLowerCase().split('\\');
  for (let i = 0; i < Math.min(pa.length, pb.length); i++) {
    if (pa[i] === pb[i]) {
      continue;
    }
    const aFile = i === pa.length - 1;
    const bFile = i === pb.length - 1;
    if (aFile !== bFile) {
      return aFile ? -1 : 1;
    }
    return pa[i] < pb[i] ? -1 : 1;
  }
  return pa.length - pb.length;
};

const addToDme = (text, file) => {
  const line = dmeLine(file);
  const lines = toLf(text).split('\n');
  if (lines.includes(line)) {
    return null;
  }
  const want = file.replace(/\//g, '\\');
  let at = -1;
  let lastInclude = -1;
  for (let i = 0; i < lines.length; i++) {
    const m = lines[i].match(/^#include "(.+)"$/);
    if (!m) {
      continue;
    }
    lastInclude = i;
    if (at < 0 && dmePathCompare(want, m[1]) < 0) {
      at = i;
    }
  }
  lines.splice(at < 0 ? lastInclude + 1 : at, 0, line);
  return lines.join('\n');
};

const removeFromDme = (text, file) => {
  const line = dmeLine(file);
  const lines = toLf(text).split('\n');
  const i = lines.indexOf(line);
  if (i < 0) {
    return null;
  }
  lines.splice(i, 1);
  return lines.join('\n');
};

// -----------------------------------------------------------------------
// Lint

const runEslint = files => new Promise(resolve => {
  const eslint = path.join(TGUI_NEXT, 'node_modules', 'eslint', 'bin',
    'eslint.js');
  const child = spawn(process.execPath, [eslint, ...files], {
    cwd: TGUI_NEXT,
  });
  let output = '';
  child.stdout.on('data', d => {
    output += d;
  });
  child.stderr.on('data', d => {
    output += d;
  });
  child.on('close', code => resolve({ ok: code === 0, output }));
  child.on('error', err => resolve({ ok: false, output: err.message }));
});

// -----------------------------------------------------------------------
// Save

const NAME_RE = /^[A-Z][A-Za-z0-9]*$/;
const ROUTE_RE = /^[a-z][a-z0-9_]*$/;
const DMFILE_RE = /^[\w\-./]+\.dm$/;

const save = async body => {
  const { design, js, dm, route: routeLines, force } = body || {};
  if (!design || typeof js !== 'string' || typeof dm !== 'string'
    || !Array.isArray(routeLines)) {
    return { error: 'Bad save request.' };
  }
  if (!NAME_RE.test(design.name || '')) {
    return { error: 'Name must be PascalCase letters and digits.' };
  }
  if (!ROUTE_RE.test(design.route || '')) {
    return { error: 'Key must be lowercase letters, digits and _.' };
  }
  const dmFile = (design.dm && design.dm.file) || '';
  const dmPath = path.resolve(REPO, dmFile);
  if (!DMFILE_RE.test(dmFile) || dmFile.includes('..')
    || !within(REPO, dmPath)) {
    return { error: 'The DM file must be a path inside the repo ending '
      + 'in .dm.' };
  }
  const meta = design.meta || {};
  const jsPath = path.join(INTERFACES, design.name + '.js');
  const designPath = path.join(DESIGNS, design.name + '.json');
  const conflicts = [];

  if (exists(jsPath)) {
    const cur = read(jsPath);
    if (!cur.includes(HEADER_MARK)) {
      return { error: `interfaces/${design.name}.js is a hand-written `
        + 'interface. Pick another name.' };
    }
    const ours = meta.savedName === design.name && meta.jsHash === hash(cur);
    if (!ours && toLf(cur) !== toLf(js)) {
      conflicts.push({ file: rel(jsPath) });
    }
  }
  if (exists(dmPath)) {
    const cur = read(dmPath);
    if (!cur.includes(HEADER_MARK)) {
      return { error: `${dmFile} exists and wasn't written by the `
        + 'designer. Pick another DM file.' };
    }
    const ours = meta.savedDmFile === dmFile && meta.dmHash === hash(cur);
    if (!ours && toLf(cur) !== toLf(dm)) {
      conflicts.push({ file: dmFile });
    }
  }
  if (exists(designPath) && meta.savedName !== design.name) {
    conflicts.push({ file: rel(designPath) + ' (another design)' });
  }
  const routesText = read(ROUTES);
  const routeMap = parseRoutes(routesText);
  if (routeMap[design.route] && routeMap[design.route] !== design.name) {
    return { error: `The key ${design.route} already opens `
      + `${routeMap[design.route]}. Pick another key.` };
  }
  if (conflicts.length && !force) {
    return { conflicts };
  }

  const written = [];
  // Clean up after a rename
  const old = {
    name: meta.savedName, route: meta.savedRoute, file: meta.savedDmFile,
  };
  if (old.name && old.name !== design.name) {
    const oldJs = path.join(INTERFACES, old.name + '.js');
    if (exists(oldJs) && read(oldJs).includes(HEADER_MARK)) {
      fs.unlinkSync(oldJs);
      written.push('removed ' + rel(oldJs));
    }
    const oldDesign = path.join(DESIGNS, old.name + '.json');
    if (exists(oldDesign)) {
      fs.unlinkSync(oldDesign);
    }
  }
  if (old.file && old.file !== dmFile) {
    const oldDm = path.resolve(REPO, old.file);
    if (within(REPO, oldDm) && exists(oldDm)
      && read(oldDm).includes(HEADER_MARK)) {
      fs.unlinkSync(oldDm);
      written.push('removed ' + old.file);
    }
    const dmeText = read(DME);
    const next = removeFromDme(dmeText, old.file);
    if (next !== null) {
      writeKeepingEol(DME, next, eolOf(dmeText));
      written.push('hippiestation.dme: dropped ' + old.file);
    }
  }

  // The interface
  writeKeepingEol(jsPath, js, '\n');
  written.push(rel(jsPath));
  // routes.js
  const nextRoutes = updateRoutes(routesText, design, routeLines, old);
  if (nextRoutes !== toLf(routesText)) {
    writeKeepingEol(ROUTES, nextRoutes, eolOf(routesText));
    written.push(rel(ROUTES));
  }
  // The DM and its include
  const dmEol = exists(dmPath) ? eolOf(read(dmPath)) : '\n';
  writeKeepingEol(dmPath, dm, dmEol);
  written.push(dmFile);
  const dmeText = read(DME);
  const nextDme = addToDme(dmeText, dmFile);
  if (nextDme !== null) {
    writeKeepingEol(DME, nextDme, eolOf(dmeText));
    written.push('hippiestation.dme: included ' + dmFile);
  }
  // The design, stamped with what was written
  const saved = {
    ...design,
    meta: {
      ...meta,
      savedName: design.name,
      savedRoute: design.route,
      savedDmFile: dmFile,
      jsHash: hash(js),
      dmHash: hash(dm),
      savedAt: new Date().toISOString(),
    },
  };
  fs.mkdirSync(DESIGNS, { recursive: true });
  fs.writeFileSync(designPath, JSON.stringify(saved, null, 2) + '\n');
  written.push(rel(designPath));

  const lint = await runEslint([
    path.relative(TGUI_NEXT, jsPath).replace(/\\/g, '/'),
    path.relative(TGUI_NEXT, ROUTES).replace(/\\/g, '/'),
  ]);
  return { design: saved, written, lint };
};

// -----------------------------------------------------------------------
// Jobs: the tgui build and a side DM compile

const jobs = new Map();
let jobSeq = 0;

const startJob = what => {
  for (const job of jobs.values()) {
    if (!job.done) {
      return { error: job.label + ' is still running.' };
    }
  }
  const id = ++jobSeq;
  const job = { id, label: what, lines: [], done: false, code: null };
  jobs.set(id, job);
  const push = chunk => {
    const text = (job.partial || '') + chunk.toString();
    const parts = text.split(/\r?\n/);
    job.partial = parts.pop();
    for (const line of parts) {
      job.lines.push(line.replace(/\u001b\[[0-9;]*m/g, ''));
    }
  };
  const finish = code => {
    if (job.partial) {
      job.lines.push(job.partial);
      job.partial = '';
    }
    job.code = code;
    job.done = true;
    if (job.cleanup) {
      job.cleanup();
    }
  };
  let child;
  let command;
  if (what === 'build') {
    command = 'yarn run build';
    child = spawn('yarn', ['run', 'build'], {
      cwd: TGUI_NEXT,
      shell: true,
      env: { ...process.env, NODE_OPTIONS: '--openssl-legacy-provider' },
    });
  }
  else if (what === 'compile') {
    if (!exists(DM_EXE)) {
      jobs.delete(id);
      return { error: 'No dm.exe at ' + DM_EXE + ' (set BYOND_DM).' };
    }
    // A side copy, so a running server's .dmb isn't touched
    const side = 'tgui_designer_check.mdme';
    fs.copyFileSync(DME, path.join(REPO, side));
    command = '"' + DM_EXE + '" ' + side;
    child = spawn(DM_EXE, [side], { cwd: REPO });
    job.cleanup = () => {
      for (const ext of ['', '.dmb', '.rsc', '.int', '.lk', '.dyn.rsc']) {
        const file = path.join(REPO, side + ext);
        try {
          if (exists(file)) {
            fs.unlinkSync(file);
          }
        }
        catch (err) {
          job.lines.push('(could not remove ' + side + ext + ')');
        }
      }
    };
  }
  else {
    jobs.delete(id);
    return { error: 'Unknown job ' + what };
  }
  child.stdout.on('data', push);
  child.stderr.on('data', push);
  child.on('close', code => finish(code));
  child.on('error', err => {
    job.lines.push(err.message);
    finish(1);
  });
  return { id, command };
};

// -----------------------------------------------------------------------
// Type paths, for the DM type box

let typeIndex = null;
let typeIndexing = null;

const indexTypes = () => {
  if (typeIndexing) {
    return typeIndexing;
  }
  typeIndexing = (async () => {
    const types = new Set();
    const visit = async dir => {
      let entries;
      try {
        entries = await fs.promises.readdir(dir, { withFileTypes: true });
      }
      catch (err) {
        return;
      }
      for (const entry of entries) {
        const full = path.join(dir, entry.name);
        if (entry.isDirectory()) {
          await visit(full);
        }
        else if (entry.name.endsWith('.dm')) {
          const text = await fs.promises.readFile(full, 'utf8');
          const re = /^(\/[A-Za-z_][\w/]*)[ \t]*(?:\/\/.*)?\r?$/gm;
          let m;
          while ((m = re.exec(text)) !== null) {
            if (!/\/(proc|verb)(\/|$)/.test(m[1])) {
              types.add(m[1].replace(/\/$/, ''));
            }
          }
        }
      }
    };
    await visit(path.join(REPO, 'code'));
    await visit(path.join(REPO, 'hippiestation', 'code'));
    typeIndex = [...types].sort();
    console.log(`[designer] indexed ${typeIndex.length} DM types`);
    return typeIndex;
  })();
  return typeIndexing;
};

let iconList = null;
const icons = () => {
  if (!iconList) {
    const css = read(path.join(FA, 'css', 'all.min.css'));
    const set = new Set();
    const re = /\.fa-([a-z0-9-]+):before/g;
    let m;
    while ((m = re.exec(css)) !== null) {
      set.add(m[1]);
    }
    iconList = [...set].sort();
  }
  return iconList;
};

// -----------------------------------------------------------------------
// HTTP

const TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.map': 'application/json; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2',
  '.ttf': 'font/ttf',
  '.eot': 'application/vnd.ms-fontobject',
};

const STATIC = [
  ['/build/', path.join(DESIGNER, 'public', 'build')],
  ['/tgui/', path.join(TGUI, 'public')],
  // The game's asset cache is flat, so the CSS names its fonts bare
  ['/fa/css/', path.join(FA, 'webfonts')],
  ['/fa/', FA],
  ['/', path.join(DESIGNER, 'public')],
];

const sendJson = (res, status, obj) => {
  res.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Cache-Control': 'no-store',
  });
  res.end(JSON.stringify(obj));
};

const readBody = req => new Promise((resolve, reject) => {
  let data = '';
  req.on('data', chunk => {
    data += chunk;
    if (data.length > 20e6) {
      reject(new Error('too big'));
      req.destroy();
    }
  });
  req.on('end', () => {
    try {
      resolve(data ? JSON.parse(data) : {});
    }
    catch (err) {
      reject(err);
    }
  });
});

const serveStatic = (req, res, pathname) => {
  const file = pathname === '/' ? '/index.html' : pathname;
  for (const [prefix, dir] of STATIC) {
    if (!file.startsWith(prefix)) {
      continue;
    }
    const full = path.join(dir, decodeURIComponent(file.slice(
      prefix.length)));
    if (!within(dir, full) || !exists(full) || fs.statSync(full)
      .isDirectory()) {
      continue;
    }
    res.writeHead(200, {
      'Content-Type': TYPES[path.extname(full)] || 'application/octet-stream',
      'Cache-Control': 'no-store',
    });
    fs.createReadStream(full).pipe(res);
    return;
  }
  res.writeHead(404, { 'Content-Type': 'text/plain' });
  res.end('Not found: ' + pathname);
};

const handleApi = async (req, res, url) => {
  const q = url.searchParams;
  switch (url.pathname) {
    case '/api/designs': {
      fs.mkdirSync(DESIGNS, { recursive: true });
      const designs = fs.readdirSync(DESIGNS)
        .filter(f => f.endsWith('.json'))
        .map(f => {
          const full = path.join(DESIGNS, f);
          let title = '';
          try {
            title = JSON.parse(read(full)).title || '';
          }
          catch (err) {
            title = '(unreadable)';
          }
          const stat = fs.statSync(full);
          return {
            name: f.replace(/\.json$/, ''),
            title,
            mtime: stat.mtimeMs,
            modified: stat.mtime.toISOString().slice(0, 16)
              .replace('T', ' '),
          };
        })
        .sort((a, b) => b.mtime - a.mtime);
      return sendJson(res, 200, { designs });
    }
    case '/api/design': {
      const name = q.get('name') || '';
      if (!NAME_RE.test(name)) {
        return sendJson(res, 400, { error: 'Bad name' });
      }
      const file = path.join(DESIGNS, name + '.json');
      if (!exists(file)) {
        return sendJson(res, 404, { error: 'No design called ' + name });
      }
      return sendJson(res, 200, { design: JSON.parse(read(file)) });
    }
    case '/api/check': {
      const name = q.get('name') || '';
      const route = q.get('route') || '';
      const jsPath = path.join(INTERFACES, name + '.js');
      const jsExists = NAME_RE.test(name) && exists(jsPath);
      const routeMap = parseRoutes(read(ROUTES));
      return sendJson(res, 200, {
        jsExists,
        jsOurs: jsExists && read(jsPath).includes(HEADER_MARK),
        routeExists: !!routeMap[route],
        routeOurs: routeMap[route] === name,
        routeComponent: routeMap[route] || null,
      });
    }
    case '/api/type': {
      const types = await indexTypes();
      return sendJson(res, 200, {
        exists: types.includes((q.get('path') || '').replace(/\/$/, '')),
      });
    }
    case '/api/types': {
      const needle = (q.get('q') || '').toLowerCase();
      const types = await indexTypes();
      const hits = types.filter(t => t.toLowerCase().includes(needle));
      hits.sort((a, b) => {
        const sa = a.toLowerCase().startsWith(needle) ? 0 : 1;
        const sb = b.toLowerCase().startsWith(needle) ? 0 : 1;
        return sa - sb || a.length - b.length;
      });
      return sendJson(res, 200, { types: hits.slice(0, 40) });
    }
    case '/api/icons':
      return sendJson(res, 200, { icons: icons() });
    case '/api/save': {
      const body = await readBody(req);
      return sendJson(res, 200, await save(body));
    }
    case '/api/delete': {
      const body = await readBody(req);
      return sendJson(res, 200, removeDesign(body.name));
    }
    case '/api/run': {
      const body = await readBody(req);
      return sendJson(res, 200, startJob(body.what));
    }
    case '/api/job': {
      const job = jobs.get(Number(q.get('id')));
      if (!job) {
        return sendJson(res, 404, { error: 'No such job' });
      }
      const since = Number(q.get('since')) || 0;
      return sendJson(res, 200, {
        lines: job.lines.slice(since),
        next: job.lines.length,
        done: job.done,
        code: job.code,
      });
    }
    default:
      return sendJson(res, 404, { error: 'No such API ' + url.pathname });
  }
};

/** Removes a design and everything its saves wrote. */
const removeDesign = name => {
  if (!NAME_RE.test(name || '')) {
    return { error: 'Bad name' };
  }
  const designPath = path.join(DESIGNS, name + '.json');
  if (!exists(designPath)) {
    return { error: 'No design called ' + name };
  }
  const design = JSON.parse(read(designPath));
  const meta = design.meta || {};
  const removed = [];
  const jsPath = path.join(INTERFACES, name + '.js');
  if (exists(jsPath) && read(jsPath).includes(HEADER_MARK)) {
    fs.unlinkSync(jsPath);
    removed.push(rel(jsPath));
  }
  if (meta.savedRoute) {
    const text = read(ROUTES);
    const next = removeFromRoutes(text, name, meta.savedRoute);
    if (next !== toLf(text)) {
      writeKeepingEol(ROUTES, next, eolOf(text));
      removed.push('routes.js entry');
    }
  }
  if (meta.savedDmFile) {
    const dmPath = path.resolve(REPO, meta.savedDmFile);
    if (within(REPO, dmPath) && exists(dmPath)
      && read(dmPath).includes(HEADER_MARK)) {
      fs.unlinkSync(dmPath);
      removed.push(meta.savedDmFile);
    }
    const text = read(DME);
    const next = removeFromDme(text, meta.savedDmFile);
    if (next !== null) {
      writeKeepingEol(DME, next, eolOf(text));
      removed.push('.dme include');
    }
  }
  fs.unlinkSync(designPath);
  removed.push(rel(designPath));
  return { removed };
};

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, 'http://localhost');
  try {
    // Only this machine's browser may write into the repo
    const host = (req.headers.host || '').split(':')[0];
    if (!['localhost', '127.0.0.1'].includes(host)) {
      return sendJson(res, 403, { error: 'Local use only' });
    }
    if (url.pathname.startsWith('/api/')) {
      if (req.method === 'POST') {
        const origin = req.headers.origin;
        if (origin && !/^http:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/
          .test(origin)) {
          return sendJson(res, 403, { error: 'Bad origin' });
        }
      }
      return await handleApi(req, res, url);
    }
    serveStatic(req, res, url.pathname);
  }
  catch (err) {
    console.error(err);
    sendJson(res, 500, { error: err.message });
  }
});

// -----------------------------------------------------------------------
// Start: build the page, then serve it

const startWebpack = () => new Promise(resolve => {
  const webpack = require(path.join(TGUI_NEXT, 'node_modules', 'webpack'));
  const config = require('./webpack.config.js')({}, {
    mode: process.env.DESIGNER_MODE || 'development',
  });
  const compiler = webpack(config);
  let first = true;
  console.log('[designer] building the page…');
  compiler.watch({ aggregateTimeout: 300 }, (err, stats) => {
    if (err) {
      console.error('[designer] webpack failed:', err);
      return;
    }
    const info = stats.toJson({ all: false, errors: true, warnings: true });
    if (info.errors.length) {
      console.error('[designer] build errors:\n' + info.errors.join('\n'));
    }
    else {
      const secs = ((stats.endTime - stats.startTime) / 1000).toFixed(1);
      console.log(`[designer] page built in ${secs} s`);
    }
    if (first) {
      first = false;
      resolve();
    }
  });
});

const listen = port => new Promise((resolve, reject) => {
  server.once('error', reject);
  server.listen(port, '127.0.0.1', () => resolve(port));
});

const main = async () => {
  if (!args.includes('--no-build')) {
    await startWebpack();
  }
  let port = PORT;
  for (let i = 0; i < 10; i++) {
    try {
      await listen(port);
      break;
    }
    catch (err) {
      if (err.code !== 'EADDRINUSE') {
        throw err;
      }
      port++;
    }
  }
  const address = `http://localhost:${port}/`;
  console.log(`[designer] open ${address}`);
  indexTypes();
  if (OPEN) {
    const cmd = process.platform === 'win32'
      ? `start "" "${address}"`
      : (process.platform === 'darwin' ? 'open ' : 'xdg-open ') + address;
    exec(cmd);
  }
};

if (require.main === module) {
  main().catch(err => {
    console.error(err);
    process.exit(1);
  });
}

module.exports = {
  addToDme, dmePathCompare, parseRoutes, updateRoutes, removeFromRoutes,
};
