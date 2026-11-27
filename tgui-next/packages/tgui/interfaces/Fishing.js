import { Component, Fragment } from 'inferno';
import { useBackend } from '../backend';
import { Box, NoticeBox, ProgressBar, Section, Table } from '../components';

// hippie -- fishing, from Paradise (hippiestation/code/modules/fishing/)

// What the fish is doing, and how urgent it is
const FISH_STATES = {
  'resting': { text: 'Resting. Reel!', color: 'good' },
  'tensing': { text: 'About to run!', color: 'average' },
  'running': { text: 'Running. Ease off!', color: 'bad' },
  'worn out': { text: 'Worn out. Reel it in!', color: 'good' },
};

// Held down to wind the reel. Letting go anywhere in the window stops it,
// not just over the button.
class ReelButton extends Component {
  constructor() {
    super();
    this.letGo = () => {
      if (this.props.reeling) {
        this.props.act('reel', { held: 0 });
      }
    };
  }

  componentDidMount() {
    window.addEventListener('mouseup', this.letGo);
  }

  componentWillUnmount() {
    window.removeEventListener('mouseup', this.letGo);
  }

  render() {
    const { act, reeling } = this.props;
    return (
      <Box
        className={'Button Button--fluid '
          + (reeling ? 'Button--selected' : 'Button--color--default')}
        height="64px"
        textAlign="center"
        fontSize="18px"
        bold
        style={{
          'display': 'flex',
          'align-items': 'center',
          'justify-content': 'center',
          'user-select': 'none',
        }}
        onMouseDown={e => {
          e.preventDefault();
          act('reel', { held: 1 });
        }}>
        {reeling ? 'Reeling' : 'Hold to reel'}
      </Box>
    );
  }
}

export const FishingReel = props => {
  const { act, data } = useBackend(props);
  const {
    fighting,
    tension,
    max_tension,
    distance,
    max_distance,
    fish_state,
    hint,
    reeling,
  } = data;
  if (!fighting) {
    return (
      <NoticeBox>
        Nothing on the line.
      </NoticeBox>
    );
  }
  const fishState = FISH_STATES[fish_state] || FISH_STATES['resting'];
  return (
    <Fragment>
      <Section title={'There\'s ' + hint + ' on the line'}>
        <Box bold fontSize="18px" textAlign="center" color={fishState.color}>
          {fishState.text}
        </Box>
      </Section>
      <Section>
        <Box mb={0.5} color="label">Strain</Box>
        <ProgressBar
          value={tension}
          minValue={0}
          maxValue={max_tension}
          ranges={{
            good: [0, max_tension * 0.6],
            average: [max_tension * 0.6, max_tension * 0.85],
            bad: [max_tension * 0.85, max_tension],
          }}>
          {tension}%
        </ProgressBar>
        <Box mt={1} mb={0.5} color="label">Line out</Box>
        <ProgressBar
          value={distance}
          minValue={0}
          maxValue={max_distance}
          ranges={{
            good: [0, max_distance * 0.5],
            average: [max_distance * 0.5, max_distance * 0.8],
            bad: [max_distance * 0.8, max_distance],
          }}>
          {distance.toFixed(1)} / {max_distance.toFixed(1)} tiles
        </ProgressBar>
      </Section>
      <ReelButton act={act} reeling={!!reeling} />
    </Fragment>
  );
};

export const FishingBoard = props => {
  const { data } = useBackend(props);
  // Biggest fish at the top
  const records = [...(data.records || [])]
    .sort((a, b) => b.length - a.length);
  return (
    <Section title="Biggest catches this shift">
      {records.length === 0 && (
        <NoticeBox>
          No catches yet.
        </NoticeBox>
      )}
      {records.length > 0 && (
        <Table>
          <Table.Row header>
            <Table.Cell>Fish</Table.Cell>
            <Table.Cell>Length</Table.Cell>
            <Table.Cell>Angler</Table.Cell>
            <Table.Cell>Spot</Table.Cell>
            <Table.Cell>Time</Table.Cell>
          </Table.Row>
          {records.map(record => (
            <Table.Row key={record.fish} className="candystripe">
              <Table.Cell bold style={{ 'text-transform': 'capitalize' }}>
                {record.fish}
              </Table.Cell>
              <Table.Cell>{record.length} cm</Table.Cell>
              <Table.Cell>{record.angler}</Table.Cell>
              <Table.Cell>{record.spot}</Table.Cell>
              <Table.Cell>{record.time}</Table.Cell>
            </Table.Row>
          ))}
        </Table>
      )}
    </Section>
  );
};
