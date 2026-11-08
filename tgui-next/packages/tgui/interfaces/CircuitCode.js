import { decodeHtmlEntities } from 'common/string';
import { Component, Fragment } from 'inferno';
import { Box, Button, Icon } from '../components';

// hippie -- a circuit's save code from the analyzer or a ghost's scan (the
// user's ask, 2026-11-07: "syntaxed and stuff"). The code laid out and
// coloured on the left (it's JSON: keys, text, numbers, the I/O/A pin
// letters of the wires), and what it builds in words on the right: the
// parts in order, the values typed into them that a copy keeps, the wires.
// Copy puts the one-line code on the clipboard, as the printer's Program
// box wants it. DM side: circuit_show_code() in
// hippiestation/code/modules/integrated_electronics/core/circuits_tgui.dm.

const plain = text => decodeHtmlEntities(String(
  text === null || text === undefined ? '' : text));

const PIN_LETTERS = { I: 'input', O: 'output', A: 'pulse' };

const isScalar = value => value === null || typeof value !== 'object';

// JSON as coloured tokens, one array per line. Short lists of plain values
// (a wire end [2, "O", 1], a typed value [1, 0, 5]) stay on one line.
const layoutJson = (value, indent, key, last, lines) => {
  const pad = '  '.repeat(indent);
  const head = [];
  if (key !== null) {
    head.push(['key', JSON.stringify(key)]);
    head.push(['punc', ': ']);
  }
  const comma = last ? [] : [['punc', ',']];
  const scalarToken = v => {
    if (v === null) {
      return ['null', 'null'];
    }
    if (typeof v === 'number' || typeof v === 'boolean') {
      return ['num', String(v)];
    }
    if (typeof v === 'string' && PIN_LETTERS[v]) {
      return ['pin', JSON.stringify(v)];
    }
    return ['str', JSON.stringify(v)];
  };
  if (isScalar(value)) {
    lines.push([['pad', pad]].concat(head, [scalarToken(value)], comma));
    return;
  }
  const isArray = Array.isArray(value);
  const open = isArray ? '[' : '{';
  const close = isArray ? ']' : '}';
  const entries = isArray
    ? value.map(v => [null, v])
    : Object.keys(value).map(k => [k, value[k]]);
  if (entries.length === 0) {
    lines.push([['pad', pad]].concat(head, [['punc', open + close]], comma));
    return;
  }
  if (isArray && entries.length <= 4 && value.every(isScalar)) {
    const inline = [];
    value.forEach((v, i) => {
      if (i) {
        inline.push(['punc', ', ']);
      }
      inline.push(scalarToken(v));
    });
    lines.push([['pad', pad]].concat(head, [['punc', open]], inline,
      [['punc', close]], comma));
    return;
  }
  lines.push([['pad', pad]].concat(head, [['punc', open]]));
  entries.forEach(([k, v], i) => {
    layoutJson(v, indent + 1, k, i === entries.length - 1, lines);
  });
  lines.push([['pad', pad], ['punc', close]].concat(comma));
};

const codeLines = code => {
  let parsed;
  try {
    parsed = JSON.parse(code);
  }
  catch (e) {
    return null;
  }
  const lines = [];
  layoutJson(parsed, 0, null, true, lines);
  return lines;
};

export class CircuitCode extends Component {
  selectRaw() {
    if (this.raw) {
      this.raw.focus();
      this.raw.select();
    }
  }

  copy() {
    this.selectRaw();
    document.execCommand('copy');
    this.setState({ copied: true });
  }

  render() {
    const { data } = this.props.state;
    const code = String(data.code || '');
    const outline = data.outline;
    const lines = codeLines(code);
    const copied = this.state && this.state.copied;
    return (
      <Fragment>
        <div className="CircuitCode__bar">
          <Button
            icon={copied ? 'check' : 'copy'}
            content={copied ? 'Copied' : 'Copy'}
            color={copied ? 'good' : null}
            onClick={() => this.copy()} />
          <Box inline color="label" ml={1}>
            {code.length} characters
          </Box>
        </div>
        <div className={'CircuitCode__pane'
          + (outline ? '' : ' CircuitCode__pane--wide')}>
          {lines ? (
            <div className="CircuitCode__lines">
              {lines.map((tokens, i) => (
                <div key={i} className="CircuitCode__line">
                  <span className="CircuitCode__gutter">{i + 1}</span>
                  {tokens.map(([kind, text], j) => (
                    <span key={j} className={'CircuitCode__' + kind}>
                      {text}
                    </span>
                  ))}
                </div>
              ))}
            </div>
          ) : (
            <div className="CircuitCode__lines">{code}</div>
          )}
        </div>
        {!!outline && (
          <div className="CircuitCode__outline">
            <Box bold>{plain(outline.name)}</Box>
            {outline.name !== outline.type && (
              <Box color="label">{plain(outline.type)}</Box>
            )}
            <Box bold mt={1} mb={0.5}>
              Parts ({outline.parts.length})
            </Box>
            {outline.parts.map(part => (
              <Box key={part.n} mb={0.5}>
                <div className="CircuitCode__part">
                  <Box inline color="label" style={{ width: '18px' }}>
                    {part.n}
                  </Box>
                  <div className="CircuitGraph__nodeIcon">
                    <span className={'circuits32x32 ' + part.icon} />
                  </div>
                  <span>{plain(part.name)}</span>
                  {part.name !== part.type && (
                    <Box inline color="label" ml={0.5}>
                      ({plain(part.type)})
                    </Box>
                  )}
                </div>
                {part.values.map(v => (
                  <div key={v.pin} className="CircuitCode__value">
                    {plain(v.pin) + ' = '}
                    <span className="CircuitCode__str">
                      {plain(v.value)}
                    </span>
                  </div>
                ))}
              </Box>
            ))}
            <Box bold mt={1} mb={0.5}>
              Wires ({outline.wires.length})
            </Box>
            {outline.wires.length === 0 && (
              <Box color="label">None.</Box>
            )}
            {outline.wires.map((wire, i) => (
              <div key={i} className="CircuitCode__wire">
                <Icon
                  name={wire.pulse ? 'bolt' : 'circle'}
                  color={wire.pulse ? 'orange' : 'blue'}
                  size={0.8} />
                {' '}{plain(wire.from)}
                {' '}<Icon name="long-arrow-alt-right" color="label" />{' '}
                {plain(wire.to)}
              </div>
            ))}
          </div>
        )}
        <textarea
          ref={el => {
            this.raw = el;
          }}
          className="CircuitCode__raw"
          readOnly
          value={code} />
      </Fragment>
    );
  }
}
