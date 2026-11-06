import { toFixed } from 'common/math';
import { decodeHtmlEntities } from 'common/string';
import { Component, Fragment } from 'inferno';
import { useBackend } from '../backend';
import { Box, Button, Icon, NoticeBox, NumberInput, Section, Tabs } from '../components';
import { InterfaceLockNoticeBox } from './common/InterfaceLockNoticeBox';
import { gasColor, gasLabel, GasBar, GasLegend, kelvinToCelsius } from './common/AtmosBits';

// hippie -- the air alarm redone: how the room is doing as one banner with
// the area alarm beside it, pressure and temperature as big readings, the
// air as a bar split by gas, and the controls as tabs (vents, scrubbers,
// mode, thresholds) instead of screens behind a back button. Thresholds are
// typed in the window. The extra data comes from hippiestation/code/
// modules/atmospherics/atmos_tgui.dm.

const DANGER = [
  { color: 'good', icon: 'check-circle', text: 'Optimal' },
  { color: 'average', icon: 'exclamation-circle', text: 'Caution' },
  { color: 'bad', icon: 'exclamation-triangle',
    text: 'Danger: internals needed' },
];

const PANIC_MODE = 3;
const SCRUB_MODE = 1;

export class AirAlarm extends Component {
  constructor() {
    super();
    this.state = { tab: 'vents' };
  }

  render() {
    const { state } = this.props;
    const { act, data } = useBackend(this.props);
    const { tab } = this.state;
    const locked = data.locked && !data.siliconUser;
    const vents = data.vents || [];
    const scrubbers = data.scrubbers || [];
    return (
      <Fragment>
        <InterfaceLockNoticeBox
          siliconUser={data.siliconUser}
          locked={data.locked}
          onLockStatusChange={() => act('lock')} />
        <AirStatus state={state} />
        {!locked && (
          <Section
            title="Controls"
            buttons={(
              <Button
                icon="exclamation-triangle"
                color={data.mode === PANIC_MODE ? 'danger' : 'default'}
                content={data.mode === PANIC_MODE
                  ? 'Stop panic siphon'
                  : 'Panic siphon'}
                onClick={() => act('mode', {
                  mode: data.mode === PANIC_MODE ? SCRUB_MODE : PANIC_MODE,
                })} />
            )}>
            <Tabs activeTab={tab}>
              <Tabs.Tab
                key="vents"
                label={'Vents (' + vents.length + ')'}
                onClick={() => this.setState({ tab: 'vents' })} />
              <Tabs.Tab
                key="scrubbers"
                label={'Scrubbers (' + scrubbers.length + ')'}
                onClick={() => this.setState({ tab: 'scrubbers' })} />
              <Tabs.Tab
                key="modes"
                label="Mode"
                onClick={() => this.setState({ tab: 'modes' })} />
              <Tabs.Tab
                key="thresholds"
                label="Thresholds"
                onClick={() => this.setState({ tab: 'thresholds' })} />
            </Tabs>
            {tab === 'vents' && <Vents state={state} />}
            {tab === 'scrubbers' && <Scrubbers state={state} />}
            {tab === 'modes' && <Modes state={state} />}
            {tab === 'thresholds' && <Thresholds state={state} />}
          </Section>
        )}
      </Fragment>
    );
  }
}

const Reading = props => {
  const { label, entry, children } = props;
  const danger = DANGER[entry ? entry.danger_level : 0] || DANGER[0];
  return (
    <div className="Atmos__reading">
      <Box color="label">{label}</Box>
      <Box fontSize="20px" bold color={danger.color}>
        {children}
      </Box>
    </div>
  );
};

