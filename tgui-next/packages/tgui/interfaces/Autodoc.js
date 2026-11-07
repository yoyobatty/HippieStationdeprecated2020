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
          <Figure target={data.target} busy />
          <div className="Autodoc__target">{partName(data.target)}</div>
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
        <Figure target={data.target} onPick={part => act('target', { part })} />
        <div className="Autodoc__target">{partName(data.target)}</div>
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
