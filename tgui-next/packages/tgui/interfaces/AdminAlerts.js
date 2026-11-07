import { useBackend } from '../backend';
import { Button, Dropdown, Icon } from '../components';

// hippie -- Alerts: kills by non-antagonists, mass deaths, explosions, loose
// engines, gas, emags and waiting tickets this round, newest first. Each
// kind can be shown alone and muted in your own chat; "On it" tells the
// other admins you've got one. Data and actions from
// hippiestation/code/modules/admin/admin_alerts.dm.

const KIND_ICONS = {
  kill: 'skull-crossbones',
  deaths: 'skull',
  boom: 'bomb',
  engine: 'radiation',
  gas: 'smog',
  emag: 'credit-card',
  ticket: 'question-circle',
};

const DISCORD_MODES = {
  adminless: 'No admin on',
  always: 'Always',
  never: 'Never',
};

const Who = props => {
  const { act, row, prefix, name, ckey, here, mob } = props;
  if (!name) {
    return null;
  }
  return (
    <span className="AdminAlerts__who">
      <span className="AdminAlerts__whoName">
        {name}{ckey ? ' (' + ckey + ')' : ''}
      </span>
      {!!here && !!mob && (
        <a onClick={() => act(prefix + 'pp', { id: row.id })}
          title="Player panel">PP
        </a>
      )}
      {!!here && (
        <a onClick={() => act(prefix + 'vv', { id: row.id })}
          title="View variables">VV
        </a>
      )}
      {!!here && (
        <a onClick={() => act(prefix + 'flw', { id: row.id })}
          title="Follow">FLW
        </a>
      )}
      {!!ckey && (
        <a onClick={() => act(prefix + 'profile', { id: row.id })}
          title="Player profile">PROFILE
        </a>
      )}
      {!!ckey && (
        <a onClick={() => act(prefix + 'logs', { id: row.id })}
          title="Search Logs for them">LOGS
        </a>
      )}
    </span>
  );
};

export const AdminAlerts = props => {
  const { act, data } = useBackend(props);
  const alerts = data.alerts || [];
  const kinds = data.kinds || [];
  const anyShown = kinds.some(k => k.shown);
  return (
    <div className="AdminAlerts">
      <div className="AdminAlerts__bar">
        <span
          className={'AdminAlerts__kind'
            + (anyShown ? '' : ' AdminAlerts__kind--on')}
          onClick={() => act('show', { kind: '' })}>
          All
        </span>
        {kinds.map(k => (
          <span key={k.kind}
            className={'AdminAlerts__kind'
              + (k.shown ? ' AdminAlerts__kind--on' : '')}>
            <span onClick={() => act('show', { kind: k.kind })}>
              <Icon name={KIND_ICONS[k.kind]} mr={0.5} />
              {k.name}
              <span className="AdminAlerts__count">{k.count}</span>
            </span>
            <Icon
              name={k.muted ? 'bell-slash' : 'bell'}
              className={'AdminAlerts__bell'
                + (k.muted ? ' AdminAlerts__bell--off' : '')}
              title={k.muted
                ? 'Not in your chat: click to get them'
                : 'In your chat: click to mute'}
              onClick={() => act('mute', { kind: k.kind })} />
          </span>
        ))}
        <span className="AdminAlerts__spacer" />
        <span className="AdminAlerts__muted">Discord</span>
        {data.can_set_discord
          ? (
            <Dropdown
              width="120px"
              selected={DISCORD_MODES[data.discord_mode]}
              options={Object.keys(DISCORD_MODES)
                .map(mode => DISCORD_MODES[mode])}
              onSelected={value => act('discord', {
                mode: Object.keys(DISCORD_MODES)
                  .find(mode => DISCORD_MODES[mode] === value),
              })} />
          )
          : (
            <span className="AdminAlerts__discord">
              {DISCORD_MODES[data.discord_mode]}
            </span>
          )}
      </div>
      <div className="AdminAlerts__list">
        {alerts.length === 0 && (
          <div className="AdminAlerts__empty">No alerts this round.</div>
        )}
        {alerts.map(row => (
          <div key={row.id}
            className={'AdminAlerts__row'
              + (row.bad ? ' AdminAlerts__row--bad' : '')
              + (row.handled_by ? ' AdminAlerts__row--handled' : '')
              + (row.picked ? ' AdminAlerts__row--picked' : '')}
            onClick={() => act('pick', { id: row.id })}>
            <div className="AdminAlerts__time">
              <div>{row.time}</div>
              <div className="AdminAlerts__muted">{row.ago} ago</div>
            </div>
            <div className="AdminAlerts__body">
              <div className="AdminAlerts__head">
                <span className="AdminAlerts__badge">
                  <Icon name={KIND_ICONS[row.kind]} mr={0.5} />
                  {row.kind_name}
                </span>
                {row.count > 1 && (
                  <span className="AdminAlerts__times">x{row.count}</span>
                )}
                <span className="AdminAlerts__text">{row.text}</span>
              </div>
              <div className="AdminAlerts__meta">
                {!!row.where && (
                  <span className="AdminAlerts__where">
                    <Icon name="map-marker-alt" mr={0.5} />
                    {row.area}
                    <a onClick={() => act('jmp', { id: row.id })}
                      title={'Jump to ' + row.where}>JMP
                    </a>
                  </span>
                )}
                <Who act={act} row={row} prefix=""
                  name={row.actor} ckey={row.actor_ckey}
                  here={row.actor_here} mob={row.actor_mob} />
                {!!row.target && (
                  <span className="AdminAlerts__muted">and</span>
                )}
                <Who act={act} row={row} prefix="t_"
                  name={row.target} ckey={row.target_ckey}
                  here={row.target_here} mob={row.target_mob} />
                {!!row.ticket && (
                  <a className="AdminAlerts__link"
                    onClick={() => act('ticket', { id: row.id })}>
                    TICKET #{row.ticket}
                  </a>
                )}
              </div>
            </div>
            <div className="AdminAlerts__handle">
              {!!row.handled_by && !row.mine && (
                <div className="AdminAlerts__on">
                  <Icon name="user-check" mr={0.5} />{row.handled_by}
                </div>
              )}
              <Button
                icon={row.mine ? 'user-times' : 'hand-paper'}
                content={row.mine ? 'Leave it' : 'On it'}
                color={row.mine ? 'default' : 'good'}
                onClick={() => act('handle', { id: row.id })} />
            </div>
          </div>
        ))}
      </div>
    </div>
  );
};
