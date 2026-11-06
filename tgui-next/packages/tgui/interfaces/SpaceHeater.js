import { Fragment } from 'inferno';
import { useBackend } from '../backend';
import { Box, Button, Icon, NumberInput, ProgressBar, Section } from '../components';
import { TemperatureScale } from './ThermoMachine';

// hippie -- the space heater redone: the room's temperature large with what
// the heater is doing about it, a scale with the target on it, the cell, and
// the thermostat's mode and target (set with the panel open, as before). The
// extra data comes from hippiestation/code/modules/atmospherics/
// atmos_tgui.dm.

const WORKING = {
  heat: { color: 'orange', icon: 'fire-alt', text: 'Heating' },
  cool: { color: 'blue', icon: 'snowflake', text: 'Cooling' },
  standby: { color: 'label', icon: 'pause', text: 'Waiting' },
};

const MODES = [
  ['auto', 'thermometer-half', 'Auto'],
  ['heat', 'fire-alt', 'Heat only'],
  ['cool', 'snowflake', 'Cool only'],
];

export const SpaceHeater = props => {
  const { act, data } = useBackend(props);
  const working = data.on
    ? (WORKING[data.working] || WORKING.standby)
    : { color: 'label', icon: 'power-off', text: 'Off' };
  const current = parseFloat(data.currentTemp);
  const target = parseFloat(data.targetTemp);
  const known = !isNaN(current);
  const gap = known ? Math.abs(target - current) : 0;
  return (
    <Fragment>
      <Section>
        <Box>
          <Box
            inline
            fontSize="26px"
            bold
            color={!known && 'label'
              || gap > 50 && 'bad'
              || gap > 20 && 'average'
              || 'good'}>
            {known ? current + ' °C' : 'N/A'}
          </Box>
          <Box inline ml={1} color="label">
            in the room, target {target} °C
          </Box>
          <Button
            style={{ float: 'right' }}
            fontSize="14px"
            icon="power-off"
            color={data.on ? 'good' : 'default'}
            content={data.on ? 'On' : 'Off'}
            disabled={!data.hasPowercell}
            onClick={() => act('power')} />
        </Box>
        <Box mb={1} color={working.color}>
          <Icon name={working.icon} mr={1} />
          {working.text}
        </Box>
        {known && (
          <TemperatureScale
            unit="°C"
            value={current}
            target={target}
            min={data.minTemp}
            max={data.maxTemp} />
        )}
      </Section>
      <Section
        title="Cell"
        buttons={(
          <Button
            icon="eject"
            content="Eject"
            disabled={!data.hasPowercell || !data.open}
            title={data.open ? null : 'Open the panel first'}
            onClick={() => act('eject')} />
        )}>
        {data.hasPowercell && (
          <ProgressBar
            value={data.powerLevel / 100}
            ranges={{
              good: [0.6, Infinity],
              average: [0.3, 0.6],
              bad: [-Infinity, 0.3],
            }}>
            {data.powerLevel}%
          </ProgressBar>
        ) || (
          <Box color="bad">
            No cell installed. Open the panel and put one in to run it.
          </Box>
        )}
      </Section>
      <Section title="Thermostat">
        {!data.open && (
          <Box color="label" mb={1}>
            <Icon name="lock" mr={1} />
            Open the maintenance panel (screwdriver) to change the mode or
            the target.
          </Box>
        )}
        <Box mb={1}>
          {MODES.map(mode => (
            <Button
              key={mode[0]}
              icon={mode[1]}
              content={mode[2]}
              selected={data.mode === mode[0]}
              disabled={!data.open}
              onClick={() => act('mode', { mode: mode[0] })} />
          ))}
        </Box>
        <Box>
          <Box inline color="label" mr={1}>Target</Box>
          {data.open && (
            <NumberInput
              animated
              value={target}
              width="70px"
              unit="°C"
              minValue={data.minTemp}
              maxValue={data.maxTemp}
              onChange={(e, value) => act('target', { target: value })} />
          ) || (
            <Box inline bold>{target} °C</Box>
          )}
        </Box>
      </Section>
    </Fragment>
  );
};
