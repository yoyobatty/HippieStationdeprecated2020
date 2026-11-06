import { useBackend } from '../backend';
import { Box, Icon, ProgressBar, Section } from '../components';

// hippie -- the experiment scanner: the station's research experiments, what
// each has recorded and what it pays. Data from hippiestation/code/modules/
// research/experiments.dm.

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

export const ExperimentScanner = props => {
  const { data } = useBackend(props);
  const experiments = data.experiments || [];
  const done = experiments.filter(exp => exp.completed).length;
  return (
    <Section title={'Experiments (' + done + '/' + experiments.length + ')'}>
      <ExperimentList experiments={experiments} />
    </Section>
  );
};
