import { Component, Fragment } from 'inferno';
import { useBackend } from '../backend';
import { Box, Button, Input, LabeledList, NoticeBox, ProgressBar, Section } from '../components';

// hippie -- a telecomms machine's multitool menu
// (hippiestation/.../telecomms/machine_interactions_tgui.dm)

class AddFrequency extends Component {
  constructor() {
    super();
    this.state = { value: '' };
  }

  render() {
    const { act } = this.props;
    return (
      <Box mt={1}>
        <Input
          width="90px"
          placeholder="145.9"
          value={this.state.value}
          onInput={(e, value) => this.setState({ value })} />
        <Button
          icon="plus"
          content="Add filter"
          disabled={!this.state.value}
          onClick={() => {
            act('add_freq', { value: this.state.value });
            this.setState({ value: '' });
          }} />
      </Box>
    );
  }
}

export const TelecommsMachine = props => {
  const { act, data } = useBackend(props);
  const links = data.links || [];
  const freqs = data.frequencies || [];
  let busFrequency = '';
  if (data.change_frequency) {
    busFrequency = String(data.change_frequency / 10);
  }
  let settings = null;
  if (data.working) {
    let bufferRow = (
      <Fragment>
        <Box inline color="label" mr={1}>Empty</Box>
        <Button
          icon="download"
          content="Store this machine"
          onClick={() => act('buffer')} />
      </Fragment>
    );
    if (data.buffer) {
      bufferRow = (
        <Fragment>
          <Box inline mr={1}>{data.buffer}</Box>
          <Button
            icon="link"
            content="Link"
            disabled={data.buffer_is_this}
            onClick={() => act('link')} />
          <Button
            icon="eraser"
            content="Flush"
            onClick={() => act('flush')} />
        </Fragment>
      );
    }
    settings = (
      <Fragment>
        <Section title="Settings">
          <LabeledList>
            <LabeledList.Item label="Identification">
              <Input
                fluid
                value={data.id}
                onChange={(e, value) => act('id', { value })} />
            </LabeledList.Item>
            <LabeledList.Item label="Network">
              <Input
                fluid
                value={data.network}
                onChange={(e, value) => act('network', { value })} />
            </LabeledList.Item>
            <LabeledList.Item label="Prefabrication">
              {data.prefab ? 'Yes' : 'No'}
            </LabeledList.Item>
            {!!data.hidden && (
              <LabeledList.Item label="Shadow link">
                <Box color="average">Active</Box>
              </LabeledList.Item>
            )}
            {(data.options || []).map(option => (
              <LabeledList.Item key={option.key} label={option.name}>
                <Button
                  content={option.on ? 'Yes' : 'No'}
                  selected={option.on}
                  onClick={() => act('option', { key: option.key })} />
              </LabeledList.Item>
            ))}
            {!!data.bus && (
              <LabeledList.Item label="Change frequency to">
                <Input
                  width="90px"
                  placeholder="off"
                  value={busFrequency}
                  onChange={(e, value) => act('change_freq', { value })} />
                <Box inline ml={1} color="label">
                  {data.change_frequency ? 'GHz' : 'not changing'}
                </Box>
              </LabeledList.Item>
            )}
          </LabeledList>
        </Section>
        <Section title={'Linked machines (' + links.length + ')'}>
          {links.length === 0 && <Box color="label">None.</Box>}
          {links.map(link => (
            <Box key={link.index} className="candystripe" p={0.5}>
              <Button
                icon="unlink"
                color="transparent"
                tooltip="Unlink"
                onClick={() => act('unlink', { index: link.index })} />
              {link.name}
              <Box inline ml={1} color="label">{link.id}</Box>
            </Box>
          ))}
        </Section>
        <Section title="Filtering frequencies">
          {freqs.length === 0 && <Box color="label">None.</Box>}
          {freqs.map(freq => (
            <Button
              key={freq.value}
              icon="times"
              content={freq.name + ' GHz'}
              onClick={() => act('delete_freq', { value: freq.value })} />
          ))}
          <AddFrequency act={act} />
        </Section>
        {!!data.has_multitool && (
          <Section title="Multitool buffer">
            {bufferRow}
          </Section>
        )}
      </Fragment>
    );
  }
  return (
    <Fragment>
      <Section
        title="Power"
        buttons={(
          <Button
            icon="power-off"
            content={data.toggled ? 'On' : 'Off'}
            selected={data.toggled}
            onClick={() => act('toggle')} />
        )}>
        {!!data.notice && <Box color="average">{data.notice}</Box>}
        {!data.working && (
          <NoticeBox>
            The machine is off. Its settings show once it&apos;s running.
          </NoticeBox>
        )}
      </Section>
      <Condition data={data} />
      {settings}
    </Fragment>
  );
};

// hippie -- the machine's condition (signal_quality.dm): what it adds to
// the static on every signal through it
const Condition = props => {
  const { data } = props;
  if (data.temperature === undefined) {
    return null;
  }
  const hot = data.temperature >= data.temp_limit;
  const warm = data.temperature > data.temp_safe;
  return (
    <Section title="Condition">
      <LabeledList>
        <LabeledList.Item
          label="Temperature"
          color={hot && 'bad' || warm && 'average' || 'good'}>
          {data.temperature} K
          <Box inline color="label" ml={1}>
            (limit {data.temp_limit} K)
          </Box>
        </LabeledList.Item>
        <LabeledList.Item label="Integrity">
          <ProgressBar
            value={data.integrity / 100}
            ranges={{
              good: [0.8, Infinity],
              average: [0.4, 0.8],
              bad: [-Infinity, 0.4],
            }}>
            {data.integrity}%
          </ProgressBar>
        </LabeledList.Item>
        <LabeledList.Item label="Traffic">
          {data.traffic}
        </LabeledList.Item>
        <LabeledList.Item
          label="Signal noise"
          color={data.noise >= 50 && 'bad' || data.noise >= 5 && 'average'
            || 'good'}>
          {data.noise}%
        </LabeledList.Item>
        {!!data.emped && (
          <LabeledList.Item label="Fault" color="bad">
            EMP: heavy static
          </LabeledList.Item>
        )}
        {!!data.overheated && (
          <LabeledList.Item label="Fault" color="bad">
            OVERHEATED
          </LabeledList.Item>
        )}
      </LabeledList>
    </Section>
  );
};
