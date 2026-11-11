/**
 * The designer: holds the design and everything about the session (the
 * selection, undo, test-mode data, drags) and lays out the panels.
 */

import { Component, createRef } from 'inferno';
import { generateDm } from '../shared/codegen-dm';
import { expressionsOf, generateJs, routeLines } from '../shared/codegen-js';
import { runAction, coerce } from '../shared/effects';
import { evaluate, freeNames, makeScope, parseTemplate, templateNames } from '../shared/expr';
import { clone, createDesign, defaultMock, findNode, insertNode, instantiate, isContainer, isIdentifier, mockData, moveNode, normalizeDesign, pathTo, reId, removeNode, repeatScopes, slotList, typeOfValue, validateDesign, wrapNode, wrapPlan } from '../shared/model';
import { COMPONENTS, labelOf } from '../shared/registry';
import { api } from './api';
import { Canvas } from './Canvas';
import { ConflictDialog, NewDialog, OpenDialog } from './Dialogs';
import { Datalists, Inspector } from './Inspector';
import { Outline } from './Outline';
import { Palette } from './Palette';
import { ActionsPanel, CodePanel, DataPanel, LogPanel } from './panels';
import { WindowPanel } from './WindowPanel';

const DRAFT_KEY = 'tgui-designer:draft';
const LAST_KEY = 'tgui-designer:last';
const ZOOMS = [0.5, 0.75, 1, 1.25, 1.5, 2];

const now = () => {
  const d = new Date();
  const pad = n => String(n).padStart(2, '0');
  return pad(d.getHours()) + ':' + pad(d.getMinutes()) + ':'
    + pad(d.getSeconds());
};

const storage = {
  get: key => {
    try {
      return JSON.parse(window.localStorage.getItem(key));
    }
    catch (err) {
      return null;
    }
  },
  set: (key, value) => {
    try {
      window.localStorage.setItem(key, JSON.stringify(value));
    }
    catch (err) {
      // Private mode or full; drafts are a convenience only
    }
  },
};

/** Renames a data name everywhere an expression reads it. */
const renameInExpr = (src, from, to) => String(src).replace(
  new RegExp('(^|[^.\\w$])' + from.replace(/\$/g, '\\$') + '(?![\\w$])',
    'g'),
  '$1' + to);

const renameInTemplate = (src, from, to) => parseTemplate(src)
  .map(p => (p.expr !== undefined
    ? '{' + renameInExpr(p.expr, from, to) + '}'
    : p.text))
  .join('');

const BOOL_NAME = /^(is|has|can|should)[A-Z_]|^(on|open|locked|active|enabled|powered|operational|broken|emagged|panel_open)$/;

const guessType = (name, fromTemplate) => {
  if (BOOL_NAME.test(name)) {
    return 'bool';
  }
  if (/s$/.test(name) && !/(status|progress|ss)$/.test(name)) {
    return 'list';
  }
  return fromTemplate ? 'text' : 'number';
};

export class App extends Component {
  constructor(props) {
    super(props);
    const design = createDesign('NewWindow');
    this.cur = design;
    this.state = {
      design,
      selectedId: null,
      hoverId: null,
      mode: 'design',
      liveData: null,
      showHidden: false,
      zoom: 1,
      rightTab: 'item',
      bottomTab: 'data',
      bottomOpen: true,
      log: [],
      errors: {},
      dirty: false,
      job: null,
      dialog: null,
      drag: null,
      dropTarget: null,
      activeTabs: {},
      focus: null,
      focusAction: null,
      icons: [],
      busy: '',
    };
    this.past = [];
    this.future = [];
    this.lastKey = null;
    this.lastAt = 0;
    this.canvasRef = createRef();
    this.outlineRef = createRef();
    this.codeCache = { key: null };
    this.usageCache = { key: null };
    this.dragInfo = null;
    this.clipboard = null;
    this.addFieldNamed = (name, fromTemplate) => this.addField(name,
      guessType(name, fromTemplate));
    this.onDragMove = e => this.dragMove(e);
    this.onDragUp = e => this.dragUp(e);
    this.onKeyDown = e => {
      const typing = /^(INPUT|TEXTAREA|SELECT)$/.test(e.target.tagName);
      const handled = this.handleKey({
        key: e.key,
        ctrl: e.ctrlKey || e.metaKey,
        shift: e.shiftKey,
        alt: e.altKey,
        design: this.state.mode === 'design',
        typing,
      });
      if (handled) {
        e.preventDefault();
      }
    };
    this.onBeforeUnload = e => {
      if (this.state.dirty) {
        e.preventDefault();
        e.returnValue = '';
      }
    };
  }

