import { Component, Fragment } from 'inferno';
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

// One-click asks: the room goes with them
const QuickRequests = props => {
  const { data, act } = props;
  const quick = data.quick || [];
  if (!quick.length) {
    return null;
  }
  return (
    <Flex mb={1} align="center">
      <Flex.Item color="label" mr={1}>Quick request:</Flex.Item>
      {quick.map(q => (
        <Flex.Item key={q.name} grow={1} basis={0} mr={0.5}>
          <Button
            fluid
            textAlign="center"
            icon={q.icon}
            content={q.name}
            tooltip={'Ask ' + q.department + ', with this room'}
            onClick={() => act('quick', { name: q.name })} />
        </Flex.Item>
      ))}
    </Flex>
  );
};

const Notice = props => {
  const { notice } = props;
  if (!notice) {
    return null;
  }
  const good = notice[1] === 'good';
  return (
    <Box
      mb={1}
      p={1}
      color={good ? 'good' : 'bad'}
      style={{
        'background-color': good
          ? 'rgba(91, 170, 39, 0.15)'
          : 'rgba(219, 40, 40, 0.15)',
        'border-left': '3px solid currentColor',
      }}>
      {notice[0]}
    </Box>
  );
};

// Where a request stands
const Tracking = props => {
  const { tracking } = props;
  if (!tracking) {
    return null;
  }
  if (tracking.status === 'done') {
    return (
      <Box inline color="good">{'Done - ' + tracking.handler}</Box>
    );
  }
  if (tracking.status === 'on it') {
    return (
      <Box inline color="average">{'On it - ' + tracking.handler}</Box>
    );
  }
  return <Box inline color="label">Not answered yet</Box>;
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
          {!!msg.tracking && (
            <Flex mt={0.5} align="center">
              <Flex.Item grow={1}>
                <Tracking tracking={msg.tracking} />
              </Flex.Item>
              {msg.tracking.status === 'new' && (
                <Flex.Item>
                  <Button
                    icon="running"
                    content="On it"
                    onClick={() => act('request_status', {
                      id: msg.tracking.id,
                      status: 'on it',
                    })} />
                </Flex.Item>
              )}
              {msg.tracking.status !== 'done' && (
                <Flex.Item>
                  <Button
                    icon="check"
                    color="good"
                    content="Done"
                    onClick={() => act('request_status', {
                      id: msg.tracking.id,
                      status: 'done',
                    })} />
                </Flex.Item>
              )}
            </Flex>
          )}
        </Box>
      ))}
      <Sent data={data} />
    </Section>
  );
};

// What this department asked for, and where each stands
const Sent = props => {
  const { data } = props;
  const sent = data.sent || [];
  if (!sent.length) {
    return null;
  }
  return (
    <Section level={2} title="Sent requests">
      {sent.map(req => (
        <Flex key={req.id} className="candystripe" p={0.5} align="center">
          <Flex.Item grow={1}>
            <Box>
              <Box inline bold>{'To ' + req.to}</Box>
              <Box inline color="label" ml={1}>{req.time}</Box>
            </Box>
            <Box color="label">{req.body}</Box>
          </Flex.Item>
          <Flex.Item ml={1}>
            <Tracking tracking={req.tracking} />
          </Flex.Item>
        </Flex>
      ))}
    </Section>
  );
};

// A crate for Cargo, into the cargo console's request list
class CrateRequest extends Component {
  constructor() {
    super();
    this.state = { search: '', reason: '' };
  }

  render() {
    const { data, act } = this.props;
    const query = this.state.search.toLowerCase();
    const packs = (data.packs || [])
      .filter(pack => !query || pack.name.toLowerCase().includes(query)
        || (pack.group || '').toLowerCase().includes(query))
      .slice(0, 25);
    return (
      <Section level={2} title="Request a crate from Cargo">
        <Flex mb={0.5}>
          <Flex.Item grow={1} mr={0.5}>
            <Input
              fluid
              placeholder="Search the crates..."
              value={this.state.search}
              onInput={(e, value) => this.setState({ search: value })} />
          </Flex.Item>
          <Flex.Item grow={1}>
            <Input
              fluid
              placeholder="Reason (optional)"
              value={this.state.reason}
              onInput={(e, value) => this.setState({ reason: value })} />
          </Flex.Item>
        </Flex>
        {packs.map(pack => (
          <Flex key={pack.id} className="candystripe" p={0.5} align="center">
            <Flex.Item grow={1}>{pack.name}</Flex.Item>
            <Flex.Item color="label" mr={1}>
              {pack.group + ', ' + pack.cost + ' cr'}
            </Flex.Item>
            <Flex.Item>
              <Button
                icon="box"
                content="Request"
                onClick={() => act('crate', {
                  id: pack.id,
                  reason: this.state.reason,
                })} />
            </Flex.Item>
          </Flex>
        ))}
      </Section>
    );
  }
}

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
      {data.screen === 2 && !!data.cargo && (
        <CrateRequest data={data} act={act} />
      )}
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
        <QuickRequests data={data} act={act} />
        <Tabs data={data} act={act} />
      </Section>
      <Notice notice={data.notice} />
      {body}
    </Fragment>
  );
};
