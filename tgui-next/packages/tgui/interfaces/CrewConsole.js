import { Component, createRef, Fragment } from 'inferno';
import { useBackend } from '../backend';
import { Box, Button, Icon, Input, ProgressBar, Section } from '../components';

// hippie -- the crew monitor redone: a map of the station with a dot for each
// person on suit sensors, coloured by how they're doing, and beside it the
// crew sorted by who needs help first, each with a health bar. Click a dot or
// a row to pick someone out. The map comes from hippiestation/code/game/
// machinery/medical_tgui.dm.

const DEPARTMENTS = {
  Command: 'yellow',
  Security: 'red',
  Medical: 'teal',
  Science: 'purple',
  Engineering: 'orange',
  Supply: 'brown',
  Service: 'green',
  'Central Command': 'blue',
  Civilian: 'grey',
};

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

const hasVitals = person => person.oxydam !== null
  && person.oxydam !== undefined;

const totalDamage = person => (person.oxydam || 0) + (person.toxdam || 0)
  + (person.burndam || 0) + (person.brutedam || 0);

// life_status is whether they're conscious: out cold is critical unless the
// damage is past what kills (200)
const stateOf = person => {
  if (person.life_status === null || person.life_status === undefined) {
    return 'unknown';
  }
  const damage = totalDamage(person);
  if (!person.life_status) {
    return hasVitals(person) && damage < 200 ? 'critical' : 'dead';
  }
  if (!hasVitals(person)) {
    return 'alive';
  }
  if (damage >= 100) {
    return 'critical';
  }
  return damage > 0 ? 'hurt' : 'alive';
};

// Who needs help first
const STATES = {
  critical: {
    order: 0,
    color: 'bad',
    hex: '#ca0916',
    icon: 'exclamation-triangle',
    label: 'critical',
  },
  dead: {
    order: 1,
    color: 'bad',
    hex: '#7a201b',
    icon: 'skull',
    label: 'dead',
  },
  hurt: {
    order: 2,
    color: 'average',
    hex: '#ec8922',
    icon: 'band-aid',
    label: 'hurt',
  },
  alive: {
    order: 3,
    color: 'good',
    hex: '#6ebc3d',
    icon: 'heartbeat',
    label: 'fine',
  },
  unknown: {
    order: 4,
    color: 'label',
    hex: '#8b8b8b',
    icon: 'question',
    label: 'no vitals',
  },
};

const MAP_SIZE = 520;
const MAP_COLORS = { '#': '#5b6372', _: '#2c3139' };

class StationMap extends Component {
  constructor() {
    super();
    this.canvasRef = createRef();
  }

  componentDidMount() {
    this.draw();
  }

  componentDidUpdate(prevProps) {
    if (prevProps.map !== this.props.map) {
      this.draw();
    }
  }

  scale() {
    const { map } = this.props;
    const rows = map.rows || [];
    const width = rows.length ? rows[0].length : 1;
    return Math.max(1, Math.min(MAP_SIZE / width, MAP_SIZE / rows.length));
  }

  draw() {
    const canvas = this.canvasRef.current;
    const { map } = this.props;
    if (!canvas || !map) {
      return;
    }
    const scale = this.scale();
    const context = canvas.getContext('2d');
    context.clearRect(0, 0, canvas.width, canvas.height);
    map.rows.forEach((row, y) => {
      for (let x = 0; x < row.length; x++) {
        const fill = MAP_COLORS[row[x]];
        if (fill) {
          context.fillStyle = fill;
          context.fillRect(x * scale, y * scale,
            Math.ceil(scale), Math.ceil(scale));
        }
      }
    });
  }

  render() {
    const { map, people, selected, onSelect } = this.props;
    if (!map || !map.rows || !map.rows.length) {
      return <Box color="label">No map of this level.</Box>;
    }
    const scale = this.scale();
    const width = Math.ceil(map.rows[0].length * scale);
    const height = Math.ceil(map.rows.length * scale);
    return (
      <div
        className="CrewMonitor__map"
        style={{ width: width + 'px', height: height + 'px' }}>
        <canvas ref={this.canvasRef} width={width} height={height} />
        {people
          .filter(person => person.pos_x !== null
            && person.pos_x !== undefined)
          .map(person => {
            const state = STATES[stateOf(person)];
            const isSelected = selected === person.name;
            return (
              <div
                key={person.name + person.assignment}
                className={'CrewMonitor__dot'
                  + (isSelected ? ' CrewMonitor__dot--selected' : '')}
                title={person.name + ' (' + state.label + ')'}
                style={{
                  left: ((person.pos_x - map.minx + 0.5) * scale) + 'px',
                  top: ((map.maxy - person.pos_y + 0.5) * scale) + 'px',
                  'background-color': state.hex,
                }}
                onClick={() => onSelect(person.name)} />
            );
          })}
      </div>
    );
  }
}

