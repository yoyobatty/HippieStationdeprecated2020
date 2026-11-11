import { Component, Fragment } from 'inferno';
import { useBackend } from '../backend';
import { Box, Button, LabeledList, NoticeBox, ProgressBar, Section } from '../components';

// hippie -- the robotics control console
// (hippiestation/.../machinery/computer/robot_tgui.dm)

// A button that asks "Sure?" on the first click and does it on the second,
// in place of the old window's Confirm/Abort popup
class ConfirmButton extends Component {
  constructor() {
    super();
    this.state = { armed: false };
  }

  componentWillUnmount() {
    clearTimeout(this.timer);
  }

  render() {
    const { content, icon, color, disabled, onConfirm } = this.props;
    if (this.state.armed) {
      return (
        <Button
          icon="exclamation-triangle"
          content={content + '? Sure'}
          color="bad"
          disabled={disabled}
          onClick={() => {
            this.setState({ armed: false });
            onConfirm();
          }} />
      );
    }
    return (
      <Button
        icon={icon}
        content={content}
        color={color}
        disabled={disabled}
        onClick={() => {
          this.setState({ armed: true });
          clearTimeout(this.timer);
          this.timer = setTimeout(() => this.setState({ armed: false }), 4000);
        }} />
    );
  }
}

const Cyborg = props => {
  const { unit, access, act } = props;
  let statusColor = 'good';
  if (unit.status === 'Locked down') {
    statusColor = 'average';
  }
  if (unit.status === 'Not responding') {
    statusColor = 'bad';
  }
  let cell = null;
  if (unit.cell !== null && unit.cell !== undefined) {
    cell = <Box color="bad">No cell</Box>;
    if (unit.cell >= 0) {
      cell = (
        <ProgressBar
          value={unit.cell / 100}
          ranges={{
            good: [0.5, Infinity],
            average: [0.2, 0.5],
            bad: [-Infinity, 0.2],
          }}>
          {unit.cell + '%'}
        </ProgressBar>
      );
    }
  }
  return (
    <Section
      level={2}
      title={unit.name}
      buttons={(
        <Fragment>
          {!!unit.can_convert && (
            <Button
              icon="cog"
              content="Convert"
              color="average"
              onClick={() => act('convert', { ref: unit.ref })} />
          )}
          {!!unit.can_hack && (
            <Button
              icon="user-secret"
              content="Hack"
              onClick={() => act('hack', { ref: unit.ref })} />
          )}
          <ConfirmButton
            icon={unit.locked ? 'unlock' : 'lock'}
            content={unit.locked ? 'Release' : 'Lockdown'}
            disabled={!access}
            onConfirm={() => act('lockdown', { ref: unit.ref })} />
          <ConfirmButton
            icon="bomb"
            content="Destroy"
            color="bad"
            disabled={!access}
            onConfirm={() => act('destroy', { ref: unit.ref })} />
        </Fragment>
      )}>
      <LabeledList>
        <LabeledList.Item label="Status" color={statusColor}>
          {unit.status}
        </LabeledList.Item>
        {!!cell && <LabeledList.Item label="Cell">{cell}</LabeledList.Item>}
        <LabeledList.Item label="Module">{unit.module}</LabeledList.Item>
      </LabeledList>
    </Section>
  );
};

export const RoboticsConsole = props => {
  const { act, data } = useBackend(props);
  const groups = data.cyborgs || [];
  const drones = data.drones || [];
  return (
    <Fragment>
      {!data.access && (
        <NoticeBox>
          Access denied: view only.
        </NoticeBox>
      )}
      <Section title="Cyborgs">
        {groups.length === 0 && (
          <Box color="label">No cyborg units within access parameters.</Box>
        )}
        {groups.map(group => (
          <Section key={group.name} level={2} title={group.name}>
            {group.units.map(unit => (
              <Cyborg
                key={unit.ref}
                unit={unit}
                access={data.access}
                act={act} />
            ))}
          </Section>
        ))}
      </Section>
      <Section title="Drones">
        {drones.length === 0 && (
          <Box color="label">No drone units within access parameters.</Box>
        )}
        {drones.map(drone => (
          <Box key={drone.ref} className="candystripe" p={0.5}>
            <ConfirmButton
              icon="bomb"
              content="Destroy"
              color="bad"
              disabled={!data.access}
              onConfirm={() => act('destroy_drone', { ref: drone.ref })} />
            <Box inline ml={1}>{drone.name}</Box>
            <Box
              inline
              ml={1}
              color={drone.status === 'Normal' ? 'good' : 'bad'}>
              {drone.status}
            </Box>
          </Box>
        ))}
      </Section>
    </Fragment>
  );
};
