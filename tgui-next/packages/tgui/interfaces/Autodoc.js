import { useBackend } from '../backend';
import { Icon } from '../components';

// hippie -- the Auto-Doc Mark IX (hippiestation/code/game/machinery/
// autodoc.dm): the patient as a figure to pick the part on (facing you, so
// their right is on the left), the surgeries that part allows as cards, and
// while it works, the steps as a timeline.

// [zone, name, svg shape]
const PARTS = [
  ['r_arm', 'Right Arm', { x: 18, y: 46, width: 15, height: 62, rx: 7 }],
  ['l_arm', 'Left Arm', { x: 87, y: 46, width: 15, height: 62, rx: 7 }],
  ['chest', 'Chest', { x: 36, y: 44, width: 48, height: 46, rx: 8 }],
  ['groin', 'Groin', { x: 38, y: 92, width: 44, height: 18, rx: 6 }],
  ['r_leg', 'Right Leg', { x: 38, y: 112, width: 20, height: 62, rx: 8 }],
  ['l_leg', 'Left Leg', { x: 62, y: 112, width: 20, height: 62, rx: 8 }],
  ['head', 'Head', { x: 44, y: 4, width: 32, height: 36, rx: 15 }],
  ['eyes', 'Eyes', { x: 48, y: 16, width: 24, height: 7, rx: 3 }],
  ['mouth', 'Mouth', { x: 53, y: 28, width: 14, height: 6, rx: 3 }],
];

const SMALL_PARTS = ['eyes', 'mouth'];

const healthColor = health => {
  if (health > 60) {
    return '#37b24d';
  }
  return health > 25 ? '#f59f00' : '#e03131';
};

const Figure = props => {
  const { target, onPick, busy } = props;
  return (
    <svg className="Autodoc__figure" viewBox="0 0 120 180">
      {PARTS.map(part => (
        <rect
          key={part[0]}
          {...part[2]}
          className={'Autodoc__part'
            + (target === part[0] ? ' Autodoc__part--on' : '')
            + (busy && target === part[0] ? ' Autodoc__part--busy' : '')
            + (SMALL_PARTS.includes(part[0]) ? ' Autodoc__part--small' : '')}
          onClick={() => !busy && onPick(part[0])} />
      ))}
    </svg>
  );
};

// The same parts over the patient's own 32x32 sprite, facing you
const SPRITE_PARTS = {
  head: { x: 12, y: 1, width: 8, height: 9 },
  chest: { x: 11, y: 10, width: 10, height: 8 },
  groin: { x: 11, y: 18, width: 10, height: 3 },
  r_arm: { x: 7, y: 10, width: 4, height: 12 },
  l_arm: { x: 21, y: 10, width: 4, height: 12 },
  r_leg: { x: 11, y: 21, width: 5, height: 9 },
  l_leg: { x: 16, y: 21, width: 5, height: 9 },
  eyes: { x: 13, y: 4.5, width: 6, height: 2 },
  mouth: { x: 14, y: 7.5, width: 4, height: 1.5 },
};

// Eyes and mouth are on the head, the groin with the chest
const LIMB_OF = { eyes: 'head', mouth: 'head', groin: 'chest' };

const damageOf = (parts, zone) => (parts || {})[LIMB_OF[zone] || zone];

// A part's colour by its damage, like a health doll
const damageColor = part => {
  if (!part || part.missing) {
    return null;
  }
  const hurt = (part.brute + part.burn) / Math.max(part.max, 1);
  if (hurt <= 0) {
    return null;
  }
  if (hurt < 0.2) {
    return '#94d82d';
  }
  if (hurt < 0.45) {
    return '#fcc419';
  }
  return hurt < 0.7 ? '#fd7e14' : '#e03131';
};

const SpriteFigure = props => {
  const { sprite, parts, target, onPick, busy } = props;
  // Limbs first, the head's eyes and mouth last so they're on top
  const order = ['r_arm', 'l_arm', 'chest', 'groin', 'r_leg', 'l_leg',
    'head', 'eyes', 'mouth'];
  return (
    <div className="Autodoc__sprite">
      <img src={sprite} />
      <svg viewBox="0 0 32 32" shapeRendering="crispEdges">
        <defs>
          <pattern id="autodoc-missing" width="2" height="2"
            patternUnits="userSpaceOnUse" patternTransform="rotate(45)">
            <rect width="1" height="2" fill="#e03131" />
          </pattern>
        </defs>
        {order.map(zone => {
          const part = damageOf(parts, zone);
          const small = SMALL_PARTS.includes(zone);
          let fill = 'transparent';
          if (part && part.missing && !small) {
            fill = 'url(#autodoc-missing)';
          } else if (!small) {
            fill = damageColor(part) || 'transparent';
          }
          return (
            <rect
              key={zone}
              {...SPRITE_PARTS[zone]}
              fill={fill}
              className={'Autodoc__hit'
                + (target === zone ? ' Autodoc__hit--on' : '')
                + (busy && target === zone ? ' Autodoc__hit--busy' : '')}
              onClick={() => !busy && onPick(zone)} />
          );
        })}
      </svg>
    </div>
  );
};

