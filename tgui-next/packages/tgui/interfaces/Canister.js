import { Fragment } from 'inferno';
import { useBackend } from '../backend';
import { AnimatedNumber, Box, Button, Dropdown, Icon, LabeledList, NumberInput, ProgressBar, Section } from '../components';
import { GasBar, GasLegend, kelvinToCelsius } from './common/AtmosBits';

// hippie -- the canister redone: what's in it as a bar split by gas, how
// full it is, the valve as one big switch that says where the gas is going
// (the tank, or the room), the release pressure typed or stepped, the tank in
// the regulator with its own gases, and the label picked from a list in the
// window. The extra data comes from hippiestation/code/modules/
// atmospherics/atmos_tgui.dm.

export const Canister = props => {
  const { act, data } = useBackend(props);
  const tank = data.hasHoldingTank ? data.holdingTank : null;
  const intoRoom = data.valveOpen && !tank;
  return (
    <Fragment>
      <Section
        title="Contents"
        buttons={(
          <Dropdown
            width="160px"
            selected="Relabel..."
            options={data.labels || []}
            onSelected={label => act('relabel_to', { label })} />
        )}>
        <Box mb={0.5}>
          <Box inline fontSize="20px" bold mr={1}>
            <AnimatedNumber value={data.tankPressure} /> kPa
          </Box>
          <Box inline color="label">
            {kelvinToCelsius(data.temperature)} °C
          </Box>
          <Box
            inline
            style={{ float: 'right' }}
            color={data.portConnected ? 'good' : 'average'}>
            <Icon name="plug" mr={1} />
            {data.portConnected ? 'Connected' : 'Not Connected'}
          </Box>
        </Box>
        <ProgressBar
          value={data.tankPressure / (data.maxPressure || 9000)}
          color="teal">
          {Math.round(data.tankPressure / (data.maxPressure || 9000) * 100)}%
        </ProgressBar>
        <Box mt={1}>
          <GasBar gases={data.gases} />
          <GasLegend gases={data.gases} showMoles />
        </Box>
        {!!data.isPrototype && (
          <Box mt={1}>
            <Button
              icon={data.restricted ? 'lock' : 'unlock'}
              color="caution"
              content={data.restricted
                ? 'Restricted to Engineering'
                : 'Public'}
              onClick={() => act('restricted')} />
          </Box>
        )}
      </Section>
      <Section title="Valve">
        <Button
          fluid
          textAlign="center"
          fontSize="14px"
          icon={data.valveOpen ? 'unlock' : 'lock'}
          color={intoRoom && 'danger'
            || data.valveOpen && 'caution'
            || 'default'}
          content={data.valveOpen
            ? 'Open → ' + (tank ? 'Holding Tank' : 'Environment')
            : 'Closed'}
          onClick={() => act('valve')} />
        <LabeledList>
          <LabeledList.Item label="Release Pressure">
            <NumberInput
              width="90px"
              unit="kPa"
              value={data.releasePressure}
              minValue={data.minReleasePressure}
              maxValue={data.maxReleasePressure}
              step={10}
              stepPixelSize={2}
              onChange={(e, value) => act('pressure', { pressure: value })} />
            <Button
              icon="fast-backward"
              disabled={data.releasePressure <= data.minReleasePressure}
              title="Lowest"
              onClick={() => act('pressure', { pressure: 'min' })} />
            <Button
              icon="undo"
              disabled={data.releasePressure === data.defaultReleasePressure}
              title={'Default (' + data.defaultReleasePressure + ' kPa)'}
              onClick={() => act('pressure', { pressure: 'reset' })} />
            <Button
              icon="fast-forward"
              disabled={data.releasePressure >= data.maxReleasePressure}
              title="Highest"
              onClick={() => act('pressure', { pressure: 'max' })} />
          </LabeledList.Item>
        </LabeledList>
      </Section>
      <Section
        title="Holding Tank"
        buttons={!!tank && (
          <Button
            icon="eject"
            color={data.valveOpen && 'danger'}
            content="Eject"
            onClick={() => act('eject')} />
        )}>
        {!!tank && (
          <Fragment>
            <Box>
              <b>{tank.name}</b>
              <Box inline ml={1}>
                <AnimatedNumber value={tank.tankPressure} /> kPa
              </Box>
            </Box>
            <Box mt={0.5}>
              <GasBar gases={tank.gases} height="10px" />
              <GasLegend gases={tank.gases} />
            </Box>
          </Fragment>
        ) || (
          <Box color="average">No Holding Tank</Box>
        )}
      </Section>
    </Fragment>
  );
};
