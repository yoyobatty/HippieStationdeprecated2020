import { Component, Fragment } from 'inferno';
import { useBackend } from '../backend';
import { Box, Button, Dropdown, Flex, Icon, Input, LabeledList, NoticeBox, Section, Table } from '../components';

// hippie -- the PDA: the original PDA's screens, tidied
// (hippiestation/.../items/devices/pda_tgui.dm)

const FIELD = {
  'width': '100%',
  'box-sizing': 'border-box',
  'background-color': 'rgba(0, 0, 0, 0.4)',
  'color': '#ffffff',
  'border': '1px solid #344f6d',
  'font-family': 'Verdana, sans-serif',
  'font-size': '12px',
  'padding': '4px',
};

const MONO = { 'font-family': 'monospace' };

// Each screen's title and icon, as the original's headings had them
const TITLES = {
  0: ['PERSONAL DATA ASSISTANT v.1.2', 'tablet-alt'],
  1: ['Notekeeper V2.2', 'sticky-note'],
  2: ['SpaceMessenger V3.9.6', 'envelope'],
  21: ['Messages', 'envelope-open-text'],
  22: ['Conversations', 'comments'],
  24: ['New Message', 'pen'],
  3: ['Atmospheric Readings', 'wind'],
  40: ['Remote Signaling System', 'broadcast-tower'],
  41: ['Crew Manifest', 'users'],
  42: ['Station Status Display Interlink', 'tv'],
  43: ['Power Monitors', 'bolt'],
  433: ['Power Monitor', 'bolt'],
  44: ['Medical Record List', 'notes-medical'],
  441: ['Medical Record', 'notes-medical'],
  45: ['Security Record List', 'shield-alt'],
  451: ['Security Record', 'shield-alt'],
  47: ['Supply Record Interlink', 'box'],
  48: ['Ore Silo Logs', 'gem'],
  49: ['Persistent Custodial Object Locator', 'broom'],
  53: ['Newscaster Access', 'newspaper'],
  54: ['Bots Interlink', 'robot'],
  99: ['Newscaster Access', 'newspaper'],
};

// Box in this tgui has no padding props (p, px, py): padding goes in style.
// Nor can Flex or Flex.Item take style alongside grow, align or justify,
// which their style replaces.

const Badge = props => {
  if (!props.count) {
    return null;
  }
  return (
    <Box
      inline
      ml={0.5}
      backgroundColor="bad"
      color="white"
      bold
      style={{
        'padding': '0 5px',
        'border-radius': '8px',
        'font-size': '10px',
        'line-height': '14px',
      }}>
      {props.count}
    </Box>
  );
};

// The time, its colons blinking
const Clock = props => {
  const parts = (props.time || '').split(':');
  return (
    <Box as="span" className={props.className}>
      {parts.map((part, i) => (
        <Fragment key={i}>
          {i > 0 && <span className="Pda__colon">:</span>}
          {part}
        </Fragment>
      ))}
    </Box>
  );
};

// Bars for whether a message gets through, from the route one takes
const SignalBars = props => {
  const signal = props.signal || {};
  const bars = signal.bars || 0;
  return (
    <span
      className={'Pda__signal' + (bars ? '' : ' Pda__signal--none')}
      title={signal.why}>
      {[3, 5, 7, 10].map((height, i) => (
        <span
          key={i}
          className={'Pda__bar' + (i < bars ? ' Pda__bar--on' : '')}
          style={{ 'height': height + 'px' }} />
      ))}
    </span>
  );
};

// The strip along the top, as on a handheld: who it's for, what's on, time
const StatusBar = props => {
  const { data } = props;
  return (
    <Box className="Pda__status">
      <Flex align="center">
        <Flex.Item grow={1} fontFamily="monospace" nowrap>
          <SignalBars signal={data.signal} />
          {data.owner}
          <Box inline color="label" ml={1}>{data.job}</Box>
        </Flex.Item>
        {!!data.unread && (
          <Flex.Item ml={1} color="average">
            <span className="Pda__pulse">
              <Icon name="envelope" />
            </span>
            <Badge count={data.unread} />
          </Flex.Item>
        )}
        {!!data.light && (
          <Flex.Item ml={1} color="yellow">
            <Icon name="lightbulb" />
          </Flex.Item>
        )}
        {!!data.id && (
          <Flex.Item ml={1} color="label">
            <Icon name="id-card" />
          </Flex.Item>
        )}
        {!!data.cartridge && (
          <Flex.Item ml={1} color="label">
            <Icon name="sd-card" />
          </Flex.Item>
        )}
        <Flex.Item ml={1.5} bold fontFamily="monospace">
          <Clock time={data.time} />
        </Flex.Item>
      </Flex>
    </Box>
  );
};

// Back and Home, and the screen's name
const NavBar = props => {
  const { data, act, title } = props;
  const entry = TITLES[data.mode] || ['', 'tablet-alt'];
  if (data.mode === 0) {
    return (
      <Box bold textAlign="center" mb={1} fontFamily="monospace">
        <Icon name={entry[1]} mr={1} />
        {entry[0]}
      </Box>
    );
  }
  return (
    <Flex align="center" mb={1}>
      <Flex.Item>
        <Button
          icon="arrow-left"
          content="Back"
          onClick={() => act('back')} />
        <Button
          icon="home"
          content="Home"
          onClick={() => act('home')} />
      </Flex.Item>
      <Flex.Item grow={1} ml={1} bold textAlign="right">
        <Icon name={entry[1]} mr={1} />
        {title || entry[0]}
      </Flex.Item>
    </Flex>
  );
};

// A screen's own buttons, above it, as the original had its links
const Toolbar = props => (
  <Box mb={1}>{props.children}</Box>
);

