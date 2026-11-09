import { decodeHtmlEntities } from 'common/string';
import { Fragment } from 'inferno';
import { useBackend } from '../backend';
import { Box, Button, Icon, LabeledList, NoticeBox, Section } from '../components';

// hippie -- admin pages designed for tgui: Check Antagonists (RoundStatus),
// the traitor panel (TraitorPanel) and Check Teams (TeamListing). Data and
// actions from hippiestation/code/modules/admin/admin_pages_tgui.dm.

const text = value => decodeHtmlEntities(String(value || ''));

// One antagonist: name and what they are, their state, and the admin buttons
const AntagRow = props => {
  const { antag, act } = props;
  return (
    <div className={'AdminPages__antag'
      + (antag.dead ? ' AdminPages__antag--dead' : '')}>
      <div className="AdminPages__antagMain">
        <div>
          <b>{text(antag.name)}</b>
          {!!antag.note && (
            <span className="AdminPages__muted"> {text(antag.note)}</span>
          )}
        </div>
        <div className="AdminPages__muted">
          {text(antag.role)}
          {!!antag.status && (
            <span className="AdminPages__bad"> · {text(antag.status)}</span>
          )}
          {!antag.status && !antag.client && antag.mob && (
            <span> · no client</span>
          )}
        </div>
      </div>
      <span className="AdminPages__buttons">
        {!!antag.ckey && (
          <Button icon="comment" tooltip="PM"
            onClick={() => act('pm', { ref: antag.ckey })} />
        )}
        {!!antag.mob && (
          <Button icon="eye" tooltip="Follow"
            onClick={() => act('follow', { ref: antag.mob })} />
        )}
        {!!antag.mind && (
          <Button icon="user-secret" content="TP"
            onClick={() => act('traitor_panel', { ref: antag.mind })} />
        )}
        {!!antag.mob && (
          <Button icon="user-cog" content="PP"
            onClick={() => act('player_panel', { ref: antag.mob })} />
        )}
        {!!antag.mind && (
          <Button icon="code" tooltip="View variables of the mind"
            onClick={() => act('vv', { ref: antag.mind })} />
        )}
      </span>
    </div>
  );
};

const Stat = props => (
  <div className={'AdminPages__stat' + (props.bad ? ' AdminPages__bad' : '')}>
    <div className="AdminPages__statValue">{props.value}</div>
    <div className="AdminPages__muted">{props.label}</div>
  </div>
);

export const RoundStatus = props => {
  const { act, data } = useBackend(props);
  const p = data.players || {};
  const groups = data.groups || [];
  return (
    <Fragment>
      <Section
        title="Round"
        buttons={(
          <Fragment>
            <Button icon="users" content="Check teams"
              onClick={() => act('check_teams')} />
            {!!data.dynamic && (
              <Button icon="dice" content="Gamemode panel"
                onClick={() => act('gamemode_panel')} />
            )}
          </Fragment>
        )}>
        <LabeledList>
          <LabeledList.Item label="Game mode">
            {data.replacement
              ? <span>{data.mode} → {data.replacement}</span>
              : data.mode}
          </LabeledList.Item>
          <LabeledList.Item label="Duration">{data.duration}</LabeledList.Item>
          <LabeledList.Item label="Emergency shuttle">
            {data.shuttle === 'idle' && (
              <Fragment>
                At CentCom{' '}
                <Button icon="phone" content="Call"
                  onClick={() => act('call_shuttle')} />
              </Fragment>
            )}
            {data.shuttle !== 'idle' && (
              <Fragment>
                {data.shuttle_mode} · ETA{' '}
                <Button content={data.eta} icon="clock"
                  onClick={() => act('edit_eta')} />
                {data.shuttle === 'called' && (
                  <Button icon="undo" content="Send back"
                    onClick={() => act('recall_shuttle')} />
                )}
              </Fragment>
            )}
          </LabeledList.Item>
          <LabeledList.Item label="Round end">
            <Button icon="hourglass-half"
              content={data.delay_end ? 'Delayed' : 'Normal'}
              selected={data.delay_end}
              onClick={() => act('delay')} />
            <Button icon="flag-checkered" color="bad" content="End round now"
              onClick={() => act('end_round')} />
          </LabeledList.Item>
        </LabeledList>
      </Section>
      <Section title="Continuous round">
        <LabeledList>
          <LabeledList.Item label="When antagonists die">
            <Button
              content={data.continuous ? 'Continue' : 'End the round'}
              selected={data.continuous}
              onClick={() => act('toggle_continuous')} />
          </LabeledList.Item>
          {!!data.continuous && (
            <LabeledList.Item label="Replacements">
              <Button
                content={data.midround
                  ? 'Create new antagonists'
                  : 'No new antagonists'}
                selected={data.midround}
                onClick={() => act('toggle_midround')} />
            </LabeledList.Item>
          )}
          {!!data.midround && (
            <Fragment>
              <LabeledList.Item label="Time limit">
                <Button content={data.time_limit + ' min into the round'}
                  onClick={() => act('time_limit')} />
              </LabeledList.Item>
              <LabeledList.Item label="Crew alive limit">
                <Button content={data.life_limit + '%'}
                  onClick={() => act('life_limit')} />
              </LabeledList.Item>
              <LabeledList.Item label="Past the limits">
                <Button
                  content={data.end_on_limit
                    ? 'End the round'
                    : 'Continue as extended'}
                  onClick={() => act('limit_behaviour')} />
              </LabeledList.Item>
            </Fragment>
          )}
        </LabeledList>
      </Section>
      <Section title="Players">
        <div className="AdminPages__stats">
          <Stat value={p.in_game} label="in game" />
          <Stat value={p.connected} label="connected" />
          <Stat value={p.lobby} label="in the lobby" />
          <Stat value={p.living_active} label="living, active" />
          <Stat value={p.living_dc} label="living, disconnected" />
          <Stat value={p.antagonists} label="living antagonists" />
          <Stat value={p.dead_active} label="dead or observing" />
          <Stat value={p.dead_dc} label="dead, disconnected" />
          <Stat value={p.skipped + ' / ' + p.drones}
            label="on CentCom / drones" />
          {p.invalid > 0 && (
            <Stat bad value={p.invalid} label="in an invalid state" />
          )}
        </div>
      </Section>
      {groups.length === 0 && (
        <Section title="Antagonists">
          <Box color="label">None this round.</Box>
        </Section>
      )}
      {groups.map(group => (
        <Section
          key={group.name}
          title={text(group.name) + ' (' + group.antags.length + ')'}>
          {group.antags.map(antag => (
            <AntagRow key={antag.ref} antag={antag} act={act} />
          ))}
          {(group.disks || []).map(disk => (
            <div key={disk.ref} className="AdminPages__antag">
              <div className="AdminPages__antagMain">
                <Icon name="compact-disc" mr={1} />
                <b>{text(disk.name)}</b>
                <div className="AdminPages__muted">{text(disk.where)}</div>
              </div>
              <span className="AdminPages__buttons">
                {!!disk.carrier && (
                  <Button icon="user-cog" content="PP"
                    onClick={() => act('player_panel',
                      { ref: disk.carrier })} />
                )}
                <Button icon="eye" tooltip="Follow"
                  onClick={() => act('follow', { ref: disk.ref })} />
              </span>
            </div>
          ))}
        </Section>
      ))}
    </Fragment>
  );
};

