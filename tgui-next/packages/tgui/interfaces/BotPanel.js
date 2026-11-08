import { useBackend } from '../backend';
import { Box, Button, Icon, Section } from '../components';

// hippie -- a bot's control panel: its sprite, name and what it's doing up
// top with the power switch, its settings as switches, steppers and choices,
// then the network and the personality card. Every button is the link the
// old page had (hippiestation/code/modules/tgui/bots_strip_tgui.dm).

const MODE_COLORS = {
  good: '#5ee08a',
  average: '#f5b84a',
  bad: '#ff6b6b',
};

const KIND_ICONS = {
  security: 'shield-alt',
  lasertag: 'crosshairs',
  janitor: 'broom',
  engineering: 'hammer',
  medical: 'first-aid',
  fire: 'fire-extinguisher',
  clown: 'grin-tongue-wink',
  generic: 'robot',
};

const Switch = props => {
  const { on, onClick, disabled } = props;
  return (
    <div
      className={'BotPanel__switch'
        + (on ? ' BotPanel__switch--on' : '')
        + (disabled ? ' BotPanel__switch--off' : '')}
      onClick={() => !disabled && onClick()}>
      <div className="BotPanel__knob" />
    </div>
  );
};

const Setting = props => {
  const { setting, act } = props;
  const send = params => params && act('topic', { params });
  let control;
  switch (setting.kind) {
    case 'toggle':
      control = (
        <Switch on={!!setting.value} onClick={() => send(setting.params)} />
      );
      break;
    case 'choice':
      control = (setting.options || []).map(option => (
        <Button
          key={option.label}
          content={option.label}
          selected={option.label === setting.value}
          onClick={() => send(option.params)} />
      ));
      break;
    case 'stepper': {
      const steps = setting.steps || [];
      const down = steps.filter(step => step.label[0] === '-');
      const up = steps.filter(step => step.label[0] !== '-');
      control = (
        <span className="BotPanel__stepper">
          {down.map(step => (
            <Button
              key={step.label}
              content={step.label}
              disabled={setting.value <= setting.min}
              onClick={() => send(step.params)} />
          ))}
          <span className="BotPanel__number">
            {setting.value}{setting.unit || ''}
          </span>
          {up.map(step => (
            <Button
              key={step.label}
              content={step.label}
              disabled={setting.value >= setting.max}
              onClick={() => send(step.params)} />
          ))}
        </span>
      );
      break;
    }
    default:
      control = <span>{setting.value}</span>;
  }
  return (
    <div className="BotPanel__row">
      <span className="BotPanel__label">{setting.label}</span>
      <span className="BotPanel__control">{control}</span>
    </div>
  );
};

const PAI_TEXT = {
  active: 'Active',
  inactive: 'Inactive',
  none: 'Not inserted',
  unavailable: 'Unavailable',
};

export const BotPanel = props => {
  const { act, data } = useBackend(props);
  const mode = data.mode || {};
  const settings = data.settings || [];
  const extra = data.extra || [];
  const kind = data.kind || 'generic';
  return (
    <div className={'BotPanel BotPanel--' + kind}>
      <div className="BotPanel__head">
        <div className="BotPanel__sprite">
          {data.sprite
            ? <img src={data.sprite} />
            : <Icon name={KIND_ICONS[kind] || 'robot'} size={2} />}
        </div>
        <div className="BotPanel__who">
          <div className="BotPanel__name">{data.name}</div>
          <div className="BotPanel__model">
            <Icon name={KIND_ICONS[kind] || 'robot'} /> {data.model}
          </div>
          <div style={{ color: MODE_COLORS[mode.mode_color] }}>
            {mode.mode}
          </div>
        </div>
        <div className="BotPanel__power">
          <Switch on={!!data.on}
            onClick={() => act('topic', { params: 'power=1' })} />
          <div className="BotPanel__powerText">{data.on ? 'ON' : 'OFF'}</div>
        </div>
      </div>
      <div className="BotPanel__badges">
        <span className={'BotPanel__badge'
          + (data.locked ? '' : ' BotPanel__badge--warn')}>
          <Icon name={data.locked ? 'lock' : 'lock-open'} />
          {data.locked ? ' Controls locked' : ' Controls unlocked'}
        </span>
        <span className={'BotPanel__badge'
          + (data.open ? ' BotPanel__badge--warn' : '')}>
          <Icon name="screwdriver" />
          {data.open ? ' Panel open' : ' Panel closed'}
        </span>
        {!!data.emagged && (
          <span className="BotPanel__badge BotPanel__badge--bad">
            <Icon name="bolt" /> Compromised
          </span>
        )}
      </div>
      {extra.map(item => (
        <div key={item.label} className="BotPanel__row BotPanel__row--extra">
          <span className="BotPanel__label">{item.label}</span>
          <span className="BotPanel__control">
            {item.value}
            {!!item.params && (
              <Button ml={1} icon="eject" content={item.button}
                onClick={() => act('topic', { params: item.params })} />
            )}
          </span>
        </div>
      ))}
      {!data.can_behave && (
        <div className="BotPanel__locked">
          <Icon name="id-card" /> Swipe an ID with access to change how it
          behaves.
        </div>
      )}
      {settings.length > 0 && (
        <Section title="Behaviour">
          {settings.map(setting => (
            <Setting key={setting.label} setting={setting} act={act} />
          ))}
        </Section>
      )}
      {(data.safety || data.remote !== undefined || data.pai) && (
        <Section title="Network">
          {!!data.safety && (
            <div className="BotPanel__row">
              <span className="BotPanel__label">Harm prevention safety</span>
              <span className="BotPanel__control">
                <Button
                  content={data.safety === 'danger' ? 'DANGER' : 'Engaged'}
                  color={data.safety === 'danger' ? 'bad' : null}
                  onClick={() => act('topic',
                    { params: 'operation=hack' })} />
              </span>
            </div>
          )}
          {data.remote !== undefined && data.remote !== null && (
            <div className="BotPanel__row">
              <span className="BotPanel__label">Remote control radio</span>
              <span className="BotPanel__control">
                <Switch on={!!data.remote}
                  onClick={() => act('topic',
                    { params: 'operation=remote' })} />
              </span>
            </div>
          )}
          {!!data.pai && (
            <div className="BotPanel__row">
              <span className="BotPanel__label">Personality card</span>
              <span className="BotPanel__control">
                {PAI_TEXT[data.pai]}
                {(data.pai === 'active' || data.pai === 'inactive') && (
                  <Button ml={1} icon="eject" content="Eject"
                    onClick={() => act('topic',
                      { params: 'operation=ejectpai' })} />
                )}
              </span>
            </div>
          )}
        </Section>
      )}
    </div>
  );
};
