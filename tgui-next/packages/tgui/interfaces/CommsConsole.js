import { Component, Fragment } from 'inferno';
import { useBackend } from '../backend';
import { Box, Button, Collapsible, Input, LabeledList, NoticeBox, Section } from '../components';

// hippie -- the communications console (hippiestation/.../computer/
// communications_tgui.dm)

const SHUTTLE_TEXT = {
  idle: 'At CentCom',
  called: 'On its way',
  recalled: 'Recalled',
  docked: 'Docked at the station',
  igniting: 'Engines igniting',
  escaping: 'On its way back to CentCom',
  stranded: 'Stranded',
  disabled: 'Disabled by CentCom',
};

const formatTime = seconds => {
  const mins = Math.floor(seconds / 60);
  const secs = seconds % 60;
  return mins + ':' + (secs < 10 ? '0' : '') + secs;
};

// A button that asks once more before it acts
class ConfirmButton extends Component {
  constructor() {
    super();
    this.state = {
      asking: false,
    };
  }

  render() {
    const { content, confirm, icon, color, disabled, onClick } = this.props;
    const { asking } = this.state;
    if (asking) {
      return (
        <Fragment>
          <Button
            icon="check"
            color="bad"
            content={confirm || 'Confirm'}
            onClick={() => {
              this.setState({ asking: false });
              onClick();
            }} />
          <Button
            icon="times"
            content="Cancel"
            onClick={() => this.setState({ asking: false })} />
        </Fragment>
      );
    }
    return (
      <Button
        icon={icon}
        color={color}
        content={content}
        disabled={disabled}
        onClick={() => this.setState({ asking: true })} />
    );
  }
}

// A one-line text box and its send button, emptied once sent
class SendBox extends Component {
  constructor() {
    super();
    this.state = {
      text: '',
    };
  }

  render() {
    const { placeholder, button, icon, disabled, tooltip, onSend } = this.props;
    const { text } = this.state;
    return (
      <Box style={{ 'display': 'flex' }}>
        <Input
          fluid
          style={{ 'flex-grow': 1 }}
          placeholder={placeholder}
          value={text}
          onInput={(e, value) => this.setState({ text: value })} />
        <Button
          ml={0.5}
          icon={icon || 'paper-plane'}
          content={button}
          disabled={disabled || !text.trim()}
          tooltip={tooltip}
          tooltipPosition="left"
          onClick={() => {
            onSend(text);
            this.setState({ text: '' });
          }} />
      </Box>
    );
  }
}

class ShuttleSection extends Component {
  constructor() {
    super();
    this.state = {
      reason: '',
    };
  }

  render() {
    const { data, act, canUse } = this.props;
    const { reason } = this.state;
    const { shuttle } = data;
    const length = reason.trim().length;
    // A reason's only needed above green (requestEvac())
    const needReason = data.alert_num !== data.levels.green;
    const reasonOk = (!needReason || length >= data.reason_min)
      && length <= data.reason_max;
    return (
      <Section title="Emergency shuttle">
        <LabeledList>
          <LabeledList.Item label="Status">
            {SHUTTLE_TEXT[shuttle.mode] || shuttle.mode}
            {shuttle.eta !== null && shuttle.eta !== undefined && (
              <Box inline ml={1} bold>
                {formatTime(shuttle.eta)}
              </Box>
            )}
          </LabeledList.Item>
          {!!shuttle.trace && (
            <LabeledList.Item label="Last call traced to">
              {shuttle.trace}
            </LabeledList.Item>
          )}
        </LabeledList>
        {!!shuttle.can_call && (
          <Box mt={1} style={{ 'display': 'flex' }}>
            <Input
              style={{ 'flex-grow': 1 }}
              placeholder={needReason
                ? 'The nature of the emergency (' + data.reason_min
                  + ' to ' + data.reason_max + ' characters)'
                : 'The nature of the emergency'}
              value={reason}
              onInput={(e, value) => this.setState({ reason: value })} />
            <ConfirmButton
              icon="space-shuttle"
              color="bad"
              content="Call the shuttle"
              confirm="Call it"
              disabled={!canUse || !reasonOk}
              onClick={() => {
                act('call_shuttle', { reason });
                this.setState({ reason: '' });
              }} />
          </Box>
        )}
        {!!shuttle.can_recall && (
          <Box mt={1}>
            <ConfirmButton
              icon="undo"
              content="Recall the shuttle"
              confirm="Recall it"
              disabled={!canUse}
              onClick={() => act('recall_shuttle')} />
          </Box>
        )}
      </Section>
    );
  }
}

class StatusSection extends Component {
  constructor() {
    super();
    this.state = {
      line1: null,
      line2: null,
    };
  }

