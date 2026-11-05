import { Fragment } from 'inferno';
import { useBackend } from '../backend';
import { Box, Button, Flex, Input, LabeledList, NoticeBox, Section } from '../components';

// hippie -- the requests console
// (hippiestation/.../machinery/requests_console_tgui.dm). Its screens keep
// the old numbers: 0 and 8 messages, 1-3 the departments, 9 writing a
// message, 6 and 7 sent or not, 10 an announcement.

const NORMAL = 1;
const HIGH = 2;
const EXTREME = 3;

const goTo = (act, screen) => act('screen', { screen });

const Tabs = props => {
  const { data, act } = props;
  const screen = data.screen;
  const tabs = [
    [[0, 8], 'envelope', 'Messages (' + data.messages.length + ')'],
    [[1], 'hands-helping', 'Assistance'],
    [[2], 'box', 'Supplies'],
    [[3], 'info-circle', 'Information'],
  ];
  if (data.announcement_console) {
    tabs.push([[10], 'bullhorn', 'Announce']);
  }
  return (
    <Flex mb={1}>
      {tabs.map(([screens, icon, title]) => (
        <Flex.Item key={title} grow={1} basis={0} mr={0.5}>
          <Button
            fluid
            textAlign="center"
            icon={icon}
            content={title}
            selected={screens.indexOf(screen) !== -1}
            onClick={() => goTo(act, screens[0])} />
        </Flex.Item>
      ))}
    </Flex>
  );
};

const EMERGENCIES = [
  [1, 'Security', 'shield-alt'],
  [2, 'Engineering', 'wrench'],
  [3, 'Medical', 'medkit'],
];

const Emergencies = props => {
  const { data, act } = props;
  if (data.emergency) {
    return (
      <Box bold color="bad" mb={1}>
        {data.emergency + ' has been dispatched to this location.'}
      </Box>
    );
  }
  return (
    <Flex mb={1} align="center">
      <Flex.Item color="label" mr={1}>Emergency:</Flex.Item>
      {EMERGENCIES.map(([kind, title, icon]) => (
        <Flex.Item key={kind} grow={1} basis={0} mr={0.5}>
          <Button
            fluid
            textAlign="center"
            color="bad"
            icon={icon}
            content={title}
            onClick={() => act('emergency', { kind })} />
        </Flex.Item>
      ))}
    </Flex>
  );
};

const PRIORITY_TEXT = {
  [HIGH]: 'High Priority',
  [EXTREME]: '!!!Extreme Priority!!!',
};

const Messages = props => {
  const { data, act } = props;
  const messages = data.messages || [];
  return (
    <Section title="Messages">
      {messages.length === 0 && (
        <Box color="label">No messages.</Box>
      )}
      {messages.map((msg, i) => (
        <Box
          key={i}
          className="candystripe"
          p={1}
          style={msg.priority > NORMAL
            ? { 'border-left': '3px solid #db2828' }
            : null}>
          <Flex align="center">
            <Flex.Item grow={1}>
              {!!PRIORITY_TEXT[msg.priority] && (
                <Box bold color="bad">{PRIORITY_TEXT[msg.priority]}</Box>
              )}
              <Box>
                <Box inline bold>{msg.from}</Box>
                <Box inline color="label" ml={1}>{msg.time}</Box>
              </Box>
            </Flex.Item>
            {!!msg.reply && (
              <Flex.Item>
                <Button
                  icon="reply"
                  content="Reply"
                  onClick={() => act('write', {
                    department: msg.reply,
                    priority: NORMAL,
                  })} />
              </Flex.Item>
            )}
          </Flex>
          <Box mt={0.5}>{msg.body}</Box>
          {!!msg.verified && <Box color="good">{msg.verified}</Box>}
          {!!msg.stamped && <Box color="average">{msg.stamped}</Box>}
        </Box>
      ))}
    </Section>
  );
};

const QUESTION = {
  1: 'Which department do you need assistance from?',
  2: 'Which department do you need supplies from?',
  3: 'Which department would you like to send information to?',
};

