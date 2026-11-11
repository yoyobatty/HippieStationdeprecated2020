import { Component } from 'inferno';
import { useBackend } from '../backend';
import { Icon } from '../components';

// hippie -- the research dashboard (the R&D server controller's window): the
// points, where they came from this shift and minute by minute over the last
// hour, what's next to afford and the servers. Data from hippiestation/code/
// modules/research/research_dashboard.dm.

// One colour per source, in the order the server sends them; Other is grey
const COLORS = [
  '#429cf8', '#eb7026', '#5aae6b', '#e58c3b',
  '#e566a5', '#008235', '#a692f8', '#85857f',
];
const SURFACE = '#1f2022';

const full = value => String(Math.round(value || 0))
  .replace(/\B(?=(\d{3})+(?!\d))/g, ',');

const compact = value => {
  if (value >= 10000) {
    return Math.round(value / 1000) + 'K';
  }
  if (value >= 1000) {
    return (Math.round(value / 100) / 10) + 'K';
  }
  return String(Math.round(value));
};

// A clean top for the axis: 1, 2, 2.5 or 5 times a power of ten
const niceMax = value => {
  if (value <= 0) {
    return 100;
  }
  const power = Math.pow(10, Math.floor(Math.log10(value)));
  const steps = [1, 2, 2.5, 5, 10];
  for (let i = 0; i < steps.length; i++) {
    if (steps[i] * power >= value) {
      return steps[i] * power;
    }
  }
  return 10 * power;
};

// A bar's top segment: square at the bottom, rounded at the top
const topPath = (x, y, w, h, r) => {
  const rr = Math.min(r, w / 2, h);
  return 'M' + x + ',' + (y + h)
    + 'V' + (y + rr)
    + 'Q' + x + ',' + y + ' ' + (x + rr) + ',' + y
    + 'H' + (x + w - rr)
    + 'Q' + (x + w) + ',' + y + ' ' + (x + w) + ',' + (y + rr)
    + 'V' + (y + h) + 'Z';
};

// When a node's affordable: now, in so many minutes at this rate, or short
const nodeWhen = node => {
  if (!node.short) {
    return 'ready';
  }
  if (node.eta) {
    return '~' + node.eta + ' min';
  }
  return full(node.short) + ' short';
};

const Tile = props => (
  <div className="RDash__tile">
    <div className="RDash__tileLabel">{props.label}</div>
    <div className="RDash__tileValue">{props.value}</div>
    {!!props.sub && <div className="RDash__tileSub">{props.sub}</div>}
  </div>
);

const Legend = props => (
  <div className="RDash__legend">
    {props.sources.map((source, i) => (
      <span key={source} className="RDash__legendItem">
        <span
          className="RDash__swatch"
          style={{ 'background-color': COLORS[i] }} />
        {source}
      </span>
    ))}
  </div>
);

// Income a minute over the last hour, stacked by source, now at the right
class IncomeChart extends Component {
  constructor() {
    super();
    this.state = { hover: null };
  }

  render() {
    const { chart, sources } = this.props;
    const { hover } = this.state;
    const W = 732;
    const H = 150;
    const left = 40;
    const bottom = 16;
    const slots = 61;
    const slot = (W - left) / slots;
    const barW = Math.min(24, slot - 2);
    const plotH = H - bottom - 4;
    const totals = chart.map(row => row.reduce((a, b) => a + b, 0));
    const top = niceMax(Math.max(0, ...totals));
    const scale = plotH / top;
    const first = slots - chart.length;
    const xOf = i => left + (first + i) * slot + (slot - barW) / 2;
    const ticks = [0, top / 2, top];
    const hovered = hover !== null ? chart[hover] : null;
    return (
      <div className="RDash__chart">
        <svg width={W} height={H} style={{ display: 'block' }}>
          {ticks.map(tick => {
            const y = 4 + plotH - tick * scale + 0.5;
            return (
              <g key={tick}>
                <line x1={left} x2={W} y1={y} y2={y}
                  stroke="#34363a" />
                <text x={left - 6} y={y + 3} fill="#8b8f96"
                  style={{
                    'text-anchor': 'end',
                    'font-size': '10px',
                  }}>{compact(tick)}
                </text>
              </g>
            );
          })}
          {[60, 45, 30, 15, 0].map(ago => (
            <text key={ago}
              x={ago ? left + (slots - 1 - ago) * slot + slot / 2 : W}
              y={H - 3} fill="#8b8f96"
              style={{
                'text-anchor': ago ? 'middle' : 'end',
                'font-size': '10px',
              }}>
              {ago ? '-' + ago + 'm' : 'now'}
            </text>
          ))}
          {chart.map((row, i) => {
            const x = xOf(i);
            let y = 4 + plotH;
            const parts = [];
            const last = row.reduce((at, value, k) => (value > 0 ? k : at), -1);
            row.forEach((value, k) => {
              if (value <= 0) {
                return;
              }
              const h = Math.max(1, value * scale);
              y -= h;
              // the 2px gap: each segment above another stops short of it
              const gap = y + h < 4 + plotH ? 2 : 0;
              const segH = Math.max(1, h - gap);
              parts.push(k === last
                ? <path key={k} d={topPath(x, y, barW, segH, 4)}
                  fill={COLORS[k]} />
                : <rect key={k} x={x} y={y} width={barW} height={segH}
                  fill={COLORS[k]} />);
            });
            const live = i === chart.length - 1;
            return (
              <g key={i}
                opacity={hover !== null && hover !== i
                  ? 0.55
                  : (live ? 0.7 : 1)}>
                {parts}
              </g>
            );
          })}
          {chart.map((row, i) => (
            <rect key={'hit' + i}
              x={left + (first + i) * slot} y={0}
              width={slot} height={H - bottom}
              fill="transparent"
              onMouseOver={() => this.setState({ hover: i })}
              onMouseOut={() => this.setState({ hover: null })} />
          ))}
        </svg>
        {!!hovered && (
          <div
            className="RDash__tip"
            style={{
              left: Math.min(W - 170,
                Math.max(0, xOf(hover) - 80)) + 'px',
            }}>
            <div className="RDash__tipHead">
              {hover === chart.length - 1
                ? 'This minute so far'
                : (chart.length - 1 - hover) + ' min ago'}
            </div>
            <div className="RDash__tipTotal">{full(totals[hover])}</div>
            {hovered.map((value, k) => value > 0 && (
              <div key={k} className="RDash__tipRow">
                <span className="RDash__tipKey"
                  style={{ 'background-color': COLORS[k] }} />
                <b>{full(value)}</b>
                <span className="RDash__muted">{sources[k]}</span>
              </div>
            ))}
          </div>
        )}
      </div>
    );
  }
}

