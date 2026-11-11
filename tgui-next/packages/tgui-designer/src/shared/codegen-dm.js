/**
 * Writes the DM side of a design: ui_interact() opening the window,
 * ui_data()/ui_static_data() from the fields and ui_act() from the
 * actions' effects. With "declare type" it also declares the type and its
 * vars, so a new window works from a fresh object.
 */

import { HEADER_MARK } from './codegen-js';
import { isSet } from './effects';

const T = '\t';

/** A DM string literal. [ starts an embedded expression in DM. */
export const dmString = s => '"' + String(s === undefined || s === null
  ? '' : s)
  .replace(/\\/g, '\\\\')
  .replace(/"/g, '\\"')
  .replace(/\[/g, '\\[')
  .replace(/\n/g, '\\n') + '"';

const isLvalue = expr => /^[A-Za-z_]\w*(\.[A-Za-z_]\w*)*$/.test(expr || '');

const dmOf = field => (field.dm && field.dm.trim()) || field.name;

const dmLiteral = (value, type) => {
  switch (type) {
    case 'number': {
      const n = Number(value);
      return Number.isFinite(n) ? String(n) : '0';
    }
    case 'bool':
      return value === true || value === 'true' || value === 1
        || value === '1' ? 'TRUE' : 'FALSE';
    case 'list': {
      if (Array.isArray(value) && value.length
        && value.every(v => typeof v !== 'object' || v === null)) {
        return 'list(' + value.map(v => (typeof v === 'number'
          ? String(v) : dmString(v))).join(', ') + ')';
      }
      return 'list()';
    }
    case 'object':
      return 'list()';
    default:
      return dmString(value);
  }
};

/** A default for one key of a list entry, guessed from the mock. */
const entryValue = (key, sample) => {
  if (key === 'name') {
    return '"[entry]"';
  }
  if (key === 'ref') {
    return 'REF(entry)';
  }
  if (typeof sample === 'number') {
    return '0';
  }
  if (typeof sample === 'boolean') {
    return 'FALSE';
  }
  if (Array.isArray(sample) || (sample && typeof sample === 'object')) {
    return 'list()';
  }
  return '""';
};

const dataLines = (field, indent) => {
  const expr = dmOf(field);
  const mock = field.mock;
  const objects = field.type === 'list' && Array.isArray(mock)
    && mock.length && mock[0] && typeof mock[0] === 'object'
    && !Array.isArray(mock[0]);
  if (!objects) {
    return [`${indent}data[${dmString(field.name)}] = ${expr}`];
  }
  // A list of entries: loop over the source and send each one's values
  const keys = Object.keys(mock[0]);
  const local = field.name + '_data';
  const lines = [
    `${indent}var/list/${local} = list()`,
    `${indent}for(var/entry in ${expr}) // TODO: what each entry sends`,
    `${indent}${T}${local} += list(list(`,
  ];
  keys.forEach((key, i) => {
    const comma = i < keys.length - 1 ? ',' : '';
    lines.push(`${indent}${T}${T}${dmString(key)} = `
      + entryValue(key, mock[0][key]) + comma);
  });
  lines.push(`${indent}${T}))`);
  lines.push(`${indent}data[${dmString(field.name)}] = ${local}`);
  return lines;
};

const effectLines = (effect, design, indent) => {
  if (effect.op === 'dm') {
    // Typed code may be indented with spaces; DM blocks want tabs
    const tabs = ws => T.repeat((ws.match(/\t/g) || []).length
      + Math.floor(ws.replace(/\t/g, '').length / 4));
    return String(effect.code || '').split('\n')
      .filter(l => l.trim())
      .map(l => indent + l.replace(/^[ \t]+/, tabs).replace(/\s+$/, ''));
  }
  const field = design.fields.find(f => f.name === effect.field);
  if (!field) {
    return [`${indent}// TODO: effect on unknown field "${effect.field}"`];
  }
  const lv = dmOf(field);
  if (!isLvalue(lv)) {
    return [`${indent}// TODO: change ${field.name} (${lv})`];
  }
  const clampOf = expr => {
    const lo = isSet(effect.min) ? Number(effect.min) : null;
    const hi = isSet(effect.max) ? Number(effect.max) : null;
    if (lo !== null && hi !== null) {
      return `clamp(${expr}, ${lo}, ${hi})`;
    }
    if (lo !== null) {
      return `max(${expr}, ${lo})`;
    }
    if (hi !== null) {
      return `min(${expr}, ${hi})`;
    }
    return expr;
  };
  switch (effect.op) {
    case 'toggle':
      return [`${indent}${lv} = !${lv}`];
    case 'set':
      return [`${indent}${lv} = ${dmLiteral(effect.value, field.type)}`];
    case 'add': {
      const amount = Number(effect.amount) || 0;
      const sum = `${lv} ${amount < 0 ? '-' : '+'} ${Math.abs(amount)}`;
      const clamped = clampOf(sum);
      if (clamped === sum) {
        return [`${indent}${lv} ${amount < 0 ? '-=' : '+='} `
          + Math.abs(amount)];
      }
      return [`${indent}${lv} = ${clamped}`];
    }
    case 'param': {
      const param = `params[${dmString(effect.param || 'value')}]`;
      const local = 'new_' + field.name;
      switch (field.type) {
        case 'number':
          return [
            `${indent}var/${local} = text2num(${param})`,
            `${indent}if(!isnull(${local}))`,
            `${indent}${T}${lv} = ${clampOf(local)}`,
          ];
        case 'bool':
          return [`${indent}${lv} = (${param} == "true" || `
            + `${param} == "1")`];
        case 'text':
          return [
            `${indent}var/${local} = trim(html_encode(${param}), `
              + 'MAX_NAME_LEN)',
            `${indent}if(length(${local}))`,
            `${indent}${T}${lv} = ${local}`,
          ];
        default:
          return [`${indent}// TODO: ${lv} from ${param}`];
      }
    }
    default:
      return [];
  }
};

/** The actions each control sends, with the params it sends. */
const actionsUsed = design => {
  const used = new Map();
  const visit = node => {
    for (const name of Object.keys(node.props || {})) {
      const p = node.props[name];
      if (p && p.action) {
        const params = used.get(p.action) || new Set();
        Object.keys(p.params || {}).forEach(k => params.add(k));
        used.set(p.action, params);
      }
    }
    for (const child of node.children || []) {
      visit(child);
    }
    for (const slot of Object.keys(node.slots || {})) {
      node.slots[slot].forEach(visit);
    }
  };
  visit(design.root);
  return used;
};

/** The DM file's text. */
export const generateDm = design => {
  const dm = design.dm || {};
  const type = dm.type || '/obj/machinery/' + design.route;
  const out = [];
  out.push(`// ${HEADER_MARK} from designs/${design.name}.json in `
    + 'tgui-next/packages/tgui-designer.');
  out.push('// Saving there rewrites this file; it asks first when this '
    + 'file was edited by hand.');
  out.push('');

  if (dm.declareType) {
    out.push(type);
    const short = design.title || design.name;
    out.push(`${T}name = ${dmString(short.toLowerCase())}`);
    out.push(`${T}desc = ${dmString('A ' + short.toLowerCase() + '.')}`);
    if (type.startsWith('/obj/item')) {
      out.push(`${T}icon = 'icons/obj/device.dmi' // TODO: its own icon`);
      out.push(`${T}icon_state = "multitool"`);
    }
    else if (type.startsWith('/obj')) {
      out.push(`${T}icon = 'icons/obj/computer.dmi' // TODO: its own icon`);
      out.push(`${T}icon_state = "computer"`);
    }
    for (const field of design.fields) {
      const lv = dmOf(field);
      if (!/^[A-Za-z_]\w*$/.test(lv)) {
        continue;
      }
      const prefix = field.type === 'list' || field.type === 'object'
        ? 'var/list/' : 'var/';
      out.push(`${T}${prefix}${lv} = ${dmLiteral(field.mock, field.type)}`);
    }
    out.push('');
  }

  const state = dm.state && dm.state !== 'default_state'
    ? dm.state : 'default_state';
  out.push(`${type}/ui_interact(mob/user, ui_key = "main", `
    + 'datum/tgui/ui = null, force_open = FALSE, '
    + 'datum/tgui/master_ui = null, '
    + `datum/ui_state/state = GLOB.${state})`);
  out.push(`${T}ui = SStgui.try_update_ui(user, src, ui_key, ui, `
    + 'force_open)');
  out.push(`${T}if(!ui)`);
  const title = dm.titleFromName ? 'name' : dmString(design.title || '');
  out.push(`${T}${T}ui = new(user, src, ui_key, ${dmString(design.route)}, `
    + `${title}, ${Number(design.width) || 400}, `
    + `${Number(design.height) || 300}, master_ui, state)`);
  out.push(`${T}${T}ui.open()`);
  out.push('');

  const statics = design.fields.filter(f => f.isStatic);
  const dynamics = design.fields.filter(f => !f.isStatic);
  if (statics.length) {
    out.push(`${type}/ui_static_data(mob/user)`);
    out.push(`${T}var/list/data = list()`);
    statics.forEach(f => out.push(...dataLines(f, T)));
    out.push(`${T}return data`);
    out.push('');
  }
  out.push(`${type}/ui_data(mob/user)`);
  out.push(`${T}var/list/data = list()`);
  dynamics.forEach(f => out.push(...dataLines(f, T)));
  out.push(`${T}return data`);

  // Actions: the listed ones, plus any a control sends that isn't listed
  const used = actionsUsed(design);
  const names = [...design.actions.map(a => a.name)];
  for (const name of used.keys()) {
    if (!names.includes(name)) {
      names.push(name);
    }
  }
  if (names.length) {
    out.push('');
    out.push(`${type}/ui_act(action, params)`);
    out.push(`${T}if(..())`);
    out.push(`${T}${T}return`);
    out.push(`${T}switch(action)`);
    for (const name of names) {
      const action = design.actions.find(a => a.name === name);
      out.push(`${T}${T}if(${dmString(name)})`);
      const body = [];
      for (const effect of (action && action.effects) || []) {
        body.push(...effectLines(effect, design, T + T + T));
      }
      if (!body.length) {
        const params = [...(used.get(name) || [])];
        body.push(`${T}${T}${T}// TODO: what "${name}" does`
          + (params.length
            ? ` (sends ${params.map(p => `params["${p}"]`).join(', ')})`
            : ''));
      }
      out.push(...body);
      out.push(`${T}${T}${T}. = TRUE`);
    }
  }
  return out.join('\n') + '\n';
};

/** The .dme include line for the DM file. */
export const dmeInclude = file => (
  '#include "' + file.replace(/\//g, '\\') + '"'
);