  async componentDidMount() {
    window.addEventListener('keydown', this.onKeyDown);
    window.addEventListener('beforeunload', this.onBeforeUnload);
    window.tguiDesigner = this;
    const draft = storage.get(DRAFT_KEY);
    if (draft && draft.design) {
      this.loadDesign(normalizeDesign(draft.design), !!draft.dirty);
      if (draft.dirty) {
        this.log('info', `Restored unsaved changes to ${draft.design.name}.`);
      }
    }
    else {
      const last = storage.get(LAST_KEY);
      if (last) {
        await this.open(last, true);
      }
    }
    this.loadIcons();
  }

  async loadIcons() {
    const icons = await api.icons();
    if (!icons.error) {
      this.setState({ icons: icons.icons });
    }
  }

  componentWillUnmount() {
    window.removeEventListener('keydown', this.onKeyDown);
    window.removeEventListener('beforeunload', this.onBeforeUnload);
  }

  // -------------------------------------------------------------------
  // The design and undo

  /**
   * Changes the design: fn gets a copy to change (return false for "no
   * change"). Changes with the same key in a row make one undo step.
   */
  change(fn, key) {
    const before = this.cur;
    const next = clone(before);
    if (fn(next) === false) {
      return false;
    }
    const at = Date.now();
    if (!(key && key === this.lastKey && at - this.lastAt < 1500)) {
      this.past.push(before);
      if (this.past.length > 300) {
        this.past.shift();
      }
    }
    this.lastKey = key;
    this.lastAt = at;
    this.future = [];
    this.cur = next;
    this.setState({ design: next, dirty: true });
    this.saveDraft(next, true);
    return true;
  }

  saveDraft(design, dirty) {
    clearTimeout(this.draftTimer);
    this.draftTimer = setTimeout(() => {
      storage.set(DRAFT_KEY, { design, dirty });
    }, 300);
  }

  undo() {
    if (!this.past.length) {
      return;
    }
    this.future.push(this.cur);
    this.cur = this.past.pop();
    this.lastKey = null;
    this.setState({ design: this.cur, dirty: true });
    this.saveDraft(this.cur, true);
  }

  redo() {
    if (!this.future.length) {
      return;
    }
    this.past.push(this.cur);
    this.cur = this.future.pop();
    this.lastKey = null;
    this.setState({ design: this.cur, dirty: true });
    this.saveDraft(this.cur, true);
  }

  loadDesign(design, dirty = false) {
    this.cur = design;
    this.past = [];
    this.future = [];
    this.lastKey = null;
    this.setState({
      design,
      dirty,
      selectedId: null,
      liveData: null,
      mode: 'design',
      activeTabs: {},
      errors: {},
    });
    storage.set(LAST_KEY, design.name);
    this.saveDraft(design, dirty);
  }

  // -------------------------------------------------------------------
  // Nodes

  select(id) {
    const opened = {};
    if (id) {
      // Open the tabs it sits in
      for (const pid of pathTo(this.cur, id)) {
        const found = pid !== 'root' && findNode(this.cur, pid);
        if (found && found.node.type === 'Tabs.Tab' && found.parent) {
          opened[found.parent.id] = found.node.repeat
            ? found.node.id + ':0' : found.node.id;
        }
      }
    }
    this.setState(state => ({
      selectedId: id,
      activeTabs: { ...state.activeTabs, ...opened },
      rightTab: id ? 'item' : state.rightTab,
    }));
  }

  setProp(id, name, value) {
    this.change(d => {
      const found = findNode(d, id);
      if (!found) {
        return false;
      }
      if (value === undefined) {
        delete found.node.props[name];
      }
      else {
        found.node.props[name] = value;
      }
    }, id + ':' + name);
  }

  changeNode(id, fn, key) {
    this.change(d => {
      const found = findNode(d, id);
      if (!found) {
        return false;
      }
      return fn(found.node);
    }, id + ':' + key);
  }

  deleteNode(id) {
    const found = findNode(this.cur, id);
    if (!found || !found.parent) {
      return;
    }
    const siblings = slotList(found.parent, found.slot);
    const next = siblings[found.index + 1] || siblings[found.index - 1];
    this.change(d => {
      removeNode(d, id);
    });
    this.select(next ? next.id
      : (found.parent.id === 'root' ? null : found.parent.id));
  }

  duplicate(id) {
    let newId = null;
    this.change(d => {
      const found = findNode(d, id);
      if (!found || !found.parent) {
        return false;
      }
      const copy = reId(d, found.node);
      slotList(found.parent, found.slot).splice(found.index + 1, 0, copy);
      newId = copy.id;
    });
    if (newId) {
      this.select(newId);
    }
  }

  wrap(id, type) {
    let wrapper = null;
    this.change(d => {
      wrapper = wrapNode(d, id, type);
      return wrapper ? undefined : false;
    });
    if (wrapper) {
      this.select(wrapper);
    }
    else {
      this.log('warn', `Can't wrap that in ${labelOf(type)}.`);
    }
  }

