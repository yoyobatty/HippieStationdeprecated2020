import { decodeHtmlEntities } from 'common/string';
import { Component, Fragment } from 'inferno';
import { act } from '../byond';
import { Box, Button, Icon, ProgressBar } from '../components';
import { UI_INTERACTIVE } from '../constants';

// hippie -- an electronic assembly as a node graph (the user's ruling,
// 2026-11-07): every component a chip on a circuit board with its pins down
// the sides, wires drawn between them. Drag a chip by its top bar, drag the
// board to pan, wheel to zoom. The tool rules stay: a pin's dot wires (a
// multitool or wirer), a pin's value sets data (a multitool: typed in the
// side panel; a debugger: writes its memory), a wire cuts. DM side:
// hippiestation/code/modules/integrated_electronics/core/circuits_tgui.dm.
// A loose circuit (no assembly) opens the same window with one chip.

const NODE_W = 250;
const HEAD_H = 26;
const ROW_H = 20;
const PULSE_GAP = 5; // the pulse rows' margin and dashed line
const FOOT = 6;
const COL_GAP = 90;
const ROW_GAP = 24;

const plain = text => decodeHtmlEntities(String(
  text === null || text === undefined ? '' : text));

const allPins = node => node.inputs
  .concat(node.outputs, node.pulse_in, node.pulse_out);

const dataRows = node => Math.max(node.inputs.length, node.outputs.length);
const pulseRows = node => Math.max(node.pulse_in.length,
  node.pulse_out.length);
const nodeHeight = node => HEAD_H + dataRows(node) * ROW_H
  + (pulseRows(node) ? PULSE_GAP + pulseRows(node) * ROW_H : 0) + FOOT;

// Where every pin's dot sits on the board, from where its chip sits
const buildPinMap = (nodes, posOf) => {
  const map = {};
  for (const node of nodes) {
    const pos = posOf(node);
    const add = (pins, side, base, io) => pins.forEach((pin, i) => {
      map[pin.ref] = {
        pin,
        node,
        side,
        io,
        x: side < 0 ? pos.x : pos.x + NODE_W,
        y: pos.y + 1 + base + i * ROW_H + ROW_H / 2,
      };
    });
    add(node.inputs, -1, HEAD_H, 'data');
    add(node.outputs, 1, HEAD_H, 'data');
    const pulseBase = HEAD_H + dataRows(node) * ROW_H + PULSE_GAP;
    add(node.pulse_in, -1, pulseBase, 'pulse');
    add(node.pulse_out, 1, pulseBase, 'pulse');
  }
  return map;
};

const wirePath = (a, b) => {
  const dx = Math.max(40, Math.abs(b.x - a.x) / 2);
  return 'M ' + a.x + ' ' + a.y
    + ' C ' + (a.x + a.side * dx) + ' ' + a.y
    + ', ' + (b.x + b.side * dx) + ' ' + b.y
    + ', ' + b.x + ' ' + b.y;
};

// Chips in columns by how far down the wires they are: parts nothing feeds
// on the left, what they feed to the right of them. Only `refs` are placed,
// starting at `startY`.
const autoLayout = (nodes, refs, startY) => {
  const owner = {};
  nodes.forEach(node => allPins(node).forEach(pin => {
    owner[pin.ref] = node.ref;
  }));
  const next = {};
  const layer = {};
  nodes.forEach(node => {
    next[node.ref] = [];
    layer[node.ref] = 0;
    node.outputs.concat(node.pulse_out).forEach(pin => pin.links
      .forEach(link => {
        const other = owner[link];
        if (other && other !== node.ref) {
          next[node.ref].push(other);
        }
      }));
  });
  for (let pass = 0; pass < nodes.length; pass++) {
    let changed = false;
    nodes.forEach(node => next[node.ref].forEach(other => {
      const want = layer[node.ref] + 1;
      if (layer[other] < want && want < nodes.length) {
        layer[other] = want;
        changed = true;
      }
    }));
    if (!changed) {
      break;
    }
  }
  const columnY = {};
  const positions = {};
  nodes.forEach(node => {
    if (!refs[node.ref]) {
      return;
    }
    const column = layer[node.ref];
    const y = columnY[column] === undefined ? startY : columnY[column];
    positions[node.ref] = { x: 20 + column * (NODE_W + COL_GAP), y };
    columnY[column] = y + nodeHeight(node) + ROW_GAP;
  });
  return positions;
};

const layoutString = positions => Object.keys(positions)
  .map(ref => ref + ',' + positions[ref].x + ',' + positions[ref].y)
  .join(';');

const DIRS = [
  ['NW', 9], ['N', 1], ['NE', 5],
  ['W', 8], null, ['E', 4],
  ['SW', 10], ['S', 2], ['SE', 6],
];