  render() {
    const { data, act } = this.props;
    const line1 = this.state.line1 === null
      ? (data.stat_msg1 || '')
      : this.state.line1;
    const line2 = this.state.line2 === null
      ? (data.stat_msg2 || '')
      : this.state.line2;
    const pictures = [
      ['default', 'None'],
      ['redalert', 'Red alert'],
      ['lockdown', 'Lockdown'],
      ['biohazard', 'Biohazard'],
    ];
    return (
      <Section title="Status displays">
        <Box mb={1}>
          <Button
            icon="eraser"
            content="Clear"
            onClick={() => act('status', { display: 'blank' })} />
          <Button
            icon="clock"
            content="Shuttle ETA"
            onClick={() => act('status', { display: 'shuttle' })} />
          <Box inline ml={1} color="label">Picture:</Box>
          {pictures.map(entry => (
            <Button
              key={entry[0]}
              content={entry[1]}
              onClick={() => act('status', {
                display: 'alert',
                picture: entry[0],
              })} />
          ))}
        </Box>
        <Box style={{ 'display': 'flex' }}>
          <Input
            style={{ 'flex-grow': 1 }}
            placeholder="Line 1"
            maxLength={40}
            value={line1}
            onInput={(e, value) => this.setState({ line1: value })} />
          <Input
            ml={0.5}
            style={{ 'flex-grow': 1 }}
            placeholder="Line 2"
            maxLength={40}
            value={line2}
            onInput={(e, value) => this.setState({ line2: value })} />
          <Button
            ml={0.5}
            icon="tv"
            content="Show"
            onClick={() => act('status', {
              display: 'message',
              line1,
              line2,
            })} />
        </Box>
      </Section>
    );
  }
}

const MessagesSection = props => {
  const { data, act, canDelete } = props;
  const { messages } = data;
  return (
    <Section title={'Messages (' + messages.length + ')'}>
      {messages.length === 0 && (
        <Box color="label" italic>None received.</Box>
      )}
      {messages.map((msg, index) => (
        <Collapsible
          key={index}
          title={msg.title + (msg.answers.length && !msg.answered
            ? ' (awaiting an answer)'
            : '')}
          color={msg.answers.length && !msg.answered ? 'average' : null}>
          <Box mb={1} px={1} style={{ 'white-space': 'pre-wrap' }}>
            {msg.content}
          </Box>
          <Box mb={1}>
            {msg.answered && (
              <Box inline color="good" mr={1}>
                {'Answered: ' + msg.answered}
              </Box>
            )}
            {!msg.answered && msg.answers.map((answer, i) => (
              <Button
                key={answer}
                content={answer}
                onClick={() => act('answer', {
                  index: index + 1,
                  answer: i + 1,
                })} />
            ))}
            <ConfirmButton
              icon="trash"
              content="Delete"
              confirm="Delete it"
              disabled={!canDelete}
              onClick={() => act('delete', { index: index + 1 })} />
          </Box>
        </Collapsible>
      ))}
    </Section>
  );
};

const CaptainSection = props => {
  const { data, act, silicon } = props;
  const cooling = data.cc_cooldown > 0;
  const wait = cooling ? 'Arrays recycling: ' + data.cc_cooldown + 's' : null;
  return (
    <Section title={silicon ? 'Announcements' : 'Captain functions'}>
      <Box color="label" mb={0.5}>
        {silicon ? 'Make an announcement' : 'Make a captain\'s announcement'}
      </Box>
      <SendBox
        placeholder="What to tell the crew"
        button="Announce"
        icon="bullhorn"
        disabled={!data.can_announce}
        tooltip={data.can_announce ? null : 'Intercomms recharging'}
        onSend={text => act('announce', { text })} />
      {!silicon && (
        <Fragment>
          <Box color="label" mt={1} mb={0.5}>
            {data.emagged
              ? 'Send a message to [UNKNOWN]'
              : 'Send a message to Central Command'}
          </Box>
          <SendBox
            placeholder="Transmission doesn't guarantee a response"
            button="Send"
            disabled={cooling}
            tooltip={wait}
            onSend={text => act('message_centcom', { text })} />
          {!!data.emagged && (
            <Button
              mt={0.5}
              icon="undo"
              content="Restore backup routing data"
              onClick={() => act('restore_backup')} />
          )}
          {data.cross_servers > 0 && (
            <Fragment>
              <Box color="label" mt={1} mb={0.5}>
                Send a message to allied stations
              </Box>
              <SendBox
                placeholder="A very expensive message"
                button="Send"
                disabled={cooling}
                tooltip={wait}
                onSend={text => act('message_allies', { text })} />
            </Fragment>
          )}
          <Box color="label" mt={1} mb={0.5}>
            Request the nuclear authentication codes
          </Box>
          <SendBox
            placeholder="Why the station needs them"
            button="Request"
            icon="radiation"
            disabled={cooling}
            tooltip={wait}
            onSend={text => act('nuke_request', { text })} />
        </Fragment>
      )}
    </Section>
  );
};