// This shift's points by source, biggest first, each in its colour
const SourceBars = props => {
  const { sources, shift, recent } = props;
  const max = Math.max(1, ...shift);
  const order = sources.map((source, i) => i)
    .sort((a, b) => shift[b] - shift[a]);
  return (
    <div>
      {order.map(i => (
        <div key={sources[i]}
          className={'RDash__source'
            + (shift[i] > 0 ? '' : ' RDash__source--none')}>
          <span className="RDash__sourceName">
            <span className="RDash__swatch"
              style={{ 'background-color': COLORS[i] }} />
            {sources[i]}
          </span>
          <span className="RDash__sourceTrack">
            {shift[i] > 0 && (
              <span className="RDash__sourceBar"
                style={{
                  width: Math.max(2, shift[i] / max * 100) + '%',
                  'background-color': COLORS[i],
                }} />
            )}
          </span>
          <span className="RDash__sourceValue">{full(shift[i])}</span>
          <span className="RDash__sourceRecent">
            {recent[i] > 0 ? '+' + full(recent[i]) : ''}
          </span>
        </div>
      ))}
    </div>
  );
};

export const ResearchDashboard = props => {
  const { data } = useBackend(props);
  const sources = data.sources || [];
  const chart = data.chart || [];
  const next = data.next || [];
  const servers = data.servers || [];
  const lastResearched = data.last_researched || [];
  return (
    <div className="RDash">
      <div className="RDash__tiles">
        <Tile label="Points" value={full(data.points)} />
        <Tile
          label="Per minute"
          value={full(data.per_minute)}
          sub="last 5 min" />
        <Tile
          label="Researched"
          value={data.researched_count + ' / ' + data.node_count}
          sub="nodes" />
        <Tile label="Spent" value={full(data.spent)} sub="this shift" />
      </div>
      <div className="RDash__panel">
        <div className="RDash__title">Income, last hour</div>
        <Legend sources={sources} />
        <IncomeChart chart={chart} sources={sources} />
      </div>
      <div className="RDash__cols">
        <div className="RDash__panel RDash__col">
          <div className="RDash__title">
            This shift
            <span className="RDash__titleNote">last 10 min</span>
          </div>
          <SourceBars
            sources={sources}
            shift={data.shift || []}
            recent={data.recent || []} />
        </div>
        <div className="RDash__panel RDash__col">
          <div className="RDash__title">Next to unlock</div>
          {next.length === 0 && (
            <div className="RDash__muted">Nothing available</div>
          )}
          {next.map(node => (
            <div key={node.name} className="RDash__node">
              <span className="RDash__nodeName">{node.name}</span>
              <span className="RDash__nodeCost">{full(node.cost)}</span>
              <span className={'RDash__nodeWhen'
                + (node.short ? '' : ' RDash__nodeWhen--ready')}>
                {nodeWhen(node)}
              </span>
            </div>
          ))}
          {lastResearched.length > 0 && (
            <div className="RDash__subTitle">Last researched</div>
          )}
          {lastResearched.map((node, i) => (
            <div key={i} className="RDash__node RDash__node--done">
              <span className="RDash__nodeName">
                <Icon name="check" mr={0.5} />
                {node.name}
              </span>
              <span className="RDash__nodeCost">{full(node.cost)}</span>
              <span className="RDash__nodeWhen">
                {node.minutes_ago ? node.minutes_ago + ' min ago' : 'now'}
              </span>
            </div>
          ))}
        </div>
      </div>
      <div className="RDash__panel">
        <div className="RDash__title">
          Servers
          {data.server_income !== null && (
            <span className="RDash__titleNote">
              {full(data.server_income)}/min while any runs
            </span>
          )}
        </div>
        {servers.length === 0 && (
          <div className="RDash__bad">No servers</div>
        )}
        <div className="RDash__servers">
          {servers.map((server, i) => (
            <div key={i} className="RDash__server">
              <Icon name="server" mr={0.5} />
              <span className="RDash__serverName">{server.name}</span>
              <span className={server.working ? 'RDash__good' : 'RDash__bad'}>
                {server.status}
              </span>
              <span className={server.hot ? 'RDash__bad' : 'RDash__muted'}>
                {server.temperature}&deg;C
              </span>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
};