export const TraitorPanel = props => {
  const { act, data } = useBackend(props);
  if (data.gone) {
    return <NoticeBox>This mind is gone.</NoticeBox>;
  }
  const uplink = data.uplink;
  return (
    <Fragment>
      <div className="AdminPages__head">
        <div className="AdminPages__name">
          {text(data.name)}
          {!!data.real_name && (
            <span className="AdminPages__muted">
              {' (as ' + text(data.real_name) + ')'}
            </span>
          )}
        </div>
        <div>
          <Icon name="key" /> {data.key}{' '}
          <span className="AdminPages__muted">
            {data.synced ? '(synced)' : '(not synced)'}
          </span>
        </div>
        <div>
          {data.role || 'No role'}{' '}
          <Button icon="pen" content="Edit role"
            onClick={() => act('role_edit')} />
          {!!data.special_role && (
            <span className="AdminPages__bad"> {data.special_role}</span>
          )}
        </div>
        <div>
          {!!data.no_body && <span className="AdminPages__tag">No body</span>}
          {!!data.mindshield && (
            <span className="AdminPages__tag AdminPages__tag--good">
              Mindshielded
            </span>
          )}
          {!!data.emagged && <span className="AdminPages__tag">Emagged</span>}
        </div>
      </div>
      {(data.antags || []).map(antag => (
        <Section
          key={antag.ref}
          title={antag.name}
          className="AdminPages__active"
          buttons={(
            <Button icon="times" color="bad" content="Remove"
              onClick={() => act('remove_antag', { ref: antag.ref })} />
          )}>
          {antag.commands.length > 0 && (
            <Box mb={1}>
              {antag.commands.map(command => (
                <Button key={command} content={command}
                  onClick={() => act('antag_command',
                    { ref: antag.ref, command })} />
              ))}
            </Box>
          )}
          {!!antag.data && (
            <Box mb={1} className="AdminPages__pre">{text(antag.data)}</Box>
          )}
          <Box bold mb={0.5}>Objectives</Box>
          {antag.objectives.length === 0 && (
            <Box color="label">None.</Box>
          )}
          {antag.objectives.map((objective, i) => (
            <div key={objective.ref} className="AdminPages__objective">
              <span className="AdminPages__objectiveNo">{i + 1}</span>
              <span className="AdminPages__objectiveText">
                {text(objective.text)}
              </span>
              <Button.Checkbox
                checked={objective.completed}
                content="Done"
                color={objective.completed ? 'good' : null}
                onClick={() => act('obj_completed', { ref: objective.ref })} />
              <Button icon="pen" tooltip="Edit"
                onClick={() => act('obj_edit', { ref: objective.ref })} />
              <Button icon="trash" tooltip="Delete"
                onClick={() => act('obj_delete', { ref: objective.ref })} />
            </div>
          ))}
          <Box mt={0.5}>
            <Button icon="plus" content="Add objective"
              onClick={() => act('obj_add', { ref: antag.ref })} />
            <Button icon="bullhorn" content="Announce objectives"
              onClick={() => act('announce')} />
          </Box>
          <Box bold mt={1} mb={0.5}>
            Memory{' '}
            <Button icon="pen" content="Edit"
              onClick={() => act('antag_memory', { ref: antag.ref })} />
          </Box>
          <Box className="AdminPages__pre">
            {antag.memory ? text(antag.memory) : 'Empty.'}
          </Box>
        </Section>
      ))}
      <Section title="Make them">
        {(data.categories || []).map(category => (
          <div key={category.name} className="AdminPages__category">
            <span className="AdminPages__categoryName">
              {category.name}
              {category.pref === 'disabled' && (
                <Icon name="ban" ml={1} color="label"
                  title="Disabled in their preferences" />
              )}
            </span>
            <span>
              {category.options.map(option => (
                <Button
                  key={option.type}
                  content={option.name}
                  disabled={!option.can}
                  tooltip={category.pref === 'disabled'
                    ? 'Disabled in their preferences'
                    : null}
                  onClick={() => act('add_antag', { type: option.type })} />
              ))}
            </span>
          </div>
        ))}
      </Section>
      <Section title="Uplink, memory and commands">
        {!!uplink && (
          <Box mb={1}>
            Uplink:{' '}
            {uplink.has
              ? (
                <Fragment>
                  <Button icon="coins"
                    content={uplink.tc + ' TC'}
                    disabled={!uplink.can_set}
                    onClick={() => act('uplink_tc')} />
                  <Button icon="hand-paper" content="Take"
                    onClick={() => act('uplink_take')} />
                </Fragment>
              )
              : (
                <Button icon="gift" content="Give"
                  onClick={() => act('uplink_give')} />
              )}
          </Box>
        )}
        <Box bold mb={0.5}>
          Common memory{' '}
          <Button icon="pen" content="Edit"
            onClick={() => act('memory_edit')} />
        </Box>
        <Box className="AdminPages__pre" mb={1}>
          {data.memory ? text(data.memory) : 'Empty.'}
        </Box>
        {(data.common || []).map(c => (
          <Button key={c.value} content={c.label}
            onClick={() => act('common', { key: c.key, value: c.value })} />
        ))}
      </Section>
    </Fragment>
  );
};

