import { Component, Fragment } from 'inferno';
import { useBackend } from '../backend';
import { Box, Button, Icon, Input, Section, Table } from '../components';

// hippie -- the crew monitor redone: everyone on suit sensors grouped by
// department, a count of who's fine, hurt, critical and dead, a search and a
// "hurt only" filter, and each person's damage as coloured numbers

const DEPARTMENTS = [
  ['Command', 'yellow'],
  ['Security', 'red'],
  ['Medical', 'teal'],
  ['Science', 'purple'],
  ['Engineering', 'orange'],
  ['Supply', 'brown'],
  ['Service', 'green'],
  ['Central Command', 'blue'],
  ['Civilian', 'grey'],
];

// The monitor's own job order (code/game/machinery/computer/crew.dm): heads
// are the round tens, each department its own ten
const departmentOf = ijob => {
  if (ijob >= 200 && ijob < 999) {
    return 'Central Command';
  }
  if (ijob === 0 || (ijob % 10 === 0 && ijob <= 50)) {
    return 'Command';
  }
  const tens = Math.floor(ijob / 10);
  return ['Command', 'Security', 'Medical', 'Science', 'Engineering',
    'Supply', 'Service'][tens] || 'Civilian';
};

const totalDamage = person => (person.oxydam || 0) + (person.toxdam || 0)
  + (person.burndam || 0) + (person.brutedam || 0);

const stateOf = person => {
  if (person.life_status === null || person.life_status === undefined) {
    return 'unknown';
  }
  // life_status is whether they're conscious: out cold is critical unless
  // the damage is past what kills (200)
  const vitals = person.oxydam !== null && person.oxydam !== undefined;
  const damage = totalDamage(person);
  if (!person.life_status) {
    return vitals && damage < 200 ? 'critical' : 'dead';
  }
  if (!vitals) {
    return 'alive';
  }
  if (damage >= 100) {
    return 'critical';
  }
  return damage > 0 ? 'hurt' : 'alive';
};

const STATE_COLOR = {
  alive: 'good',
  hurt: 'average',
  critical: 'bad',
  dead: 'bad',
  unknown: 'label',
};

const Damage = props => {
  const { person } = props;
  if (person.oxydam === null || person.oxydam === undefined) {
    return <Box inline color="label">No vitals</Box>;
  }
  return (
    <Box inline>
      <Box inline color="blue" mr={1} title="Suffocation">
        {person.oxydam}
      </Box>
      <Box inline color="green" mr={1} title="Toxin">
        {person.toxdam}
      </Box>
      <Box inline color="orange" mr={1} title="Burn">
        {person.burndam}
      </Box>
      <Box inline color="red" title="Brute">
        {person.brutedam}
      </Box>
    </Box>
  );
};

export class CrewConsole extends Component {
  constructor() {
    super();
    this.state = { search: '', hurtOnly: false };
  }

  render() {
    const { act, data } = useBackend(this.props);
    const { search, hurtOnly } = this.state;
    const sensors = data.sensors || [];
    const counts = { alive: 0, hurt: 0, critical: 0, dead: 0, unknown: 0 };
    for (let person of sensors) {
      counts[stateOf(person)]++;
    }
    const term = search.toLowerCase();
    const shown = sensors.filter(person => {
      const state = stateOf(person);
      if (hurtOnly && state !== 'hurt' && state !== 'critical'
        && state !== 'dead') {
        return false;
      }
      return !term || person.name.toLowerCase().includes(term)
        || (person.assignment || '').toLowerCase().includes(term)
        || (person.area || '').toLowerCase().includes(term);
    });
    return (
      <Fragment>
        <Section>
          <Box inline mr={2} color="good">
            <Icon name="heartbeat" mr={1} />
            {counts.alive} fine
          </Box>
          <Box inline mr={2} color="average">
            <Icon name="band-aid" mr={1} />
            {counts.hurt} hurt
          </Box>
          <Box inline mr={2} color="bad">
            <Icon name="exclamation-triangle" mr={1} />
            {counts.critical} critical
          </Box>
          <Box inline mr={2} color="bad">
            <Icon name="skull" mr={1} />
            {counts.dead} dead
          </Box>
          <Box inline color="label">
            <Icon name="question" mr={1} />
            {counts.unknown} no vitals
          </Box>
        </Section>
        <Section
          title="Crew"
          buttons={(
            <Fragment>
              <Input
                width="160px"
                placeholder="Search name, job, place..."
                value={search}
                onInput={(e, value) => this.setState({ search: value })} />
              <Button.Checkbox
                checked={hurtOnly}
                content="Hurt only"
                onClick={() => this.setState({ hurtOnly: !hurtOnly })} />
            </Fragment>
          )}>
          {shown.length === 0 && (
            <Box color="label">Nobody to show.</Box>
          )}
          <Table>
            {DEPARTMENTS.map(department => {
              const people = shown.filter(person => (
                departmentOf(person.ijob) === department[0]));
              if (!people.length) {
                return null;
              }
              return [
                <Table.Row key={department[0]}>
                  <Table.Cell colspan="4" pt={1} bold color={department[1]}>
                    {department[0]}
                  </Table.Cell>
                </Table.Row>,
                ...people.map(person => (
                  <Table.Row key={person.name + person.assignment}>
                    <Table.Cell>
                      <Icon
                        name="circle"
                        mr={1}
                        color={STATE_COLOR[stateOf(person)]} />
                      <b>{person.name}</b>
                      <Box inline color="label" ml={1}>
                        {person.assignment}
                      </Box>
                    </Table.Cell>
                    <Table.Cell collapsing px={1}>
                      <Damage person={person} />
                    </Table.Cell>
                    <Table.Cell color={person.area ? null : 'label'}>
                      {person.area || 'Unknown'}
                    </Table.Cell>
                    <Table.Cell collapsing>
                      {!!data.link_allowed && (
                        <Button
                          icon="video"
                          disabled={!person.can_track}
                          content="Track"
                          onClick={() => act('select_person', {
                            name: person.name,
                          })} />
                      )}
                    </Table.Cell>
                  </Table.Row>
                )),
              ];
            })}
          </Table>
        </Section>
      </Fragment>
    );
  }
}
