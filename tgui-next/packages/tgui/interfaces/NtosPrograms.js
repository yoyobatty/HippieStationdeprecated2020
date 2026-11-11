import { Component, Fragment } from 'inferno';
import { useBackend } from '../backend';
import { Box, Button, Flex, Input, LabeledList, NoticeBox, ProgressBar, Section, Table } from '../components';

// hippie -- laptop and tablet programs on the tgui-next look (were
// tgui/src/interfaces/ntos_*.ract and synd_contract.ract). What they type goes
// in the window (hippiestation/code/modules/modular_computers/ntos_tgui.dm).

// The file viewer shows a file's own markup, as the old window did
const Html = props => {
  const { html, ...rest } = props;
  // eslint-disable-next-line react/no-danger
  return <Box {...rest} dangerouslySetInnerHTML={{ __html: html }} />;
};

const OnOff = props => (
  <Box inline bold color={props.on ? 'good' : 'bad'}>
    {props.on ? 'ENABLED' : 'DISABLED'}
  </Box>
);

export const NtosConfiguration = props => {
  const { act, data } = useBackend(props);
  const {
    power_usage,
    battery,
    disk_size,
    disk_used,
    hardware = [],
  } = data;
  return (
    <Fragment>
      <Section title="Power supply">
        <LabeledList>
          <LabeledList.Item label="Drawing">
            {power_usage} W
          </LabeledList.Item>
          <LabeledList.Item label="Battery">
            {!battery && (
              <Box color="label">None fitted</Box>
            ) || (
              <ProgressBar
                value={battery.charge / battery.max}
                ranges={{
                  good: [0.5, Infinity],
                  average: [0.25, 0.5],
                  bad: [-Infinity, 0.25],
                }}>
                {Math.round(battery.charge)} / {battery.max}
              </ProgressBar>
            )}
          </LabeledList.Item>
          <LabeledList.Item label="Disk">
            <ProgressBar value={disk_used / disk_size} color="good">
              {disk_used} / {disk_size} GQ
            </ProgressBar>
          </LabeledList.Item>
        </LabeledList>
      </Section>
      <Section title="Components">
        {hardware.map(part => (
          <Section
            key={part.name}
            level={2}
            title={part.name}
            buttons={(
              <Fragment>
                {!!part.powerusage && (
                  <Box inline color="label" mr={1}>
                    {part.powerusage} W
                  </Box>
                )}
                <Button.Checkbox
                  checked={part.enabled}
                  disabled={part.critical}
                  content={part.enabled ? 'On' : 'Off'}
                  tooltip={part.critical ? 'The computer needs this' : null}
                  onClick={() => act('PC_toggle_component', {
                    name: part.name,
                  })} />
              </Fragment>
            )}>
            <Box color="label">{part.desc}</Box>
          </Section>
        ))}
      </Section>
    </Fragment>
  );
};

const FileTable = props => {
  const { files = [], actions } = props;
  if (!files.length) {
    return <Box color="label">No files.</Box>;
  }
  return (
    <Table>
      <Table.Row header>
        <Table.Cell>File</Table.Cell>
        <Table.Cell collapsing textAlign="right">Size</Table.Cell>
        <Table.Cell collapsing />
      </Table.Row>
      {files.map(file => (
        <Table.Row key={file.name}>
          <Table.Cell>
            {file.name}
            <Box inline color="label">.{file.type}</Box>
          </Table.Cell>
          <Table.Cell collapsing textAlign="right" color="label">
            {file.size} GQ
          </Table.Cell>
          <Table.Cell collapsing pl={1}>
            {actions(file)}
          </Table.Cell>
        </Table.Row>
      ))}
    </Table>
  );
};

