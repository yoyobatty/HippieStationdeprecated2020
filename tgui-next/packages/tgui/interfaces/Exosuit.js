import { Component, Fragment } from 'inferno';
import { useBackend } from '../backend';
import { Box, Button, Icon, LabeledList, NoticeBox, ProgressBar, Section } from '../components';

// hippie -- a mech's own menu (hippiestation/code/game/mecha/mecha_tgui.dm)

const ROW = { 'display': 'flex', 'align-items': 'center' };

// Each mech's paint (mecha_tgui.dm mecha_ui_paint()), as the custom
// properties the mecha theme reads: text, labels, bars, text on the bars,
// the background, then buttons and the title bar. The rest is derived.
const PAINTS = {
  ripley: ['#3dff6b', '#22a845', '#2ecc55', '#031a09', '#020602',
    '#0c2c15', '#164a24', '#041006'],
  firefighter: ['#ff9a3c', '#c0661f', '#ff7a1a', '#1f0a00', '#070301',
    '#2e1306', '#4d210b', '#0e0502'],
  syndicate: ['#ff4d4d', '#b02f2f', '#d42a2a', '#160000', '#060101',
    '#2b0808', '#4a0e0e', '#0d0202'],
  medical: ['#4ff3e6', '#2aa69c', '#33cfc3', '#00191a', '#010607',
    '#06292a', '#0b4547', '#020c0d'],
  gygax: ['#ffc23d', '#b8862a', '#e6a823', '#1c1200', '#060401',
    '#2b1f06', '#48340b', '#0d0902'],
  durand: ['#8fd3ff', '#5a93ba', '#6fb8ea', '#021220', '#02050a',
    '#0b2238', '#133a5c', '#040a12'],
  marauder: ['#dce9f5', '#8aa0b5', '#b7cbe0', '#0a1118', '#05070a',
    '#1a2430', '#2a3a4c', '#0a0e13'],
  seraph: ['#ffd96b', '#b89640', '#e8bf3f', '#1a1200', '#040716',
    '#141c44', '#1f2b66', '#070b22'],
  phazon: ['#c792ff', '#8a5fc0', '#a86ff0', '#12031f', '#05020a',
    '#220d38', '#37165c', '#0a0412'],
  honk: ['#ff86dc', '#e0b400', '#ffe14d', '#2a0020', '#14040f',
    '#3a0f2e', '#5c1849', '#1f0718'],
  honk_dark: ['#ff5c8a', '#b03a5a', '#7a0f2a', '#ffe0e8', '#0a0104',
    '#2e0613', '#4c0b20', '#120207'],
  mime: ['#f2f2f2', '#9a9a9a', '#f2f2f2', '#000000', '#000000',
    '#141414', '#262626', '#050505'],
  scrap: ['#e3a15a', '#9c6b38', '#b8783a', '#1a0d03', '#0b0805',
    '#2a1a0c', '#432a14', '#120c07'],
  brass: ['#e8b84f', '#a67c2b', '#c9962f', '#1c1000', '#0c0702',
    '#2e1e08', '#4a3210', '#140c03'],
};

// What only some of them have: a face, bars that aren't flat, no glow
const EXTRAS = {
  honk: {
    'font': '"Comic Sans MS", "Comic Neue", cursive',
    'bar-image': 'linear-gradient(90deg, #ff86dc, #ffe14d, #8affc1, '
      + '#86d4ff, #c792ff)',
  },
  honk_dark: {
    'font': '"Comic Sans MS", "Comic Neue", cursive',
    'bar-image': 'linear-gradient(90deg, #7a0f2a, #ff2d55, #7a0f2a)',
  },
  mime: { 'glow': 'transparent', 'scan': 'transparent' },
  scrap: { 'border-style': 'dashed' },
  brass: {
    'font': 'Georgia, "Times New Roman", serif',
    'bar-image': 'linear-gradient(180deg, #f2cc6b, #b8862e)',
  },
};

