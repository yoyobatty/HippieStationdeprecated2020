/**
 * The selected item's properties: its own props, its style, when it shows
 * (show if) and whether it repeats per list entry.
 */

import { Component } from 'inferno';
import { findNode, repeatScopes, toSnake } from '../shared/model';
import { BUTTON_COLORS, COLORS, getDef, labelOf, stylePropsOf } from '../shared/registry';
import { RANGE_MODES } from '../shared/ranges';
import { templateNames } from '../shared/expr';
import { ExprInput, NumberBox, Row, Select, TextInput } from './editors';

const literalCode = v => {
  if (v === undefined || v === null) {
    return '';
  }
  if (typeof v === 'string') {
    return JSON.stringify(v).replace(/^"|"$/g, '\'');
  }
  return JSON.stringify(v);
};

/**
 * A name for a control's new action: its fixed text ("Eject" -> eject),
 * or toggle_<field> when its text only shows a yes/no field.
 */
const suggestActionName = (node, design) => {
  const text = ['content', 'label']
    .map(name => node.props[name] && node.props[name].v)
    .find(v => typeof v === 'string' && v.trim());
  if (text) {
    const fixed = toSnake(text.replace(/\{[^}]*\}/g, ' '));
    if (fixed) {
      return fixed;
    }
    const names = templateNames(text);
    const bool = design.fields.find(f => f.type === 'bool'
      && names.includes(f.name));
    if (bool) {
      return 'toggle_' + bool.name;
    }
    if (names.length) {
      return 'set_' + toSnake(names[0]);
    }
  }
  if (node.type === 'Input' || node.type === 'NumberInput'
    || node.type === 'Dropdown') {
    return 'set_value';
  }
  return 'action';
};

const ActionEditor = props => {
  const { app, node, def, prop, names, known } = props;
  const design = app.state.design;
  const p = prop || {};
  const params = p.params || {};
  const set = next => app.setProp(node.id, def.name, next);
  const suggestion = suggestActionName(node, design);
  return (
    <div className="act">
      <div className="tin__row">
        <Select
          value={p.action || ''}
          empty="(does nothing)"
          options={[
            ...design.actions.map(a => a.name),
            ...(p.action && !design.actions.find(a => a.name === p.action)
              ? [p.action] : []),
            { value: '__new', label: 'New action…' },
          ]}
          onChange={value => {
            if (value === '__new') {
              app.newAction(suggestion, name => set({
                action: name,
                params: def.valueVar ? { value: 'value' } : {},
              }));
              return;
            }
            set(value ? { action: value, params } : undefined);
          }} />
        {p.action && (
          <span
            className="iconbtn"
            title="Edit what this action does"
            onClick={() => app.showAction(p.action)}>
            <i className="fas fa-bolt" />
          </span>
        )}
      </div>
      {p.action && (
        <div className="act__params">
          {Object.keys(params).map(key => (
            <div key={key} className="act__param">
              <input
                className="tin__input act__key"
                value={key}
                spellCheck={false}
                onInput={e => {
                  const next = {};
                  for (const k of Object.keys(params)) {
                    next[k === key ? e.target.value : k] = params[k];
                  }
                  set({ ...p, params: next });
                }} />
              <span className="act__eq">=</span>
              <ExprInput
                value={params[key]}
                names={names}
                known={known}
                extraKnown={def.valueVar ? ['value'] : []}
                onAddField={app.addFieldNamed}
                onChange={value => set({
                  ...p, params: { ...params, [key]: value },
                })} />
              <span
                className="iconbtn"
                title="Remove this param"
                onClick={() => {
                  const next = { ...params };
                  delete next[key];
                  set({ ...p, params: next });
                }}>
                <i className="fas fa-times" />
              </span>
            </div>
          ))}
          <div
            className="linkbtn"
            onClick={() => {
              let key = def.valueVar ? 'value' : 'param';
              let n = 2;
              while (params[key] !== undefined) {
                key = (def.valueVar ? 'value' : 'param') + n++;
              }
              set({
                ...p,
                params: { ...params, [key]: def.valueVar ? 'value' : '' },
              });
            }}>
            + param
          </div>
          {def.valueVar && (
            <div className="hint">
              value = what was {node.type === 'Dropdown'
                ? 'picked' : 'entered'}
            </div>
          )}
        </div>
      )}
    </div>
  );
};

const RangesEditor = props => {
  const { value, onChange } = props;
  const r = value || { mode: 'none' };
  return (
    <div className="ranges">
      <Select
        value={r.mode || 'none'}
        empty={false}
        options={RANGE_MODES.map(m => ({ value: m.mode, label: m.label }))}
        onChange={mode => onChange(mode === 'none' ? undefined : {
          hi: 0.66, lo: 0.33, ...r, mode,
        })} />
      {r.mode && r.mode !== 'none' && (
        <div className="ranges__nums">
          <span>bad</span>
          <NumberBox
            value={r.mode === 'high' ? r.lo : r.hi}
            onChange={n => onChange(r.mode === 'high'
              ? { ...r, lo: n } : { ...r, hi: n })} />
          <span>good</span>
          <NumberBox
            value={r.mode === 'high' ? r.hi : r.lo}
            onChange={n => onChange(r.mode === 'high'
              ? { ...r, hi: n } : { ...r, lo: n })} />
        </div>
      )}
    </div>
  );
};

