import { toFixed } from 'common/math';
import { Fragment } from 'inferno';
import { useBackend } from '../backend';
import { AnimatedNumber, Box, Button, Icon, NumberInput, Section } from '../components';
import { kelvinToCelsius } from './common/AtmosBits';

// hippie -- the freezer and heater redone: the pipe gas's temperature large,
// a scale from the machine's coldest to its hottest with where the gas is and
// where it's headed, and the target typed, stepped or set to a preset. The
// extra data comes from hippiestation/code/modules/atmospherics/
// atmos_tgui.dm.

const tempColor = kelvin => {
  if (kelvin < 200) {
    return 'blue';
  }
  if (kelvin < 273) {
    return 'teal';
  }
  if (kelvin < 340) {
    return 'good';
  }
  if (kelvin < 500) {
    return 'orange';
  }
  return 'red';
};

// Where a temperature sits on the scale, 0 to 100
export const scalePercent = (value, min, max) => {
  if (max <= min) {
    return 0;
  }
  return Math.max(0, Math.min(100, (value - min) / (max - min) * 100));
};

export const TemperatureScale = props => {
  const { value, target, min, max, unit = 'K', format } = props;
  const show = format || (v => Math.round(v) + ' ' + unit);
  return (
    <Box>
      <div className="Atmos__scale">
        <div
          className={'Atmos__scaleFill color-bg-' + tempColor(
            unit === 'K' ? value : value + 273.15)}
          style={{ width: scalePercent(value, min, max) + '%' }} />
        <div
          className="Atmos__scaleTarget"
          title={'Target ' + show(target)}
          style={{ left: scalePercent(target, min, max) + '%' }} />
      </div>
      <Box fontSize="11px" color="label">
        {show(min)}
        <Box inline style={{ float: 'right' }}>{show(max)}</Box>
      </Box>
    </Box>
  );
};

export const ThermoMachine = props => {
  const { act, data } = useBackend(props);
  const cooling = !!data.cooling;
  const reached = Math.abs(data.temperature - data.target) < 1;
  return (
    <Fragment>
      <Section>
        <Box>
          <Box inline fontSize="26px" bold color={tempColor(data.temperature)}>
            <AnimatedNumber
              value={data.temperature}
              format={value => toFixed(value, 1)} /> K
          </Box>
          <Box inline ml={1} color="label">
            {kelvinToCelsius(data.temperature)} °C ·{' '}
            {toFixed(data.pressure, 1)} kPa
          </Box>
          <Button
            style={{ float: 'right' }}
            fontSize="14px"
            icon="power-off"
            color={data.on ? 'good' : 'default'}
            content={data.on ? 'On' : 'Off'}
            onClick={() => act('power')} />
        </Box>
        <Box mb={1} color={data.on ? (cooling ? 'blue' : 'orange') : 'label'}>
          <Icon name={cooling ? 'snowflake' : 'fire-alt'} mr={1} />
          {!data.on && 'Off'
            || reached && 'At target'
            || (cooling ? 'Cooling' : 'Heating') + ' → '
              + Math.round(data.target) + ' K'}
        </Box>
        <TemperatureScale
          value={data.temperature}
          target={data.target}
          min={data.min}
          max={data.max} />
      </Section>
      <Section title="Target">
        <Box>
          <Button
            icon="minus"
            disabled={data.target <= data.min}
            onClick={() => act('target', { adjust: -10 })} />
          <NumberInput
            width="80px"
            unit="K"
            value={Math.round(data.target)}
            minValue={Math.round(data.min)}
            maxValue={Math.round(data.max)}
            step={5}
            stepPixelSize={3}
            onChange={(e, value) => act('target', { target: value })} />
          <Button
            icon="plus"
            disabled={data.target >= data.max}
            onClick={() => act('target', { adjust: 10 })} />
          <Box inline ml={1} color="label">
            {kelvinToCelsius(data.target)} °C
          </Box>
        </Box>
        <Box mt={1}>
          <Button
            icon="snowflake"
            content="Min"
            disabled={data.target === data.min}
            onClick={() => act('target', { target: data.min })} />
          <Button
            icon="home"
            content="Room"
            disabled={Math.round(data.target)
              === Math.round(data.roomTemp || data.initial)}
            onClick={() => act('target', {
              target: data.roomTemp || data.initial,
            })} />
          <Button
            icon="fire-alt"
            content="Max"
            disabled={data.target === data.max}
            onClick={() => act('target', { target: data.max })} />
        </Box>
      </Section>
    </Fragment>
  );
};
