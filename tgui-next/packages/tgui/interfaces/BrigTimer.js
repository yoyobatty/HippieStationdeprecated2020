import { useBackend } from '../backend';
import { Icon } from '../components';

// hippie -- the cell timer as a wall panel: the time left in big red
// digits, keys to set it, presets, Start/Stop and the flash. Data and
// actions from code/game/machinery/doors/brigdoors.dm, as before.

const pad2 = n => (n < 10 ? '0' : '') + n;

export const SecKey = props => {
  const { className, on, disabled, onClick, children } = props;
  return (
    <div
      className={'SecDev__key'
        + (on ? ' SecDev__key--on' : '')
        + (disabled ? ' SecDev__key--disabled' : '')
        + (className ? ' ' + className : '')}
      onClick={() => !disabled && onClick()}>
      {children}
    </div>
  );
};

export const BrigTimer = props => {
  const { act, data } = useBackend(props);
  const { timing, minutes, seconds, flash_charging } = data;
  const adjust = value => act('time', { adjust: value });
  return (
    <div className="SecDev">
      <div className={'BrigTimer__display'
        + (timing ? ' BrigTimer__display--running' : '')}>
        <span className="BrigTimer__ghost">88:88</span>
        <span className="BrigTimer__digits">
          {pad2(minutes) + ':' + pad2(seconds)}
        </span>
        <span className="BrigTimer__state">
          {timing ? 'Running' : 'Stopped'}
        </span>
      </div>
      <div className="SecDev__row">
        <SecKey onClick={() => adjust(-600)}>-1m</SecKey>
        <SecKey onClick={() => adjust(-100)}>-10s</SecKey>
        <SecKey onClick={() => adjust(100)}>+10s</SecKey>
        <SecKey onClick={() => adjust(600)}>+1m</SecKey>
      </div>
      <div className="SecDev__row">
        {['short', 'medium', 'long'].map(preset => (
          <SecKey
            key={preset}
            onClick={() => act('preset', { preset })}>
            {preset}
          </SecKey>
        ))}
      </div>
      <div className="SecDev__row">
        <SecKey
          className={timing ? 'SecDev__key--stop' : 'SecDev__key--go'}
          onClick={() => act(timing ? 'stop' : 'start')}>
          <Icon name={timing ? 'stop' : 'play'} mr={1} />
          {timing ? 'Stop' : 'Start'}
        </SecKey>
        <SecKey
          className="SecDev__key--flash"
          disabled={!!flash_charging}
          onClick={() => act('flash')}>
          <Icon name="lightbulb" mr={1} />
          {flash_charging ? 'Charging' : 'Flash'}
        </SecKey>
      </div>
    </div>
  );
};