// The picked part's damage, under the figure
const PartDamage = props => {
  const part = damageOf(props.parts, props.target);
  if (!part) {
    return null;
  }
  if (part.missing) {
    return <div className="Autodoc__damage Autodoc__damage--bad">Missing</div>;
  }
  return (
    <div className="Autodoc__damage">
      <span className="Autodoc__brute">{part.brute}</span> brute
      {' · '}
      <span className="Autodoc__burn">{part.burn}</span> burn
    </div>
  );
};

const PatientFigure = props => {
  const { data, onPick, busy } = props;
  if (data.sprite) {
    return (
      <SpriteFigure
        sprite={data.sprite}
        parts={data.parts}
        target={data.target}
        onPick={onPick}
        busy={busy} />
    );
  }
  return <Figure target={data.target} onPick={onPick} busy={busy} />;
};

const partName = zone => {
  const part = PARTS.find(p => p[0] === zone);
  return part ? part[1] : zone;
};

const Patient = props => {
  const { data } = props;
  if (!data.patient) {
    return <div className="Autodoc__patient Autodoc__dim">No patient</div>;
  }
  return (
    <div className="Autodoc__patient">
      <div className="Autodoc__patientName">{data.patient}</div>
      <div className="Autodoc__health">
        <div
          className="Autodoc__healthFill"
          style={{
            'width': Math.max(0, data.health) + '%',
            'background-color': healthColor(data.health),
          }} />
        <span className="Autodoc__healthText">{data.health}%</span>
      </div>
    </div>
  );
};

export const Autodoc = props => {
  const { act, data } = useBackend(props);
  if (data.mode === 2) {
    const steps = data.steps || [];
    const current = steps.findIndex(step => step.current);
    return (
      <div className="Autodoc">
        <div className="Autodoc__left">
          <Patient data={data} />
          <PatientFigure data={data} busy />
          <div className="Autodoc__target">{partName(data.target)}</div>
          <PartDamage parts={data.parts} target={data.target} />
        </div>
        <div className="Autodoc__right">
          <div className="Autodoc__heading">
            <Icon name="cog" spin mr={1} />
            {data.s_name}
          </div>
          <div className="Autodoc__steps">
            {steps.map((step, i) => {
              let state = 'next';
              if (step.current) {
                state = 'now';
              } else if (i < current) {
                state = 'done';
              }
              return (
                <div key={i} className={'Autodoc__step Autodoc__step--'
                  + state}>
                  <span className="Autodoc__dot" />
                  {step.name}
                </div>
              );
            })}
          </div>
        </div>
      </div>
    );
  }
  const surgeries = data.surgeries || [];
  const chosen = surgeries.find(surgery => surgery.selected);
  return (
    <div className="Autodoc">
      <div className="Autodoc__left">
        <Patient data={data} />
        <PatientFigure
          data={data}
          onPick={part => act('target', { part })} />
        <div className="Autodoc__target">{partName(data.target)}</div>
        <PartDamage parts={data.parts} target={data.target} />
      </div>
      <div className="Autodoc__right">
        <div className="Autodoc__heading">Surgeries</div>
        <div className="Autodoc__cards">
          {surgeries.length === 0 && (
            <div className="Autodoc__dim">None for this part</div>
          )}
          {surgeries.map(surgery => (
            <div
              key={surgery.path}
              className={'Autodoc__card'
                + (surgery.selected ? ' Autodoc__card--on' : '')}
              onClick={() => act('surgery', { path: surgery.path })}>
              {surgery.name}
            </div>
          ))}
        </div>
        <div
          className={'Autodoc__start' + (chosen ? '' : ' Autodoc__start--off')}
          onClick={() => chosen && act('start')}>
          <Icon name="play" mr={1} />
          {chosen ? 'Start ' + chosen.name : 'Pick a surgery'}
        </div>
      </div>
    </div>
  );
};
