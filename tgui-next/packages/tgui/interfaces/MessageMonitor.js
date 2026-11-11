import { Component, Fragment } from 'inferno';
import { useBackend } from '../backend';
import { Box, Button, Dropdown, Input, LabeledList, NoticeBox, Section, Table, Tabs } from '../components';

// hippie -- the message monitor console
// (hippiestation/.../telecomms/computers/message_tgui.dm)

const SCREEN_LOGS = 1;
const SCREEN_HACKED = 2;
const SCREEN_CUSTOM = 3;
const SCREEN_REQUESTS = 4;

const BINARY = '01000010011100100111010101110100011001010010110'
  + '10110011001101111011100100110001101101001011011100110011'
  + '10010000001100110011011110111001000100000011100110110010'
  + '10111001001110110011001010111001000100000011010110110010';

class Login extends Component {
  constructor() {
    super();
    this.state = { key: '' };
  }

  render() {
    const { act } = this.props;
    return (
      <Box>
        <Input
          width="160px"
          placeholder="Decryption key"
          value={this.state.key}
          onInput={(e, value) => this.setState({ key: value })} />
        <Button
          icon="key"
          content="Log in"
          disabled={!this.state.key}
          onClick={() => {
            act('login', { key: this.state.key });
            this.setState({ key: '' });
          }} />
      </Box>
    );
  }
}

const MessageLogs = props => {
  const { data, act } = props;
  const logs = data.logs || [];
  return (
    <Section
      title={'Messages (' + (data.total || 0) + ')'}
      buttons={(
        <Button
          icon="trash"
          content="Clear all"
          color="bad"
          disabled={!logs.length}
          onClick={() => act('clear_logs')} />
      )}>
      {logs.length === 0 && <Box color="label">No messages logged.</Box>}
      {logs.length > 0 && (
        <Table>
          <Table.Row header>
            <Table.Cell collapsing />
            <Table.Cell>Sender</Table.Cell>
            <Table.Cell>Recipient</Table.Cell>
            <Table.Cell>Message</Table.Cell>
          </Table.Row>
          {logs.map(log => (
            <Table.Row key={log.ref} className="candystripe">
              <Table.Cell collapsing>
                <Button
                  icon="times"
                  color="transparent"
                  onClick={() => act('delete_log', { ref: log.ref })} />
              </Table.Cell>
              <Table.Cell>{log.sender}</Table.Cell>
              <Table.Cell>{log.recipient}</Table.Cell>
              <Table.Cell>
                {log.message}
                {!!log.photo && <Box inline color="label"> (photo)</Box>}
              </Table.Cell>
            </Table.Row>
          ))}
        </Table>
      )}
    </Section>
  );
};

const RequestLogs = props => {
  const { data, act } = props;
  const logs = data.requests || [];
  return (
    <Section
      title={'Requests consoles (' + (data.total || 0) + ')'}
      buttons={(
        <Button
          icon="trash"
          content="Clear all"
          color="bad"
          disabled={!logs.length}
          onClick={() => act('clear_requests')} />
      )}>
      {logs.length === 0 && <Box color="label">No requests logged.</Box>}
      {logs.length > 0 && (
        <Table>
          <Table.Row header>
            <Table.Cell collapsing />
            <Table.Cell>From</Table.Cell>
            <Table.Cell>To</Table.Cell>
            <Table.Cell>Message</Table.Cell>
            <Table.Cell>Stamp</Table.Cell>
            <Table.Cell>ID</Table.Cell>
            <Table.Cell>Priority</Table.Cell>
          </Table.Row>
          {logs.map(log => (
            <Table.Row key={log.ref} className="candystripe">
              <Table.Cell collapsing>
                <Button
                  icon="times"
                  color="transparent"
                  onClick={() => act('delete_request', { ref: log.ref })} />
              </Table.Cell>
              <Table.Cell>{log.from}</Table.Cell>
              <Table.Cell>{log.to}</Table.Cell>
              <Table.Cell>{log.message}</Table.Cell>
              <Table.Cell>{log.stamp}</Table.Cell>
              <Table.Cell>{log.id_auth}</Table.Cell>
              <Table.Cell>{log.priority}</Table.Cell>
            </Table.Row>
          ))}
        </Table>
      )}
    </Section>
  );
};

const CustomMessage = props => {
  const { data, act } = props;
  const custom = data.custom || {};
  const pdas = data.pdas || [];
  const set = (field, value) => act('custom', { field, value });
  const names = pdas.map(p => p.name);
  return (
    <Section
      title="Send a message as anybody"
      buttons={(
        <Button
          icon="undo"
          content="Reset"
          onClick={() => act('custom_reset')} />
      )}>
      <LabeledList>
        <LabeledList.Item label="Sender">
          <Input
            fluid
            value={custom.sender}
            onChange={(e, value) => set('sender', value)} />
        </LabeledList.Item>
        <LabeledList.Item label="Sender's job">
          <Input
            fluid
            value={custom.job}
            onChange={(e, value) => set('job', value)} />
        </LabeledList.Item>
        <LabeledList.Item label="Recipient">
          <Dropdown
            key={custom.recipient || 'none'}
            width="100%"
            over
            options={names}
            selected={custom.recipient || 'Choose a PDA...'}
            onSelected={name => {
              const pda = pdas.find(p => p.name === name);
              if (pda) {
                set('recipient', pda.ref);
              }
            }} />
        </LabeledList.Item>
        <LabeledList.Item label="Message">
          <Input
            fluid
            value={custom.message}
            onChange={(e, value) => set('message', value)} />
        </LabeledList.Item>
      </LabeledList>
      <Box mt={1}>
        <Button
          icon="paper-plane"
          content="Send"
          disabled={!custom.recipient}
          onClick={() => act('custom_send')} />
      </Box>
      <Box mt={1} color="average">
        Reg. #5a0e39 forbids sending messages to a Head of Staff containing
        Erotic Rendering Properties.
      </Box>
    </Section>
  );
};