export const NtosFileManager = props => {
  const { act, data } = useBackend(props);
  const {
    error,
    filename,
    filedata,
    files,
    usbconnected,
    usbfiles,
  } = data;
  if (error) {
    return (
      <Section title="Something went wrong">
        <Box mb={1}>{error}</Box>
        <Button
          icon="redo"
          content="Restart program"
          onClick={() => act('PRG_closefile')} />
      </Section>
    );
  }
  if (filename) {
    return (
      <Section
        title={filename}
        buttons={(
          <Fragment>
            <Button
              icon="pen"
              content="Edit"
              onClick={() => act('PRG_edit')} />
            <Button
              icon="print"
              content="Print"
              onClick={() => act('PRG_printfile')} />
            <Button
              icon="times"
              content="Close"
              onClick={() => act('PRG_closefile')} />
          </Fragment>
        )}>
        <Html html={filedata} />
      </Section>
    );
  }
  return (
    <Fragment>
      <Section
        title="This computer"
        buttons={(
          <Button
            icon="file"
            content="New file"
            onClick={() => act('PRG_newtextfile')} />
        )}>
        <FileTable
          files={files}
          actions={file => (
            <Fragment>
              <Button
                icon="eye"
                tooltip="Open"
                onClick={() => act('PRG_openfile', { name: file.name })} />
              <Button
                icon="i-cursor"
                tooltip="Rename"
                disabled={file.undeletable}
                onClick={() => act('PRG_rename', { name: file.name })} />
              <Button
                icon="copy"
                tooltip="Copy"
                disabled={file.undeletable}
                onClick={() => act('PRG_clone', { name: file.name })} />
              {!!usbconnected && (
                <Button
                  icon="sign-out-alt"
                  tooltip="Copy to the portable drive"
                  disabled={file.undeletable}
                  onClick={() => act('PRG_copytousb', { name: file.name })} />
              )}
              <Button
                icon="trash"
                color="bad"
                tooltip="Delete"
                disabled={file.undeletable}
                onClick={() => act('PRG_deletefile', { name: file.name })} />
            </Fragment>
          )} />
      </Section>
      {!!usbconnected && (
        <Section title="Portable drive">
          <FileTable
            files={usbfiles}
            actions={file => (
              <Fragment>
                <Button
                  icon="sign-in-alt"
                  tooltip="Copy to this computer"
                  disabled={file.undeletable}
                  onClick={() => act('PRG_copyfromusb', { name: file.name })} />
                <Button
                  icon="trash"
                  color="bad"
                  tooltip="Delete"
                  disabled={file.undeletable}
                  onClick={() => act('PRG_usbdeletefile', {
                    name: file.name,
                  })} />
              </Fragment>
            )} />
        </Section>
      )}
    </Fragment>
  );
};

export class NtosNetChat extends Component {
  constructor() {
    super();
    this.state = { message: '' };
  }

