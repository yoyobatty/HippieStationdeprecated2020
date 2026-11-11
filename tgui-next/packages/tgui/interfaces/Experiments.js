import { useBackend } from '../backend';
import { Box, Icon, NoticeBox, ProgressBar, Section } from '../components';

// hippie -- the experiment scanner: the station's research experiments, what
// each has recorded and what it pays, and science's sample board. Data from
// hippiestation/code/modules/research/experiments.dm and sample_requests.dm.
// SampleBoard is also the R&D console's Samples tab.

export const ExperimentList = props => {
  const { experiments = [] } = props;
  return experiments.map(exp => (
    <div
      key={exp.name}
      className={'Experiments__card'
        + (exp.completed ? ' Experiments__card--done' : '')}>
      <Box mb={0.5}>
        <b>{exp.name}</b>
        <Box inline style={{ float: 'right' }}
          color={exp.completed ? 'good' : 'label'}>
          {!!exp.completed && (
            <Icon name="check" mr={0.5} />
          )}
          {exp.completed ? 'Complete' : exp.reward + ' pts'}
        </Box>
      </Box>
      <Box color="label" fontSize="11px" mb={0.5}>{exp.desc}</Box>
      <ProgressBar
        value={exp.count / exp.required}
        color={exp.completed ? 'good' : 'teal'}>
        {exp.count} / {exp.required}
      </ProgressBar>
      {exp.done.length > 0 && (
        <Box fontSize="11px" mt={0.5}>
          {exp.done.join(', ')}
        </Box>
      )}
      {exp.nodes.length > 0 && (
        <Box fontSize="11px" mt={0.5} color="average">
          <Icon name="flask" mr={0.5} />
          {exp.nodes.join(', ')}
        </Box>
      )}
    </div>
  ));
};

// Sample requests by kind: the icon on the card
export const SAMPLE_ICONS = {
  botany: 'seedling',
  kitchen: 'utensils',
  mining: 'gem',
  lavaland: 'skull',
  medical: 'heartbeat',
  chemistry: 'vial',
  atmos: 'wind',
};

const points = value => String(value).replace(/\B(?=(\d{3})+(?!\d))/g, ',');

const SampleCard = props => {
  const { request } = props;
  return (
    <div
      className={'SampleBoard__card SampleBoard__card--' + request.kind}>
      <div className="SampleBoard__top">
        <span className="SampleBoard__dept">
          <Icon name={SAMPLE_ICONS[request.kind]} mr={0.5} />
          {request.department}
        </span>
        <span className="SampleBoard__reward">
          {points(request.reward)} pts
        </span>
      </div>
      <div className="SampleBoard__name">{request.name}</div>
      {request.needed > 1 && (
        <ProgressBar
          mt={0.5}
          value={request.got / request.needed}>
          {request.got} / {request.needed}{request.unit}
        </ProgressBar>
      )}
      <div className="SampleBoard__time">
        <Icon name="clock" mr={0.5} />
        {request.minutes_left} min
      </div>
    </div>
  );
};

export const SampleBoard = props => {
  const { board } = props;
  if (!board) {
    return null;
  }
  const requests = board.requests || [];
  const history = board.history || [];
  if (!board.open) {
    return (
      <NoticeBox>
        {board.opens_in !== null && board.opens_in !== undefined
          ? 'The sample board opens in ' + board.opens_in + ' min.'
          : 'Board opens at shift start.'}
      </NoticeBox>
    );
  }
  return (
    <Box>
      <Box color="label" mb={1}>
        {board.filled_count} filled, {points(board.points_paid)} pts
      </Box>
      <div className="SampleBoard__grid">
        {requests.map(request => (
          <SampleCard key={request.kind} request={request} />
        ))}
      </div>
      {history.length > 0 && (
        <Box mt={1}>
          {history.map((done, i) => (
            <div
              key={i}
              className={'SampleBoard__done' + (done.via === 'expired'
                ? ' SampleBoard__done--expired'
                : '')}>
              <Icon
                name={done.via === 'expired' ? 'times' : 'check'}
                mr={0.5} />
              <span className="SampleBoard__doneName">{done.name}</span>
              <span className="SampleBoard__doneVia">
                {done.via === 'expired'
                  ? 'expired'
                  : done.via + (done.by ? ', ' + done.by : '')
                    + ' · ' + points(done.reward) + ' pts'}
              </span>
            </div>
          ))}
        </Box>
      )}
    </Box>
  );
};

export const ExperimentScanner = props => {
  const { data } = useBackend(props);
  const experiments = data.experiments || [];
  const done = experiments.filter(exp => exp.completed).length;
  return (
    <Box>
      <Section title="Sample board">
        <SampleBoard board={data.samples} />
      </Section>
      <Section title={'Experiments (' + done + '/' + experiments.length + ')'}>
        <ExperimentList experiments={experiments} />
      </Section>
    </Box>
  );
};
