import { Component, Fragment } from 'inferno';
import { useBackend } from '../backend';
import { Button, Icon, Input } from '../components';

// hippie -- the Bans window: New ban (length presets, the player's record,
// who's online and who left, the role grid with their current role bans),
// the list of bans (role bans made together as one row, edit which roles,
// lift all or one, time left), sticky bans, and notes (kept on the server
// with no database). Data and actions from
// hippiestation/code/modules/admin/ban_window.dm.

const TABS = [
  ['new', 'New ban', 'gavel'],
  ['bans', 'Bans', 'list'],
  ['sticky', 'Sticky', 'link'],
  ['notes', 'Notes', 'sticky-note'],
];

const UNITS = [
  ['MINUTE', 'Minutes', 60],
  ['HOUR', 'Hours', 3600],
  ['DAY', 'Days', 86400],
  ['WEEK', 'Weeks', 604800],
  ['MONTH', 'Months', 2592000],
  ['YEAR', 'Years', 31536000],
];

const UNIT_SECONDS = {};
UNITS.forEach(u => {
  UNIT_SECONDS[u[0]] = u[2];
});

const PRESETS = [
  ['1h', 1, 'HOUR'],
  ['1d', 1, 'DAY'],
  ['3d', 3, 'DAY'],
  ['1w', 1, 'WEEK'],
  ['1mo', 1, 'MONTH'],
];

const SEVERITIES = ['none', 'minor', 'medium', 'high'];

const SEVERITY_NAMES = {
  none: 'None',
  minor: 'Minor',
  medium: 'Medium',
  high: 'High',
};

const KIND_NAMES = {
  'note': 'Note',
  'message': 'Message',
  'message sent': 'Message (read)',
  'watchlist entry': 'Watchlist',
  'memo': 'Memo',
};

const DAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug',
  'Sep', 'Oct', 'Nov', 'Dec'];

const pad = n => (n < 10 ? '0' : '') + n;

// world.realtime (tenths of a second since 2000, GMT) as the server's own
// clock reads it, so far from now
const serverDate = (realtime, tz, seconds) => new Date(Number(realtime) * 100
  + 946684800000 + (tz || 0) * 3600000 + (seconds || 0) * 1000);

const formatDate = d => DAYS[d.getUTCDay()] + ' ' + d.getUTCDate() + ' '
  + MONTHS[d.getUTCMonth()] + ' ' + d.getUTCFullYear() + ', '
  + pad(d.getUTCHours()) + ':' + pad(d.getUTCMinutes());

// "3d 4h", "5h 12m", "12m"
const spanText = seconds => {
  seconds = Math.max(0, Math.round(seconds));
  let days = Math.floor(seconds / 86400);
  const hours = Math.floor((seconds % 86400) / 3600);
  const minutes = Math.floor((seconds % 3600) / 60);
  if (days >= 365) {
    const years = Math.floor(days / 365);
    days -= years * 365;
    return years + 'y' + (days ? ' ' + days + 'd' : '');
  }
  if (days) {
    return days + 'd' + (hours ? ' ' + hours + 'h' : '');
  }
  if (hours) {
    return hours + 'h' + (minutes ? ' ' + minutes + 'm' : '');
  }
  return minutes ? minutes + 'm' : '<1m';
};

// A length in minutes as a number and a unit, the biggest that fits whole
const fromMinutes = minutes => {
  const seconds = minutes * 60;
  for (let i = UNITS.length - 1; i >= 0; i--) {
    if (seconds >= UNITS[i][2] && seconds % UNITS[i][2] === 0) {
      return [String(seconds / UNITS[i][2]), UNITS[i][0]];
    }
  }
  return [String(minutes), 'MINUTE'];
};

const lengthSeconds = form => {
  if (form.perm) {
    return 0;
  }
  return (Number(form.length) || 0) * (UNIT_SECONDS[form.unit] || 60);
};

// A button that asks once more in place before it acts
class Confirm extends Component {
  constructor() {
    super();
    this.state = { armed: false };
  }

  componentWillUnmount() {
    clearTimeout(this.timer);
  }

  render() {
    const {
      content, confirmContent, icon, color, disabled, title, onClick,
    } = this.props;
    if (this.state.armed) {
      return (
        <Button
          icon="exclamation-triangle"
          color="red"
          content={confirmContent || 'Sure?'}
          onClick={() => {
            clearTimeout(this.timer);
            this.setState({ armed: false });
            onClick();
          }} />
      );
    }
    return (
      <Button
        icon={icon}
        color={color}
        disabled={disabled}
        title={title}
        content={content}
        onClick={() => {
          this.setState({ armed: true });
          clearTimeout(this.timer);
          this.timer = setTimeout(() => this.setState({ armed: false }), 4000);
        }} />
    );
  }
}

const Chip = props => {
  const { className, children, ...rest } = props;
  return (
    <span className={'BanWindow__chip ' + (className || '')} {...rest}>
      {children}
    </span>
  );
};

const Select = props => {
  const { value, options, onChange, className } = props;
  return (
    <select
      className={'BanWindow__select ' + (className || '')}
      value={value}
      onChange={e => onChange(e.target.value)}>
      {options.map(o => (
        <option key={o[0]} value={o[0]}>{o[1]}</option>
      ))}
    </select>
  );
};

const Check = props => {
  const { checked, content, onClick, title } = props;
  return (
    <span
      className={'BanWindow__check'
        + (checked ? ' BanWindow__check--on' : '')}
      title={title}
      onClick={onClick}>
      <Icon name={checked ? 'check-square' : 'square-o'} mr={0.5} />
      {content}
    </span>
  );
};

// The length controls: presets, a number and a unit, and when it ends
const LengthPicker = props => {
  const { form, onChange, endsFrom, tz } = props;
  const seconds = lengthSeconds(form);
  return (
    <Fragment>
      <div className="BanWindow__row">
        {PRESETS.map(p => (
          <Button
            key={p[0]}
            content={p[0]}
            selected={!form.perm && String(form.length) === String(p[1])
              && form.unit === p[2]}
            onClick={() => onChange({
              perm: false, length: String(p[1]), unit: p[2],
            })} />
        ))}
        <Button
          content="Perm"
          color={form.perm ? 'red' : null}
          selected={form.perm}
          onClick={() => onChange({ perm: true })} />
        <span className="BanWindow__gap" />
        <Input
          className="BanWindow__number"
          value={form.perm ? '' : form.length}
          placeholder={form.perm ? 'never' : '#'}
          onInput={(e, value) => onChange({ perm: false, length: value })} />
        <Select
          value={form.unit}
          options={UNITS}
          onChange={value => onChange({ perm: false, unit: value })} />
      </div>
      <div className="BanWindow__ends">
        {form.perm
          ? 'Permanent: it never ends.'
          : seconds > 0
            ? 'Ends ' + formatDate(serverDate(endsFrom, tz, seconds))
              + ' (server time), ' + spanText(seconds)
              + (props.fromStart ? ' after it was made' : ' from now')
            : 'Give a length above 0.'}
      </div>
    </Fragment>
  );
};

