import { decodeHtmlEntities } from 'common/string';
import { Component, Fragment } from 'inferno';
import { useBackend } from '../backend';
import { Box, Button, Icon, Input, LabeledList, NoticeBox, Section, Tabs } from '../components';

// hippie -- admin panels designed for tgui: the Player Panel, the Game
// Panel, Create Antagonist and Station Goals. Data and actions from
// hippiestation/code/modules/admin/admin_panels_tgui.dm.

const text = value => decodeHtmlEntities(String(value || ''));

const STATES = [
  ['all', 'All'],
  ['alive', 'Alive'],
  ['dead', 'Dead'],
  ['ghost', 'Ghosts'],
  ['lobby', 'Lobby'],
  ['antag', 'Antagonists'],
];

const COLUMNS = [
  ['name', 'Name'],
  ['real_name', 'Real name'],
  ['key', 'Key'],
  ['job', 'Job'],
  ['state', 'State'],
  ['antag', 'Antag'],
  ['client', 'Online'],
  ['ip', 'IP'],
];

const STATE_NAMES = {
  alive: 'Alive',
  dead: 'Dead',
  ghost: 'Ghost',
  lobby: 'Lobby',
};

export class AdminPlayers extends Component {
  constructor() {
    super();
    this.state = { search: '', tab: 'all', open: null, sort: 'name',
      desc: false };
  }

  render() {
    const { act, data } = useBackend(this.props);
    const players = data.players || [];
    const query = this.state.search.toLowerCase();
    const tab = this.state.tab;
    const counts = {};
    for (let [key] of STATES) {
      counts[key] = players.filter(p => key === 'all'
        || (key === 'antag' ? p.antag : p.state === key)).length;
    }
    const shown = players.filter(p => {
      if (tab !== 'all' && (tab === 'antag' ? !p.antag : p.state !== tab)) {
        return false;
      }
      if (!query) {
        return true;
      }
      return [p.name, p.real_name, p.key, p.job]
        .concat(p.old_names || [])
        .some(v => String(v || '').toLowerCase().includes(query));
    });
    const { sort, desc } = this.state;
    const value = (p, key) => {
      // DM sends its booleans as 0/1, so numbers sort as numbers
      const v = p[key];
      if (typeof v === 'number' || typeof v === 'boolean') {
        return v ? 1 : 0;
      }
      return String(v || '').toLowerCase();
    };
    const sorted = shown.slice().sort((a, b) => {
      const x = value(a, sort);
      const y = value(b, sort);
      const order = x < y ? -1 : x > y ? 1 : 0;
      return desc ? -order : order;
    });
    return (
      <Fragment>
        <Box mb={1} className="AdminPanels__bar">
          <Input fluid placeholder="Search names, keys, jobs, old names..."
            value={this.state.search}
            onInput={(e, value) => this.setState({ search: value })} />
        </Box>
        <Tabs>
          {STATES.map(([key, label]) => (
            <Tabs.Tab key={key} selected={tab === key}
              label={label + ' (' + counts[key] + ')'}
              onClick={() => this.setState({ tab: key })} />
          ))}
        </Tabs>
        <Box mb={1}>
          <Button icon="user-secret" content="Check antagonists"
            onClick={() => act('check_antagonists')} />
          <Button icon="door-open" content="Kick everyone in the lobby"
            onClick={() => act('kick_lobby', { afk: 0 })} />
          <Button icon="bed" content="Kick the lobby's AFKers"
            onClick={() => act('kick_lobby', { afk: 1 })} />
        </Box>
        {shown.length === 0 && <Box color="label">Nobody matches.</Box>}
        {shown.length > 0 && (
          <table className="AdminPanels__table">
            <thead>
              <tr>
                {COLUMNS.map(([key, label]) => (
                  <th key={key}
                    className={sort === key ? 'AdminPanels__sorted' : null}
                    onClick={() => this.setState({
                      sort: key,
                      desc: sort === key ? !desc : false,
                    })}>
                    {label}
                    {sort === key && (
                      <Icon name={desc ? 'caret-down' : 'caret-up'} ml={0.5} />
                    )}
                  </th>
                ))}
                <th />
              </tr>
            </thead>
            <tbody>
              {sorted.map(p => {
                const open = this.state.open === p.ref;
                const go = action => () => act(action, { ref: p.ref });
                return (
                  <Fragment key={p.ref}>
                    <tr
                      className={'AdminPanels__row'
                        + (p.antag ? ' AdminPanels__row--antag' : '')
                        + (open ? ' AdminPanels__row--open' : '')}
                      onClick={() => this.setState({
                        open: open ? null : p.ref,
                      })}>
                      <td className="AdminPanels__playerName">
                        {text(p.name)}
                      </td>
                      <td>{text(p.real_name)}</td>
                      <td className="AdminPanels__muted">{p.key}</td>
                      <td className="AdminPanels__job">{p.job}</td>
                      <td>
                        <span className={'AdminPanels__dot AdminPanels__dot--'
                          + p.state} />
                        {' ' + STATE_NAMES[p.state]}
                      </td>
                      <td>
                        {!!p.antag && (
                          <span className="AdminPanels__antag">Antag</span>
                        )}
                      </td>
                      <td>
                        {p.client
                          ? <Icon name="plug" color="good" />
                          : <Icon name="unlink" color="label" />}
                      </td>
                      <td className="AdminPanels__muted">{p.ip}</td>
                      <td className="AdminPanels__rowActions"
                        onClick={e => e.stopPropagation()}>
                        <Button content="PP" onClick={go('pp')} />
                        <Button content="VV" onClick={go('vv')} />
                        <Button content="PM" onClick={go('pm')} />
                        <Button content="FLW" onClick={go('flw')} />
                      </td>
                    </tr>
                    {open && (
                      <tr className="AdminPanels__openRow">
                        <td colSpan={9}>
                          <Box mb={0.5}>
                            <Button icon="user-cog" content="Player panel"
                              onClick={go('pp')} />
                            <Button icon="sticky-note"
                              content="Notes, messages, watchlist"
                              onClick={go('notes')} />
                            <Button icon="code" content="VV"
                              onClick={go('vv')} />
                            {!!p.has_mind && (
                              <Button icon="user-secret"
                                content="Traitor panel" onClick={go('tp')} />
                            )}
                            {!!p.cyborg && (
                              <Button icon="robot" content="Borg panel"
                                onClick={go('bp')} />
                            )}
                            <Button icon="comment" content="PM"
                              onClick={go('pm')} />
                            <Button icon="comment-dots"
                              content="Subtle message" onClick={go('sm')} />
                            <Button icon="eye" content="Follow"
                              onClick={go('flw')} />
                            <Button icon="list" content="Logs"
                              onClick={go('logs')} />
                          </Box>
                          <Box className="AdminPanels__muted">
                            Old names:{' '}
                            {(p.old_names || []).length
                              ? p.old_names.map(text).join(', ')
                              : 'none'}
                          </Box>
                        </td>
                      </tr>
                    )}
                  </Fragment>
                );
              })}
            </tbody>
          </table>
        )}
      </Fragment>
    );
  }
}

