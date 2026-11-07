import { useBackend } from '../backend';
import { Input, NumberInput } from '../components';
import { Key } from './NaniteParts';

// hippie -- the nanite remote as a handheld: a screen with the program name,
// the code (and the relay code or message), the
// mode keys, and the saved settings. Data and actions as before
// (code/modules/research/nanites/nanite_remote.dm).

const MODES = ['Off', 'Local', 'Targeted', 'Area', 'Relay'];

export const NaniteRemote = props => {
  const { act, data } = useBackend(props);
  const {
    code,
    locked,
    mode,
    program_name,
    relay_code,
    comms,
    message,
  } = data;
  const saved = data.saved_settings || [];
  if (locked) {
    return (
      <div className="NaniteRemote">
        <div
          className="NaniteRemote__screen"
          style={{ 'text-align': 'center', padding: '24px 0' }}>
          LOCKED
        </div>
      </div>
    );
  }
  return (
    <div className="NaniteRemote">
      <div className="NaniteRemote__screen">
        <div className="NaniteRemote__screenTop">
          <span>{comms ? 'COMM' : 'SIGNAL'} - {mode.toUpperCase()}</span>
          {mode === 'Relay' && (
            <span className="NaniteRemote__screenRight">
              RELAY{' '}
              <NumberInput
                value={relay_code}
                minValue={0}
                maxValue={9999}
                width="44px"
                step={1}
                stepPixelSize={2}
                onChange={(e, value) => act('set_relay_code', {
                  code: value,
                })} />
            </span>
          )}
        </div>
        <div className="NaniteRemote__code">
          <NumberInput
            value={code}
            minValue={0}
            maxValue={9999}
            width="100%"
            step={1}
            stepPixelSize={2}
            format={value => String(value).padStart(4, '0')}
            onChange={(e, value) => act('set_code', { code: value })} />
        </div>
        <div className="NaniteRemote__name">
          <Input
            value={program_name}
            maxLength={14}
            width="100%"
            placeholder="Name"
            onChange={(e, value) => act('update_name', { name: value })} />
        </div>
      </div>
      <div className="NaniteRemote__modes">
        {MODES.map(key => (
          <div
            key={key}
            className={'NaniteRemote__mode'
              + (mode === key ? ' NaniteRemote__mode--on' : '')}
            onClick={() => act('select_mode', { mode: key })}>
            {key}
          </div>
        ))}
      </div>
      {!!comms && (
        <div className="NaniteRemote__fields">
          <Input
            value={message}
            width="100%"
            placeholder="Message"
            onChange={(e, value) => act('set_message', { value })} />
        </div>
      )}
      <div className="NaniteRemote__fields">
        <Key icon="save" content="Save" onClick={() => act('save')} />
        <span style={{ 'margin-left': 'auto' }}>
          <Key icon="lock" content="Lock" onClick={() => act('lock')} />
        </span>
      </div>
      <div className="NaniteRemote__saved">
        {saved.length === 0 && (
          <div className="Nanites__desc" style={{ 'text-align': 'center' }}>
            No saved settings
          </div>
        )}
        {saved.map(setting => (
          <div key={setting.id} className="NaniteRemote__preset">
            <span className="NaniteRemote__presetName">{setting.name}</span>
            <span className="NaniteRemote__presetMeta">
              {setting.mode} {String(setting.code).padStart(4, '0')}
              {setting.mode === 'Relay' && ' > ' + setting.relay_code}
            </span>
            <Key
              icon="upload"
              title="Load"
              onClick={() => act('load', { save_id: setting.id })} />
            <Key
              icon="times"
              title="Delete"
              danger
              onClick={() => act('remove_save', {
                save_id: setting.id,
              })} />
          </div>
        ))}
      </div>
    </div>
  );
};