// The role groups as chips. picked: role = true. banned: lowercase role =
// { id, left, computer }.
const RoleGrid = props => {
  const { groups, picked, banned, onToggle, onToggleGroup, onLift } = props;
  return (
    <div className="BanWindow__roles">
      {groups.map(group => {
        const all = group.roles.every(role => picked[role]);
        return (
          <div key={group.name} className="BanWindow__roleGroup">
            <div
              className="BanWindow__roleGroupName"
              title={all ? 'Untick all' : 'Tick all'}
              onClick={() => onToggleGroup(group.roles, !all)}>
              <Icon name={all ? 'check-square' : 'square-o'} mr={0.5} />
              {group.name}
            </div>
            <div>
              {group.roles.map(role => {
                const ban = banned && banned[role.toLowerCase()];
                return (
                  <Chip
                    key={role}
                    className={(picked[role] ? 'BanWindow__chip--on ' : '')
                      + (ban ? 'BanWindow__chip--banned' : '')}
                    title={ban
                      ? 'Banned already, ' + ban.left
                        + (ban.computer ? ' (a ban on this computer)' : '')
                      : null}
                    onClick={() => onToggle(role)}>
                    {role}
                    {!!ban && (
                      <span className="BanWindow__chipLeft">{ban.left}</span>
                    )}
                    {!!ban && !!onLift && (
                      <span
                        className="BanWindow__chipX"
                        title={'Lift the ' + role + ' ban'}
                        onClick={e => {
                          e.stopPropagation();
                          onLift(ban.id, role);
                        }}>
                        <Icon name="times" />
                      </span>
                    )}
                  </Chip>
                );
              })}
            </div>
          </div>
        );
      })}
    </div>
  );
};

const STATE_NAMES = {
  lifted: 'Lifted',
  expired: 'Ended',
};

const DB_NAMES = {
  off: 'Kept on this server',
  up: 'Database',
  down: 'Database out of reach',
};

const statusClass = status => 'BanWindow__status--' + status;

export class BanWindow extends Component {
  constructor() {
    super();
    this.prefillSerial = null;
    this.form = {
      key: '', ip: '', cid: '', use_ip: false, use_cid: true,
      kind: 'server', roles: {}, perm: false, length: '1', unit: 'DAY',
      reason: '', applies: false, severity: null,
    };
    // what's typed in the boxes, until searched (then the server's)
    this.typed = { search: null, notesSearch: null };
    this.sticky = { ckey: '', reason: '' };
    this.stickyEdit = null;
    this.compose = null;
    this.composeSerial = null;
    this.noteEdit = null;
    this.state = {
      picker: false,
      edit: null,
      liftArmed: null,
    };
  }

  redraw() {
    this.setState({});
  }

  setForm(patch) {
    Object.assign(this.form, patch);
    this.setState({});
  }

  syncPrefill(data) {
    const p = data.prefill;
    if (!p || p.serial === this.prefillSerial) {
      return;
    }
    this.prefillSerial = p.serial;
    const form = this.form;
    form.key = p.key || '';
    form.ip = p.ip || '';
    form.cid = p.cid || '';
    if (p.full) {
      form.use_ip = !!p.use_ip;
      form.use_cid = !!p.use_cid;
      form.kind = p.kind || 'server';
      form.roles = {};
      (p.roles || []).forEach(role => {
        form.roles[role] = true;
      });
      form.perm = !!p.perm;
      form.length = String(p.length);
      form.unit = p.unit || 'DAY';
      form.reason = p.reason || '';
      form.applies = !!p.applies;
      form.severity = p.severity || null;
    }
  }

  syncCompose(data) {
    const c = data.compose;
    const serial = c ? c.serial : null;
    if (serial === this.composeSerial) {
      return;
    }
    this.composeSerial = serial;
    this.compose = null;
    if (c) {
      this.compose = {
        kind: c.kind, text: c.text || '', secret: c.kind !== 'message',
        severity: null, expiry: 'Never', key: '',
      };
    }
  }

  render() {
    const { act, data } = useBackend(this.props);
    this.syncPrefill(data);
    this.syncCompose(data);
    const tab = data.tab;
    return (
      <div className="BanWindow">
        <div className="BanWindow__tabs">
          {TABS.filter(t => data.can_ban || t[0] === 'notes').map(t => (
            <span
              key={t[0]}
              className={'BanWindow__tab'
                + (tab === t[0] ? ' BanWindow__tab--on' : '')}
              onClick={() => act('tab', { tab: t[0] })}>
              <Icon name={t[2]} mr={0.5} />
              {t[1]}
            </span>
          ))}
          <span className="BanWindow__spacer" />
          <span
            className={'BanWindow__db BanWindow__db--' + data.db}
            title={data.db === 'off'
              ? 'No database: bans, notes and connections are kept on'
                + ' this server, in data/'
              : data.db === 'up'
                ? 'The database is connected'
                : 'The database is out of reach: what\'s made now is kept'
                  + ' on this server and sent when it\'s back'}>
            <Icon name="database" mr={0.5} />
            {DB_NAMES[data.db]}
          </span>
        </div>
        {!!data.notice && (
          <div className={'BanWindow__notice'
            + (data.notice_bad ? ' BanWindow__notice--bad' : '')}>
            <Icon name={data.notice_bad ? 'exclamation-circle' : 'check'}
              mr={0.5} />
            {data.notice}
          </div>
        )}
        <div className="BanWindow__body">
          {tab === 'new' && this.renderNew(act, data)}
          {tab === 'bans' && this.renderBans(act, data)}
          {tab === 'sticky' && this.renderSticky(act, data)}
          {tab === 'notes' && this.renderNotes(act, data)}
        </div>
      </div>
    );
  }

  // ---------------------------------------------------------------- New ban

