import { decodeHtmlEntities } from 'common/string';
import { Component, Fragment } from 'inferno';
import { useBackend } from '../backend';
import { Box, Button, Icon, Input, LabeledList } from '../components';

// hippie -- the Bot Crew panel: a row per bot crewmember, what it's doing and
// the last thing it gave up on; a row opens its personality, grudges, hands
// and last lines. hippiestation/code/modules/admin/bot_crew_panel.dm. Uses the
// Player Panel's table look (AdminPanels.scss).

const text = value => decodeHtmlEntities(String(value || ''));

const COLUMNS = [
  ['name', 'Name'],
  ['job', 'Job'],
  ['style', 'Style'],
  ['state', 'State'],
  ['goal', 'Doing'],
  ['gave_up_ago', 'Gave up'],
  ['area', 'Area'],
];

const STATE_COLORS = {
  wander: 'label',
  goal: 'good',
  combat: 'bad',
  arrest: 'average',
  'shut in': 'average',
  down: 'average',
  dead: 'bad',
};

// seconds ago -> "45s", "12m"
const ago = seconds => {
  if (seconds === null || seconds === undefined) {
    return '';
  }
  return seconds < 120 ? seconds + 's' : Math.floor(seconds / 60) + 'm';
};

const TRAITS = [
  ['diligence', 'Diligence'],
  ['sociability', 'Sociability'],
  ['nerve', 'Nerve'],
  ['temper', 'Temper'],
  ['competence', 'Competence'],
  ['strictness', 'Strictness'],
];

const Detail = props => {
  const { bot, open, go } = props;
  return (
    <Fragment>
      <Box mb={0.5}>
        <Button icon="eye" content="Follow" onClick={go('flw')} />
        <Button icon="location-arrow" content="Jump" onClick={go('jmp')} />
        <Button icon="code" content="VV" onClick={go('vv')} />
        <Button icon="brain" content="VV brain" onClick={go('vv_brain')} />
        <Button icon="user-cog" content="Player panel" onClick={go('pp')} />
      </Box>
      <LabeledList>
        <LabeledList.Item label="Doing">
          {text(bot.goal) || '-'}
          {!!bot.step && (
            <Box inline ml={1} color="label">{bot.step}</Box>
          )}
          {!!bot.target && (
            <Box inline ml={1} color="average">{text(bot.target)}</Box>
          )}
          {!!open.suspended && (
            <Box inline ml={1} color="label">
              (put off: {text(open.suspended)})
            </Box>
          )}
        </LabeledList.Item>
        {!!bot.gave_up && (
          <LabeledList.Item label="Gave up">
            {text(bot.gave_up)}
            <Box inline ml={1} color="label">{ago(bot.gave_up_ago)} ago</Box>
          </LabeledList.Item>
        )}
        <LabeledList.Item label="Health">{open.health}</LabeledList.Item>
        <LabeledList.Item label="Traits">
          {TRAITS.map(([key, label]) => (
            <Box key={key} inline mr={2}>
              <Box inline color="label">{label}</Box>{' '}
              {Math.round(open[key] * 100) / 100}
            </Box>
          ))}
          {!!bot.greytider && (
            <Box inline mr={2} color="average">Greytider</Box>
          )}
          {!!bot.hardened && (
            <Box inline mr={2} color="bad">Hardened</Box>
          )}
        </LabeledList.Item>
        <LabeledList.Item label="Habits">
          {(open.habits || []).join(', ') || '-'}
        </LabeledList.Item>
        <LabeledList.Item label="Holding">
          {(open.held || []).map(text).join(', ') || 'Nothing'}
        </LabeledList.Item>
        <LabeledList.Item label="Wearing">
          {(open.worn || []).map(text).join(', ') || '-'}
        </LabeledList.Item>
        <LabeledList.Item label="Grudges">
          {!(open.grudges || []).length && '-'}
          {(open.grudges || []).map(g => (
            <Box key={g.name} inline mr={2}>
              {text(g.name)} <Box inline color="bad">{g.points}</Box>
            </Box>
          ))}
        </LabeledList.Item>
      </LabeledList>
      <Box mt={1} color="label">Last lines</Box>
      <Box
        className="BotCrew__lines"
        style={{
          'font-family': 'monospace',
          'font-size': '11px',
          'white-space': 'pre-wrap',
          'max-height': '220px',
          'overflow-y': 'auto',
        }}>
        {!(open.lines || []).length && (
          <Box color="label">None yet</Box>
        )}
        {(open.lines || []).slice().reverse().map((line, i) => (
          <div key={i}>{text(line)}</div>
        ))}
      </Box>
    </Fragment>
  );
};