  render() {
    const { act, data } = useBackend(this.props);
    const { message } = this.state;
    const {
      adminmode,
      title,
      username,
      is_operator,
      messages = [],
      clients = [],
      all_channels = [],
    } = data;
    const send = () => {
      if (message) {
        act('PRG_speak', { text: message });
        this.setState({ message: '' });
      }
    };
    const nick = (
      <LabeledList.Item label="Nickname">
        <Input
          value={username}
          onChange={(e, value) => act('PRG_changename', { text: value })} />
      </LabeledList.Item>
    );
    const admin = (
      <Button.Checkbox
        checked={adminmode}
        color={adminmode ? 'bad' : null}
        content="Administrator mode"
        onClick={() => act('PRG_toggleadmin')} />
    );
    if (!title) {
      return (
        <Fragment>
          <Section title="NTNet Relay Chat" buttons={admin}>
            <LabeledList>{nick}</LabeledList>
          </Section>
          <Section
            title="Channels"
            buttons={(
              <Button
                icon="plus"
                content="New channel"
                onClick={() => act('PRG_newchannel')} />
            )}>
            {all_channels.length === 0 && (
              <Box color="label">No channels yet.</Box>
            )}
            {all_channels.map(channel => (
              <Button
                key={channel.id}
                fluid
                icon="hashtag"
                content={channel.chan}
                onClick={() => act('PRG_joinchannel', { id: channel.id })} />
            ))}
          </Section>
        </Fragment>
      );
    }
    return (
      <Fragment>
        {!!adminmode && (
          <NoticeBox>Administrator mode</NoticeBox>
        )}
        <Section
          title={'#' + title}
          buttons={(
            <Fragment>
              <Button
                icon="save"
                tooltip="Save the log to this computer"
                onClick={() => act('PRG_savelog')} />
              <Button
                icon="sign-out-alt"
                content="Leave"
                onClick={() => act('PRG_leavechannel')} />
            </Fragment>
          )}>
          <Flex>
            <Flex.Item grow={1}>
              <Box
                height="260px"
                p={0.5}
                style={{
                  'overflow-y': 'auto',
                  'background-color': 'rgba(0, 0, 0, 0.3)',
                  'font-family': 'monospace',
                }}>
                {messages.map((line, i) => (
                  <Box key={i}>{line.msg}</Box>
                ))}
              </Box>
            </Flex.Item>
            <Flex.Item ml={1}>
              <Box width="120px">
                <Box color="label" mb={0.5}>Here</Box>
                {clients.map((client, i) => (
                  <Box key={i} color={client.name === username ? 'good' : null}>
                    {client.name}
                  </Box>
                ))}
              </Box>
            </Flex.Item>
          </Flex>
          <Flex mt={1}>
            <Flex.Item grow={1}>
              <Box onKeyDown={e => e.keyCode === 13 && send()}>
                <Input
                  fluid
                  placeholder="Say something..."
                  value={message}
                  onInput={(e, value) => this.setState({ message: value })} />
              </Box>
            </Flex.Item>
            <Flex.Item ml={1}>
              <Button
                icon="paper-plane"
                disabled={!message}
                content="Send"
                onClick={() => send()} />
            </Flex.Item>
          </Flex>
        </Section>
        <Section title="Settings" buttons={admin}>
          <LabeledList>
            {nick}
            {!!is_operator && (
              <LabeledList.Item label="Channel">
                <Button
                  icon="pen"
                  content="Rename"
                  onClick={() => act('PRG_renamechannel')} />
                <Button
                  icon="key"
                  content="Password"
                  onClick={() => act('PRG_setpassword')} />
                <Button
                  icon="trash"
                  color="bad"
                  content="Delete"
                  onClick={() => act('PRG_deletechannel')} />
              </LabeledList.Item>
            )}
          </LabeledList>
        </Section>
      </Fragment>
    );
  }
}

export const NtosNetMonitor = props => {
  const { act, data } = useBackend(props);
  const {
    ntnetrelays,
    ntnetstatus,
    config_softwaredownload,
    config_peertopeer,
    config_communication,
    config_systemcontrol,
    idsalarm,
    idsstatus,
    ntnetmaxlogs,
    ntnetlogs = [],
  } = data;
  const firewall = [
    ['Software downloads', config_softwaredownload, 1],
    ['Peer to peer traffic', config_peertopeer, 2],
    ['Communication systems', config_communication, 3],
    ['Remote system control', config_systemcontrol, 4],
  ];
  return (
    <Fragment>
      <Section
        title="Wireless"
        buttons={!!ntnetrelays && (
          <Button
            icon="power-off"
            selected={ntnetstatus}
            content={ntnetstatus ? 'On' : 'Off'}
            onClick={() => act('toggleWireless')} />
        )}>
        <LabeledList>
          <LabeledList.Item label="Relays">
            {ntnetrelays}
          </LabeledList.Item>
          {!!ntnetrelays && (
            <LabeledList.Item label="Status">
              <OnOff on={ntnetstatus} />
            </LabeledList.Item>
          )}
        </LabeledList>
        <Box color={ntnetrelays ? 'label' : 'bad'} mt={1}>
          {ntnetrelays
            ? 'Warning: wireless device.'
            : 'No relays connected.'}
        </Box>
      </Section>
      <Section title="Firewall">
        <LabeledList>
          {firewall.map(rule => (
            <LabeledList.Item
              key={rule[2]}
              label={rule[0]}
              buttons={(
                <Button
                  icon="power-off"
                  selected={rule[1]}
                  content={rule[1] ? 'On' : 'Off'}
                  onClick={() => act('toggle_function', { id: rule[2] })} />
              )}>
              <OnOff on={rule[1]} />
            </LabeledList.Item>
          ))}
        </LabeledList>
      </Section>
      <Section title="Security">
        {!!idsalarm && (
          <NoticeBox>
            NETWORK INCURSION DETECTED: check the logs.
          </NoticeBox>
        )}
        <LabeledList>
          <LabeledList.Item
            label="Intrusion detection"
            buttons={(
              <Fragment>
                <Button
                  icon="power-off"
                  selected={idsstatus}
                  content={idsstatus ? 'On' : 'Off'}
                  onClick={() => act('toggleIDS')} />
                <Button
                  icon="sync"
                  content="Reset"
                  onClick={() => act('resetIDS')} />
              </Fragment>
            )}>
            <OnOff on={idsstatus} />
          </LabeledList.Item>
          <LabeledList.Item
            label="Log limit"
            buttons={(
              <Button
                icon="pen"
                content="Set"
                onClick={() => act('updatemaxlogs')} />
            )}>
            {ntnetmaxlogs}
          </LabeledList.Item>
        </LabeledList>
      </Section>
      <Section
        title="Logs"
        buttons={(
          <Button
            icon="trash"
            content="Purge"
            onClick={() => act('purgelogs')} />
        )}>
        <Box
          p={0.5}
          style={{
            'max-height': '200px',
            'overflow-y': 'auto',
            'background-color': 'rgba(0, 0, 0, 0.3)',
            'font-family': 'monospace',
          }}>
          {ntnetlogs.length === 0 && (
            <Box color="label">Empty.</Box>
          )}
          {ntnetlogs.map((log, i) => (
            <Box key={i}>{log.entry}</Box>
          ))}
        </Box>
      </Section>
    </Fragment>
  );
};

