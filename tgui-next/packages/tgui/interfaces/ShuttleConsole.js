import { Fragment } from 'inferno';
import { useBackend } from '../backend';
import { Box, Button, Icon, LabeledList, NoticeBox, NumberInput, Section } from '../components';

// hippie -- the shuttle console (every shuttle on /obj/machinery/computer/
// shuttle) and the mass driver console, moved off their old HTML windows.
// Data from hippiestation/code/modules/shuttle/shuttle_tgui.dm.

export const ShuttleConsole = props => {
  const { act, data } = useBackend(props);
  const destinations = data.destinations || [];
  const away = destinations.filter(dest => !dest.here);
  return (
    <Fragment>
      <Section>
        <LabeledList>
          <LabeledList.Item
            label="Status"
            color={data.found ? (data.moving ? 'average' : 'good') : 'bad'}>
            {data.status}
          </LabeledList.Item>
          {!!data.emagged && (
            <LabeledList.Item label="ID check" color="bad">
              Disabled
            </LabeledList.Item>
          )}
        </LabeledList>
      </Section>
      {!data.authorized && (
        <NoticeBox>Access denied.</NoticeBox>
      )}
      <Section title="Destinations">
        {destinations.map(dest => (
          <Button
            key={dest.id}
            fluid
            icon={dest.here ? 'map-marker-alt' : 'plane-departure'}
            content={dest.here
              ? dest.name + ' (docked)'
              : 'Send to ' + dest.name}
            disabled={dest.here || data.moving || !data.authorized}
            onClick={() => act('move', { id: dest.id })} />
        ))}
        {away.length === 0 && (
          <Box mt={destinations.length ? 1 : 0}>
            <Box bold color="average">
              <Icon name="lock" mr={1} />
              Shuttle Locked
            </Box>
            {!!data.admin_controlled && (
              <Box mt={1}>
                <Box color="label" mb={0.5}>Authorized personnel only</Box>
                <Button
                  icon="bell"
                  content="Request Authorization"
                  onClick={() => act('request')} />
              </Box>
            )}
          </Box>
        )}
      </Section>
    </Fragment>
  );
};

const formatTime = seconds => Math.floor(seconds / 60) + ':'
  + String(seconds % 60).padStart(2, '0');

export const MassDriverConsole = props => {
  const { act, data } = useBackend(props);
  const levels = data.power_levels || [];
  return (
    <Fragment>
      {!!data.connected && (
        <Fragment>
          <Section
            title="Timer"
            buttons={(
              <Button
                icon={data.timing ? 'stop' : 'clock'}
                content={data.timing ? 'Stop' : 'Start'}
                color={data.timing ? 'bad' : 'default'}
                onClick={() => act('timer')} />
            )}>
            <Box inline fontSize="20px" bold mr={2}
              color={data.timing ? 'average' : null}>
              {formatTime(data.time)}
            </Box>
            <Button
              content="-30"
              disabled={data.time <= 0}
              onClick={() => act('time', { time: data.time - 30 })} />
            <Button
              content="-1"
              disabled={data.time <= 0}
              onClick={() => act('time', { time: data.time - 1 })} />
            <NumberInput
              width="55px"
              unit="s"
              value={data.time}
              minValue={0}
              maxValue={120}
              onChange={(e, value) => act('time', { time: value })} />
            <Button
              content="+1"
              disabled={data.time >= 120}
              onClick={() => act('time', { time: data.time + 1 })} />
            <Button
              content="+30"
              disabled={data.time >= 120}
              onClick={() => act('time', { time: data.time + 30 })} />
          </Section>
          <Section title="Power">
            {levels.map(level => (
              <Button
                key={level}
                content={level}
                selected={level === data.power}
                onClick={() => act('power', { level })} />
            ))}
          </Section>
        </Fragment>
      )}
      <Section title="Controls">
        {!!data.connected && (
          <Fragment>
            <Button
              icon="rocket"
              color="bad"
              content="Firing Sequence"
              onClick={() => act('fire')} />
            <Button
              icon="bolt"
              content="Test Fire"
              onClick={() => act('test')} />
          </Fragment>
        )}
        <Button
          icon={data.door_open ? 'door-open' : 'door-closed'}
          content={data.door_open === null
            ? 'Toggle Outer Door'
            : (data.door_open ? 'Close Outer Door' : 'Open Outer Door')}
          onClick={() => act('door')} />
      </Section>
    </Fragment>
  );
};
