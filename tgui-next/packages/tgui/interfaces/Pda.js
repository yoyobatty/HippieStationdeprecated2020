import { Component, Fragment } from 'inferno';
import { useBackend } from '../backend';
import { Box, Button, Flex, Icon, Input, LabeledList, NoticeBox, Section } from '../components';

// hippie -- the PDA, phone-style
// (hippiestation/.../items/devices/pda_tgui.dm)

const FIELD = {
  'width': '100%',
  'box-sizing': 'border-box',
  'background-color': 'rgba(0, 0, 0, 0.4)',
  'color': '#ffffff',
  'border': '1px solid #404b6e',
  'font-family': 'Verdana, sans-serif',
  'font-size': '12px',
  'padding': '4px',
};

const Badge = props => {
  if (!props.count) {
    return null;
  }
  return (
    <Box
      inline
      ml={0.5}
      px={0.5}
      backgroundColor="bad"
      color="white"
      bold
      style={{ 'border-radius': '8px', 'font-size': '10px' }}>
      {props.count}
    </Box>
  );
};

// The bar along the top of every screen: back, a title, and its buttons
const Header = props => {
  const { act, title, back, buttons } = props;
  return (
    <Flex align="center" mb={1}>
      {!!back && (
        <Flex.Item>
          <Button
            icon="chevron-left"
            color="transparent"
            onClick={() => act('screen', { screen: back })} />
        </Flex.Item>
      )}
      <Flex.Item grow={1} bold fontSize="14px">{title}</Flex.Item>
      {!!buttons && <Flex.Item>{buttons}</Flex.Item>}
    </Flex>
  );
};

const AppTile = props => {
  const { app, act } = props;
  return (
    <Box
      inline
      width="33%"
      p={0.5}
      style={{ 'vertical-align': 'top', 'box-sizing': 'border-box' }}>
      <Button
        fluid
        color={app.on ? 'good' : 'transparent'}
        textAlign="center"
        style={{
          'padding': '8px 2px 4px 2px',
          'white-space': 'normal',
          'line-height': '14px',
        }}
        onClick={() => act('app', { key: app.key })}>
        <Icon name={app.icon} size={2} />
        <Box fontSize="11px" mt={0.5}>
          {app.name}
          <Badge count={app.badge} />
        </Box>
      </Button>
    </Box>
  );
};

const Home = props => {
  const { data, act } = props;
  return (
    <Fragment>
      <Box
        textAlign="center"
        py={2}
        mb={1}
        style={{
          'background': 'linear-gradient(160deg, ' + data.color
            + ', rgba(0, 0, 0, 0.6))',
          'border-radius': '6px',
        }}>
        <Box fontSize="32px" bold>{data.time}</Box>
        <Box color="label">{data.date}</Box>
        <Box mt={1}>{data.owner}</Box>
        <Box color="label" fontSize="11px">{data.job}</Box>
      </Box>
      <Box>
        {(data.apps || []).map(app => (
          <AppTile key={app.key} app={app} act={act} />
        ))}
      </Box>
    </Fragment>
  );
};

