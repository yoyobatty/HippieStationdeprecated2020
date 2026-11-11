import { Fragment } from 'inferno';
import { useBackend } from '../backend';
import { Box, Button, Icon, LabeledList, NoticeBox, Section, Table } from '../components';

// hippie -- the experimentor
// (hippiestation/code/modules/research/research_machines_tgui.dm). The R&D
// server controller's window is ResearchDashboard.js.

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
          <Box color="label">No sample loaded.</Box>
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
