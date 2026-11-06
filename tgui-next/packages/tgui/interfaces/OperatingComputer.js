import { Fragment } from 'inferno';
import { useBackend } from '../backend';
import { AnimatedNumber, Box, Button, Collapsible, Icon, LabeledList, NoticeBox, ProgressBar, Section } from '../components';

// hippie -- the operating computer redone: the patient and the surgery under
// way on one screen, the next step large with what it needs, the other way on
// (for a step that repeats) beside it, and the advanced surgeries it knows
// folded away below

const DAMAGES = [
  ['Brute', 'bruteLoss', 'bad'],
  ['Burn', 'fireLoss', 'orange'],
  ['Toxin', 'toxLoss', 'green'],
  ['Suffocation', 'oxyLoss', 'blue'],
];

const Procedure = props => {
  const { procedure } = props;
  return (
    <Section level={2} title={procedure.name}>
      <Box color="label">Next step</Box>
      <Box fontSize="16px" bold color="good" mb={0.5}>
        <Icon name="arrow-right" mr={1} />
        {procedure.next_step}
      </Box>
      {!!procedure.chems_needed && (
        <Box color="average" mb={0.5}>
          <Icon name="flask" mr={1} />
          Needs {procedure.chems_needed}
        </Box>
      )}
      {!!procedure.alternative_step && (
        <Box color="label">
          Or, to move on: <b>{procedure.alternative_step}</b>
          {!!procedure.alt_chems_needed && (
            <Box inline color="average" ml={1}>
              (needs {procedure.alt_chems_needed})
            </Box>
          )}
        </Box>
      )}
    </Section>
  );
};

export const OperatingComputer = props => {
  const { act, data } = useBackend(props);
  const {
    table,
    surgeries = [],
    procedures = [],
    patient,
  } = data;
  return (
    <Fragment>
      {!table && (
        <NoticeBox>
          No operating table next to this computer.
        </NoticeBox>
      )}
      <Section title={patient ? 'Patient' : 'No patient'}>
        {!patient && (
          <Box color="label">
            Nobody is lying on the table.
          </Box>
        ) || (
          <LabeledList>
            <LabeledList.Item label="State" color={patient.statstate}>
              {patient.stat}
              <Box inline color="label" ml={2}>
                Blood type {patient.blood_type}
              </Box>
            </LabeledList.Item>
            <LabeledList.Item label="Health">
              <ProgressBar
                value={patient.health}
                minValue={patient.minHealth}
                maxValue={patient.maxHealth}
                ranges={{
                  good: [patient.maxHealth * 0.5, Infinity],
                  average: [0, patient.maxHealth * 0.5],
                  bad: [-Infinity, 0],
                }}>
                <AnimatedNumber value={Math.round(patient.health)} />
              </ProgressBar>
            </LabeledList.Item>
            {DAMAGES.map(damage => (
              <LabeledList.Item key={damage[1]} label={damage[0]}>
                <ProgressBar
                  value={patient[damage[1]]}
                  minValue={0}
                  maxValue={patient.maxHealth}
                  color={patient[damage[1]] > 0 ? damage[2] : 'good'}>
                  <AnimatedNumber value={Math.round(patient[damage[1]])} />
                </ProgressBar>
              </LabeledList.Item>
            ))}
          </LabeledList>
        )}
      </Section>
      {!!patient && (
        <Section title="Surgery">
          {procedures.length === 0 && (
            <Box color="label">No surgery under way.</Box>
          )}
          {procedures.map(procedure => (
            <Procedure key={procedure.name} procedure={procedure} />
          ))}
        </Section>
      )}
      <Section
        title={'Advanced surgeries (' + surgeries.length + ')'}
        buttons={(
          <Button
            icon="sync"
            content="Sync"
            onClick={() => act('sync')} />
        )}>
        {surgeries.length === 0 && (
          <Box color="label">
            None yet. Research them and sync.
          </Box>
        )}
        {surgeries.map(surgery => (
          <Collapsible key={surgery.name} title={surgery.name}>
            <Box color="label" mb={1}>{surgery.desc}</Box>
          </Collapsible>
        ))}
      </Section>
    </Fragment>
  );
};
