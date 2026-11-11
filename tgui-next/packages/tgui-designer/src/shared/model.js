/**
 * The design: a window's settings, its node tree, its data fields and
 * actions. Everything here works on plain JSON, so a design is saved and
 * undone by copying it.
 */

import { COMPONENTS, getDef, ROOT_TYPE } from './registry';

export const DESIGN_VERSION = 1;

export const clone = obj => JSON.parse(JSON.stringify(obj));

export const toSnake = name => name
  .replace(/([a-z0-9])([A-Z])/g, '$1_$2')
  .replace(/[^A-Za-z0-9]+/g, '_')
  .replace(/^_+|_+$/g, '')
  .toLowerCase();

export const dmFileFor = route => (
  'hippiestation/code/modules/tgui_designs/' + route + '_tgui.dm'
);

export const createDesign = (name = 'NewWindow') => {
  const route = toSnake(name);
  const design = {
    version: DESIGN_VERSION,
    name,
    route,
    title: name.replace(/([a-z])([A-Z])/g, '$1 $2'),
    width: 400,
    height: 300,
    theme: 'nanotrasen',
    scrollable: true,
    nextId: 1,
    root: { id: 'root', type: ROOT_TYPE, props: {}, children: [] },
    fields: [],
    actions: [],
    dm: {
      type: '/obj/machinery/' + route,
      file: dmFileFor(route),
      state: 'default_state',
      declareType: true,
      titleFromName: false,
    },
    meta: {},
  };
  const section = instantiate(design, COMPONENTS['Section'].create());
  section.props.title = { v: 'Status' };
  design.root.children.push(section);
  return design;
};

/** Gives a template subtree (from registry create()) real ids. */
export const instantiate = (design, template) => {
  const node = {
    id: 'n' + design.nextId++,
    type: template.type,
    props: clone(template.props || {}),
    children: [],
    slots: {},
  };
  for (const child of template.children || []) {
    node.children.push(instantiate(design, child));
  }
  for (const slot of Object.keys(template.slots || {})) {
    node.slots[slot] = template.slots[slot]
      .map(child => instantiate(design, child));
  }
  if (template.showIf) {
    node.showIf = template.showIf;
  }
  if (template.repeat) {
    node.repeat = clone(template.repeat);
  }
  return node;
};

/** A copy of a node with fresh ids all the way down. */
export const reId = (design, node) => {
  const copy = clone(node);
  const walkCopy = n => {
    n.id = 'n' + design.nextId++;
    for (const child of n.children || []) {
      walkCopy(child);
    }
    for (const slot of Object.keys(n.slots || {})) {
      for (const child of n.slots[slot]) {
        walkCopy(child);
      }
    }
  };
  walkCopy(copy);
  return copy;
};

export const slotList = (node, slot) => {
  if (slot === 'children') {
    if (!node.children) {
      node.children = [];
    }
    return node.children;
  }
  if (!node.slots) {
    node.slots = {};
  }
  if (!node.slots[slot]) {
    node.slots[slot] = [];
  }
  return node.slots[slot];
};

/** Slot names of a node that hold something or could. */
export const slotsOf = node => {
  if (node.type === ROOT_TYPE) {
    return ['children'];
  }
  const def = getDef(node.type);
  return (def && def.slots) || [];
};

/** Calls fn(node, parent, slot, index, depth) for every node. */
export const walk = (node, fn, parent = null, slot = null, index = 0,
  depth = 0) => {
  if (fn(node, parent, slot, index, depth) === false) {
    return;
  }
  for (const s of slotsOf(node)) {
    const list = s === 'children'
      ? (node.children || [])
      : ((node.slots && node.slots[s]) || []);
    list.forEach((child, i) => walk(child, fn, node, s, i, depth + 1));
  }
};

/** { node, parent, slot, index } for an id, or null. */
export const findNode = (design, id) => {
  let found = null;
  walk(design.root, (node, parent, slot, index) => {
    if (found) {
      return false;
    }
    if (node.id === id) {
      found = { node, parent, slot, index };
      return false;
    }
  });
  return found;
};

/** Ids from the root down to the node (both included). */
export const pathTo = (design, id) => {
  const path = [];
  const visit = node => {
    path.push(node.id);
    if (node.id === id) {
      return true;
    }
    for (const s of slotsOf(node)) {
      const list = s === 'children'
        ? (node.children || [])
        : ((node.slots && node.slots[s]) || []);
      for (const child of list) {
        if (visit(child)) {
          return true;
        }
      }
    }
    path.pop();
    return false;
  };
  visit(design.root);
  return path;
};

export const isInside = (design, id, ancestorId) => (
  pathTo(design, id).includes(ancestorId)
);

const typeOk = (childType, parentType, slot) => {
  const childDef = getDef(childType);
  if (slot !== 'children') {
    // Button slots take anything that doesn't need a special parent
    return !childDef.parent;
  }
  const parentDef = parentType === ROOT_TYPE ? null : getDef(parentType);
  if (parentDef && parentDef.accepts) {
    return parentDef.accepts.includes(childType);
  }
  if (childDef.parent) {
    return childDef.parent.includes(parentType);
  }
  return true;
};

