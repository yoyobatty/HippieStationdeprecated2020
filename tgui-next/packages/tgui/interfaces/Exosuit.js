import { Component, Fragment } from 'inferno';
import { useBackend } from '../backend';
import { Box, Button, Icon, LabeledList, NoticeBox, ProgressBar, Section } from '../components';

// hippie -- a mech's own menu (hippiestation/code/game/mecha/mecha_tgui.dm)

const ROW = { 'display': 'flex', 'align-items': 'center' };

const healthColor = percent => {
  if (percent < 30) {
    return 'bad';
  }
  return percent < 60 ? 'average' : 'good';
};

class NameBox extends Component {
  constructor() {
    super();
    this.state = { editing: false, text: '' };
  }

  render() {
    const { name, act } = this.props;
    if (!this.state.editing) {
      return (
        <Box style={ROW}>
          <Box bold fontSize="16px" style={{ 'flex-grow': 1 }}>
            <Icon name="robot" mr={1} />
            {name}
          </Box>
          <Button
            icon="pen"
            color="transparent"
            tooltip="Rename"
            tooltipPosition="left"
            onClick={() => this.setState({ editing: true, text: name })} />
        </Box>
      );
    }
    const done = () => {
      if (this.state.text) {
        act('rename', { name: this.state.text });
      }
      this.setState({ editing: false });
    };
    return (
      <Box style={ROW}>
        <input
          value={this.state.text}
          maxLength={42}
          onInput={e => this.setState({ text: e.target.value })}
          onKeyDown={e => {
            if (e.keyCode === 13) {
              done();
            }
          }}
          style={{
            'flex-grow': 1,
            'background-color': 'rgba(0, 0, 0, 0.4)',
            'color': '#ffffff',
            'border': '1px solid #404b6e',
            'padding': '3px',
          }} />
        <Button ml={0.5} icon="check" content="Rename" onClick={done} />
        <Button
          icon="times"
          onClick={() => this.setState({ editing: false })} />
      </Box>
    );
  }
}

const Status = props => {
  const { data, act } = props;
  return (
    <Section>
      <NameBox name={data.name} act={act} />
      <LabeledList>
        <LabeledList.Item label="Integrity">
          <ProgressBar
            value={data.integrity}
            maxValue={100}
            color={healthColor(data.integrity)}
            content={data.integrity + '%'} />
        </LabeledList.Item>
        <LabeledList.Item label="Power">
          {data.cell === null && <Box color="bad">No power cell</Box>}
          {data.cell !== null && (
            <ProgressBar
              value={data.cell}
              maxValue={100}
              color={healthColor(data.cell)}
              content={data.cell + '%'} />
          )}
        </LabeledList.Item>
      </LabeledList>
      <Box mt={1}>
        <Button
          icon="lightbulb"
          content={'Lights ' + (data.lights ? 'on' : 'off')}
          selected={data.lights}
          onClick={() => act('lights')} />
        {!!data.has_tank && (
          <Button
            icon="wind"
            content={data.internal_air ? 'Internal airtank' : 'Outside air'}
            selected={data.internal_air}
            tooltip="Where the cabin's air comes from"
            onClick={() => act('internals')} />
        )}
      </Box>
    </Section>
  );
};

const Warnings = props => {
  const { data, act } = props;
  const damage = data.damage || [];
  if (!damage.length && data.integrity >= 30 && !data.cabin_high) {
    return null;
  }
  return (
    <NoticeBox>
      {data.integrity < 30 && <Box bold>DAMAGE LEVEL CRITICAL</Box>}
      {damage.map(line => (
        <Box key={line} bold>{line.toUpperCase()}</Box>
      ))}
      {!!data.cabin_high && <Box bold>DANGEROUSLY HIGH CABIN PRESSURE</Box>}
      {!!data.control_lost && (
        <Button
          mt={0.5}
          icon="wrench"
          content="Recalibrate"
          onClick={() => act('recalibrate')} />
      )}
    </NoticeBox>
  );
};

const Air = props => {
  const { data, act } = props;
  if (!data.has_tank) {
    return null;
  }
  const portLabel = data.port ? 'Disconnect from port' : 'Connect to port';
  let portTip = null;
  if (!data.port && !data.port_here) {
    portTip = 'No gas port under the exosuit';
  }
  return (
    <Section
      title="Air"
      buttons={(
        <Button
          icon="plug"
          content={portLabel}
          selected={data.port}
          disabled={!data.port && !data.port_here}
          tooltip={portTip}
          tooltipPosition="left"
          onClick={() => act('port')} />
      )}>
      <LabeledList>
        <LabeledList.Item label="Airtank">
          {data.tank_pressure + ' kPa, ' + data.tank_temperature + ' °C'}
        </LabeledList.Item>
        <LabeledList.Item
          label="Cabin"
          color={data.cabin_high ? 'bad' : null}>
          {data.cabin_pressure + ' kPa, ' + data.cabin_temperature
            + ' °C'}
        </LabeledList.Item>
        <LabeledList.Item label="Cabin valve">
          {data.valve + ' kPa'}
        </LabeledList.Item>
      </LabeledList>
    </Section>
  );
};

