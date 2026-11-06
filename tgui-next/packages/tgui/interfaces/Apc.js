import { Fragment } from 'inferno';
import { useBackend } from '../backend';
import { Box, Button, Icon, NoticeBox, ProgressBar, Section } from '../components';
import { InterfaceLockNoticeBox } from './common/InterfaceLockNoticeBox';
import { channelAuto, channelOn, formatDuration, formatPower } from './common/PowerBits';

// hippie -- the APC redone: the cell, the grid and the breaker up top with
// how long the cell lasts when nothing charges it, each channel a card with
// its load, its share of the area's draw and an Off / Auto / On switch, and
// the settings as one row of toggles. The raw numbers come from
// hippiestation/code/modules/power/power_tgui.dm.

const GRID = {
  2: { color: 'good', icon: 'plug', text: 'Grid power' },
  1: { color: 'average', icon: 'plug', text: 'Low grid power' },
  0: { color: 'bad', icon: 'times-circle', text: 'No grid power' },
};

const CHARGING = {
  2: { color: 'good', icon: 'battery-full', text: 'Fully charged' },
  1: { color: 'average', icon: 'bolt', text: 'Charging' },
  0: { color: 'bad', icon: 'battery-quarter', text: 'Not charging' },
};

const CHANNEL_ICONS = {
  Equipment: 'plug',
  Lighting: 'lightbulb',
  Environment: 'wind',
};

const MALF = {
  1: { icon: 'terminal', content: 'Override programming', action: 'hack' },
  2: { icon: 'caret-square-down', content: 'Shunt core', action: 'occupy' },
  3: { icon: 'caret-square-left', content: 'Return to core',
    action: 'deoccupy' },
  4: { icon: 'caret-square-down', content: 'Shunt core', action: 'occupy' },
};

const Channel = props => {
  const { act, channel, load, totalLoad, locked } = props;
  const on = channelOn(channel.status);
  const auto = channelAuto(channel.status);
  const share = totalLoad > 0 ? load / totalLoad : 0;
  const { topicParams } = channel;
  return (
    <div className="Power__card">
      <Box mb={0.5}>
        <Icon
          name={CHANNEL_ICONS[channel.title] || 'plug'}
          color={on ? 'good' : 'bad'}
          mr={1} />
        <b>{channel.title}</b>
        <Box
          inline
          bold
          style={{ float: 'right' }}
          color={on ? 'good' : 'bad'}>
          {on ? 'ON' : 'OFF'}
        </Box>
      </Box>
      <Box fontSize="18px" bold>
        {on ? channel.powerLoad : '0 W'}
      </Box>
      <Box mb={0.5}>
        <ProgressBar value={on ? share : 0} color="teal">
          {Math.round((on ? share : 0) * 100)}% of the draw
        </ProgressBar>
      </Box>
      <div className="Power__switch">
        <Button
          content="Off"
          selected={!auto && !on}
          color={!auto && !on ? 'bad' : 'default'}
          disabled={locked}
          onClick={() => act('channel', topicParams.off)} />
        <Button
          content="Auto"
          selected={auto}
          disabled={locked}
          onClick={() => act('channel', topicParams.auto)} />
        <Button
          content="On"
          selected={!auto && on}
          color={!auto && on ? 'good' : 'default'}
          disabled={locked}
          onClick={() => act('channel', topicParams.on)} />
      </div>
    </div>
  );
};