// What the tool in hand does, in a line
const toolHint = (tool, pinMap) => {
  const held = tool.selected && pinMap[tool.selected];
  const heldName = held
    ? plain(held.node.name) + ': ' + plain(held.pin.name)
    : null;
  switch (tool.kind) {
    case 'multitool':
      return held
        ? 'Multitool on ' + heldName + '. Click a pin to connect.'
        : 'Multitool: dot wires, value sets, wire cuts.';
    case 'wirer':
      if (tool.mode === 'wiring' || tool.mode === 'unwiring') {
        return 'Wirer on ' + (heldName || 'a pin')
          + '. Click a pin to ' + (tool.mode === 'wiring'
          ? 'connect.'
          : 'disconnect.');
      }
      return tool.mode === 'unwire'
        ? 'Wirer (unwire): click a wire to cut.'
        : 'Wirer (wire): click a dot, then another.';
    case 'debugger':
      if (tool.mode === 'copy') {
        return 'Debugger (copy): click a value to copy it.';
      }
      if (tool.mode === 'ref') {
        return 'Debugger (ref scanner): Copy Ref on a part.';
      }
      return 'Debugger: click a value to write ' + plain(tool.data) + '.';
    default:
      return 'No tool: look only.';
  }
};

class PinEditor extends Component {
  constructor() {
    super();
    this.state = {
      draft: '',
      anyType: 'string',
      listType: 'string',
      editIndex: null,
    };
  }

  send(action, params) {
    const { config, nodeRef, pin } = this.props;
    act(config.ref, action, Object.assign({
      ref: nodeRef,
      pin: pin.ref,
    }, params));
  }

  draftField(multiline) {
    const { draft } = this.state;
    const onInput = e => this.setState({ draft: e.target.value });
    const onKeyDown = e => {
      if (e.keyCode === 13 && !e.shiftKey) {
        e.preventDefault();
        this.submit();
      }
    };
    if (multiline) {
      return (
        <textarea
          className="CircuitGraph__field"
          rows={3}
          value={draft}
          onInput={onInput}
          onKeyDown={onKeyDown} />
      );
    }
    return (
      <input
        className="CircuitGraph__field"
        value={draft}
        onInput={onInput}
        onKeyDown={onKeyDown} />
    );
  }

  submit() {
    const { pin } = this.props;
    const { draft, anyType, listType, editIndex } = this.state;
    if (pin.kind === 'list') {
      if (editIndex) {
        this.send('list_edit', { pos: editIndex, type: listType,
          value: draft });
      } else {
        this.send('list_add', { type: listType, value: draft });
      }
      this.setState({ draft: '', editIndex: null });
      return;
    }
    const type = pin.kind === 'any' ? anyType : pin.kind;
    this.send('set', { type, value: draft });
  }

  typePicker(stateKey, withNull) {
    const types = withNull
      ? [['string', 'Text'], ['number', 'Num'], ['null', 'Null']]
      : [['string', 'Text'], ['number', 'Num']];
    return types.map(([type, label]) => (
      <Button
        key={type}
        content={label}
        selected={this.state[stateKey] === type}
        onClick={() => this.setState({ [stateKey]: type })} />
    ));
  }