const PersonRow = props => {
  const { act, person, selected, linkAllowed, onSelect } = props;
  const stateName = stateOf(person);
  const state = STATES[stateName];
  const department = departmentOf(person.ijob);
  const vitals = hasVitals(person);
  const health = 100 - totalDamage(person);
  return (
    <div
      className={'CrewMonitor__row'
        + (selected ? ' CrewMonitor__row--selected' : '')}
      onClick={() => onSelect(person.name)}>
      <Box inline width="22px" textAlign="center" color={state.color}>
        <Icon name={state.icon} />
      </Box>
      <Box inline width="190px" style={{ 'vertical-align': 'middle' }}>
        <Box bold>{person.name}</Box>
        <Box fontSize="11px" color={DEPARTMENTS[department]}>
          {person.assignment || 'No job'}
        </Box>
      </Box>
      <Box
        inline
        width="130px"
        mr={1}
        style={{ 'vertical-align': 'middle' }}
        title={vitals
          ? 'Suffocation ' + person.oxydam + ', toxin ' + person.toxdam
            + ', burn ' + person.burndam + ', brute ' + person.brutedam
          : 'No vitals on their sensors'}>
        {vitals && (
          <ProgressBar
            value={health}
            minValue={-100}
            maxValue={100}
            color={state.color}>
            {stateName === 'dead' ? 'Dead' : health}
          </ProgressBar>
        ) || (
          <Box color={state.color}>
            {state.label}
          </Box>
        )}
      </Box>
      <Box
        inline
        width="150px"
        style={{ 'vertical-align': 'middle' }}
        color={person.area ? null : 'label'}>
        {person.area || 'Unknown'}
      </Box>
      {!!linkAllowed && (
        <Button
          icon="video"
          disabled={!person.can_track}
          content="Track"
          onClick={() => act('select_person', { name: person.name })} />
      )}
    </div>
  );
};

export class CrewConsole extends Component {
  constructor() {
    super();
    this.state = { search: '', hurtOnly: false, selected: null };
  }

  render() {
    const { act, data } = useBackend(this.props);
    const { search, hurtOnly, selected } = this.state;
    const sensors = data.sensors || [];
    const counts = { critical: 0, dead: 0, hurt: 0, alive: 0, unknown: 0 };
    for (let person of sensors) {
      counts[stateOf(person)]++;
    }
    const term = search.toLowerCase();
    const shown = sensors
      .filter(person => {
        const state = stateOf(person);
        if (hurtOnly && (state === 'alive' || state === 'unknown')) {
          return false;
        }
        return !term || person.name.toLowerCase().includes(term)
          || (person.assignment || '').toLowerCase().includes(term)
          || (person.area || '').toLowerCase().includes(term);
      })
      .sort((a, b) => (STATES[stateOf(a)].order - STATES[stateOf(b)].order)
        || (totalDamage(b) - totalDamage(a)));
    const select = name => this.setState({
      selected: selected === name ? null : name,
    });
    return (
      <Fragment>
        <Section>
          {Object.keys(STATES).map(key => (
            <Box key={key} inline mr={2} fontSize="14px"
              color={STATES[key].color}>
              <Icon name={STATES[key].icon} mr={1} />
              {counts[key]} {STATES[key].label}
            </Box>
          ))}
        </Section>
        <div className="CrewMonitor__layout">
          <Section title="Station" className="CrewMonitor__left">
            <StationMap
              map={data.map}
              people={shown}
              selected={selected}
              onSelect={select} />
          </Section>
          <Section
            title="Crew"
            className="CrewMonitor__right"
            buttons={(
              <Fragment>
                <Input
                  width="150px"
                  placeholder="Search..."
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
            {shown.map(person => (
              <PersonRow
                key={person.name + person.assignment}
                act={act}
                person={person}
                selected={selected === person.name}
                linkAllowed={data.link_allowed}
                onSelect={select} />
            ))}
          </Section>
        </div>
      </Fragment>
    );
  }
}
