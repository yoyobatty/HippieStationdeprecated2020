import { useBackend } from '../backend';
import { AnimatedNumber, Icon, NumberInput } from '../components';

// hippie -- Hippie's chemistry machines as lab instruments: the beaker as a
// glass vessel with its reagents in layers of their own colours, and each
// machine's control beside it (a pressure gauge, a radiation source, a
// bluespace field, a centrifuge rotor). Data and actions from
// hippiestation/code/modules/reagents/chemistry/machinery/lcasschem.dm.

const Vessel = props => {
  const { act, data } = props;
  const {
    isBeakerLoaded,
    beakerCurrentVolume = 0,
    beakerMaxVolume = 1,
    beakerContents = [],
  } = data;
  if (!isBeakerLoaded) {
    return (
      <div className="ChemInst__vesselBox">
        <div className="ChemInst__vessel ChemInst__vessel--empty">
          <span className="ChemInst__none">No beaker</span>
        </div>
      </div>
    );
  }
  const total = Math.max(beakerCurrentVolume, 0.01);
  const fill = Math.min(1, beakerCurrentVolume / beakerMaxVolume);
  return (
    <div className="ChemInst__vesselBox">
      <div className="ChemInst__vessel">
        <div className="ChemInst__liquid" style={{ height: fill * 100 + '%' }}>
          {beakerContents.map(reagent => (
            <div
              key={reagent.name}
              className="ChemInst__layer"
              style={{
                'height': (reagent.volume / total) * 100 + '%',
                'background-color': reagent.color || '#7fb3d5',
              }} />
          ))}
        </div>
        <div className="ChemInst__marks" />
      </div>
      <div className="ChemInst__volume">
        <AnimatedNumber value={Math.round(beakerCurrentVolume)} />
        {' / ' + beakerMaxVolume + 'u'}
      </div>
      <div className="ChemInst__eject" onClick={() => act('eject')}>
        <Icon name="eject" mr={0.5} />
        Eject
      </div>
    </div>
  );
};

const Contents = props => {
  const { beakerContents = [], isBeakerLoaded } = props.data;
  if (!isBeakerLoaded) {
    return null;
  }
  return (
    <div className="ChemInst__contents">
      {beakerContents.length === 0 && (
        <div className="ChemInst__dim">Empty</div>
      )}
      {beakerContents.map(reagent => (
        <div key={reagent.name} className="ChemInst__reagent">
          <span
            className="ChemInst__chip"
            style={{ 'background-color': reagent.color || '#7fb3d5' }} />
          <span className="ChemInst__reagentName">{reagent.name}</span>
          <span className="ChemInst__dim">
            {reagent.volume.toFixed(1)}u
          </span>
        </div>
      ))}
    </div>
  );
};

const Power = props => {
  const { act, on, disabled } = props;
  return (
    <div
      className={'ChemInst__power' + (on ? ' ChemInst__power--on' : '')
        + (disabled ? ' ChemInst__power--disabled' : '')}
      onClick={() => !disabled && act('power')}>
      <span className="ChemInst__powerLed" />
      <Icon name="power-off" mr={0.5} />
      {on ? 'On' : 'Off'}
    </div>
  );
};

// What the beaker reads, or a dash with no beaker in
const beakerReading = (data, reading) => (data.isBeakerLoaded ? reading : '-');

const Readout = props => (
  <div className="ChemInst__readout">
    <span className="ChemInst__readLabel">{props.label}</span>
    <span className="ChemInst__readValue">{props.children}</span>
  </div>
);

const Instrument = props => {
  const { act, data, title, children } = props;
  return (
    <div className="ChemInst">
      <Vessel act={act} data={data} />
      <div className="ChemInst__panel">
        <div className="ChemInst__head">
          <span className="ChemInst__title">{title}</span>
          <Power
            act={act}
            on={!!data.isActive}
            disabled={props.needsBeaker && !data.isBeakerLoaded} />
        </div>
        {children}
        <Contents data={data} />
      </div>
    </div>
  );
};