// ---------------------------------------------------------------------------
// Home
// ---------------------------------------------------------------------------

const IdLine = props => {
  const { data, act } = props;
  if (!data.id) {
    return (
      <Fragment>
        <Box inline color="label" fontFamily="monospace">----------</Box>
        {!!data.holding_id && (
          <Button
            ml={1}
            icon="id-card"
            content="Insert ID"
            onClick={() => act('id')} />
        )}
      </Fragment>
    );
  }
  return (
    <Fragment>
      <Button
        icon="eject"
        content={data.id}
        tooltip="Remove the ID"
        onClick={() => act('id')} />
      <Button
        icon="sync"
        content="Update PDA Info"
        onClick={() => act('update_info')} />
    </Fragment>
  );
};

const CELL = { 'width': '50%', 'padding': '2px' };

const hasItem = (menu, key) => (menu || []).some(section => (
  section.items.some(item => item.key === key)
));

const Home = props => {
  const { data, act } = props;
  return (
    <Fragment>
      <Section>
        <Flex align="center">
          <Flex.Item grow={1}>
            <LabeledList>
              <LabeledList.Item label="Owner">
                {data.owner + ', ' + data.job}
              </LabeledList.Item>
              <LabeledList.Item label="ID">
                <IdLine data={data} act={act} />
              </LabeledList.Item>
            </LabeledList>
          </Flex.Item>
          <Flex.Item textAlign="right" ml={1}>
            <Box fontSize="26px" bold fontFamily="monospace">
              <Clock time={data.time} className="Pda__clock" />
            </Box>
            <Box color="label">{data.date}</Box>
          </Flex.Item>
        </Flex>
        {!!data.cartridge && (
          <Box mt={1}>
            <Button
              icon="eject"
              content={'Eject ' + data.cartridge}
              onClick={() => act('eject_cart')} />
          </Box>
        )}
      </Section>
      {data.theme === 'clown' && hasItem(data.menu, 'honk') && (
        <Box mb={1}>
          <Button
            fluid
            className="Pda__honk"
            icon="bullhorn"
            content="HONK!"
            onClick={() => act('open', { key: 'honk' })} />
        </Box>
      )}
      {(data.menu || []).map(section => (
        <Section key={section.title} title={section.title}>
          <Flex wrap="wrap">
            {section.items.map(item => (
              <Flex.Item key={item.key} style={CELL}>
                <Button
                  fluid
                  icon={item.icon}
                  selected={item.on}
                  onClick={() => act('open', { key: item.key })}>
                  {item.name}
                  <Badge count={item.badge} />
                </Button>
              </Flex.Item>
            ))}
          </Flex>
        </Section>
      ))}
    </Fragment>
  );
};

// ---------------------------------------------------------------------------
// Notekeeper
// ---------------------------------------------------------------------------

class Notes extends Component {
  constructor(props) {
    super(props);
    this.state = { editing: false, text: props.data.note || '' };
  }

  render() {
    const { data, act } = this.props;
    if (this.state.editing) {
      return (
        <Section
          title="Edit"
          buttons={(
            <Fragment>
              <Button
                icon="save"
                content="Save"
                onClick={() => {
                  act('save_note', { text: this.state.text });
                  this.setState({ editing: false });
                }} />
              <Button
                icon="times"
                content="Cancel"
                onClick={() => this.setState({ editing: false })} />
            </Fragment>
          )}>
          <textarea
            value={this.state.text}
            onInput={e => this.setState({ text: e.target.value })}
            style={Object.assign({}, FIELD, { 'height': '420px' })} />
        </Section>
      );
    }
    return (
      <Fragment>
        <Toolbar>
          <Button
            icon="pen"
            content="Edit"
            onClick={() => this.setState({
              editing: true,
              text: data.note || '',
            })} />
        </Toolbar>
        <Section>
          {!!data.note_scanned && (
            <Box color="label" mb={1}>
              (This is a scanned image, editing it may cause some text
              formatting to change.)
            </Box>
          )}
          <Box style={{ 'white-space': 'pre-wrap' }}>{data.note}</Box>
        </Section>
      </Fragment>
    );
  }
}

// ---------------------------------------------------------------------------
// Messenger
// ---------------------------------------------------------------------------

class Messenger extends Component {
  constructor(props) {
    super(props);
    this.state = { tone: props.data.ringtone || '' };
  }