const AirStatus = props => {
  const { act, data } = useBackend(props);
  const entries = data.environment_data || [];
  const find = name => entries.find(entry => entry.name === name);
  const pressure = find('Pressure');
  const temperature = find('Temperature');
  const danger = DANGER[data.danger_level] || DANGER[0];
  const alarm = data.atmos_alarm || data.fire_alarm;
  if (!entries.length) {
    return (
      <NoticeBox>
        Cannot obtain an air sample for analysis.
      </NoticeBox>
    );
  }
  return (
    <Section>
      <div className={'Atmos__banner Atmos__banner--' + danger.color}>
        <Box inline fontSize="16px" bold>
          <Icon name={danger.icon} mr={1} />
          {danger.text}
        </Box>
        <Box inline style={{ float: 'right' }}>
          <Box inline mr={1} color={alarm ? 'bad' : 'label'}>
            {data.fire_alarm && 'Fire alarm'
              || data.atmos_alarm && 'Area alarm on'
              || 'No area alarm'}
          </Box>
          <Button
            icon="bell"
            color={data.atmos_alarm ? 'danger' : 'default'}
            content={data.atmos_alarm ? 'Reset alarm' : 'Raise alarm'}
            onClick={() => act(data.atmos_alarm ? 'reset' : 'alarm')} />
        </Box>
      </div>
      <div className="Atmos__readings">
        <Reading label="Pressure" entry={pressure}>
          {toFixed(data.pressure !== undefined
            ? data.pressure
            : pressure && pressure.value, 1)} kPa
        </Reading>
        <Reading label="Temperature" entry={temperature}>
          {kelvinToCelsius(data.temperature !== undefined
            ? data.temperature
            : temperature && temperature.value)} °C
          <Box inline fontSize="12px" color="label" ml={1}>
            {toFixed(data.temperature !== undefined
              ? data.temperature
              : temperature && temperature.value, 1)} K
          </Box>
        </Reading>
      </div>
      <GasBar gases={data.gases} />
      <GasLegend gases={data.gases} />
      {!!data.emagged && (
        <Box mt={1} color="bad">
          <Icon name="exclamation-triangle" mr={1} />
          Safety measures offline. The device may behave abnormally.
        </Box>
      )}
    </Section>
  );
};

const Vents = props => {
  const { state } = props;
  const { data } = useBackend(props);
  const vents = data.vents || [];
  if (!vents.length) {
    return <Box color="label">No vents on this alarm.</Box>;
  }
  return vents.map(vent => (
    <Vent key={vent.id_tag} state={state} vent={vent} />
  ));
};

const PressureCheck = props => {
  const { act, vent, label, title, checked, checkAction, value,
    setAction, resetAction, isDefault } = props;
  return (
    <Box mt={0.5}>
      <Button.Checkbox
        checked={checked}
        content={label}
        title={title}
        onClick={() => act(checkAction, {
          id_tag: vent.id_tag,
          val: vent.checks,
        })} />
      {!!checked && (
        <Fragment>
          <NumberInput
            value={Math.round(value)}
            unit="kPa"
            width="80px"
            minValue={0}
            step={10}
            maxValue={5066}
            onChange={(e, newValue) => act(setAction, {
              id_tag: vent.id_tag,
              value: newValue,
            })} />
          <Button
            icon="undo"
            disabled={isDefault}
            content="Reset"
            onClick={() => act(resetAction, { id_tag: vent.id_tag })} />
        </Fragment>
      )}
    </Box>
  );
};

const Vent = props => {
  const { vent } = props;
  const { act } = useBackend(props);
  const pressurizing = vent.direction === 'release';
  return (
    <div className="Atmos__device">
      <Box>
        <b>{decodeHtmlEntities(vent.long_name)}</b>
        <Button
          style={{ float: 'right' }}
          icon="power-off"
          selected={vent.power}
          content={vent.power ? 'On' : 'Off'}
          onClick={() => act('power', {
            id_tag: vent.id_tag,
            val: Number(!vent.power),
          })} />
      </Box>
      <Box color={vent.power ? (pressurizing ? 'good' : 'average') : 'label'}>
        <Icon name={pressurizing ? 'sign-out-alt' : 'sign-in-alt'} mr={1} />
        {pressurizing ? 'Pressurizing' : 'Siphoning'}
      </Box>
      <PressureCheck
        act={act}
        vent={vent}
        label="Room limit"
        title="External: stop when the room reaches this"
        checked={vent.excheck}
        checkAction="excheck"
        value={vent.external}
        setAction="set_external_pressure"
        resetAction="reset_external_pressure"
        isDefault={vent.extdefault} />
      <PressureCheck
        act={act}
        vent={vent}
        label="Pipe limit"
        title="Internal: stop when the pipe falls to this"
        checked={vent.incheck}
        checkAction="incheck"
        value={vent.internal}
        setAction="set_internal_pressure"
        resetAction="reset_internal_pressure"
        isDefault={vent.intdefault} />
    </div>
  );
};

const Scrubbers = props => {
  const { state } = props;
  const { data } = useBackend(props);
  const scrubbers = data.scrubbers || [];
  if (!scrubbers.length) {
    return <Box color="label">No scrubbers on this alarm.</Box>;
  }
  return scrubbers.map(scrubber => (
    <Scrubber key={scrubber.id_tag} state={state} scrubber={scrubber} />
  ));
};

