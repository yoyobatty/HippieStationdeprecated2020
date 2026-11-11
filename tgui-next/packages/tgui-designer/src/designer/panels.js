/**
 * The bottom panels: Data (fields and their mock values), Actions (what
 * buttons do), Code (what Save writes) and Log.
 */

import { Component } from 'inferno';
import { EFFECT_OPS } from '../shared/effects';
import { FIELD_TYPES, isIdentifier } from '../shared/model';
import { NumberBox, Select } from './editors';

/** A name box that only commits on Enter or leaving it. */
class NameInput extends Component {
  constructor(props) {
    super(props);
    this.state = { text: null };
  }

  commit() {
    const { value, onCommit } = this.props;
    const text = this.state.text;
    this.setState({ text: null });
    if (text !== null && text !== value) {
      onCommit(text);
    }
  }

  render() {
    const { value, valid } = this.props;
    const text = this.state.text === null ? value : this.state.text;
    const bad = valid && !valid(text);
    return (
      <input
        className={'tin__input tin__input--code'
          + (bad ? ' tin__input--error' : '')}
        value={text}
        spellCheck={false}
        onInput={e => this.setState({ text: e.target.value })}
        onBlur={() => this.commit()}
        onKeyDown={e => {
          if (e.key === 'Enter') {
            e.target.blur();
          }
          if (e.key === 'Escape') {
            this.setState({ text: null });
          }
        }} />
    );
  }
}

/** A JSON box for list and object values; red until it parses. */
class JsonInput extends Component {
  constructor(props) {
    super(props);
    this.state = { text: null };
  }

  render() {
    const { value, onChange } = this.props;
    const shown = this.state.text === null
      ? JSON.stringify(value === undefined ? null : value)
      : this.state.text;
    let bad = false;
    try {
      JSON.parse(shown);
    }
    catch (err) {
      bad = true;
    }
    return (
      <textarea
        className={'tin__input tin__input--code tin__input--json'
          + (bad ? ' tin__input--error' : '')}
        rows={1}
        value={shown}
        spellCheck={false}
        onInput={e => {
          const text = e.target.value;
          this.setState({ text });
          try {
            onChange(JSON.parse(text));
          }
          catch (err) {
            // Wait until it parses
          }
        }}
        onBlur={() => this.setState({ text: null })} />
    );
  }
}

const MockEditor = props => {
  const { field, onChange } = props;
  switch (field.type) {
    case 'number':
      return (
        <NumberBox
          value={field.mock}
          onChange={n => onChange(n === undefined ? 0 : n)} />
      );
    case 'bool':
      return (
        <input
          type="checkbox"
          checked={!!field.mock}
          onChange={e => onChange(e.target.checked)} />
      );
    case 'list':
    case 'object':
      return <JsonInput value={field.mock} onChange={onChange} />;
    default:
      return (
        <input
          className="tin__input"
          value={field.mock === undefined ? '' : field.mock}
          onInput={e => onChange(e.target.value)} />
      );
  }
};

export class DataPanel extends Component {
  constructor(props) {
    super(props);
    this.state = { paste: null, note: '' };
  }

  importJson() {
    const { app } = this.props;
    let obj;
    try {
      obj = JSON.parse(this.state.paste);
    }
    catch (err) {
      this.setState({ note: 'That isn\'t JSON: ' + err.message });
      return;
    }
    if (!obj || typeof obj !== 'object' || Array.isArray(obj)) {
      this.setState({ note: 'Paste an object, like ui_data sends.' });
      return;
    }
    const count = app.importFields(obj);
    this.setState({ paste: null, note: `${count} fields set.` });
  }