  renderNew(act, data) {
    const form = this.form;
    const record = data.record;
    const seconds = lengthSeconds(form);
    const pickedRoles = Object.keys(form.roles).filter(r => form.roles[r]);
    const target = form.key
      || [form.use_ip && form.ip, form.use_cid && form.cid]
        .filter(x => x).join('/')
      || 'nobody';
    let what = pickedRoles.length + ' roles';
    if (form.kind === 'server') {
      what = 'the server';
    }
    else if (pickedRoles.length === 1) {
      what = pickedRoles[0];
    }
    const howLong = form.perm ? 'permanently' : 'for ' + spanText(seconds);
    return (
      <div className="BanWindow__newBan">
        <div className="BanWindow__form">
          <div className="BanWindow__field">
            <span className="BanWindow__label">Player</span>
            <Input
              className="BanWindow__keyBox"
              value={form.key}
              placeholder="Key or ckey"
              onInput={(e, value) => {
                this.form.key = value;
              }}
              onChange={(e, value) => {
                if (value !== (record && record.key)) {
                  act('pick', { key: value });
                }
              }} />
            <Button
              icon="users"
              content="Players"
              selected={this.state.picker}
              onClick={() => this.setState(state => ({
                picker: !state.picker,
              }))} />
          </div>
          {this.state.picker && this.renderPicker(act, data)}
          <div className="BanWindow__field">
            <span className="BanWindow__label">Match</span>
            <Check
              checked={form.use_ip}
              content="IP"
              title="Bans everyone on this address too"
              onClick={() => this.setForm({ use_ip: !form.use_ip })} />
            <Input
              className="BanWindow__ipBox"
              value={form.ip}
              placeholder="IP address"
              onInput={(e, value) => {
                this.form.ip = value;
              }} />
            <Check
              checked={form.use_cid}
              content="Computer ID"
              title={'With a computer ID, a role ban holds every key on'
                + ' that computer'}
              onClick={() => this.setForm({ use_cid: !form.use_cid })} />
            <Input
              className="BanWindow__cidBox"
              value={form.cid}
              placeholder="Computer ID"
              onInput={(e, value) => {
                this.form.cid = value;
              }} />
          </div>
          <div className="BanWindow__field BanWindow__field--top">
            <span className="BanWindow__label">Length</span>
            <div className="BanWindow__grow">
              <LengthPicker
                form={form}
                endsFrom={data.now}
                tz={data.tz}
                onChange={patch => this.setForm(patch)} />
            </div>
          </div>
          <div className="BanWindow__field">
            <span className="BanWindow__label">Ban from</span>
            <Button
              content="The server"
              icon="server"
              selected={form.kind === 'server'}
              onClick={() => this.setForm({ kind: 'server' })} />
            <Button
              content={pickedRoles.length
                ? 'Roles (' + pickedRoles.length + ')'
                : 'Roles'}
              icon="user-tag"
              selected={form.kind === 'roles'}
              onClick={() => this.setForm({ kind: 'roles' })} />
            <span className="BanWindow__gap" />
            <Check
              checked={form.applies}
              content="Applies to admins"
              onClick={() => this.setForm({ applies: !form.applies })} />
          </div>
          <div className="BanWindow__field">
            <span className="BanWindow__label">Note</span>
            {SEVERITIES.map(s => (
              <Button
                key={s}
                content={SEVERITY_NAMES[s]}
                className={'BanWindow__sev BanWindow__sev--' + s}
                selected={form.severity === s}
                onClick={() => this.setForm({ severity: s })} />
            ))}
            <span className="BanWindow__muted BanWindow__hint">
              Severity of the note it writes
            </span>
          </div>
          <div className="BanWindow__field BanWindow__field--top">
            <span className="BanWindow__label">Reason</span>
            <textarea
              className="BanWindow__textarea"
              value={form.reason}
              maxLength={data.reason_max}
              placeholder="What they did, and the rule"
              onInput={e => {
                this.form.reason = e.target.value;
                this.setState({});
              }} />
          </div>
          <div className="BanWindow__submit">
            <span className="BanWindow__muted">
              {'Ban ' + target + ' from ' + what + ' ' + howLong
                + (record && record.status === 'unknown'
                  ? '. This key has never been seen here.'
                  : '.')}
            </span>
            <Confirm
              icon="gavel"
              color="red"
              content="Ban"
              confirmContent={'Ban ' + target + '?'}
              onClick={() => act('ban', {
                key: form.key,
                ip: form.ip,
                cid: form.cid,
                use_ip: form.use_ip ? 1 : 0,
                use_cid: form.use_cid ? 1 : 0,
                kind: form.kind,
                roles: pickedRoles.join(','),
                perm: form.perm ? 1 : 0,
                length: form.length,
                unit: form.unit,
                applies: form.applies ? 1 : 0,
                severity: form.severity,
                reason: form.reason,
              })} />
          </div>
          {form.kind === 'roles' && (
            <RoleGrid
              groups={data.role_groups || []}
              picked={form.roles}
              banned={record && record.role_bans}
              onToggle={role => {
                form.roles[role] = !form.roles[role];
                this.setState({});
              }}
              onToggleGroup={(roles, on) => {
                roles.forEach(role => {
                  form.roles[role] = on;
                });
                this.setState({});
              }}
              onLift={id => act('lift_role', { id })} />
          )}
        </div>
        <div className="BanWindow__record">
          {this.renderRecord(act, data, record)}
        </div>
      </div>
    );
  }

  renderPicker(act, data) {
    const row = (p, left) => (
      <div
        key={p.ckey}
        className="BanWindow__pick"
        onClick={() => {
          this.setState({ picker: false });
          act('pick', { key: p.key });
        }}>
        <div className="BanWindow__pickTop">
          <span className="BanWindow__pickKey">{p.key}</span>
          {!!p.admin && (
            <span className="BanWindow__badge">admin</span>
          )}
          <span className="BanWindow__spacer" />
          {left && (
            <span className="BanWindow__muted">{p.ago} ago</span>
          )}
        </div>
        <div className="BanWindow__pickName">
          {p.name || '?'}{p.job ? ', ' + p.job : ''}
        </div>
      </div>
    );
    const online = data.online || [];
    const left = data.left || [];
    return (
      <div className="BanWindow__picker">
        <div className="BanWindow__pickerCol">
          <div className="BanWindow__pickerHead">
            Online ({online.length})
          </div>
          {online.map(p => row(p, false))}
        </div>
        <div className="BanWindow__pickerCol">
          <div className="BanWindow__pickerHead">
            Left this round ({left.length})
          </div>
          {left.length === 0 && (
            <div className="BanWindow__muted">Nobody yet.</div>
          )}
          {left.map(p => row(p, true))}
        </div>
      </div>
    );
  }

