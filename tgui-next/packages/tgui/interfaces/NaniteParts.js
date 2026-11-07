import { Component } from 'inferno';
import { Icon } from '../components';

// hippie -- the pieces the nanite windows share
// (styles/components/Nanites.scss): the swarm meter, program chips and a
// program's
// details, codes, the disk slot, and a key (with an armed second click for the
// dangerous ones).

export const Key = props => {
  const { icon, content, on, danger, disabled, onClick, title } = props;
  return (
    <div
      className={'Nanites__key'
        + (on ? ' Nanites__key--on' : '')
        + (danger ? ' Nanites__key--danger' : '')
        + (disabled ? ' Nanites__key--disabled' : '')}
      title={title}
      onClick={disabled ? null : onClick}>
      {!!icon && <Icon name={icon} />}
      {content}
    </div>
  );
};

// A key that needs a second click within 3 s
export class ConfirmKey extends Component {
  constructor() {
    super();
    this.state = { armed: false };
  }

  componentWillUnmount() {
    clearTimeout(this.timer);
  }

  render() {
    const { icon, content, armedContent, onClick } = this.props;
    const { armed } = this.state;
    return (
      <div
        className={'Nanites__key Nanites__key--danger'
          + (armed ? ' Nanites__key--armed' : '')}
        onClick={() => {
          if (armed) {
            clearTimeout(this.timer);
            this.setState({ armed: false });
            onClick();
            return;
          }
          this.setState({ armed: true });
          this.timer = setTimeout(() => this.setState({ armed: false }), 3000);
        }}>
        {!!icon && <Icon name={icon} />}
        {armed ? (armedContent || 'Confirm') : content}
      </div>
    );
  }
}

export const SwarmMeter = props => {
  const { volume = 0, max = 500, safety = 0, regen } = props;
  const top = Math.max(max, 1);
  const pct = Math.max(0, Math.min(100, volume / top * 100));
  const safetyPct = Math.max(0, Math.min(100, safety / top * 100));
  const low = volume <= safety;
  return (
    <div>
      <div className="Nanites__meter">
        <div
          className={'Nanites__fill' + (low ? ' Nanites__fill--low' : '')}
          style={{ width: pct + '%' }} />
        <div
          className="Nanites__safety"
          title={'Safety threshold: ' + safety}
          style={{ left: safetyPct + '%' }} />
        <div className="Nanites__meterText">
          {Math.round(volume)} / {max}
        </div>
      </div>
      <div className="Nanites__meterLegend">
        {regen !== undefined && (
          <span className="Nanites__legendGrowth">+{regen}/s</span>
        )}
        <span className="Nanites__legendSafety">safety {safety}</span>
        {low && <span className="Nanites__legendSafety">programs halted</span>}
      </div>
    </div>
  );
};

export const ProgramChip = props => {
  const { program, selected, onClick, onRemove } = props;
  const known = program.activated !== undefined;
  return (
    <div
      className={'Nanites__chip' + (selected ? ' Nanites__chip--selected' : '')}
      onClick={onClick}>
      {known && (
        <div className={'Nanites__chipLed'
          + (program.activated ? ' Nanites__chipLed--on' : '')} />
      )}
      <div className="Nanites__chipName">{program.name}</div>
      <div className="Nanites__chipMeta">
        {program.use_rate !== undefined && program.use_rate + '/s'}
        {!!program.can_trigger && <Icon name="bolt" title="Triggered" />}
      </div>
      {!!onRemove && (
        <div
          className="Nanites__chipRemove"
          title="Remove"
          onClick={e => {
            e.stopPropagation();
            onRemove();
          }}>
          <Icon name="times" />
        </div>
      )}
    </div>
  );
};

export const CodeChip = props => {
  const { kind, label, value, children } = props;
  return (
    <div className={'Nanites__code Nanites__code--' + kind}>
      <div className="Nanites__codeLabel">{label}</div>
      <div className={'Nanites__codeValue'
        + (!children && !value ? ' Nanites__codeValue--unset' : '')}>
        {children || (value ? String(value).padStart(4, '0') : '----')}
      </div>
    </div>
  );
};

