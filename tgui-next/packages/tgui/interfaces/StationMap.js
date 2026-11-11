import { Component, createRef } from 'inferno';
import { useBackend } from '../backend';
import { Box, Button, LabeledList, Section } from '../components';

// hippie -- Station Map: the station's rooms by their air, power and alarms.
// Data from hippiestation/code/modules/modular_computers/station_map.dm.
// The plan comes once as rows of "code*length" runs (code = room * 2, + 1
// for a wall); the readings come every update.

const SPACE = '#0b0f17';

// Each layer: what a room's readings make it, as [label, colour]; the
// legend lists them in this order
const AIR = [
  ['Normal', '#008c39'],
  ['Low O2', '#ef8600'],
  ['Low pressure', '#ee8709'],
  ['High pressure', '#f5ce25'],
  ['Cold', '#5ca8fa'],
  ['Hot', '#fb700e'],
  ['Toxic', '#a02bb7'],
  ['Vacuum', '#a42d28'],
  ['Not breathable', '#232b38'],
];

const airState = room => {
  if (!room || room.p === undefined) {
    return AIR[8];
  }
  if (room.p < 20) {
    return AIR[7];
  }
  if (room.plasma > 0.2 || room.co2 > 5) {
    return AIR[6];
  }
  if (room.tmax > 313) {
    return AIR[5];
  }
  if (room.t < 273) {
    return AIR[4];
  }
  if (room.pmax > 121) {
    return AIR[3];
  }
  if (room.p < 81) {
    return AIR[2];
  }
  if (room.o2 < 19) {
    return AIR[1];
  }
  return AIR[0];
};

const POWER = [
  ['Charged', '#008c39'],
  ['Above half', '#6ec82d'],
  ['Below half', '#ee8709'],
  ['Low', '#ca1119'],
  ['Unpowered', '#a42d28'],
  ['Breaker off', '#983eab'],
  ['Fault', '#b72678'],
  ['No APC', '#5c6370'],
  ['Unpowered area', '#2b3340'],
];

const powerState = room => {
  if (!room || !room.needs_power) {
    return POWER[8];
  }
  if (!room.apc) {
    return POWER[7];
  }
  if (room.broken || room.charge === null || room.charge === undefined) {
    return POWER[6];
  }
  if (!room.breaker) {
    return POWER[5];
  }
  if (!room.equip && !room.light && !room.environ) {
    return POWER[4];
  }
  if (room.charge < 15) {
    return POWER[3];
  }
  if (room.charge < 50) {
    return POWER[2];
  }
  if (room.charge < 99 && room.charging !== 2) {
    return POWER[1];
  }
  return POWER[0];
};

const ALARMS = [
  ['Fire', '#ca1119'],
  ['Atmos', '#ee8709'],
  ['Power', '#f5ce25'],
  ['Clear', '#27384a'],
];

const alarmState = room => {
  if (room && room.fire) {
    return ALARMS[0];
  }
  if (room && room.atmos) {
    return ALARMS[1];
  }
  if (room && room.power_alarm) {
    return ALARMS[2];
  }
  return ALARMS[3];
};

const LAYERS = {
  Air: [AIR, airState],
  Power: [POWER, powerState],
  Alarms: [ALARMS, alarmState],
};

const toHex = (r, g, b) => '#' + [r, g, b]
  .map(c => ('0' + Math.round(c).toString(16)).slice(-2)).join('');

// A wall's colour: the room's, darker
const darken = hex => {
  const n = parseInt(hex.slice(1), 16);
  return toHex(((n >> 16) & 255) * 0.45, ((n >> 8) & 255) * 0.45,
    (n & 255) * 0.45);
};

class MapCanvas extends Component {
  constructor() {
    super();
    this.canvasRef = createRef();
    this.runs = null;
    this.runsFrom = null;
  }

  componentDidMount() {
    this.draw();
  }

  componentDidUpdate() {
    this.draw();
  }

  getRuns() {
    const { rows } = this.props;
    if (this.runsFrom !== rows) {
      this.runsFrom = rows;
      this.runs = rows.map(row => {
        if (!row) {
          return [];
        }
        return row.split(',').map(run => {
          const parts = run.split('*');
          return [parseInt(parts[0], 10), parseInt(parts[1], 10)];
        });
      });
    }
    return this.runs;
  }

  roomAt(e) {
    const canvas = this.canvasRef.current;
    const { scale } = this.props;
    const rect = canvas.getBoundingClientRect();
    const tx = Math.floor((e.clientX - rect.left) / scale);
    const ty = Math.floor((e.clientY - rect.top) / scale);
    const row = this.getRuns()[ty];
    if (!row) {
      return 0;
    }
    let x = 0;
    for (let i = 0; i < row.length; i++) {
      if (tx < x + row[i][1]) {
        return row[i][0] >> 1;
      }
      x += row[i][1];
    }
    return 0;
  }

  draw() {
    const canvas = this.canvasRef.current;
    if (!canvas) {
      return;
    }
    const ctx = canvas.getContext('2d');
    const { colors, walls, scale, selected, hover } = this.props;
    ctx.fillStyle = SPACE;
    ctx.fillRect(0, 0, canvas.width, canvas.height);
    // Edges rounded to whole pixels, so a scale like 2.9 leaves no seams
    const fill = (x, y, length) => {
      const left = Math.round(x * scale);
      const top = Math.round(y * scale);
      ctx.fillRect(left, top, Math.round((x + length) * scale) - left,
        Math.round((y + 1) * scale) - top);
    };
    const runs = this.getRuns();
    const marks = [];
    runs.forEach((row, y) => {
      let x = 0;
      row.forEach(run => {
        const code = run[0];
        const length = run[1];
        if (code) {
          const room = code >> 1;
          ctx.fillStyle = (code & 1) ? walls[room] : colors[room];
          fill(x, y, length);
          if (room === selected || room === hover) {
            marks.push([room, x, y, length]);
          }
        }
        x += length;
      });
    });
    marks.forEach(mark => {
      ctx.fillStyle = mark[0] === selected
        ? 'rgba(255, 255, 255, 0.5)'
        : 'rgba(255, 255, 255, 0.22)';
      fill(mark[1], mark[2], mark[3]);
    });
  }