/** One prop: picks the editor for its kind, with the ƒ bind toggle. */
const PropRow = props => {
  const { app, node, def, names, known, focusKey } = props;
  const prop = node.props[def.name];
  const set = value => app.setProp(node.id, def.name, value);
  const label = def.label
    || def.name.charAt(0).toUpperCase() + def.name.slice(1);
  const bound = !!prop && prop.x !== undefined;
  const bindable = !['text', 'expr', 'action', 'ranges'].includes(def.kind);
  const onBind = bindable ? () => {
    if (bound) {
      set(undefined);
    }
    else {
      set({ x: prop ? literalCode(prop.v) : '' });
    }
  } : null;
  if (bound || def.kind === 'expr') {
    const value = prop && prop.x !== undefined
      ? prop.x : literalCode(prop && prop.v);
    return (
      <Row label={label} bound={bound} onBind={onBind}>
        <ExprInput
          value={value}
          names={names}
          known={known}
          onAddField={app.addFieldNamed}
          onChange={x => set(x === '' && def.kind !== 'expr'
            ? { x: '' } : { x })} />
      </Row>
    );
  }
  const v = prop ? prop.v : undefined;
  let editor;
  switch (def.kind) {
    case 'text':
      editor = (
        <TextInput
          value={v}
          template
          names={names}
          known={known}
          multiline={def.multiline}
          placeholder={def.placeholder}
          focusKey={focusKey}
          onAddField={app.addFieldNamed}
          onChange={s => set(s === '' ? undefined : { v: s })} />
      );
      break;
    case 'number':
      editor = (
        <NumberBox
          value={v}
          onChange={n => set(n === undefined ? undefined : { v: n })} />
      );
      break;
    case 'bool':
      editor = (
        <input
          type="checkbox"
          checked={!!v}
          onChange={e => set(e.target.checked ? { v: true } : undefined)} />
      );
      break;
    case 'select':
      editor = (
        <Select
          value={v}
          options={def.options}
          onChange={s => {
            if (s === '') {
              set(undefined);
              return;
            }
            const num = def.options.find(o => String(o) === s);
            set({ v: num !== undefined ? num : s });
          }} />
      );
      break;
    case 'color':
    case 'buttonColor':
    case 'icon':
    case 'size': {
      const list = {
        color: 'dl-colors', buttonColor: 'dl-button-colors',
        icon: 'dl-icons', size: null,
      }[def.kind];
      editor = (
        <div className="tin__row">
          <input
            className="tin__input"
            value={v === undefined || v === null ? '' : v}
            list={list || undefined}
            spellCheck={false}
            placeholder={def.kind === 'size' ? 'units or 60px' : ''}
            onInput={e => {
              const s = e.target.value.trim();
              if (!s) {
                set(undefined);
                return;
              }
              const n = Number(s);
              set({ v: def.kind === 'size' && Number.isFinite(n)
                && String(n) === s ? n : e.target.value });
            }} />
          {def.kind === 'icon' && v && (
            <i className={'prow__icon fas fa-' + v} />
          )}
        </div>
      );
      break;
    }
    case 'list':
      editor = (
        <textarea
          className="tin__input tin__input--multi"
          rows={3}
          value={Array.isArray(v) ? v.join('\n') : ''}
          placeholder="one per line"
          onInput={e => set({ v: e.target.value.split('\n') })} />
      );
      break;
    case 'action':
      editor = (
        <ActionEditor
          app={app}
          node={node}
          def={def}
          prop={prop}
          names={names}
          known={known} />
      );
      break;
    case 'ranges':
      editor = <RangesEditor value={v} onChange={r => set(r && { v: r })} />;
      break;
    default:
      editor = <span>?</span>;
  }
  return (
    <Row label={label} bound={false} onBind={onBind}>
      {editor}
    </Row>
  );
};

export class Inspector extends Component {
  constructor(props) {
    super(props);
    this.state = { styleOpen: false };
  }

