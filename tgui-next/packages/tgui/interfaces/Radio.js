import { map } from 'common/collections';
import { toFixed } from 'common/math';
import { Component } from 'inferno';
import { useBackend } from '../backend';
import { Input } from '../components';
import { RADIO_CHANNELS } from '../constants';

// hippie -- the radio as a handset: a backlit display with the frequency
// and the channel tuned, tuning buttons, switches and the encryption keys'
// channels as keys. Data and actions from code/game/objects/items/devices/
// radio/radio.dm, as before.

// A channel key's light, in the channel's colour when it's on
const keyLight = channel => {
  if (!channel.on) {
    return null;
  }
  const color = channel.color || '#31c35d';
  return {
    'background-color': color,
    'box-shadow': '0 0 6px ' + color,
  };
};

const Switch = props => {
  const { label, on, onClick } = props;
  return (
    <div
      className={'Radio__switch' + (on ? ' Radio__switch--on' : '')}
      onClick={onClick}>
      <div className="Radio__led" />
      <div className="Radio__toggle">
        <div className="Radio__knob" />
      </div>
      <div className="Radio__switchLabel">{label}</div>
    </div>
  );
};

export class Radio extends Component {
  constructor() {
    super();
    this.state = { typing: false };
  }

  render() {
    const { act, data } = useBackend(this.props);
    const {
      freqlock,
      frequency,
      listening,
      broadcasting,
      command,
      useCommand,
      subspace,
      subspaceSwitchable,
    } = data;
    const { typing } = this.state;
    const tuned = RADIO_CHANNELS.find(channel => channel.freq === frequency);
    const channels = map((value, key) => ({
      name: key,
      on: !!value,
      color: (RADIO_CHANNELS.find(c => c.name === key) || {}).color,
    }))(data.channels);
    const tune = adjust => act('frequency', { adjust });
    return (
      <div className="Radio">
        <div className="Radio__front">
          <div
            className="Radio__lcd"
            onClick={() => !freqlock && this.setState({ typing: true })}>
            {typing ? (
              <Input
                className="Radio__lcdInput"
                value={toFixed(frequency / 10, 1)}
                onChange={(e, value) => {
                  this.setState({ typing: false });
                  if (value) {
                    act('frequency', { tune: value });
                  }
                }} />
            ) : (
              <div className="Radio__digits">
                <span className="Radio__ghost">888.8</span>
                <span className="Radio__value">
                  {toFixed(frequency / 10, 1)}
                </span>
              </div>
            )}
            <div className="Radio__lcdLine">
              <span>{tuned ? tuned.name : 'kHz'}</span>
              {!!freqlock && <span className="Radio__lock">LOCK</span>}
            </div>
          </div>
          <div className="Radio__tuner">
            {[[-1, '«'], [-0.2, '‹'], [0.2, '›'], [1, '»']]
              .map(step => (
                <div
                  key={step[0]}
                  className={'Radio__tuneKey'
                    + (freqlock ? ' Radio__tuneKey--locked' : '')}
                  onClick={() => !freqlock && tune(step[0])}>
                  {step[1]}
                </div>
              ))}
          </div>
        </div>
        <div className="Radio__switches">
          <Switch
            label="Speaker"
            on={listening}
            onClick={() => act('listen')} />
          <Switch
            label="Mic"
            on={broadcasting}
            onClick={() => act('broadcast')} />
          {!!command && (
            <Switch
              label="Loud"
              on={useCommand}
              onClick={() => act('command')} />
          )}
          {!!subspaceSwitchable && (
            <Switch
              label="Subspace"
              on={subspace}
              onClick={() => act('subspace')} />
          )}
        </div>
        {!!subspace && (
          <div className="Radio__keys">
            <div className="Radio__keysLabel">Keys</div>
            {channels.length === 0 && (
              <div className="Radio__empty">No encryption keys</div>
            )}
            {channels.map(channel => (
              <div
                key={channel.name}
                className={'Radio__key' + (channel.on ? ' Radio__key--on' : '')}
                onClick={() => act('channel', { channel: channel.name })}>
                <span
                  className="Radio__keyLed"
                  style={keyLight(channel)} />
                {channel.name}
              </div>
            ))}
          </div>
        )}
      </div>
    );
  }
}
