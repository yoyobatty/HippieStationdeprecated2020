import { Fragment } from 'inferno';
import { useBackend } from '../backend';
import { Box, Flex, LabeledList, NoticeBox, Section } from '../components';

// hippie -- the thermoelectric generator's readout
// (hippiestation/.../power/generator_tgui.dm)

const Loop = props => {
  const { title, color, loop } = props;
  return (
    <Section
      title={(
        <Box inline color={color}>{title}</Box>
      )}
      buttons={(
        <Box color={loop.flowing ? 'good' : 'label'}>
          {loop.flowing ? 'Flowing' : 'Still'}
        </Box>
      )}>
      <LabeledList>
        <LabeledList.Item label="Inlet">
          {loop.inlet_temperature + ' K, ' + loop.inlet_pressure + ' kPa'}
        </LabeledList.Item>
        <LabeledList.Item label="Outlet">
          {loop.outlet_temperature + ' K, ' + loop.outlet_pressure + ' kPa'}
        </LabeledList.Item>
      </LabeledList>
    </Section>
  );
};

export const ThermoelectricGenerator = props => {
  const { data } = useBackend(props);
  const { cold, hot } = data;
  let problem = null;
  if (!data.connected) {
    problem = 'Unable to connect to the power network!';
  } else if (!cold && !hot) {
    problem = 'Unable to locate any parts!';
  } else if (!hot) {
    problem = 'Unable to locate hot circulator!';
  } else if (!cold) {
    problem = 'Unable to locate cold circulator!';
  }
  if (problem) {
    return <NoticeBox>{problem}</NoticeBox>;
  }
  const difference = Math.round(
    (hot.inlet_temperature - cold.inlet_temperature) * 10) / 10;
  return (
    <Fragment>
      <Section>
        <LabeledList>
          <LabeledList.Item label="Output">
            <Box bold color={data.output_level > 0 ? 'good' : 'label'}>
              {data.output}
            </Box>
          </LabeledList.Item>
          <LabeledList.Item label="Inlet difference">
            <Box color={difference > 0 ? null : 'bad'}>
              {difference + ' K'}
            </Box>
          </LabeledList.Item>
        </LabeledList>
      </Section>
      <Flex>
        <Flex.Item grow={1} basis={0}>
          <Loop title="Cold loop" color="#65a9f3" loop={cold} />
        </Flex.Item>
        <Flex.Item grow={1} basis={0} ml={1}>
          <Loop title="Hot loop" color="#ff7266" loop={hot} />
        </Flex.Item>
      </Flex>
    </Fragment>
  );
};