  /** Puts a node after the selection, or inside it when it holds items. */
  placeNew(d, node) {
    const sel = this.state.selectedId && findNode(d, this.state.selectedId);
    if (sel) {
      // Prefer a spot where it fits as is: inside, then after; only then
      // one where it gets wrapped (a Button into a list gets a row)
      const inside = isContainer(sel.node.type)
        && wrapPlan(node.type, sel.node.type, 'children');
      const after = sel.parent
        && wrapPlan(node.type, sel.parent.type, sel.slot);
      const tries = [
        inside && !inside.length && 'inside',
        after && !after.length && 'after',
        after && 'after',
        inside && 'inside',
      ].filter(Boolean);
      for (const where of tries) {
        if (where === 'inside' && insertNode(d, node, sel.node.id,
          'children', sel.node.children.length)) {
          return true;
        }
        if (where === 'after' && insertNode(d, node, sel.parent.id,
          sel.slot, sel.index + 1)) {
          return true;
        }
      }
    }
    // Nothing selected: into the last section, if the window ends in one
    const last = d.root.children[d.root.children.length - 1];
    if (!sel && last && ['Section', 'Box', 'Collapsible'].includes(last.type)
      && node.type !== 'Section'
      && insertNode(d, node, last.id, 'children', last.children.length)) {
      return true;
    }
    return insertNode(d, node, 'root', 'children', d.root.children.length);
  }

  addComponent(type) {
    let newId = null;
    this.change(d => {
      const node = instantiate(d, COMPONENTS[type].create());
      if (!this.placeNew(d, node)) {
        return false;
      }
      newId = node.id;
    });
    if (newId) {
      this.select(newId);
    }
  }

  copy() {
    const found = this.state.selectedId
      && findNode(this.cur, this.state.selectedId);
    if (found) {
      this.clipboard = clone(found.node);
      this.log('info', `Copied ${labelOf(found.node.type)}.`);
    }
  }

  paste() {
    if (!this.clipboard) {
      return;
    }
    let newId = null;
    this.change(d => {
      const node = reId(d, this.clipboard);
      if (!this.placeNew(d, node)) {
        return false;
      }
      newId = node.id;
    });
    if (newId) {
      this.select(newId);
    }
  }

  /** Moves the selection up or down among its siblings. */
  nudge(dir) {
    const id = this.state.selectedId;
    const found = id && findNode(this.cur, id);
    if (!found || !found.parent) {
      return;
    }
    const to = found.index + (dir < 0 ? -1 : 2);
    const len = slotList(found.parent, found.slot).length;
    if (to < 0 || to > len) {
      return;
    }
    this.change(d => moveNode(d, id, found.parent.id, found.slot, to)
      || false);
  }

  focusText(id) {
    const found = findNode(this.cur, id);
    const def = found && COMPONENTS[found.node.type];
    if (def && def.textProp) {
      this.setState({
        rightTab: 'item',
        focus: { id, n: Date.now() },
      });
    }
  }

  // -------------------------------------------------------------------
  // Dragging

  beginDrag(payload, x, y) {
    this.dragInfo = { payload, x, y, active: false, target: null };
    window.addEventListener('mousemove', this.onDragMove);
    window.addEventListener('mouseup', this.onDragUp);
    this.setState({ drag: { active: false, x, y } });
  }

  dragMove(e) {
    const info = this.dragInfo;
    if (!info) {
      return;
    }
    if (!info.active && Math.abs(e.clientX - info.x)
      + Math.abs(e.clientY - info.y) < 5) {
      return;
    }
    let type;
    let movingId = null;
    let label;
    if (info.payload.kind === 'new') {
      type = info.payload.type;
      label = labelOf(type);
    }
    else {
      const found = findNode(this.cur, info.payload.id);
      if (!found) {
        return;
      }
      type = found.node.type;
      movingId = info.payload.id;
      label = labelOf(type);
    }
    info.active = true;
    let target = null;
    if (this.outlineRef.current) {
      target = this.outlineRef.current.dropAt(e.clientX, e.clientY, type,
        movingId);
    }
    if (!target && this.canvasRef.current) {
      target = this.canvasRef.current.dropAt(e.clientX, e.clientY, type,
        movingId);
      if (target) {
        target.source = 'canvas';
      }
    }
    info.target = target;
    this.setState({
      drag: { active: true, x: e.clientX, y: e.clientY, label,
        ok: !!target },
      dropTarget: target,
    });
  }