  render() {
    const { app } = this.props;
    const { design } = app.state;
    const usage = app.fieldUsage();
    const { paste, note } = this.state;
    return (
      <div className="panel">
        <div className="panel__tools">
          <span className="btn" onClick={() => app.addField()}>
            <i className="fas fa-plus" /> Field
          </span>
          <span
            className="btn"
            onClick={() => this.setState({ paste: paste === null ? '' : null,
              note: '' })}>
            <i className="fas fa-paste" /> Paste ui_data JSON
          </span>
          <span className="hint">
            Mock values feed the preview. DM value is what ui_data()
            sends (a var by default).
          </span>
          {note && <span className="note">{note}</span>}
        </div>
        {paste !== null && (
          <div className="paste">
            <textarea
              className="tin__input tin__input--code"
              rows={4}
              value={paste}
              placeholder={'{"on": 1, "charge": 75, '
                + '"items": [{"name": "x"}]}'}
              onInput={e => this.setState({ paste: e.target.value })} />
            <span
              className="btn btn--primary"
              onClick={() => this.importJson()}>
              Add fields
            </span>
          </div>
        )}
        {design.fields.length === 0 && paste === null && (
          <div className="empty">
            No fields yet. A field is a value the game sends (on, charge,
            a list of things). Add one, or type {'{name}'} in a text and
            use + add.
          </div>
        )}
        {design.fields.length > 0 && (
          <table className="grid">
            <thead>
              <tr>
                <th>Field</th>
                <th>Type</th>
                <th>Mock value</th>
                <th>DM value</th>
                <th title="Sent once (ui_static_data)">Static</th>
                <th>Used</th>
                <th />
              </tr>
            </thead>
            <tbody>
              {design.fields.map((field, i) => (
                <tr key={i}>
                  <td>
                    <NameInput
                      value={field.name}
                      valid={isIdentifier}
                      onCommit={name => app.renameField(field.name, name)} />
                  </td>
                  <td>
                    <Select
                      value={field.type}
                      empty={false}
                      options={FIELD_TYPES}
                      onChange={type => app.setFieldType(field.name, type)} />
                  </td>
                  <td className="grid__wide">
                    <MockEditor
                      field={field}
                      onChange={mock => app.change(d => {
                        d.fields[i].mock = mock;
                      }, 'mock:' + field.name)} />
                  </td>
                  <td>
                    <input
                      className="tin__input tin__input--code"
                      value={field.dm || ''}
                      placeholder={field.name}
                      spellCheck={false}
                      onInput={e => app.change(d => {
                        d.fields[i].dm = e.target.value;
                      }, 'dm:' + field.name)} />
                  </td>
                  <td>
                    <input
                      type="checkbox"
                      checked={!!field.isStatic}
                      onChange={e => app.change(d => {
                        d.fields[i].isStatic = e.target.checked;
                      })} />
                  </td>
                  <td className={usage[field.name] ? '' : 'grid__unused'}>
                    {usage[field.name] || 0}
                  </td>
                  <td>
                    <span
                      className="iconbtn iconbtn--danger"
                      title="Remove the field"
                      onClick={() => app.change(d => {
                        d.fields.splice(i, 1);
                      })}>
                      <i className="fas fa-times" />
                    </span>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    );
  }
}

const EffectRow = props => {
  const { app, action, effect, ai, ei, params } = props;
  const { design } = app.state;
  const set = fn => app.change(d => fn(d.actions[ai].effects[ei]),
    'effect:' + action.name + ':' + ei);
  const field = design.fields.find(f => f.name === effect.field);
  const fieldSelect = (
    <Select
      value={effect.field || ''}
      empty="(field)"
      options={design.fields.map(f => f.name)}
      onChange={name => set(e => {
        e.field = name;
      })} />
  );
  const minMax = (
    <span className="effect__minmax">
      <span>min</span>
      <NumberBox
        value={effect.min}
        onChange={n => set(e => {
          e.min = n;
        })} />
      <span>max</span>
      <NumberBox
        value={effect.max}
        onChange={n => set(e => {
          e.max = n;
        })} />
    </span>
  );
  let rest = null;
  switch (effect.op) {
    case 'toggle':
      rest = fieldSelect;
      break;
    case 'set':
      rest = (
        <span className="effect__parts">
          {fieldSelect}
          <span>to</span>
          {field && field.type === 'bool' ? (
            <input
              type="checkbox"
              checked={effect.value === true}
              onChange={e => set(ef => {
                ef.value = e.target.checked;
              })} />
          ) : (
            <input
              className="tin__input"
              value={effect.value === undefined ? '' : effect.value}
              onInput={e => set(ef => {
                ef.value = e.target.value;
              })} />
          )}
        </span>
      );
      break;
    case 'param':
      rest = (
        <span className="effect__parts">
          {fieldSelect}
          <span>to params.</span>
          <input
            className="tin__input tin__input--code effect__param"
            value={effect.param || ''}
            list={'dl-params-' + ai}
            placeholder="value"
            spellCheck={false}
            onInput={e => set(ef => {
              ef.param = e.target.value;
            })} />
          <datalist id={'dl-params-' + ai}>
            {params.map(p => <option key={p} value={p} />)}
          </datalist>
          {field && field.type === 'number' && minMax}
        </span>
      );
      break;
    case 'add':
      rest = (
        <span className="effect__parts">
          {fieldSelect}
          <span>by</span>
          <NumberBox
            value={effect.amount}
            onChange={n => set(e => {
              e.amount = n;
            })} />
          {minMax}
        </span>
      );
      break;
    case 'dm':
      rest = (
        <textarea
          className="tin__input tin__input--code effect__dm"
          rows={2}
          value={effect.code || ''}
          placeholder="DM code for ui_act()"
          spellCheck={false}
          onKeyDown={e => {
            if (e.key === 'Tab') {
              e.preventDefault();
              const el = e.target;
              const s = el.selectionStart;
              const v = el.value;
              const next = v.slice(0, s) + '\t' + v.slice(el.selectionEnd);
              set(ef => {
                ef.code = next;
              });
              setTimeout(() => el.setSelectionRange(s + 1, s + 1));
            }
          }}
          onInput={e => set(ef => {
            ef.code = e.target.value;
          })} />
      );
      break;
    default:
      break;
  }
  return (
    <div className="effect">
      <Select
        value={effect.op}
        empty={false}
        options={EFFECT_OPS.map(o => ({ value: o.op, label: o.label }))}
        onChange={op => set(e => {
          e.op = op;
        })} />
      {rest}
      <span
        className="iconbtn iconbtn--danger"
        title="Remove the effect"
        onClick={() => app.change(d => {
          d.actions[ai].effects.splice(ei, 1);
        })}>
        <i className="fas fa-times" />
      </span>
    </div>
  );
};

export const ActionsPanel = props => {
  const { app, focusAction } = props;
  const { design } = app.state;
  const used = app.actionUsage();
  return (
    <div className="panel">
      <div className="panel__tools">
        <span className="btn" onClick={() => app.newAction('action')}>
          <i className="fas fa-plus" /> Action
        </span>
        <span className="hint">
          {'An action is what a control sends: act(\'name\', params). Its '
            + 'effects run on the mock data in Test mode and become ui_act() '
            + 'code.'}
        </span>
      </div>
      {design.actions.length === 0 && (
        <div className="empty">
          No actions yet. Select a button and pick New action under On
          click.
        </div>
      )}
      {design.actions.map((action, ai) => {
        const use = used[action.name] || { count: 0, params: [] };
        return (
          <div
            key={ai}
            className={'card' + (focusAction === action.name
              ? ' card--focus' : '')}>
            <div className="card__head">
              <i className="fas fa-bolt" />
              <NameInput
                value={action.name}
                valid={n => /^[A-Za-z0-9_-]+$/.test(n)}
                onCommit={name => app.renameAction(action.name, name)} />
              <span className="hint">
                {use.count
                  ? `sent by ${use.count} control${use.count > 1 ? 's' : ''}`
                  : 'not sent by anything yet'}
                {use.params.length
                  ? ' with ' + use.params.join(', ') : ''}
              </span>
              <span
                className="iconbtn iconbtn--danger"
                title="Remove the action"
                onClick={() => app.change(d => {
                  d.actions.splice(ai, 1);
                })}>
                <i className="fas fa-trash" />
              </span>
            </div>
            {(action.effects || []).map((effect, ei) => (
              <EffectRow
                key={ei}
                app={app}
                action={action}
                effect={effect}
                ai={ai}
                ei={ei}
                params={use.params} />
            ))}
            <div
              className="linkbtn"
              onClick={() => app.change(d => {
                const fields = d.fields;
                const bool = fields.find(f => f.type === 'bool');
                d.actions[ai].effects.push(bool
                  ? { op: 'toggle', field: bool.name }
                  : { op: 'set', field: fields[0] && fields[0].name,
                    value: '' });
              })}>
              + effect
            </div>
          </div>
        );
      })}
    </div>
  );
};

export class CodePanel extends Component {
  constructor(props) {
    super(props);
    this.state = { which: 'js', copied: false };
  }

  render() {
    const { app } = this.props;
    const code = app.generated();
    const { which, copied } = this.state;
    const text = code[which];
    const tabs = [
      ['js', 'interfaces/' + app.state.design.name + '.js'],
      ['dm', app.state.design.dm.file.split('/').pop()],
      ['route', 'routes.js entry'],
    ];
    return (
      <div className="panel panel--code">
        <div className="panel__tools">
          {tabs.map(([key, label]) => (
            <span
              key={key}
              className={'tab' + (which === key ? ' tab--on' : '')}
              onClick={() => this.setState({ which: key })}>
              {label}
            </span>
          ))}
          <span
            className="btn"
            onClick={() => {
              navigator.clipboard.writeText(text);
              this.setState({ copied: true });
              setTimeout(() => this.setState({ copied: false }), 1200);
            }}>
            <i className="fas fa-copy" /> {copied ? 'Copied' : 'Copy'}
          </span>
        </div>
        <pre className="code">{text}</pre>
      </div>
    );
  }
}

export const LogPanel = props => {
  const { app } = props;
  const { log, job } = app.state;
  return (
    <div className="panel panel--log">
      <div className="panel__tools">
        <span className="btn" onClick={() => app.clearLog()}>
          <i className="fas fa-eraser" /> Clear
        </span>
        {job && !job.done && (
          <span className="note">
            <i className="fas fa-spinner fa-spin" /> {job.label} running
          </span>
        )}
      </div>
      <div className="log">
        {log.map((entry, i) => (
          <div key={i} className={'log__line log__line--' + entry.kind}>
            <span className="log__time">{entry.time}</span>
            <span className="log__text">{entry.text}</span>
          </div>
        ))}
      </div>
    </div>
  );
};
