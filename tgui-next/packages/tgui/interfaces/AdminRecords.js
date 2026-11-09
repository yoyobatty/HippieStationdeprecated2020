// hippie -- admin records (admin_records_tgui.dm): the Permissions Panel,
// an edit history, related accounts and a player's own notes.
import { decodeHtmlEntities } from 'common/string';
import { Component, Fragment } from 'inferno';
import { useBackend } from '../backend';
import { Box, Button, Dropdown, Icon, Input, NoticeBox, Section, Tabs } from '../components';

const text = value => decodeHtmlEntities(String(value || ''));

// One flag as a chip: held, denied, or editable
const FlagChip = props => {
  const { name, kind } = props;
  return (
    <span className={'AdminRecords__flag AdminRecords__flag--' + kind}>
      {kind === 'denied' ? '-' : kind === 'edit' ? '*' : ''}{name}
    </span>
  );
};

const RightsChips = props => {
  const { flags, include, exclude, can_edit, showEdit } = props;
  const held = flags.filter(f => (include & f.bit) && !(exclude & f.bit));
  const denied = flags.filter(f => exclude & f.bit);
  const edit = showEdit ? flags.filter(f => can_edit & f.bit) : [];
  if (!held.length && !denied.length && !edit.length) {
    return <span className="AdminRecords__muted">None</span>;
  }
  return (
    <Fragment>
      {held.map(f => <FlagChip key={f.name} name={f.name} kind="held" />)}
      {denied.map(f => <FlagChip key={f.name} name={f.name} kind="denied" />)}
      {edit.map(f => <FlagChip key={f.name} name={f.name} kind="edit" />)}
    </Fragment>
  );
};

// ---------------------------------------------------------------------------
// The Permissions Panel
// ---------------------------------------------------------------------------

const FLAG_COLUMNS = [
  ['include', 'Has'],
  ['exclude', 'Denied'],
  ['can_edit', 'Can edit'],
];

class RankFlagEditor extends Component {
  constructor(props) {
    super(props);
    const { rank } = props;
    this.state = {
      include: rank.include,
      exclude: rank.exclude,
      can_edit: rank.can_edit,
    };
  }

  render() {
    const { rank, flags, myCanEdit, act } = this.props;
    const { include, exclude, can_edit } = this.state;
    const changed = include !== rank.include
      || exclude !== rank.exclude
      || can_edit !== rank.can_edit;
    const editable = rank.editable && !rank.protected;
    return (
      <Box className="AdminRecords__editor">
        <table className="AdminRecords__flagGrid">
          <thead>
            <tr>
              <th />
              {FLAG_COLUMNS.map(([key, label]) => <th key={key}>{label}</th>)}
            </tr>
          </thead>
          <tbody>
            {flags.map(f => {
              const mine = !!(myCanEdit & f.bit);
              return (
                <tr key={f.name}
                  className={mine ? null : 'AdminRecords__locked'}>
                  <td>{f.name}</td>
                  {FLAG_COLUMNS.map(([key]) => {
                    const on = !!(this.state[key] & f.bit);
                    return (
                      <td key={key}>
                        <Button
                          icon={on ? 'check-square' : 'square-o'}
                          color={on
                            ? (key === 'exclude' ? 'bad' : 'good')
                            : 'transparent'}
                          disabled={!editable || !mine}
                          onClick={() => this.setState(prev => ({
                            [key]: prev[key] ^ f.bit,
                          }))} />
                      </td>
                    );
                  })}
                </tr>
              );
            })}
          </tbody>
        </table>
        <Box mt={1}>
          <Button icon="save" content="Save flags" color="good"
            disabled={!changed || !editable}
            onClick={() => act('set_flags', {
              rank: rank.name,
              include,
              exclude,
              can_edit,
            })} />
          <Button icon="undo" content="Reset" disabled={!changed}
            onClick={() => this.setState({
              include: rank.include,
              exclude: rank.exclude,
              can_edit: rank.can_edit,
            })} />
          <Box inline ml={1} className="AdminRecords__muted">
            Applies to everyone holding {rank.name}.
          </Box>
        </Box>
      </Box>
    );
  }
}