  dragUp() {
    window.removeEventListener('mousemove', this.onDragMove);
    window.removeEventListener('mouseup', this.onDragUp);
    const info = this.dragInfo;
    this.dragInfo = null;
    this.setState({ drag: null, dropTarget: null });
    // A palette click without a drag adds it after the selection
    if (info && !info.active && info.payload.kind === 'new') {
      this.addComponent(info.payload.type);
      return;
    }
    if (!info || !info.active || !info.target) {
      return;
    }
    const t = info.target;
    if (info.payload.kind === 'new') {
      let newId = null;
      this.change(d => {
        const node = instantiate(d, COMPONENTS[info.payload.type].create());
        if (!insertNode(d, node, t.parentId, t.slot, t.index)) {
          return false;
        }
        newId = node.id;
      });
      if (newId) {
        this.select(newId);
      }
      return;
    }
    const id = info.payload.id;
    this.change(d => moveNode(d, id, t.parentId, t.slot, t.index) || false);
    this.select(id);
  }

  /** Mouse down on the preview in design mode. */
  nodeMouseDown(id, x, y, button, double) {
    if (button !== 0) {
      return;
    }
    this.select(id);
    if (double && id) {
      this.focusText(id);
      return;
    }
    if (id) {
      this.beginDrag({ kind: 'move', id }, x, y);
    }
  }

  // -------------------------------------------------------------------
  // Keys

  handleKey(k) {
    const key = k.key.toLowerCase();
    if (k.ctrl && key === 's') {
      this.save(false);
      return true;
    }
    if (k.typing) {
      return false;
    }
    if (k.ctrl && !k.shift && key === 'z') {
      this.undo();
      return true;
    }
    if (k.ctrl && (key === 'y' || (k.shift && key === 'z'))) {
      this.redo();
      return true;
    }
    if (!k.design) {
      return false;
    }
    const sel = this.state.selectedId;
    if (sel && (key === 'delete' || key === 'backspace')) {
      this.deleteNode(sel);
      return true;
    }
    if (sel && k.ctrl && key === 'd') {
      this.duplicate(sel);
      return true;
    }
    if (sel && k.ctrl && key === 'c') {
      this.copy();
      return true;
    }
    if (k.ctrl && key === 'v') {
      this.paste();
      return true;
    }
    if (sel && k.alt && (key === 'arrowup' || key === 'arrowdown')) {
      this.nudge(key === 'arrowup' ? -1 : 1);
      return true;
    }
    if (key === 'escape') {
      const found = sel && findNode(this.cur, sel);
      this.select(found && found.parent && found.parent.id !== 'root'
        ? found.parent.id : null);
      return true;
    }
    if (sel && key === 'enter') {
      this.focusText(sel);
      return true;
    }
    return false;
  }

  // -------------------------------------------------------------------
  // Data fields and actions

  addField(name, type = 'text') {
    const taken = new Set(this.cur.fields.map(f => f.name));
    let n = name;
    if (!n) {
      let i = 1;
      do {
        n = 'field' + i++;
      } while (taken.has(n));
    }
    if (taken.has(n) || !isIdentifier(n)) {
      return;
    }
    let mock = defaultMock(type);
    if (type === 'number') {
      mock = 50;
    }
    if (type === 'text') {
      mock = n;
    }
    if (type === 'bool') {
      mock = true;
    }
    this.change(d => {
      d.fields.push({ name: n, type, mock });
    });
    this.setState({ bottomTab: 'data', bottomOpen: true });
  }

  renameField(from, to) {
    if (from === to) {
      return;
    }
    if (!isIdentifier(to) || this.cur.fields.some(f => f.name === to)) {
      this.log('warn', `Can't rename ${from} to ${to}: `
        + (isIdentifier(to) ? 'that name is taken.' : 'not a usable name.'));
      return;
    }
    this.change(d => {
      d.fields.find(f => f.name === from).name = to;
      for (const e of expressionsOf(d)) {
        const node = e.node;
        // Rewrite each place the old name is read
        if (e.where === 'show if') {
          node.showIf = renameInExpr(node.showIf, from, to);
        }
        else if (e.where === 'repeat') {
          node.repeat.list = renameInExpr(node.repeat.list, from, to);
        }
        else if (e.where.includes(' ')) {
          const [prop, param] = e.where.split(' ');
          node.props[prop].params[param] = renameInExpr(
            node.props[prop].params[param], from, to);
        }
        else if (e.kind === 'template') {
          node.props[e.where].v = renameInTemplate(node.props[e.where].v,
            from, to);
        }
        else {
          node.props[e.where].x = renameInExpr(node.props[e.where].x,
            from, to);
        }
      }
      for (const action of d.actions) {
        for (const effect of action.effects || []) {
          if (effect.field === from) {
            effect.field = to;
          }
        }
      }
    });
  }