  render() {
    const { data, act } = this.props;
    const toggle = what => act('toggle', { what });
    const contacts = data.contacts || [];
    const virus = data.virus_charges;
    const hasVirus = virus !== null && virus !== undefined;
    const signal = data.signal || {};
    return (
      <Fragment>
        {!data.toff && !signal.bars && (
          <NoticeBox>{signal.why}</NoticeBox>
        )}
        <Section>
          <Box mb={0.5}>
            <Button
              icon={data.silent ? 'bell-slash' : 'bell'}
              content={'Ringer: ' + (data.silent ? 'Off' : 'On')}
              selected={!data.silent}
              onClick={() => toggle('ringer')} />
            <Button
              icon="envelope"
              content={'Send / Receive: ' + (data.toff ? 'Off' : 'On')}
              selected={!data.toff}
              onClick={() => toggle('messenger')} />
            <Button
              icon="heartbeat"
              content={'Emergency Beacon: ' + (data.beacon ? 'On' : 'Off')}
              selected={data.beacon}
              onClick={() => toggle('beacon')} />
          </Box>
          <Box mb={0.5}>
            <Button
              icon="envelope-open-text"
              content="Messages"
              onClick={() => act('open', { key: '21' })}>
              <Badge count={data.unread} />
            </Button>
            <Button
              icon="comments"
              content="Conversations"
              onClick={() => act('conversations')} />
          </Box>
          <Flex align="center">
            <Flex.Item color="label" mr={1}>
              <Icon name="bell" mr={0.5} />
              Ringtone
            </Flex.Item>
            <Flex.Item>
              <Input
                width="120px"
                maxLength={20}
                value={this.state.tone}
                onInput={(e, value) => this.setState({ tone: value })} />
            </Flex.Item>
            <Flex.Item>
              <Button
                content="Set Ringtone"
                onClick={() => act('ringtone', { text: this.state.tone })} />
            </Flex.Item>
          </Flex>
          {hasVirus && (
            <Box mt={1} bold color="average">
              {virus + ' viral files left.'}
            </Box>
          )}
        </Section>
        <Section
          title="Detected PDAs"
          buttons={!!data.can_send_all && !!contacts.length && (
            <Button
              icon="bullhorn"
              content="Send To All"
              onClick={() => act('compose', { everyone: 1 })} />
          )}>
          {!!data.toff && (
            <Box color="label">Send / Receive is off.</Box>
          )}
          {!data.toff && contacts.length === 0 && (
            <Box color="label">None detected.</Box>
          )}
          {contacts.map(contact => (
            <Flex key={contact.ref} className="candystripe" align="center">
              <Flex.Item grow={1}>
                <Button
                  fluid
                  icon="user"
                  color="transparent"
                  content={contact.name}
                  onClick={() => act('compose', { ref: contact.ref })} />
              </Flex.Item>
              {hasVirus && (
                <Flex.Item>
                  <Button
                    icon="bug"
                    content="*Send Virus*"
                    color="bad"
                    disabled={!virus}
                    onClick={() => act('virus', { ref: contact.ref })} />
                </Flex.Item>
              )}
            </Flex>
          ))}
        </Section>
      </Fragment>
    );
  }
}

const MessageLog = props => {
  const { data, act } = props;
  const log = data.log || [];
  return (
    <Fragment>
      <Toolbar>
        <Button
          icon="trash"
          content="Clear Messages"
          disabled={!log.length}
          onClick={() => act('clear')} />
      </Toolbar>
      <MessageEntries log={log} act={act} />
    </Fragment>
  );
};

const ROW = { 'padding': '4px 6px' };

const MessageEntries = props => {
  const { log, act } = props;
  return (
    <Section>
      {log.length === 0 && <Box color="label">No messages.</Box>}
      {log.map((entry, i) => {
        let heading = 'From ' + entry.name + ' (' + entry.job + ')';
        let color = 'label';
        if (entry.out) {
          heading = 'To ' + entry.name;
          if (entry.job) {
            heading += ' (' + entry.job + ')';
          }
          color = 'good';
        }
        if (entry.page) {
          heading = entry.page + ' - ' + entry.name;
          color = 'bad';
        }
        return (
          <Box key={i} className="candystripe" style={ROW}>
            <Flex align="center">
              <Flex.Item grow={1} bold color={color} italic>
                <Icon name={entry.out ? 'arrow-right' : 'arrow-left'} mr={1} />
                {heading}
              </Flex.Item>
              <Flex.Item color="label" fontSize="11px" mr={1}>
                {(entry.photo ? 'photo - ' : '') + entry.time}
              </Flex.Item>
              {!entry.out && !!entry.pda && (
                <Flex.Item>
                  <Button
                    icon="reply"
                    content="Reply"
                    onClick={() => act('compose', { ref: entry.pda })} />
                </Flex.Item>
              )}
            </Flex>
            <Box ml={3} style={{ 'white-space': 'pre-wrap' }}>
              {'"' + entry.text + '"'}
            </Box>
          </Box>
        );
      })}
    </Section>
  );
};

const Conversations = props => {
  const { data, act } = props;
  const threads = data.threads || [];
  return (
    <Section>
      {threads.length === 0 && (
        <Box color="label" textAlign="center">No conversations yet.</Box>
      )}
      {threads.map(thread => (
        <Box
          key={thread.key}
          className="candystripe"
          style={{ 'padding': '4px 6px', 'cursor': 'pointer' }}
          onClick={() => act('thread', { key: thread.key })}>
          <Flex>
            <Flex.Item grow={1} bold>
              {thread.name}
              <Badge count={thread.unread} />
            </Flex.Item>
            <Flex.Item color="label" fontSize="11px">{thread.time}</Flex.Item>
          </Flex>
          <Box color="label" fontSize="11px">{thread.job}</Box>
          <Box
            color={thread.unread ? null : 'label'}
            style={{
              'overflow': 'hidden',
              'white-space': 'nowrap',
              'text-overflow': 'ellipsis',
            }}>
            {thread.last}
          </Box>
        </Box>
      ))}
    </Section>
  );
};

// A message; one that came while the conversation was open slides in
const Bubble = props => {
  const { message, fresh } = props;
  let color = 'rgba(255, 255, 255, 0.1)';
  if (message.out) {
    color = 'var(--pda-button)';
  }
  if (message.page) {
    color = 'rgba(200, 40, 40, 0.45)';
  }
  let className = null;
  if (fresh) {
    className = message.out ? 'Pda__bubble--out' : 'Pda__bubble--in';
  }
  return (
    <Flex justify={message.out ? 'flex-end' : 'flex-start'} mb={0.5}>
      <Flex.Item
        className={className}
        style={{
          'max-width': '80%',
          'padding': '5px 9px',
          'background-color': color,
          'border-radius': '10px',
          'white-space': 'pre-wrap',
          'word-wrap': 'break-word',
        }}>
        {!!message.page && (
          <Box bold fontSize="11px">{message.page}</Box>
        )}
        <Box>{message.text}</Box>
        <Box textAlign="right" color="label" fontSize="10px">
          {(message.photo ? 'photo - ' : '') + message.time}
        </Box>
      </Flex.Item>
    </Flex>
  );
};