const settingText = setting => {
  switch (setting.type) {
    case 'number':
      return setting.value + (setting.unit || '');
    case 'boolean':
      return setting.value ? setting.true_text : setting.false_text;
    default:
      return setting.value;
  }
};

const seconds = value => (value ? value + ' s' : 'off');

// What's known of a program: the chamber shows more the better it scans, the
// cloud and disks show everything
export const ProgramDetail = props => {
  const { program, children, rules } = props;
  if (!program) {
    return (
      <div className="Nanites__notice">Pick a program</div>
    );
  }
  const extra = program.extra_settings || [];
  const hasCodes = program.activation_code !== undefined;
  const hasTimers = program.timer_restart !== undefined;
  return (
    <div>
      <div className="Nanites__detailName">
        {program.name}
        {program.activated !== undefined && (
          <span className={'Nanites__status'
            + (program.activated ? ' Nanites__status--on' : '')}>
            {program.activated ? 'Active' : 'Inactive'}
          </span>
        )}
      </div>
      <div className="Nanites__desc">{program.desc}</div>
      {program.use_rate !== undefined && (
        <div className="Nanites__stats">
          <div className="Nanites__stat">
            Use rate<b>{program.use_rate}/s</b>
          </div>
          {!!program.can_trigger && (
            <div className="Nanites__stat">
              Trigger cost<b>{program.trigger_cost}</b>
            </div>
          )}
          {!!program.can_trigger && (
            <div className="Nanites__stat">
              Cooldown<b>{program.trigger_cooldown} s</b>
            </div>
          )}
        </div>
      )}
      {hasCodes && (
        <div>
          <div className="Nanites__heading">Codes</div>
          <div className="Nanites__codes">
            <CodeChip
              kind="activation"
              label="Activate"
              value={program.activation_code} />
            <CodeChip
              kind="deactivation"
              label="Deactivate"
              value={program.deactivation_code} />
            <CodeChip kind="kill" label="Kill" value={program.kill_code} />
            {!!program.can_trigger && (
              <CodeChip
                kind="trigger"
                label="Trigger"
                value={program.trigger_code} />
            )}
          </div>
        </div>
      )}
      {hasTimers && (
        <div>
          <div className="Nanites__heading">Timers</div>
          <div className="Nanites__rows">
            <Row label="Restart" value={seconds(program.timer_restart)} />
            <Row label="Shutdown" value={seconds(program.timer_shutdown)} />
            {!!program.can_trigger && (
              <Row
                label="Trigger repeat"
                value={seconds(program.timer_trigger)} />
            )}
            {!!program.can_trigger && (
              <Row
                label="Trigger delay"
                value={seconds(program.timer_trigger_delay)} />
            )}
          </div>
        </div>
      )}
      {extra.length > 0 && (
        <div>
          <div className="Nanites__heading">Settings</div>
          <div className="Nanites__rows">
            {extra.map(setting => (
              <Row
                key={setting.name}
                label={setting.name}
                value={settingText(setting)} />
            ))}
          </div>
        </div>
      )}
      {rules}
      {children}
    </div>
  );
};

export const Row = props => (
  <div className="Nanites__row">
    <div className="Nanites__rowLabel">{props.label}</div>
    <div className="Nanites__rowValue">{props.value}{props.children}</div>
  </div>
);

export const DiskSlot = props => {
  const { has_disk, has_program, disk, children } = props;
  return (
    <div className="Nanites__disk">
      <div className={'Nanites__diskIcon'
        + (has_program ? '' : ' Nanites__diskIcon--empty')}>
        <Icon name="save" />
      </div>
      <div className="Nanites__diskText">
        {has_disk ? (
          has_program ? (
            <b>{disk.name}</b>
          ) : (
            <b>Blank disk</b>
          )
        ) : (
          <b>No disk</b>
        )}
        {has_disk && has_program && !!disk.desc && (
          <span title={disk.desc}>
            {disk.desc.length > 60
              ? disk.desc.substring(0, 58) + '...'
              : disk.desc}
          </span>
        )}
      </div>
      {children}
    </div>
  );
};
