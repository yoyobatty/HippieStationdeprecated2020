import { Fragment } from 'inferno';
import { useBackend } from '../backend';
import { Box, Button, Input, Section, Table } from '../components';

// hippie -- Profiler: the procs' times from whichever profiler SSprofiler
// runs, with a mark to see only what's been added since, and BYOND's
// SendMaps profile as a tree. In place of BYOND's ?debug=profile pages.
// Data and actions from hippiestation/code/modules/admin/verbs/debug_tools.dm.

const secs = n => (typeof n === 'number' ? n.toFixed(3) : '-');

const SortButton = props => {
  const { act, sort, by, label, disabled } = props;
  return (
    <Button
      content={label}
      selected={sort === by}
      disabled={disabled}
      onClick={() => act('sort', { by })} />
  );
};

const ProcsTab = props => {
  const { act, data } = props;
  const {
    engine,
    sort,
    filter,
    read_at,
    mark_at,
    span,
    idle,
    matched,
    has_calls,
    rows = [],
  } = data;
  if (!engine) {
    return (
      <Section>
        <Box color="label">Profiler off</Box>
      </Section>
    );
  }
  const parts = [engine, `read ${read_at}`];
  parts.push(mark_at ? `since mark ${mark_at}, ${span} s` : 'since start');
  if (typeof idle === 'number') {
    parts.push(`idle ${secs(idle)} s`);
  }
  if (matched > rows.length) {
    parts.push(`top ${rows.length} of ${matched}`);
  }
  return (
    <Fragment>
      <Section>
        <Button
          icon="map-marker-alt"
          content="Mark"
          onClick={() => act('mark')} />
        <Button
          content="Since start"
          disabled={!mark_at}
          onClick={() => act('unmark')} />
        <Input
          value={filter}
          placeholder="Filter"
          onChange={(e, value) => act('filter', { text: value })} />
      </Section>
      <Section>
        <Box color="label">{parts.join(' · ')}</Box>
        {rows.length === 0 && (
          <Box mt={1} color="label">
            {mark_at ? 'Nothing since the mark' : 'No procs'}
          </Box>
        )}
        {rows.length > 0 && (
          <Table mt={1}>
            <Table.Row header>
              <Table.Cell>Proc</Table.Cell>
              <Table.Cell collapsing textAlign="right">
                <SortButton act={act} sort={sort} by="self" label="Self" />
              </Table.Cell>
              <Table.Cell collapsing textAlign="right">
                <SortButton act={act} sort={sort} by="total" label="Total" />
              </Table.Cell>
              {!!has_calls && (
                <Table.Cell collapsing textAlign="right">
                  <SortButton
                    act={act}
                    sort={sort}
                    by="calls"
                    label="Calls" />
                </Table.Cell>
              )}
            </Table.Row>
            {rows.map(row => (
              <Table.Row key={row.name}>
                <Table.Cell>{row.name}</Table.Cell>
                <Table.Cell textAlign="right">{secs(row.self)}</Table.Cell>
                <Table.Cell textAlign="right">{secs(row.total)}</Table.Cell>
                {!!has_calls && (
                  <Table.Cell textAlign="right">
                    {typeof row.calls === 'number' ? row.calls : '-'}
                  </Table.Cell>
                )}
              </Table.Row>
            ))}
          </Table>
        )}
      </Section>
    </Fragment>
  );
};

// Time rows in ms, per call in us; the count rows (movables examined) as
// counts. Parents BYOND has no figures for stay blank.
const smValue = row => {
  if (typeof row.value !== 'number') {
    return '';
  }
  return row.time ? (row.value * 1000).toFixed(1) : String(row.value);
};

const perCall = row => {
  if (typeof row.value !== 'number' || !row.calls) {
    return '';
  }
  if (row.time) {
    return (row.value / row.calls * 1e6).toFixed(1);
  }
  return (row.value / row.calls).toFixed(1);
};

const SendMapsTab = props => {
  const { act, data } = props;
  const { running, read_at, cleared_at, sm_rows = [] } = data;
  return (
    <Fragment>
      <Section>
        <Button
          icon={running ? 'stop' : 'play'}
          content={running ? 'Stop' : 'Start'}
          selected={!!running}
          onClick={() => act(running ? 'sm_stop' : 'sm_start')} />
        <Button
          icon="eraser"
          content="Clear"
          onClick={() => act('sm_clear')} />
      </Section>
      <Section>
        <Box color="label">
          {(running ? 'Running' : 'Stopped')
            + ` · read ${read_at}`
            + (cleared_at ? ` · since clear ${cleared_at}` : '')}
        </Box>
        {sm_rows.length === 0 && (
          <Box mt={1} color="label">No data</Box>
        )}
        {sm_rows.length > 0 && (
          <Table mt={1}>
            <Table.Row header>
              <Table.Cell>Part</Table.Cell>
              <Table.Cell collapsing textAlign="right">ms</Table.Cell>
              <Table.Cell collapsing textAlign="right">Calls</Table.Cell>
              <Table.Cell collapsing textAlign="right">us/call</Table.Cell>
            </Table.Row>
            {sm_rows.map((row, i) => (
              <Table.Row key={i}>
                <Table.Cell>
                  <Box
                    style={{ 'padding-left': (row.depth * 14) + 'px' }}
                    color={row.time || row.depth === 0 ? null : 'label'}
                    bold={row.depth === 0}>
                    {row.name}
                  </Box>
                </Table.Cell>
                <Table.Cell textAlign="right">{smValue(row)}</Table.Cell>
                <Table.Cell textAlign="right">{row.calls}</Table.Cell>
                <Table.Cell textAlign="right">{perCall(row)}</Table.Cell>
              </Table.Row>
            ))}
          </Table>
        )}
      </Section>
    </Fragment>
  );
};

export const DebugProfiler = props => {
  const { act, data } = useBackend(props);
  const { tab } = data;
  return (
    <Fragment>
      <Section>
        <Button
          content="Procs"
          selected={tab === 'procs'}
          onClick={() => act('tab', { tab: 'procs' })} />
        <Button
          content="SendMaps"
          selected={tab === 'sendmaps'}
          onClick={() => act('tab', { tab: 'sendmaps' })} />
        <Button
          icon="sync"
          content="Refresh"
          onClick={() => act('refresh')} />
      </Section>
      {tab === 'procs'
        ? <ProcsTab act={act} data={data} />
        : <SendMapsTab act={act} data={data} />}
    </Fragment>
  );
};