// A box to type in and Send; Enter sends too
class WriteBox extends Component {
  constructor() {
    super();
    this.state = { text: '' };
  }

  send() {
    if (!this.state.text) {
      return;
    }
    this.props.onSend(this.state.text);
    this.setState({ text: '' });
  }

  render() {
    return (
      <Flex>
        <Flex.Item grow={1}>
          <input
            value={this.state.text}
            placeholder={this.props.placeholder || 'Message...'}
            maxLength={1024}
            onInput={e => this.setState({ text: e.target.value })}
            onKeyDown={e => {
              if (e.keyCode === 13) {
                this.send();
              }
            }}
            style={FIELD} />
        </Flex.Item>
        <Flex.Item ml={0.5}>
          <Button
            icon="paper-plane"
            content="Send"
            disabled={!this.state.text}
            onClick={() => this.send()} />
        </Flex.Item>
      </Flex>
    );
  }
}

// The mime's PDA has nothing to say
const placeholder = data => (data.theme === 'mime' ? '...' : null);

class Thread extends Component {
  constructor(props) {
    super(props);
    // What was there when it opened doesn't slide in; what comes after does
    this.seen = props.data.thread.messages.length;
  }

  render() {
    const { data, act } = this.props;
    const thread = data.thread;
    let reply = (
      <Box color="label" textAlign="center">
        They can&apos;t be reached now.
      </Box>
    );
    if (data.toff) {
      reply = (
        <Box color="label" textAlign="center">Send / Receive is off.</Box>
      );
    }
    else if (data.can_reply) {
      reply = (
        <WriteBox
          placeholder={placeholder(data)}
          onSend={text => act('send', { text })} />
      );
    }
    return (
      <Section
        title={thread.job}
        buttons={(
          <Button
            icon="trash"
            color="transparent"
            tooltip="Delete this conversation"
            tooltipPosition="left"
            onClick={() => act('delete_thread', { key: thread.key })} />
        )}>
        <Box mb={1}>
          {thread.messages.map((message, i) => (
            <Bubble key={i} message={message} fresh={i >= this.seen} />
          ))}
        </Box>
        {reply}
      </Section>
    );
  }
}

const Compose = props => {
  const { data, act } = props;
  let to = data.compose_to;
  if (to === 'everyone') {
    to = 'Everyone';
  }
  return (
    <Section title={'To ' + to}>
      <WriteBox
        placeholder={placeholder(data)}
        onSend={text => act('send', { text })} />
    </Section>
  );
};

// ---------------------------------------------------------------------------
// Atmospheric scan
// ---------------------------------------------------------------------------

const Atmos = props => {
  const { data } = props;
  const atmos = data.atmos;
  if (!atmos) {
    return (
      <Section>
        <Box color="bad">Unable to obtain a reading.</Box>
      </Section>
    );
  }
  return (
    <Section>
      <LabeledList>
        <LabeledList.Item label="Air Pressure">
          {atmos.pressure + ' kPa'}
        </LabeledList.Item>
        {atmos.gases.map(gas => (
          <LabeledList.Item key={gas.name} label={gas.name}>
            {gas.percent + '%'}
          </LabeledList.Item>
        ))}
        <LabeledList.Item label="Temperature">
          {atmos.temperature + ' °C'}
        </LabeledList.Item>
      </LabeledList>
    </Section>
  );
};

// ---------------------------------------------------------------------------
// Cartridge programs
// ---------------------------------------------------------------------------

const cart = (act, what, params) => (
  act('cart', Object.assign({ do: what }, params))
);

const Signaler = props => {
  const { data, act } = props;
  const signal = data.signal;
  if (!signal) {
    return <NoticeBox>No signaler in this cartridge.</NoticeBox>;
  }
  const step = (what, by) => cart(act, what, { by });
  return (
    <Section>
      <Button
        icon="broadcast-tower"
        content="Send Signal"
        onClick={() => cart(act, 'send_signal')} />
      <LabeledList>
        <LabeledList.Item label="Frequency">
          <Button content="-" onClick={() => step('frequency', -10)} />
          <Button content="-" onClick={() => step('frequency', -2)} />
          <Box inline mx={1} bold style={MONO}>{signal.frequency}</Box>
          <Button content="+" onClick={() => step('frequency', 2)} />
          <Button content="+" onClick={() => step('frequency', 10)} />
        </LabeledList.Item>
        <LabeledList.Item label="Code">
          <Button content="-" onClick={() => step('code', -5)} />
          <Button content="-" onClick={() => step('code', -1)} />
          <Box inline mx={1} bold style={MONO}>{signal.code}</Box>
          <Button content="+" onClick={() => step('code', 1)} />
          <Button content="+" onClick={() => step('code', 5)} />
        </LabeledList.Item>
      </LabeledList>
    </Section>
  );
};

const Manifest = props => {
  const { data } = props;
  const crew = data.manifest || [];
  return (
    <Section>
      <Box color="label" mb={1}>
        Entries cannot be modified from this terminal.
      </Box>
      <Table>
        {crew.map((person, i) => (
          <Table.Row key={i} className="candystripe">
            <Table.Cell>{person.name}</Table.Cell>
            <Table.Cell color="label">{person.rank}</Table.Cell>
          </Table.Row>
        ))}
      </Table>
    </Section>
  );
};