const Departments = props => {
  const { data, act } = props;
  const list = { 1: data.assistance, 2: data.supplies, 3: data.information }[
    data.screen] || [];
  return (
    <Section title={QUESTION[data.screen]}>
      {list.length === 0 && (
        <Box color="label">No departments take these.</Box>
      )}
      {list.map(dept => (
        <Flex key={dept.key} className="candystripe" p={0.5} align="center">
          <Flex.Item grow={1}>{dept.name}</Flex.Item>
          <Flex.Item>
            <Button
              content="Normal"
              onClick={() => act('write', {
                department: dept.key,
                priority: NORMAL,
              })} />
            <Button
              color="average"
              content="High"
              onClick={() => act('write', {
                department: dept.key,
                priority: HIGH,
              })} />
            {!!data.hacked && (
              <Button
                color="bad"
                content="EXTREME"
                onClick={() => act('write', {
                  department: dept.key,
                  priority: EXTREME,
                })} />
            )}
          </Flex.Item>
        </Flex>
      ))}
    </Section>
  );
};

const Compose = props => {
  const { data, act } = props;
  let level = 'Normal';
  if (data.priority === HIGH) {
    level = 'High';
  } else if (data.priority === EXTREME) {
    level = 'EXTREME';
  }
  return (
    <Section title={'Message for ' + data.to_department}>
      <LabeledList>
        <LabeledList.Item label="Priority">{level}</LabeledList.Item>
        <LabeledList.Item label="Message">
          <Input
            fluid
            placeholder="Write your message..."
            value={data.message}
            onChange={(e, value) => act('set_message', { text: value })} />
        </LabeledList.Item>
        <LabeledList.Item label="Validated by">
          {data.verified || <Box inline color="label">Not validated</Box>}
        </LabeledList.Item>
        <LabeledList.Item label="Stamped by">
          {data.stamped || <Box inline color="label">Not stamped</Box>}
        </LabeledList.Item>
      </LabeledList>
      <Box color="label" mt={1}>
        You may authenticate your message by swiping your ID or your stamp
        on the console.
      </Box>
      <Box mt={1}>
        <Button
          icon="paper-plane"
          content="Send Message"
          disabled={!data.message}
          onClick={() => act('send')} />
        <Button
          icon="trash"
          content="Discard"
          onClick={() => goTo(act, 0)} />
      </Box>
    </Section>
  );
};

const Announcement = props => {
  const { data, act } = props;
  return (
    <Section title="Station-wide Announcement">
      {data.announce_auth
        ? <Box color="good" mb={1}>Authentication accepted.</Box>
        : <NoticeBox>Swipe your card to authenticate yourself.</NoticeBox>}
      <Input
        fluid
        placeholder="Write the announcement..."
        value={data.message}
        onChange={(e, value) => act('set_announcement', { text: value })} />
      <Box mt={1}>
        <Button
          icon="bullhorn"
          content="Announce Message"
          disabled={!data.announce_auth || !data.message}
          onClick={() => act('announce')} />
      </Box>
    </Section>
  );
};

export const RequestsConsole = props => {
  const { act, data } = useBackend(props);
  const screen = data.screen;
  let body = <Messages data={data} act={act} />;
  if (screen >= 1 && screen <= 3) {
    body = <Departments data={data} act={act} />;
  } else if (screen === 9) {
    body = <Compose data={data} act={act} />;
  } else if (screen === 10) {
    body = <Announcement data={data} act={act} />;
  } else if (screen === 6 || screen === 7) {
    body = (
      <Section>
        <Box color={screen === 6 ? 'good' : 'bad'} mb={1}>
          {screen === 6 ? 'Message sent.' : 'An error occurred.'}
        </Box>
        <Button
          icon="arrow-left"
          content="Back"
          onClick={() => goTo(act, 0)} />
      </Section>
    );
  }
  return (
    <Fragment>
      <Section
        title={data.department}
        buttons={(
          <Button
            icon={data.silent ? 'volume-mute' : 'volume-up'}
            content={data.silent ? 'Speaker off' : 'Speaker on'}
            selected={!data.silent}
            onClick={() => act('silent')} />
        )}>
        <Emergencies data={data} act={act} />
        <Tabs data={data} act={act} />
      </Section>
      {body}
    </Fragment>
  );
};
