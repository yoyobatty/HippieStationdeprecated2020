import { Fragment } from 'inferno';
import { useBackend } from '../backend';
import { Box, Button, Icon, LabeledList, NoticeBox, Section } from '../components';

// hippie -- turrets (hippiestation/code/game/machinery/turret_tgui.dm): a
// portable turret's own settings, and the wall turret control panel

export const PortableTurret = props => {
  const { act, data } = useBackend(props);
  const {
    on,
    anchored,
    locked,
    manual,
    canHack,
    settings = [],
  } = data;
  return (
    <Fragment>
      {!!locked && (
        <NoticeBox>
          <Icon name="lock" mr={1} />
          Behaviour controls are locked. Swipe an ID to unlock them.
        </NoticeBox>
      )}
      <Section
        title="Turret"
        buttons={(
          <Button
            icon="power-off"
            selected={on}
            disabled={locked}
            content={on ? 'On' : 'Off'}
            tooltip={!anchored ? 'Secure it to the floor first' : null}
            onClick={() => act('power')} />
        )}>
        {!anchored && (
          <Box color="average">Not secured to the floor.</Box>
        )}
        {!!manual && (
          <Box color="bad">Remote control protocol enabled.</Box>
        )}
        {!!canHack && (
          <Button
            icon="gamepad"
            content="Assume direct control"
            onClick={() => act('manual')} />
        )}
      </Section>
      <Section title="Targets">
        {settings.map(setting => (
          <Button
            key={setting.key}
            fluid
            color="transparent"
            disabled={locked}
            icon={setting.on ? 'check-square-o' : 'square-o'}
            content={setting.name}
            onClick={() => act('setting', { key: setting.key })} />
        ))}
      </Section>
    </Fragment>
  );
};

export const TurretControl = props => {
  const { act, data } = useBackend(props);
  const {
    locked,
    silicon,
    enabled,
    lethal,
    turrets = [],
  } = data;
  return (
    <Fragment>
      {!silicon && (
        <NoticeBox>
          <Icon name={locked ? 'lock' : 'lock-open'} mr={1} />
          Swipe an ID card to {locked ? 'unlock' : 'lock'} this panel.
        </NoticeBox>
      )}
      <Section title="Turrets">
        <LabeledList>
          <LabeledList.Item label="Turrets">
            <Button
              icon="power-off"
              selected={enabled}
              disabled={locked}
              content={enabled ? 'Active' : 'Inactive'}
              onClick={() => act('power')} />
          </LabeledList.Item>
          <LabeledList.Item label="Mode">
            <Button
              icon="bolt"
              selected={!lethal}
              disabled={locked}
              content="Stun"
              onClick={() => lethal && act('lethal')} />
            <Button
              icon="skull-crossbones"
              color={lethal ? 'bad' : null}
              disabled={locked}
              content="Lethal"
              onClick={() => !lethal && act('lethal')} />
          </LabeledList.Item>
        </LabeledList>
      </Section>
      <Section title={'Linked turrets (' + turrets.length + ')'}>
        {turrets.length === 0 && (
          <Box color="label">No turrets in this area.</Box>
        )}
        {turrets.map((turret, i) => (
          <Box key={i} py={0.25}>
            <Icon name="crosshairs" mr={1} />
            {turret.name}
            <Box inline ml={1} color={turret.bad ? 'bad' : 'label'}>
              {turret.status}
            </Box>
          </Box>
        ))}
      </Section>
    </Fragment>
  );
};