export const FilterChips = props => {
  const { filters = [], onToggle } = props;
  return filters.map(filter => (
    <Button
      key={filter.gas_id}
      color={filter.enabled ? gasColor(filter.gas_id) : 'transparent'}
      title={filter.gas_name}
      onClick={() => onToggle(filter.gas_id)}>
      <Icon name={filter.enabled ? 'check' : 'times'} mr={0.5} />
      {gasLabel(filter.gas_id, filter.gas_name)}
    </Button>
  ));
};

const Scrubber = props => {
  const { scrubber } = props;
  const { act } = useBackend(props);
  const id_tag = scrubber.id_tag;
  return (
    <div className="Atmos__device">
      <Box>
        <b>{decodeHtmlEntities(scrubber.long_name)}</b>
        <Button
          style={{ float: 'right' }}
          icon="power-off"
          selected={scrubber.power}
          content={scrubber.power ? 'On' : 'Off'}
          onClick={() => act('power', {
            id_tag,
            val: Number(!scrubber.power),
          })} />
      </Box>
      <Box mt={0.5}>
        <Button
          icon="filter"
          selected={scrubber.scrubbing}
          content="Scrubbing"
          onClick={() => !scrubber.scrubbing && act('scrubbing', {
            id_tag,
            val: 1,
          })} />
        <Button
          icon="sign-in-alt"
          color={scrubber.scrubbing ? 'default' : 'danger'}
          content="Siphoning"
          onClick={() => scrubber.scrubbing && act('scrubbing', {
            id_tag,
            val: 0,
          })} />
        <Button.Checkbox
          checked={scrubber.widenet}
          content="Wide range"
          onClick={() => act('widenet', {
            id_tag,
            val: Number(!scrubber.widenet),
          })} />
      </Box>
      <Box mt={0.5}>
        {scrubber.scrubbing && (
          <FilterChips
            filters={scrubber.filter_types}
            onToggle={gas_id => act('toggle_filter', {
              id_tag,
              val: gas_id,
            })} />
        ) || (
          <Box color="average">Siphoning everything, filters unused.</Box>
        )}
      </Box>
    </div>
  );
};

const Modes = props => {
  const { act, data } = useBackend(props);
  const modes = data.modes || [];
  return (
    <div className="Atmos__modes">
      {modes.map(mode => {
        const [title, ...rest] = mode.name.split(' - ');
        return (
          <div
            key={mode.mode}
            className={'Atmos__mode'
              + (mode.selected ? ' Atmos__mode--selected' : '')
              + (mode.danger ? ' Atmos__mode--danger' : '')}
            onClick={() => act('mode', { mode: mode.mode })}>
            <Box bold>
              {!!mode.selected && <Icon name="check" mr={1} />}
              {title}
            </Box>
            <Box fontSize="11px" color="label">{rest.join(' - ')}</Box>
          </div>
        );
      })}
    </div>
  );
};

const LIMITS = [
  ['min2', 'bad', 'Danger below'],
  ['min1', 'average', 'Caution below'],
  ['max1', 'average', 'Caution above'],
  ['max2', 'bad', 'Danger above'],
];

const Thresholds = props => {
  const { act, data } = useBackend(props);
  const thresholds = data.thresholds || [];
  return (
    <Fragment>
      <Box color="label" mb={1}>
        Click a number to type it, or drag it. Below zero turns the limit
        off. Gas limits are partial pressures in kPa.
      </Box>
      <table className="Atmos__thresholds">
        <tr>
          <td />
          {LIMITS.map(limit => (
            <td key={limit[0]} className={'color-' + limit[1]}>
              {limit[2]}
            </td>
          ))}
        </tr>
        {thresholds.map(threshold => (
          <tr key={threshold.name}>
            <td className="color-label">{threshold.name}</td>
            {threshold.settings.map(setting => (
              <td key={setting.val}>
                <NumberInput
                  width="70px"
                  value={setting.selected}
                  minValue={-1}
                  maxValue={100000}
                  step={1}
                  stepPixelSize={4}
                  format={value => (value < 0 ? 'off' : toFixed(value, 2))}
                  onChange={(e, value) => act('threshold_set', {
                    env: setting.env,
                    var: setting.val,
                    value,
                  })} />
              </td>
            ))}
          </tr>
        ))}
      </table>
    </Fragment>
  );
};
