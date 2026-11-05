import { Fragment } from 'inferno';
import { useBackend } from '../backend';
import { Box, Button, Icon, LabeledList, NoticeBox, Section, Table } from '../components';

// hippie -- the R&D server controller and the experimentor
// (hippiestation/code/modules/research/research_machines_tgui.dm)

export const RdServerControl = props => {
  const { data } = useBackend(props);
  const { servers = [], points = [] } = data;
  return (
    <Fragment>
      <Section title="Research">
        <LabeledList>
          {points.map(point => (
            <LabeledList.Item key={point.type} label={point.type}>
              <b>{point.points}</b> points
              <Box inline color="label" ml={1}>
                (+{point.rate}/s)
              </Box>
            </LabeledList.Item>
          ))}
        </LabeledList>
      </Section>
      <Section title="Servers">
        {servers.length === 0 && (
          <Box color="bad">No servers found.</Box>
        )}
        <Table>
          {servers.length > 0 && (
            <Table.Row header>
              <Table.Cell>Server</Table.Cell>
              <Table.Cell>Status</Table.Cell>
              <Table.Cell textAlign="right">Room</Table.Cell>
              <Table.Cell textAlign="right">Output</Table.Cell>
            </Table.Row>
          )}
          {servers.map(server => (
            <Table.Row key={server.id + server.name}>
              <Table.Cell>
                <Icon name="server" mr={1} />
                {server.name}
              </Table.Cell>
              <Table.Cell color={server.working ? 'good' : 'bad'}>
                {server.status}
              </Table.Cell>
              <Table.Cell
                textAlign="right"
                color={server.hot ? 'bad' : 'label'}>
                {server.temperature}&deg;C
              </Table.Cell>
              <Table.Cell
                textAlign="right"
                color={server.output < server.best ? 'average' : 'good'}>
                {server.output}
              </Table.Cell>
            </Table.Row>
          ))}
        </Table>
        <Box color="label" mt={1}>
          Servers make less research the hotter their room is.
        </Box>
      </Section>
    </Fragment>
  );
};

const TESTS = [
  [1, 'Poke', 'hand-point-up'],
  [2, 'Irradiate', 'radiation'],
  [3, 'Gas', 'cloud'],
  [4, 'Burn', 'fire'],
  [5, 'Freeze', 'snowflake'],
  [6, 'Destroy', 'trash'],
];

export const Experimentor = props => {
  const { act, data } = useBackend(props);
  const { linked, item, relic, cooling, boosts = [] } = data;
  return (
    <Fragment>
      {!linked && (
        <NoticeBox>
          Not linked to an R&amp;D console: no research from experiments.
          <Button
            ml={1}
            icon="search"
            content="Scan"
            onClick={() => act('search')} />
        </NoticeBox>
      )}
      <Section
        title={item || 'Nothing loaded'}
        buttons={!!item && (
          <Button
            icon="eject"
            content="Eject"
            onClick={() => act('eject')} />
        )}>
        {!item && (
          <Box color="label">Put an item in by hand to experiment on it.</Box>
        )}
        {!!item && (
          <Fragment>
            {!!cooling && (
              <Box color="average" mb={1}>
                <Icon name="hourglass-half" mr={1} />
                Cooling down...
              </Box>
            )}
            {TESTS.map(test => (
              <Button
                key={test[0]}
                icon={test[2]}
                disabled={cooling}
                color={test[0] === 6 ? 'bad' : null}
                content={test[1]}
                onClick={() => act('test', { test: test[0] })} />
            ))}
            {!!relic && (
              <Button
                icon="question"
                disabled={cooling}
                color="good"
                content="Discover"
                onClick={() => act('test', { test: 7 })} />
            )}
          </Fragment>
        )}
      </Section>
      {boosts.length > 0 && (
        <Section title="Research boosts">
          <Table>
            {boosts.map(boost => (
              <Table.Row key={boost.name}>
                <Table.Cell>{boost.name}</Table.Cell>
                <Table.Cell collapsing textAlign="right">
                  {boost.points}
                </Table.Cell>
                <Table.Cell
                  collapsing
                  pl={1}
                  color={boost.state === 'Boost available' ? 'good' : 'label'}>
                  {boost.state}
                </Table.Cell>
              </Table.Row>
            ))}
          </Table>
        </Section>
      )}
    </Fragment>
  );
};