  render() {
    const { width, height, scale, onHover, onSelect } = this.props;
    return (
      <canvas
        ref={this.canvasRef}
        className="StationMap__canvas"
        width={Math.round(width * scale)}
        height={Math.round(height * scale)}
        onMouseMove={e => onHover(this.roomAt(e))}
        onMouseLeave={() => onHover(0)}
        onClick={e => onSelect(this.roomAt(e))} />
    );
  }
}

const kpa = value => (value === undefined ? '-' : value + ' kPa');

const range = (low, high, unit) => {
  if (low === undefined) {
    return '-';
  }
  return (low === high ? low : low + '–' + high) + ' ' + unit;
};

const onOff = value => (value ? 'On' : 'Off');

const CHARGING = ['Not charging', 'Charging', 'Full'];

const Readings = props => {
  const { room } = props;
  if (!room) {
    return null;
  }
  return (
    <LabeledList>
      <LabeledList.Item label="Pressure">
        {range(room.p, room.pmax, 'kPa')}
      </LabeledList.Item>
      <LabeledList.Item label="Temperature">
        {range(room.t, room.tmax, 'K')}
      </LabeledList.Item>
      <LabeledList.Item label="O2">{kpa(room.o2)}</LabeledList.Item>
      <LabeledList.Item label="CO2">{kpa(room.co2)}</LabeledList.Item>
      <LabeledList.Item label="Plasma">{kpa(room.plasma)}</LabeledList.Item>
      <LabeledList.Item label="Air alarm">
        {room.air_alarm ? 'Fitted' : 'None'}
      </LabeledList.Item>
      <LabeledList.Item label="Alarms">
        {[
          room.fire && 'Fire',
          room.atmos && 'Atmos',
          room.power_alarm && 'Power',
        ].filter(Boolean).join(', ') || 'Clear'}
      </LabeledList.Item>
      <LabeledList.Item label="APC">
        {room.apc ? (
          (room.charge === null || room.charge === undefined
            ? 'No cell'
            : room.charge + '%')
          + (room.broken ? ', broken' : '')
          + (room.breaker ? '' : ', breaker off')
        ) : (room.needs_power ? 'None' : 'Not needed')}
      </LabeledList.Item>
      {!!room.apc && (
        <LabeledList.Item label="Cell">
          {CHARGING[room.charging] || '-'}
        </LabeledList.Item>
      )}
      <LabeledList.Item label="Channels">
        {'Equip ' + onOff(room.equip)
          + ', Light ' + onOff(room.light)
          + ', Env ' + onOff(room.environ)}
      </LabeledList.Item>
    </LabeledList>
  );
};

export class StationMap extends Component {
  constructor() {
    super();
    this.state = { layer: 'Air', selected: 0, hover: 0 };
  }

  render() {
    const { act, data } = useBackend(this.props);
    const {
      rows = [],
      areas = [],
      rooms = [],
      width = 0,
      height = 0,
      levels = [],
      z,
    } = data;
    const { layer, selected, hover } = this.state;
    const [legend, stateOf] = LAYERS[layer];
    const colors = [null];
    const walls = [null];
    const counts = {};
    for (let i = 0; i < areas.length; i++) {
      const room = rooms[i];
      const state = stateOf(room);
      const color = state[1];
      colors.push(color);
      walls.push(darken(color));
      counts[state[0]] = (counts[state[0]] || 0) + 1;
    }
    const scale = Math.max(1, Math.min(
      640 / Math.max(width, 1), 590 / Math.max(height, 1)));
    const shown = selected || 0;
    return (
      <div className="StationMap">
        <div className="StationMap__main">
          <div className="StationMap__bar">
            {Object.keys(LAYERS).map(name => (
              <Button
                key={name}
                content={name}
                selected={layer === name}
                onClick={() => this.setState({ layer: name })} />
            ))}
            {levels.length > 1 && levels.map(level => (
              <Button
                key={level}
                content={'Z' + level}
                selected={level === z}
                onClick={() => act('level', { z: level })} />
            ))}
            <Box inline ml={1} color="label">
              {hover ? areas[hover - 1] : ''}
            </Box>
          </div>
          <div className="StationMap__frame">
            <MapCanvas
              rows={rows}
              width={width}
              height={height}
              scale={scale}
              colors={colors}
              walls={walls}
              selected={selected}
              hover={hover}
              onHover={room => {
                if (room !== this.state.hover) {
                  this.setState({ hover: room });
                }
              }}
              onSelect={room => this.setState({ selected: room })} />
          </div>
        </div>
        <div className="StationMap__side">
          <Section title={layer}>
            {legend.map(entry => (
              <div key={entry[0]} className="StationMap__legend">
                <span
                  className="StationMap__chip"
                  style={{ 'background-color': entry[1] }} />
                {entry[0]}
                <span className="StationMap__count">
                  {counts[entry[0]] || ''}
                </span>
              </div>
            ))}
          </Section>
          <Section title={shown ? areas[shown - 1] : 'Room'}>
            {shown ? (
              <Readings room={rooms[shown - 1]} />
            ) : (
              <Box color="label">None selected</Box>
            )}
          </Section>
        </div>
      </div>
    );
  }
}
