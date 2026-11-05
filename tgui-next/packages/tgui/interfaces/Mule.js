import { Fragment } from 'inferno';
import { useBackend } from '../backend';
import { Box, Button, Dropdown, Input, LabeledList, NoticeBox, ProgressBar, Section } from '../components';

// hippie -- the MULE (was tgui/src/interfaces/mulebot.ract); destination, home
// and ID are set here, not in pop-ups
// (hippiestation/code/modules/mob/living/simple_animal/bot/mulebot_tgui.dm)

export const Mule = props => {
  const { act, data } = useBackend(props);
  const {
    on,
    locked,
    siliconUser,
    mode,
    modeStatus,
    load,
    destination,
    home,
    id,
    cell,
    cellPercent,
    autoReturn,
    autoPickup,
    reportDelivery,
    haspai,
    beacons = [],
  } = data;
  const canControl = !locked || !!siliconUser;
  return (
    <Fragment>
      {!!siliconUser && (
        <NoticeBox>
          <Box inline mt={0.5}>
            Interface lock: {locked ? 'engaged' : 'disengaged'}
          </Box>
          <Button
            m={0}
            style={{ float: 'right' }}
            icon={locked ? 'lock' : 'unlock'}
            content={locked ? 'Unlock' : 'Lock'}
            onClick={() => act('lock')} />
        </NoticeBox>
      ) || (
        <NoticeBox>
          Swipe an ID card to {locked ? 'unlock' : 'lock'} this interface.
        </NoticeBox>
      )}
      <Section
        title="Status"
        buttons={canControl && (
          <Button
            icon="power-off"
            selected={on}
            disabled={!cell}
            content={on ? 'On' : 'Off'}
            onClick={() => act('power')} />
        ) || (
          <Box inline color={on ? 'good' : 'bad'}>
            {on ? 'On' : 'Off'}
          </Box>
        )}>
        <LabeledList>
          <LabeledList.Item label="Cell">
            {cell && (
              <ProgressBar
                value={cellPercent / 100}
                ranges={{
                  good: [0.5, Infinity],
                  average: [0.2, 0.5],
                  bad: [-Infinity, 0.2],
                }}>
                {cellPercent}%
              </ProgressBar>
            ) || (
              <Box color="bad">No cell</Box>
            )}
          </LabeledList.Item>
          <LabeledList.Item label="Mode" color={modeStatus || 'label'}>
            {mode}
          </LabeledList.Item>
          <LabeledList.Item
            label="Load"
            color={load ? 'good' : 'label'}
            buttons={canControl && !!load && (
              <Button
                icon="eject"
                content="Unload"
                onClick={() => act('unload')} />
            )}>
            {load || 'Nothing'}
          </LabeledList.Item>
        </LabeledList>
      </Section>
      {canControl && (
        <Section
          title="Delivery"
          buttons={(
            <Fragment>
              <Button
                icon="stop"
                content="Stop"
                onClick={() => act('stop')} />
              <Button
                icon="play"
                color="good"
                disabled={!destination}
                content="Go"
                onClick={() => act('go')} />
              <Button
                icon="home"
                content="Go home"
                onClick={() => act('home')} />
            </Fragment>
          )}>
          <LabeledList>
            <LabeledList.Item label="Destination">
              <Dropdown
                key={'dest' + destination}
                width="100%"
                over
                options={beacons}
                selected={destination || 'Pick a beacon'}
                onSelected={value => act('destination', { value })} />
            </LabeledList.Item>
            <LabeledList.Item label="Home">
              <Dropdown
                key={'home' + home}
                width="100%"
                over
                options={beacons}
                selected={home || 'Pick a beacon'}
                onSelected={value => act('sethome', { value })} />
            </LabeledList.Item>
            <LabeledList.Item label="ID">
              <Input
                fluid
                value={id}
                onChange={(e, value) => act('setid', { value })} />
            </LabeledList.Item>
          </LabeledList>
        </Section>
      )}
      {canControl && (
        <Section
          title="Settings"
          buttons={!!haspai && (
            <Button
              icon="eject"
              content="Eject pAI"
              onClick={() => act('ejectpai')} />
          )}>
          <Button
            fluid
            color="transparent"
            icon={autoReturn ? 'check-square-o' : 'square-o'}
            content="Go home after a delivery"
            onClick={() => act('autoret')} />
          <Button
            fluid
            color="transparent"
            icon={autoPickup ? 'check-square-o' : 'square-o'}
            content="Pick up a crate at the destination"
            onClick={() => act('autopick')} />
          <Button
            fluid
            color="transparent"
            icon={reportDelivery ? 'check-square-o' : 'square-o'}
            content="Report deliveries on the radio"
            onClick={() => act('report')} />
        </Section>
      )}
    </Fragment>
  );
};