  renderRecord(act, data, record) {
    if (!record) {
      return (
        <div className="BanWindow__empty">
          Pick a player, or type a key: their bans, notes and the keys on
          their computer show here.
        </div>
      );
    }
    const status = {
      online: 'Online, ' + (record.name || '?')
        + (record.job ? ' (' + record.job + ')' : ''),
      left: 'Left ' + record.left_ago + ' ago, as ' + (record.name || '?')
        + (record.job ? ' (' + record.job + ')' : ''),
      seen: 'Last seen ' + (record.last_seen || '?'),
      unknown: 'Never seen here',
    }[record.status];
    const groups = record.groups || [];
    const activeGroups = groups.filter(g => g.status === 'active');
    const notes = record.notes || [];
    return (
      <Fragment>
        <div className="BanWindow__recordHead">
          <span className="BanWindow__recordKey">{record.key}</span>
          <span className={'BanWindow__presence BanWindow__presence--'
            + record.status}>
            {status}
          </span>
        </div>
        {record.status !== 'unknown' && (
          <div className="BanWindow__muted BanWindow__small">
            {record.first_seen ? 'First seen ' + record.first_seen : ''}
            {record.connections
              ? ' · ' + record.connections + ' connection'
                + (record.connections === 1 ? '' : 's')
              : ''}
          </div>
        )}
        {(record.ips || []).length > 0 && (
          <div className="BanWindow__recordRow">
            <span className="BanWindow__label">IPs</span>
            {record.ips.map(ip => (
              <Chip
                key={ip}
                className={this.form.ip === ip ? 'BanWindow__chip--on' : ''}
                title="Use this IP"
                onClick={() => this.setForm({ ip: ip })}>
                {ip}
              </Chip>
            ))}
          </div>
        )}
        {(record.cids || []).length > 0 && (
          <div className="BanWindow__recordRow">
            <span className="BanWindow__label">Computers</span>
            {record.cids.map(cid => (
              <Chip
                key={cid}
                className={this.form.cid === cid ? 'BanWindow__chip--on' : ''}
                title="Use this computer ID"
                onClick={() => this.setForm({ cid: cid })}>
                {cid}
              </Chip>
            ))}
          </div>
        )}
        {(record.same_computer || []).length > 0 && (
          <div className="BanWindow__recordRow">
            <span className="BanWindow__label BanWindow__warn">
              Same PC
            </span>
            {record.same_computer.map(key => (
              <Chip key={key} className="BanWindow__chip--warn"
                title="Another key seen on this computer: look them up"
                onClick={() => act('pick', { key })}>
                {key}
              </Chip>
            ))}
          </div>
        )}
        {(record.same_ip || []).length > 0 && (
          <div className="BanWindow__recordRow">
            <span className="BanWindow__label">Same IP</span>
            {record.same_ip.map(key => (
              <Chip key={key}
                title="Another key seen on this address: look them up"
                onClick={() => act('pick', { key })}>
                {key}
              </Chip>
            ))}
          </div>
        )}
        <div className="BanWindow__recordSection">
          Bans
          <span className="BanWindow__muted">
            {' '}{activeGroups.length} on, {groups.length} in all
          </span>
          <span className="BanWindow__spacer" />
          {groups.length > 0 && (
            <Button
              content="In the list"
              icon="list"
              onClick={() => {
                this.typed.search = null;
                act('show_in_list', { key: record.key });
              }} />
          )}
        </div>
        {groups.length === 0 && (
          <div className="BanWindow__muted BanWindow__small">None.</div>
        )}
        {groups.slice(0, 8).map(g => (
          <div key={g.id}
            className={'BanWindow__mini ' + statusClass(g.status)}>
            <div>
              <b>{g.server ? 'Server' : g.roles.map(r => r.role).join(', ')}</b>
              <span className="BanWindow__muted">
                {' · ' + g.length + ' · ' + g.bantime
                  + ' · ' + g.admin}
              </span>
            </div>
            <div className="BanWindow__miniLine">
              <span className={'BanWindow__state ' + statusClass(g.status)}>
                {STATE_NAMES[g.status] || g.left}
              </span>
              <span className="BanWindow__miniReason">{g.reason}</span>
              {g.status === 'active' && (
                <Confirm
                  icon="unlock"
                  content="Lift"
                  confirmContent="Lift it?"
                  onClick={() => act('lift_group', { id: g.id })} />
              )}
            </div>
          </div>
        ))}
        <div className="BanWindow__recordSection">
          Notes
          <span className="BanWindow__muted">
            {' '}{record.note_count}
          </span>
          <span className="BanWindow__spacer" />
          <Button
            content="Open"
            icon="sticky-note"
            onClick={() => act('open_notes', { key: record.ckey })} />
        </div>
        {notes.length === 0 && (
          <div className="BanWindow__muted BanWindow__small">None.</div>
        )}
        {notes.map(n => (
          <div key={n.id} className="BanWindow__mini">
            <div>
              {!!n.severity && (
                <span className={'BanWindow__sevDot BanWindow__sev--'
                  + n.severity} title={SEVERITY_NAMES[n.severity]} />
              )}
              <b>{KIND_NAMES[n.kind] || n.kind}</b>
              <span className="BanWindow__muted">
                {' · ' + n.timestamp + ' · ' + n.admin_key}
              </span>
            </div>
            <div className="BanWindow__miniReason">{n.text}</div>
          </div>
        ))}
      </Fragment>
    );
  }

  // ------------------------------------------------------------------- Bans

  search(act, data, patch) {
    const choice = Object.assign({
      text: this.typed.search !== null ? this.typed.search : data.search,
      active: data.show_active ? 1 : 0,
      expired: data.show_expired ? 1 : 0,
      lifted: data.show_lifted ? 1 : 0,
      sort: data.sort,
    }, patch || {});
    act('search', choice);
  }