export const NtosNetTransfer = props => {
  const { act, data } = useBackend(props);
  const {
    error,
    downloading,
    download_name,
    download_progress,
    download_size,
    download_netspeed,
    uploading,
    upload_clients,
    upload_filename,
    upload_haspassword,
    upload_filelist,
    servers = [],
  } = data;
  if (error) {
    return (
      <Section title="Something went wrong">
        <Box mb={1}>{error}</Box>
        <Button
          icon="times"
          content="Clear"
          onClick={() => act('PRG_reset')} />
      </Section>
    );
  }
  if (downloading) {
    return (
      <Section
        title={'Downloading ' + download_name}
        buttons={(
          <Button
            icon="times"
            content="Abort"
            onClick={() => act('PRG_reset')} />
        )}>
        <ProgressBar value={download_progress / download_size} color="good">
          {download_progress} / {download_size} GQ
        </ProgressBar>
        <Box color="label" mt={1}>
          {download_netspeed} GQ/s
        </Box>
      </Section>
    );
  }
  if (uploading) {
    return (
      <Section
        title={'Sharing ' + upload_filename}
        buttons={(
          <Fragment>
            <Button
              icon="key"
              content="Password"
              onClick={() => act('PRG_setpassword')} />
            <Button
              icon="times"
              content="Stop"
              onClick={() => act('PRG_reset')} />
          </Fragment>
        )}>
        <LabeledList>
          <LabeledList.Item label="Connected">
            {upload_clients}
          </LabeledList.Item>
          <LabeledList.Item label="Password">
            <OnOff on={upload_haspassword} />
          </LabeledList.Item>
        </LabeledList>
      </Section>
    );
  }
  if (upload_filelist) {
    return (
      <Section
        title="Pick a file to share"
        buttons={(
          <Fragment>
            <Button
              icon="key"
              content="Password"
              onClick={() => act('PRG_setpassword')} />
            <Button
              icon="arrow-left"
              content="Back"
              onClick={() => act('PRG_reset')} />
          </Fragment>
        )}>
        <Table>
          {upload_filelist.map(file => (
            <Table.Row key={file.uid}>
              <Table.Cell>{file.filename}</Table.Cell>
              <Table.Cell collapsing color="label">{file.size} GQ</Table.Cell>
              <Table.Cell collapsing pl={1}>
                <Button
                  icon="upload"
                  content="Share"
                  onClick={() => act('PRG_uploadfile', { id: file.uid })} />
              </Table.Cell>
            </Table.Row>
          ))}
        </Table>
      </Section>
    );
  }
  return (
    <Section
      title="Files shared on NTNet"
      buttons={(
        <Button
          icon="upload"
          content="Share a file"
          onClick={() => act('PRG_uploadmenu')} />
      )}>
      {servers.length === 0 && (
        <Box color="label">Nobody is sharing anything.</Box>
      )}
      <Table>
        {servers.map(server => (
          <Table.Row key={server.uid}>
            <Table.Cell>
              {server.filename}
              <Box inline color="label" ml={1}>#{server.uid}</Box>
            </Table.Cell>
            <Table.Cell collapsing color="label">{server.size} GQ</Table.Cell>
            <Table.Cell collapsing>
              {!!server.haspassword && (
                <Box inline color="average" mx={1}>locked</Box>
              )}
            </Table.Cell>
            <Table.Cell collapsing>
              <Button
                icon="download"
                content="Download"
                onClick={() => act('PRG_downloadfile', { id: server.uid })} />
            </Table.Cell>
          </Table.Row>
        ))}
      </Table>
    </Section>
  );
};