class StatusDisplay extends Component {
  constructor(props) {
    super(props);
    const status = props.data.status || {};
    this.state = { line1: status.line1 || '', line2: status.line2 || '' };
  }

  render() {
    const { act } = this.props;
    // Typed in, then Set (or Enter), as the original's "Set" links
    const set = (n, text) => cart(act, 'status_line', { line: n, text });
    const line = n => (
      <Flex align="center">
        <Flex.Item grow={1}>
          <Input
            fluid
            maxLength={40}
            value={this.state['line' + n]}
            onInput={(e, value) => this.setState({ ['line' + n]: value })}
            onChange={(e, value) => set(n, value)} />
        </Flex.Item>
        <Flex.Item ml={0.5}>
          <Button
            content="Set"
            onClick={() => set(n, this.state['line' + n])} />
        </Flex.Item>
      </Flex>
    );
    const alert = (key, label) => (
      <Button
        content={label}
        onClick={() => cart(act, 'status_alert', { alert: key })} />
    );
    return (
      <Section>
        <Box mb={1}>
          <Button
            icon="eraser"
            content="Clear"
            onClick={() => cart(act, 'status', { what: 'blank' })} />
          <Button
            icon="space-shuttle"
            content="Shuttle ETA"
            onClick={() => cart(act, 'status', { what: 'shuttle' })} />
          <Button
            icon="comment"
            content="Message"
            onClick={() => cart(act, 'status', { what: 'message' })} />
        </Box>
        <LabeledList>
          <LabeledList.Item label="Line 1">{line(1)}</LabeledList.Item>
          <LabeledList.Item label="Line 2">{line(2)}</LabeledList.Item>
          <LabeledList.Item label="Alert">
            {alert('default', 'None')}
            {alert('redalert', 'Red Alert')}
            {alert('lockdown', 'Lockdown')}
            {alert('biohazard', 'Biohazard')}
          </LabeledList.Item>
        </LabeledList>
      </Section>
    );
  }
}

const PowerList = props => {
  const { data, act } = props;
  const monitors = data.monitors || [];
  return (
    <Section title="Please select one">
      {monitors.length === 0 && <Box color="bad">No connection</Box>}
      {monitors.map(monitor => (
        <Button
          key={monitor.index}
          fluid
          icon="desktop"
          content={monitor.name + ' - ' + monitor.area}
          onClick={() => cart(act, 'power_select', { index: monitor.index })} />
      ))}
    </Section>
  );
};

// The original's short states, so the area names have the room
const POWER_STATE = {
  'On': ['On', 'good'],
  'Auto on': ['AOn', 'good'],
  'Off': ['Off', 'bad'],
  'Auto off': ['AOff', 'average'],
};

const CHARGE_ICON = {
  'charging': ['bolt', 'good'],
  'full': ['check', 'label'],
  'not charging': ['minus', 'average'],
};

const PowerMonitor = props => {
  const { data } = props;
  const power = data.power;
  if (!power) {
    return <Section><Box color="bad">No connection</Box></Section>;
  }
  const state = s => {
    const entry = POWER_STATE[s] || [s, 'label'];
    return <Box inline color={entry[1]} title={s}>{entry[0]}</Box>;
  };
  return (
    <Fragment>
      <Section>
        <LabeledList>
          <LabeledList.Item label="Location">{power.location}</LabeledList.Item>
          <LabeledList.Item label="Total power">
            {power.available}
          </LabeledList.Item>
          <LabeledList.Item label="Total load">{power.load}</LabeledList.Item>
        </LabeledList>
      </Section>
      <Section title="Areas">
        <Table>
          <Table.Row header>
            <Table.Cell>Area</Table.Cell>
            <Table.Cell collapsing>Eqp.</Table.Cell>
            <Table.Cell collapsing>Lgt.</Table.Cell>
            <Table.Cell collapsing>Env.</Table.Cell>
            <Table.Cell collapsing>Load</Table.Cell>
            <Table.Cell collapsing>Cell</Table.Cell>
          </Table.Row>
          {power.apcs.map((apc, i) => {
            let cell = <Box inline color="bad">N/C</Box>;
            if (apc.cell !== null) {
              const charge = CHARGE_ICON[apc.charging] || ['minus', 'label'];
              cell = (
                <Box inline nowrap title={apc.charging}>
                  {apc.cell + '%'}
                  <Icon name={charge[0]} color={charge[1]} ml={0.5} />
                </Box>
              );
            }
            return (
              <Table.Row key={i} className="candystripe">
                <Table.Cell>{apc.area}</Table.Cell>
                <Table.Cell collapsing>{state(apc.equipment)}</Table.Cell>
                <Table.Cell collapsing>{state(apc.lighting)}</Table.Cell>
                <Table.Cell collapsing>{state(apc.environ)}</Table.Cell>
                <Table.Cell collapsing>{apc.load}</Table.Cell>
                <Table.Cell collapsing>{cell}</Table.Cell>
              </Table.Row>
            );
          })}
        </Table>
      </Section>
    </Fragment>
  );
};

const RecordList = props => {
  const { data, act } = props;
  const records = data.records || [];
  return (
    <Section>
      {records.length === 0 && <Box color="label">No records.</Box>}
      {records.map(record => (
        <Button
          key={record.id}
          fluid
          color="transparent"
          icon="file-alt"
          content={record.id + ': ' + record.name}
          onClick={() => cart(act, 'record', { id: record.id })} />
      ))}
    </Section>
  );
};

