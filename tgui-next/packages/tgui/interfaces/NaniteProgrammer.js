import { useBackend } from '../backend';
import { Button, Dropdown, Input, NumberInput } from '../components';
import { CodeChip, DiskSlot, Key, Row } from './NaniteParts';

// hippie -- the programmer: the disk's program as one chip to set, its power
// switch, its codes as keyed chips you type into,
// its timers and its own settings. Data and actions as before
// (code/modules/research/nanites/nanite_programmer.dm).

const CODES = [
  ['activation', 'Activate', 'activation_code'],
  ['deactivation', 'Deactivate', 'deactivation_code'],
  ['kill', 'Kill', 'kill_code'],
  ['trigger', 'Trigger', 'trigger_code'],
];

const TIMERS = [
  ['Restart', 'timer_restart', 'set_restart_timer', false],
  ['Shutdown', 'timer_shutdown', 'set_shutdown_timer', false],
  ['Trigger repeat', 'timer_trigger', 'set_trigger_timer', true],
  ['Trigger delay', 'timer_trigger_delay', 'set_timer_trigger_delay', true],
];

const ExtraSetting = props => {
  const { act, setting } = props;
  const set = value => act('set_extra_setting', {
    target_setting: setting.name,
    value,
  });
  switch (setting.type) {
    case 'number':
      return (
        <NumberInput
          value={setting.value}
          width="64px"
          minValue={setting.min}
          maxValue={setting.max}
          unit={setting.unit}
          onChange={(e, value) => set(value)} />
      );
    case 'text':
      return (
        <Input
          value={setting.value}
          width="160px"
          onInput={(e, value) => set(value)} />
      );
    case 'type':
      return (
        <Dropdown
          over
          selected={setting.value}
          width="140px"
          options={setting.types}
          onSelected={value => set(value)} />
      );
    case 'boolean':
      return (
        <Button
          content={setting.value ? setting.true_text : setting.false_text}
          selected={setting.value}
          onClick={() => act('set_extra_setting', {
            target_setting: setting.name,
          })} />
      );
  }
  return null;
};

export const NaniteProgrammer = props => {
  const { act, data } = useBackend(props);
  const {
    has_disk,
    has_program,
    name,
    desc,
    use_rate,
    can_trigger,
    trigger_cost,
    trigger_cooldown,
    activated,
  } = data;
  const extra = data.extra_settings || [];
  return (
    <div className="Nanites">
      <div className="Nanites__bar">
        <div className="Nanites__title">Nanite Programmer</div>
      </div>
      <div style={{ padding: '8px 10px 0' }}>
        <DiskSlot
          has_disk={has_disk}
          has_program={has_program}
          disk={{ name: 'Program disk', desc: '' }}>
          {!!has_disk && (
            <Key icon="eject" title="Eject" onClick={() => act('eject')} />
          )}
        </DiskSlot>
      </div>
      {!has_program ? (
        <div className="Nanites__notice">
          {has_disk ? 'The disk is blank' : 'Insert a program disk'}
        </div>
      ) : (
        <div className="Nanites__scroll">
          <div className="Nanites__detailName">
            {name}
            <div
              className={'Nanites__power'
                + (activated ? ' Nanites__power--on' : '')}
              style={{ 'margin-left': 'auto' }}
              onClick={() => act('toggle_active')}>
              <div className="Nanites__powerKnob" />
              {activated ? 'Starts active' : 'Starts inactive'}
            </div>
          </div>
          <div className="Nanites__desc">{desc}</div>
          <div className="Nanites__stats">
            <div className="Nanites__stat">Use rate<b>{use_rate}/s</b></div>
            {!!can_trigger && (
              <div className="Nanites__stat">
                Trigger cost<b>{trigger_cost}</b>
              </div>
            )}
            {!!can_trigger && (
              <div className="Nanites__stat">
                Cooldown<b>{trigger_cooldown} s</b>
              </div>
            )}
          </div>
          <div className="Nanites__heading">Codes</div>
          <div className="Nanites__codes">
            {CODES.filter(code => code[0] !== 'trigger' || can_trigger)
              .map(code => (
                <CodeChip key={code[0]} kind={code[0]} label={code[1]}>
                  <NumberInput
                    value={data[code[2]]}
                    minValue={0}
                    maxValue={9999}
                    width="100%"
                    format={value => (value
                      ? String(value).padStart(4, '0')
                      : '----')}
                    onChange={(e, value) => act('set_code', {
                      target_code: code[0],
                      code: value,
                    })} />
                </CodeChip>
              ))}
          </div>
          <div className="Nanites__heading">Timers</div>
          <div className="Nanites__rows">
            {TIMERS.filter(timer => !timer[3] || can_trigger).map(timer => (
              <Row key={timer[1]} label={timer[0]}>
                <NumberInput
                  value={data[timer[1]]}
                  unit="s"
                  width="60px"
                  minValue={0}
                  maxValue={3600}
                  onChange={(e, value) => act(timer[2], { delay: value })} />
              </Row>
            ))}
          </div>
          {extra.length > 0 && (
            <div>
              <div className="Nanites__heading">Settings</div>
              <div className="Nanites__rows">
                {extra.map(setting => (
                  <Row key={setting.name} label={setting.name}>
                    <ExtraSetting act={act} setting={setting} />
                  </Row>
                ))}
              </div>
            </div>
          )}
        </div>
      )}
    </div>
  );
};