export const NtosNetDos = props => {
  const { act, data } = useBackend(props);
  const {
    error,
    target,
    speed,
    dos_strings = [],
    focus,
    relays = [],
  } = data;
  if (error) {
    return (
      <Section title="System error">
        <Box color="bad" mb={1}>{error}</Box>
        <Button
          icon="redo"
          content="Reset"
          onClick={() => act('PRG_reset')} />
      </Section>
    );
  }
  if (target) {
    return (
      <Section
        title={'Flooding at ' + speed + ' GQ/s'}
        buttons={(
          <Button
            icon="stop"
            color="bad"
            content="Abort"
            onClick={() => act('PRG_reset')} />
        )}>
        <Box style={{ 'font-family': 'monospace' }} color="good">
          {dos_strings.map((line, i) => (
            <Box key={i}>{line.nums}</Box>
          ))}
        </Box>
      </Section>
    );
  }
  return (
    <Section
      title="DoS traffic generator"
      buttons={(
        <Button
          icon="bolt"
          color="bad"
          disabled={!focus}
          content="Execute"
          onClick={() => act('PRG_execute')} />
      )}>
      <Box color="label" mb={1}>
        Target: {focus || 'pick a relay'}
      </Box>
      {relays.length === 0 && (
        <Box color="label">No relays on the network.</Box>
      )}
      {relays.map(relay => (
        <Button
          key={relay.id}
          icon="server"
          selected={focus === relay.id}
          content={relay.id}
          onClick={() => act('PRG_target_relay', { targid: relay.id })} />
      ))}
    </Section>
  );
};

export const NtosRevelation = props => {
  const { act, data } = useBackend(props);
  return (
    <Section title="Payload">
      <Box
        textAlign="center"
        fontSize="20px"
        bold
        mb={1}
        color={data.armed ? 'bad' : 'label'}>
        {data.armed ? 'ARMED' : 'DISARMED'}
      </Box>
      <Button
        fluid
        icon="user-secret"
        textAlign="center"
        content="Disguise the program's name"
        onClick={() => act('PRG_obfuscate')} />
      <Button
        fluid
        icon={data.armed ? 'lock-open' : 'lock'}
        textAlign="center"
        selected={data.armed}
        content={data.armed ? 'Disarm' : 'Arm'}
        onClick={() => act('PRG_arm')} />
      <Button
        fluid
        icon="radiation"
        color="bad"
        textAlign="center"
        disabled={!data.armed}
        content="ACTIVATE"
        onClick={() => act('PRG_activate')} />
    </Section>
  );
};