/**
 * How a node of `childType` gets into `parentType`'s slot: [] when it goes
 * in as is, a list of wrapper types (outermost first) when it needs
 * wrapping, or null when it can't go there at all.
 */
export const wrapPlan = (childType, parentType, slot) => {
  if (parentType !== ROOT_TYPE) {
    const parentDef = getDef(parentType);
    if (!parentDef || !parentDef.slots || !parentDef.slots.includes(slot)) {
      return null;
    }
  }
  else if (slot !== 'children') {
    return null;
  }
  if (typeOk(childType, parentType, slot)) {
    return [];
  }
  // Wrap the child down into what the parent accepts (Table: Row > Cell)
  const parentDef = parentType === ROOT_TYPE ? null : getDef(parentType);
  if (slot === 'children' && parentDef && parentDef.wrapIn) {
    const plan = [];
    let outer = parentType;
    let inner = parentDef.wrapIn;
    for (let i = 0; i < 3 && inner; i++) {
      plan.push(inner);
      if (typeOk(childType, inner, 'children')) {
        return plan;
      }
      outer = inner;
      inner = getDef(outer).wrapIn;
    }
  }
  // Wrap the child up into its own required parent (Cell outside a Row)
  const childDef = getDef(childType);
  if (childDef.wrapOut) {
    const plan = [];
    let type = childType;
    for (let i = 0; i < 3; i++) {
      const out = getDef(type).wrapOut;
      if (!out) {
        break;
      }
      plan.unshift(out);
      if (typeOk(out, parentType, slot)) {
        return plan;
      }
      type = out;
    }
  }
  return null;
};

const wrapWith = (design, node, plan) => {
  let inner = node;
  for (let i = plan.length - 1; i >= 0; i--) {
    const def = getDef(plan[i]);
    const props = {};
    if (plan[i] === 'LabeledList.Item') {
      props.label = { v: 'Label' };
    }
    if (plan[i] === 'Tabs.Tab') {
      props.label = { v: 'Tab' };
    }
    if (plan[i] === 'Flex.Item') {
      props.grow = { v: 1 };
    }
    const wrapper = {
      id: 'n' + design.nextId++,
      type: plan[i],
      props,
      children: [inner],
      slots: {},
    };
    if (!def.slots) {
      throw new Error('cannot wrap in ' + plan[i]);
    }
    inner = wrapper;
  }
  return inner;
};

/**
 * Puts a node into parent's slot at index, wrapping it if it needs to.
 * Mutates the design. Returns false when it can't go there.
 */
export const insertNode = (design, node, parentId, slot, index) => {
  const target = parentId === 'root'
    ? { node: design.root }
    : findNode(design, parentId);
  if (!target) {
    return false;
  }
  const plan = wrapPlan(node.type, target.node.type, slot);
  if (!plan) {
    return false;
  }
  const placed = plan.length ? wrapWith(design, node, plan) : node;
  const list = slotList(target.node, slot);
  const at = Math.max(0, Math.min(index, list.length));
  list.splice(at, 0, placed);
  return true;
};

export const removeNode = (design, id) => {
  const found = findNode(design, id);
  if (!found || !found.parent) {
    return null;
  }
  slotList(found.parent, found.slot).splice(found.index, 1);
  return found.node;
};

/** Moves a node; refuses to move it into itself. */
export const moveNode = (design, id, parentId, slot, index) => {
  if (id === parentId || isInside(design, parentId, id)) {
    return false;
  }
  const found = findNode(design, id);
  if (!found || !found.parent) {
    return false;
  }
  const target = parentId === 'root'
    ? { node: design.root }
    : findNode(design, parentId);
  if (!target || !wrapPlan(found.node.type, target.node.type, slot)) {
    return false;
  }
  let at = index;
  if (found.parent.id === parentId && found.slot === slot
    && found.index < index) {
    at--;
  }
  removeNode(design, id);
  return insertNode(design, found.node, parentId, slot, at);
};

/** Can a node of this type (or the node `movingId`) drop there? */
export const canDrop = (design, type, parentId, slot, movingId) => {
  if (movingId && (movingId === parentId
    || isInside(design, parentId, movingId))) {
    return false;
  }
  const target = parentId === 'root'
    ? { node: design.root }
    : findNode(design, parentId);
  if (!target) {
    return false;
  }
  return !!wrapPlan(type, target.node.type, slot);
};