export const AdminGamePanel = props => {
  const { act, data } = useBackend(props);
  const modes = data.modes || [];
  if (data.page === 'mode' || data.page === 'secret') {
    const secret = data.page === 'secret';
    const options = modes.concat(secret
      ? [{ id: 'secret', name: 'Random (default)' }]
      : [{ id: 'secret', name: 'Secret' }, { id: 'random', name: 'Random' }]);
    return (
      <Section
        title={secret ? 'Force secret to be' : 'Change game mode'}
        buttons={(
          <Button icon="arrow-left" content="Back"
            onClick={() => act('page', { page: null })} />
        )}>
        <Box color="label" mb={1}>
          {secret
            ? 'Players still see secret. Now: ' + (data.secret_force || '-')
            : 'Now: ' + data.master_mode}
        </Box>
        {options.map(mode => (
          <Button
            key={mode.id}
            fluid
            content={mode.name}
            selected={secret
              ? data.secret_force === mode.id
              : data.master_mode === mode.id}
            onClick={() => act(secret ? 'force_secret' : 'set_mode',
              { mode: mode.id })} />
        ))}
      </Section>
    );
  }
  const dynamic = data.master_mode === 'dynamic';
  return (
    <Fragment>
      <Section title="Game mode">
        <LabeledList>
          <LabeledList.Item label="Mode">
            {data.master_mode}{' '}
            <Button icon="exchange-alt" content="Change"
              onClick={() => act('page', { page: 'mode' })} />
          </LabeledList.Item>
          {data.master_mode === 'secret' && (
            <LabeledList.Item label="Secret">
              {data.secret_force || 'random'}{' '}
              <Button icon="user-secret" content="Force" disabled={data.started}
                onClick={() => act('page', { page: 'secret' })} />
            </LabeledList.Item>
          )}
        </LabeledList>
        {!!data.in_progress && (
          <Button mt={1} icon="dice" content="Game mode panel"
            onClick={() => act('link', { link: 'gamemode_panel' })} />
        )}
      </Section>
      {dynamic && (
        <Section title="Dynamic">
          {!!data.pregame && (
            <Fragment>
              <Button icon="plus" content="Force roundstart rulesets"
                onClick={() => act('link', { link: 'f_dynamic_roundstart' })} />
              {(data.dynamic_forced || []).map(rule => (
                <Button key={rule.ref} icon="times" content={rule.name}
                  onClick={() => act('remove_ruleset', { ref: rule.ref })} />
              ))}
              {(data.dynamic_forced || []).length > 0 && (
                <Button content="Clear rulesets"
                  onClick={() => act('link',
                    { link: 'f_dynamic_roundstart_clear' })} />
              )}
              <Button icon="sliders-h" content="Dynamic options"
                onClick={() => act('link', { link: 'f_dynamic_options' })} />
            </Fragment>
          )}
          {!!data.in_progress && (
            <Fragment>
              <Button icon="user-plus" content="Force next latejoin ruleset"
                onClick={() => act('link', { link: 'f_dynamic_latejoin' })} />
              {!!data.dynamic_latejoin && (
                <Button icon="times" content={data.dynamic_latejoin}
                  onClick={() => act('link',
                    { link: 'f_dynamic_latejoin_clear' })} />
              )}
              <Button icon="bolt" content="Execute midround ruleset"
                color="bad"
                onClick={() => act('link', { link: 'f_dynamic_midround' })} />
            </Fragment>
          )}
        </Section>
      )}
      <Section title="Create">
        <Button icon="cube" content="Object"
          onClick={() => act('link', { link: 'create_object' })} />
        <Button icon="bolt" content="Quick object"
          onClick={() => act('link', { link: 'quick_create_object' })} />
        <Button icon="th" content="Turf"
          onClick={() => act('link', { link: 'create_turf' })} />
        <Button icon="paw" content="Mob"
          onClick={() => act('link', { link: 'create_mob' })} />
        {!!data.marked && (
          <Box mt={1}>
            <Button
              icon="clone"
              content={'Duplicate marked: ' + text(data.marked)}
              onClick={() => act('link', { link: 'dupe_marked_datum' })} />
          </Box>
        )}
      </Section>
    </Fragment>
  );
};