// Contract statuses (CONTRACT_STATUS_* in code/__DEFINES/antagonists.dm): with
// a contract going, the one that's active, at the bounty console or extracting
// (2-4) shows; otherwise every one not complete or aborted (5, 6) is offered
export const SyndContract = props => {
  const { act, data } = useBackend(props);
  const {
    logged_in,
    error,
    station_name,
    redeemable_tc,
    ongoing_contract,
    extraction_enroute,
    contracts = [],
    current_location,
    dropoff_direction,
  } = data;
  if (!logged_in) {
    return (
      <Section title="Syndicate contract uplink">
        <Button
          fluid
          icon="user-secret"
          textAlign="center"
          content="Assign"
          onClick={() => act('PRG_login')} />
        {!!error && (
          <Box color="bad" mt={1}>{error}</Box>
        )}
      </Section>
    );
  }
  const shown = contracts.filter(contract => (ongoing_contract
    ? contract.status >= 2 && contract.status <= 4
    : contract.status !== 5 && contract.status !== 6));
  return (
    <Fragment>
      <Section title={'Welcome, Agent. Onboard ' + station_name + '.'}>
        <Box color="label" mb={1}>
          Bring a target to their drop-off, alive for the bonus, and call for
          extraction here. Payment is in telecrystals, collected below.
        </Box>
        <LabeledList>
          <LabeledList.Item
            label="Telecrystals"
            buttons={(
              <Button
                icon="coins"
                disabled={!redeemable_tc}
                content="Collect"
                onClick={() => act('PRG_redeem_TC')} />
            )}>
            {redeemable_tc} TC to collect
          </LabeledList.Item>
        </LabeledList>
      </Section>
      <Section
        title="Contracts"
        buttons={!!ongoing_contract && (
          <Button
            icon="parachute-box"
            color="good"
            disabled={extraction_enroute}
            content="Call extraction"
            onClick={() => act('PRG_call_extraction')} />
        )}>
        <Table>
          <Table.Row header>
            <Table.Cell>Target</Table.Cell>
            <Table.Cell>Payment</Table.Cell>
            <Table.Cell>Drop-off</Table.Cell>
            <Table.Cell collapsing />
          </Table.Row>
          {shown.map(contract => (
            <Table.Row key={contract.id}>
              <Table.Cell>{contract.target}</Table.Cell>
              <Table.Cell>
                {contract.payout}
                <Box inline color="good">
                  {' '}(+{contract.payout_bonus})
                </Box>
                {' TC'}
              </Table.Cell>
              <Table.Cell>{contract.dropoff}</Table.Cell>
              <Table.Cell collapsing>
                {ongoing_contract && (
                  <Button
                    icon="times"
                    disabled={extraction_enroute}
                    content="Cancel"
                    onClick={() => act('PRG_contract_abort', {
                      contract_id: contract.id,
                    })} />
                ) || (
                  <Button
                    icon="check"
                    content="Accept"
                    onClick={() => act('PRG_contract-accept', {
                      contract_id: contract.id,
                    })} />
                )}
              </Table.Cell>
            </Table.Row>
          ))}
        </Table>
      </Section>
      {!!ongoing_contract && (
        <Section title="Drop-off locator">
          <LabeledList>
            <LabeledList.Item label="You are">
              {current_location}
            </LabeledList.Item>
            <LabeledList.Item label="Drop-off">
              {dropoff_direction}
            </LabeledList.Item>
          </LabeledList>
        </Section>
      )}
    </Fragment>
  );
};

export const NtnetRelay = props => {
  const { act, data } = useBackend(props);
  const { enabled, dos_capacity, dos_overload, dos_crashed } = data;
  if (dos_crashed) {
    return (
      <Section title="NETWORK BUFFERS OVERLOADED">
        <Box color="bad" mb={1}>
          Overload recovery mode: until the buffered traffic is processed,
          all further requests are dropped. Frequent overloads mean the
          network needs more capacity.
        </Box>
        <Button
          icon="signal"
          color="bad"
          content="Purge buffered traffic (data may be lost)"
          onClick={() => act('restart')} />
      </Section>
    );
  }
  return (
    <Section
      title="Relay"
      buttons={(
        <Button
          icon="power-off"
          selected={enabled}
          content={enabled ? 'Enabled' : 'Disabled'}
          onClick={() => act('toggle')} />
      )}>
      <LabeledList>
        <LabeledList.Item label="Buffer">
          <ProgressBar
            value={dos_overload / dos_capacity}
            ranges={{
              bad: [0.75, Infinity],
              average: [0.4, 0.75],
              good: [-Infinity, 0.4],
            }}>
            {dos_overload} / {dos_capacity} GQ
          </ProgressBar>
        </LabeledList.Item>
      </LabeledList>
    </Section>
  );
};
