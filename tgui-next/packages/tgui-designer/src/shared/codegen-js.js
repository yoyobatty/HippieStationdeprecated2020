/**
 * Writes a design as a tgui-next interface (interfaces/<Name>.js) in the
 * style of the hand-written ones, lint-clean where it can be: 80 columns,
 * closing brackets after the last prop, no bare quotes in JSX text.
 */

import { HELPERS, parseTemplate, freeNames, templateNames } from './expr';
import { findPropDef, getDef, propDefsOf } from './registry';
import { rangesLines } from './ranges';
import { walk } from './model';

const MAX = 80;
const IND = '  ';

export const HEADER_MARK = 'Made with the tgui designer';

// ---------------------------------------------------------------------
// Values

const jsString = s => {
  const str = String(s);
  if (str.includes('\'') && !str.includes('"')) {
    return '"' + str.replace(/\\/g, '\\\\').replace(/\n/g, '\\n') + '"';
  }
  return '\'' + str
    .replace(/\\/g, '\\\\')
    .replace(/'/g, '\\\'')
    .replace(/\n/g, '\\n') + '\'';
};

const jsLiteral = value => {
  if (typeof value === 'string') {
    return jsString(value);
  }
  if (Array.isArray(value)) {
    return '[' + value.map(jsLiteral).join(', ') + ']';
  }
  if (value === null || value === undefined) {
    return 'null';
  }
  if (typeof value === 'object') {
    const keys = Object.keys(value);
    if (!keys.length) {
      return '{}';
    }
    return '{ ' + keys.map(k => (/^[A-Za-z_$][\w$]*$/.test(k)
      ? k : jsString(k)) + ': ' + jsLiteral(value[k])).join(', ') + ' }';
  }
  return String(value);
};

