import { Component } from 'inferno';
import { Box, LabeledList, ProgressBar } from '../../components';

// hippie -- the telecomms network drawn as a map: machines where they stand
// in the telecomms room, their links, packets running along busy links, and
// each machine's state (ok, static, fault, off). Click a machine for its
// details. Data from tcomms_map_data() in hippiestation/code/game/
// machinery/telecomms/telecomms_map.dm.

const WIDTH = 620;
const HEIGHT = 300;
const PAD = 28;

const LETTERS = {
  hub: 'H',
  bus: 'B',
  processor: 'P',
  server: 'S',
  receiver: 'Rx',
  broadcaster: 'Tx',
  relay: 'Re',
  message: 'M',
};

const STATE_TEXT = {
  ok: ['good', 'OK'],
  warn: ['average', 'Static'],
  fault: ['bad', 'Fault'],
  off: ['label', 'Off'],
};

// Where each machine goes: a schematic in the order a signal travels, left
// to right (receivers and relays, the hub, buses, processors, servers,
// broadcasters), each column ordered by the bus its machines hang off
const COLUMNS = {
  receiver: 0,
  relay: 0,
  hub: 1,
  bus: 2,
  processor: 3,
  server: 4,
  broadcaster: 5,
  message: 5,
};
const ROW = 36;

const layout = (nodes, links) => {
  const neighbours = {};
  links.forEach(link => {
    (neighbours[link.a] = neighbours[link.a] || []).push(link.b);
    (neighbours[link.b] = neighbours[link.b] || []).push(link.a);
  });
  const buses = nodes
    .filter(node => node.kind === 'bus')
    .sort((a, b) => String(a.id).localeCompare(String(b.id)));
  const busIndex = {};
  buses.forEach((bus, i) => {
    busIndex[bus.ref] = i;
  });
  // The first bus a machine is linked to, for ordering its column
  const busOf = node => {
    const near = (neighbours[node.ref] || [])
      .filter(ref => busIndex[ref] !== undefined)
      .map(ref => busIndex[ref]);
    return near.length ? Math.min(...near) : 99;
  };
  const columns = [[], [], [], [], [], []];
  nodes.forEach(node => {
    columns[COLUMNS[node.kind] !== undefined ? COLUMNS[node.kind] : 0]
      .push(node);
  });
  columns.forEach(column => column.sort((a, b) => (busOf(a) - busOf(b))
    || String(a.id).localeCompare(String(b.id))));
  const tallest = Math.max(...columns.map(column => column.length));
  const height = Math.max(HEIGHT, tallest * ROW + PAD * 2);
  const at = {};
  columns.forEach((column, c) => {
    const x = PAD + 20 + c * ((WIDTH - PAD * 2 - 40) / 5);
    column.forEach((node, i) => {
      at[node.ref] = {
        x,
        y: PAD + (i + 0.5) * ((height - PAD * 2) / column.length),
      };
    });
  });
  return { at, height };
};

export class TelecommsMap extends Component {
  constructor() {
    super();
    this.state = { selected: null };
  }

  render() {
    const { map } = this.props;
    const nodes = (map && map.nodes) || [];
    const links = (map && map.links) || [];
    if (!nodes.length) {
      return <Box color="label">No machines.</Box>;
    }
    const { at, height } = layout(nodes, links);
    const byRef = {};
    nodes.forEach(node => {
      byRef[node.ref] = node;
    });
    const selected = byRef[this.state.selected];
    const select = ref => this.setState(prev => ({
      selected: prev.selected === ref ? null : ref,
    }));
    return (
      <div className="TcommsMap">
        <svg
          className="TcommsMap__svg"
          viewBox={'0 0 ' + WIDTH + ' ' + height}
          width={WIDTH}
          height={height}>
          {links.map(link => {
            const a = at[link.a];
            const b = at[link.b];
            if (!a || !b) {
              return null;
            }
            const busy = (byRef[link.a].traffic + byRef[link.b].traffic) > 0;
            const down = byRef[link.a].state === 'off'
              || byRef[link.b].state === 'off';
            return (
              <line
                key={link.a + link.b}
                className={'TcommsMap__link'
                  + (busy && !down ? ' TcommsMap__link--busy' : '')
                  + (down ? ' TcommsMap__link--down' : '')}
                x1={a.x} y1={a.y} x2={b.x} y2={b.y} />
            );
          })}
          {nodes.map(node => {
            const p = at[node.ref];
            return (
              <g
                key={node.ref}
                className="TcommsMap__node"
                onClick={() => select(node.ref)}>
                <circle
                  className={'TcommsMap__dot TcommsMap__dot--' + node.state
                    + (selected === node ? ' TcommsMap__dot--selected' : '')}
                  cx={p.x} cy={p.y} r={13} />
                <text
                  className="TcommsMap__letter"
                  x={p.x} y={p.y + 4}>
                  {LETTERS[node.kind] || '?'}
                </text>
                <text
                  className="TcommsMap__label"
                  x={p.x} y={p.y + 25}>
                  {node.id}
                </text>
              </g>
            );
          })}
        </svg>
        <div className="TcommsMap__legend">
          {Object.keys(STATE_TEXT).map(state => (
            <Box key={state} inline mr={2}>
              <span className={'TcommsMap__swatch TcommsMap__dot--' + state} />
              {STATE_TEXT[state][1]}
            </Box>
          ))}
          <Box inline color="label">
            H hub · B bus · P processor · S server · Rx/Tx receiver/broadcaster
          </Box>
        </div>
        {selected && (
          <div className="TcommsMap__details">
            <Box bold mb={0.5}>
              {selected.name}
              <Box inline color="label" ml={1}>{selected.id}</Box>
              <Box inline ml={1} color={STATE_TEXT[selected.state][0]}>
                {STATE_TEXT[selected.state][1]}
              </Box>
            </Box>
            <LabeledList>
              <LabeledList.Item
                label="Temperature"
                color={selected.overheated
                  ? 'bad'
                  : (selected.temperature > 200 ? 'average' : 'good')}>
                {selected.temperature} K
                {selected.overheated && ' (OVERHEATED)'}
              </LabeledList.Item>
              <LabeledList.Item label="Integrity">
                <ProgressBar
                  value={selected.integrity / 100}
                  ranges={{
                    good: [0.8, Infinity],
                    average: [0.4, 0.8],
                    bad: [-Infinity, 0.4],
                  }}>
                  {selected.integrity}%
                </ProgressBar>
              </LabeledList.Item>
              <LabeledList.Item label="Traffic">
                {selected.traffic}
              </LabeledList.Item>
              <LabeledList.Item label="Signal noise">
                {selected.noise}%
              </LabeledList.Item>
              {!!selected.emped && (
                <LabeledList.Item label="Fault" color="bad">
                  EMP
                </LabeledList.Item>
              )}
              {!selected.toggled && (
                <LabeledList.Item label="Power" color="label">
                  Switched off
                </LabeledList.Item>
              )}
            </LabeledList>
          </div>
        )}
      </div>
    );
  }
}