  renderBans(act, data) {
    const groups = data.groups || [];
    const searchText = this.typed.search !== null
      ? this.typed.search
      : (data.search || '');
    const toggle = (key, value, name) => (
      <Chip
        className={value ? 'BanWindow__chip--on' : ''}
        onClick={() => this.search(act, data, { [key]: value ? 0 : 1 })}>
        {name}
      </Chip>
    );
    return (
      <div className="BanWindow__bans">
        <div className="BanWindow__bar">
          <Input
            className="BanWindow__searchBox"
            value={searchText}
            placeholder="Key, admin, role, reason, IP or computer ID"
            onInput={(e, value) => {
              this.typed.search = value;
            }}
            onChange={(e, value) => this.search(act, data, { text: value })} />
          <Button icon="search" content="Search"
            onClick={() => this.search(act, data)} />
          <span className="BanWindow__gap" />
          {toggle('active', data.show_active, 'Active')}
          {toggle('expired', data.show_expired, 'Expired')}
          {toggle('lifted', data.show_lifted, 'Lifted')}
          <span className="BanWindow__spacer" />
          <Button
            icon={data.sort === 'ending' ? 'hourglass-half' : 'clock'}
            content={data.sort === 'ending' ? 'Ending soonest' : 'Newest'}
            title="Sort"
            onClick={() => this.search(act, data, {
              sort: data.sort === 'ending' ? 'newest' : 'ending',
            })} />
        </div>
        <div className="BanWindow__status">
          {groups.length === 0
            ? 'No bans match.'
            : groups.length + data.more + ' ban'
              + (groups.length + data.more === 1 ? '' : 's')
              + (data.more ? ', the first ' + groups.length + ' shown' : '')}
          {data.db === 'down' && (
            <span className="BanWindow__warn">
              {' '}The database is out of reach: these are the active bans
              as last copied, and the ones made here.
            </span>
          )}
        </div>
        <div className="BanWindow__list">
          {groups.map(g => this.renderGroup(act, data, g))}
        </div>
      </div>
    );
  }

  startEdit(g) {
    const [length, unit] = g.minutes ? fromMinutes(g.minutes) : ['1', 'DAY'];
    const roles = {};
    g.roles.forEach(r => {
      if (r.status === 'active') {
        roles[r.role] = true;
      }
    });
    this.setState({
      edit: {
        id: g.id, key: g.key || '', ip: g.ip || '', cid: g.cid || '',
        perm: !g.minutes, length, unit, applies: !!g.applies,
        reason: g.reason || '', roles,
      },
    });
  }

  renderGroup(act, data, g) {
    const editing = this.state.edit && this.state.edit.id === g.id;
    return (
      <div key={g.id} className={'BanWindow__group ' + statusClass(g.status)}>
        <div className="BanWindow__groupHead">
          <span className="BanWindow__target">{g.target}</span>
          {!!g.applies && (
            <span className="BanWindow__badge BanWindow__badge--red">
              admins too
            </span>
          )}
          {!!g.local && data.db !== 'off' && (
            <span className="BanWindow__badge"
              title="Made while the database was out of reach">
              kept here
            </span>
          )}
          <span className="BanWindow__groupRoles">
            {g.server
              ? <Chip className="BanWindow__chip--server">Server</Chip>
              : g.roles.map(r => this.renderRoleChip(act, g, r))}
          </span>
        </div>
        <div className="BanWindow__groupMeta">
          {g.length + ' · by ' + g.admin + ' · ' + g.bantime
            + (g.round_id ? ' · round ' + g.round_id : '')}
        </div>
        {g.status === 'active' && !!g.minutes && (
          <div className="BanWindow__progress">
            <div className="BanWindow__progressBar">
              <div className="BanWindow__progressFill"
                style={{ width: Math.round(g.fraction * 100) + '%' }} />
            </div>
            <span className="BanWindow__left">{g.left}</span>
            <span className="BanWindow__muted">ends {g.ends}</span>
          </div>
        )}
        {g.status === 'active' && !g.minutes && (
          <div className="BanWindow__progress">
            <span className="BanWindow__left">Permanent</span>
          </div>
        )}
        {g.status === 'expired' && (
          <div className="BanWindow__progress BanWindow__muted">
            Ended {g.ends}
          </div>
        )}
        {g.status === 'lifted' && (
          <div className="BanWindow__progress BanWindow__muted">
            Lifted by {g.lifted_by} on {g.lifted_at}
          </div>
        )}
        {!editing && (
          <div className="BanWindow__reason">{g.reason}</div>
        )}
        {editing && this.renderEdit(act, data, g)}
        {!editing && (
          <div className="BanWindow__groupActs">
            {g.status === 'active' && (
              <Fragment>
                <Button icon="pen" content="Edit"
                  onClick={() => this.startEdit(g)} />
                <Confirm
                  icon="unlock"
                  content={g.server || g.roles.length === 1
                    ? 'Lift'
                    : 'Lift all'}
                  confirmContent="Lift it?"
                  onClick={() => act('lift_group', { id: g.id })} />
              </Fragment>
            )}
            {!!g.key && (
              <Fragment>
                <Button icon="user" content="Record"
                  title="Their record, on New ban"
                  onClick={() => act('open_player', { key: g.key })} />
                <Button icon="sticky-note" content="Notes"
                  onClick={() => act('open_notes', { key: g.ckey })} />
              </Fragment>
            )}
            {!!g.edits && (
              <Button icon="history" content="Edit log"
                selected={data.log_id === g.id}
                onClick={() => act('ban_log', { id: g.id })} />
            )}
          </div>
        )}
        {data.log_id === g.id && (
          <pre className="BanWindow__log">{data.log_text}</pre>
        )}
      </div>
    );
  }

  renderRoleChip(act, g, r) {
    const armed = this.state.liftArmed === r.id;
    return (
      <Chip
        key={r.id}
        className={'BanWindow__chip--' + r.status
          + (armed ? ' BanWindow__chip--armed' : '')}
        title={r.status === 'active'
          ? (armed ? 'Click again to lift' : 'Click to lift just this role')
          : r.status === 'lifted' ? 'Lifted' : 'Ended'}
        onClick={() => {
          if (r.status !== 'active' || g.roles.length === 1) {
            return;
          }
          if (armed) {
            this.setState({ liftArmed: null });
            act('lift_one', { id: r.id });
            return;
          }
          this.setState({ liftArmed: r.id });
        }}>
        {r.role}
        {armed && ' — lift?'}
      </Chip>
    );
  }

