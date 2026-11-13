import { Fragment } from 'inferno';
import { useBackend } from '../backend';
import { Box, Button, Input, Section, Table } from '../components';

// hippie -- Counts: running timers by the proc they'll call, and atoms or
// datums by type, with the change since the last count of that kind. Data
// and actions from hippiestation/code/modules/admin/verbs/debug_tools.dm.

const TABS = [
  ['timers', 'Timers'],
  ['atoms', 'Atoms'],
  ['datums', 'Datums'],
];

const signed = n => (n > 0 ? '+' + n : String(n));

const changeColor = n => {
  if (n > 0) {
    return 'bad';
  }
  if (n < 0) {
    return 'good';
  }
  return 'label';
};

const Summary = props => {
  const { data } = props;
  const { tab, total, kinds, at, took, queues, matched, rows = [] } = data;
  const parts = [
    `${total} ${tab}`,
    `${kinds} ${tab === 'timers' ? 'sources' : 'types'}`,
  ];
  if (queues) {
    parts.push(`buckets ${queues[0]}, later ${queues[1]}`
      + `, client time ${queues[2]}`);
  }
  parts.push(`at ${at}` + (took > 0 ? `, ${took} s` : ''));
  return (
    <Box color="label">
      {parts.join(' · ')}
      {matched > rows.length && ` · top ${rows.length} of ${matched}`}
    </Box>
  );
};

export const DebugCounts = props => {
  const { act, data } = useBackend(props);
  const {
    tab,
    sort,
    filter,
    busy,
    counted,
    has_before,
    rows = [],
  } = data;
  return (
    <Fragment>
      <Section>
        {TABS.map(([key, label]) => (
          <Button
            key={key}
            content={label}
            selected={tab === key}
            onClick={() => act('tab', { kind: key })} />
        ))}
        <Button
          icon="sync"
          content={busy ? 'Counting' : (counted ? 'Recount' : 'Count')}
          disabled={!!busy}
          onClick={() => act('count')} />
        <Button
          icon="download"
          content="JSON"
          disabled={!counted}
          onClick={() => act('json')} />
        <Input
          value={filter}
          placeholder="Filter"
          onChange={(e, value) => act('filter', { text: value })} />
      </Section>
      <Section>
        {!counted && (
          <Box color="label">
            {busy ? 'Counting' : 'Not counted'}
          </Box>
        )}
        {!!counted && (
          <Fragment>
            <Summary data={data} />
            <Table mt={1}>
              <Table.Row header>
                <Table.Cell>
                  {tab === 'timers' ? 'Proc' : 'Type'}
                </Table.Cell>
                <Table.Cell collapsing textAlign="right">
                  <Button
                    content="Count"
                    selected={sort === 'count'}
                    onClick={() => act('sort', { by: 'count' })} />
                </Table.Cell>
                <Table.Cell collapsing textAlign="right">
                  <Button
                    content="Change"
                    selected={sort === 'change'}
                    disabled={!has_before}
                    onClick={() => act('sort', { by: 'change' })} />
                </Table.Cell>
              </Table.Row>
              {rows.map(row => (
                <Table.Row key={row.name}>
                  <Table.Cell>
                    {row.name}
                  </Table.Cell>
                  <Table.Cell textAlign="right">
                    {row.count}
                  </Table.Cell>
                  <Table.Cell textAlign="right">
                    {row.change === null ? (
                      <Box color="label">-</Box>
                    ) : (
                      <Box color={changeColor(row.change)}>
                        {signed(row.change)}
                      </Box>
                    )}
                  </Table.Cell>
                </Table.Row>
              ))}
            </Table>
          </Fragment>
        )}
      </Section>
    </Fragment>
  );
};