export const TeamListing = props => {
  const { act, data } = useBackend(props);
  const teams = data.teams || [];
  return (
    <Fragment>
      {teams.length === 0 && (
        <Section><Box color="label">No teams.</Box></Section>
      )}
      {teams.map(team => (
        <Section
          key={team.ref}
          title={text(team.name)}
          buttons={(
            <Fragment>
              <Button icon="pen" tooltip="Rename"
                onClick={() => act('rename', { team: team.ref })} />
              <Button icon="comment" tooltip="Communicate"
                onClick={() => act('communicate', { team: team.ref })} />
              <Button icon="trash" tooltip="Delete" color="bad"
                onClick={() => act('delete', { team: team.ref })} />
            </Fragment>
          )}>
          <Box className="AdminPages__muted" mb={1}>{team.type}</Box>
          {team.commands.length > 0 && (
            <Box mb={1}>
              {team.commands.map(command => (
                <Button key={command} content={command}
                  onClick={() => act('command',
                    { team: team.ref, command })} />
              ))}
            </Box>
          )}
          <Box bold mb={0.5}>Objectives</Box>
          {team.objectives.map((objective, i) => (
            <div key={objective.ref} className="AdminPages__objective">
              <span className="AdminPages__objectiveNo">{i + 1}</span>
              <span className="AdminPages__objectiveText">
                {text(objective.text)}
              </span>
              <Button icon="trash" tooltip="Remove"
                onClick={() => act('remove_objective',
                  { team: team.ref, ref: objective.ref })} />
            </div>
          ))}
          <Button icon="plus" content="Add objective"
            onClick={() => act('add_objective', { team: team.ref })} />
          <Box bold mt={1} mb={0.5}>Members ({team.members.length})</Box>
          {team.members.map(member => (
            <div key={member.ref} className="AdminPages__objective">
              <span className="AdminPages__objectiveText">
                {text(member.name)}
                {!!member.dead && (
                  <span className="AdminPages__bad"> · dead</span>
                )}
              </span>
              {!!member.mob && (
                <Button icon="user-cog" content="PP"
                  onClick={() => act('player_panel',
                    { team: team.ref, ref: member.ref })} />
              )}
              <Button icon="user-minus" tooltip="Remove"
                onClick={() => act('remove_member',
                  { team: team.ref, ref: member.ref })} />
            </div>
          ))}
          <Button icon="user-plus" content="Add member"
            onClick={() => act('add_member', { team: team.ref })} />
        </Section>
      ))}
      <Section>
        <Button icon="plus" content="Create team"
          onClick={() => act('create')} />
      </Section>
    </Fragment>
  );
};