  render() {
    const { pin, tool } = this.props;
    if (tool.kind === 'debugger') {
      return (
        <Button
          icon={tool.mode === 'copy' ? 'copy' : 'pen'}
          content={tool.mode === 'copy'
            ? 'Copy value'
            : 'Write ' + plain(tool.data)}
          disabled={tool.mode === 'ref' || tool.mode === 'id'}
          onClick={() => this.send('data')} />
      );
    }
    if (tool.kind !== 'multitool') {
      return (
        <Box color="label" fontSize="11px">
          {pin.kind === 'pulse' || tool.kind === 'wirer'
            ? 'Needs a multitool.'
            : 'Needs a multitool or debugger.'}
        </Box>
      );
    }
    switch (pin.kind) {
      case 'pulse':
        return (
          <Button icon="bolt" content="Pulse"
            onClick={() => this.send('data')} />
        );
      case 'bool':
        return (
          <Button icon="exchange-alt" content="Toggle"
            onClick={() => this.send('data')} />
        );
      case 'ref':
        return (
          <Button icon="eraser" content="Clear"
            onClick={() => this.send('data')} />
        );
      case 'self':
        return null;
      case 'dir':
        return (
          <Box style={{ width: '96px' }}>
            {DIRS.map((dir, i) => dir ? (
              <Button
                key={dir[0]}
                style={{ width: '30px', 'text-align': 'center' }}
                content={dir[0]}
                onClick={() => this.send('set', {
                  type: 'number', value: dir[1] })} />
            ) : (
              <Box key={i} inline style={{ width: '30px' }} />
            ))}
          </Box>
        );
      case 'color':
        return (
          <Fragment>
            <input
              type="color"
              value={pin.color || '#FFFFFF'}
              onChange={e => this.send('set', {
                type: 'color', value: e.target.value })} />
            {this.draftField(false)}
            <Button content="Set" onClick={() => this.submit()} />
            <Button content="Null"
              onClick={() => this.send('set', { type: 'null' })} />
          </Fragment>
        );
      case 'list': {
        const items = pin.items || [];
        const { editIndex } = this.state;
        return (
          <Fragment>
            {items.length === 0 && (
              <Box color="label">Empty.</Box>
            )}
            {items.map((item, i) => (
              <div key={i} className="CircuitGraph__listItem">
                <Box inline color="label" style={{ width: '24px' }}>
                  {i + 1}
                </Box>
                <Box
                  inline
                  color={editIndex === i + 1 ? 'good' : null}
                  style={{
                    flex: '1 1 auto',
                    overflow: 'hidden',
                    'text-overflow': 'ellipsis',
                  }}>
                  {plain(item)}
                </Box>
                <Button icon="arrow-up" disabled={i === 0}
                  onClick={() => this.send('list_swap', {
                    pos: i + 1, other: i })} />
                <Button icon="pen"
                  selected={editIndex === i + 1}
                  onClick={() => this.setState({
                    editIndex: editIndex === i + 1 ? null : i + 1,
                  })} />
                <Button icon="times" color="bad"
                  onClick={() => this.send('list_remove', { pos: i + 1 })} />
              </div>
            ))}
            <Box mt={0.5}>
              {this.typePicker('listType', false)}
              <Button icon="trash" content="Clear" color="bad"
                disabled={!items.length}
                onClick={() => this.send('list_clear')} />
            </Box>
            {this.draftField(false)}
            <Button
              icon={editIndex ? 'pen' : 'plus'}
              content={editIndex ? 'Set #' + editIndex : 'Add'}
              onClick={() => this.submit()} />
          </Fragment>
        );
      }
      case 'any':
        return (
          <Fragment>
            {this.typePicker('anyType', true)}
            {this.state.anyType !== 'null' && this.draftField(
              this.state.anyType === 'string')}
            <Button content="Set" onClick={() => this.submit()} />
          </Fragment>
        );
      default:
        return (
          <Fragment>
            {this.draftField(pin.kind === 'string')}
            <Button content="Set" onClick={() => this.submit()} />
            {(pin.kind === 'string' || pin.kind === 'char') && (
              <Button content="Null"
                onClick={() => this.send('set', { type: 'null' })} />
            )}
          </Fragment>
        );
    }
  }
}

export class CircuitAssembly extends Component {
  constructor() {
    super();
    this.state = {
      pan: { x: 20, y: 20 },
      zoom: 1,
      selected: null,
      editPin: null,
      local: {},
      mouse: null,
      renaming: null,
      nameDraft: '',
      panning: false,
    };
    this.drag = null;
    this.panStart = null;
    this.sentLayout = {};
    this.focusTime = null;
    this.fitted = false;
    this.bounds = null;
    this.onMove = this.onMove.bind(this);
    this.onUp = this.onUp.bind(this);
    this.onWheel = this.onWheel.bind(this);
  }

  componentDidMount() {
    document.addEventListener('mousemove', this.onMove);
    document.addEventListener('mouseup', this.onUp);
    if (this.board) {
      this.board.addEventListener('wheel', this.onWheel, { passive: false });
    }
    this.afterData();
  }

  componentWillUnmount() {
    document.removeEventListener('mousemove', this.onMove);
    document.removeEventListener('mouseup', this.onUp);
    if (this.board) {
      this.board.removeEventListener('wheel', this.onWheel);
    }
  }

  componentDidUpdate() {
    this.afterData();
  }

  canAct() {
    return this.props.state.config.status === UI_INTERACTIVE;
  }

  // Once per data: pick the part DM asked for, drop local positions the
  // server has caught up with, and store a layout for unplaced chips.
  afterData() {
    const { config, data } = this.props.state;
    const nodes = data.components || [];
    if (data.focus && data.focus_time !== this.focusTime) {
      this.focusTime = data.focus_time;
      this.setState({ selected: data.focus, editPin: null });
    }
    const local = this.state.local;
    const stale = Object.keys(local).filter(ref => {
      const node = nodes.find(n => n.ref === ref);
      return !node
        || (node.x === local[ref].x && node.y === local[ref].y);
    });
    if (stale.length && !this.drag) {
      const kept = Object.assign({}, local);
      stale.forEach(ref => delete kept[ref]);
      this.setState({ local: kept });
    }
    if (!this.fitted && nodes.length && this.bounds && this.board) {
      this.fitted = true;
      this.fit();
    }
    if (data.loose || !this.canAct()) {
      return;
    }
    const unplaced = this.unplaced(nodes);
    const toSend = {};
    let any = false;
    Object.keys(unplaced).forEach(ref => {
      if (!this.sentLayout[ref]) {
        this.sentLayout[ref] = true;
        toSend[ref] = unplaced[ref];
        any = true;
      }
    });
    if (any) {
      act(config.ref, 'arrange', { layout: layoutString(toSend) });
    }
  }

