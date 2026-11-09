// hippie -- the admin's log and report windows (admin_logs_tgui.dm):
// Investigate, individual logs, the server's log files, SDQL results,
// playtime and the station upgrade report.
import { decodeHtmlEntities } from 'common/string';
import { Component, Fragment } from 'inferno';
import { useBackend } from '../backend';
import { Box, Button, Icon, Input, NoticeBox, ProgressBar, Tabs } from '../components';

const text = value => decodeHtmlEntities(String(value || ''));

const matches = (query, ...values) => !query || values
  .some(v => String(v || '').toLowerCase().includes(query));

// Minutes as "3h 20m"
const hours = minutes => {
  const m = Math.round(minutes || 0);
  if (m < 60) {
    return m + 'm';
  }
  return Math.floor(m / 60) + 'h' + (m % 60 ? ' ' + (m % 60) + 'm' : '');
};

const SearchBox = props => (
  <Input placeholder={props.placeholder || 'Search...'}
    width={props.width || '220px'}
    value={props.value}
    onInput={(e, value) => props.onInput(value)} />
);

// ---------------------------------------------------------------------------
// Investigate
// ---------------------------------------------------------------------------

export class AdminInvestigate extends Component {
  constructor() {
    super();
    this.state = { search: '' };
  }

  render() {
    const { act, data } = useBackend(this.props);
    const query = this.state.search.toLowerCase();
    const lines = (data.lines || [])
      .filter(l => matches(query, l.text, l.time));
    return (
      <Box className="AdminLogs__split">
        <Box className="AdminLogs__side">
          {(data.subjects || []).map(s => (
            <Box key={s.name}
              className={'AdminLogs__sideItem'
                + (data.subject === s.name ? ' AdminLogs__sideItem--on' : '')
                + (s.present ? '' : ' AdminLogs__sideItem--empty')}
              onClick={() => act('subject', { subject: s.name })}>
              {s.name}
            </Box>
          ))}
          {!!data.can_notes && (
            <Box mt={1}>
              <Button fluid icon="sticky-note" content="Notes and watchlist"
                onClick={() => act('notes')} />
            </Box>
          )}
        </Box>
        <Box className="AdminLogs__main">
          {!data.subject && (
            <Box color="label" mt={2} textAlign="center">
              Pick a subject.
            </Box>
          )}
          {!!data.subject && (
            <Fragment>
              <Box className="AdminLogs__bar">
                <span className="AdminLogs__title">{data.subject}</span>
                <span className="AdminLogs__muted">
                  {data.total > lines.length && !query
                    ? 'newest ' + lines.length + ' of ' + data.total
                    : lines.length + ' lines'}
                </span>
                <Box inline className="AdminLogs__barEnd">
                  <SearchBox value={this.state.search}
                    onInput={value => this.setState({ search: value })} />
                  <Button icon="sync" tooltip="Read again"
                    onClick={() => act('refresh')} />
                </Box>
              </Box>
              {lines.length === 0 && (
                <Box color="label" mt={1}>
                  {data.total ? 'Nothing matches.' : 'Nothing logged.'}
                </Box>
              )}
              {lines.map((l, i) => (
                <Box key={i} className="AdminLogs__line">
                  <span className="AdminLogs__time">{l.time}</span>
                  {l.x ? (
                    <span className="AdminLogs__where"
                      title="Jump there"
                      onClick={() => act('jump', { x: l.x, y: l.y, z: l.z })}>
                      {l.x + ',' + l.y + ',' + l.z}
                    </span>
                  ) : <span className="AdminLogs__where" />}
                  <span className="AdminLogs__text">{text(l.text)}</span>
                  {!!l.ref && (
                    <Button className="AdminLogs__lineButton" content="VV"
                      onClick={() => act('vv', { ref: l.ref })} />
                  )}
                </Box>
              ))}
            </Fragment>
          )}
        </Box>
      </Box>
    );
  }
}

// ---------------------------------------------------------------------------
// Individual logs
// ---------------------------------------------------------------------------

const KIND_CLASS = {
  'Attack': 'bad',
  'Say': 'say',
  'Whisper': 'say',
  'Dead chat': 'say',
  'Emote': 'emote',
  'OOC': 'ooc',
  'Admin': 'ooc',
};