  renderEdit(act, data, g) {
    const edit = this.state.edit;
    const set = patch => this.setState({
      edit: Object.assign({}, edit, patch),
    });
    const picked = Object.keys(edit.roles).filter(r => edit.roles[r]);
    return (
      <div className="BanWindow__edit">
        <div className="BanWindow__field">
          <span className="BanWindow__label">Key</span>
          <Input className="BanWindow__keyBox" value={edit.key}
            onInput={(e, value) => {
              edit.key = value;
            }} />
          <span className="BanWindow__label BanWindow__label--short">IP</span>
          <Input className="BanWindow__ipBox" value={edit.ip}
            onInput={(e, value) => {
              edit.ip = value;
            }} />
          <span className="BanWindow__label BanWindow__label--short">CID</span>
          <Input className="BanWindow__cidBox" value={edit.cid}
            onInput={(e, value) => {
              edit.cid = value;
            }} />
        </div>
        <div className="BanWindow__field BanWindow__field--top">
          <span className="BanWindow__label">Length</span>
          <div className="BanWindow__grow">
            <LengthPicker
              form={edit}
              endsFrom={g.bantime_rt}
              fromStart
              tz={data.tz}
              onChange={set} />
          </div>
        </div>
        <div className="BanWindow__field">
          <span className="BanWindow__label" />
          <Check checked={edit.applies} content="Applies to admins"
            onClick={() => set({ applies: !edit.applies })} />
        </div>
        <div className="BanWindow__field BanWindow__field--top">
          <span className="BanWindow__label">Reason</span>
          <textarea
            className="BanWindow__textarea BanWindow__textarea--short"
            value={edit.reason}
            maxLength={data.reason_max}
            onInput={e => {
              edit.reason = e.target.value;
            }} />
        </div>
        {!g.server && (
          <Fragment>
            <div className="BanWindow__muted BanWindow__small">
              Roles: the ones taken off are lifted; the ones added are banned
              from the same time. {picked.length} picked.
            </div>
            <RoleGrid
              groups={data.role_groups || []}
              picked={edit.roles}
              onToggle={role => {
                const roles = Object.assign({}, edit.roles);
                roles[role] = !roles[role];
                set({ roles });
              }}
              onToggleGroup={(roles, on) => {
                const next = Object.assign({}, edit.roles);
                roles.forEach(role => {
                  next[role] = on;
                });
                set({ roles: next });
              }} />
          </Fragment>
        )}
        <div className="BanWindow__groupActs">
          <Button icon="save" content="Save" color="good"
            onClick={() => {
              this.setState({ edit: null });
              act('edit_save', {
                id: g.id,
                key: edit.key,
                ip: edit.ip,
                cid: edit.cid,
                perm: edit.perm ? 1 : 0,
                length: edit.length,
                unit: edit.unit,
                applies: edit.applies ? 1 : 0,
                reason: edit.reason,
                roles: picked.join(','),
              });
            }} />
          <Button icon="times" content="Cancel"
            onClick={() => this.setState({ edit: null })} />
        </div>
      </div>
    );
  }

  // ----------------------------------------------------------------- Sticky

  renderSticky(act, data) {
    const sticky = data.sticky || [];
    return (
      <div className="BanWindow__bans">
        <div className="BanWindow__bar">
          <Input
            className="BanWindow__keyBox"
            value={this.sticky.ckey}
            placeholder="Key"
            onInput={(e, value) => {
              this.sticky.ckey = value;
            }} />
          <Input
            className="BanWindow__searchBox"
            value={this.sticky.reason}
            placeholder="Reason (shown to them)"
            onInput={(e, value) => {
              this.sticky.reason = value;
            }} />
          <Button icon="plus" content="Sticky ban"
            onClick={() => {
              act('sticky_add', {
                ckey: this.sticky.ckey,
                reason: this.sticky.reason,
              });
              this.sticky = { ckey: '', reason: '' };
              this.redraw();
            }} />
        </div>
        <div className="BanWindow__status BanWindow__muted">
          A sticky ban follows a key onto every key that connects from the
          same computer or address, and catches them too.
        </div>
        <div className="BanWindow__list">
          {sticky.length === 0 && (
            <div className="BanWindow__empty">No sticky bans.</div>
          )}
          {sticky.map(s => (
            <div key={s.ckey}
              className={'BanWindow__group '
                + statusClass(s.timeout ? 'expired' : 'active')}>
              <div className="BanWindow__groupHead">
                <span className="BanWindow__target">{s.ckey}</span>
                {!!s.timeout && (
                  <span className="BanWindow__badge">on timeout</span>
                )}
                <span className="BanWindow__muted">by {s.admin}</span>
              </div>
              {this.stickyEdit && this.stickyEdit.ckey === s.ckey
                ? (
                  <div className="BanWindow__field">
                    <Input
                      className="BanWindow__searchBox"
                      value={this.stickyEdit.reason}
                      onInput={(e, value) => {
                        this.stickyEdit.reason = value;
                      }} />
                    <Button icon="save" content="Save" color="good"
                      onClick={() => {
                        act('sticky', {
                          op: 'edit', ckey: s.ckey,
                          reason: this.stickyEdit.reason,
                        });
                        this.stickyEdit = null;
                        this.redraw();
                      }} />
                    <Button icon="times" content="Cancel"
                      onClick={() => {
                        this.stickyEdit = null;
                        this.redraw();
                      }} />
                  </div>
                )
                : <div className="BanWindow__reason">{s.reason}</div>}
              <div className="BanWindow__recordRow">
                <span className="BanWindow__label">Caught</span>
                {s.caught.length === 0 && (
                  <span className="BanWindow__muted">nobody yet</span>
                )}
                {s.caught.map(c => (
                  <span key={c.key} className="BanWindow__caught">
                    <Chip className={'BanWindow__chip--'
                      + (c.exempt ? 'lifted' : 'active')}>
                      {c.key}{c.exempt ? ' (exempt)' : ''}
                    </Chip>
                    <Confirm
                      content={c.exempt ? 'Unexempt' : 'Exempt'}
                      confirmContent="Sure?"
                      onClick={() => act('sticky', {
                        op: c.exempt ? 'unexempt' : 'exempt',
                        ckey: s.ckey, alt: c.key,
                      })} />
                    <Confirm
                      icon="unlink"
                      title={'Unlink: nothing stops BYOND linking them'
                        + ' again; exempt them for good'}
                      confirmContent="Unlink?"
                      onClick={() => act('sticky', {
                        op: 'remove_alt', ckey: s.ckey, alt: c.key,
                      })} />
                  </span>
                ))}
              </div>
              <div className="BanWindow__groupActs">
                <Button icon="pen" content="Reason"
                  onClick={() => {
                    this.stickyEdit = { ckey: s.ckey, reason: s.reason || '' };
                    this.redraw();
                  }} />
                {data.sticky_db
                  ? (
                    <Confirm
                      icon="pause"
                      content={s.timeout ? 'End timeout' : 'Timeout'}
                      title="Off until next round"
                      onClick={() => act('sticky', {
                        op: s.timeout ? 'untimeout' : 'timeout',
                        ckey: s.ckey,
                      })} />
                  )
                  : (
                    <Confirm
                      icon="undo"
                      content="Revert"
                      title="Back to how it was at round start"
                      onClick={() => act('sticky', {
                        op: 'revert', ckey: s.ckey,
                      })} />
                  )}
                <Confirm
                  icon="trash"
                  color="red"
                  content="Remove"
                  confirmContent="Remove it?"
                  onClick={() => act('sticky', {
                    op: 'remove', ckey: s.ckey,
                  })} />
              </div>
            </div>
          ))}
        </div>
      </div>
    );
  }

