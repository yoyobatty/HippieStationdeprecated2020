import { Component, Fragment } from 'inferno';
import { useBackend } from '../backend';
import { Box, Button, Dropdown, Icon, Input, LabeledList, NoticeBox, NumberInput, Section, Tabs } from '../components';
import { TelecommsMap } from './common/TelecommsMap';

// hippie -- the Traffic Control NTOS app: telecomms traffic rules, a
// point-and-click NTSL. Data from hippiestation/code/game/machinery/
// telecomms/traffic_control.dm.

const ACTION_COLORS = {
  block: 'bad',
  reroute: 'average',
  copy: 'teal',
  replace: 'blue',
  garble: 'orange',
  rename: 'purple',
};

const RuleRow = props => {
  const { act, rule, first, last } = props;
  return (
    <div
      className={'TrafficControl__rule'
        + (rule.enabled ? '' : ' TrafficControl__rule--off')
        + (rule.silent ? ' TrafficControl__rule--silent' : '')}>
      <Box inline width="36px" color="label">#{rule.id}</Box>
      <Box inline
        className="TrafficControl__action"
        backgroundColor={ACTION_COLORS[rule.action]}>
        {rule.action}
      </Box>
      <Box inline className="TrafficControl__text">
        {rule.text}
        {!!rule.silent && (
          <Box inline ml={1} color="purple" bold>SILENT</Box>
        )}
        <Box fontSize="10px" color="label">
          {rule.author} · {rule.hits} hits
        </Box>
      </Box>
      <Box inline style={{ float: 'right' }}>
        <Button
          icon="arrow-up"
          disabled={first}
          onClick={() => act('move_rule', { id: rule.id, dir: 'up' })} />
        <Button
          icon="arrow-down"
          disabled={last}
          onClick={() => act('move_rule', { id: rule.id, dir: 'down' })} />
        <Button
          icon="power-off"
          selected={rule.enabled}
          onClick={() => act('toggle_rule', { id: rule.id })} />
        <Button
          icon="trash"
          color="bad"
          onClick={() => act('delete_rule', { id: rule.id })} />
      </Box>
    </div>
  );
};

class RuleForm extends Component {
  constructor() {
    super();
    this.state = {
      channel: 'Any',
      speaker: '',
      job: '',
      word: '',
      action: 'block',
      target: null,
      replaceWith: '',
      garble: 50,
      renameTo: '',
      silent: false,
    };
  }

