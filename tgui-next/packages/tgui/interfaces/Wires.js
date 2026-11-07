import { useBackend } from '../backend';
import { Icon } from '../components';

// hippie -- the wiring panel as a maintenance panel: each wire a cable
// between two terminals (cut ones with a gap, an attached assembly as a box
// on the cable), the tool for each beside it, and the machine's lights below.
// Data and actions from code/datums/wires/_wires.dm, as before.

// A status line's light: lit, dark, or not a light at all
const lightOf = text => {
  const lower = text.toLowerCase();
  if (/\b(off|disconnected|disabled|dark|unpowered|look up)\b/.test(lower)) {
    return 'off';
  }
  if (/\b(on|lit|fallen|active|enabled|powered|flashing|blinking)\b/
    .test(lower)) {
    return 'on';
  }
  return null;
};

const Tool = props => (
  <div className="Wires__tool" onClick={props.onClick}>
    <Icon name={props.icon} mr={0.5} />
    {props.label}
  </div>
);

export const Wires = props => {
  const { act, data } = useBackend(props);
  const wires = data.wires || [];
  const statuses = data.status || [];
  return (
    <div className="Wires">
      <div className="Wires__panel">
        <span className="Wires__screw Wires__screw--tl" />
        <span className="Wires__screw Wires__screw--tr" />
        <span className="Wires__screw Wires__screw--bl" />
        <span className="Wires__screw Wires__screw--br" />
        {wires.map(wire => (
          <div key={wire.color} className="Wires__row">
            <div className="Wires__name">
              {wire.color}
              {!!wire.wire && (
                <div className="Wires__purpose">{wire.wire}</div>
              )}
            </div>
            <div className="Wires__run">
              <span className="Wires__terminal" />
              {wire.cut ? (
                <div className="Wires__cable Wires__cable--cut">
                  <span
                    className="Wires__half Wires__half--left"
                    style={{ 'background-color': wire.color }} />
                  <span
                    className="Wires__half Wires__half--right"
                    style={{ 'background-color': wire.color }} />
                </div>
              ) : (
                <div className="Wires__cable">
                  <span
                    className="Wires__whole"
                    style={{ 'background-color': wire.color }} />
                </div>
              )}
              {!!wire.attached && (
                <span className="Wires__assembly">
                  <Icon name="broadcast-tower" />
                </span>
              )}
              <span className="Wires__terminal" />
            </div>
            <div className="Wires__tools">
              <Tool
                icon="cut"
                label={wire.cut ? 'Mend' : 'Cut'}
                onClick={() => act('cut', { wire: wire.color })} />
              <Tool
                icon="bolt"
                label="Pulse"
                onClick={() => act('pulse', { wire: wire.color })} />
              <Tool
                icon={wire.attached ? 'unlink' : 'link'}
                label={wire.attached ? 'Detach' : 'Attach'}
                onClick={() => act('attach', { wire: wire.color })} />
            </div>
          </div>
        ))}
      </div>
      {statuses.length > 0 && (
        <div className="Wires__lights">
          {statuses.map(status => {
            const light = lightOf(status);
            return (
              <div key={status} className="Wires__light">
                <span className={'Wires__lamp'
                  + (light ? ' Wires__lamp--' + light : '')} />
                {status}
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
};
