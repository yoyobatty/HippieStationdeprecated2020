import { Fragment } from 'inferno';
import { useBackend } from '../backend';
import { Box, Button, Input, LabeledList, NoticeBox, Section, Table } from '../components';

// hippie -- the telecommunications server monitor
// (hippiestation/.../telecomms/computers/logbrowser_tgui.dm)

const KIND_COLOR = {
  speech: 'good',
  error: 'bad',
  other: 'label',
};

const LogEntry = props => {
  const { entry, act } = props;
  return (
    <Section
      level={2}
      title={(
        <Box inline color={KIND_COLOR[entry.kind]}>{entry.name}</Box>
      )}
      buttons={(
        <Button
          icon="trash"
          color="transparent"
          content="Delete"
          onClick={() => act('delete', { index: entry.index })} />
      )}>
      <LabeledList>
        {entry.kind !== 'error' && (
          <LabeledList.Item label="Data type">{entry.type}</LabeledList.Item>
        )}
        {entry.kind === 'speech' && (
          <LabeledList.Item label="Source">
            {entry.source + ' (Job: ' + entry.job + ')'}
          </LabeledList.Item>
        )}
        {entry.kind === 'speech' && (
          <LabeledList.Item label="Class">{entry.race}</LabeledList.Item>
        )}
        <LabeledList.Item label={entry.kind === 'error' ? 'Error' : 'Contents'}>
          {entry.message}
        </LabeledList.Item>
      </LabeledList>
    </Section>
  );
};

export const TelecommsLogs = props => {
  const { act, data } = useBackend(props);
  const servers = data.servers || [];
  const selected = data.selected;
  let networkButton = (
    <Button
      icon="satellite-dish"
      content="Scan"
      onClick={() => act('scan')} />
  );
  if (servers.length > 0) {
    networkButton = (
      <Button
        icon="trash"
        content="Flush buffer"
        onClick={() => act('flush')} />
    );
  }
  return (
    <Fragment>
      <Section title="Network" buttons={networkButton}>
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
          title={selected.id}
          buttons={(
            <Button
              icon="arrow-left"
              content="Main menu"
              onClick={() => act('main')} />
          )}>
          <LabeledList>
            <LabeledList.Item label="Recorded traffic">
              {selected.traffic}
            </LabeledList.Item>
          </LabeledList>
          <Box mt={1}>
            {selected.logs.length === 0 && (
              <Box color="label">No stored logs.</Box>
            )}
            {selected.logs.map(entry => (
              <LogEntry key={entry.index} entry={entry} act={act} />
            ))}
          </Box>
        </Section>
      )}
      {!selected && (
        <Section title="Detected telecommunication servers">
          {servers.length === 0 && (
            <Box color="label">No servers detected: scan for them.</Box>
          )}
          <Table>
            {servers.map(server => (
              <Table.Row key={server.id} className="candystripe">
                <Table.Cell px={0.5} py={0.5}>{server.name}</Table.Cell>
                <Table.Cell px={0.5} color="label">{server.id}</Table.Cell>
                <Table.Cell px={0.5} collapsing>
                  <Button
                    icon="search"
                    content="View"
                    onClick={() => act('view', { id: server.id })} />
                </Table.Cell>
              </Table.Row>
            ))}
          </Table>
        </Section>
      )}
    </Fragment>
  );
};