  setFieldType(name, type) {
    this.change(d => {
      const field = d.fields.find(f => f.name === name);
      field.type = type;
      const mock = coerce(field.mock, type);
      field.mock = typeOfValue(mock) === type ? mock : defaultMock(type);
    });
  }

  importFields(obj) {
    let count = 0;
    this.change(d => {
      for (const key of Object.keys(obj)) {
        if (!isIdentifier(key)) {
          continue;
        }
        const value = obj[key];
        const type = typeOfValue(value);
        const field = d.fields.find(f => f.name === key);
        if (field) {
          field.type = type;
          field.mock = value;
        }
        else {
          d.fields.push({ name: key, type, mock: value });
        }
        count++;
      }
    });
    return count;
  }

  newAction(suggestion, then) {
    const taken = new Set(this.cur.actions.map(a => a.name));
    let name = suggestion.replace(/[^A-Za-z0-9_-]/g, '_') || 'action';
    let i = 2;
    while (taken.has(name)) {
      name = suggestion + '_' + i++;
    }
    this.change(d => {
      d.actions.push({ name, effects: [] });
    });
    if (then) {
      then(name);
    }
    this.showAction(name);
  }

  renameAction(from, to) {
    if (from === to || !/^[A-Za-z0-9_-]+$/.test(to)
      || this.cur.actions.some(a => a.name === to)) {
      return;
    }
    this.change(d => {
      d.actions.find(a => a.name === from).name = to;
      const visit = node => {
        for (const p of Object.values(node.props || {})) {
          if (p && p.action === from) {
            p.action = to;
          }
        }
        (node.children || []).forEach(visit);
        Object.values(node.slots || {}).forEach(list => list.forEach(visit));
      };
      visit(d.root);
    });
  }

  showAction(name) {
    this.setState({
      bottomTab: 'actions',
      bottomOpen: true,
      focusAction: name,
    });
  }

  /** { fieldName: times read } */
  fieldUsage() {
    const key = JSON.stringify(this.cur.root) + JSON.stringify(
      this.cur.fields.map(f => f.name));
    if (this.usageCache.key !== key) {
      const usage = {};
      for (const e of expressionsOf(this.cur)) {
        const names = e.kind === 'template'
          ? templateNames(e.src) : freeNames(e.src);
        for (const n of names) {
          usage[n] = (usage[n] || 0) + 1;
        }
      }
      this.usageCache = { key, usage };
    }
    return this.usageCache.usage;
  }

  /** { actionName: { count, params } } from the controls that send it. */
  actionUsage() {
    const out = {};
    const visit = node => {
      for (const p of Object.values(node.props || {})) {
        if (p && p.action) {
          const entry = out[p.action] || (out[p.action] = {
            count: 0, params: [],
          });
          entry.count++;
          for (const k of Object.keys(p.params || {})) {
            if (!entry.params.includes(k)) {
              entry.params.push(k);
            }
          }
        }
      }
      (node.children || []).forEach(visit);
      Object.values(node.slots || {}).forEach(list => list.forEach(visit));
    };
    visit(this.cur.root);
    return out;
  }

  /** Names an expression at a node may read, for the { } menus. */
  namesFor(id) {
    const names = this.cur.fields.map(f => ({
      name: f.name, hint: f.type, type: f.type,
    }));
    const data = mockData(this.cur);
    const node = findNode(this.cur, id);
    const scopes = repeatScopes(this.cur, id);
    if (node && node.node.repeat && !scopes.includes(node.node.repeat)) {
      scopes.push(node.node.repeat);
    }
    let vars = { ...data };
    for (const scope of scopes) {
      const res = evaluate(scope.list, makeScope(vars));
      const first = Array.isArray(res.value) ? res.value[0] : undefined;
      const as = scope.as || 'item';
      names.push({ name: as, hint: 'each of ' + scope.list, type: 'item' });
      if (first && typeof first === 'object') {
        for (const key of Object.keys(first)) {
          names.push({
            name: as + '.' + key,
            hint: typeOfValue(first[key]),
            type: typeOfValue(first[key]),
          });
        }
      }
      vars = { ...vars, [as]: first };
    }
    return names;
  }

  // -------------------------------------------------------------------
  // Test mode

  setMode(mode) {
    this.setState({
      mode,
      liveData: mode === 'test' ? mockData(this.cur) : null,
    });
    if (mode === 'test') {
      this.log('info', 'Test mode: controls send their actions and the '
        + 'effects change the mock data.');
    }
  }

  act(action, params) {
    const data = this.state.liveData || mockData(this.cur);
    const res = runAction(this.cur, data, action, params);
    this.setState({ liveData: res.data });
    const p = Object.keys(params).length ? ', ' + JSON.stringify(params) : '';
    this.log('act', `act('${action}'${p})`
      + (res.notes.length ? ' → ' + res.notes.join('; ') : ' → no effects'));
  }