export class AdminIndividualLog extends Component {
  constructor() {
    super();
    this.state = { search: '' };
  }

  render() {
    const { act, data } = useBackend(this.props);
    if (data.gone) {
      return <NoticeBox>That mob is gone.</NoticeBox>;
    }
    const query = this.state.search.toLowerCase();
    const entries = (data.entries || [])
      .filter(e => matches(query, e.text, e.who, e.kind));
    const counts = data.counts || {};
    return (
      <Fragment>
        <Box className="AdminLogs__bar">
          <span className="AdminLogs__title">{text(data.name)}</span>
          <span className="AdminLogs__muted">{data.key}</span>
          <Box inline className="AdminLogs__barEnd">
            <Button content="Client" selected={data.source === 'Client'}
              disabled={!data.has_client}
              onClick={() => act('source', { source: 'Client' })} />
            <Button content="Mob" selected={data.source === 'Mob'}
              onClick={() => act('source', { source: 'Mob' })} />
            <Button ml={1} icon="user-cog" content="PP"
              onClick={() => act('pp')} />
            <Button icon="eye" content="Follow"
              onClick={() => act('flw')} />
          </Box>
        </Box>
        <Tabs>
          {(data.tabs || []).map(([label, flag]) => (
            <Tabs.Tab key={flag} selected={data.type === flag}
              label={label + ' (' + (counts[flag] || 0) + ')'}
              onClick={() => act('type', { type: flag })} />
          ))}
        </Tabs>
        <Box mb={1}>
          <SearchBox width="100%" value={this.state.search}
            placeholder="Search the lines..."
            onInput={value => this.setState({ search: value })} />
        </Box>
        {entries.length === 0 && <Box color="label">Nothing logged.</Box>}
        {entries.map((e, i) => (
          <Box key={i} className="AdminLogs__entry">
            <Box>
              <span className="AdminLogs__time">{e.time}</span>
              <span className={'AdminLogs__kind AdminLogs__kind--'
                + (KIND_CLASS[e.kind] || 'other')}>
                {e.kind}
              </span>
              <span className="AdminLogs__text">{text(e.text)}</span>
            </Box>
            <Box className="AdminLogs__who">{text(e.who)}</Box>
          </Box>
        ))}
      </Fragment>
    );
  }
}

// ---------------------------------------------------------------------------
// The server's log files
// ---------------------------------------------------------------------------

const fileSize = bytes => {
  if (bytes >= 1048576) {
    return (bytes / 1048576).toFixed(1) + ' MB';
  }
  if (bytes >= 1024) {
    return Math.round(bytes / 1024) + ' KB';
  }
  return bytes + ' B';
};

export class AdminLogFiles extends Component {
  constructor() {
    super();
    this.state = { search: '', filter: '' };
  }

