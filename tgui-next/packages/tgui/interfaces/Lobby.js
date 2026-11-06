import { Fragment } from 'inferno';
import { useBackend } from '../backend';
import { Box, Button, Icon, LabeledList, NoticeBox, Section } from '../components';

// hippie -- the lobby and the late-join job list. Data from hippiestation/
// code/modules/mob/dead/new_player/lobby_tgui.dm.

const PLAYER_NOT_READY = 0;
const PLAYER_READY_TO_PLAY = 1;
const PLAYER_READY_TO_OBSERVE = 2;

const pad = n => (n < 10 ? '0' : '') + n;

const clock = secs => {
  const h = Math.floor(secs / 3600);
  const m = Math.floor(secs / 60) % 60;
  const s = secs % 60;
  return (h ? h + ':' + pad(m) : m) + ':' + pad(s);
};

const startText = data => {
  if (data.startup) {
    return 'Initializing';
  }
  if (data.delayed) {
    return 'Delayed';
  }
  return data.time_left > 0 ? clock(data.time_left) : 'Soon';
};

const RoundInfo = props => {
  const { data } = props;
  if (data.pregame) {
    return (
      <LabeledList>
        <LabeledList.Item label="Start">
          <Box inline bold color={data.delayed ? 'bad' : 'good'}>
            {startText(data)}
          </Box>
        </LabeledList.Item>
        <LabeledList.Item label="Players">
          {data.players}
          {data.players_ready !== undefined && (
            <Box inline color="label" ml={1}>
              ({data.players_ready} ready)
            </Box>
          )}
        </LabeledList.Item>
        <LabeledList.Item label="Map">{data.map}</LabeledList.Item>
      </LabeledList>
    );
  }
  return (
    <LabeledList>
      <LabeledList.Item label="Duration">
        {data.setting_up ? 'Setting up' : clock(data.round_time || 0)}
      </LabeledList.Item>
      <LabeledList.Item label="Crew">{data.crew}</LabeledList.Item>
      <LabeledList.Item label="Map">{data.map}</LabeledList.Item>
    </LabeledList>
  );
};

export const Lobby = props => {
  const { act, data } = useBackend(props);
  const { ready, queue } = data;
  const readyButton = (value, text, icon, color) => (
    <Button
      fluid
      icon={icon}
      content={text}
      textAlign="center"
      selected={ready === value}
      color={ready === value ? color : 'default'}
      onClick={() => act('ready', { value })} />
  );
  let joinText = 'Join Game';
  if (data.ended) {
    joinText = 'Round Over';
  } else if (queue) {
    joinText = 'Queued (' + queue + ')';
  }
  return (
    <Fragment>
      <Section>
        <LabeledList>
          <LabeledList.Item label="Character">
            {data.character || '-'}
          </LabeledList.Item>
          <LabeledList.Item label="Job">{data.job || '-'}</LabeledList.Item>
        </LabeledList>
        <Box mt={1}>
          <Button
            fluid
            icon="user-cog"
            content="Setup Character"
            textAlign="center"
            onClick={() => act('setup')} />
        </Box>
      </Section>
      <Section title={data.round_id ? 'Round ' + data.round_id : 'Round'}>
        <RoundInfo data={data} />
        {!!data.evac && (
          <NoticeBox mt={1} mb={0}>{data.evac}</NoticeBox>
        )}
      </Section>
      {data.pregame ? (
        <div className="Lobby__row">
          {readyButton(PLAYER_READY_TO_PLAY, 'Ready', 'check', 'good')}
          {readyButton(PLAYER_NOT_READY, 'Not Ready', 'times', 'average')}
          {readyButton(PLAYER_READY_TO_OBSERVE, 'Observe', 'eye', 'default')}
        </div>
      ) : (
        <Fragment>
          <Button
            fluid
            className="Lobby__join"
            icon="sign-in-alt"
            color="good"
            content={joinText}
            textAlign="center"
            disabled={!!data.ended || !!data.setting_up}
            onClick={() => act('join')} />
          <div className="Lobby__row">
            <Button
              fluid
              icon="clipboard-list"
              content="Crew Manifest"
              textAlign="center"
              onClick={() => act('manifest')} />
            <Button
              fluid
              icon="eye"
              content="Observe"
              textAlign="center"
              onClick={() => act('ready', {
                value: PLAYER_READY_TO_OBSERVE,
              })} />
          </div>
        </Fragment>
      )}
      {!!data.polls && (
        <Box mt={0.5}>
          <Button
            fluid
            icon="poll"
            textAlign="center"
            color={data.new_polls ? 'average' : 'default'}
            content={'Player Polls' + (data.new_polls ? ' (New)' : '')}
            onClick={() => act('polls')} />
        </Box>
      )}
    </Fragment>
  );
};

const slotText = job => {
  if (job.status) {
    return job.status;
  }
  return job.filled + '/' + (job.slots < 0 ? '∞' : job.slots);
};

const Department = props => {
  const { dept, canJoin, act } = props;
  return (
    <div
      className="Lobby__dept"
      style={{ 'border-color': dept.color }}>
      <div className="Lobby__deptName" style={{ 'color': dept.color }}>
        {dept.name}
      </div>
      {dept.jobs.map(job => (
        <Button
          key={job.title}
          fluid
          className={'Lobby__job'
            + (job.command ? ' Lobby__job--command' : '')
            + (job.priority ? ' Lobby__job--priority' : '')}
          disabled={!!job.status || !canJoin}
          tooltip={job.priority ? 'Wanted' : null}
          onClick={() => act('join', { job: job.title })}>
          {!!job.priority && (
            <Icon name="star" mr={0.5} />
          )}
          {job.title}
          <span className="Lobby__slots">{slotText(job)}</span>
        </Button>
      ))}
    </div>
  );
};

export const LateJoin = props => {
  const { act, data } = useBackend(props);
  const departments = data.departments || [];
  // Three columns, each department to the shortest so far
  const columns = [[], [], []];
  const heights = [0, 0, 0];
  departments.forEach(dept => {
    let best = 0;
    for (let i = 1; i < columns.length; i++) {
      if (heights[i] < heights[best]) {
        best = i;
      }
    }
    columns[best].push(dept);
    heights[best] += dept.jobs.length + 2;
  });
  return (
    <Fragment>
      <Box className="Lobby__header">
        <Box inline mr={2}>
          <Box inline color="label" mr={0.5}>Duration</Box>
          {clock(data.round_time || 0)}
        </Box>
        <Box inline mr={2}>
          <Box inline color="label" mr={0.5}>Crew</Box>
          {data.crew}
        </Box>
        <Box inline>
          <Box inline color="label" mr={0.5}>Map</Box>
          {data.map}
        </Box>
      </Box>
      {!!data.evac && (
        <NoticeBox>{data.evac}</NoticeBox>
      )}
      {!!data.queue && (
        <NoticeBox>Queued ({data.queue})</NoticeBox>
      )}
      <div className="Lobby__columns">
        {columns.map((column, i) => (
          <div key={i} className="Lobby__column">
            {column.map(dept => (
              <Department
                key={dept.name}
                dept={dept}
                canJoin={!!data.can_join}
                act={act} />
            ))}
          </div>
        ))}
      </div>
    </Fragment>
  );
};
