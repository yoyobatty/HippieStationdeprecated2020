import { Fragment } from 'inferno';
import { useBackend } from '../backend';
import { Box, Button, Input, LabeledList, NoticeBox, Section, Table } from '../components';
import { TelecommsMap } from './common/TelecommsMap';

// hippie -- the telecommunications monitor
// (hippiestation/.../telecomms/computers/telemonitor_tgui.dm)

const MachineRows = props => {
  const { machines, act } = props;
  return (
    <Table>
      {machines.map((machine, i) => (
        <Table.Row key={machine.id + i} className="candystripe">
          <Table.Cell px={0.5} py={0.5}>{machine.name}</Table.Cell>
          <Table.Cell px={0.5} color="label">{machine.id}</Table.Cell>
          <Table.Cell px={0.5} collapsing color={machine.on ? 'good' : 'bad'}>
            {machine.on ? 'On' : 'Off'}
          </Table.Cell>
          <Table.Cell px={0.5} collapsing>
            <Button
              icon="search"
              content="View"
              disabled={!machine.buffered}
              tooltip={machine.buffered ? null : 'Not in the buffer'}
              tooltipPosition="left"
              onClick={() => act('view', { id: machine.id })} />
          </Table.Cell>
        </Table.Row>
      ))}
    </Table>
  );
};

export const TelecommsMonitor = props => {
  const { act, data } = useBackend(props);
  const machines = data.machines || [];
  const selected = data.selected;
  let networkButton = (
    <Button
      icon="satellite-dish"
      content="Probe network"
      onClick={() => act('probe')} />
  );
  if (machines.length > 0) {
    networkButton = (
      <Button
        icon="trash"
        content="Flush buffer"
        onClick={() => act('flush')} />
    );
  }
  return (
    <Fragment>
      <Section
        title="Network"
        buttons={networkButton}>
        <Input
          fluid
          value={data.network}
          onChange={(e, value) => act('network', { network: value })} />
      </Section>
      {!!data.notice && (
        <NoticeBox>
          <Box color={data.failed ? 'bad' : null}>{data.notice}</Box>
        </NoticeBox>
      )}
      {!!selected && (
        <Section
          title={selected.name + ' (' + selected.id + ')'}
          buttons={(
            <Button
              icon="arrow-left"
              content="Main menu"
              onClick={() => act('main')} />
          )}>
          <LabeledList>
            <LabeledList.Item
              label="Status"
              color={selected.on ? 'good' : 'bad'}>
              {selected.on ? 'On' : 'Off'}
            </LabeledList.Item>
          </LabeledList>
          <Box mt={1} mb={0.5} color="label">Linked entities</Box>
          {selected.links.length === 0 && (
            <Box color="label">None.</Box>
          )}
          <MachineRows machines={selected.links} act={act} />
        </Section>
      )}
      {!selected && machines.length > 0 && (
        <Section title="Network map">
          <TelecommsMap map={data.map} />
        </Section>
      )}
      {!selected && (
        <Section title="Detected network entities">
          {machines.length === 0 && (
            <Box color="label">
              None in the buffer: probe the network to find them.
            </Box>
          )}
          <MachineRows machines={machines} act={act} />
        </Section>
      )}
    </Fragment>
  );
};
