import { Fragment } from 'inferno';
import { useBackend } from '../backend';
import { Box, Button, Icon, Section, Table } from '../components';

// hippie -- the emergency shuttle's early launch console (was
// tgui/src/interfaces/emergency_shuttle_console.ract)

export const EmergencyShuttleConsole = props => {
  const { act, data } = useBackend(props);
  const {
    timer_str,
    engines_started,
    authorizations_remaining,
    authorizations = [],
    enabled,
    emagged,
  } = data;
  const needed = authorizations.length + authorizations_remaining;
  return (
    <Fragment>
      <Section textAlign="center">
        <Box color="label">
          {engines_started ? 'Launching' : 'Time until launch'}
        </Box>
        <Box fontSize="32px" bold color={engines_started ? 'average' : 'good'}>
          {timer_str}
        </Box>
        <Box color={engines_started ? 'average' : 'label'}>
          <Icon name="cog" spin={engines_started} mr={1} />
          Engines {engines_started ? 'online' : 'idle'}
        </Box>
      </Section>
      <Section
        title="Early launch"
        buttons={(
          <Box inline color={emagged ? 'bad' : 'label'}>
            {emagged ? 'ERROR' : authorizations_remaining + ' more needed'}
          </Box>
        )}>
        {!emagged && (
          <Box textAlign="center" mb={1}>
            {[...Array(needed)].map((x, i) => (
              <Icon
                key={i}
                mx={0.5}
                size={1.5}
                name={i < authorizations.length ? 'id-card' : 'id-card-o'}
                color={i < authorizations.length ? 'bad' : 'label'} />
            ))}
          </Box>
        )}
        <Button
          fluid
          icon="exclamation-triangle"
          color="bad"
          textAlign="center"
          disabled={!enabled}
          content="AUTHORIZE"
          onClick={() => act('authorize')} />
        <Table mt={0.5}>
          <Table.Row>
            <Table.Cell pr={0.5}>
              <Button
                fluid
                icon="minus"
                textAlign="center"
                disabled={!enabled}
                content="Repeal mine"
                onClick={() => act('repeal')} />
            </Table.Cell>
            <Table.Cell pl={0.5}>
              <Button
                fluid
                icon="times"
                textAlign="center"
                disabled={!enabled}
                content="Repeal all"
                onClick={() => act('abort')} />
            </Table.Cell>
          </Table.Row>
        </Table>
        {!enabled && (
          <Box color="label" mt={1}>
            {engines_started
              ? 'Past the point of no return.'
              : 'Only while the shuttle is docked at the station.'}
          </Box>
        )}
      </Section>
      <Section title="Authorized by">
        {authorizations.length === 0 && (
          <Box color="label">Nobody yet.</Box>
        )}
        {authorizations.map((auth, i) => (
          <Box key={i} py={0.25}>
            <Icon name="id-badge" mr={1} color="bad" />
            {auth.name}
            <Box inline color="label" ml={1}>
              {auth.job}
            </Box>
          </Box>
        ))}
      </Section>
    </Fragment>
  );
};
