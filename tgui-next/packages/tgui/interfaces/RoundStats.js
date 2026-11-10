import { decodeHtmlEntities } from 'common/string';
import { Fragment } from 'inferno';
import { useBackend } from '../backend';
import { Box, Button, Input, LabeledList, NoticeBox, Section, Table } from '../components';

// hippie -- Round Stats: past rounds, deaths, game modes and playtime, from
// hippiestation/code/modules/stats/round_stats.dm. Admins also get the round
// being played, keys, anyone's playtime, and runtimes. A round's id opens its
// page: antagonists and objectives, the round-end numbers, its deaths.

const TABS = [
  ['rounds', 'Rounds', 'list'],
  ['deaths', 'Deaths', 'skull'],
  ['modes', 'Modes', 'chess'],
  ['playtime', 'Playtime', 'clock'],
];

const ADMIN_TABS = [
  ['runtimes', 'Runtimes', 'bug'],
];

// seconds -> "12:05"
const clock = seconds => {
  if (seconds === null || seconds === undefined) {
    return '-';
  }
  const m = Math.floor(seconds / 60);
  const s = seconds % 60;
  return m + ':' + (s < 10 ? '0' : '') + s;
};

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
            <Button
              compact
              color="transparent"
              content={row.id}
              onClick={() => act('round', { round: row.id })} />
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

const Objective = props => {
  const { objective, n } = props;
  const done = objective.result === 'SUCCESS';
  return (
    <Box>
      <Box inline color="label">#{n}</Box>{' '}
      {text(objective.text)}{' '}
      <Box inline bold color={done ? 'good' : 'bad'}>
        {done ? 'Success' : 'Fail'}
      </Box>
    </Box>
  );
};