  // ------------------------------------------------------------------ Notes

  renderNotes(act, data) {
    const view = data.notes_view;
    const players = data.notes_players || [];
    const searchText = this.typed.notesSearch !== null
      ? this.typed.notesSearch
      : (data.notes_search || '');
    return (
      <div className="BanWindow__notes">
        <div className="BanWindow__notesNav">
          <div className="BanWindow__navButtons">
            <Button icon="clipboard" content="Memos"
              selected={view === 'memos'}
              onClick={() => act('notes_view', { view: 'memos' })} />
            <Button icon="eye" content="Watchlist"
              selected={view === 'watchlist'}
              onClick={() => act('notes_view', { view: 'watchlist' })} />
          </div>
          <Input
            fluid
            value={searchText}
            placeholder="Find a player"
            onInput={(e, value) => {
              this.typed.notesSearch = value;
            }}
            onChange={(e, value) => act('notes_search', { text: value })} />
          <div className="BanWindow__players">
            {players.length === 0 && (
              <div className="BanWindow__muted BanWindow__small">
                No one with notes{searchText ? ' matches' : ' yet'}.
              </div>
            )}
            {players.map(p => (
              <div key={p.ckey}
                className={'BanWindow__player'
                  + (view === 'player' && data.notes_ckey === p.ckey
                    ? ' BanWindow__player--on'
                    : '')}
                onClick={() => act('notes_view', {
                  view: 'player', key: p.ckey,
                })}>
                <span>{p.key}</span>
                <span className="BanWindow__muted">{p.count}</span>
              </div>
            ))}
          </div>
        </div>
        <div className="BanWindow__notesMain">
          {view === 'index' && this.renderNotesIndex(act, data)}
          {view === 'player' && this.renderNotesPlayer(act, data)}
          {view === 'memos' && this.renderNotesKind(act, data, 'memo')}
          {view === 'watchlist'
            && this.renderNotesKind(act, data, 'watchlist entry')}
        </div>
      </div>
    );
  }

  renderNotesIndex(act, data) {
    return (
      <Fragment>
        <div className="BanWindow__notesHead">
          <span className="BanWindow__recordKey">Notes</span>
          <span className="BanWindow__spacer" />
          <Button icon="plus" content="Note for a key"
            onClick={() => act('compose', { kind: 'note' })} />
        </div>
        {this.renderCompose(act, data, true)}
        {!this.compose && (
          <div className="BanWindow__empty">
            Pick a player on the left, or find one.
          </div>
        )}
      </Fragment>
    );
  }

  renderNotesPlayer(act, data) {
    const rows = data.notes_rows || [];
    const sections = [
      ['Messages', rows.filter(r => r.kind === 'message'
        || r.kind === 'message sent')],
      ['Watchlist', rows.filter(r => r.kind === 'watchlist entry')],
      ['Notes', rows.filter(r => r.kind === 'note')],
    ];
    return (
      <Fragment>
        <div className="BanWindow__notesHead">
          <span className="BanWindow__recordKey">{data.notes_key}</span>
          {!!data.notes_online && (
            <span className="BanWindow__presence BanWindow__presence--online">
              Online
            </span>
          )}
          <span className="BanWindow__spacer" />
          <Button icon="plus" content="Note"
            onClick={() => act('compose', { kind: 'note' })} />
          <Button icon="envelope" content="Message"
            title="Shown to them when they next connect"
            onClick={() => act('compose', { kind: 'message' })} />
          <Button icon="eye" content="Watchlist"
            title="Admins are told when they connect"
            onClick={() => act('compose', { kind: 'watchlist entry' })} />
          {!!data.can_ban && (
            <Button icon="gavel" content="Ban"
              onClick={() => act('open_player', { key: data.notes_key })} />
          )}
        </div>
        {this.renderCompose(act, data, false)}
        {rows.length === 0 && (
          <div className="BanWindow__empty">Nothing for them.</div>
        )}
        {sections.filter(s => s[1].length).map(s => (
          <Fragment key={s[0]}>
            <div className="BanWindow__recordSection">
              {s[0]}
              <span className="BanWindow__muted">{' '}{s[1].length}</span>
            </div>
            {s[1].map(row => this.renderNote(act, data, row, false))}
          </Fragment>
        ))}
      </Fragment>
    );
  }

  renderNotesKind(act, data, kind) {
    const rows = data.notes_rows || [];
    const memo = kind === 'memo';
    return (
      <Fragment>
        <div className="BanWindow__notesHead">
          <span className="BanWindow__recordKey">
            {memo ? 'Memos' : 'Watchlist'}
          </span>
          <span className="BanWindow__muted">
            {memo
              ? 'shown to admins when they connect'
              : 'admins are told when these players connect'}
          </span>
          <span className="BanWindow__spacer" />
          {!memo && (
            <Check
              checked={data.notes_online_only}
              content="Online only"
              onClick={() => act('notes_online_only')} />
          )}
          <Button icon="plus" content={memo ? 'Memo' : 'Entry'}
            onClick={() => act('compose', { kind })} />
        </div>
        {this.renderCompose(act, data, !memo)}
        {rows.length === 0 && (
          <div className="BanWindow__empty">None.</div>
        )}
        {rows.map(row => this.renderNote(act, data, row, !memo))}
      </Fragment>
    );
  }