  // -------------------------------------------------------------------
  // Log, save, build

  log(kind, text) {
    this.setState(state => {
      const log = [...state.log, { kind, text, time: now() }];
      if (log.length > 500) {
        log.splice(0, log.length - 500);
      }
      return { log };
    });
  }

  clearLog() {
    this.setState({ log: [] });
  }

  generated() {
    const key = JSON.stringify(this.cur);
    if (this.codeCache.key !== key) {
      let js;
      let dm;
      try {
        js = generateJs(this.cur);
      }
      catch (err) {
        js = '// The code generator failed: ' + err.message;
      }
      try {
        dm = generateDm(this.cur);
      }
      catch (err) {
        dm = '// The code generator failed: ' + err.message;
      }
      this.codeCache = {
        key,
        code: { js, dm, route: routeLines(this.cur).join('\n') + '\n' },
      };
    }
    return this.codeCache.code;
  }

  async save(force) {
    const problems = validateDesign(this.cur);
    if (problems.length) {
      problems.forEach(p => this.log('error', p));
      this.setState({ bottomTab: 'log', bottomOpen: true });
      return;
    }
    const code = this.generated();
    this.setState({ busy: 'Saving…', dialog: null });
    const res = await api.save({
      design: this.cur,
      js: code.js,
      dm: code.dm,
      route: routeLines(this.cur),
      force: !!force,
    });
    this.setState({ busy: '' });
    if (res.conflicts && res.conflicts.length) {
      this.setState({ dialog: { kind: 'conflict',
        conflicts: res.conflicts } });
      return;
    }
    if (res.error) {
      this.log('error', 'Save failed: ' + res.error);
      this.setState({ bottomTab: 'log', bottomOpen: true });
      return;
    }
    // The server stamps what it wrote; that isn't an edit
    const saved = normalizeDesign(res.design);
    this.cur = saved;
    this.setState({ design: saved, dirty: false });
    storage.set(DRAFT_KEY, { design: saved, dirty: false });
    storage.set(LAST_KEY, saved.name);
    for (const line of res.written || []) {
      this.log('ok', 'Wrote ' + line);
    }
    if (res.lint) {
      if (res.lint.ok) {
        this.log('ok', 'eslint: clean.');
      }
      else {
        this.log('error', 'eslint found problems:');
        res.lint.output.split('\n').filter(Boolean)
          .forEach(l => this.log('out', l));
        this.setState({ bottomTab: 'log', bottomOpen: true });
      }
    }
    this.log('info', 'Saved. Build to put it in the game\'s bundle.');
  }

  async run(what) {
    if (this.state.job && !this.state.job.done) {
      return;
    }
    const label = what === 'build' ? 'Build' : 'DM check';
    const res = await api.run(what);
    if (res.error) {
      this.log('error', label + ': ' + res.error);
      return;
    }
    const started = Date.now();
    const job = { id: res.id, label, done: false, since: 0 };
    this.setState({ job, bottomTab: 'log', bottomOpen: true });
    this.log('info', label + ' started: ' + res.command);
    const poll = async () => {
      const r = await api.job(job.id, job.since);
      if (r.error) {
        this.log('error', label + ': ' + r.error);
        this.setState({ job: { ...job, done: true } });
        return;
      }
      for (const line of r.lines) {
        this.log(/error|failed/i.test(line) ? 'error' : 'out', line);
      }
      job.since = r.next;
      if (r.done) {
        const secs = ((Date.now() - started) / 1000).toFixed(1);
        this.log(r.code === 0 ? 'ok' : 'error', `${label} ${r.code === 0
          ? 'finished' : 'failed (exit ' + r.code + ')'} in ${secs} s.`);
        this.setState({ job: { ...job, done: true } });
        return;
      }
      setTimeout(poll, 700);
    };
    setTimeout(poll, 500);
  }

  async open(name, quiet) {
    const res = await api.load(name);
    if (res.error) {
      if (!quiet) {
        this.log('error', 'Open failed: ' + res.error);
      }
      return;
    }
    this.loadDesign(normalizeDesign(res.design));
    this.setState({ dialog: null });
    if (!quiet) {
      this.log('info', 'Opened ' + name + '.');
    }
  }

  async showOpen() {
    this.setState({ dialog: { kind: 'open', designs: null } });
    const res = await api.designs();
    this.setState({ dialog: { kind: 'open', designs: res.designs,
      error: res.error } });
  }

  confirmDiscard() {
    return !this.state.dirty || window.confirm(
      'Drop the unsaved changes to ' + this.cur.name + '?');
  }

  // -------------------------------------------------------------------