// The words that change with the mech: the old H.O.N.K. page's own, the
// mime's silence, the locker mech's optimism
const WORDS = {
  honk: { integrity: 'IntegriHONK', power: 'PowerHONK',
    airtank: 'AirHONK', cabin: 'HONK', nominal: 'ALL SYSTEMS HONK' },
  mime: { nominal: '...' },
  scrap: { nominal: 'HOLDING TOGETHER' },
  brass: { nominal: 'ALL COGS TURNING' },
};
WORDS.honk_dark = WORDS.honk;

const words = paint => Object.assign({
  integrity: 'Integrity',
  power: 'Power',
  airtank: 'Airtank',
  cabin: 'Cabin',
  nominal: 'ALL SYSTEMS NOMINAL',
}, WORDS[paint]);

// rgba() of a #rrggbb at an alpha
const alpha = (hex, a) => 'rgba(' + parseInt(hex.substr(1, 2), 16) + ', '
  + parseInt(hex.substr(3, 2), 16) + ', ' + parseInt(hex.substr(5, 2), 16)
  + ', ' + a + ')';

const paintCss = paint => {
  const p = PAINTS[paint] || PAINTS.ripley;
  const vars = Object.assign({
    'fg': p[0],
    'dim': p[1],
    'bar': p[2],
    'ink': p[3],
    'bg': p[4],
    'button': p[5],
    'button-hover': p[6],
    'title': p[7],
    'panel': alpha(p[2], 0.08),
    'line': alpha(p[0], 0.36),
    'glow': alpha(p[0], 0.3),
    'scan': alpha(p[0], 0.03),
    'stripe': alpha(p[0], 0.05),
  }, EXTRAS[paint]);
  return ':root {' + Object.keys(vars)
    .map(key => '--m-' + key + ': ' + vars[key] + ';').join(' ') + '}';
};

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
          <Box bold fontSize="15px" style={{ 'flex-grow': 1 }}>
            <span className="Exosuit__prompt">&gt;</span>
            {name.toUpperCase()}
            <span className="Exosuit__cursor" />
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
            'background-color': 'rgba(0, 0, 0, 0.6)',
            'color': 'inherit',
            'border': '1px solid rgba(61, 255, 107, 0.5)',
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

// One line under the name, as the cockpit's own read-out would put it
const readout = data => {
  if (data.integrity < 30) {
    return ['bad', 'DAMAGE CRITICAL'];
  }
  if ((data.damage || []).length) {
    return ['average', 'INTERNAL DAMAGE'];
  }
  if (data.cell === null || data.cell < 15) {
    return ['average', 'POWER LOW'];
  }
  return ['good', words(data.paint).nominal];
};

// The bar's figure on a chip of its own, clear of the segments
const pct = value => <span className="Exosuit__pct">{value + '%'}</span>;

const Status = props => {
  const { data, act } = props;
  const [color, line] = readout(data);
  const said = words(data.paint);
  return (
    <Section>
      <NameBox name={data.name} act={act} />
      <Box color={color} fontSize="11px" mb={1} style={{
        'letter-spacing': '1px' }}>
        {'SYS: ' + line}
      </Box>
      <LabeledList>
        <LabeledList.Item label={said.integrity}>
          <ProgressBar
            value={data.integrity}
            maxValue={100}
            color={healthColor(data.integrity)}
            content={pct(data.integrity)} />
        </LabeledList.Item>
        <LabeledList.Item label={said.power}>
          {data.cell === null && <Box color="bad">No power cell</Box>}
          {data.cell !== null && (
            <ProgressBar
              value={data.cell}
              maxValue={100}
              color={healthColor(data.cell)}
              content={pct(data.cell)} />
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
  const said = words(data.paint);
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
        <LabeledList.Item label={said.airtank}>
          {data.tank_pressure + ' kPa, ' + data.tank_temperature + ' °C'}
        </LabeledList.Item>
        <LabeledList.Item
          label={said.cabin}
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
      <style>{paintCss(data.paint)}</style>
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
