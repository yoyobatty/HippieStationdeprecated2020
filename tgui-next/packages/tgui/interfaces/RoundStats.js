import { decodeHtmlEntities } from 'common/string';
import { Fragment } from 'inferno';
import { useBackend } from '../backend';
import { Box, Button, Input, NoticeBox, Section, Table } from '../components';

// hippie -- Round Stats: past rounds, deaths, game modes and playtime, from
// hippiestation/code/modules/stats/round_stats.dm. Admins also get the round
// being played, keys, and anyone's playtime.

const TABS = [
  ['rounds', 'Rounds', 'list'],
  ['deaths', 'Deaths', 'skull'],
  ['modes', 'Modes', 'chess'],
  ['playtime', 'Playtime', 'clock'],
];

const text = value => decodeHtmlEntities(String(value || ''));

const length = minutes => {
  if (minutes === null || minutes === undefined) {
    return '-';
  }
  const h = Math.floor(minutes / 60);
  return h ? h + 'h ' + (minutes % 60) + 'm' : minutes + 'm';
};

// "2026-11-08 18:43:51" -> "11-08 18:43"
const when = value => (value ? String(value).slice(5, 16) : '-');

const DAMAGE = [
  ['brute', 'B', 'red'],
  ['burn', 'F', 'orange'],
  ['oxy', 'O', 'blue'],
  ['tox', 'T', 'green'],
  ['clone', 'C', 'teal'],
  ['brain', 'Br', 'pink'],
  ['stamina', 'S', 'grey'],
];

const Damage = props => {
  const { row } = props;
  const parts = DAMAGE.filter(([key]) => row[key] > 0);
  if (!parts.length) {
    return <Box color="label">-</Box>;
  }
  return parts.map(([key, short, color]) => (
    <Box key={key} inline mr={1} color={color}>
      {short}{row[key]}
    </Box>
  ));
};

const Rounds = props => {
  const { data, act } = props;
  const rows = data.rows || [];
  if (!rows.length) {
    return <Box color="label">No rounds</Box>;
  }
  return (
    <Table>
      <Table.Row header>
        <Table.Cell>Round</Table.Cell>
        <Table.Cell>Mode</Table.Cell>
        <Table.Cell>Result</Table.Cell>
        <Table.Cell>Length</Table.Cell>
        <Table.Cell>Deaths</Table.Cell>
        <Table.Cell>Map</Table.Cell>
        <Table.Cell>Started</Table.Cell>
        {!!data.admin && <Table.Cell>Server</Table.Cell>}
      </Table.Row>
      {rows.map(row => (
        <Table.Row key={row.id}>
          <Table.Cell>
            {row.id}
            {row.id === data.current_round && (
              <Box inline ml={1} color="average">now</Box>
            )}
          </Table.Cell>
          <Table.Cell>{text(row.mode) || '-'}</Table.Cell>
          <Table.Cell
            color={row.result ? null : 'label'}
            title={text(row.end_state)}>
            {text(row.result) || text(row.end_state) || '-'}
          </Table.Cell>
          <Table.Cell>{length(row.minutes)}</Table.Cell>
          <Table.Cell>
            <Button
              compact
              content={row.deaths}
              disabled={!row.deaths}
              onClick={() => act('tab', { tab: 'deaths', round: row.id })} />
          </Table.Cell>
          <Table.Cell title={text(row.station)}>
            {text(row.map) || '-'}
          </Table.Cell>
          <Table.Cell>{when(row.start)}</Table.Cell>
          {!!data.admin && (
            <Table.Cell color="label">
              {row.server} {row.commit}
            </Table.Cell>
          )}
        </Table.Row>
      ))}
    </Table>
  );
};