  // Positions for chips the server has none for, under the placed ones
  unplaced(nodes) {
    const refs = {};
    let bottom = -1;
    let missing = false;
    nodes.forEach(node => {
      if (this.state.local[node.ref]) {
        return;
      }
      if (node.x === null || node.x === undefined) {
        refs[node.ref] = true;
        missing = true;
      } else {
        bottom = Math.max(bottom, node.y + nodeHeight(node));
      }
    });
    if (!missing) {
      return {};
    }
    return autoLayout(nodes, refs, bottom < 0 ? 20 : bottom + 40);
  }

  // Zoom and pan so every chip shows (never above 100%)
  fit() {
    const b = this.bounds;
    if (!b || !this.board) {
      return;
    }
    const rect = this.board.getBoundingClientRect();
    const w = b.maxX - b.minX + 40;
    const h = b.maxY - b.minY + 70;
    const zoom = Math.max(0.3, Math.min(1, rect.width / w, rect.height / h));
    this.setState({
      zoom,
      pan: {
        x: 20 - b.minX * zoom,
        y: 20 - b.minY * zoom,
      },
    });
  }

  graphPoint(e) {
    const rect = this.board.getBoundingClientRect();
    const { pan, zoom } = this.state;
    return {
      x: (e.clientX - rect.left - pan.x) / zoom,
      y: (e.clientY - rect.top - pan.y) / zoom,
    };
  }

  onWheel(e) {
    e.preventDefault();
    const rect = this.board.getBoundingClientRect();
    const { pan, zoom } = this.state;
    const factor = e.deltaY < 0 ? 1.1 : 1 / 1.1;
    const next = Math.min(2, Math.max(0.3, zoom * factor));
    const mx = e.clientX - rect.left;
    const my = e.clientY - rect.top;
    this.setState({
      zoom: next,
      pan: {
        x: mx - (mx - pan.x) * next / zoom,
        y: my - (my - pan.y) * next / zoom,
      },
    });
  }

  onBoardDown(e) {
    if (e.button !== 0) {
      return;
    }
    this.panStart = {
      sx: e.clientX,
      sy: e.clientY,
      px: this.state.pan.x,
      py: this.state.pan.y,
    };
    this.setState({ panning: true });
  }

  onNodeDown(e, node, pos) {
    if (e.button !== 0) {
      return;
    }
    e.stopPropagation();
    if (this.state.selected !== node.ref) {
      this.setState({ selected: node.ref, editPin: null });
    }
    if (!this.canAct()) {
      return;
    }
    this.drag = {
      ref: node.ref,
      sx: e.clientX,
      sy: e.clientY,
      ox: pos.x,
      oy: pos.y,
      moved: false,
    };
  }

  onMove(e) {
    if (this.drag) {
      const { zoom } = this.state;
      const d = this.drag;
      const dx = (e.clientX - d.sx) / zoom;
      const dy = (e.clientY - d.sy) / zoom;
      if (!d.moved && Math.abs(dx) + Math.abs(dy) < 3) {
        return;
      }
      d.moved = true;
      this.setState(prev => ({
        local: Object.assign({}, prev.local, {
          [d.ref]: {
            x: Math.max(0, Math.round(d.ox + dx)),
            y: Math.max(0, Math.round(d.oy + dy)),
          },
        }),
      }));
      return;
    }
    if (this.panStart) {
      const p = this.panStart;
      this.setState({
        pan: { x: p.px + e.clientX - p.sx, y: p.py + e.clientY - p.sy },
      });
      return;
    }
    const { data } = this.props.state;
    if (this.board && data.tool && data.tool.selected) {
      this.setState({ mouse: this.graphPoint(e) });
    }
  }

  onUp() {
    if (this.drag) {
      const d = this.drag;
      this.drag = null;
      const pos = this.state.local[d.ref];
      if (d.moved && pos) {
        act(this.props.state.config.ref, 'move', {
          ref: d.ref, x: pos.x, y: pos.y });
      }
    }
    if (this.panStart) {
      this.panStart = null;
      this.setState({ panning: false });
    }
  }