/** Wraps an existing node in a new container of `type`. */
export const wrapNode = (design, id, type) => {
  const found = findNode(design, id);
  if (!found || !found.parent) {
    return null;
  }
  const def = getDef(type);
  if (!def || !def.slots) {
    return null;
  }
  const template = def.create();
  const wrapper = instantiate(design, { ...template, children: [] });
  const list = slotList(found.parent, found.slot);
  if (!wrapPlan(type, found.parent.type, found.slot)) {
    return null;
  }
  list.splice(found.index, 1);
  insertNode(design, wrapper, found.parent.id === 'root'
    ? 'root' : found.parent.id, found.slot, found.index);
  if (!insertNode(design, found.node, wrapper.id, 'children', 0)) {
    // Put it back where it was
    removeNode(design, wrapper.id);
    list.splice(found.index, 0, found.node);
    return null;
  }
  return wrapper.id;
};

/** Every node id in the subtree, the node included. */
export const subtreeIds = node => {
  const ids = [];
  walk(node, n => {
    ids.push(n.id);
  });
  return ids;
};

/** Repeat variables in scope at a node: [{ as, list }] outermost first. */
export const repeatScopes = (design, id) => {
  const scopes = [];
  for (const nodeId of pathTo(design, id)) {
    const found = nodeId === 'root' ? null : findNode(design, nodeId);
    if (found && found.node.repeat && found.node.repeat.list) {
      scopes.push(found.node.repeat);
    }
  }
  return scopes;
};

export const FIELD_TYPES = ['number', 'text', 'bool', 'list', 'object'];

/** Guesses a field's type from a mock value. */
export const typeOfValue = value => {
  if (Array.isArray(value)) {
    return 'list';
  }
  if (value === null) {
    return 'text';
  }
  if (typeof value === 'object') {
    return 'object';
  }
  if (typeof value === 'boolean') {
    return 'bool';
  }
  if (typeof value === 'number') {
    return 'number';
  }
  return 'text';
};

export const defaultMock = type => {
  switch (type) {
    case 'number':
      return 0;
    case 'bool':
      return false;
    case 'list':
      return [];
    case 'object':
      return {};
    default:
      return '';
  }
};

/** The mock data object the preview starts from. */
export const mockData = design => {
  const data = {};
  for (const field of design.fields) {
    data[field.name] = clone(field.mock === undefined
      ? defaultMock(field.type) : field.mock);
  }
  return data;
};

const JS_RESERVED = new Set(('break case catch class const continue debugger '
  + 'default delete do else export extends finally for function if import '
  + 'in instanceof new return super switch this throw try typeof var void '
  + 'while with yield let static enum await implements package protected '
  + 'interface private public null true false undefined NaN Infinity '
  + 'act data props Fragment').split(' '));

export const isIdentifier = name => (
  /^[A-Za-z_$][\w$]*$/.test(name) && !JS_RESERVED.has(name)
);

/** Problems that stop a save, as text. */
export const validateDesign = design => {
  const problems = [];
  if (!/^[A-Z][A-Za-z0-9]*$/.test(design.name || '')) {
    problems.push('Name must be PascalCase letters and digits, '
      + 'like GravityGenerator.');
  }
  if (!/^[a-z][a-z0-9_]*$/.test(design.route || '')) {
    problems.push('Interface key must be lowercase letters, digits '
      + 'and _, like gravity_generator.');
  }
  const names = new Set();
  for (const field of design.fields) {
    if (!isIdentifier(field.name)) {
      problems.push(`Field "${field.name}" isn't a usable name.`);
    }
    if (names.has(field.name)) {
      problems.push(`Field "${field.name}" is listed twice.`);
    }
    names.add(field.name);
  }
  const actionNames = new Set();
  for (const action of design.actions) {
    if (!/^[A-Za-z0-9_-]+$/.test(action.name || '')) {
      problems.push(`Action "${action.name}" needs a plain name.`);
    }
    if (actionNames.has(action.name)) {
      problems.push(`Action "${action.name}" is listed twice.`);
    }
    actionNames.add(action.name);
  }
  if (design.dm.type && !/^(\/[A-Za-z_][\w]*)+$/.test(design.dm.type)) {
    problems.push('DM type must be a path like /obj/machinery/thing.');
  }
  if (!/^[\w\-./]+\.dm$/.test(design.dm.file || '')
    || design.dm.file.includes('..')) {
    problems.push('DM file must be a repo path ending in .dm.');
  }
  return problems;
};

/** Brings an older or hand-edited design up to the current shape. */
export const normalizeDesign = raw => {
  const design = { ...createDesign(raw.name || 'NewWindow'), ...raw };
  design.dm = { ...createDesign(design.name).dm, ...(raw.dm || {}) };
  design.fields = raw.fields || [];
  design.actions = raw.actions || [];
  design.meta = raw.meta || {};
  let maxId = 0;
  walk(design.root, node => {
    node.props = node.props || {};
    node.children = node.children || [];
    node.slots = node.slots || {};
    const n = parseInt(String(node.id).replace(/^n/, ''), 10);
    if (n > maxId) {
      maxId = n;
    }
  });
  design.nextId = Math.max(design.nextId || 1, maxId + 1);
  return design;
};

export const isContainer = type => {
  if (type === ROOT_TYPE) {
    return true;
  }
  const def = getDef(type);
  return !!def && !!def.slots && def.slots.includes('children');
};