const Deaths = props => {
  const { data, act } = props;
  const rows = data.rows || [];
  return (
    <Fragment>
      <Box mb={1}>
        <Input
          width="220px"
          placeholder={data.admin
            ? 'Name, job, place or key'
            : 'Name, job or place'}
          value={data.search || ''}
          onChange={(e, value) => act('search', { search: value })} />
        {data.round_filter !== null && data.round_filter !== undefined && (
          <Button
            ml={1}
            icon="times"
            content={'Round ' + data.round_filter}
            onClick={() => act('round_filter', { round: null })} />
        )}
      </Box>
      {!rows.length && <Box color="label">No deaths</Box>}
      {!!rows.length && (
        <Table>
          <Table.Row header>
            <Table.Cell>Name</Table.Cell>
            <Table.Cell>Where</Table.Cell>
            <Table.Cell>Damage</Table.Cell>
            <Table.Cell>Last attacker</Table.Cell>
            <Table.Cell>Round</Table.Cell>
            <Table.Cell>Time</Table.Cell>
          </Table.Row>
          {rows.map(row => (
            <Fragment key={row.id}>
              <Table.Row>
                <Table.Cell>
                  <b>{text(row.name)}</b>
                  <Box color="label">
                    {text(row.job)}
                    {row.special ? ' (' + text(row.special) + ')' : ''}
                    {!!data.admin && row.key ? ' - ' + row.key : ''}
                  </Box>
                </Table.Cell>
                <Table.Cell>{text(row.where)}</Table.Cell>
                <Table.Cell>
                  {row.suicide
                    ? <Box color="bad">Suicide</Box>
                    : <Damage row={row} />}
                </Table.Cell>
                <Table.Cell>
                  {text(row.killer) || '-'}
                  {!!data.admin && row.killer_key && (
                    <Box color="label">{row.killer_key}</Box>
                  )}
                </Table.Cell>
                <Table.Cell>
                  <Button
                    compact
                    content={row.round}
                    color="transparent"
                    onClick={() => act('round_filter', { round: row.round })} />
                </Table.Cell>
                <Table.Cell>{String(row.time || '').slice(11, 16)}</Table.Cell>
              </Table.Row>
              {!!row.last_words && (
                <Table.Row>
                  <Table.Cell />
                  <Table.Cell colspan={5} color="label">
                    <i>&quot;{text(row.last_words)}&quot;</i>
                  </Table.Cell>
                </Table.Row>
              )}
            </Fragment>
          ))}
        </Table>
      )}
    </Fragment>
  );
};

const Modes = props => {
  const { data } = props;
  const rows = data.rows || [];
  if (!rows.length) {
    return <Box color="label">No rounds</Box>;
  }
  return (
    <Table>
      <Table.Row header>
        <Table.Cell>Mode</Table.Cell>
        <Table.Cell>Rounds</Table.Cell>
        <Table.Cell>Avg length</Table.Cell>
        <Table.Cell>Results</Table.Cell>
      </Table.Row>
      {rows.map(row => (
        <Table.Row key={row.mode}>
          <Table.Cell><b>{text(row.mode)}</b></Table.Cell>
          <Table.Cell>{row.rounds}</Table.Cell>
          <Table.Cell>{length(row.minutes)}</Table.Cell>
          <Table.Cell>
            {(row.results || []).map(r => (
              <Box key={r.result} inline mr={2}>
                {text(r.result)} <Box inline color="label">{r.rounds}</Box>
              </Box>
            ))}
          </Table.Cell>
        </Table.Row>
      ))}
    </Table>
  );
};

const Playtime = props => {
  const { data, act } = props;
  const rows = data.rows || [];
  const total = rows.reduce((sum, row) => (
    row.job === 'Living' || row.job === 'Ghost' ? sum + row.minutes : sum
  ), 0);
  return (
    <Fragment>
      {!!data.admin && (
        <Box mb={1}>
          Key{' '}
          <Input
            width="180px"
            value={data.playtime_ckey || ''}
            onChange={(e, value) => act('playtime_ckey', { ckey: value })} />
        </Box>
      )}
      {!rows.length && <Box color="label">No time logged</Box>}
      {!!rows.length && (
        <Fragment>
          <Box mb={1}>
            Total <b>{length(total)}</b>
          </Box>
          <Table>
            {rows.map(row => (
              <Table.Row key={row.job}>
                <Table.Cell>{text(row.job)}</Table.Cell>
                <Table.Cell collapsing textAlign="right">
                  {length(row.minutes)}
                </Table.Cell>
              </Table.Row>
            ))}
          </Table>
        </Fragment>
      )}
    </Fragment>
  );
};

const PANES = {
  rounds: Rounds,
  deaths: Deaths,
  modes: Modes,
  playtime: Playtime,
};

export const RoundStats = props => {
  const { act, data } = useBackend(props);
  const Pane = PANES[data.tab] || Rounds;
  return (
    <Fragment>
      <Box mb={1}>
        {TABS.map(([key, name, icon]) => (
          <Button
            key={key}
            icon={icon}
            content={name}
            selected={data.tab === key}
            onClick={() => act('tab', { tab: key })} />
        ))}
        <Button
          icon="sync"
          content={data.loading ? 'Reading' : 'Refresh'}
          disabled={!!data.loading}
          style={{ float: 'right' }}
          onClick={() => act('refresh')} />
      </Box>
      {!!data.error && <NoticeBox>{data.error}</NoticeBox>}
      {!data.error && (
        <Section>
          <Pane data={data} act={act} />
        </Section>
      )}
    </Fragment>
  );
};
