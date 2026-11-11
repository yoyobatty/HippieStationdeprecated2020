/**
 * What a button does in test mode. An action's effects change the mock
 * data the same way the generated ui_act() changes the object's vars.
 *
 * Effects:
 *   { op: 'toggle', field }
 *   { op: 'set', field, value }            a fixed value
 *   { op: 'param', field, param, min, max } the value the button sent
 *   { op: 'add', field, amount, min, max }
 *   { op: 'dm', code }                     DM code only, nothing here
 */

import { clone } from './model';

export const EFFECT_OPS = [
  { op: 'toggle', label: 'Toggle' },
  { op: 'set', label: 'Set to' },
  { op: 'param', label: 'Set from param' },
  { op: 'add', label: 'Add' },
  { op: 'dm', label: 'DM code' },
];

const toNumber = value => {
  const n = Number(value);
  return Number.isFinite(n) ? n : null;
};

export const isSet = value => value !== '' && value !== undefined
  && value !== null && toNumber(value) !== null;

const limit = (n, min, max) => {
  let out = n;
  if (isSet(min) && out < toNumber(min)) {
    out = toNumber(min);
  }
  if (isSet(max) && out > toNumber(max)) {
    out = toNumber(max);
  }
  return out;
};

/** A typed-in value read as the field's type. */
export const coerce = (value, type) => {
  switch (type) {
    case 'number': {
      const n = toNumber(value);
      return n === null ? 0 : n;
    }
    case 'bool':
      return value === true || value === 'true' || value === 1
        || value === '1';
    case 'list':
    case 'object':
      if (typeof value === 'string') {
        try {
          return JSON.parse(value);
        }
        catch (err) {
          return type === 'list' ? [] : {};
        }
      }
      return value;
    default:
      return value === undefined || value === null ? '' : String(value);
  }
};

/**
 * Runs an action against the data. Returns { data, notes } where notes
 * say what happened, for the test log.
 */
export const runAction = (design, data, name, params) => {
  const next = clone(data);
  const notes = [];
  const action = design.actions.find(a => a.name === name);
  if (!action) {
    notes.push(`no action "${name}" in the Actions list`);
    return { data: next, notes };
  }
  for (const effect of action.effects || []) {
    const field = design.fields.find(f => f.name === effect.field);
    if (effect.op !== 'dm' && !field) {
      notes.push(`effect on unknown field "${effect.field}"`);
      continue;
    }
    switch (effect.op) {
      case 'toggle':
        next[field.name] = !next[field.name];
        notes.push(`${field.name} = ${JSON.stringify(next[field.name])}`);
        break;
      case 'set':
        next[field.name] = coerce(effect.value, field.type);
        notes.push(`${field.name} = ${JSON.stringify(next[field.name])}`);
        break;
      case 'param': {
        const raw = params ? params[effect.param] : undefined;
        if (raw === undefined) {
          notes.push(`param "${effect.param}" wasn't sent`);
          break;
        }
        let value = coerce(raw, field.type);
        if (field.type === 'number') {
          value = limit(value, effect.min, effect.max);
        }
        next[field.name] = value;
        notes.push(`${field.name} = ${JSON.stringify(value)}`);
        break;
      }
      case 'add': {
        const amount = toNumber(effect.amount) || 0;
        const value = limit((toNumber(next[field.name]) || 0) + amount,
          effect.min, effect.max);
        next[field.name] = value;
        notes.push(`${field.name} = ${value}`);
        break;
      }
      case 'dm':
        notes.push('DM code (runs in game only)');
        break;
      default:
        break;
    }
  }
  return { data: next, notes };
};
