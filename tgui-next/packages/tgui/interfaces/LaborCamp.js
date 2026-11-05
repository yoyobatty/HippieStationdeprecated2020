import { Fragment } from 'inferno';
import { useBackend } from '../backend';
import { Box, Button, LabeledList, NumberInput, ProgressBar, Section, Table } from '../components';

// hippie -- the labor camp teleporter console and the camp's point claim
// console (were tgui/src/interfaces/gulag_console.ract and
// labor_claim_console.ract); the goal is typed here
// (hippiestation/code/game/machinery/computer/gulag_tgui.dm)

const jailed = status => status === 'Arrest' || status === 'Incarcerated';

export const GulagConsole = props => {
  const { act, data } = useBackend(props);
  const {
    teleporter,
    teleporter_location,
    teleporter_lock,
    teleporter_state_open,
    beacon,
    beacon_location,
    id,
    id_name,
    goal,
    prisoner = {},
    can_teleport,
  } = data;
  return (
    <Fragment>
      <Section title="Teleporter">
        <LabeledList>
          <LabeledList.Item
            label="Pod"
            color={teleporter ? 'good' : 'bad'}
            buttons={!teleporter && (
              <Button
                icon="search"
                content="Scan"
                onClick={() => act('scan_teleporter')} />
            )}>
            {teleporter ? 'Connected ' + teleporter_location : 'Not connected'}
          </LabeledList.Item>
          {!!teleporter && (
            <LabeledList.Item label="Door">
              <Button
                icon={teleporter_state_open ? 'door-open' : 'door-closed'}
                disabled={teleporter_lock}
                content={teleporter_state_open ? 'Open' : 'Closed'}
                onClick={() => act('toggle_open')} />
              <Button
                icon={teleporter_lock ? 'lock' : 'unlock'}
                selected={teleporter_lock}
                disabled={teleporter_state_open}
                content={teleporter_lock ? 'Locked' : 'Unlocked'}
                onClick={() => act('teleporter_lock')} />
            </LabeledList.Item>
          )}
          <LabeledList.Item
            label="Beacon"
            color={beacon ? 'good' : 'bad'}
            buttons={!beacon && (
              <Button
                icon="search"
                content="Scan"
                onClick={() => act('scan_beacon')} />
            )}>
            {beacon ? 'Connected ' + beacon_location : 'Not connected'}
          </LabeledList.Item>
        </LabeledList>
      </Section>
      <Section title="Prisoner">
        <LabeledList>
          <LabeledList.Item label="In the pod">
            {prisoner.name || (
              <Box color="label">Nobody</Box>
            )}
          </LabeledList.Item>
          {!!prisoner.name && (
            <LabeledList.Item
              label="Criminal status"
              color={jailed(prisoner.crimstat) ? 'bad' : 'average'}>
              {prisoner.crimstat || 'No record'}
            </LabeledList.Item>
          )}
          <LabeledList.Item label="Prisoner ID">
            <Button
              icon={id ? 'eject' : 'id-card'}
              content={id ? id_name : 'Insert a prisoner ID'}
              onClick={() => act('handle_id')} />
          </LabeledList.Item>
          {!!id && (
            <LabeledList.Item label="Point goal">
              <NumberInput
                value={goal}
                minValue={0}
                maxValue={1000}
                step={10}
                stepPixelSize={2}
                width="64px"
                onChange={(e, value) => act('set_goal', { value })} />
            </LabeledList.Item>
          )}
        </LabeledList>
      </Section>
      <Button
        fluid
        icon="bolt"
        color="bad"
        textAlign="center"
        disabled={!can_teleport}
        content="Process prisoner"
        tooltip={!can_teleport
          ? 'Needs someone in the pod and a prisoner ID'
          : null}
        onClick={() => act('teleport')} />
    </Fragment>
  );
};

export const LaborClaimConsole = props => {
  const { act, data } = useBackend(props);
  const {
    id,
    id_name,
    points = 0,
    goal = 0,
    unclaimed_points,
    ores = [],
    can_go_home,
    emagged,
  } = data;
  return (
    <Fragment>
      <Section title="Your points">
        <LabeledList>
          <LabeledList.Item label="ID">
            <Button
              icon={id ? 'eject' : 'id-card'}
              content={id ? id_name : 'Insert your prisoner ID'}
              onClick={() => act('handle_id')} />
          </LabeledList.Item>
          {!!id && (
            <LabeledList.Item label="Progress">
              <ProgressBar
                value={points}
                minValue={0}
                maxValue={Math.max(goal, 1)}
                color={points >= goal ? 'good' : 'average'}>
                {points} / {goal}
              </ProgressBar>
            </LabeledList.Item>
          )}
          <LabeledList.Item
            label="Unclaimed"
            buttons={!!id && (
              <Button
                icon="download"
                disabled={!unclaimed_points}
                content="Claim"
                onClick={() => act('claim_points')} />
            )}>
            {unclaimed_points || 0} points in the stacker
          </LabeledList.Item>
        </LabeledList>
      </Section>
      <Button
        fluid
        icon="shuttle-van"
        color={can_go_home ? 'good' : 'default'}
        textAlign="center"
        disabled={!can_go_home}
        content={emagged
          ? 'Move shuttle (no report to Security)'
          : 'Move shuttle'}
        tooltip={!can_go_home ? 'Meet your goal first' : null}
        onClick={() => act('move_shuttle')} />
      <Section title="What each sheet is worth" mt={1}>
        <Table>
          {ores.map(ore => (
            <Table.Row key={ore.ore}>
              <Table.Cell>{ore.ore}</Table.Cell>
              <Table.Cell collapsing textAlign="right" color="label">
                {ore.value}
              </Table.Cell>
            </Table.Row>
          ))}
        </Table>
      </Section>
    </Fragment>
  );
};
