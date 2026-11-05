import { Fragment } from 'inferno';
import { useBackend } from '../backend';
import { Box, Button, LabeledList, NoticeBox, Section } from '../components';

// hippie -- the teleporter control console (hippiestation/code/game/
// machinery/computer/teleporter_tgui.dm): the beacons, implants or gate
// stations to lock onto are listed here, where the old one asked in a pop-up.

export const Teleporter = props => {
  const { act, data } = useBackend(props);
  const {
    station,
    hub,
    regime,
    calibrating,
    calibrated,
    engaged,
    target,
    choices = [],
  } = data;
  if (!station) {
    return <NoticeBox>No power station linked.</NoticeBox>;
  }
  if (!hub) {
    return <NoticeBox>No hub linked.</NoticeBox>;
  }
  const gate = regime === 'Gate';
  let calibration = calibrated ? 'Optimal' : 'Sub-optimal';
  let calibrationColor = calibrated ? 'good' : 'bad';
  if (calibrating) {
    calibration = 'In progress...';
    calibrationColor = 'average';
  }
  const iconFor = choice => {
    if (gate) {
      return 'dungeon';
    }
    return choice.implant ? 'user' : 'broadcast-tower';
  };
  return (
    <Fragment>
      <Section title="Teleporter">
        <LabeledList>
          <LabeledList.Item label="Regime">
            <Button
              selected={!gate}
              disabled={calibrating}
              content="Teleporter"
              onClick={() => gate && act('regime')} />
            <Button
              selected={gate}
              disabled={calibrating}
              content="Gate"
              onClick={() => !gate && act('regime')} />
          </LabeledList.Item>
          <LabeledList.Item label="Target" color={target ? null : 'label'}>
            {target ? target + (gate ? ' teleporter' : '') : 'None'}
          </LabeledList.Item>
          <LabeledList.Item
            label="Calibration"
            color={calibrationColor}
            buttons={(
              <Button
                icon="crosshairs"
                disabled={!target || calibrating || calibrated}
                content="Calibrate"
                onClick={() => act('calibrate')} />
            )}>
            {calibration}
          </LabeledList.Item>
          <LabeledList.Item
            label="Station"
            color={engaged ? 'good' : 'label'}>
            {engaged ? 'Engaged' : 'Not engaged: switch it on at the station'}
          </LabeledList.Item>
        </LabeledList>
      </Section>
      <Section title={gate ? 'Gate stations' : 'Beacons and implants'}>
        {choices.length === 0 && (
          <Box color="label">
            {gate
              ? 'No active connected stations.'
              : 'Nothing to lock onto.'}
          </Box>
        )}
        {choices.map(choice => (
          <Button
            key={choice.name}
            fluid
            icon={iconFor(choice)}
            selected={choice.current}
            disabled={calibrating}
            content={choice.name}
            onClick={() => act('target', { name: choice.name })} />
        ))}
      </Section>
    </Fragment>
  );
};
