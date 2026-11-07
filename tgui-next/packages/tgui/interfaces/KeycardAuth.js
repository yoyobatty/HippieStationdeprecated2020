import { useBackend } from '../backend';
import { Icon } from '../components';
import { SecKey } from './BrigTimer';

// hippie -- the keycard authentication device: what's in force now, a
// guarded switch for each event, "awaiting second swipe" while a request is
// out, and the event to confirm when another device asks. Data and actions
// from code/modules/security_levels/keycard_authentication.dm, as before.

const EVENTS = [
  ['red_alert', 'Red Alert', 'exclamation-triangle'],
  ['emergency_maint', 'Emergency Maint Access', 'wrench'],
  ['bsa_unlock', 'BSA Unlock', 'meteor'],
];

export const KeycardAuth = props => {
  const { act, data } = useBackend(props);
  const { waiting, auth_required } = data;
  let screen = 'Ready';
  let screenClass = '';
  if (waiting) {
    screen = 'Awaiting second swipe';
    screenClass = ' Keycard__screen--blink';
  } else if (auth_required) {
    screen = 'Confirm: ' + auth_required;
    screenClass = ' Keycard__screen--alert';
  }
  return (
    <div className="SecDev">
      <div className={'Keycard__screen' + screenClass}>{screen}</div>
      {auth_required && !waiting ? (
        <SecKey
          className="Keycard__confirm"
          onClick={() => act('auth_swipe')}>
          <Icon name="id-card" mr={1} />
          Swipe to confirm
        </SecKey>
      ) : (
        EVENTS.map(event => (
          <div key={event[0]} className="Keycard__event">
            <span className={'Keycard__lamp'
              + (data[event[0]] ? ' Keycard__lamp--on' : '')} />
            <span className="Keycard__name">
              <Icon name={event[2]} mr={1} />
              {event[1]}
            </span>
            <span className="Keycard__state">
              {data[event[0]] ? 'In force' : ''}
            </span>
            <SecKey
              className="Keycard__guard"
              disabled={!!waiting}
              onClick={() => act(event[0])}>
              Request
            </SecKey>
          </div>
        ))
      )}
    </div>
  );
};