  renderToolbar() {
    const { design, dirty, mode, showHidden, zoom, busy, job } = this.state;
    const running = job && !job.done;
    return (
      <div className="toolbar">
        <span className="toolbar__brand">
          <i className="fas fa-drafting-compass" /> tgui designer
        </span>
        <span className="toolbar__name" title="Window settings">
          <span onClick={() => this.setState({ rightTab: 'window' })}>
            {design.name}
          </span>
          {dirty && <span className="toolbar__dirty" title="Unsaved">●</span>}
        </span>
        <span
          className="tbtn"
          title="New window"
          onClick={() => this.confirmDiscard()
            && this.setState({ dialog: { kind: 'new' } })}>
          <i className="fas fa-file" /> New
        </span>
        <span
          className="tbtn"
          title="Open a saved design"
          onClick={() => this.confirmDiscard() && this.showOpen()}>
          <i className="fas fa-folder-open" /> Open
        </span>
        <span className="toolbar__sep" />
        <span
          className={'tbtn' + (this.past.length ? '' : ' tbtn--off')}
          title="Undo (Ctrl+Z)"
          onClick={() => this.undo()}>
          <i className="fas fa-undo" />
        </span>
        <span
          className={'tbtn' + (this.future.length ? '' : ' tbtn--off')}
          title="Redo (Ctrl+Y)"
          onClick={() => this.redo()}>
          <i className="fas fa-redo" />
        </span>
        <span className="toolbar__sep" />
        <span className="seg">
          <span
            className={'seg__opt' + (mode === 'design' ? ' seg__opt--on' : '')}
            title="Arrange and edit"
            onClick={() => this.setMode('design')}>
            <i className="fas fa-pencil-ruler" /> Design
          </span>
          <span
            className={'seg__opt' + (mode === 'test' ? ' seg__opt--on' : '')}
            title="Use the window: buttons run their actions on mock data"
            onClick={() => this.setMode('test')}>
            <i className="fas fa-play" /> Test
          </span>
        </span>
        {mode === 'test' && (
          <span
            className="tbtn"
            title="Back to the mock values"
            onClick={() => this.setState({ liveData: mockData(this.cur) })}>
            <i className="fas fa-sync" /> Reset data
          </span>
        )}
        {mode === 'design' && (
          <span
            className={'tbtn' + (showHidden ? ' tbtn--on' : '')}
            title="Show items hidden by their show-if, faded"
            onClick={() => this.setState(state => ({
              showHidden: !state.showHidden,
            }))}>
            <i className={'fas fa-' + (showHidden ? 'eye' : 'eye-slash')} />
            {' Hidden'}
          </span>
        )}
        <select
          className="sel toolbar__zoom"
          value={String(zoom)}
          title="Zoom"
          onChange={e => this.setState({ zoom: Number(e.target.value) })}>
          {ZOOMS.map(z => (
            <option key={z} value={String(z)}>{Math.round(z * 100)}%</option>
          ))}
        </select>
        <span className="toolbar__spacer" />
        {busy && <span className="toolbar__busy">{busy}</span>}
        <span
          className="tbtn tbtn--primary"
          title={'Write the design, interface, route and DM into the '
            + 'repo (Ctrl+S)'}
          onClick={() => this.save(false)}>
          <i className="fas fa-save" /> Save
        </span>
        <span
          className={'tbtn' + (running ? ' tbtn--off' : '')}
          title="yarn build: lint and bundle tgui-next (about a minute)"
          onClick={() => this.run('build')}>
          <i className="fas fa-hammer" /> Build
        </span>
        <span
          className={'tbtn' + (running ? ' tbtn--off' : '')}
          title="Compile the DM in a side copy (the real .dmb is untouched)"
          onClick={() => this.run('compile')}>
          <i className="fas fa-check-double" /> Check DM
        </span>
      </div>
    );
  }

  renderBottom() {
    const { bottomTab, bottomOpen, log, design, focusAction } = this.state;
    const errorsInLog = log.filter(l => l.kind === 'error').length;
    const tabs = [
      ['data', 'Data', design.fields.length],
      ['actions', 'Actions', design.actions.length],
      ['code', 'Code', null],
      ['log', 'Log', errorsInLog || null],
    ];
    let panel = null;
    if (bottomOpen) {
      if (bottomTab === 'data') {
        panel = <DataPanel app={this} />;
      }
      else if (bottomTab === 'actions') {
        panel = <ActionsPanel app={this} focusAction={focusAction} />;
      }
      else if (bottomTab === 'code') {
        panel = <CodePanel app={this} />;
      }
      else {
        panel = <LogPanel app={this} />;
      }
    }
    return (
      <div className={'bottom' + (bottomOpen ? '' : ' bottom--closed')}>
        <div className="bottom__tabs">
          {tabs.map(([key, label, count]) => (
            <span
              key={key}
              className={'tab' + (bottomTab === key && bottomOpen
                ? ' tab--on' : '')}
              onClick={() => this.setState({
                bottomTab: key,
                bottomOpen: !(bottomOpen && bottomTab === key),
              })}>
              {label}
              {count ? <span className="pill">{count}</span> : null}
            </span>
          ))}
          <span className="toolbar__spacer" />
          <span
            className="iconbtn"
            title={bottomOpen ? 'Hide' : 'Show'}
            onClick={() => this.setState({ bottomOpen: !bottomOpen })}>
            <i className={'fas fa-chevron-' + (bottomOpen ? 'down' : 'up')} />
          </span>
        </div>
        {panel}
      </div>
    );
  }