export class BotCrew extends Component {
  constructor() {
    super();
    this.state = { search: '', sort: 'name', desc: false };
  }

  render() {
    const { act, data } = useBackend(this.props);
    const bots = data.bots || [];
    const query = this.state.search.toLowerCase();
    const shown = bots.filter(b => !query || [b.name, b.job, b.style,
      b.state, b.goal, b.area, b.gave_up]
      .some(v => String(v || '').toLowerCase().includes(query)));
    const { sort, desc } = this.state;
    const value = (b, key) => {
      const v = b[key];
      if (key === 'gave_up_ago') {
        // the most recent first, then nobody who's given up
        return v === null || v === undefined ? Infinity : v;
      }
      if (typeof v === 'number') {
        return v;
      }
      return String(v || '').toLowerCase();
    };
    const sorted = shown.slice().sort((a, b) => {
      const x = value(a, sort);
      const y = value(b, sort);
      const order = x < y ? -1 : x > y ? 1 : 0;
      return desc ? -order : order;
    });
    const counts = {};
    for (let b of bots) {
      counts[b.state] = (counts[b.state] || 0) + 1;
    }
    return (
      <Fragment>
        <Box mb={1} className="AdminPanels__bar">
          <Input fluid placeholder="Search names, jobs, goals, areas..."
            value={this.state.search}
            onInput={(e, value) => this.setState({ search: value })} />
        </Box>
        <Box mb={1}>
          <Box inline mr={2}><b>{bots.length}</b> bots</Box>
          {Object.keys(counts).sort().map(state => (
            <Box key={state} inline mr={2} color={STATE_COLORS[state]}>
              {state} {counts[state]}
            </Box>
          ))}
        </Box>
        {shown.length === 0 && <Box color="label">No bots.</Box>}
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
              {sorted.map(b => {
                const open = data.open_ref === b.ref;
                const go = action => () => act(action, { ref: b.ref });
                return (
                  <Fragment key={b.ref}>
                    <tr
                      className={'AdminPanels__row'
                        + (b.antag ? ' AdminPanels__row--antag' : '')
                        + (open ? ' AdminPanels__row--open' : '')}
                      onClick={go('open')}>
                      <td className="AdminPanels__playerName">
                        {text(b.name)}
                      </td>
                      <td className="AdminPanels__job">
                        {b.job}
                        {!!b.antag && (
                          <span className="AdminPanels__antag">
                            {' ' + text(b.antag)}
                          </span>
                        )}
                      </td>
                      <td className="AdminPanels__muted">
                        {b.style}
                        {!!b.hardened && b.style !== 'paranoid' && (
                          <Box inline ml={0.5} color="bad">*</Box>
                        )}
                      </td>
                      <td>
                        <Box inline color={STATE_COLORS[b.state]}>
                          {b.state}
                        </Box>
                      </td>
                      <td>
                        {text(b.goal) || (
                          <Box inline color="label">-</Box>
                        )}
                        {!!b.step && (
                          <Box className="AdminPanels__muted">{b.step}</Box>
                        )}
                      </td>
                      <td title={text(b.gave_up)}>
                        {!!b.gave_up && (
                          <Fragment>
                            <Box inline color="average">
                              {ago(b.gave_up_ago)}
                            </Box>{' '}
                            <span className="AdminPanels__muted">
                              {text(b.gave_up).slice(0, 40)}
                            </span>
                          </Fragment>
                        )}
                      </td>
                      <td className="AdminPanels__muted">{text(b.area)}</td>
                      <td className="AdminPanels__rowActions"
                        onClick={e => e.stopPropagation()}>
                        <Button content="FLW" onClick={go('flw')} />
                        <Button content="VV" onClick={go('vv')} />
                        <Button content="JMP" onClick={go('jmp')} />
                      </td>
                    </tr>
                    {open && !!data.open && (
                      <tr className="AdminPanels__openRow">
                        <td colSpan={8}>
                          <Detail bot={b} open={data.open} go={go} />
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