// A dial from 0 to max, the needle at value
const Gauge = props => {
  const { value, max, unit } = props;
  const angle = -120 + 240 * Math.min(1, Math.max(0, value / max));
  const ticks = [];
  for (let i = 0; i <= 8; i++) {
    const a = (-120 + 30 * i) * Math.PI / 180;
    ticks.push(
      <line
        key={i}
        x1={50 + Math.sin(a) * 34}
        y1={50 - Math.cos(a) * 34}
        x2={50 + Math.sin(a) * 40}
        y2={50 - Math.cos(a) * 40}
        stroke={i >= 7 ? '#e03131' : '#9aa5b1'}
        strokeWidth="2" />,
    );
  }
  return (
    <div className="ChemInst__gauge">
      <svg viewBox="0 0 100 100">
        <circle cx="50" cy="50" r="46" fill="#15191d" stroke="#59616a"
          strokeWidth="3" />
        {ticks}
        <line
          x1="50"
          y1="50"
          x2={50 + Math.sin(angle * Math.PI / 180) * 36}
          y2={50 - Math.cos(angle * Math.PI / 180) * 36}
          stroke="#ff6b3d"
          strokeWidth="3"
          strokeLinecap="round" />
        <circle cx="50" cy="50" r="5" fill="#c8cdd2" />
      </svg>
      <div className="ChemInst__gaugeValue">
        <AnimatedNumber value={Math.round(value)} />
        {' ' + unit}
      </div>
    </div>
  );
};

export const ChemPressure = props => {
  const { act, data } = useBackend(props);
  return (
    <Instrument act={act} data={data} title="Pressure chamber">
      <Gauge value={data.internalPressure || 0} max={100} unit="bar" />
      <Readout label="Beaker">
        {beakerReading(data, Math.round(data.currentPressure || 0) + ' bar')}
      </Readout>
    </Instrument>
  );
};

export const ChemRadioactive = props => {
  const { act, data } = useBackend(props);
  const active = !!data.isActive;
  return (
    <Instrument act={act} data={data} title="Radiation source" needsBeaker>
      <div className="ChemInst__center">
        <div className={'ChemInst__trefoil'
          + (active ? ' ChemInst__trefoil--on' : '')}>
          <Icon name="radiation" />
        </div>
      </div>
      <Readout label="Target">
        <NumberInput
          width="56px"
          value={data.targetRadioactivity}
          minValue={0}
          maxValue={20}
          step={1}
          stepPixelSize={8}
          onChange={(e, value) => act('irradiate', { target: value })} />
      </Readout>
      <Readout label="Uranium">
        <div className="ChemInst__bar">
          <div
            className="ChemInst__barFill ChemInst__barFill--uranium"
            style={{ width: Math.min(100, data.materialAmount / 500) + '%' }} />
        </div>
        <span className="ChemInst__barText">{data.materialAmount}</span>
      </Readout>
      <Readout label="Beaker">
        {beakerReading(data, Math.round(data.currentRadioactivity || 0))}
      </Readout>
    </Instrument>
  );
};

export const ChemBluespace = props => {
  const { act, data } = useBackend(props);
  const active = !!data.isActive;
  const pips = [];
  for (let i = 0; i < 10; i++) {
    pips.push(
      <span
        key={i}
        className={'ChemInst__pip'
          + (i < data.crystalAmount ? ' ChemInst__pip--on' : '')} />,
    );
  }
  return (
    <Instrument act={act} data={data} title="Bluespace field" needsBeaker>
      <div className="ChemInst__center">
        <div className={'ChemInst__field'
          + (active ? ' ChemInst__field--on' : '')} />
      </div>
      <Readout label="Intensity">
        <NumberInput
          width="56px"
          value={data.intensity}
          minValue={0}
          maxValue={30}
          step={1}
          stepPixelSize={6}
          onChange={(e, value) => act('bluespace', { target: value })} />
      </Readout>
      <Readout label="Crystals">{pips}</Readout>
      <Readout label="Beaker">
        {beakerReading(data, data.isBluespaced ? 'Bluespaced' : 'Stable')}
      </Readout>
    </Instrument>
  );
};

export const ChemCentrifuge = props => {
  const { act, data } = useBackend(props);
  const active = !!data.isActive;
  return (
    <Instrument act={act} data={data} title="Centrifuge">
      <div className="ChemInst__center">
        <div className={'ChemInst__rotor'
          + (active ? ' ChemInst__rotor--on' : '')}>
          <span /><span /><span />
        </div>
      </div>
      <Readout label="Time left">
        {Math.max(0, Math.round(data.timeRemaining || 0)) + 's'}
      </Readout>
    </Instrument>
  );
};