const GeneralRecord = props => {
  const g = props.general;
  if (!g) {
    return <Section><Box bold color="bad">Record Lost!</Box></Section>;
  }
  return (
    <Section>
      <LabeledList>
        <LabeledList.Item label="Name">{g.name}</LabeledList.Item>
        <LabeledList.Item label="ID">{g.id}</LabeledList.Item>
        <LabeledList.Item label="Gender">{g.gender}</LabeledList.Item>
        <LabeledList.Item label="Age">{g.age}</LabeledList.Item>
        <LabeledList.Item label="Rank">{g.rank}</LabeledList.Item>
        <LabeledList.Item label="Fingerprint">{g.fingerprint}</LabeledList.Item>
        <LabeledList.Item label="Physical Status">{g.p_stat}</LabeledList.Item>
        <LabeledList.Item label="Mental Status">{g.m_stat}</LabeledList.Item>
      </LabeledList>
    </Section>
  );
};

const MedicalRecord = props => {
  const { data } = props;
  const m = data.medical;
  const pair = (label, value, details) => (
    <LabeledList.Item label={label}>
      {value}
      {!!details && <Box color="label">{details}</Box>}
    </LabeledList.Item>
  );
  return (
    <Fragment>
      <GeneralRecord general={data.general} />
      <Section title="Medical Data">
        {!m && <Box bold color="bad">Record Lost!</Box>}
        {!!m && (
          <LabeledList>
            <LabeledList.Item label="Blood Type">
              {m.blood_type}
            </LabeledList.Item>
            {pair('Minor Disabilities', m.mi_dis, m.mi_dis_d)}
            {pair('Major Disabilities', m.ma_dis, m.ma_dis_d)}
            {pair('Allergies', m.alg, m.alg_d)}
            {pair('Current Diseases', m.cdi, m.cdi_d)}
            <LabeledList.Item label="Important Notes">
              {m.notes}
            </LabeledList.Item>
          </LabeledList>
        )}
      </Section>
    </Fragment>
  );
};

const CrimeTable = props => {
  const { crimes } = props;
  if (!crimes.length) {
    return <Box color="label" mb={1}>None.</Box>;
  }
  return (
    <Table mb={1}>
      <Table.Row header>
        <Table.Cell>Crime</Table.Cell>
        <Table.Cell>Details</Table.Cell>
        <Table.Cell>Author</Table.Cell>
        <Table.Cell>Time Added</Table.Cell>
      </Table.Row>
      {crimes.map((crime, i) => (
        <Table.Row key={i} className="candystripe">
          <Table.Cell>{crime.name}</Table.Cell>
          <Table.Cell>{crime.details}</Table.Cell>
          <Table.Cell>{crime.author}</Table.Cell>
          <Table.Cell>{crime.time}</Table.Cell>
        </Table.Row>
      ))}
    </Table>
  );
};

const SecurityRecord = props => {
  const { data } = props;
  const s = data.security;
  return (
    <Fragment>
      <GeneralRecord general={data.general} />
      <Section title="Security Data">
        {!s && <Box bold color="bad">Record Lost!</Box>}
        {!!s && (
          <Fragment>
            <LabeledList>
              <LabeledList.Item label="Criminal Status">
                {s.criminal}
              </LabeledList.Item>
            </LabeledList>
            <Box bold mt={1} mb={0.5}>Minor Crimes</Box>
            <CrimeTable crimes={s.minor} />
            <Box bold mb={0.5}>Major Crimes</Box>
            <CrimeTable crimes={s.major} />
            <Box bold mb={0.5}>Important Notes</Box>
            <Box>{s.notes}</Box>
          </Fragment>
        )}
      </Section>
    </Fragment>
  );
};

const Supply = props => {
  const { data } = props;
  const supply = data.supply;
  if (!supply) {
    return null;
  }
  const list = (title, items, render) => (
    <Section title={title}>
      {items.length === 0 && <Box color="label">None.</Box>}
      {items.map((item, i) => (
        <Box key={i} className="candystripe" style={ROW}>
          {render(item)}
        </Box>
      ))}
    </Section>
  );
  return (
    <Fragment>
      <Section title="Supply shuttle">
        <LabeledList>
          <LabeledList.Item label="Location">{supply.where}</LabeledList.Item>
        </LabeledList>
      </Section>
      {list('Current approved orders', supply.approved, o => {
        let text = '#' + o.id + ' - ' + o.pack + ' ordered by ' + o.orderer;
        if (o.approved_by) {
          text += ', approved by ' + o.approved_by;
        }
        if (o.reason) {
          text += ' (' + o.reason + ')';
        }
        return text;
      })}
      {list('Current requests', supply.requests, o => (
        '#' + o.id + ' - ' + o.pack + ' requested by ' + o.orderer
      ))}
      {list('Recently shipped', supply.shipped, o => (
        '#' + o.id + ' - ' + o.text
      ))}
    </Fragment>
  );
};

const Silo = props => {
  const { data } = props;
  const silo = data.silo;
  if (!silo) {
    return <Section><Box bold color="bad">No ore silo detected!</Box></Section>;
  }
  return (
    <Section>
      {silo.entries.length === 0 && <Box color="label">Nothing!</Box>}
      {silo.entries.map(entry => (
        <Box key={entry.index} className="candystripe" style={ROW}>
          <Box inline color="label" mr={1}>{entry.index + '.'}</Box>
          {entry.text}
        </Box>
      ))}
      {!!silo.more && (
        <Box color="label" mt={1}>(... older logs not shown ...)</Box>
      )}
    </Section>
  );
};