  render() {
    const { app, focus } = this.props;
    const { design, selectedId, errors } = app.state;
    const found = selectedId && findNode(design, selectedId);
    if (!found) {
      return (
        <div className="insp insp--empty">
          <p>Click something in the window to edit it.</p>
          <p className="hint">
            Drag components from the left. Bind values to data in the Data
            tab below; buttons send actions you set up in Actions.
          </p>
        </div>
      );
    }
    const node = found.node;
    const def = getDef(node.type);
    const names = app.namesFor(node.id);
    const known = names.map(n => n.name.split('.')[0]);
    const styleDefs = stylePropsOf(node.type);
    const styleSet = styleDefs.filter(s => node.props[s.name]).length;
    const scopes = repeatScopes(design, node.id)
      .filter(s => s !== node.repeat);
    const focusKey = focus && focus.id === node.id ? focus.n : null;
    const rowProps = { app, node, names, known };
    return (
      <div className="insp">
        <div className="insp__head">
          <i className={'fas fa-' + def.icon} />
          <span className="insp__type">{labelOf(node.type)}</span>
          <span className="insp__id">{node.id}</span>
          <span className="insp__tools">
            <span
              className="iconbtn"
              title="Select the parent (Esc)"
              onClick={() => app.select(found.parent.id === 'root'
                ? null : found.parent.id)}>
              <i className="fas fa-level-up-alt" />
            </span>
            <span
              className="iconbtn"
              title="Duplicate (Ctrl+D)"
              onClick={() => app.duplicate(node.id)}>
              <i className="fas fa-clone" />
            </span>
            <span
              className="iconbtn iconbtn--danger"
              title="Delete (Del)"
              onClick={() => app.deleteNode(node.id)}>
              <i className="fas fa-trash" />
            </span>
          </span>
        </div>
        {errors[node.id] && (
          <div className="insp__errors">
            {errors[node.id].map(e => <div key={e}>{e}</div>)}
          </div>
        )}
        <div className="insp__section">
          {def.props.map(p => (
            <PropRow
              key={p.name}
              def={p}
              focusKey={p.name === def.textProp ? focusKey : null}
              {...rowProps} />
          ))}
          {def.props.length === 0 && (
            <div className="hint">Nothing to set; it holds other items.</div>
          )}
        </div>
        {def.style && (
          <div className="insp__section">
            <div
              className="insp__fold"
              onClick={() => this.setState(state => ({
                styleOpen: !state.styleOpen,
              }))}>
              <i className={'fas fa-caret-'
                + (this.state.styleOpen ? 'down' : 'right')} />
              {' Style'}
              {styleSet > 0 && <span className="pill">{styleSet}</span>}
            </div>
            {this.state.styleOpen && styleDefs.map(p => (
              <PropRow key={p.name} def={p} {...rowProps} />
            ))}
          </div>
        )}
        <div className="insp__section">
          <div className="insp__sub">When it shows</div>
          <Row label="Show if" title="Leave empty to always show it">
            <ExprInput
              value={node.showIf || ''}
              names={names}
              known={known}
              placeholder="always"
              onAddField={app.addFieldNamed}
              onChange={x => app.changeNode(node.id, n => {
                if (x) {
                  n.showIf = x;
                }
                else {
                  delete n.showIf;
                }
              }, 'showIf')} />
          </Row>
          <Row label="Repeat for" title="One copy per entry in a list">
            <ExprInput
              value={(node.repeat && node.repeat.list) || ''}
              names={names.filter(n => n.type === 'list'
                || n.name.includes('.'))}
              known={known}
              placeholder="no repeat (a list field)"
              onAddField={app.addFieldNamed}
              onChange={x => app.changeNode(node.id, n => {
                if (x) {
                  n.repeat = { as: 'item', ...(n.repeat || {}), list: x };
                }
                else {
                  delete n.repeat;
                }
              }, 'repeat')} />
          </Row>
          {node.repeat && node.repeat.list && (
            <Row label="Each one is" title="The name an entry goes by">
              <input
                className="tin__input tin__input--code"
                value={node.repeat.as || 'item'}
                spellCheck={false}
                onInput={e => app.changeNode(node.id, n => {
                  n.repeat.as = e.target.value.replace(/[^\w$]/g, '');
                }, 'repeatAs')} />
            </Row>
          )}
          {scopes.length > 0 && (
            <div className="hint">
              Inside a repeat: {scopes.map(s => s.as).join(', ')} can be
              used here.
            </div>
          )}
        </div>
        <div className="insp__section">
          <div className="insp__sub">Wrap in</div>
          <div className="wraps">
            {['Section', 'Box', 'LabeledList', 'Flex', 'Collapsible']
              .map(type => (
                <span
                  key={type}
                  className="chip"
                  onClick={() => app.wrap(node.id, type)}>
                  {labelOf(type)}
                </span>
              ))}
          </div>
        </div>
      </div>
    );
  }
}

export const Datalists = props => (
  <div style={{ display: 'none' }}>
    <datalist id="dl-colors">
      {COLORS.map(c => <option key={c} value={c} />)}
    </datalist>
    <datalist id="dl-button-colors">
      {BUTTON_COLORS.map(c => <option key={c} value={c} />)}
    </datalist>
    <datalist id="dl-icons">
      {(props.icons || []).map(c => <option key={c} value={c} />)}
    </datalist>
    <datalist id="dl-types">
      {(props.types || []).map(c => <option key={c} value={c} />)}
    </datalist>
  </div>
);
