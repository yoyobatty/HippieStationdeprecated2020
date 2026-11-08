import { decodeHtmlEntities } from 'common/string';
import { Fragment } from 'inferno';
import { useBackend } from '../backend';
import { Box, Button, Flex, NoticeBox, ProgressBar, Section, Table } from '../components';

// The vote panel (hippiestation/code/controllers/subsystem/vote_tgui.dm):
// live counts and time left while a vote runs, starting one when none does.

const formatTime = seconds => {
  const m = Math.floor(seconds / 60);
  const s = seconds % 60;
  return m + ':' + (s < 10 ? '0' : '') + s;
};

const Running = props => {
  const { act, data } = props;
  const choices = data.choices || [];
  const total = data.total || 0;
  const title = data.question
    ? decodeHtmlEntities(data.question)
    : String(data.mode).charAt(0).toUpperCase() + String(data.mode).slice(1);
  const period = Math.max(1, data.vote_period || 1);
  return (
    <Fragment>
      <Section
        title={'Vote: ' + title}
        buttons={!!data.admin && (
          <Button
            icon="ban"
            color="bad"
            content="Cancel"
            onClick={() => act('cancel')} />
        )}>
        <ProgressBar
          value={data.time_left / period}
          ranges={{
            good: [0.5, Infinity],
            average: [0.2, 0.5],
            bad: [-Infinity, 0.2],
          }}>
          {formatTime(data.time_left)}
        </ProgressBar>
        <Box mt={0.5} color="label" fontSize="11px">
          Started by {data.initiator} · {total} vote{total === 1 ? '' : 's'}
        </Box>
      </Section>
      {!!data.dead_blocked && (
        <NoticeBox>{"Dead players can't vote."}</NoticeBox>
      )}
      <Section>
        <Table>
          {choices.map((choice, i) => {
            const mine = data.my_vote === i + 1;
            const share = total ? choice.votes / total : 0;
            return (
              <Table.Row key={i}>
                <Table.Cell collapsing pb={0.5}>
                  <Button
                    fluid
                    icon={mine ? 'check-square-o' : 'square-o'}
                    selected={mine}
                    disabled={!!data.dead_blocked}
                    content={decodeHtmlEntities(choice.name)}
                    onClick={() => act('vote', { index: i + 1 })} />
                </Table.Cell>
                <Table.Cell pl={1} pb={0.5}>
                  <ProgressBar value={share} color={mine ? 'good' : 'average'}>
                    {choice.votes}
                  </ProgressBar>
                </Table.Cell>
              </Table.Row>
            );
          })}
        </Table>
      </Section>
    </Fragment>
  );
};

const Idle = props => {
  const { act, data } = props;
  const starts = data.starts || [];
  return (
    <Section title="Start a vote">
      {!!data.cooldown && (
        <Box color="average" mb={1}>
          Next vote in {formatTime(data.cooldown)}
        </Box>
      )}
      {starts.map(start => (
        <Flex key={start.type} align="center" mb={0.5}>
          <Flex.Item grow={1}>
            <Button
              fluid
              content={start.name
                + (start.wait ? ' (' + formatTime(start.wait) + ')' : '')}
              disabled={!start.can_start || !!start.wait || !!data.cooldown}
              onClick={() => act('start', { type: start.type })} />
          </Flex.Item>
          {!!start.toggle && (
            <Flex.Item ml={1}>
              <Button
                width="90px"
                textAlign="center"
                color={start.allowed ? 'good' : 'bad'}
                content={start.allowed ? 'Allowed' : 'Disallowed'}
                onClick={() => act('toggle', { type: start.type })} />
            </Flex.Item>
          )}
        </Flex>
      ))}
    </Section>
  );
};

export const VotePanel = props => {
  const { act, data } = useBackend(props);
  return data.mode
    ? <Running act={act} data={data} />
    : <Idle act={act} data={data} />;
};
