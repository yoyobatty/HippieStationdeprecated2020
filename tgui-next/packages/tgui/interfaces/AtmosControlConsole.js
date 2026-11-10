import { toFixed } from 'common/math';
import { Fragment } from 'inferno';
import { useBackend } from '../backend';
import { AnimatedNumber, Box, Button, LabeledList, NumberInput, Section } from '../components';
import { GasBar, GasLegend, kelvinToCelsius } from './common/AtmosBits';

// hippie -- the tank consoles after tg's rework: the tank's air as a bar
// split by gas, and its injector and vent driven straight from the console
// (no radio, so a change shows at once). A tank whose sensor, injector or vent
// is missing says so. The monitoring console lists every chamber and loop the
// same way. Data from hippiestation/code/game/machinery/computer/
// atmos_control.dm.

const Readout = props => {
  const { air, big } = props;
  return (
    <Fragment>
      <Box mb={0.5}>
        <Box inline bold fontSize={big ? '20px' : null} mr={1}>
          <AnimatedNumber
            value={air.pressure}
            format={value => toFixed(value, 1)} /> kPa
        </Box>
        <Box inline color="label" mr={1}>
          {kelvinToCelsius(air.temperature)} °C
        </Box>
        {!!big && (
          <Box inline color="label">
            {toFixed(air.moles, 1)} mol
          </Box>
        )}
      </Box>
      <GasBar gases={air.gases} height={big ? '14px' : '8px'} />
      <GasLegend gases={air.gases} showMoles={big} />
    </Fragment>
  );
};

const PortState = props => {
  const { state } = props;
  return !!state && (
    <Box inline bold color="bad" ml={1}>
      {state}
    </Box>
  );
};

const TankConsole = props => {
  const { act, data } = useBackend(props);
  const { chamber, sensor, air, input, output } = data;
  return (
    <Fragment>
      <Section
        title={chamber || 'No chamber'}
        buttons={(
          <Button
            icon="link"
            content="Reconnect"
            onClick={() => act('reconnect')} />
        )}>
        {!chamber && (
          <Box className="Atmos__banner Atmos__banner--average">
            Not connected
          </Box>
        ) || !sensor && (
          <Box className="Atmos__banner Atmos__banner--bad">
            No gas sensor
          </Box>
        ) || (
          <Readout air={air} big />
        )}
      </Section>
      {!!sensor && (
        <Fragment>
          <Section title="Input">
            {!input && (
              <Box color="average">No injector linked</Box>
            ) || (
              <LabeledList>
                <LabeledList.Item label="Injector">
                  <Button
                    icon={input.on ? 'power-off' : 'times'}
                    content={input.on ? 'Injecting' : 'Off'}
                    selected={input.on}
                    onClick={() => act('input')} />
                  <PortState state={input.state} />
                </LabeledList.Item>
                <LabeledList.Item label="Rate">
                  <NumberInput
                    width="70px"
                    unit="L/s"
                    value={input.rate}
                    minValue={0}
                    maxValue={data.maxRate}
                    step={1}
                    stepPixelSize={2}
                    onChange={(e, value) => act('rate', { rate: value })} />
                  <Button
                    icon="fast-forward"
                    title="Highest"
                    disabled={input.rate >= data.maxRate}
                    onClick={() => act('rate', { rate: 'max' })} />
                </LabeledList.Item>
              </LabeledList>
            )}
          </Section>
          <Section title="Output">
            {!output && (
              <Box color="average">No vent linked</Box>
            ) || (
              <LabeledList>
                <LabeledList.Item label="Regulator">
                  <Button
                    icon={output.on ? 'power-off' : 'times'}
                    content={output.on ? 'Open' : 'Closed'}
                    selected={output.on}
                    onClick={() => act('output')} />
                  <PortState state={output.state} />
                </LabeledList.Item>
                <LabeledList.Item label="Pressure">
                  <NumberInput
                    width="85px"
                    unit="kPa"
                    value={output.pressure}
                    minValue={0}
                    maxValue={data.maxPressure}
                    step={10}
                    stepPixelSize={2}
                    onChange={(e, value) => act('pressure', {
                      pressure: value,
                    })} />
                  <Button
                    icon="fast-forward"
                    title="Highest"
                    disabled={output.pressure >= data.maxPressure}
                    onClick={() => act('pressure', { pressure: 'max' })} />
                </LabeledList.Item>
              </LabeledList>
            )}
          </Section>
        </Fragment>
      )}
    </Fragment>
  );
};

const ChamberRow = props => {
  const { chamber } = props;
  return (
    <Box className="Atmos__row">
      <Box bold mb={0.25}>{chamber.name}</Box>
      {!chamber.present && (
        <Box bold color="bad">
          {chamber.missing || 'No reading'}
        </Box>
      ) || (
        <Readout air={chamber} />
      )}
    </Box>
  );
};

const MonitorConsole = props => {
  const { data } = useBackend(props);
  const chambers = data.chambers || [];
  const loops = chambers.filter(chamber => chamber.kind === 'loop');
  const tanks = chambers.filter(chamber => chamber.kind !== 'loop');
  return (
    <Fragment>
      {loops.length > 0 && (
        <Section title="Loops">
          {loops.map(chamber => (
            <ChamberRow key={chamber.id} chamber={chamber} />
          ))}
        </Section>
      )}
      <Section title="Chambers">
        {tanks.map(chamber => (
          <ChamberRow key={chamber.id} chamber={chamber} />
        ))}
      </Section>
    </Fragment>
  );
};

export const AtmosControlConsole = props => {
  const { data } = useBackend(props);
  return data.tank
    ? <TankConsole {...props} />
    : <MonitorConsole {...props} />;
};
