import { useBackend } from '../backend';
import { Icon } from '../components';

// hippie -- the abductors' machines in their own alien look: the agent
// console (Abductsoft 3000), the gland storage and the probing console. Data
// and actions from hippiestation/code/modules/antagonists/abductor/
// abductor_tgui.dm; every move goes through the machine's Topic().

const SUPPLY_ICONS = {
  baton: 'bolt',
  mind_device: 'brain',
  helmet: 'hard-hat',
  vest: 'user-shield',
  silencer: 'volume-mute',
  tool: 'flask',
  tongue: 'language',
};

const Pod = props => {
  const { icon, content, on, off, danger, onClick, title } = props;
  return (
    <div
      className={'Abductor__pod'
        + (on ? ' Abductor__pod--on' : '')
        + (off ? ' Abductor__pod--off' : '')
        + (danger ? ' Abductor__pod--danger' : '')}
      title={title}
      onClick={off ? null : onClick}>
      {!!icon && <Icon name={icon} />}
      {content}
    </div>
  );
};

const Missing = props => (
  <div className="Abductor__missing">
    <Icon name="exclamation-triangle" /> {props.children}
  </div>
);

export const AbductorConsole = props => {
  const { act, data } = useBackend(props);
  const supplies = data.supplies || [];
  return (
    <div className="Abductor">
      <div className="Abductor__head">
        <div className="Abductor__logo">ABDUCTSOFT 3000</div>
        <div className="Abductor__team">team {data.team}</div>
      </div>
      <div className="Abductor__body">
        {!data.has_experiment ? (
          <Missing>No experiment machine</Missing>
        ) : (
          <div className="Abductor__counters">
            <div className="Abductor__counter">
              <b>{data.points}</b>
              <span>samples</span>
            </div>
            <div className="Abductor__counter">
              <b>{data.credits}</b>
              <span>credits</span>
            </div>
          </div>
        )}
        <div className="Abductor__label">Supplies</div>
        <div className="Abductor__grid">
          {supplies.map(supply => (
            <div
              key={supply.id}
              className={'Abductor__supply'
                + (data.credits < supply.cost ? ' Abductor__supply--off' : '')}
              onClick={() => act('dispense', { id: supply.id })}>
              <Icon name={SUPPLY_ICONS[supply.id] || 'cube'} />
              <span className="Abductor__supplyName">{supply.name}</span>
              <span className="Abductor__supplyCost">{supply.cost}</span>
            </div>
          ))}
        </div>
        <div className="Abductor__label">Teleporter</div>
        {!data.has_pad ? (
          <Missing>No telepad</Missing>
        ) : (
          <div className="Abductor__row">
            <Pod
              icon="share"
              content="Send to the station"
              onClick={() => act('teleporter_send')} />
            <Pod
              icon="crosshairs"
              content={data.has_mark
                ? 'Retrieve ' + data.mark_name
                : 'Retrieve mark'}
              off={!data.has_mark}
              onClick={() => act('teleporter_retrieve')} />
          </div>
        )}
        <div className="Abductor__label">Agent vest</div>
        {!data.has_vest ? (
          <Missing>No vest linked</Missing>
        ) : (
          <div className="Abductor__row">
            <div className="Abductor__toggle">
              <div
                className={'Abductor__toggleSide'
                  + (data.vest_stealth ? ' Abductor__toggleSide--on' : '')}
                onClick={data.vest_stealth ? null : () => act('flip_vest')}>
                <Icon name="eye-slash" /> Stealth
              </div>
              <div
                className={'Abductor__toggleSide'
                  + (!data.vest_stealth ? ' Abductor__toggleSide--on' : '')}
                onClick={!data.vest_stealth ? null : () => act('flip_vest')}>
                <Icon name="fist-raised" /> Combat
              </div>
            </div>
            <Pod
              icon="user-secret"
              content={'Disguise (' + data.disguises + ')'}
              off={!data.disguises}
              onClick={() => act('select_disguise')} />
            <Pod
              icon={data.vest_locked ? 'lock' : 'lock-open'}
              content={data.vest_locked ? 'Locked' : 'Unlocked'}
              on={data.vest_locked}
              onClick={() => act('toggle_vest')} />
          </div>
        )}
      </div>
    </div>
  );
};

export const GlandDispenser = props => {
  const { act, data } = useBackend(props);
  const glands = data.glands || [];
  return (
    <div className="Abductor">
      <div className="Abductor__head">
        <div className="Abductor__logo">GLAND STORAGE</div>
      </div>
      <div className="Abductor__body">
        <div className="Abductor__glands">
          {glands.map(gland => (
            <div
              key={gland.index}
              className={'Abductor__gland'
                + (gland.amount > 0 ? '' : ' Abductor__gland--empty')}
              style={{
                'background-color': gland.color,
                'box-shadow': gland.amount > 0
                  ? '0 0 10px ' + gland.color
                  : 'none',
              }}
              title={gland.amount + ' left'}
              onClick={gland.amount > 0
                ? () => act('dispense', { index: gland.index })
                : null}>
              <span>{gland.amount}</span>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
};

export const AbductorExperiment = props => {
  const { act, data } = useBackend(props);
  const occupied = !!data.occupant;
  return (
    <div className="Abductor">
      <div className="Abductor__head">
        <div className="Abductor__logo">PROBING CONSOLE</div>
        <div className="Abductor__team">
          {data.points} samples / {data.credits} credits
        </div>
      </div>
      <div className="Abductor__body">
        <div className="Abductor__specimen">
          <div className="Abductor__picture">
            {occupied ? (
              <img src={data.picture} />
            ) : (
              <Icon name="user-alt-slash" />
            )}
          </div>
          <div className="Abductor__specimenText">
            <div className="Abductor__label">Specimen</div>
            <div className="Abductor__specimenName">
              {occupied ? data.occupant : 'None'}
            </div>
            {occupied && (
              <div className={'Abductor__state Abductor__state--'
                + data.occupant_state.toLowerCase()}>
                {data.occupant_state}
              </div>
            )}
          </div>
        </div>
        <div className="Abductor__row">
          <Pod
            icon="syringe"
            content="Probe"
            off={!occupied}
            onClick={() => act('experiment', { kind: 1 })} />
          <Pod
            icon="cut"
            content="Dissect"
            off={!occupied}
            onClick={() => act('experiment', { kind: 2 })} />
          <Pod
            icon="microscope"
            content="Analyze"
            off={!occupied}
            onClick={() => act('experiment', { kind: 3 })} />
        </div>
        <div className={'Abductor__result'
          + (data.result_kind ? ' Abductor__result--' + data.result_kind : '')}>
          {data.result}
        </div>
        <div className="Abductor__row Abductor__row--end">
          <Pod
            icon={data.open ? 'door-closed' : 'door-open'}
            content={data.open ? 'Close' : 'Open'}
            onClick={() => act(data.open ? 'close' : 'open')} />
        </div>
      </div>
    </div>
  );
};