const PurchaseSection = props => {
  const { data, act } = props;
  return (
    <Section>
      <Collapsible
        title={'Buy a shuttle (budget: ' + data.budget + ' credits)'}>
        <NoticeBox>
          Buying a dangerous shuttle may lead to mutiny and/or death.
        </NoticeBox>
        {!!data.shuttle_purchased && (
          <Box color="average" mb={1}>A shuttle has already been bought.</Box>
        )}
        {data.shuttles.map(shuttle => (
          <Collapsible
            key={shuttle.ref}
            title={shuttle.name + ' (' + shuttle.cost + ' credits)'}>
            <Box px={1} mb={0.5}>{shuttle.desc}</Box>
            {!!shuttle.prereqs && (
              <Box px={1} mb={0.5} color="label">
                {'Requires: ' + shuttle.prereqs}
              </Box>
            )}
            <Box px={1} mb={1}>
              <ConfirmButton
                icon="shopping-cart"
                content="Buy"
                confirm={'Buy it for ' + shuttle.cost}
                disabled={data.shuttle_purchased
                  || data.budget < shuttle.cost}
                onClick={() => act('buy_shuttle', { ref: shuttle.ref })} />
            </Box>
          </Collapsible>
        ))}
      </Collapsible>
    </Section>
  );
};

export const CommsConsole = props => {
  const { act, data } = useBackend(props);
  const { silicon, authenticated } = data;
  if (data.far) {
    return (
      <NoticeBox>
        Unable to establish a connection: you&apos;re too far away from the
        station!
      </NoticeBox>
    );
  }
  const canUse = silicon || authenticated > 0;
  const captain = silicon || authenticated === 2;
  let who = 'Not logged in';
  if (silicon) {
    who = 'AI access';
  } else if (authenticated) {
    who = data.auth_id + (authenticated === 2 ? ' (captain functions)' : '');
  }
  return (
    <Fragment>
      <Section
        title="Login"
        buttons={!silicon && (authenticated ? (
          <Button
            icon="sign-out-alt"
            content="Log out"
            onClick={() => act('logout')} />
        ) : (
          <Button
            icon="sign-in-alt"
            content="Log in"
            onClick={() => act('login')} />
        ))}>
        <Box color={canUse ? 'good' : 'label'}>{who}</Box>
        {!canUse && (
          <Box mt={0.5} color="label">
            Log in with a head of staff&apos;s ID, worn or in hand.
          </Box>
        )}
      </Section>
      {canUse && (
        <Fragment>
          <ShuttleSection data={data} act={act} canUse={canUse} />
          <Section title="Alert level">
            <LabeledList>
              <LabeledList.Item label="Now">
                <Box inline bold>{data.alert_level}</Box>
              </LabeledList.Item>
              {captain && (
                <LabeledList.Item label="Change to">
                  {data.delta ? (
                    <Box color="bad" bold>
                      The self-destruct mechanism is active: stop it, or
                      evacuate.
                    </Box>
                  ) : (
                    <Fragment>
                      <Button
                        content="Green"
                        color="good"
                        disabled={data.alert_lock > 0}
                        onClick={() => act('alert', {
                          level: data.levels.green,
                        })} />
                      <Button
                        content="Blue"
                        disabled={data.alert_lock > 0}
                        onClick={() => act('alert', {
                          level: data.levels.blue,
                        })} />
                      {data.alert_lock > 0 ? (
                        <Box inline ml={1} color="average">
                          Locked: {data.alert_lock}s
                        </Box>
                      ) : !silicon && (
                        <Box inline ml={1} color="label">
                          Captain&apos;s ID
                        </Box>
                      )}
                    </Fragment>
                  )}
                </LabeledList.Item>
              )}
              {captain && (
                <LabeledList.Item label="Emergency access">
                  <Box inline mr={1}
                    color={data.emergency_access ? 'bad' : 'good'}>
                    {data.emergency_access
                      ? 'Maintenance and external airlocks open to all'
                      : 'Off'}
                  </Box>
                  <ConfirmButton
                    icon={data.emergency_access ? 'lock' : 'lock-open'}
                    content={data.emergency_access ? 'Restore' : 'Lift'}
                    onClick={() => act('emergency_access')} />
                </LabeledList.Item>
              )}
            </LabeledList>
          </Section>
          {captain && (
            <CaptainSection data={data} act={act} silicon={silicon} />
          )}
          <MessagesSection data={data} act={act} canDelete={canUse} />
          <StatusSection data={data} act={act} />
          {!silicon && authenticated === 2 && !!data.can_buy_shuttles && (
            <PurchaseSection data={data} act={act} />
          )}
        </Fragment>
      )}
    </Fragment>
  );
};