const AdminLine = props => {
  const { admin: a, dbranks, act } = props;
  return (
    <Box className="AdminRecords__admin">
      <span className={'AdminRecords__dot'
        + (a.online ? ' AdminRecords__dot--on' : '')} />
      <span className="AdminRecords__key">{a.key}</span>
      {!!a.me && <span className="AdminRecords__muted">(you)</span>}
      {!!a.protected && <Icon name="lock" color="label" />}
      {a.deadmined
        ? <span className="AdminRecords__state">Deadmin</span>
        : (
          <span className="AdminRecords__state AdminRecords__state--on">
            Active
          </span>
        )}
      <Box inline className="AdminRecords__manageButtons">
        <Button icon="id-badge" content="Change rank"
          disabled={!a.editable || a.protected}
          onClick={() => act('rank', { ckey: a.ckey })} />
        {a.deadmined ? (
          <Button icon="user-check" content="Readmin"
            disabled={!a.editable}
            onClick={() => act('activate', { ckey: a.ckey })} />
        ) : (
          <Button icon="user-slash" content="Deadmin"
            disabled={!a.editable}
            onClick={() => act('deactivate', { ckey: a.ckey })} />
        )}
        {!!dbranks && (
          <Button icon="sync" tooltip="Sync rank to DB"
            onClick={() => act('sync', { ckey: a.ckey })} />
        )}
        <Button icon="user-times" color="bad"
          tooltip="Remove" disabled={!a.editable || a.me}
          onClick={() => act('remove', { ckey: a.ckey })} />
      </Box>
    </Box>
  );
};

// How many flags a rank holds, for putting the biggest ranks first
const heldCount = (flags, rank) => flags
  .filter(f => (rank.include & f.bit) && !(rank.exclude & f.bit)).length;

class PermissionsAdmins extends Component {
  constructor() {
    super();
    this.state = { search: '', open: null, newKey: '' };
  }

  render() {
    const { data, act } = this.props;
    const flags = data.flags || [];
    const query = this.state.search.toLowerCase();
    const admins = (data.admins || [])
      .filter(a => !query
        || (a.key + ' ' + a.rank).toLowerCase().includes(query))
      .sort((a, b) => a.key.toLowerCase() < b.key.toLowerCase() ? -1 : 1);
    const ranks = (data.ranks || [])
      .filter(r => admins.some(a => a.rank === r.name))
      .sort((a, b) => (heldCount(flags, b) - heldCount(flags, a))
        || (a.name < b.name ? -1 : 1));
    return (
      <Fragment>
        <Box mb={1} className="AdminRecords__bar">
          <Input placeholder="Search keys and ranks..." width="260px"
            value={this.state.search}
            onInput={(e, value) => this.setState({ search: value })} />
          <Box inline ml={2}>
            <Input placeholder="New admin's key" width="160px"
              value={this.state.newKey}
              onInput={(e, value) => this.setState({ newKey: value })} />
            <Button icon="user-plus" content="Add admin"
              disabled={!this.state.newKey.trim()}
              onClick={() => {
                act('add', { key: this.state.newKey });
                this.setState({ newKey: '' });
              }} />
          </Box>
        </Box>
        {ranks.length === 0 && <Box color="label">Nobody matches.</Box>}
        {ranks.map(r => {
          const open = this.state.open === r.name;
          const holders = admins.filter(a => a.rank === r.name);
          return (
            <Box key={r.name} className={'AdminRecords__rankCard'
              + (open ? ' AdminRecords__rankCard--open' : '')}>
              <Box className="AdminRecords__rankHead"
                onClick={() => this.setState({ open: open ? null : r.name })}>
                <Icon name={open ? 'chevron-down' : 'chevron-right'}
                  color="label" />
                <span className="AdminRecords__rankName">{r.name}</span>
                {!!r.protected && <Icon name="lock" color="label" />}
                <span className="AdminRecords__muted">
                  {holders.length + ' admin'
                    + (holders.length === 1 ? '' : 's')}
                </span>
                <Box inline className="AdminRecords__rights">
                  <RightsChips flags={flags} include={r.include}
                    exclude={r.exclude} />
                </Box>
              </Box>
              {open && (
                <RankFlagEditor
                  key={r.name + ':' + r.include + ':' + r.exclude
                    + ':' + r.can_edit}
                  rank={r} flags={flags}
                  myCanEdit={data.my_can_edit} act={act} />
              )}
              {holders.map(a => (
                <AdminLine key={a.ckey} admin={a} dbranks={data.dbranks}
                  act={act} />
              ))}
            </Box>
          );
        })}
      </Fragment>
    );
  }
}

const OPERATION_COLORS = {
  'add admin': 'good',
  'remove admin': 'bad',
  'change admin rank': 'info',
  'add rank': 'good',
  'remove rank': 'bad',
  'change rank flags': 'average',
};

class PermissionsLog extends Component {
  constructor(props) {
    super(props);
    this.state = { target: props.data.log_target || '' };
  }