  arrangeAll(nodes) {
    const refs = {};
    nodes.forEach(node => {
      refs[node.ref] = true;
    });
    const positions = autoLayout(nodes, refs, 20);
    this.setState({ local: positions });
    this.fitted = false; // fit again once the new layout renders
    act(this.props.state.config.ref, 'arrange', {
      layout: layoutString(positions) });
  }

  renderPinSide(node, pin, side, io, tool) {
    const { config } = this.props.state;
    const wired = pin.links.length > 0;
    const held = tool.selected === pin.ref;
    const isNull = pin.value === 'null';
    const dot = (
      <span
        className={[
          'CircuitGraph__dot',
          'CircuitGraph__dot--' + (side < 0 ? 'left' : 'right'),
          io === 'pulse' && 'CircuitGraph__dot--pulse',
          wired && 'CircuitGraph__dot--wired',
          held && 'CircuitGraph__dot--held',
        ].filter(Boolean).join(' ')}
        title={plain(pin.name) + ' ' + plain(pin.type)}
        onMouseDown={e => e.stopPropagation()}
        onClick={() => act(config.ref, 'wire', {
          ref: node.ref, pin: pin.ref })} />
    );
    const name = (
      <span className="CircuitGraph__pinName" title={plain(pin.type)}>
        {plain(pin.name)}
      </span>
    );
    const value = io === 'data' && (
      <span
        className={'CircuitGraph__pinValue'
          + (isNull ? ' CircuitGraph__pinValue--null' : '')}
        title={plain(pin.value)}
        onMouseDown={e => e.stopPropagation()}
        onClick={() => this.onValueClick(node, pin)}>
        {pin.color && (
          <span className="CircuitGraph__swatch"
            style={{ 'background-color': pin.color }} />
        )}
        {plain(pin.value)}
      </span>
    );
    const pulse = io === 'pulse' && (
      <span
        className="CircuitGraph__pinValue"
        onMouseDown={e => e.stopPropagation()}
        onClick={() => this.onValueClick(node, pin)}>
        <Icon name="bolt" />
      </span>
    );
    return (
      <div className={'CircuitGraph__half'
        + (side > 0 ? ' CircuitGraph__half--right' : '')}>
        {dot}
        {side < 0 ? (
          <Fragment>{name}{value}{pulse}</Fragment>
        ) : (
          <Fragment>{pulse}{value}{name}</Fragment>
        )}
      </div>
    );
  }

  onValueClick(node, pin) {
    const { config, data } = this.props.state;
    const tool = data.tool || {};
    this.setState({ selected: node.ref, editPin: pin.ref });
    if (tool.kind === 'debugger'
      || (tool.kind === 'multitool'
        && ['bool', 'ref', 'self', 'pulse'].indexOf(pin.kind) >= 0)) {
      act(config.ref, 'data', { ref: node.ref, pin: pin.ref });
    }
  }

  renderNode(node, pos, tool) {
    const { selected } = this.state;
    const rows = [];
    for (let i = 0; i < dataRows(node); i++) {
      rows.push(
        <div key={'d' + i} className="CircuitGraph__row">
          {node.inputs[i]
            ? this.renderPinSide(node, node.inputs[i], -1, 'data', tool)
            : <div className="CircuitGraph__half" />}
          {node.outputs[i]
            ? this.renderPinSide(node, node.outputs[i], 1, 'data', tool)
            : <div className="CircuitGraph__half" />}
        </div>,
      );
    }
    const pulses = [];
    for (let i = 0; i < pulseRows(node); i++) {
      pulses.push(
        <div key={'p' + i} className="CircuitGraph__row">
          {node.pulse_in[i]
            ? this.renderPinSide(node, node.pulse_in[i], -1, 'pulse', tool)
            : <div className="CircuitGraph__half" />}
          {node.pulse_out[i]
            ? this.renderPinSide(node, node.pulse_out[i], 1, 'pulse', tool)
            : <div className="CircuitGraph__half" />}
        </div>,
      );
    }
    return (
      <div
        key={node.ref}
        className={'CircuitGraph__node'
          + (selected === node.ref ? ' CircuitGraph__node--selected' : '')}
        style={{
          left: pos.x + 'px',
          top: pos.y + 'px',
          width: NODE_W + 'px',
          height: nodeHeight(node) + 'px',
        }}
        onMouseDown={e => e.stopPropagation()}>
        <div
          className={'CircuitGraph__nodeHead'
            + (node.removable ? '' : ' CircuitGraph__nodeHead--builtin')}
          title={plain(node.type)}
          onMouseDown={e => this.onNodeDown(e, node, pos)}>
          <div className="CircuitGraph__nodeIcon">
            <span className={'circuits32x32 ' + node.icon} />
          </div>
          <div className="CircuitGraph__nodeName">{plain(node.name)}</div>
          {!node.removable && (
            <Icon name="lock" color="label" title="Built in" />
          )}
        </div>
        {rows}
        {pulses.length > 0 && (
          <div className="CircuitGraph__pulseRows">{pulses}</div>
        )}
      </div>
    );
  }