  render() {
    const { act, data } = useBackend(this.props);
    const root = data.root || '';
    const crumbs = (data.path || '').slice(root.length)
      .split('/').filter(Boolean);
    const filter = this.state.filter.toLowerCase();
    const files = (data.files || [])
      .filter(f => matches(filter, f.name));
    const folders = (data.folders || [])
      .filter(f => matches(filter, f));
    const query = this.state.search.toLowerCase();
    const viewLines = data.view_text
      ? data.view_text.split('\n')
        .map((line, i) => [i + 1, line])
        .filter(([, line]) => !query || line.toLowerCase().includes(query))
      : [];
    return (
      <Fragment>
        <Box className="AdminLogs__bar">
          <Button icon="arrow-up" disabled={data.path === root}
            onClick={() => act('up')} />
          <span className="AdminLogs__crumb"
            onClick={() => act('go', { path: root })}>
            logs
          </span>
          {crumbs.map((c, i) => (
            <Fragment key={i}>
              <Icon name="chevron-right" color="label" mx={0.5} />
              <span className="AdminLogs__crumb"
                onClick={() => act('go', {
                  path: root + crumbs.slice(0, i + 1).join('/') + '/',
                })}>
                {c}
              </span>
            </Fragment>
          ))}
          <Box inline className="AdminLogs__barEnd">
            <Button icon="clock" content="This round"
              selected={data.current}
              onClick={() => act('current')} />
          </Box>
        </Box>
        <Box className="AdminLogs__split AdminLogs__split--files">
          <Box className="AdminLogs__side AdminLogs__side--files">
            <SearchBox width="100%" value={this.state.filter}
              placeholder="Filter..."
              onInput={value => this.setState({ filter: value })} />
            {folders.map(f => (
              <Box key={f} className="AdminLogs__file"
                onClick={() => act('open_folder', { name: f })}>
                <Icon name="folder" color="average" mr={1} />
                {f.slice(0, -1)}
              </Box>
            ))}
            {files.map(f => (
              <Box key={f.name}
                className={'AdminLogs__file'
                  + (data.viewing === data.path + f.name
                    ? ' AdminLogs__file--on'
                    : '')
                  + (f.viewable ? '' : ' AdminLogs__file--other')}
                onClick={() => f.viewable && act('view', { name: f.name })}>
                <Icon name="file-alt" color="label" mr={1} />
                <span className="AdminLogs__fileName">{f.name}</span>
                <span className="AdminLogs__muted">{fileSize(f.size)}</span>
              </Box>
            ))}
            {!folders.length && !files.length && (
              <Box color="label" mt={1}>Empty.</Box>
            )}
          </Box>
          <Box className="AdminLogs__main">
            {!data.viewing && (
              <Box color="label" mt={2} textAlign="center">
                Pick a file to read it here.
              </Box>
            )}
            {!!data.viewing && (
              <Fragment>
                <Box className="AdminLogs__bar">
                  <span className="AdminLogs__title">
                    {data.viewing.split('/').pop()}
                  </span>
                  <span className="AdminLogs__muted">
                    {fileSize(data.view_size)
                      + (data.view_cut ? ', the last 256 KB shown' : '')}
                  </span>
                  <Box inline className="AdminLogs__barEnd">
                    <SearchBox value={this.state.search}
                      placeholder="Find lines..."
                      onInput={value => this.setState({ search: value })} />
                    <Button icon="external-link-alt" tooltip="Open"
                      onClick={() => act('open', {
                        name: data.viewing.split('/').pop(),
                      })} />
                    <Button icon="download" tooltip="Download"
                      onClick={() => act('download', {
                        name: data.viewing.split('/').pop(),
                      })} />
                    <Button icon="times" onClick={() => act('close_view')} />
                  </Box>
                </Box>
                <Box className="AdminLogs__viewer">
                  {viewLines.slice(-3000).map(([n, line]) => (
                    <div key={n} className="AdminLogs__viewLine">
                      <span className="AdminLogs__lineNo">{n}</span>
                      {line}
                    </div>
                  ))}
                </Box>
              </Fragment>
            )}
          </Box>
        </Box>
      </Fragment>
    );
  }
}

// ---------------------------------------------------------------------------
// SDQL results
// ---------------------------------------------------------------------------

export class AdminSdqlResults extends Component {
  constructor() {
    super();
    this.state = { search: '' };
  }

