import { Fragment } from 'inferno';
import { useBackend } from '../backend';
import { AnimatedNumber, Box, Button, LabeledList, ProgressBar, Section } from '../components';

// hippie -- the sleeper, on the tgui-next look (was
// tgui/src/interfaces/sleeper.ract)

const DAMAGES = [
  { label: 'Brute', type: 'bruteLoss', color: 'bad' },
  { label: 'Burn', type: 'fireLoss', color: 'orange' },
  { label: 'Toxin', type: 'toxLoss', color: 'green' },
  { label: 'Respiratory', type: 'oxyLoss', color: 'blue' },
];

export const Sleeper = props => {
  const { act, data } = useBackend(props);
  const {
    occupied,
    open,
    occupant = {},
    chems = [],
  } = data;
  const reagents = occupant.reagents || [];
  const inBlood = name => {
    const found = reagents.find(reagent => reagent.name === name);
    return found ? found.volume : 0;
  };
  return (
    <Fragment>
      <Section
        title={occupant.name || 'No occupant'}
        buttons={(
          <Button
            icon={open ? 'door-closed' : 'door-open'}
            content={open ? 'Close door' : 'Open door'}
            onClick={() => act('door')} />
        )}>
        {!occupied && (
          <Box color="label">
            {open
              ? 'No occupant.'
              : 'Empty.'}
          </Box>
        ) || (
          <LabeledList>
            <LabeledList.Item label="State" color={occupant.statstate}>
              {occupant.stat}
            </LabeledList.Item>
            <LabeledList.Item label="Health">
              <ProgressBar
                value={occupant.health}
                minValue={occupant.minHealth}
                maxValue={occupant.maxHealth}
                ranges={{
                  good: [occupant.maxHealth * 0.5, Infinity],
                  average: [0, occupant.maxHealth * 0.5],
                  bad: [-Infinity, 0],
                }}>
                <AnimatedNumber value={Math.round(occupant.health)} />
                {' / ' + occupant.maxHealth}
              </ProgressBar>
            </LabeledList.Item>
            {DAMAGES.map(damage => (
              <LabeledList.Item key={damage.type} label={damage.label}>
                <ProgressBar
                  value={occupant[damage.type]}
                  minValue={0}
                  maxValue={occupant.maxHealth}
                  color={occupant[damage.type] > 0 ? damage.color : 'good'}>
                  <AnimatedNumber value={Math.round(occupant[damage.type])} />
                </ProgressBar>
              </LabeledList.Item>
            ))}
            <LabeledList.Item
              label="Cells"
              color={occupant.cloneLoss ? 'bad' : 'good'}>
              {occupant.cloneLoss ? 'Damaged' : 'Healthy'}
            </LabeledList.Item>
            <LabeledList.Item
              label="Brain"
              color={occupant.brainLoss ? 'bad' : 'good'}>
              {occupant.brainLoss ? 'Abnormal' : 'Healthy'}
            </LabeledList.Item>
          </LabeledList>
        )}
      </Section>
      {!!occupied && (
        <Section title="Bloodstream">
          {reagents.length === 0 && (
            <Box color="good">Pure</Box>
          )}
          {reagents.map(reagent => (
            <Box key={reagent.name} color="highlight">
              <AnimatedNumber
                value={reagent.volume}
                format={v => v.toFixed(1)} />
              {' units of ' + reagent.name}
            </Box>
          ))}
        </Section>
      )}
      <Section title="Inject">
        {chems.map(chem => (
          <Button
            key={chem.id}
            fluid
            icon="syringe"
            disabled={!occupied || !chem.allowed}
            onClick={() => act('inject', { chem: chem.id })}>
            {chem.name}
            {inBlood(chem.name) > 0 && (
              <Box inline color="label" ml={1}>
                ({inBlood(chem.name).toFixed(1)}u in blood)
              </Box>
            )}
          </Button>
        ))}
      </Section>
    </Fragment>
  );
};
