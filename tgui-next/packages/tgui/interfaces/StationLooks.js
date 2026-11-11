import { useBackend } from '../backend';
import { Box, Button, Flex, Section, Table } from '../components';

// hippie -- Station Looks: this round's looks by slot with their weights.
// Click a look to force it (extras and histories toggle), the ban icon keeps
// it out of re-rolls. Data and actions from
// hippiestation/code/modules/station_looks/station_looks_window.dm.

const LookRow = props => {
  const { look, locked, act } = props;
  return (
    <Table.Row>
      <Table.Cell>
        <Button
          fluid
          content={look.name}
          icon={look.picked ? (look.on ? 'check-circle' : 'circle') : null}
          selected={look.picked}
          disabled={locked}
          onClick={() => act('force', { id: look.id })} />
      </Table.Cell>
      <Table.Cell collapsing textAlign="right">
        <Box color={look.weight > 0 ? 'label' : 'bad'} px={1}>
          {look.weight}
        </Box>
      </Table.Cell>
      <Table.Cell collapsing>
        <Button
          icon="ban"
          color={look.banned ? 'bad' : 'transparent'}
          tooltip={look.banned ? 'Banned' : 'Ban'}
          tooltipPosition="left"
          onClick={() => act('ban', { id: look.id })} />
      </Table.Cell>
    </Table.Row>
  );
};

export const StationLooks = props => {
  const { act, data } = useBackend(props);
  const slots = data.slots || [];
  return (
    <Box>
      <Flex align="center" mb={1}>
        <Flex.Item grow={1}>
          <Box color={data.started ? 'good' : 'average'}>
            {data.started ? 'On the station' : 'Goes on at round start'}
          </Box>
        </Flex.Item>
        <Flex.Item>
          <Button
            icon="dice"
            content="Re-roll all"
            onClick={() => act('reroll_all')} />
        </Flex.Item>
      </Flex>
      <Box color="label" mb={1}>
        {data.notes || 'No shift notes.'}
      </Box>
      {slots.map(slot => (
        <Section
          key={slot.id}
          title={slot.name}
          buttons={(
            <Button
              icon="dice"
              content="Re-roll"
              disabled={slot.locked}
              onClick={() => act('reroll', { slot: slot.id })} />
          )}>
          <Table>
            {slot.looks.map(look => (
              <LookRow
                key={look.id}
                look={look}
                locked={slot.locked}
                act={act} />
            ))}
          </Table>
          {slot.none > 0 && (
            <Box color="label" mt={0.5}>
              Nothing: {slot.none}
              {slot.most > 1 && ' · up to ' + slot.most}
            </Box>
          )}
        </Section>
      ))}
    </Box>
  );
};