class KeyChange extends Component {
  constructor() {
    super();
    this.state = { old: '', next: '' };
  }

  render() {
    const { act } = this.props;
    return (
      <Section title="Change the decryption key">
        <LabeledList>
          <LabeledList.Item label="Current key">
            <Input
              value={this.state.old}
              onInput={(e, value) => this.setState({ old: value })} />
          </LabeledList.Item>
          <LabeledList.Item label="New key">
            <Input
              value={this.state.next}
              placeholder="4 to 16 characters"
              onInput={(e, value) => this.setState({ next: value })} />
          </LabeledList.Item>
        </LabeledList>
        <Box mt={1}>
          <Button
            icon="key"
            content="Set key"
            disabled={!this.state.old || !this.state.next}
            onClick={() => {
              act('set_key', { old: this.state.old, new: this.state.next });
              this.setState({ old: '', next: '' });
            }} />
        </Box>
      </Section>
    );
  }
}

export const MessageMonitor = props => {
  const { act, data } = useBackend(props);
  if (data.hacked || data.screen === SCREEN_HACKED) {
    let text = (
      <Box style={{ 'word-break': 'break-all' }}>
        {BINARY + BINARY + BINARY}
      </Box>
    );
    if (data.silicon) {
      text = (
        <Box>
          Brute-forcing for the server key. It takes 20 seconds for every
          character the key has. In the meantime this console can show your
          true intentions to anybody who uses it: make sure no humans come in.
        </Box>
      );
    }
    return (
      <Section>
        <NoticeBox>{data.notice}</NoticeBox>
        {text}
      </Section>
    );
  }
  let loginBox = <Login act={act} />;
  if (data.auth) {
    loginBox = (
      <Button
        icon="sign-out-alt"
        content="Log out"
        onClick={() => act('logout')} />
    );
  }
  let body = null;
  if (data.auth && !data.server_down) {
    let tab = null;
    if (data.screen === SCREEN_LOGS) {
      tab = <MessageLogs data={data} act={act} />;
    }
    else if (data.screen === SCREEN_REQUESTS) {
      tab = <RequestLogs data={data} act={act} />;
    }
    else if (data.screen === SCREEN_CUSTOM) {
      tab = <CustomMessage data={data} act={act} />;
    }
    else {
      tab = <KeyChange act={act} />;
    }
    const tabs = [
      ['logs', 'Messages', 'envelope', SCREEN_LOGS],
      ['requests', 'Requests consoles', 'clipboard-list', SCREEN_REQUESTS],
      ['custom', 'Send a message', 'paper-plane', SCREEN_CUSTOM],
      ['main', 'Key', 'key', 0],
    ];
    const active = tabs.find(t => t[3] === data.screen) || tabs[3];
    body = (
      <Tabs activeTab={active[0]}>
        {tabs.map(([key, label, icon]) => (
          <Tabs.Tab
            key={key}
            icon={icon}
            label={label}
            onClick={() => act('tab', { tab: key })}>
            {tab}
          </Tabs.Tab>
        ))}
      </Tabs>
    );
  }
  else if (!data.server_down) {
    body = (
      <NoticeBox>
        Log in with the server&apos;s decryption key to see its logs.
      </NoticeBox>
    );
  }
  return (
    <Fragment>
      <Section>
        <LabeledList>
          <LabeledList.Item
            label="Server"
            buttons={(
              <Button
                icon="link"
                content="Link to a server"
                onClick={() => act('link')} />
            )}>
            {data.server || 'None'}
            {!!data.server && data.server_down && (
              <Box inline ml={1} color="bad">(not responding)</Box>
            )}
          </LabeledList.Item>
          <LabeledList.Item label="Power">
            <Button
              icon="power-off"
              content={data.server_on ? 'On' : 'Off'}
              selected={data.server_on}
              disabled={!data.auth || data.server_down}
              onClick={() => act('power')} />
          </LabeledList.Item>
          <LabeledList.Item label="Access">
            {loginBox}
          </LabeledList.Item>
          {!!data.can_hack && (
            <LabeledList.Item label="Hack">
              <Button
                icon="user-secret"
                content="Brute-force the key"
                color="bad"
                onClick={() => act('hack')} />
            </LabeledList.Item>
          )}
        </LabeledList>
        {!!data.notice && <Box mt={1} color="label">{data.notice}</Box>}
      </Section>
      {body}
    </Fragment>
  );
};