const Messenger = props => {
  const { data, act } = props;
  const threads = data.threads || [];
  return (
    <Fragment>
      <Header
        act={act}
        title="Messages"
        back="home"
        buttons={(
          <Fragment>
            <Button
              icon="pen"
              content="New"
              disabled={data.toff}
              onClick={() => act('screen', { screen: 'contacts' })} />
            <Button
              icon="trash"
              color="transparent"
              tooltip="Clear all messages"
              tooltipPosition="left"
              onClick={() => act('clear_all')} />
          </Fragment>
        )} />
      {!!data.toff && (
        <NoticeBox>The messenger is off. Turn it on in Settings.</NoticeBox>
      )}
      {threads.length === 0 && (
        <Box color="label" textAlign="center" mt={2}>No messages yet.</Box>
      )}
      {threads.map(thread => (
        <Box
          key={thread.key}
          className="candystripe"
          p={0.5}
          style={{ 'cursor': 'pointer' }}
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
    </Fragment>
  );
};

class Contacts extends Component {
  constructor() {
    super();
    this.state = { search: '' };
  }

  render() {
    const { data, act } = this.props;
    const query = this.state.search.toLowerCase();
    const contacts = (data.contacts || [])
      .filter(c => !query || c.name.toLowerCase().includes(query));
    const virus = data.virus_charges;
    return (
      <Fragment>
        <Header act={act} title="New message" back="messenger" />
        <Input
          fluid
          placeholder="Search..."
          value={this.state.search}
          onInput={(e, value) => this.setState({ search: value })} />
        {virus !== null && virus !== undefined && (
          <Box color="average" mt={1}>{virus + ' viral files left.'}</Box>
        )}
        <Box mt={1}>
          {!!data.can_send_all && (
            <Button
              fluid
              icon="bullhorn"
              content="Everyone"
              onClick={() => act('new_thread', { everyone: 1 })} />
          )}
          {contacts.length === 0 && (
            <Box color="label">Nobody to message.</Box>
          )}
          {contacts.map(contact => (
            <Flex key={contact.ref} className="candystripe" align="center">
              <Flex.Item grow={1}>
                <Button
                  fluid
                  color="transparent"
                  content={contact.name}
                  onClick={() => act('new_thread', { ref: contact.ref })} />
              </Flex.Item>
              {virus !== null && virus !== undefined && (
                <Flex.Item>
                  <Button
                    icon="bug"
                    content="Send virus"
                    color="bad"
                    disabled={!virus}
                    onClick={() => act('virus', { ref: contact.ref })} />
                </Flex.Item>
              )}
            </Flex>
          ))}
        </Box>
      </Fragment>
    );
  }
}

const Bubble = props => {
  const { message } = props;
  let color = 'rgba(255, 255, 255, 0.1)';
  if (message.out) {
    color = 'rgba(32, 160, 80, 0.45)';
  }
  if (message.page) {
    color = 'rgba(200, 40, 40, 0.45)';
  }
  return (
    <Flex justify={message.out ? 'flex-end' : 'flex-start'} mb={0.5}>
      <Flex.Item
        p={0.5}
        style={{
          'max-width': '80%',
          'background-color': color,
          'border-radius': '8px',
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

class Thread extends Component {
  constructor() {
    super();
    this.state = { text: '' };
  }

  send() {
    const { act } = this.props;
    if (!this.state.text) {
      return;
    }
    act('send', { text: this.state.text });
    this.setState({ text: '' });
  }

  render() {
    const { data, act } = this.props;
    const thread = data.thread;
    let reply = (
      <Box color="label" textAlign="center">
        {data.toff ? 'The messenger is off.' : 'They can\'t be reached now.'}
      </Box>
    );
    if (data.can_reply) {
      reply = (
        <Flex>
          <Flex.Item grow={1}>
            <input
              value={this.state.text}
              placeholder="Message..."
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
    return (
      <Fragment>
        <Header
          act={act}
          title={thread.name}
          back="messenger"
          buttons={(
            <Button
              icon="trash"
              color="transparent"
              tooltip="Delete this conversation"
              tooltipPosition="left"
              onClick={() => act('delete_thread', { key: thread.key })} />
          )} />
        <Box color="label" fontSize="11px" mt={-1} mb={1} ml={3}>
          {thread.job}
        </Box>
        <Box mb={1}>
          {thread.messages.length === 0 && (
            <Box color="label" textAlign="center">Say hello.</Box>
          )}
          {thread.messages.map((message, i) => (
            <Bubble key={i} message={message} />
          ))}
        </Box>
        {reply}
      </Fragment>
    );
  }
}

class Notes extends Component {
  constructor(props) {
    super(props);
    this.state = { text: props.data.note || '', changed: false };
  }

  render() {
    const { data, act } = this.props;
    return (
      <Fragment>
        <Header
          act={act}
          title="Notes"
          back="home"
          buttons={(
            <Button
              icon="save"
              content="Save"
              disabled={!this.state.changed}
              onClick={() => {
                act('save_note', { text: this.state.text });
                this.setState({ changed: false });
              }} />
          )} />
        {!!data.note_scanned && (
          <Box color="label" mb={1}>
            Scanned from paper. Saving it keeps the words, not the layout.
          </Box>
        )}
        <textarea
          value={this.state.text}
          onInput={e => this.setState({
            text: e.target.value,
            changed: true,
          })}
          style={Object.assign({}, FIELD, { 'height': '420px' })} />
      </Fragment>
    );
  }
}

const Atmos = props => {
  const { data, act } = props;
  const atmos = data.atmos;
  let body = <Box color="bad">Unable to obtain a reading.</Box>;
  if (atmos) {
    body = (
      <LabeledList>
        <LabeledList.Item label="Pressure">
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
    );
  }
  return (
    <Fragment>
      <Header act={act} title="Atmospheric Scan" back="home" />
      {body}
    </Fragment>
  );
};

class Settings extends Component {
  constructor(props) {
    super(props);
    this.state = { tone: props.data.ringtone || '' };
  }

  render() {
    const { data, act } = this.props;
    const toggle = what => act('toggle', { what });
    let idButton = (
      <Button
        icon="id-card"
        content="Insert"
        disabled={!data.holding_id}
        onClick={() => act('id')} />
    );
    if (data.id) {
      idButton = (
        <Fragment>
          <Button
            icon="sync"
            content="Update info"
            onClick={() => act('update_info')} />
          <Button
            icon="eject"
            content="Remove"
            onClick={() => act('id')} />
        </Fragment>
      );
    }
    return (
      <Fragment>
        <Header act={act} title="Settings" back="home" />
        <LabeledList>
          <LabeledList.Item label="Ringer">
            <Button
              icon={data.silent ? 'bell-slash' : 'bell'}
              content={data.silent ? 'Off' : 'On'}
              selected={!data.silent}
              onClick={() => toggle('ringer')} />
          </LabeledList.Item>
          <LabeledList.Item label="Ringtone">
            <Input
              width="120px"
              maxLength={20}
              value={this.state.tone}
              onInput={(e, value) => this.setState({ tone: value })} />
            <Button
              content="Set"
              onClick={() => act('ringtone', { text: this.state.tone })} />
          </LabeledList.Item>
          <LabeledList.Item label="Messenger">
            <Button
              icon="comment-dots"
              content={data.toff ? 'Off' : 'On'}
              selected={!data.toff}
              onClick={() => toggle('messenger')} />
          </LabeledList.Item>
          <LabeledList.Item label="Emergency beacon">
            <Button
              icon="heartbeat"
              content={data.beacon ? 'On' : 'Off'}
              selected={data.beacon}
              tooltip="Messages your department if you go down"
              tooltipPosition="left"
              onClick={() => toggle('beacon')} />
          </LabeledList.Item>
          <LabeledList.Item label="Wallpaper">
            <Box
              inline
              width="16px"
              height="16px"
              mr={1}
              backgroundColor={data.color}
              style={{ 'vertical-align': 'middle' }} />
            <Button content="Change" onClick={() => act('color')} />
          </LabeledList.Item>
          <LabeledList.Item label="ID">
            <Box mb={0.5}>{data.id || 'None'}</Box>
            {idButton}
          </LabeledList.Item>
          <LabeledList.Item label="Cartridge">
            <Box mb={0.5}>{data.cartridge || 'None'}</Box>
            {!!data.cartridge && (
              <Button
                icon="eject"
                content="Eject"
                onClick={() => act('eject_cart')} />
            )}
          </LabeledList.Item>
        </LabeledList>
      </Fragment>
    );
  }
}

export const Pda = props => {
  const { act, data } = useBackend(props);
  if (!data.owner) {
    return (
      <Section>
        <NoticeBox>
          No owner information. Swipe an ID card to register it.
        </NoticeBox>
        <Button
          icon="id-card"
          content="Swipe the ID in your hand"
          disabled={!data.holding_id}
          onClick={() => act('register')} />
      </Section>
    );
  }
  let screen = <Home data={data} act={act} />;
  switch (data.screen) {
    case 'messenger':
      screen = <Messenger data={data} act={act} />;
      break;
    case 'contacts':
      screen = <Contacts data={data} act={act} />;
      break;
    case 'thread':
      if (data.thread) {
        screen = <Thread data={data} act={act} />;
      }
      break;
    case 'notes':
      screen = <Notes data={data} act={act} />;
      break;
    case 'atmos':
      screen = <Atmos data={data} act={act} />;
      break;
    case 'settings':
      screen = <Settings data={data} act={act} />;
      break;
  }
  return (
    <Section>
      {screen}
    </Section>
  );
};
