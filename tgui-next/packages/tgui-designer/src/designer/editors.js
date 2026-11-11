/**
 * The small editors the properties panel is built from.
 */

import { Component, createRef } from 'inferno';
import { freeNames, syntaxError, templateNames } from '../shared/expr';

/** A menu of names to insert: fields, repeat items and their keys. */
export class NamesMenu extends Component {
  constructor(props) {
    super(props);
    this.state = { open: false };
    this.close = () => this.setState({ open: false });
  }

  componentWillUnmount() {
    window.removeEventListener('mousedown', this.close);
  }

  render() {
    const { names, onPick, title } = this.props;
    const { open } = this.state;
    return (
      <span className="names">
        <span
          className="names__button"
          title={title || 'Insert a data field'}
          onMouseDown={e => {
            e.preventDefault();
            e.stopPropagation();
            const next = !open;
            this.setState({ open: next });
            if (next) {
              setTimeout(() => window.addEventListener('mousedown',
                this.close, { once: true }));
            }
          }}>
          {'{ }'}
        </span>
        {open && (
          <div className="names__menu">
            {names.length === 0 && (
              <div className="names__empty">
                No data fields yet. Add them in the Data tab.
              </div>
            )}
            {names.map(n => (
              <div
                key={n.name}
                className="names__item"
                onMouseDown={e => {
                  e.preventDefault();
                  e.stopPropagation();
                  this.setState({ open: false });
                  onPick(n.name);
                }}>
                <span className="names__name">{n.name}</span>
                <span className="names__hint">{n.hint}</span>
              </div>
            ))}
          </div>
        )}
      </span>
    );
  }
}

/** Inserts text at an input's caret and returns the new value. */
const insertAt = (input, value, text) => {
  if (!input) {
    return (value || '') + text;
  }
  const start = input.selectionStart === null
    ? (value || '').length : input.selectionStart;
  const end = input.selectionEnd === null ? start : input.selectionEnd;
  const v = value || '';
  return v.slice(0, start) + text + v.slice(end);
};

/**
 * A text box that may hold {field} parts. `multiline` makes it grow.
 * `focusKey` changing focuses it and selects its text.
 */
export class TextInput extends Component {
  constructor(props) {
    super(props);
    this.inputRef = createRef();
  }

  componentDidMount() {
    this.maybeFocus();
  }

  componentDidUpdate() {
    this.maybeFocus();
  }

  maybeFocus() {
    const { focusKey } = this.props;
    if (focusKey && focusKey !== this.focused && this.inputRef.current) {
      this.focused = focusKey;
      this.inputRef.current.focus();
      this.inputRef.current.select();
    }
  }

  render() {
    const { value, onChange, names, multiline, placeholder, template,
      known, onAddField } = this.props;
    const unknown = template && known
      ? templateNames(value).filter(n => !known.includes(n)) : [];
    const v = value === undefined || value === null ? '' : value;
    return (
      <div className="tin">
        <div className="tin__row">
          {multiline ? (
            <textarea
              ref={this.inputRef}
              className="tin__input tin__input--multi"
              value={v}
              placeholder={placeholder}
              rows={2}
              spellCheck={false}
              onInput={e => onChange(e.target.value)} />
          ) : (
            <input
              ref={this.inputRef}
              className="tin__input"
              value={v}
              placeholder={placeholder}
              spellCheck={false}
              onInput={e => onChange(e.target.value)} />
          )}
          {names && (
            <NamesMenu
              names={names}
              onPick={name => onChange(insertAt(this.inputRef.current,
                value, '{' + name + '}'))} />
          )}
        </div>
        <Unknown
          names={unknown}
          onAddField={onAddField && (n => onAddField(n, true))} />
      </div>
    );
  }
}

const Unknown = props => {
  const { names, onAddField } = props;
  if (!names || !names.length) {
    return null;
  }
  return (
    <div className="unknown">
      <i className="fas fa-exclamation-triangle" />
      {' Not a field: '}
      {names.map(n => (
        <span key={n} className="unknown__name">
          {n}
          {onAddField && (
            <span
              className="unknown__add"
              title={'Add a data field called ' + n}
              onClick={() => onAddField(n)}>
              + add
            </span>
          )}
        </span>
      ))}
    </div>
  );
};

/** A JS expression over the data, checked as you type. */
export class ExprInput extends Component {
  constructor(props) {
    super(props);
    this.inputRef = createRef();
  }

  render() {
    const { value, onChange, names, known, placeholder, onAddField,
      extraKnown } = this.props;
    const v = value === undefined || value === null ? '' : String(value);
    const error = syntaxError(v);
    const allKnown = [...(known || []), ...(extraKnown || [])];
    const unknown = !error && known
      ? freeNames(v).filter(n => !allKnown.includes(n)) : [];
    return (
      <div className="tin">
        <div className="tin__row">
          <input
            ref={this.inputRef}
            className={'tin__input tin__input--code'
              + (error ? ' tin__input--error' : '')}
            value={v}
            placeholder={placeholder || 'expression'}
            spellCheck={false}
            title={error || ''}
            onInput={e => onChange(e.target.value)} />
          {names && (
            <NamesMenu
              names={names}
              onPick={name => onChange(insertAt(this.inputRef.current, v,
                name))} />
          )}
        </div>
        {error && <div className="tin__error">{error}</div>}
        <Unknown names={unknown} onAddField={onAddField} />
      </div>
    );
  }
}

/** A labelled row in the properties panel. */
export const Row = props => {
  const { label, children, bound, onBind, title } = props;
  return (
    <div className="prow" title={title}>
      <div className="prow__label">{label}</div>
      <div className="prow__edit">{children}</div>
      {onBind && (
        <span
          className={'prow__bind' + (bound ? ' prow__bind--on' : '')}
          title={bound
            ? 'Bound to an expression. Click for a fixed value.'
            : 'Use an expression over the data instead'}
          onClick={onBind}>
          ƒ
        </span>
      )}
    </div>
  );
};

/** A plain <select>; '' stands for "not set". */
export const Select = props => {
  const { value, options, onChange, empty } = props;
  const v = value === undefined || value === null ? '' : String(value);
  return (
    <select
      className="sel"
      value={v}
      onChange={e => onChange(e.target.value)}>
      {empty !== false && <option value="">{empty || '(default)'}</option>}
      {options.map(o => {
        const val = typeof o === 'object' ? o.value : o;
        const label = typeof o === 'object' ? o.label : o;
        return <option key={String(val)} value={String(val)}>{label}</option>;
      })}
    </select>
  );
};

/** A number box where empty means "not set". */
export const NumberBox = props => {
  const { value, onChange, placeholder } = props;
  return (
    <input
      className="tin__input tin__input--num"
      value={value === undefined || value === null ? '' : value}
      placeholder={placeholder}
      onInput={e => {
        const s = e.target.value.trim();
        if (s === '') {
          onChange(undefined);
          return;
        }
        // Keep "1." or "-" as typed until it reads as a number
        const n = Number(s);
        onChange(Number.isFinite(n) && String(n) === s ? n : s);
      }} />
  );
};
