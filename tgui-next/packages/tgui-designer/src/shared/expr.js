/**
 * Expressions: what a bound prop, a show-if or a repeat list says. They are
 * plain JS over the window's data fields (and a repeat's item), copied into
 * the generated code as they are, and evaluated here for the preview.
 *
 * Text props are templates: "Charge: {charge}%" fills in {expr} parts.
 */

import { clamp, round, toFixed } from 'common/math';

/** Helpers an expression may call; the generated code imports them. */
export const HELPERS = {
  toFixed: { fn: toFixed, from: 'common/math' },
  round: { fn: round, from: 'common/math' },
  clamp: { fn: clamp, from: 'common/math' },
};

const GLOBALS = new Set([
  'Math', 'Number', 'String', 'Boolean', 'Array', 'Object', 'JSON',
  'parseInt', 'parseFloat', 'isNaN', 'isFinite', 'Infinity', 'NaN',
  'undefined', 'null', 'true', 'false', 'typeof', 'instanceof', 'new',
  'in', 'of', 'this', 'void', 'delete', 'value', 'Date',
]);

const cache = new Map();

const compile = src => {
  let fn = cache.get(src);
  if (!fn) {
    // `with` lets an expression name data fields directly, the way the
    // generated code's destructured names do.
    // eslint-disable-next-line no-new-func
    fn = new Function('scope', 'with (scope) { return (' + src + '\n); }');
    if (cache.size > 2000) {
      cache.clear();
    }
    cache.set(src, fn);
  }
  return fn;
};

/** A scope where unknown names read as undefined instead of throwing. */
export const makeScope = vars => {
  const target = { ...vars };
  for (const name of Object.keys(HELPERS)) {
    if (!(name in target)) {
      target[name] = HELPERS[name].fn;
    }
  }
  return new Proxy(target, {
    has: (obj, key) => typeof key === 'string',
    get: (obj, key) => {
      if (key === Symbol.unscopables) {
        return undefined;
      }
      if (key in obj) {
        return obj[key];
      }
      if (typeof key === 'string' && key in window) {
        return window[key];
      }
      return undefined;
    },
  });
};

/** { value } or { error } */
export const evaluate = (src, scope) => {
  if (src === undefined || src === null || String(src).trim() === '') {
    return { value: undefined };
  }
  try {
    return { value: compile(String(src))(scope) };
  }
  catch (err) {
    return { error: err.message || String(err) };
  }
};

/** A syntax error message, or null when the expression parses. */
export const syntaxError = src => {
  if (!src || !String(src).trim()) {
    return null;
  }
  try {
    compile(String(src));
    return null;
  }
  catch (err) {
    return err.message || String(err);
  }
};

/** Splits "a {b} c" into [{ text: 'a ' }, { expr: 'b' }, { text: ' c' }]. */
export const parseTemplate = str => {
  const parts = [];
  const s = String(str === undefined || str === null ? '' : str);
  let i = 0;
  let textStart = 0;
  while (i < s.length) {
    if (s[i] === '{') {
      // Find the matching brace, allowing nested ones inside
      let depth = 1;
      let j = i + 1;
      let quote = null;
      while (j < s.length && depth > 0) {
        const c = s[j];
        if (quote) {
          if (c === '\\') {
            j++;
          }
          else if (c === quote) {
            quote = null;
          }
        }
        else if (c === '\'' || c === '"' || c === '`') {
          quote = c;
        }
        else if (c === '{') {
          depth++;
        }
        else if (c === '}') {
          depth--;
        }
        j++;
      }
      if (depth === 0) {
        if (i > textStart) {
          parts.push({ text: s.slice(textStart, i) });
        }
        const inner = s.slice(i + 1, j - 1).trim();
        if (inner) {
          parts.push({ expr: inner });
        }
        i = j;
        textStart = i;
        continue;
      }
    }
    i++;
  }
  if (textStart < s.length) {
    parts.push({ text: s.slice(textStart) });
  }
  return parts;
};

/** Fills in a template. Returns { value, errors }. */
export const fillTemplate = (str, scope) => {
  const parts = parseTemplate(str);
  // A template that is just one {expr} keeps the value's own type
  if (parts.length === 1 && parts[0].expr) {
    const res = evaluate(parts[0].expr, scope);
    return {
      value: res.value,
      errors: res.error ? [res.error] : [],
    };
  }
  let out = '';
  const errors = [];
  for (const part of parts) {
    if (part.text !== undefined) {
      out += part.text;
      continue;
    }
    const res = evaluate(part.expr, scope);
    if (res.error) {
      errors.push(res.error);
    }
    else if (res.value !== undefined && res.value !== null) {
      out += String(res.value);
    }
  }
  return { value: out, errors };
};

const KEYWORDS = new Set(('break case catch class const continue debugger '
  + 'default delete do else export extends finally for function if import '
  + 'in instanceof new return super switch this throw try typeof var void '
  + 'while with yield let static await of null true false undefined').split(
  ' '));

/**
 * Names an expression reads that aren't properties (a.b reads a), string
 * contents or keywords. Rough, but good enough to point at typos.
 */
export const freeNames = src => {
  if (!src) {
    return [];
  }
  const s = String(src)
    .replace(/'(?:\\.|[^'\\])*'/g, '\'\'')
    .replace(/"(?:\\.|[^"\\])*"/g, '""')
    .replace(/`(?:\\.|[^`\\])*`/g, '``');
  const names = new Set();
  const re = /[A-Za-z_$][\w$]*/g;
  let m;
  while ((m = re.exec(s)) !== null) {
    const before = s.slice(0, m.index).replace(/\s+$/, '');
    if (before.endsWith('.') && !before.endsWith('..')) {
      continue;
    }
    const after = s.slice(m.index + m[0].length).replace(/^\s+/, '');
    // An object key ({ a: 1 }) or an arrow param list is not a read
    if (after.startsWith(':') && /[{,]$/.test(before)) {
      continue;
    }
    if (KEYWORDS.has(m[0]) || GLOBALS.has(m[0])) {
      continue;
    }
    names.add(m[0]);
  }
  return [...names];
};

/** Names used in a template's {expr} parts. */
export const templateNames = str => {
  const names = new Set();
  for (const part of parseTemplate(str)) {
    if (part.expr) {
      freeNames(part.expr).forEach(n => names.add(n));
    }
  }
  return [...names];
};

export const hasExpr = str => parseTemplate(str).some(p => p.expr);