  render() {
    const { act, data } = useBackend(this.props);
    const query = this.state.search.toLowerCase();
    const rows = (data.rows || [])
      .filter(r => matches(query, r.name, r.type, r.area));
    return (
      <Fragment>
        <Box className="AdminLogs__query">{text(data.query)}</Box>
        <Box className="AdminLogs__bar">
          <span className="AdminLogs__title">
            {(data.rows || []).length + ' found'}
          </span>
          <span className="AdminLogs__muted">{'in ' + data.took}</span>
          <Box inline className="AdminLogs__barEnd">
            <SearchBox value={this.state.search}
              placeholder="Search names, types, areas..."
              onInput={value => this.setState({ search: value })} />
          </Box>
        </Box>
        <table className="AdminLogs__table">
          <thead>
            <tr>
              <th>Name</th>
              <th>Type</th>
              <th>Where</th>
              <th />
            </tr>
          </thead>
          <tbody>
            {rows.map(r => (
              <tr key={r.ref}>
                <td className="AdminLogs__name">{text(r.name)}</td>
                <td className="AdminLogs__muted">{r.type}</td>
                <td>
                  {r.x ? (
                    <Fragment>
                      {text(r.area)}
                      <span className="AdminLogs__muted">
                        {' ' + r.x + ',' + r.y + ',' + r.z}
                      </span>
                    </Fragment>
                  ) : ''}
                </td>
                <td className="AdminLogs__rowButtons">
                  {!!r.type && (
                    <Button content="VV"
                      onClick={() => act('vv', { ref: r.ref })} />
                  )}
                  {!!r.x && (
                    <Button content="Jump"
                      onClick={() => act('jump', { ref: r.ref })} />
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </Fragment>
    );
  }
}

// ---------------------------------------------------------------------------
// Playtime
// ---------------------------------------------------------------------------

const PlaytimeBars = props => {
  const { rows, total } = props;
  const most = Math.max(1, ...rows.map(r => r.minutes));
  return rows
    .slice()
    .sort((a, b) => b.minutes - a.minutes)
    .map(r => (
      <Box key={r.name} className="AdminLogs__barRow">
        <span className="AdminLogs__barName">{r.name}</span>
        <Box className="AdminLogs__barTrack">
          <Box className="AdminLogs__barFill"
            style={{ width: (100 * r.minutes / most) + '%' }} />
        </Box>
        <span className="AdminLogs__barValue">
          {hours(r.minutes)}
          {!!total && (
            <span className="AdminLogs__muted">
              {' ' + Math.round(100 * r.minutes / total) + '%'}
            </span>
          )}
        </span>
      </Box>
    ));
};

export const PlaytimeDetail = props => {
  const { detail, act } = props;
  if (detail.disabled) {
    return <NoticeBox>Playtime is not tracked on this server.</NoticeBox>;
  }
  return (
    <Fragment>
      <Box className="AdminLogs__totals">
        <Box className="AdminLogs__total">
          <Box className="AdminLogs__totalValue">{hours(detail.living)}</Box>
          <Box className="AdminLogs__muted">Alive</Box>
        </Box>
        <Box className="AdminLogs__total">
          <Box className="AdminLogs__totalValue">{hours(detail.ghost)}</Box>
          <Box className="AdminLogs__muted">Ghost</Box>
        </Box>
        <Box className="AdminLogs__totalFlags">
          {!!detail.exempt && (
            <span className="AdminLogs__tag">Exempt: every job open</span>
          )}
          {!!detail.admin_bypass && (
            <span className="AdminLogs__tag">Admin: every job open</span>
          )}
          {!!act && (
            <Button
              icon="unlock"
              content={detail.exempt ? 'Remove exempt' : 'Make exempt'}
              onClick={() => act('toggle_exempt')} />
          )}
        </Box>
      </Box>
      <Box className="AdminLogs__heading">Departments</Box>
      {(detail.departments || []).length === 0 && (
        <Box color="label">None yet.</Box>
      )}
      <PlaytimeBars rows={detail.departments || []} total={detail.living} />
      <Box className="AdminLogs__heading">Jobs</Box>
      {(detail.jobs || []).length === 0 && <Box color="label">None yet.</Box>}
      <PlaytimeBars rows={detail.jobs || []} total={detail.living} />
      {(detail.locked || []).length > 0 && (
        <Fragment>
          <Box className="AdminLogs__heading">Not unlocked yet</Box>
          {detail.locked.map(j => (
            <Box key={j.name} className="AdminLogs__barRow">
              <span className="AdminLogs__barName">{j.name}</span>
              <Box className="AdminLogs__lockBar">
                <ProgressBar value={j.have / Math.max(1, j.need)}
                  color="average">
                  {hours(j.have) + ' / ' + hours(j.need) + ' as ' + j.as}
                </ProgressBar>
              </Box>
            </Box>
          ))}
        </Fragment>
      )}
    </Fragment>
  );
};

export class AdminPlaytime extends Component {
  constructor() {
    super();
    this.state = { search: '' };
  }

  render() {
    const { act, data } = useBackend(this.props);
    const query = this.state.search.toLowerCase();
    const players = (data.players || [])
      .filter(p => matches(query, p.key, p.job))
      .sort((a, b) => b.living - a.living);
    return (
      <Box className="AdminLogs__split">
        <Box className="AdminLogs__side AdminLogs__side--wide">
          <SearchBox width="100%" value={this.state.search}
            placeholder="Search keys, jobs..."
            onInput={value => this.setState({ search: value })} />
          {players.map(p => (
            <Box key={p.ckey}
              className={'AdminLogs__player'
                + (data.selected === p.ckey
                  ? ' AdminLogs__player--on'
                  : '')}
              onClick={() => act('select', { ckey: p.ckey })}>
              <Box>
                <span className="AdminLogs__name">{p.key}</span>
                {!!p.job && (
                  <span className="AdminLogs__muted">{' ' + p.job}</span>
                )}
              </Box>
              <Box className="AdminLogs__muted">
                {hours(p.living) + ' alive · ' + hours(p.ghost) + ' ghost'}
              </Box>
            </Box>
          ))}
        </Box>
        <Box className="AdminLogs__main">
          {!data.detail && (
            <Box color="label" mt={2} textAlign="center">
              Pick a player.
            </Box>
          )}
          {!!data.detail && (
            <Fragment>
              <Box className="AdminLogs__title" mb={1}>
                {data.detail.key}
              </Box>
              <PlaytimeDetail detail={data.detail} act={act} />
            </Fragment>
          )}
        </Box>
      </Box>
    );
  }
}

export const PlayerPlaytime = props => {
  const { data } = useBackend(props);
  return (
    <Fragment>
      <Box className="AdminLogs__title" mb={1}>{data.key}</Box>
      <PlaytimeDetail detail={data} />
    </Fragment>
  );
};

// ---------------------------------------------------------------------------
// The station upgrade report
// ---------------------------------------------------------------------------

export class AdminUpgradeReport extends Component {
  constructor() {
    super();
    this.state = { search: '', group: 'All' };
  }

  render() {
    const { act, data } = useBackend(this.props);
    const rows = data.rows || [];
    const groups = ['All'].concat(['Machines', 'APCs', 'Mechs', 'Cyborgs']
      .filter(g => rows.some(r => r.group === g)));
    const query = this.state.search.toLowerCase();
    const shown = rows
      .filter(r => this.state.group === 'All' || r.group === this.state.group)
      .filter(r => matches(query, r.name, r.area, r.change));
    return (
      <Fragment>
        <Box className="AdminLogs__title" mb={1}>
          Upgraded {text(data.summary)}
        </Box>
        {(data.explanations || []).map((e, i) => (
          <Box key={i} className="AdminLogs__explain">
            {!!e.title && <b>{e.title}</b>}
            {' ' + e.text}
          </Box>
        ))}
        {(data.totals || []).length > 0 && (
          <Box className="AdminLogs__chips">
            {data.totals.map(t => (
              <span key={t.name} className="AdminLogs__chip">
                {t.name}
                <b>{' ×' + t.count}</b>
              </span>
            ))}
          </Box>
        )}
        <Tabs>
          {groups.map(g => (
            <Tabs.Tab key={g} selected={this.state.group === g}
              label={g + ' (' + (g === 'All'
                ? rows.length
                : rows.filter(r => r.group === g).length) + ')'}
              onClick={() => this.setState({ group: g })} />
          ))}
        </Tabs>
        <Box mb={1}>
          <SearchBox width="100%" value={this.state.search}
            placeholder="Search names, areas, parts..."
            onInput={value => this.setState({ search: value })} />
        </Box>
        {shown.length === 0 && (
          <Box color="label">Nothing needed upgrading.</Box>
        )}
        {shown.map(r => (
          <Box key={r.ref} className="AdminLogs__entry AdminLogs__upgrade">
            <Box>
              <span className="AdminLogs__name">{text(r.name)}</span>
              <span className="AdminLogs__muted">
                {' ' + text(r.area)
                  + (r.x ? ' (' + r.x + ',' + r.y + ',' + r.z + ')' : '')}
              </span>
              <Box inline className="AdminLogs__barEnd">
                <Button content="Jump"
                  onClick={() => act('jump', { ref: r.ref })} />
                <Button content="VV"
                  onClick={() => act('vv', { ref: r.ref })} />
              </Box>
            </Box>
            <Box className="AdminLogs__change">{text(r.change)}</Box>
          </Box>
        ))}
      </Fragment>
    );
  }
}