  render() {
    const { data, act } = this.props;
    const rows = data.log || [];
    const operation = data.log_operation || '';
    const search = op => act('log_filter', {
      target: this.state.target,
      operation: op,
    });
    return (
      <Fragment>
        <Box mb={1} className="AdminRecords__bar">
          <Input placeholder="Target (ckey or rank)" width="200px"
            value={this.state.target}
            onInput={(e, value) => this.setState({ target: value })}
            onChange={() => search(operation)} />
          <Box inline ml={1}>
            <Dropdown width="180px"
              options={['Any operation'].concat(data.operations || [])}
              selected={operation || 'Any operation'}
              onSelected={value => search(
                value === 'Any operation' ? '' : value)} />
          </Box>
          <Button ml={1} icon="search" content="Search"
            onClick={() => search(operation)} />
          <Button icon="times" content="Clear"
            disabled={!this.state.target && !operation}
            onClick={() => {
              this.setState({ target: '' });
              act('log_filter', { target: '', operation: '' });
            }} />
        </Box>
        {rows.length === 0 && <Box color="label">No entries.</Box>}
        {rows.map((row, i) => (
          <Box key={i} className="AdminRecords__logEntry">
            <Box className="AdminRecords__logHead">
              <span className={'AdminRecords__op AdminRecords__op--'
                + (OPERATION_COLORS[row.operation] || 'info')}>
                {row.operation}
              </span>
              <b>{text(row.target)}</b>
              <span className="AdminRecords__muted">
                {' by ' + text(row.admin) + ' · ' + row.when
                  + ' · round ' + row.round}
              </span>
            </Box>
            <Box className="AdminRecords__logText">{text(row.log)}</Box>
          </Box>
        ))}
        {data.log_pages > 1 && (
          <Box mt={1} textAlign="center">
            <Button icon="chevron-left" disabled={data.log_page <= 0}
              onClick={() => act('log_page', { page: data.log_page - 1 })} />
            <Box inline mx={1}>
              Page {data.log_page + 1} of {data.log_pages}
            </Box>
            <Button icon="chevron-right"
              disabled={data.log_page >= data.log_pages - 1}
              onClick={() => act('log_page', { page: data.log_page + 1 })} />
          </Box>
        )}
      </Fragment>
    );
  }
}

const PermissionsManage = props => {
  const { data, act } = props;
  const flags = data.flags || [];
  const bad = data.bad_ranks || [];
  const unused = data.unused_ranks || [];
  return (
    <Fragment>
      <Section title={'Admins on a missing rank (' + bad.length + ')'}>
        {bad.length === 0 && <Box color="label">None.</Box>}
        {bad.map(row => (
          <Box key={row.key} className="AdminRecords__manageRow">
            <b>{text(row.key)}</b>
            <span className="AdminRecords__missing">{text(row.rank)}</span>
            <Box inline className="AdminRecords__manageButtons">
              <Button icon="id-badge" content="Change rank"
                onClick={() => act('manage_change', { key: row.key })} />
              <Button icon="user-times" content="Remove" color="bad"
                onClick={() => act('manage_remove', { key: row.key })} />
            </Box>
          </Box>
        ))}
      </Section>
      <Section title={'Ranks nobody holds (' + unused.length + ')'}>
        {unused.length === 0 && <Box color="label">None.</Box>}
        {unused.map(row => (
          <Box key={row.rank} className="AdminRecords__manageRow">
            <b>{text(row.rank)}</b>
            <Box inline className="AdminRecords__rights">
              <RightsChips flags={flags} include={row.include}
                exclude={row.exclude} can_edit={row.can_edit} showEdit />
            </Box>
            <Box inline className="AdminRecords__manageButtons">
              <Button icon="trash" content="Remove" color="bad"
                onClick={() => act('manage_remove_rank',
                  { rank: row.rank })} />
            </Box>
          </Box>
        ))}
      </Section>
    </Fragment>
  );
};

export const AdminPermissions = props => {
  const { act, data } = useBackend(props);
  const tab = data.tab;
  const TABS = [
    ['admins', 'Admins (' + (data.admins || []).length + ')'],
    ['log', 'Log'],
    ['manage', 'Rank checks'],
  ];
  return (
    <Fragment>
      <Tabs>
        {TABS.map(([key, label]) => (
          <Tabs.Tab key={key} selected={tab === key} label={label}
            onClick={() => act('tab', { tab: key })} />
        ))}
      </Tabs>
      {tab !== 'admins' && (
        <Box mb={1} textAlign="right">
          <Button icon="sync" content="Refresh"
            onClick={() => act('refresh')} />
        </Box>
      )}
      {tab !== 'admins' && !!data.db_error && (
        <NoticeBox>{data.db_error}</NoticeBox>
      )}
      {tab === 'admins' && <PermissionsAdmins data={data} act={act} />}
      {tab === 'log' && !data.db_error && (
        <PermissionsLog data={data} act={act} />
      )}
      {tab === 'manage' && !data.db_error && (
        <PermissionsManage data={data} act={act} />
      )}
    </Fragment>
  );
};

