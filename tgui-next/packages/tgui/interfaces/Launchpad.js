import { Fragment } from 'inferno';
import { useBackend } from '../backend';
import { Box, Button, Icon, Input, LabeledList, NoticeBox, NumberInput, Section, Table } from '../components';

// hippie -- the launchpad console and the briefcase launchpad remote (were
// tgui/src/interfaces/launchpad_console.ract and launchpad_remote.ract); X, Y
// and the pad's name are typed here
// (hippiestation/code/game/machinery/launchpad_tgui.dm)

const ARROWS = [
  [
    ['up-left', 'arrow-up', -45], ['up', 'arrow-up', 0],
    ['up-right', 'arrow-up', 45],
  ],
  [
    ['left', 'arrow-left', 0], ['reset', 'crosshairs', 0],
    ['right', 'arrow-right', 0],
  ],
  [
    ['down-left', 'arrow-down', 45], ['down', 'arrow-down', 0],
    ['down-right', 'arrow-down', -45],
  ],
];

// Where the target sits against the pad's reach, drawn as a small radar
const Radar = props => {
  const { x, y, range } = props;
  const size = 116;
  const scale = (size / 2 - 6) / Math.max(range, 1);
  return (
    <Box
      position="relative"
      style={{
        width: size + 'px',
        height: size + 'px',
        border: '1px solid rgba(255, 255, 255, 0.2)',
        'border-radius': '50%',
        background: 'radial-gradient(circle, '
          + 'rgba(64, 160, 255, 0.15), rgba(0, 0, 0, 0.3))',
      }}>
      <Box
        position="absolute"
        style={{
          left: (size / 2 - 3) + 'px',
          top: (size / 2 - 3) + 'px',
          width: '6px',
          height: '6px',
          background: '#4c8cd9',
        }} />
      <Box
        position="absolute"
        style={{
          left: (size / 2 - 4 + x * scale) + 'px',
          top: (size / 2 - 4 - y * scale) + 'px',
          width: '8px',
          height: '8px',
          'border-radius': '50%',
          background: '#e0a020',
          'box-shadow': '0 0 6px #e0a020',
        }} />
    </Box>
  );
};

// The eight-way pad that nudges the target a tile at a time
const Arrows = props => {
  const { act, teleporting } = props;
  return (
    <Box>
      {ARROWS.map((row, i) => (
        <Box key={i}>
          {row.map(arrow => (
            <Button
              key={arrow[0]}
              width="28px"
              textAlign="center"
              disabled={teleporting}
              tooltip={arrow[0] === 'reset' ? 'Back on the pad' : null}
              onClick={() => act(arrow[0])}>
              <Icon name={arrow[1]} rotation={arrow[2]} />
            </Button>
          ))}
        </Box>
      ))}
    </Box>
  );
};

// The target typed or dragged, tiles east and north of the pad
const Offsets = props => {
  const { act, x, y, range } = props;
  return (
    <Fragment>
      <LabeledList>
        <LabeledList.Item label="East">
          <NumberInput
            value={x}
            minValue={-range}
            maxValue={range}
            step={1}
            stepPixelSize={8}
            width="52px"
            onChange={(e, value) => act('set_x', { value })} />
        </LabeledList.Item>
        <LabeledList.Item label="North">
          <NumberInput
            value={y}
            minValue={-range}
            maxValue={range}
            step={1}
            stepPixelSize={8}
            width="52px"
            onChange={(e, value) => act('set_y', { value })} />
        </LabeledList.Item>
      </LabeledList>
      <Box color="label" mt={1}>
        {Math.abs(y)} {y > 0 ? 'north' : 'south'},
        {' '}{Math.abs(x)} {x > 0 ? 'east' : 'west'}
        {' '}(reach {range})
      </Box>
    </Fragment>
  );
};

const LaunchpadControl = props => {
  const { act, data } = props;
  const {
    pad_name,
    x = 0,
    y = 0,
    range = 15,
    teleporting,
  } = data;
  return (
    <Fragment>
      <Section title="Launchpad">
        <LabeledList>
          <LabeledList.Item
            label="Name"
            buttons={(
              <Button
                icon="unlink"
                color="bad"
                content="Unlink"
                onClick={() => act('remove')} />
            )}>
            <Input
              fluid
              value={pad_name}
              maxLength={15}
              onChange={(e, value) => act('rename_to', { value })} />
          </LabeledList.Item>
        </LabeledList>
      </Section>
      <Section title="Target">
        <Table>
          <Table.Row>
            <Table.Cell collapsing pr={1}>
              <Arrows act={act} teleporting={teleporting} />
            </Table.Cell>
            <Table.Cell collapsing pr={1}>
              <Radar x={x} y={y} range={range} />
            </Table.Cell>
            <Table.Cell>
              <Offsets act={act} x={x} y={y} range={range} />
            </Table.Cell>
          </Table.Row>
        </Table>
      </Section>
      <Table>
        <Table.Row>
          <Table.Cell pr={0.5} style={{ width: '50%' }}>
            <Button
              fluid
              icon="upload"
              color="good"
              textAlign="center"
              disabled={teleporting}
              content="Launch"
              tooltip="Send everything on the pad to the target"
              onClick={() => act('launch')} />
          </Table.Cell>
          <Table.Cell pl={0.5} style={{ width: '50%' }}>
            <Button
              fluid
              icon="download"
              textAlign="center"
              disabled={teleporting}
              content="Pull"
              tooltip="Bring everything at the target to the pad"
              onClick={() => act('pull')} />
          </Table.Cell>
        </Table.Row>
      </Table>
    </Fragment>
  );
};

export const LaunchpadConsole = props => {
  const { act, data } = useBackend(props);
  const { screen, launchpads = [], pad_active } = data;
  if (screen === 'empty') {
    return (
      <NoticeBox>
        No launchpad linked. Link one with a multitool.
      </NoticeBox>
    );
  }
  if (screen === 'select') {
    return (
      <Section title="Launchpads">
        {launchpads.map(pad => (
          <Button
            key={pad.id}
            fluid
            icon="rocket"
            disabled={pad.inactive}
            content={pad.name + (pad.inactive ? ' (no power)' : '')}
            onClick={() => act('select_pad', { id: pad.id })} />
        ))}
      </Section>
    );
  }
  return (
    <Fragment>
      <Button
        icon="arrow-left"
        content="All launchpads"
        mb={1}
        onClick={() => act('return')} />
      {!pad_active && (
        <NoticeBox>Launchpad not responding.</NoticeBox>
      ) || (
        <LaunchpadControl act={act} data={data} />
      )}
    </Fragment>
  );
};

export const LaunchpadRemote = props => {
  const { act, data } = useBackend(props);
  if (!data.has_pad) {
    return (
      <NoticeBox>
        No launchpad found. Link the remote to a launchpad.
      </NoticeBox>
    );
  }
  if (data.pad_closed) {
    return (
      <NoticeBox>
        The launchpad is closed. Open the briefcase to use it.
      </NoticeBox>
    );
  }
  return <LaunchpadControl act={act} data={data} />;
};