const RoundPage = props => {
  const { data, act } = props;
  const page = data.page;
  if (!page || !page.round) {
    return <Box color="label">Reading</Box>;
  }
  const r = page.round;
  const s = page.stats || {};
  const antags = page.antags || [];
  const deaths = page.deaths || [];
  const runtimes = page.runtimes || [];
  return (
    <Fragment>
      <Box mb={1}>
        <Button
          icon="arrow-left"
          content="Rounds"
          onClick={() => act('tab', { tab: 'rounds' })} />
        {!!deaths.length && (
          <Button
            icon="skull"
            content="Deaths"
            onClick={() => act('tab', { tab: 'deaths', round: r.id })} />
        )}
      </Box>
      <LabeledList>
        <LabeledList.Item label="Round">
          {r.id}
          {r.id === data.current_round && (
            <Box inline ml={1} color="average">now</Box>
          )}
        </LabeledList.Item>
        <LabeledList.Item label="Mode">
          {text(r.mode) || '-'}
          {(r.result || r.end_state) && (
            <Box inline ml={1} color="label">
              {text(r.result) || text(r.end_state)}
            </Box>
          )}
        </LabeledList.Item>
        <LabeledList.Item label="Map">
          {text(r.map) || '-'}
          {!!r.station && (
            <Box inline ml={1} color="label">{text(r.station)}</Box>
          )}
        </LabeledList.Item>
        <LabeledList.Item label="Length">
          {length(r.minutes)}
          <Box inline ml={1} color="label">
            {when(r.start)} - {when(r.end)}
          </Box>
        </LabeledList.Item>
        {!!r.shuttle && (
          <LabeledList.Item label="Shuttle">{text(r.shuttle)}</LabeledList.Item>
        )}
        <LabeledList.Item label="Crew">
          {(s.players === null || s.players === undefined) && '-'}
          {s.players !== null && s.players !== undefined && (
            <Fragment>
              {s.players}
              <Box inline ml={2} color="good">Survived {s.survivors || 0}</Box>
              <Box inline ml={2} color="average">Escaped {s.escapees || 0}</Box>
              <Box inline ml={2} color="bad">Dead {r.deaths || 0}</Box>
            </Fragment>
          )}
        </LabeledList.Item>
        {!!data.admin && !!r.server && (
          <LabeledList.Item label="Server">
            <Box color="label">{r.server} {r.commit}</Box>
          </LabeledList.Item>
        )}
      </LabeledList>
      <Section title={'Antagonists (' + antags.length + ')'} level={2} mt={1}>
        {!antags.length && <Box color="label">None</Box>}
        {antags.map((a, i) => (
          <Box key={i} mb={1}>
            <Box>
              <b>{text(a.name)}</b>
              <Box inline ml={1} color="average">{text(a.role)}</Box>
              {!!a.team && (
                <Box inline ml={1} color="label">{text(a.team)}</Box>
              )}
              {!!data.admin && !!a.key && (
                <Box inline ml={1} color="label">- {a.key}</Box>
              )}
            </Box>
            {(a.objectives || []).map((o, n) => (
              <Objective key={n} objective={o} n={n + 1} />
            ))}
            {!(a.objectives || []).length && (
              <Box color="label">No objectives</Box>
            )}
          </Box>
        ))}
      </Section>
      <Section title={'Deaths (' + deaths.length + ')'} level={2}>
        {!deaths.length && <Box color="label">None</Box>}
        {!!deaths.length && (
          <Table>
            {deaths.map((d, i) => (
              <Table.Row key={i}>
                <Table.Cell collapsing color="label">
                  {String(d.time || '').slice(11, 16)}
                </Table.Cell>
                <Table.Cell>
                  <b>{text(d.name)}</b>
                  <Box inline ml={1} color="label">
                    {text(d.job)}
                    {d.special ? ' (' + text(d.special) + ')' : ''}
                    {!!data.admin && d.key ? ' - ' + d.key : ''}
                  </Box>
                </Table.Cell>
                <Table.Cell>{text(d.where)}</Table.Cell>
                <Table.Cell>
                  {d.suicide
                    ? <Box color="bad">Suicide</Box>
                    : (text(d.killer) || '-')}
                  {!!data.admin && d.killer_key && (
                    <Box inline ml={1} color="label">{d.killer_key}</Box>
                  )}
                </Table.Cell>
              </Table.Row>
            ))}
          </Table>
        )}
      </Section>
      {!!data.admin && (
        <Section title={'Runtimes (' + runtimes.length + ')'} level={2}>
          {!runtimes.length && <Box color="label">None</Box>}
          {!!runtimes.length && (
            <Table>
              {runtimes.map((e, i) => (
                <Table.Row key={i}>
                  <Table.Cell collapsing textAlign="right">
                    {e.count}
                  </Table.Cell>
                  <Table.Cell>
                    <Box color="label">{e.file}:{e.line}</Box>
                    {text(e.message)}
                  </Table.Cell>
                  <Table.Cell collapsing color="label">
                    {clock(e.first)}
                  </Table.Cell>
                </Table.Row>
              ))}
            </Table>
          )}
        </Section>
      )}
    </Fragment>
  );
};

const Runtimes = props => {
  const { data, act } = props;
  const rows = data.rows || [];
  if (!rows.length) {
    return <Box color="label">No runtimes</Box>;
  }
  return (
    <Table>
      <Table.Row header>
        <Table.Cell>Count</Table.Cell>
        <Table.Cell>Site</Table.Cell>
        <Table.Cell>Rounds</Table.Cell>
        <Table.Cell>Last</Table.Cell>
      </Table.Row>
      {rows.map(row => (
        <Table.Row key={row.file + ':' + row.line}>
          <Table.Cell collapsing textAlign="right">{row.count}</Table.Cell>
          <Table.Cell>
            <Box color="label">
              {row.file}:{row.line}
              {!!row.new && <Box inline ml={1} color="average">new</Box>}
            </Box>
            {text(row.message)}
          </Table.Cell>
          <Table.Cell collapsing>{row.rounds}</Table.Cell>
          <Table.Cell collapsing>
            <Button
              compact
              color="transparent"
              content={row.last}
              onClick={() => act('round', { round: row.last })} />
          </Table.Cell>
        </Table.Row>
      ))}
    </Table>
  );
};

const PANES = {
  rounds: Rounds,
  deaths: Deaths,
  modes: Modes,
  playtime: Playtime,
  round: RoundPage,
  runtimes: Runtimes,
};

export const RoundStats = props => {
  const { act, data } = useBackend(props);
  const Pane = PANES[data.tab] || Rounds;
  const tabs = data.admin ? TABS.concat(ADMIN_TABS) : TABS;
  return (
    <Fragment>
      <Box mb={1}>
        {tabs.map(([key, name, icon]) => (
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