// ---------------------------------------------------------------------------
// An edit history
// ---------------------------------------------------------------------------

export const AdminEditLog = props => {
  const { data } = useBackend(props);
  const entries = data.entries || [];
  return (
    <Fragment>
      <Box className="AdminRecords__editTitle">
        <span className="AdminRecords__muted">{data.what} · </span>
        {text(data.about)}
      </Box>
      {entries.length === 0 && <Box color="label">No edits.</Box>}
      {entries.map((e, i) => (
        <Box key={i} className="AdminRecords__edit">
          <Box className="AdminRecords__editHead">
            <Icon name="pen" mr={1} color="label" />
            {e.heading}
          </Box>
          {e.old !== null && e.new !== null && (
            <Fragment>
              <Box className="AdminRecords__before">{e.old}</Box>
              <Box className="AdminRecords__after">{e.new}</Box>
            </Fragment>
          )}
          {!!e.body && <Box className="AdminRecords__logText">{e.body}</Box>}
        </Box>
      ))}
    </Fragment>
  );
};

// ---------------------------------------------------------------------------
// Related accounts
// ---------------------------------------------------------------------------

export const AdminRelatedAccounts = props => {
  const { act, data } = useBackend(props);
  const by = data.by;
  const rows = (by === 'ip' ? data.ip : data.cid) || [];
  return (
    <Fragment>
      <Box className="AdminRecords__editTitle">
        <span className="AdminRecords__muted">Sharing with </span>
        {text(data.key)}
      </Box>
      <Tabs>
        <Tabs.Tab selected={by === 'cid'}
          label={'Computer ID (' + (data.cid || []).length + ')'}
          onClick={() => act('by', { by: 'cid' })} />
        <Tabs.Tab selected={by === 'ip'}
          label={'IP (' + (data.ip || []).length + ')'}
          onClick={() => act('by', { by: 'ip' })} />
      </Tabs>
      {rows.length === 0 && <Box color="label">None.</Box>}
      {rows.map(row => (
        <Box key={row.ckey} className="AdminRecords__manageRow">
          <span className={'AdminRecords__dot'
            + (row.online ? ' AdminRecords__dot--on' : '')} />
          <b>{text(row.key)}</b>
          {!!row.admin && <span className="AdminRecords__tag">Admin</span>}
          <Box inline className="AdminRecords__manageButtons">
            <Button icon="sticky-note" content="Notes"
              onClick={() => act('notes', { ckey: row.ckey })} />
            <Button icon="gavel" content="Bans"
              onClick={() => act('bans', { ckey: row.ckey })} />
            <Button icon="user-cog" content="PP" disabled={!row.online}
              onClick={() => act('pp', { ckey: row.ckey })} />
          </Box>
        </Box>
      ))}
    </Fragment>
  );
};

// ---------------------------------------------------------------------------
// A player's notes
// ---------------------------------------------------------------------------

const NOTE_SECTIONS = [
  ['messages', 'Messages', 'envelope'],
  ['watchlist', 'Watchlist', 'eye'],
  ['notes', 'Notes', 'sticky-note'],
];

export const PlayerNotes = props => {
  const { data } = useBackend(props);
  const rows = data.rows || [];
  return (
    <Fragment>
      <Box className="AdminRecords__editTitle">
        <span className="AdminRecords__muted">Admin remarks · </span>
        {text(data.key)}
      </Box>
      {rows.length === 0 && (
        <Box color="label" mt={2} textAlign="center">Nothing here.</Box>
      )}
      {NOTE_SECTIONS.map(([key, label, icon]) => {
        const shown = rows.filter(r => r.section === key);
        if (!shown.length) {
          return null;
        }
        return (
          <Section key={key}
            title={<Fragment><Icon name={icon} mr={1} />{label}</Fragment>}>
            {shown.map((r, i) => (
              <Box key={i} className="AdminRecords__note">
                <Box className="AdminRecords__noteHead">
                  {r.when}
                  <span className="AdminRecords__muted">
                    {' · ' + text(r.admin)
                      + (r.server ? ' · ' + text(r.server) : '')}
                  </span>
                  {!!r.severity && r.severity !== 'none' && (
                    <span className={'AdminRecords__severity '
                      + 'AdminRecords__severity--' + r.severity}>
                      {r.severity}
                    </span>
                  )}
                  {!!r.expires && (
                    <span className="AdminRecords__muted">
                      {' · until ' + r.expires}
                    </span>
                  )}
                </Box>
                <Box className="AdminRecords__noteText">{text(r.text)}</Box>
              </Box>
            ))}
          </Section>
        );
      })}
    </Fragment>
  );
};