  renderDialog() {
    const { dialog, design } = this.state;
    if (!dialog) {
      return null;
    }
    const close = () => this.setState({ dialog: null });
    if (dialog.kind === 'new') {
      return (
        <NewDialog
          onClose={close}
          onCreate={name => {
            this.loadDesign(createDesign(name), true);
            this.setState({ dialog: null, rightTab: 'window' });
            this.log('info', `New window ${name}. Drag components in from `
              + 'the left.');
          }} />
      );
    }
    if (dialog.kind === 'open') {
      return (
        <OpenDialog
          designs={dialog.designs}
          error={dialog.error}
          current={design.name}
          onClose={close}
          onOpen={name => this.open(name)} />
      );
    }
    if (dialog.kind === 'conflict') {
      return (
        <ConflictDialog
          conflicts={dialog.conflicts}
          onClose={close}
          onOverwrite={() => this.save(true)} />
      );
    }
    return null;
  }

  render() {
    const { design, mode, liveData, selectedId, hoverId, showHidden,
      activeTabs, drag, dropTarget, zoom, rightTab, errors, focus,
      icons } = this.state;
    const data = mode === 'test' && liveData ? liveData : mockData(design);
    return (
      <div className="app">
        {this.renderToolbar()}
        <div className="main">
          <div className="left">
            <div className="left__title">Components</div>
            <Palette
              onStartDrag={(payload, x, y) => this.beginDrag(payload, x, y)}
              onAdd={type => this.addComponent(type)} />
            <div className="left__title">Outline</div>
            <Outline
              ref={this.outlineRef}
              design={design}
              selectedId={selectedId}
              errors={errors}
              dropTarget={dropTarget}
              onSelect={id => this.select(id)}
              onHover={id => this.setState({ hoverId: id })}
              onStartDrag={(payload, x, y) => this.beginDrag(payload, x,
                y)} />
          </div>
          <div className="center">
            <Canvas
              ref={this.canvasRef}
              design={design}
              data={data}
              mode={mode}
              zoom={zoom}
              selectedId={selectedId}
              hoverId={hoverId}
              showHidden={showHidden}
              activeTabs={activeTabs}
              dragging={!!(drag && drag.active)}
              dropTarget={dropTarget && dropTarget.source === 'canvas'
                ? dropTarget : null}
              onHover={id => {
                if (id !== this.state.hoverId) {
                  this.setState({ hoverId: id });
                }
              }}
              onNodeMouseDown={(id, x, y, button, double) => this
                .nodeMouseDown(id, x, y, button, double)}
              onKeyDown={k => this.handleKey(k)}
              onAct={(action, params) => this.act(action, params)}
              onErrors={next => {
                if (JSON.stringify(next) !== JSON.stringify(errors)) {
                  this.setState({ errors: next });
                }
              }}
              onResize={(w, h, live) => {
                if (w === null) {
                  this.lastKey = null;
                  return;
                }
                this.change(d => {
                  d.width = w;
                  d.height = h;
                }, 'resize');
              }} />
            {this.renderBottom()}
          </div>
          <div className="right">
            <div className="right__tabs">
              <span
                className={'tab' + (rightTab === 'item' ? ' tab--on' : '')}
                onClick={() => this.setState({ rightTab: 'item' })}>
                Item
              </span>
              <span
                className={'tab' + (rightTab === 'window' ? ' tab--on' : '')}
                onClick={() => this.setState({ rightTab: 'window' })}>
                Window
              </span>
            </div>
            <div className="right__body">
              {rightTab === 'item'
                ? <Inspector app={this} focus={focus} />
                : <WindowPanel app={this} />}
            </div>
          </div>
        </div>
        {drag && (
          <div className={'shield' + (drag.active ? ' shield--active' : '')}>
            {drag.active && (
              <div
                className={'ghost' + (drag.ok ? '' : ' ghost--no')}
                style={{
                  left: (drag.x + 12) + 'px',
                  top: (drag.y + 8) + 'px',
                }}>
                {drag.label}
              </div>
            )}
          </div>
        )}
        {this.renderDialog()}
        <Datalists icons={icons} />
      </div>
    );
  }
}
