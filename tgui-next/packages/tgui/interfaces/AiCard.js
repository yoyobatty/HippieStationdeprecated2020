import { Fragment } from 'inferno';
import { useBackend } from '../backend';
import { Box, Button, LabeledList, NoticeBox, ProgressBar, Section } from '../components';

// hippie -- the intelliCard and the AI system integrity restorer laptop program
// (were tgui/src/interfaces/intellicard.ract and ntos_ai_restorer.ract)

const AiStatus = props => {
  const { name, health, offline, laws = [], children } = props;
  return (
    <Fragment>
      <LabeledList>
        <LabeledList.Item label="Status" color={offline ? 'bad' : 'good'}>
          {offline ? 'Offline' : 'Operational'}
        </LabeledList.Item>
        <LabeledList.Item label="Integrity">
          <ProgressBar
            value={health / 100}
            ranges={{
              good: [0.7, Infinity],
              average: [0.5, 0.7],
              bad: [-Infinity, 0.5],
            }}>
            {Math.round(health)}%
          </ProgressBar>
        </LabeledList.Item>
        {children}
      </LabeledList>
      <Section level={2} title={'Laws of ' + name}>
        {laws.length === 0 && (
          <Box color="label">No laws.</Box>
        )}
        {laws.map((law, i) => (
          <Box key={i} color="highlight" mb={0.5}>
            {law}
          </Box>
        ))}
      </Section>
    </Fragment>
  );
};

export const Intellicard = props => {
  const { act, data } = useBackend(props);
  const {
    name,
    laws,
    health,
    wireless,
    radio,
    isDead,
    isBraindead,
    wiping,
  } = data;
  return (
    <Fragment>
      {!!wiping && (
        <NoticeBox>Wipe in progress!</NoticeBox>
      )}
      <Section
        title={name || 'Empty card'}
        buttons={!!name && (
          <Button
            icon="trash"
            color="bad"
            disabled={isDead}
            content={wiping ? 'Stop wiping' : 'Wipe AI'}
            onClick={() => act('wipe')} />
        )}>
        {!name && (
          <Box color="label">
            No AI loaded.
          </Box>
        ) || (
          <AiStatus
            name={name}
            health={health}
            offline={isDead || isBraindead}
            laws={laws}>
            <LabeledList.Item label="Settings">
              <Button
                icon="signal"
                selected={wireless}
                content="Wireless activity"
                onClick={() => act('wireless')} />
              <Button
                icon="microphone"
                selected={radio}
                content="Subspace radio"
                onClick={() => act('radio')} />
            </LabeledList.Item>
          </AiStatus>
        )}
      </Section>
    </Fragment>
  );
};

export const NtosAiRestorer = props => {
  const { act, data } = useBackend(props);
  const {
    nocard,
    error,
    name,
    restoring,
    health,
    isDead,
    ai_laws,
  } = data;
  return (
    <Fragment>
      {!!restoring && (
        <NoticeBox>Reconstruction in progress!</NoticeBox>
      )}
      <Section
        title="intelliCard"
        buttons={(
          <Button
            icon="eject"
            disabled={nocard}
            content={name || 'Eject'}
            onClick={() => act('PRG_eject')} />
        )}>
        {!!error && (
          <Box color="average">{error}</Box>
        ) || (
          <AiStatus
            name={name}
            health={health}
            offline={isDead}
            laws={ai_laws}>
            <LabeledList.Item label="Repair">
              <Button
                icon="wrench"
                disabled={restoring}
                content="Begin reconstruction"
                onClick={() => act('PRG_beginReconstruction')} />
            </LabeledList.Item>
          </AiStatus>
        )}
      </Section>
    </Fragment>
  );
};