export const AdminOneClickAntag = props => {
  const { act, data } = useBackend(props);
  const kinds = data.kinds || [];
  const group = (title, ghosts) => (
    <Section title={title}>
      <div className="AdminPanels__grid">
        {kinds.filter(k => !!k.ghosts === ghosts).map(kind => (
          <div key={kind.id} className="AdminPanels__card"
            onClick={() => act('make', { id: kind.id })}>
            <Icon name={kind.icon} size={2} />
            <div>{kind.name}</div>
          </div>
        ))}
      </div>
    </Section>
  );
  return (
    <Fragment>
      {!data.started && (
        <NoticeBox>The round hasn&#39;t started yet.</NoticeBox>
      )}
      {group('From the crew', false)}
      {group('From ghosts (' + data.ghosts + ' observing)', true)}
    </Fragment>
  );
};

export const AdminStationGoals = props => {
  const { act, data } = useBackend(props);
  const goals = data.goals || [];
  return (
    <Section
      title="Station goals"
      buttons={(
        <Button icon="plus" content="Add goal" onClick={() => act('add')} />
      )}>
      {goals.length === 0 && <Box color="label">No goals this round.</Box>}
      {goals.map(goal => (
        <Section key={goal.ref} level={2} title={goal.name}
          buttons={(
            <Fragment>
              <Button icon="bullhorn" content="Announce"
                onClick={() => act('announce', { ref: goal.ref })} />
              <Button icon="trash" color="bad"
                onClick={() => act('remove', { ref: goal.ref })} />
            </Fragment>
          )}>
          <Box color={goal.done ? 'good' : 'label'} mb={0.5}>
            {goal.done ? 'Done' : 'Not done yet'}
          </Box>
          <Box className="AdminPanels__pre">{text(goal.report)}</Box>
        </Section>
      ))}
    </Section>
  );
};