const Janitor = props => {
  const { data } = props;
  const j = data.janitor;
  if (!j) {
    return (
      <Section>
        <Box color="bad">ERROR: Unable to determine current location.</Box>
      </Section>
    );
  }
  const list = (title, label, items) => (
    <Section title={title}>
      {items.length === 0 && <Box color="label">None</Box>}
      {items.map((item, i) => (
        <Flex key={i} className="candystripe" style={ROW}>
          <Flex.Item grow={1}>{label}</Flex.Item>
          <Flex.Item mr={1} bold style={MONO}>
            {'[' + item.x + ',' + item.y + '] ' + item.dir}
          </Flex.Item>
          <Flex.Item color="label">{item.state}</Flex.Item>
        </Flex>
      ))}
    </Section>
  );
  return (
    <Fragment>
      <Section>
        Current Orbital Location:
        <Box inline ml={1} bold style={MONO}>{'[' + j.x + ',' + j.y + ']'}</Box>
      </Section>
      {list('Located Mops', 'Mop', j.mops)}
      {list('Located Janitorial Cart', 'Cart', j.carts)}
      {list('Located Cleanbots', 'Cleanbot', j.bots)}
    </Fragment>
  );
};

const News = props => {
  const { data, act } = props;
  const news = data.news;
  if (!news) {
    return null;
  }
  return (
    <Fragment>
      <Section>
        <LabeledList>
          <LabeledList.Item label="Current Newsfeed">
            <Dropdown
              key={news.channel || 'none'}
              width="100%"
              options={news.channels}
              selected={news.channel || 'Choose a channel...'}
              onSelected={name => cart(act, 'news_channel', { name })} />
          </LabeledList.Item>
        </LabeledList>
      </Section>
      {!news.found && (
        <NoticeBox>ERROR : NO CHANNEL FOUND</NoticeBox>
      )}
      {!!news.found && (
        <Section title={news.channel}>
          {news.stories.length === 0 && (
            <Box color="label">No stories on this channel.</Box>
          )}
          {news.stories.map((story, i) => (
            <Box key={i} mb={1} style={{
              'padding-bottom': '6px',
              'border-bottom': '1px solid rgba(255, 255, 255, 0.1)',
            }}>
              <Box style={{ 'white-space': 'pre-wrap' }}>{story.body}</Box>
              <Box color="label" fontSize="11px">
                {'Story by ' + story.author + ' - ' + story.comments.length
                  + ' comment' + (story.comments.length === 1 ? '' : 's')}
              </Box>
              {story.comments.map((comment, j) => (
                <Box key={j} ml={2} mt={0.5} fontSize="11px">
                  {comment.body}
                  <Box color="label">{comment.author + ' ' + comment.time}</Box>
                </Box>
              ))}
            </Box>
          ))}
          <Box bold mb={0.5}>Post Message</Box>
          <WriteBox onSend={text => cart(act, 'news_post', { text })} />
        </Section>
      )}
    </Fragment>
  );
};

const NotAuthorized = props => {
  const { data } = props;
  let text = 'ERROR : NOT AUTHORIZED';
  if (!data.id) {
    text += ' - ID SLOT EMPTY';
  }
  return <NoticeBox>{text}</NoticeBox>;
};

const OnOff = props => (
  <Button
    content={props.on ? 'On' : 'Off'}
    selected={props.on}
    onClick={props.onClick} />
);

const Bots = props => {
  const { data, act } = props;
  const bots = data.bots || {};
  const bot = op => cart(act, 'bot', { op });
  const mule = op => cart(act, 'mule', { op });
  const b = bots.active;
  if (!b) {
    const found = bots.list || [];
    return (
      <Fragment>
        <Toolbar>
          <Button
            icon="sync"
            content="Scan for active bots"
            onClick={() => bot('botlist')} />
        </Toolbar>
        <Section>
          {found.length === 0 && <Box color="label">No bots found.</Box>}
          {found.map(entry => (
            <Button
              key={entry.ref}
              fluid
              color="transparent"
              icon="robot"
              onClick={() => cart(act, 'bot', {
                op: 'control',
                ref: entry.ref,
              })}>
              <b>{entry.name}</b>
              <Box inline ml={1} color={entry.mode_color || 'label'}>
                {entry.mode}
              </Box>
            </Button>
          ))}
        </Section>
      </Fragment>
    );
  }
  const m = b.mule;
  return (
    <Section
      title={b.name}
      buttons={(
        <Fragment>
          <Button
            icon="sync"
            content="Refresh"
            onClick={() => cart(act, 'bot', { op: 'control', ref: b.ref })} />
          <Button
            icon="arrow-left"
            content="Return to bot list"
            onClick={() => bot('botlist')} />
        </Fragment>
      )}>
      <LabeledList>
        <LabeledList.Item label="Model">{b.model}</LabeledList.Item>
        <LabeledList.Item label="Location">{b.location}</LabeledList.Item>
        <LabeledList.Item label="Mode">
          <Box inline color={b.mode_color}>{b.mode}</Box>
        </LabeledList.Item>
        {b.pai !== undefined && (
          <LabeledList.Item label="pAI">
            {b.pai}
            {!!b.can_eject_pai && (
              <Button ml={1} content="Eject" onClick={() => bot('ejectpai')} />
            )}
          </LabeledList.Item>
        )}
        {!!m && (
          <Fragment>
            <LabeledList.Item label="Current Load">
              {m.load || 'none'}
              {!!m.load && (
                <Button
                  ml={1}
                  content="Unload"
                  onClick={() => mule('unload')} />
              )}
            </LabeledList.Item>
            <LabeledList.Item label="Destination">
              {m.destination || 'None'}
              <Button
                ml={1}
                content="Set"
                onClick={() => mule('destination')} />
            </LabeledList.Item>
            <LabeledList.Item label="ID">
              {m.id}
              <Button ml={1} content="Modify" onClick={() => mule('setid')} />
            </LabeledList.Item>
            <LabeledList.Item label="Power">{m.power + '%'}</LabeledList.Item>
            <LabeledList.Item label="Home">{m.home || 'none'}</LabeledList.Item>
            <LabeledList.Item label="Delivery Reporting">
              <OnOff on={m.report} onClick={() => mule('report')} />
            </LabeledList.Item>
            <LabeledList.Item label="Auto Return Home">
              <OnOff on={m.autoret} onClick={() => mule('autoret')} />
            </LabeledList.Item>
            <LabeledList.Item label="Auto Pickup Crate">
              <OnOff on={m.autopick} onClick={() => mule('autopick')} />
            </LabeledList.Item>
          </Fragment>
        )}
      </LabeledList>
      <Box mt={1}>
        {!!m && (
          <Fragment>
            <Button icon="stop" content="Stop" onClick={() => mule('stop')} />
            <Button icon="play" content="Proceed" onClick={() => mule('go')} />
            <Button
              icon="home"
              content="Return Home"
              onClick={() => mule('home')} />
          </Fragment>
        )}
        {!m && (
          <Fragment>
            <Button
              icon="stop"
              content="Stop Patrol"
              onClick={() => bot('patroloff')} />
            <Button
              icon="play"
              content="Start Patrol"
              onClick={() => bot('patrolon')} />
            <Button
              icon="bullhorn"
              content="Summon Bot"
              onClick={() => bot('summon')} />
            <Box color="label" mt={0.5}>
              Keep an ID inserted to upload access codes upon summoning.
            </Box>
          </Fragment>
        )}
      </Box>
    </Section>
  );
};