const Equipment = props => {
  const { data, act } = props;
  const kit = data.equipment || [];
  return (
    <Section
      title="Equipment"
      buttons={(
        <Box color="label" mt={0.5}>
          {data.slots + ' of ' + data.max_equip + ' slots free'}
        </Box>
      )}>
      {kit.length === 0 && <Box color="label">Nothing fitted.</Box>}
      {kit.map(item => (
        <Box
          key={item.ref}
          className="candystripe"
          style={{ 'padding': '4px', 'border-radius': '2px' }}>
          <Box style={ROW}>
            <Icon
              name="circle"
              color={item.ready ? 'good' : 'bad'}
              mr={1}
              title={item.ready ? 'Ready' : 'Not ready'} />
            <Box bold style={{ 'flex-grow': 1 }}>{item.name}</Box>
            {!!item.selectable && (
              <Button
                icon="crosshairs"
                content={item.selected ? 'Selected' : 'Select'}
                selected={item.selected}
                onClick={() => act('select', { ref: item.ref })} />
            )}
            <Button
              icon="eject"
              color="transparent"
              tooltip="Detach"
              tooltipPosition="left"
              onClick={() => act('detach', { ref: item.ref })} />
          </Box>
          {(!!item.status || item.links.length > 0) && (
            <Box ml={3} mt={0.5}>
              {!!item.status && (
                <Box inline color="label" mr={1}>{item.status}</Box>
              )}
              {item.links.map((link, i) => (
                <Button
                  key={i}
                  content={link.label}
                  onClick={() => act('link', {
                    target: link.target,
                    query: link.query,
                  })} />
              ))}
            </Box>
          )}
        </Box>
      ))}
    </Section>
  );
};

const Cargo = props => {
  const { data, act } = props;
  const cargo = data.cargo;
  if (!cargo) {
    return null;
  }
  return (
    <Section
      title="Cargo compartment"
      buttons={(
        <Box color="label" mt={0.5}>
          {cargo.items.length + ' of ' + cargo.capacity}
        </Box>
      )}>
      {cargo.items.length === 0 && <Box color="label">Nothing.</Box>}
      {cargo.items.map(item => (
        <Box key={item.ref} style={ROW} className="candystripe">
          <Box style={{ 'flex-grow': 1 }}>{item.name}</Box>
          <Button
            icon="box-open"
            content="Unload"
            onClick={() => act('unload', { ref: item.ref })} />
        </Box>
      ))}
    </Section>
  );
};

const Modes = props => {
  const { data } = props;
  const modes = data.modes || [];
  if (!modes.length) {
    return null;
  }
  return (
    <Section title="Systems">
      <LabeledList>
        {modes.map(mode => {
          let value = mode.value;
          let color = null;
          if (value === undefined) {
            value = mode.on ? 'Enabled' : 'Disabled';
            color = mode.on ? 'good' : 'label';
          }
          return (
            <LabeledList.Item key={mode.name} label={mode.name} color={color}>
              {value}
            </LabeledList.Item>
          );
        })}
      </LabeledList>
    </Section>
  );
};

const Electronics = props => {
  const { data, act } = props;
  const radio = data.radio;
  return (
    <Section title="Electronics">
      <LabeledList>
        {!!radio && (
          <Fragment>
            <LabeledList.Item label="Radio">
              <Button
                icon="microphone"
                content={radio.mic ? 'Mic on' : 'Mic off'}
                selected={radio.mic}
                onClick={() => act('mic')} />
              <Button
                icon="volume-up"
                content={radio.speaker ? 'Speaker on' : 'Speaker off'}
                selected={radio.speaker}
                onClick={() => act('speaker')} />
            </LabeledList.Item>
            <LabeledList.Item label="Frequency">
              <Button
                content="-"
                onClick={() => act('frequency', { by: -10 })} />
              <Button
                content="-"
                onClick={() => act('frequency', { by: -2 })} />
              <Box inline mx={1} bold>{radio.frequency}</Box>
              <Button
                content="+"
                onClick={() => act('frequency', { by: 2 })} />
              <Button
                content="+"
                onClick={() => act('frequency', { by: 10 })} />
            </LabeledList.Item>
          </Fragment>
        )}
        <LabeledList.Item label="ID upload panel">
          <Button
            icon={data.id_upload ? 'lock-open' : 'lock'}
            content={data.id_upload ? 'Unlocked' : 'Locked'}
            selected={data.id_upload}
            tooltip="Lets an ID set who can pilot it"
            onClick={() => act('id_upload')} />
        </LabeledList.Item>
        <LabeledList.Item label="Maintenance">
          <Button
            icon="tools"
            content={data.maint_access ? 'Permitted' : 'Forbidden'}
            selected={data.maint_access}
            disabled={data.maintenance > 0}
            tooltip="Whether maintenance protocols can be started"
            onClick={() => act('maint_access')} />
        </LabeledList.Item>
        <LabeledList.Item label="DNA lock">
          {!data.dna_lock && (
            <Button
              icon="dna"
              content="Lock to my DNA"
              disabled={!data.can_dna}
              onClick={() => act('dna_lock')} />
          )}
          {!!data.dna_lock && (
            <Fragment>
              <Box inline color="good" mr={1} fontSize="10px">
                {data.dna_lock}
              </Box>
              <Button
                icon="unlock"
                content="Reset"
                onClick={() => act('dna_reset')} />
            </Fragment>
          )}
        </LabeledList.Item>
      </LabeledList>
    </Section>
  );
};

export const Exosuit = props => {
  const { act, data } = useBackend(props);
  return (
    <Fragment>
      <Status data={data} act={act} />
      <Warnings data={data} act={act} />
      <Equipment data={data} act={act} />
      <Cargo data={data} act={act} />
      <Modes data={data} />
      <Air data={data} act={act} />
      <Electronics data={data} act={act} />
    </Fragment>
  );
};