  renderSide(nodes, pinMap, tool) {
    const { config, data } = this.props.state;
    const { selected, editPin, renaming, nameDraft } = this.state;
    const node = nodes.find(n => n.ref === selected) || nodes[0];
    const canAct = this.canAct();
    const send = (action, params) => act(config.ref, action, params);
    const startRename = (what, current) => this.setState({
      renaming: what, nameDraft: plain(current) });
    const renameField = onDone => (
      <input
        className="CircuitGraph__field"
        value={nameDraft}
        ref={el => el && el !== document.activeElement && renaming
          && el.focus()}
        onInput={e => this.setState({ nameDraft: e.target.value })}
        onKeyDown={e => {
          if (e.keyCode === 13) {
            onDone(nameDraft);
            this.setState({ renaming: null });
          }
          if (e.keyCode === 27) {
            this.setState({ renaming: null });
          }
        }} />
    );
    return (
      <Fragment>
        {!data.loose && (
          <div className="CircuitGraph__parts">
            <Box bold mb={0.5}>Parts ({nodes.length})</Box>
            {nodes.map((n, i) => (
              <div
                key={n.ref}
                className={'CircuitGraph__partRow'
                  + (node && n.ref === node.ref
                    ? ' CircuitGraph__partRow--selected'
                    : '')}
                onClick={() => this.setState({
                  selected: n.ref, editPin: null })}>
                <Box inline color="label" style={{ width: '20px' }}>
                  {i + 1}
                </Box>
                <Box inline style={{
                  flex: '1 1 auto',
                  overflow: 'hidden',
                  'text-overflow': 'ellipsis',
                }}>
                  {plain(n.name)}
                </Box>
                {!n.removable && <Icon name="lock" color="label" />}
                {!!n.removable && canAct && (
                  <Fragment>
                    <Button icon="arrow-up"
                      onClick={e => {
                        e.stopPropagation();
                        send('order', { ref: n.ref, dir: 'up' });
                      }} />
                    <Button icon="arrow-down"
                      onClick={e => {
                        e.stopPropagation();
                        send('order', { ref: n.ref, dir: 'down' });
                      }} />
                  </Fragment>
                )}
              </div>
            ))}
          </div>
        )}
        {!node && <Box color="label">No parts.</Box>}
        {!!node && (
          <Box>
            <Box style={{ display: 'flex', 'align-items': 'center' }}>
              <div className="CircuitGraph__nodeIcon">
                <span className={'circuits32x32 ' + node.icon} />
              </div>
              {renaming === node.ref
                ? renameField(name => send('rename_component', {
                  ref: node.ref, name }))
                : (
                  <Box bold style={{ flex: '1 1 auto' }}>
                    {plain(node.name)}
                  </Box>
                )}
            </Box>
            {node.name !== node.type && (
              <Box color="label">{plain(node.type)}</Box>
            )}
            {canAct && (
              <Box my={0.5}>
                {(node.removable || data.loose) && (
                  <Button icon="tag" content="Rename"
                    onClick={() => startRename(node.ref, node.name)} />
                )}
                {!!node.removable && !data.loose && (
                  <Button icon="hand-pointer" content="Interact"
                    onClick={() => send('interact', { ref: node.ref })} />
                )}
                <Button icon="crosshairs" content="Copy Ref"
                  onClick={() => send('scan', { ref: node.ref })} />
                {!!node.removable && !data.loose && (
                  <Button icon="eject" content="Remove" color="bad"
                    onClick={() => send('remove', { ref: node.ref })} />
                )}
              </Box>
            )}
            <Box color="label" fontSize="11px" my={0.5}>
              {plain(node.desc)}
            </Box>
            {!!node.ext && (
              <Box fontSize="11px" my={0.5}>{plain(node.ext)}</Box>
            )}
            <Box color="label" fontSize="11px">
              Complexity {node.complexity}
              {' · '}Cooldown {node.cooldown}s
              {!!node.ext_cooldown && ' · Ext ' + node.ext_cooldown + 's'}
              {!!node.power_idle && ' · ' + node.power_idle + ' W idle'}
              {!!node.power_use && ' · ' + node.power_use + ' W use'}
            </Box>
            <Box bold mt={1} mb={0.5}>Pins</Box>
            {allPins(node).map(pin => {
              const open = editPin === pin.ref;
              const pulse = pin.kind === 'pulse';
              return (
                <div key={pin.ref}
                  className={'CircuitGraph__pinEdit'
                    + (open ? ' CircuitGraph__pinEdit--open' : '')}>
                  <Box
                    style={{ cursor: 'pointer' }}
                    onClick={() => this.setState({
                      editPin: open ? null : pin.ref })}>
                    <Icon
                      name={pulse ? 'bolt' : 'circle'}
                      color={pulse ? 'orange' : 'blue'}
                      size={0.8} />
                    {' '}{plain(pin.name)}
                    <Box inline color="label" ml={0.5} fontSize="10px">
                      {plain(pin.type)}
                    </Box>
                    {!pulse && (
                      <Box color="good" fontSize="11px"
                        style={{
                          'font-family': 'monospace',
                          'word-break': 'break-all',
                        }}>
                        {plain(pin.value)}
                      </Box>
                    )}
                  </Box>
                  {pin.links.map(link => {
                    const other = pinMap[link];
                    if (!other) {
                      return null;
                    }
                    return (
                      <Box key={link} fontSize="11px" ml={1}>
                        <Icon name="long-arrow-alt-right" color="label" />
                        {' '}
                        <a onClick={() => this.setState({
                          selected: other.node.ref, editPin: link })}>
                          {plain(other.node.name)}: {plain(other.pin.name)}
                        </a>
                        {canAct && (tool.kind === 'multitool'
                          || tool.kind === 'wirer') && (
                          <Button icon="cut" color="transparent"
                            title="Cut"
                            onClick={() => send('unwire', {
                              ref: node.ref, pin: pin.ref, link })} />
                        )}
                      </Box>
                    );
                  })}
                  {open && canAct && (
                    <Box mt={0.5}>
                      <PinEditor
                        key={pin.ref}
                        config={config}
                        nodeRef={node.ref}
                        pin={pin}
                        tool={tool} />
                    </Box>
                  )}
                </div>
              );
            })}
          </Box>
        )}
      </Fragment>
    );
  }