// ---------------------------------------------------------------------------

const SCREENS = {
  0: Home,
  1: Notes,
  2: Messenger,
  21: MessageLog,
  22: Conversations,
  23: Thread,
  24: Compose,
  3: Atmos,
  40: Signaler,
  41: Manifest,
  42: StatusDisplay,
  43: PowerList,
  433: PowerMonitor,
  44: RecordList,
  441: MedicalRecord,
  45: RecordList,
  451: SecurityRecord,
  47: Supply,
  48: Silo,
  49: Janitor,
  53: News,
  54: Bots,
  99: NotAuthorized,
};

// The plate on the case, and the boot screen's logo, per theme
const BRAND = {
  nt: ['NANOTRASEN', 'NTOS'],
  medical: ['NT MEDICAL', 'NTOS'],
  engineering: ['NT ENGINEERING', 'NTOS'],
  security: ['NT SECURITY', 'NTOS'],
  science: ['NT SCIENCE', 'NTOS'],
  cargo: ['NT SUPPLY', 'NTOS'],
  captain: ['NANOTRASEN COMMAND', 'NTOS'],
  syndicate: ['SYNDICATE', 'SYN-OS'],
  clown: ['HONK CO.', 'HONKOS'],
  mime: ['. . .', '...'],
};

const NoOwner = props => {
  const { data, act } = props;
  return (
    <Box mt={1}>
      <NoticeBox>
        Warning: No owner information entered. Please swipe card.
      </NoticeBox>
      <Button
        icon="id-card"
        content="Swipe ID"
        disabled={!data.holding_id}
        onClick={() => act('id')} />
    </Box>
  );
};

// A second of the PDA starting up, the first time it's opened in a round
const Boot = props => {
  const { data, brand } = props;
  return (
    <div className="Pda__boot">
      <div className="Pda__bootLogo">{brand[1]}</div>
      <div className="Pda__bootText">PERSONAL DATA ASSISTANT v.1.2</div>
      <div className="Pda__bootBar">
        <div className="Pda__bootFill" />
      </div>
      {!!data.owner && (
        <div className="Pda__bootText">{'Welcome, ' + data.owner}</div>
      )}
    </div>
  );
};

// The handheld: its case, the screen, and the button under it
export class Pda extends Component {
  constructor(props) {
    super(props);
    // Only the first update of the round says to boot; it plays out here
    this.state = { booting: !!useBackend(props).data.boot };
  }

  componentDidMount() {
    if (this.state.booting) {
      this.bootTimer = setTimeout(() => {
        this.setState({ booting: false });
      }, 1600);
    }
  }

  componentWillUnmount() {
    clearTimeout(this.bootTimer);
  }

  render() {
    const { act, data } = useBackend(this.props);
    const theme = BRAND[data.theme] ? data.theme : 'nt';
    const brand = BRAND[theme];
    const Screen = SCREENS[data.mode] || Home;
    let title = null;
    if (data.mode === 23 && data.thread) {
      title = data.thread.name;
    }
    let screen = <NoOwner data={data} act={act} />;
    if (data.owner) {
      screen = (
        <Fragment>
          <NavBar data={data} act={act} title={title} />
          <Screen key={data.mode} data={data} act={act} />
        </Fragment>
      );
    }
    let screenClass = 'Pda__screen';
    if (data.mode === 0 || !data.owner) {
      screenClass += ' Pda__screen--home';
    }
    return (
      <div className={'Pda Pda--theme--' + theme}>
        <div className="Pda__top">
          <div className="Pda__grille" />
          <div className="Pda__brand">{brand[0]}</div>
          <div
            className={'Pda__led' + (data.unread ? ' Pda__led--mail' : '')}
            title={data.unread ? 'Unread messages' : null} />
        </div>
        <div className="Pda__glass">
          <div className={screenClass}>
            <StatusBar data={data} />
            {screen}
          </div>
          <div className="Pda__glare" />
          {this.state.booting && <Boot data={data} brand={brand} />}
        </div>
        <div className="Pda__bottom">
          <div
            className="Pda__homeButton"
            title="Home"
            onClick={() => act('home')} />
        </div>
      </div>
    );
  }
}