  renderCompose(act, data, needsKey) {
    const c = this.compose;
    if (!c) {
      return null;
    }
    const set = patch => {
      Object.assign(c, patch);
      this.redraw();
    };
    const playerKind = c.kind !== 'memo';
    return (
      <div className="BanWindow__compose">
        <div className="BanWindow__field">
          <span className="BanWindow__label">
            {KIND_NAMES[c.kind] || c.kind}
          </span>
          {playerKind && needsKey && (
            <Input
              className="BanWindow__keyBox"
              value={c.key}
              placeholder="Key"
              onInput={(e, value) => {
                c.key = value;
              }} />
          )}
          {c.kind === 'note' && SEVERITIES.map(s => (
            <Button
              key={s}
              content={SEVERITY_NAMES[s]}
              className={'BanWindow__sev BanWindow__sev--' + s}
              selected={c.severity === s}
              onClick={() => set({ severity: s })} />
          ))}
          <span className="BanWindow__spacer" />
          {(c.kind === 'note' || c.kind === 'message') && (
            <Check checked={c.secret} content="Secret"
              title="Players can't see secret ones in their own notes"
              onClick={() => set({ secret: !c.secret })} />
          )}
          <span className="BanWindow__muted BanWindow__hint">Shows for</span>
          <Select
            value={c.expiry}
            options={Object.keys(data.expiry_choices || {})
              .map(k => [k, k])}
            onChange={value => set({ expiry: value })} />
        </div>
        <textarea
          className="BanWindow__textarea"
          value={c.text}
          maxLength={data.note_max}
          placeholder={c.kind === 'message'
            ? 'They see this when they next connect'
            : 'Write it here'}
          onInput={e => {
            c.text = e.target.value;
          }} />
        <div className="BanWindow__groupActs">
          <Button icon="save" content="Add" color="good"
            onClick={() => act('note_add', {
              kind: c.kind,
              key: needsKey ? c.key : data.notes_ckey,
              text: c.text,
              secret: c.secret ? 1 : 0,
              severity: c.severity,
              expiry: c.expiry,
            })} />
          <Button icon="times" content="Cancel"
            onClick={() => act('compose', {})} />
        </div>
      </div>
    );
  }

  renderNote(act, data, row, showTarget) {
    const editing = this.noteEdit && this.noteEdit.id === row.id;
    let opacity = 1;
    if (row.kind === 'note' && data.stale_days > data.fresh_days
      && row.age_days > data.fresh_days) {
      opacity = Math.max(0.35, 1 - (row.age_days - data.fresh_days)
        / (data.stale_days - data.fresh_days) * 0.65);
    }
    return (
      <div key={row.id}
        className={'BanWindow__note BanWindow__note--'
          + (row.severity || 'unset')}
        style={{ opacity: opacity }}>
        <div className="BanWindow__noteHead">
          {showTarget && (
            <span className="BanWindow__noteTarget"
              onClick={() => act('notes_view', {
                view: 'player', key: row.target_ckey,
              })}>
              {row.target_key}
              {!!row.online && (
                <span className="BanWindow__badge BanWindow__badge--green">
                  online
                </span>
              )}
            </span>
          )}
          {!!row.severity && (
            <span className={'BanWindow__sevTag BanWindow__sev--'
              + row.severity}>
              {SEVERITY_NAMES[row.severity]}
            </span>
          )}
          {row.kind === 'message sent' && (
            <span className="BanWindow__badge">read</span>
          )}
          {!!row.secret && <span className="BanWindow__badge">secret</span>}
          {!!row.expires && (
            <span className="BanWindow__badge">
              until {row.expires}
            </span>
          )}
          {!!row.local && data.db !== 'off' && (
            <span className="BanWindow__badge"
              title="Made while the database was out of reach">
              kept here
            </span>
          )}
          <span className="BanWindow__muted">
            {row.timestamp + ' · ' + row.admin_key
              + (row.server ? ' · ' + row.server : '')
              + (row.round_id ? ' · round ' + row.round_id : '')}
          </span>
        </div>
        {editing
          ? (
            <Fragment>
              <textarea
                className="BanWindow__textarea BanWindow__textarea--short"
                value={this.noteEdit.text}
                maxLength={data.note_max}
                onInput={e => {
                  this.noteEdit.text = e.target.value;
                }} />
              <div className="BanWindow__groupActs">
                <Button icon="save" content="Save" color="good"
                  onClick={() => {
                    act('note_text', {
                      id: row.id, text: this.noteEdit.text,
                    });
                    this.noteEdit = null;
                    this.redraw();
                  }} />
                <Button icon="times" content="Cancel"
                  onClick={() => {
                    this.noteEdit = null;
                    this.redraw();
                  }} />
              </div>
            </Fragment>
          )
          : <div className="BanWindow__noteText">{row.text}</div>}
        {!editing && (
          <div className="BanWindow__noteActs">
            {row.kind !== 'message sent' && (
              <Button icon="pen" content="Edit"
                onClick={() => {
                  this.noteEdit = { id: row.id, text: row.text };
                  this.redraw();
                }} />
            )}
            {row.kind === 'note' && (
              <Select
                value={row.severity || ''}
                options={[['', 'Severity']].concat(SEVERITIES
                  .map(s => [s, SEVERITY_NAMES[s]]))}
                onChange={value => act('note_severity', {
                  id: row.id, severity: value,
                })} />
            )}
            {row.kind === 'note' && (
              <Button
                icon={row.secret ? 'eye-slash' : 'eye'}
                content={row.secret ? 'Secret' : 'Not secret'}
                title="Toggle: players can't see secret notes"
                onClick={() => act('note_secret', { id: row.id })} />
            )}
            <Select
              value=""
              options={[['', 'Expiry']].concat(Object.keys(
                data.expiry_choices || {}).map(k => [k,
                k === 'Never' ? 'Never expires' : k + ' from now']))}
              onChange={value => value && act('note_expiry', {
                id: row.id, expiry: value,
              })} />
            <Confirm icon="trash" content="Delete" confirmContent="Delete?"
              onClick={() => act('note_delete', { id: row.id })} />
            {!!row.edits && (
              <Button icon="history" content="Edit log"
                selected={data.note_log_id === row.id}
                onClick={() => act('note_log', { id: row.id })} />
            )}
          </div>
        )}
        {data.note_log_id === row.id && (
          <pre className="BanWindow__log">{data.note_log_text}</pre>
        )}
      </div>
    );
  }
}