export const Apc = props => {
  const { act, data } = useBackend(props);
  const locked = data.locked && !data.siliconUser;
  const grid = GRID[data.externalPower] || GRID[0];
  const charging = CHARGING[data.chargingStatus] || CHARGING[0];
  const hasCell = data.powerCellStatus !== null
    && data.powerCellStatus !== undefined;
  const channels = data.powerChannels || [];
  const loads = data.channelLoads || [];
  const malf = MALF[data.malfStatus];
  const draining = hasCell && data.chargingStatus === 0
    && data.loadRaw > 0;

  if (data.failTime > 0) {
    return (
      <NoticeBox>
        <Box fontSize="16px" bold>SYSTEM FAILURE</Box>
        <Box italic>
          I/O regulators malfunction detected! Waiting for system reboot...
        </Box>
        <Box my={1}>
          Automatic reboot in {data.failTime} seconds.
        </Box>
        <Button
          icon="sync"
          content="Reboot now"
          onClick={() => act('reboot')} />
      </NoticeBox>
    );
  }

  return (
    <Fragment>
      <InterfaceLockNoticeBox
        siliconUser={data.siliconUser}
        locked={data.locked}
        onLockStatusChange={() => act('lock')} />
      <Section>
        <div className="Power__header">
          <div className="Power__headerMain">
            <Box color="label" mb={0.5}>Cell</Box>
            {hasCell && (
              <ProgressBar
                value={data.powerCellStatus / 100}
                ranges={{
                  good: [0.5, Infinity],
                  average: [0.15, 0.5],
                  bad: [-Infinity, 0.15],
                }}>
                <Box bold>{Math.round(data.powerCellStatus)}%</Box>
              </ProgressBar>
            ) || (
              <Box color="bad" bold>No cell</Box>
            )}
            <Box mt={0.5}>
              <Box inline color={charging.color} mr={2}>
                <Icon name={charging.icon} mr={1} />
                {charging.text}
              </Box>
              <Box inline color={grid.color}>
                <Icon name={grid.icon} mr={1} />
                {grid.text}
              </Box>
            </Box>
            {draining && data.cellSeconds !== null && (
              <Box mt={0.5} color="average">
                <Icon name="hourglass-half" mr={1} />
                Lasts about {formatDuration(data.cellSeconds)} at this load
              </Box>
            )}
          </div>
          <div className="Power__headerSide">
            <Box color="label">Draw</Box>
            <Box fontSize="22px" bold mb={1}>
              {formatPower(data.loadRaw)}
            </Box>
            <Button
              fluid
              textAlign="center"
              icon="power-off"
              content={data.isOperating ? 'Breaker on' : 'Breaker off'}
              color={data.isOperating ? 'good' : 'bad'}
              disabled={locked}
              onClick={() => act('breaker')} />
          </div>
        </div>
      </Section>
      <Section title="Channels">
        <div className="Power__cards">
          {channels.map((channel, i) => (
            <Channel
              key={channel.title}
              act={act}
              channel={channel}
              load={loads[i] || 0}
              totalLoad={data.loadRaw}
              locked={locked} />
          ))}
        </div>
      </Section>
      <Section title="Settings">
        <Button
          icon={data.chargeMode ? 'sync' : 'times'}
          content={'Charge cell: ' + (data.chargeMode ? 'auto' : 'off')}
          selected={data.chargeMode}
          disabled={locked}
          onClick={() => act('charge')} />
        <Button
          icon={data.coverLocked ? 'lock' : 'unlock'}
          content={'Cover ' + (data.coverLocked ? 'locked' : 'unlocked')}
          selected={data.coverLocked}
          disabled={locked}
          onClick={() => act('cover')} />
        <Button
          icon="lightbulb"
          content={'Emergency lights '
            + (data.emergencyLights ? 'on' : 'off')}
          selected={data.emergencyLights}
          disabled={locked}
          onClick={() => act('emergency_lighting')} />
        <Button
          icon="moon"
          content={'Night shift ' + (data.nightshiftLights ? 'on' : 'off')}
          selected={data.nightshiftLights}
          disabled={locked}
          onClick={() => act('toggle_nightshift')} />
      </Section>
      {!!data.siliconUser && (
        <Section title="Silicon">
          <Button
            icon="bolt"
            content="Overload lighting"
            color="average"
            onClick={() => act('overload')} />
          {!!malf && (
            <Button
              icon={malf.icon}
              content={malf.content}
              color="bad"
              onClick={() => act(malf.action)} />
          )}
        </Section>
      )}
    </Fragment>
  );
};
