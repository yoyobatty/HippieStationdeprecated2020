import { Component, Fragment } from 'inferno';
import { useBackend } from '../backend';
import { Box, Button, Input, ProgressBar, Section } from '../components';

// hippie -- Bot Crew: what every bot crewmember is doing. Data from
// hippiestation/code/modules/mob/dead/observer/bot_crew_monitor.dm.

const STATE_WORD = {
  goal: 'Working',
  wander: 'Free',
  combat: 'Fighting',
  arrest: 'Arresting',
};

const STATUS_COLOR = {
  Alive: 'good',
  Down: 'average',
  Dead: 'bad',
};

const ago = secs => {
  if (secs < 60) {
    return secs + 's';
  }
  return Math.floor(secs / 60) + 'm';
};

const BotRow = props => {
  const { bot, open, admin, onToggle, onFollow } = props;
  const dead = bot.status === 'Dead';
  return (
    <Fragment>
      <tr
        className={'BotCrew__row' + (open ? ' BotCrew__row--open' : '')
          + (dead ? ' BotCrew__row--dead' : '')}
        onClick={onToggle}>
        <td className="BotCrew__who">
          <div className="BotCrew__name">{bot.name}</div>
          <div className="BotCrew__job">
            {bot.job}
            {admin && !!bot.antag && (
              <span className="BotCrew__antag">{bot.antag}</span>
            )}
          </div>
        </td>
        <td className="BotCrew__doing">
          <div>{dead ? '-' : (bot.doing || 'Nothing in particular')}</div>
          {!!bot.goal && (
            <div className="BotCrew__goal">
              {bot.goal}{bot.step ? ' › ' + bot.step : ''}
            </div>
          )}
        </td>
        <td className="BotCrew__state">
          {dead ? '' : (STATE_WORD[bot.state] || bot.state)}
        </td>
        <td className="BotCrew__where">{bot.area}</td>
        <td className="BotCrew__health">
          <ProgressBar
            value={bot.health / 100}
            color={STATUS_COLOR[bot.status]}>
            {bot.status === 'Alive' ? bot.health + '%' : bot.status}
          </ProgressBar>
        </td>
        <td className="BotCrew__follow">
          <Button
            icon="eye"
            content="Follow"
            onClick={e => {
              e.stopPropagation();
              onFollow();
            }} />
        </td>
      </tr>
      {open && (
        <tr className="BotCrew__detail">
          <td colSpan={6}>
            <Box mb={0.5} color="label">
              {'Playstyle: ' + bot.style}
            </Box>
            {bot.events.map((event, i) => (
              <div key={i} className="BotCrew__event">
                <span className="BotCrew__ago">{ago(event.ago)}</span>
                {event.text}
              </div>
            ))}
            {!bot.events.length && (
              <Box color="label">No goals or actions yet</Box>
            )}
          </td>
        </tr>
      )}
    </Fragment>
  );
};

export class BotCrewMonitor extends Component {
  constructor() {
    super();
    this.state = { open: null, filter: '' };
  }

  render() {
    const { act, data } = useBackend(this.props);
    const { bots = [], admin } = data;
    const { open, filter } = this.state;
    const needle = filter.toLowerCase();
    const shown = bots
      .filter(bot => !needle || (bot.name + ' ' + bot.job + ' ' + bot.area
        + ' ' + (bot.doing || '')).toLowerCase().indexOf(needle) >= 0)
      .sort((a, b) => (a.job === b.job
        ? (a.name < b.name ? -1 : 1)
        : (a.job < b.job ? -1 : 1)));
    const count = test => bots.filter(test).length;
    const alive = bot => bot.status !== 'Dead';
    return (
      <Section
        title={'Bot Crew (' + bots.length + ')'}
        buttons={(
          <Input
            placeholder="Filter"
            value={filter}
            onInput={(e, value) => this.setState({ filter: value })} />
        )}>
        <Box mb={1} className="BotCrew__counts">
          <span>{count(b => alive(b) && b.state === 'goal')} working</span>
          <span>{count(b => alive(b) && b.state === 'wander')} free</span>
          <span>
            {count(b => alive(b)
              && (b.state === 'combat' || b.state === 'arrest'))} fighting
          </span>
          <span>{count(b => b.status === 'Down')} down</span>
          <span>{count(b => b.status === 'Dead')} dead</span>
        </Box>
        {shown.length ? (
          <table className="BotCrew__table">
            <tbody>
              {shown.map(bot => (
                <BotRow
                  key={bot.ref}
                  bot={bot}
                  admin={!!admin}
                  open={open === bot.ref}
                  onToggle={() => this.setState(prev => ({
                    open: prev.open === bot.ref ? null : bot.ref,
                  }))}
                  onFollow={() => act('follow', { ref: bot.ref })} />
              ))}
            </tbody>
          </table>
        ) : (
          <Box color="label">No bots aboard</Box>
        )}
      </Section>
    );
  }
}
