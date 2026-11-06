import { Fragment } from 'inferno';
import { useBackend } from '../backend';
import { Box, Button, Input, LabeledList, NoticeBox, Section } from '../components';
import { GasBar, GasLegend, kelvinToCelsius } from './common/AtmosBits';

// hippie -- the tank transfer valve and the cyborg frame's boot debug moved
// off their old HTML windows. Data from hippiestation/code/game/objects/
// items/items_tgui.dm.

const Tank = props => {
  const { act, title, tank, removeAction } = props;
  return (
    <Section
      title={title}
      buttons={!!tank && (
        <Button
          icon="eject"
          content="Remove"
          onClick={() => act(removeAction)} />
      )}>
      {tank && (
        <Fragment>
          <Box mb={0.5}>
            <b>{tank.name}</b>
            <Box inline ml={1}>{tank.pressure} kPa</Box>
            <Box inline ml={1} color="label">
              {tank.temperature} K ({kelvinToCelsius(tank.temperature)} °C)
            </Box>
          </Box>
          <GasBar gases={tank.gases} />
          <GasLegend gases={tank.gases} showMoles />
        </Fragment>
      ) || (
        <Box color="label">None</Box>
      )}
    </Section>
  );
};

export const TransferValve = props => {
  const { act, data } = useBackend(props);
  const ready = data.tank_one && data.tank_two;
  return (
    <Fragment>
      <Tank
        act={act}
        title="Attachment one"
        tank={data.tank_one}
        removeAction="remove_one" />
      <Tank
        act={act}
        title="Attachment two"
        tank={data.tank_two}
        removeAction="remove_two" />
      <Section
        title="Valve attachment"
        buttons={!!data.device && (
          <Fragment>
            <Button
              icon="cog"
              content="Configure"
              onClick={() => act('configure')} />
            <Button
              icon="eject"
              content="Remove"
              onClick={() => act('remove_device')} />
          </Fragment>
        )}>
        {data.device || <Box color="label">None</Box>}
      </Section>
      <Section>
        <Button
          fluid
          textAlign="center"
          fontSize="14px"
          icon={data.valve_open ? 'unlock' : 'lock'}
          color={data.valve_open ? 'bad' : 'default'}
          disabled={!ready && !data.valve_open}
          content={data.valve_open ? 'Valve: Open' : 'Valve: Closed'}
          onClick={() => act('valve')} />
      </Section>
    </Fragment>
  );
};

export const CyborgFrame = props => {
  const { act, data } = useBackend(props);
  const ais = data.ais || [];
  const toggles = [
    ['lawsync', 'LawSync Port', data.lawsync ? 'Open' : 'Closed', data.lawsync],
    ['aisync', 'AI Connection Port', data.aisync ? 'Open' : 'Closed',
      data.aisync],
    ['locomotion', 'Servo Motor Functions',
      data.locomotion ? 'Unlocked' : 'Locked', data.locomotion],
    ['panel', 'Panel Lock', data.panel_locked ? 'Engaged' : 'Disengaged',
      data.panel_locked],
  ];
  return (
    <Fragment>
      {!data.multitool && (
        <NoticeBox>You need a multitool!</NoticeBox>
      )}
      <Section>
        <LabeledList>
          <LabeledList.Item label="Designation">
            <Input
              width="200px"
              placeholder="Default Cyborg"
              value={data.name}
              onChange={(e, value) => act('name', { name: value })} />
          </LabeledList.Item>
          <LabeledList.Item label="Master AI">
            <Button
              content="Automatic"
              selected={!data.master}
              onClick={() => act('master', { ref: null })} />
            {ais.map(ai => (
              <Button
                key={ai.ref}
                content={ai.name}
                selected={data.master === ai.name}
                onClick={() => act('master', { ref: ai.ref })} />
            ))}
            {ais.length === 0 && (
              <Box inline color="label" ml={1}>No active AIs</Box>
            )}
          </LabeledList.Item>
          {toggles.map(toggle => (
            <LabeledList.Item key={toggle[0]} label={toggle[1]}>
              <Button
                content={toggle[2]}
                selected={toggle[3]}
                onClick={() => act(toggle[0])} />
            </LabeledList.Item>
          ))}
        </LabeledList>
      </Section>
    </Fragment>
  );
};