  render() {
    const { act, data } = this.props;
    const channels = data.channels || [];
    const names = channels.map(channel => channel.name);
    const freqOf = name => {
      const found = channels.find(channel => channel.name === name);
      return found ? found.frequency : 0;
    };
    const s = this.state;
    const set = (key, value) => this.setState({ [key]: value });
    const needsTarget = s.action === 'reroute' || s.action === 'copy';
    const valid = (!needsTarget || s.target)
      && (s.action !== 'replace' || s.word)
      && (s.action !== 'rename' || s.renameTo);
    const full = data.rule_count >= data.max_rules;
    return (
      <Section title="New rule">
        <LabeledList>
          <LabeledList.Item label="Channel">
            <Dropdown
              width="160px"
              selected={s.channel}
              options={['Any', ...names]}
              onSelected={value => set('channel', value)} />
          </LabeledList.Item>
          <LabeledList.Item label="Speaker has">
            <Input
              width="200px"
              value={s.speaker}
              onInput={(e, value) => set('speaker', value)} />
          </LabeledList.Item>
          <LabeledList.Item label="Job has">
            <Input
              width="200px"
              value={s.job}
              onInput={(e, value) => set('job', value)} />
          </LabeledList.Item>
          <LabeledList.Item label="Message has">
            <Input
              width="200px"
              value={s.word}
              onInput={(e, value) => set('word', value)} />
          </LabeledList.Item>
          <LabeledList.Item label="Do">
            {(data.actions || []).map(action => (
              <Button
                key={action}
                content={action}
                selected={s.action === action}
                color={s.action === action ? ACTION_COLORS[action] : null}
                onClick={() => set('action', action)} />
            ))}
          </LabeledList.Item>
          {needsTarget && (
            <LabeledList.Item label="To channel">
              <Dropdown
                width="160px"
                selected={s.target || 'Pick...'}
                options={names}
                onSelected={value => set('target', value)} />
            </LabeledList.Item>
          )}
          {s.action === 'replace' && (
            <LabeledList.Item label="Replace with">
              <Input
                width="200px"
                value={s.replaceWith}
                onInput={(e, value) => set('replaceWith', value)} />
            </LabeledList.Item>
          )}
          {s.action === 'garble' && (
            <LabeledList.Item label="Garble">
              <NumberInput
                width="60px"
                unit="%"
                value={s.garble}
                minValue={5}
                maxValue={100}
                onChange={(e, value) => set('garble', value)} />
            </LabeledList.Item>
          )}
          {s.action === 'rename' && (
            <LabeledList.Item label="Rename to">
              <Input
                width="200px"
                value={s.renameTo}
                onInput={(e, value) => set('renameTo', value)} />
            </LabeledList.Item>
          )}
          {!!data.hacked && (
            <LabeledList.Item label="Silent">
              <Button.Checkbox
                checked={s.silent}
                color={s.silent ? 'purple' : null}
                content="Hidden, unlogged"
                onClick={() => set('silent', !s.silent)} />
            </LabeledList.Item>
          )}
        </LabeledList>
        <Box mt={1}>
          <Button
            icon="plus"
            content={full ? 'Rule table full' : 'Add rule'}
            disabled={!valid || full}
            onClick={() => act('add_rule', {
              frequency: freqOf(s.channel),
              speaker: s.speaker,
              job: s.job,
              word: s.word,
              action: s.action,
              target: needsTarget ? freqOf(s.target) : 0,
              replace_with: s.replaceWith,
              garble: s.garble,
              rename_to: s.renameTo,
              silent: s.silent ? 1 : 0,
            })} />
        </Box>
      </Section>
    );
  }
}

export class NtosTrafficControl extends Component {
  constructor() {
    super();
    this.state = { tab: 'network' };
  }

  render() {
    const { act, data } = useBackend(this.props);
    const { tab } = this.state;
    const rules = data.rules || [];
    const history = data.history || [];
    return (
      <Fragment>
        {!!data.hacked && (
          <NoticeBox>
            <Icon name="user-secret" mr={1} />
            OVERRIDE ACTIVE
          </NoticeBox>
        )}
        <Tabs activeTab={tab}>
          <Tabs.Tab
            key="network"
            label="Network"
            onClick={() => this.setState({ tab: 'network' })} />
          <Tabs.Tab
            key="rules"
            label={'Rules (' + rules.length + ')'}
            onClick={() => this.setState({ tab: 'rules' })} />
          <Tabs.Tab
            key="history"
            label="History"
            onClick={() => this.setState({ tab: 'history' })} />
        </Tabs>
        {tab === 'network' && (
          <Section>
            <TelecommsMap map={data.map} />
          </Section>
        )}
        {tab === 'rules' && (
          <Fragment>
            <Section title="Rules, in order">
              {rules.length === 0 && (
                <Box color="label">No rules. All traffic passes.</Box>
              )}
              {rules.map((rule, i) => (
                <RuleRow
                  key={rule.id}
                  act={act}
                  rule={rule}
                  first={i === 0}
                  last={i === rules.length - 1} />
              ))}
            </Section>
            <RuleForm act={act} data={data} />
          </Fragment>
        )}
        {tab === 'history' && (
          <Section title="Rule changes">
            {history.length === 0 && (
              <Box color="label">None</Box>
            )}
            {history.map((entry, i) => (
              <Box key={i} mb={0.5}>
                <Box inline color="label" mr={1}>{entry.time}</Box>
                <b>{entry.who}</b> {entry.what}
              </Box>
            ))}
          </Section>
        )}
      </Fragment>
    );
  }
}