const templateLiteral = parts => '`' + parts.map(part => {
  if (part.expr !== undefined) {
    return '${' + part.expr + '}';
  }
  return part.text
    .replace(/\\/g, '\\\\')
    .replace(/`/g, '\\`')
    .replace(/\$\{/g, '\\${');
}).join('') + '`';

/** A text prop as an attribute value: { str } or { code }. */
const textValue = s => {
  const parts = parseTemplate(s);
  if (!parts.length) {
    return null;
  }
  if (parts.length === 1 && parts[0].expr !== undefined) {
    return { code: parts[0].expr };
  }
  if (parts.every(p => p.text !== undefined)) {
    const str = parts.map(p => p.text).join('');
    if (/["\\\n]/.test(str)) {
      return { code: jsString(str) };
    }
    return { str };
  }
  return { code: templateLiteral(parts) };
};

const JSX_TEXT_BAD = /[{}<>"'\n]|^\s|\s$/;

/** Template text as JSX children: [{ text }] or [{ expr: code }]. */
const textChildren = s => {
  const parts = parseTemplate(s);
  if (!parts.length) {
    return [];
  }
  const textBad = parts.some(p => p.text !== undefined
    && JSX_TEXT_BAD.test(p.text));
  if (textBad) {
    if (parts.length === 1) {
      return [{ expr: jsString(parts[0].text) }];
    }
    return [{ expr: templateLiteral(parts) }];
  }
  return [{ inline: parts }];
};

// ---------------------------------------------------------------------
// The tree as JSX elements

const handlerHead = type => {
  switch (type) {
    case 'Input':
    case 'NumberInput':
      return '(e, value) =>';
    case 'Dropdown':
      return 'value =>';
    default:
      return '() =>';
  }
};

const actionValue = (node, propName, prop) => {
  if (!prop || !prop.action) {
    return null;
  }
  const head = handlerHead(node.type);
  const keys = Object.keys(prop.params || {})
    .filter(k => String(prop.params[k]).trim() !== '');
  if (!keys.length) {
    return { code: `${head} act(${jsString(prop.action)})` };
  }
  const pairs = keys.map(k => {
    const expr = String(prop.params[k]).trim();
    if (!/^[A-Za-z_$][\w$]*$/.test(k)) {
      return `${jsString(k)}: ${expr}`;
    }
    return expr === k ? k : `${k}: ${expr}`;
  });
  const oneLine = `${head} act(${jsString(prop.action)}, { `
    + pairs.join(', ') + ' })';
  return {
    code: oneLine,
    lines: [
      `${head} act(${jsString(prop.action)}, {`,
      ...pairs.map(p => IND + p + ','),
      '})',
    ],
  };
};

const SKIP_ATTRS = {
  'Text': ['text'],
  'NoticeBox': ['text'],
  'BlockQuote': ['text'],
  'ProgressBar': ['content'],
  'AnimatedNumber': ['decimals'],
  'NumberInput': ['whileDragging'],
};

const attrFor = (node, def, ctx) => {
  const prop = node.props[def.name];
  if (!prop) {
    return null;
  }
  let name = def.name;
  let value = null;
  if (def.kind === 'action') {
    value = actionValue(node, def.name, prop);
    if (value) {
      ctx.usesAct = true;
    }
    if (node.type === 'NumberInput' && node.props.whileDragging
      && node.props.whileDragging.v) {
      name = 'onDrag';
    }
  }
  else if (prop.x !== undefined) {
    if (!String(prop.x).trim()) {
      return null;
    }
    value = { code: String(prop.x).trim() };
  }
  else {
    const v = prop.v;
    if (v === undefined || v === null || v === '') {
      return null;
    }
    switch (def.kind) {
      case 'text':
        value = textValue(v);
        break;
      case 'bool':
        if (!v) {
          return null;
        }
        value = { bool: true };
        break;
      case 'number': {
        const n = Number(v);
        if (!Number.isFinite(n)) {
          return null;
        }
        value = { code: String(n) };
        break;
      }
      case 'select':
        value = typeof v === 'number' ? { code: String(v) } : { str: v };
        break;
      case 'size':
        value = typeof v === 'number' ? { code: String(v) } : { str: v };
        break;
      case 'ranges': {
        if (!v.mode || v.mode === 'none') {
          return null;
        }
        value = { lines: ['{', ...rangesLines(v).map(l => IND + l), '}'] };
        break;
      }
      case 'list':
        value = { code: jsLiteral(Array.isArray(v) ? v : []) };
        break;
      case 'expr':
        value = { code: jsLiteral(v) };
        break;
      default:
        value = { str: String(v) };
    }
  }
  if (!value) {
    return null;
  }
  // Defaults that the component already has
  if (def.name === 'labelColor' && value.str === 'label') {
    return null;
  }
  if (def.name === 'color' && value.str === 'default'
    && node.type !== 'Text') {
    return null;
  }
  return { name, ...value };
};

const elementOf = (node, ctx, depth) => {
  const def = getDef(node.type);
  const tag = def ? def.jsx : node.type;
  ctx.components.add(tag.split('.')[0]);
  ctx.maxDepth = Math.max(ctx.maxDepth, depth);
  const el = { tag, attrs: [], children: [] };
  const skip = SKIP_ATTRS[node.type] || [];
  const defs = propDefsOf(node.type);
  for (const propDef of defs) {
    if (skip.includes(propDef.name)) {
      continue;
    }
    const attr = attrFor(node, propDef, ctx);
    if (attr) {
      el.attrs.push(attr);
    }
  }
  // A fixed tab is keyed by its label, the way hand-written ones are
  if (node.type === 'Tabs.Tab') {
    const label = node.props.label && node.props.label.v;
    const fixed = typeof label === 'string' && /^[^"\\{}]+$/.test(label);
    if (!node.repeat) {
      el.attrs.unshift({ name: 'key', str: fixed ? label : node.id });
    }
  }
  if (node.type === 'AnimatedNumber' && node.props.decimals) {
    const d = Number(node.props.decimals.v);
    if (Number.isFinite(d)) {
      ctx.helpers.add('toFixed');
      el.attrs.push({ name: 'format', code: `value => toFixed(value, ${d})` });
    }
  }
  // Buttons slot
  const buttons = (node.slots && node.slots.buttons) || [];
  if (buttons.length) {
    const kids = childrenOf(buttons, ctx, depth + 1, null);
    el.attrs.push({ name: 'buttons', block: kids });
  }
  // Text content
  const textProp = { 'Text': 'text', 'NoticeBox': 'text',
    'BlockQuote': 'text', 'ProgressBar': 'content' }[node.type];
  if (textProp && node.props[textProp]) {
    const p = node.props[textProp];
    if (p.x !== undefined && String(p.x).trim()) {
      el.children.push({ expr: String(p.x).trim() });
    }
    else if (p.v !== undefined && p.v !== '') {
      el.children.push(...textChildren(p.v));
    }
  }
  const kids = childrenOf(node.children || [], ctx, depth + 1, node);
  if (node.type === 'Tabs.Tab' && kids.length) {
    el.children.push({ fn: kids });
  }
  else if (node.type === 'Tabs' && kids.length > 1
    && kids.some(k => k.map)) {
    el.children.push({ arr: kids });
  }
  else {
    el.children.push(...kids);
  }
  return el;
};

/**
 * A show-if as the left side of `&&`. It must come out a boolean, or a
 * 0 would be drawn: plain names get !!, a !name or a single comparison is
 * one already.
 */
const condCode = cond => {
  const c = String(cond).trim();
  if (/^[\w$.]+$/.test(c)) {
    return '!!' + c;
  }
  if (/^![\w$.]+$/.test(c)) {
    return c;
  }
  const oneComparison = /(===|!==|==|!=|<=|>=|<|>)/.test(c)
    && !/&&|\|\||\?|=>|,/.test(c);
  return oneComparison ? c : '!!(' + c + ')';
};

/** A node with its show-if and repeat, as a child entry. */
const childOf = (node, ctx, depth, parent) => {
  const el = elementOf(node, ctx, depth);
  const cond = node.showIf && String(node.showIf).trim();
  if (node.repeat && node.repeat.list && String(node.repeat.list).trim()) {
    const as = node.repeat.as || 'item';
    el.attrs.unshift({ name: 'key', code: 'i' });
    return {
      map: {
        list: String(node.repeat.list).trim(),
        as,
        filter: cond || null,
      },
      el,
    };
  }
  if (cond) {
    return { cond: condCode(cond), el };
  }
  return el;
};

const childrenOf = (list, ctx, depth, parent) => (
  list.map(child => childOf(child, ctx, depth, parent))
);

// ---------------------------------------------------------------------
// Printing

const attrInline = attr => {
  if (attr.bool) {
    return attr.name;
  }
  if (attr.str !== undefined) {
    return `${attr.name}="${attr.str}"`;
  }
  if (attr.code !== undefined && !attr.lines) {
    return `${attr.name}={${attr.code}}`;
  }
  return null;
};

const isMultiAttr = attr => !!attr.block || (!!attr.lines
  && attr.code === undefined);

let printChild = null;
let exprForm = null;

/**
 * Children as one JS expression (lines, no surrounding braces): an
 * element in parens, a show-if or map as is, several in a Fragment.
 */
const blockExpr = (children, indent) => {
  if (children.length === 1 && !children[0].tag) {
    const form = exprForm(children[0], indent);
    if (form) {
      return form;
    }
  }
  const inner = children.length === 1
    ? printChild(children[0], indent + IND)
    : printFragment(children, indent + IND);
  return ['(', ...inner, indent + ')'];
};

/**
 * Wraps expression lines in `prefix{` ... `}`. Lines after the first
 * carry their own indent already.
 */
const braced = (prefix, lines, indent, suffix = '') => {
  if (lines.length === 1) {
    return [indent + prefix + '{' + lines[0] + '}' + suffix];
  }
  return [
    indent + prefix + '{' + lines[0],
    ...lines.slice(1, -1),
    lines[lines.length - 1] + '}' + suffix,
  ];
};

/** Lines for an attribute that needs several (a block, ranges, act). */
const attrLines = (attr, indent, forceLines) => {
  if (attr.block) {
    return braced(attr.name + '=', blockExpr(attr.block, indent), indent);
  }
  if (attr.lines && (forceLines || attr.code === undefined)) {
    const lines = attr.lines;
    return [
      indent + attr.name + '={' + lines[0],
      ...lines.slice(1, -1).map(l => indent + l),
      indent + lines[lines.length - 1] + '}',
    ];
  }
  return [indent + attrInline(attr)];
};

const printFragment = (children, indent) => [
  indent + '<Fragment>',
  ...children.flatMap(child => printChild(child, indent + IND)),
  indent + '</Fragment>',
];

const inlineText = parts => parts.map(p => (p.expr !== undefined
  ? '{' + p.expr + '}'
  : p.text)).join('');

/** Splits plain JSX text into lines that fit, at spaces. */
const wrapText = (text, indent) => {
  const words = text.split(/\s+/).filter(Boolean);
  const lines = [];
  let cur = '';
  for (const word of words) {
    if (cur && (indent + cur + ' ' + word).length > MAX) {
      lines.push(indent + cur);
      cur = word;
    }
    else {
      cur = cur ? cur + ' ' + word : word;
    }
  }
  if (cur) {
    lines.push(indent + cur);
  }
  return lines;
};

const printTextChild = (child, indent) => {
  if (child.expr !== undefined) {
    return [indent + '{' + child.expr + '}'];
  }
  if (child.inline) {
    const line = inlineText(child.inline);
    if ((indent + line).length <= MAX
      || child.inline.some(p => p.expr !== undefined)) {
      return [indent + line];
    }
    return wrapText(line, indent);
  }
  return [];
};

const isTextChild = c => c.expr !== undefined || !!c.inline;

const printElement = (el, indent) => {
  const singles = el.attrs.map(attrInline);
  const allSingle = el.attrs.every(a => !isMultiAttr(a))
    && singles.every(s => s !== null);
  const hasKids = el.children.length > 0;
  const head = '<' + el.tag + (singles.length && allSingle
    ? ' ' + singles.join(' ') : '');
  // Everything on one line?
  if (allSingle) {
    if (!hasKids) {
      const line = indent + head + ' />';
      if (line.length <= MAX) {
        return [line];
      }
    }
    else if (el.children.length === 1 && isTextChild(el.children[0])) {
      const text = printTextChild(el.children[0], '');
      if (text.length === 1) {
        const line = indent + head + '>' + text[0] + '</' + el.tag + '>';
        if (line.length <= MAX) {
          return [line];
        }
      }
    }
    const open = indent + head + '>';
    if (hasKids && open.length <= MAX) {
      return [
        open,
        ...el.children.flatMap(c => printChild(c, indent + IND)),
        indent + '</' + el.tag + '>',
      ];
    }
  }
  // Props one per line, closing bracket after the last one
  const lines = [indent + '<' + el.tag];
  el.attrs.forEach(attr => {
    const single = attrInline(attr);
    if (single !== null && !isMultiAttr(attr)
      && (indent + IND + single).length <= MAX - 3) {
      lines.push(indent + IND + single);
    }
    else {
      lines.push(...attrLines(attr, indent + IND, true));
    }
  });
  if (el.attrs.length === 0) {
    lines[0] += hasKids ? '>' : ' />';
  }
  else {
    lines[lines.length - 1] += hasKids ? '>' : ' />';
  }
  if (!hasKids) {
    return lines;
  }
  return [
    ...lines,
    ...el.children.flatMap(c => printChild(c, indent + IND)),
    indent + '</' + el.tag + '>',
  ];
};

/**
 * A show-if or map child as expression lines (no braces); the first line
 * carries no indent, it follows whatever comes before it.
 */
exprForm = (child, indent) => {
  if (child.cond) {
    return [
      child.cond + ' && (',
      ...printElement(child.el, indent + IND),
      indent + ')',
    ];
  }
  if (child.map) {
    const { list, as, filter } = child.map;
    const chain = filter
      ? `${list}.filter(${as} => ${filter}).map((${as}, i) => (`
      : `${list}.map((${as}, i) => (`;
    if ((indent + '{' + chain).length <= MAX) {
      return [
        chain,
        ...printElement(child.el, indent + IND),
        indent + '))',
      ];
    }
    return [
      list,
      ...(filter ? [indent + IND + `.filter(${as} => ${filter})`] : []),
      indent + IND + `.map((${as}, i) => (`,
      ...printElement(child.el, indent + IND + IND),
      indent + IND + '))',
    ];
  }
  return null;
};

printChild = (child, indent) => {
  if (child.tag) {
    return printElement(child, indent);
  }
  if (isTextChild(child)) {
    return printTextChild(child, indent);
  }
  if (child.cond || child.map) {
    return braced('', exprForm(child, indent), indent);
  }
  if (child.fn) {
    return braced('', ['() => ' + blockExpr(child.fn, indent)[0],
      ...blockExpr(child.fn, indent).slice(1)], indent);
  }
  if (child.arr) {
    // Tabs that mix fixed and repeated tabs need one flat list
    const lines = [indent + '{['];
    for (const item of child.arr) {
      if (item.tag) {
        const el = printElement(item, indent + IND);
        el[el.length - 1] += ',';
        lines.push(...el);
      }
      else {
        const form = exprForm(item, indent + IND);
        const spread = item.map ? '...' : '';
        lines.push(indent + IND + spread + form[0], ...form.slice(1));
        lines[lines.length - 1] += ',';
      }
    }
    lines.push(indent + ']}');
    return lines;
  }
  return [];
};

// ---------------------------------------------------------------------
// Which fields the code reads

/** Every expression in the design, with the node it belongs to. */
export const expressionsOf = design => {
  const out = [];
  walk(design.root, node => {
    if (node.id === 'root') {
      return;
    }
    for (const name of Object.keys(node.props || {})) {
      const p = node.props[name];
      const def = findPropDef(node.type, name);
      if (!p || !def) {
        continue;
      }
      if (p.x !== undefined) {
        out.push({ node, where: name, src: p.x, kind: 'expr' });
      }
      else if (def.kind === 'text' && typeof p.v === 'string') {
        out.push({ node, where: name, src: p.v, kind: 'template' });
      }
      if (p.action) {
        for (const key of Object.keys(p.params || {})) {
          out.push({ node, where: name + ' ' + key, src: p.params[key],
            kind: 'expr', valueVar: !!def.valueVar });
        }
      }
    }
    if (node.showIf) {
      out.push({ node, where: 'show if', src: node.showIf, kind: 'expr' });
    }
    if (node.repeat && node.repeat.list) {
      out.push({ node, where: 'repeat', src: node.repeat.list,
        kind: 'expr' });
    }
  });
  return out;
};

export const namesUsed = design => {
  const names = new Set();
  for (const e of expressionsOf(design)) {
    const list = e.kind === 'template'
      ? templateNames(e.src) : freeNames(e.src);
    list.forEach(n => names.add(n));
  }
  return names;
};

// ---------------------------------------------------------------------

/** The interface file's text. */
export const generateJs = design => {
  const ctx = {
    components: new Set(),
    helpers: new Set(),
    usesAct: false,
    maxDepth: 0,
  };
  const top = childrenOf(design.root.children || [], ctx, 1, design.root);
  const used = namesUsed(design);
  const fields = design.fields.map(f => f.name).filter(n => used.has(n));
  for (const helper of Object.keys(HELPERS)) {
    if (used.has(helper)) {
      ctx.helpers.add(helper);
    }
  }
  let body;
  if (!top.length) {
    body = [IND + 'return null;'];
  }
  else if (top.length === 1 && top[0].cond) {
    const form = exprForm(top[0], IND);
    body = [
      IND + 'return ' + form[0],
      ...form.slice(1, -1),
      form[form.length - 1] + ';',
    ];
  }
  else {
    let jsx;
    if (top.length === 1 && top[0].tag) {
      jsx = printElement(top[0], IND + IND);
    }
    else if (top.length === 1) {
      // A component can't return a bare list
      ctx.components.add('Box');
      jsx = printElement({ tag: 'Box', attrs: [], children: top },
        IND + IND);
    }
    else {
      jsx = printFragment(top, IND + IND);
    }
    body = [IND + 'return (', ...jsx, IND + ');'];
  }
  const needsFragment = body.some(l => /<Fragment>/.test(l));
  const lines = [];
  lines.push(`// ${HEADER_MARK} from designs/${design.name}.json`);
  lines.push('// in packages/tgui-designer. Its saves ask before overwriting '
    + 'edits.');
  const imports = [];
  if (needsFragment) {
    imports.push('import { Fragment } from \'inferno\';');
  }
  const helperImports = [...ctx.helpers].sort();
  if (helperImports.length) {
    imports.push(`import { ${helperImports.join(', ')} } from 'common/math';`);
  }
  imports.push('import { useBackend } from \'../backend\';');
  const comps = [...ctx.components].sort();
  if (comps.length) {
    imports.push(`import { ${comps.join(', ')} } from '../components';`);
  }
  const code = [];
  code.push('');
  code.push(`export const ${design.name} = props => {`);
  const backend = [ctx.usesAct && 'act', fields.length && 'data']
    .filter(Boolean);
  if (backend.length) {
    code.push(`${IND}const { ${backend.join(', ')} } = useBackend(props);`);
  }
  if (fields.length) {
    code.push(IND + 'const {');
    fields.forEach(f => code.push(IND + IND + f + ','));
    code.push(IND + '} = data;');
  }
  code.push(...body);
  code.push('};');
  // Rules generated code can't always keep
  const disables = [];
  if (code.some(l => l.length > MAX)) {
    disables.push('max-len');
  }
  if (ctx.maxDepth > 6) {
    disables.push('react/jsx-max-depth');
  }
  if (disables.length) {
    lines.push(`/* eslint-disable ${disables.join(', ')} */`);
  }
  if (!backend.length) {
    // useBackend isn't needed
    const at = imports.findIndex(l => l.includes('useBackend'));
    imports.splice(at, 1);
  }
  return [...lines, ...imports, ...code].join('\n') + '\n';
};

/** The route entry the designer keeps in routes.js. */
export const routeLines = design => {
  const lines = [
    `  ${design.route}: {`,
    `    component: () => ${design.name},`,
    `    scrollable: ${design.scrollable ? 'true' : 'false'},`,
  ];
  if (design.theme && design.theme !== 'nanotrasen') {
    lines.push(`    theme: '${design.theme}',`);
  }
  lines.push('  },');
  return lines;
};
