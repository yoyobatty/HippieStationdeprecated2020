import { Fragment } from 'inferno';
import { useBackend } from '../backend';
import { AnimatedNumber, Box, Button, Icon, NumberInput, Section } from '../components';
import { GasBar, GasLegend } from './common/AtmosBits';
import { FilterChips } from './AirAlarm';

// hippie -- the portable pump and scrubber redone: a big power switch, what's
// inside as a bar split by gas, the pump's direction drawn as where the gas
// goes, and the scrubber's filters as chips in each gas's colour. The extra
// data comes from hippiestation/code/modules/atmospherics/atmos_tgui.dm.

const PowerSwitch = props => {
  const { on, onClick } = props;
  return (
    <Button
      fluid
      textAlign="center"
      fontSize="14px"
      icon="power-off"
      color={on ? 'good' : 'default'}
      content={on ? 'Running' : 'Off'}
      onClick={onClick} />
  );
};

const Contents = props => {
  const { data } = props;
  return (
    <Fragment>
      <Box mb={0.5}>
        <Box inline fontSize="18px" bold mr={1}>
          <AnimatedNumber value={data.pressure} /> kPa
        </Box>
        <Box inline color="label">inside</Box>
        <Box
          inline
          style={{ float: 'right' }}
          color={data.connected ? 'good' : 'label'}>
          <Icon name="plug" mr={1} />
          {data.connected ? 'On a port' : 'Not on a port'}
        </Box>
      </Box>
      <GasBar gases={data.gases} />
      <GasLegend gases={data.gases} />
    </Fragment>
  );
};

const HoldingTank = props => {
  const { act, holding, empty } = props;
  return (
    <Section
      title="Tank"
      buttons={(
        <Button
          icon="eject"
          content="Eject"
          disabled={!holding}
          onClick={() => act('eject')} />
      )}>
      {!!holding && (
        <Fragment>
          <Box>
            <b>{holding.name}</b>
            <Box inline ml={1}>
              <AnimatedNumber value={holding.pressure} /> kPa
            </Box>
          </Box>
          <Box mt={0.5}>
            <GasBar gases={holding.gases} height="10px" />
            <GasLegend gases={holding.gases} />
          </Box>
        </Fragment>
      ) || (
        <Box color="label">{empty}</Box>
      )}
    </Section>
  );
};

export const PortablePump = props => {
  const { act, data } = useBackend(props);
  const {
    direction,
    holding,
    target_pressure,
    default_pressure,
    min_pressure,
    max_pressure,
  } = data;
  // pump.dm: "out" moves the pump's gas to the room, or with a tank in,
  // the tank's gas into the pump; "in" the other way round
  const from = direction
    ? (holding ? 'the pump' : 'the room')
    : (holding ? 'the tank' : 'the pump');
  const to = direction
    ? (holding ? 'the tank' : 'the pump')
    : (holding ? 'the pump' : 'the room');
  return (
    <Fragment>
      <Section>
        <PowerSwitch on={data.on} onClick={() => act('power')} />
        <Box mt={1}>
          <Contents data={data} />
        </Box>
      </Section>
      <Section title="Pumping">
        <div className="Atmos__flow">
          <Box inline bold>{from}</Box>
          <Icon name="long-arrow-alt-right" mx={1} size={1.5}
            color={data.on ? 'good' : 'label'} />
          <Box inline bold>{to}</Box>
          <Button
            ml={2}
            icon="exchange-alt"
            content={direction ? 'In' : 'Out'}
            onClick={() => act('direction')} />
        </div>
        <Box mt={1}>
          <Box inline color="label" mr={1}>Until</Box>
          <NumberInput
            value={target_pressure}
            unit="kPa"
            width="85px"
            minValue={min_pressure}
            maxValue={max_pressure}
            step={10}
            stepPixelSize={2}
            onChange={(e, value) => act('pressure', { pressure: value })} />
          <Button
            icon="fast-backward"
            title="Lowest"
            disabled={target_pressure === min_pressure}
            onClick={() => act('pressure', { pressure: 'min' })} />
          <Button
            icon="undo"
            title={'Default (' + default_pressure + ' kPa)'}
            disabled={target_pressure === default_pressure}
            onClick={() => act('pressure', { pressure: 'reset' })} />
          <Button
            icon="fast-forward"
            title="Highest"
            disabled={target_pressure === max_pressure}
            onClick={() => act('pressure', { pressure: 'max' })} />
        </Box>
      </Section>
      <HoldingTank
        act={act}
        holding={holding}
        empty="No tank inserted. It pumps between itself and the room." />
    </Fragment>
  );
};

export const PortableScrubber = props => {
  const { act, data } = useBackend(props);
  const filters = data.filter_types || [];
  const enabled = filters.filter(filter => filter.enabled).length;
  return (
    <Fragment>
      <Section>
        <PowerSwitch on={data.on} onClick={() => act('power')} />
        <Box mt={1}>
          <Contents data={data} />
        </Box>
      </Section>
      <Section title={'Scrubbing ' + enabled + ' of ' + filters.length}>
        <FilterChips
          filters={filters}
          onToggle={gas_id => act('toggle_filter', { val: gas_id })} />
      </Section>
      <HoldingTank
        act={act}
        holding={data.holding}
        empty={'No tank inserted. What it filters out is stored inside'
          + ' the scrubber.'} />
    </Fragment>
  );
};