  render() {
    const { config, data } = this.props.state;
    const { pan, zoom, local, mouse, panning, renaming, nameDraft }
      = this.state;
    const nodes = data.components || [];
    const tool = data.tool || { kind: 'none' };
    const loose = !!data.loose;
    const auto = this.unplaced(nodes);
    const posOf = node => local[node.ref]
      || (node.x === null || node.x === undefined
        ? auto[node.ref] || { x: 20, y: 20 }
        : { x: node.x, y: node.y });
    const pinMap = buildPinMap(nodes, posOf);
    this.bounds = null;
    nodes.forEach(node => {
      const p = posOf(node);
      const b = this.bounds || {
        minX: Infinity, minY: Infinity, maxX: -Infinity, maxY: -Infinity,
      };
      this.bounds = {
        minX: Math.min(b.minX, p.x),
        minY: Math.min(b.minY, p.y),
        maxX: Math.max(b.maxX, p.x + NODE_W),
        maxY: Math.max(b.maxY, p.y + nodeHeight(node)),
      };
    });
    const edges = [];
    const seen = {};
    Object.keys(pinMap).forEach(ref => pinMap[ref].pin.links
      .forEach(link => {
        if (!pinMap[link]) {
          return;
        }
        const key = ref < link ? ref + '|' + link : link + '|' + ref;
        if (seen[key]) {
          return;
        }
        seen[key] = true;
        edges.push({ a: pinMap[ref], b: pinMap[link] });
      }));
    const held = tool.selected && pinMap[tool.selected];
    const lit = this.state.selected;
    const cell = data.cell;
    return (
      <Fragment>
        {!loose && (
          <div className="CircuitGraph__top">
            {renaming === 'assembly' ? (
              <Box inline style={{ width: '180px' }} mr={1}>
                <input
                  className="CircuitGraph__field"
                  value={nameDraft}
                  onInput={e => this.setState({ nameDraft: e.target.value })}
                  onKeyDown={e => {
                    if (e.keyCode === 13) {
                      act(config.ref, 'rename', { name: nameDraft });
                      this.setState({ renaming: null });
                    }
                    if (e.keyCode === 27) {
                      this.setState({ renaming: null });
                    }
                  }} />
              </Box>
            ) : (
              <Box inline bold mr={0.5} style={{
                'max-width': '180px',
                overflow: 'hidden',
                'text-overflow': 'ellipsis',
              }}>
                {plain(data.name)}
              </Box>
            )}
            {this.canAct() && renaming !== 'assembly' && (
              <Button icon="tag" title="Rename"
                onClick={() => this.setState({
                  renaming: 'assembly', nameDraft: plain(data.name) })} />
            )}
            <Box inline ml={1} mr={0.5} color="label">Cell</Box>
            <div className="CircuitGraph__stat">
              {cell ? (
                <ProgressBar
                  value={cell.percent / 100}
                  ranges={{
                    good: [0.5, Infinity],
                    average: [0.15, 0.5],
                    bad: [-Infinity, 0.15],
                  }}
                  content={Math.round(cell.percent) + '%'} />
              ) : (
                <Box color="bad">None</Box>
              )}
            </div>
            {!!cell && this.canAct() && (
              <Button icon="eject" title="Remove cell"
                onClick={() => act(config.ref, 'remove_cell')} />
            )}
            <Box inline ml={1} mr={0.5} color="label">Space</Box>
            <div className="CircuitGraph__stat">
              <ProgressBar
                value={data.space / Math.max(1, data.max_space)}
                color={data.space > data.max_space ? 'bad' : 'teal'}
                content={data.space + '/' + data.max_space} />
            </div>
            <Box inline mr={0.5} color="label">Complexity</Box>
            <div className="CircuitGraph__stat">
              <ProgressBar
                value={data.complexity / Math.max(1, data.max_complexity)}
                color={data.complexity > data.max_complexity
                  ? 'bad'
                  : 'teal'}
                content={data.complexity + '/' + data.max_complexity} />
            </div>
            {!data.opened && (
              <Box inline color="average" ml={1}>
                <Icon name="lock" /> Shut
              </Box>
            )}
            <Box inline style={{ 'margin-left': 'auto' }}>
              {this.canAct() && nodes.length > 1 && (
                <Button icon="project-diagram" content="Arrange"
                  onClick={() => this.arrangeAll(nodes)} />
              )}
            </Box>
          </div>
        )}
        <div
          ref={el => {
            if (el && el !== this.board) {
              if (this.board) {
                this.board.removeEventListener('wheel', this.onWheel);
              }
              this.board = el;
              el.addEventListener('wheel', this.onWheel, { passive: false });
            }
          }}
          className={'CircuitGraph__board'
            + (loose ? ' CircuitGraph__board--loose' : '')
            + (panning ? ' CircuitGraph__board--panning' : '')}
          onMouseDown={e => this.onBoardDown(e)}>
          <div
            className={'CircuitGraph__hint'
              + (held ? ' CircuitGraph__hint--active' : '')}
            onMouseDown={e => e.stopPropagation()}>
            {toolHint(tool, pinMap)}
            {!!held && this.canAct() && (
              <Button ml={1} content="Cancel"
                onClick={() => act(config.ref, 'cancel_wire', {
                  ref: held.node.ref })} />
            )}
          </div>
          <div className="CircuitGraph__zoom"
            onMouseDown={e => e.stopPropagation()}>
            <Button icon="search-minus"
              onClick={() => this.setState({
                zoom: Math.max(0.3, zoom / 1.2) })} />
            <Button content={Math.round(zoom * 100) + '%'}
              title="Fit"
              onClick={() => this.fit()} />
            <Button icon="search-plus"
              onClick={() => this.setState({
                zoom: Math.min(2, zoom * 1.2) })} />
          </div>
          <div
            className="CircuitGraph__layer"
            style={{
              transform: 'translate(' + pan.x + 'px, ' + pan.y + 'px) '
                + 'scale(' + zoom + ')',
            }}>
            <svg className="CircuitGraph__wires" width="4600" height="4600">
              {edges.map(edge => {
                const key = edge.a.pin.ref + '|' + edge.b.pin.ref;
                const isLit = edge.a.node.ref === lit
                  || edge.b.node.ref === lit;
                return (
                  <path
                    key={key}
                    className={'CircuitGraph__wire CircuitGraph__wire--'
                      + edge.a.io
                      + (isLit ? ' CircuitGraph__wire--lit' : '')}
                    d={wirePath(edge.a, edge.b)}
                    onMouseDown={e => e.stopPropagation()}
                    onClick={() => act(config.ref, 'unwire', {
                      ref: edge.a.node.ref,
                      pin: edge.a.pin.ref,
                      link: edge.b.pin.ref,
                    })}>
                    <title>
                      {plain(edge.a.node.name) + ': '
                        + plain(edge.a.pin.name) + ' - '
                        + plain(edge.b.node.name) + ': '
                        + plain(edge.b.pin.name)}
                    </title>
                  </path>
                );
              })}
              {!!held && !!mouse && (
                <path
                  className="CircuitGraph__wire CircuitGraph__wire--pending"
                  d={wirePath(held, {
                    x: mouse.x,
                    y: mouse.y,
                    side: mouse.x < held.x ? 1 : -1,
                  })} />
              )}
            </svg>
            {nodes.map(node => this.renderNode(node, posOf(node), tool))}
          </div>
        </div>
        <div className={'CircuitGraph__side'
          + (loose ? ' CircuitGraph__side--loose' : '')}>
          {this.renderSide(nodes, pinMap, tool)}
        </div>
      </Fragment>
    );
  }
}
