import { Fragment } from 'inferno';
import { useBackend } from '../backend';
import { AnimatedNumber, Box, Button, LabeledList, ProgressBar, Section, Table } from '../components';
import { FillBar, ReagentTable } from './common/ReagentBits';

// hippie -- the cryo cell redone (extra data in hippiestation/code/game/
// machinery/medical_tgui.dm): the patient's health and each kind of damage as
// bars, their body temperature against the cell's, and the beaker in its
// reagents' colours

const DAMAGES = [
  ['Brute', 'bruteLoss', 'bad'],
  ['Burn', 'fireLoss', 'orange'],
  ['Toxin', 'toxLoss', 'green'],
  ['Suffocation', 'oxyLoss', 'blue'],
];

export const Cryo = props => {
  const { act, data } = useBackend(props);
  const {
    isOperating,
    hasOccupant,
    isOpen,
    autoEject,
    occupant = {},
    cellTemperature,
    isBeakerLoaded,
    beakerColor,
    beakerVolume,
    beakerMaxVolume,
  } = data;
  return (
    <Fragment>
      <Section
        title={hasOccupant ? occupant.name : 'Cryo cell'}
        buttons={(
          <Fragment>
            <Button
              icon={isOpen ? 'door-closed' : 'door-open'}
              content={isOpen ? 'Close' : 'Open'}
              onClick={() => act('door')} />
            <Button
              icon="power-off"
              selected={isOperating}
              disabled={isOpen}
              content={isOperating ? 'On' : 'Off'}
              onClick={() => act('power')} />
          </Fragment>
        )}>
        {!hasOccupant && (
          <Box color="label">Nobody inside.</Box>
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
                <AnimatedNumber value={occupant.health} />
                {' / ' + occupant.maxHealth}
              </ProgressBar>
            </LabeledList.Item>
            {DAMAGES.map(damage => (
              <LabeledList.Item key={damage[1]} label={damage[0]}>
                <ProgressBar
                  value={occupant[damage[1]]}
                  minValue={0}
                  maxValue={occupant.maxHealth}
                  color={occupant[damage[1]] > 0 ? damage[2] : 'good'}>
                  <AnimatedNumber value={occupant[damage[1]]} />
                </ProgressBar>
              </LabeledList.Item>
            ))}
          </LabeledList>
        )}
      </Section>
      <Section title="Temperature">
        <Table>
          <Table.Row>
            <Table.Cell textAlign="center">
              <Box color="label">Patient</Box>
              <Box
                fontSize="18px"
                bold
                color={hasOccupant ? occupant.temperaturestatus : 'label'}>
                {hasOccupant && (
                  <Fragment>
                    <AnimatedNumber value={occupant.bodyTemperature} /> K
                  </Fragment>
                ) || '-'}
              </Box>
            </Table.Cell>
            <Table.Cell textAlign="center">
              <Box color="label">Cell</Box>
              <Box
                fontSize="18px"
                bold
                color={cellTemperature < 225 ? 'blue' : 'average'}>
                <AnimatedNumber value={cellTemperature} /> K
              </Box>
            </Table.Cell>
          </Table.Row>
        </Table>
        <Box color="label" mt={1} textAlign="center">
          Cryoxadone works below 225 K.
        </Box>
        <Button.Checkbox
          mt={1}
          checked={autoEject}
          content="Let them out when they're healed"
          onClick={() => act('autoeject')} />
      </Section>
      <Section
        title="Beaker"
        buttons={!!isBeakerLoaded && (
          <Button
            icon="eject"
            content="Eject"
            onClick={() => act('ejectbeaker')} />
        )}>
        {!isBeakerLoaded && (
          <Box color="label">No beaker. Put one in by hand.</Box>
        ) || (
          <Fragment>
            <FillBar
              volume={beakerVolume}
              maxVolume={beakerMaxVolume}
              color={beakerColor} />
            <ReagentTable
              contents={data.beakerContents}
              empty="The beaker is empty." />
          </Fragment>
        )}
      </Section>
    </Fragment>
  );
};
