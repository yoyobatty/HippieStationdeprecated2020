import { useBackend } from '../backend';
import { Icon, NumberInput } from '../components';
import { SecKey } from './BrigTimer';

// hippie -- the scanner gate as a control panel: what sets it off on the
// display, a key for each mode, Match/No match, and the mode's own setting.
// Data and actions from code/game/machinery/scan_gate.dm, as before.

const MODES = [
  'Off', 'Wanted', 'Guns', 'Mindshield',
  'Disease', 'Species', 'Nutrition', 'Nanites',
];

const DISEASES = [
  'Positive', 'Harmless', 'Minor', 'Medium',
  'Harmful', 'Dangerous', 'BIOHAZARD',
];

const SPECIES = [
  ['Human', 'human'],
  ['Lizard', 'lizard'],
  ['Fly', 'fly'],
  ['Felinid', 'felinid'],
  ['Plasmaman', 'plasma'],
  ['Moth', 'moth'],
  ['Jelly', 'jelly'],
  ['Pod', 'pod'],
  ['Golem', 'golem'],
  ['Zombie', 'zombie'],
];

const NUTRITION = [['Starving', 150], ['Obese', 600]];

// What sets the gate off, as its display says it
const triggerText = data => {
  const { scan_mode, reverse } = data;
  if (scan_mode === 'Off') {
    return 'Idle';
  }
  let what = scan_mode;
  if (scan_mode === 'Disease') {
    what = 'Disease ≥ ' + data.disease_threshold;
  } else if (scan_mode === 'Species') {
    const species = SPECIES.find(s => s[1] === data.target_species);
    what = 'Species: ' + (species ? species[0] : data.target_species);
  } else if (scan_mode === 'Nutrition') {
    const level = NUTRITION.find(n => n[1] === data.target_nutrition);
    what = 'Nutrition: ' + (level ? level[0] : '-');
  } else if (scan_mode === 'Nanites') {
    what = 'Nanite cloud ' + data.nanite_cloud;
  }
  return (reverse ? 'No ' : '') + what;
};

const Setting = props => {
  const { act, data } = props;
  switch (data.scan_mode) {
    case 'Disease':
      return DISEASES.map(level => (
        <SecKey
          key={level}
          className="Gate__small"
          on={data.disease_threshold === level}
          onClick={() => act('set_disease_threshold', {
            new_threshold: level,
          })}>
          {level}
        </SecKey>
      ));
    case 'Species':
      return SPECIES.map(species => (
        <SecKey
          key={species[1]}
          className="Gate__small"
          on={data.target_species === species[1]}
          onClick={() => act('set_target_species', {
            new_species: species[1],
          })}>
          {species[0]}
        </SecKey>
      ));
    case 'Nutrition':
      return NUTRITION.map(level => (
        <SecKey
          key={level[0]}
          className="Gate__small"
          on={data.target_nutrition === level[1]}
          onClick={() => act('set_target_nutrition', {
            new_nutrition: level[0],
          })}>
          {level[0]}
        </SecKey>
      ));
    case 'Nanites':
      return (
        <div className="Gate__cloud">
          Cloud
          <NumberInput
            ml={1}
            width="60px"
            value={data.nanite_cloud}
            minValue={1}
            maxValue={100}
            stepPixelSize={5}
            onChange={(e, value) => act('set_nanite_cloud', {
              new_cloud: value,
            })} />
        </div>
      );
    default:
      return null;
  }
};

export const ScannerGate = props => {
  const { act, data } = useBackend(props);
  const { locked, scan_mode, reverse } = data;
  const armed = scan_mode !== 'Off';
  return (
    <div className="SecDev">
      <div className={'Gate__display' + (armed ? ' Gate__display--armed' : '')}>
        <span className="Gate__label">Trigger</span>
        {triggerText(data)}
      </div>
      {locked ? (
        <div className="Gate__locked">
          <Icon name="lock" mr={1} />
          Locked
          <SecKey
            className="Gate__unlock"
            onClick={() => act('toggle_lock')}>
            <Icon name="id-card" mr={1} />
            Swipe ID
          </SecKey>
        </div>
      ) : (
        <div>
          <div className="Gate__modes">
            {MODES.map(mode => (
              <SecKey
                key={mode}
                on={scan_mode === mode}
                onClick={() => act('set_mode', { new_mode: mode })}>
                {mode}
              </SecKey>
            ))}
          </div>
          {armed && (
            <div className="SecDev__row Gate__logic">
              <SecKey
                on={!reverse}
                onClick={() => reverse && act('toggle_reverse')}>
                Match
              </SecKey>
              <SecKey
                on={!!reverse}
                onClick={() => !reverse && act('toggle_reverse')}>
                No match
              </SecKey>
              <SecKey
                className="Gate__lockKey"
                onClick={() => act('toggle_lock')}>
                <Icon name="lock" mr={1} />
                Lock
              </SecKey>
            </div>
          )}
          <div className="Gate__setting">
            <Setting act={act} data={data} />
          </div>
        </div>
      )}
    </div>
  );
};
