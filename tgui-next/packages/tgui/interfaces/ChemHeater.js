import { round, toFixed } from 'common/math';
import { Fragment } from 'inferno';
import { useBackend } from '../backend';
import { AnimatedNumber, Box, Button, LabeledList, NumberInput, ProgressBar, Section } from '../components';
import { FillBar, ReagentTable } from './common/ReagentBits';

// hippie -- the chem heater redone: the beaker's temperature against the
// target, cold blue to hot red, and its contents in their colours

const tempColor = kelvin => {
  if (kelvin < 273) {
    return 'blue';
  }
  if (kelvin < 340) {
    return 'good';
  }
  return kelvin < 500 ? 'average' : 'bad';
};

export const ChemHeater = props => {
  const { act, data } = useBackend(props);
  const {
    targetTemp,
    isActive,
    isBeakerLoaded,
    currentTemp,
    beakerCurrentVolume,
    beakerMaxVolume,
    beakerColor,
    isTankLinked,
    tankTemp,
    tankCurrentVolume,
    tankMaxVolume,
  } = data;
  return (
    <Fragment>
      <Section
        title="Heater"
        buttons={(
          <Button
            icon="power-off"
            selected={isActive}
            content={isActive ? 'Heating' : 'Off'}
            onClick={() => act('power')} />
        )}>
        <LabeledList>
          <LabeledList.Item label="Target">
            <NumberInput
              width="70px"
              unit="K"
              step={5}
              stepPixelSize={1}
              value={round(targetTemp)}
              minValue={0}
              maxValue={1000}
              onDrag={(e, value) => act('temperature', { target: value })} />
            {[273, 300, 373, 500].map(preset => (
              <Button
                key={preset}
                ml={0.5}
                content={preset + 'K'}
                onClick={() => act('temperature', { target: preset })} />
            ))}
          </LabeledList.Item>
          <LabeledList.Item label="Beaker">
            {isBeakerLoaded && (
              <ProgressBar
                value={currentTemp}
                minValue={0}
                maxValue={Math.max(1000, targetTemp)}
                color={tempColor(currentTemp)}>
                <AnimatedNumber
                  value={currentTemp}
                  format={value => toFixed(value) + ' K'} />
                {' (target ' + round(targetTemp) + ' K)'}
              </ProgressBar>
            ) || (
              <Box color="label">No beaker</Box>
            )}
          </LabeledList.Item>
          {!!isTankLinked && (
            <LabeledList.Item label="Tank">
              <ProgressBar
                value={tankTemp}
                minValue={0}
                maxValue={Math.max(1000, targetTemp)}
                color={tempColor(tankTemp)}>
                <AnimatedNumber
                  value={tankTemp}
                  format={value => toFixed(value) + ' K'} />
                {' (' + round(tankCurrentVolume) + '/'
                  + round(tankMaxVolume) + 'u)'}
              </ProgressBar>
            </LabeledList.Item>
          )}
        </LabeledList>
      </Section>
      <Section
        title="Beaker"
        buttons={!!isBeakerLoaded && (
          <Button
            icon="eject"
            content="Eject"
            onClick={() => act('eject')} />
        )}>
        {!isBeakerLoaded && (
          <Box color="label">No beaker.</Box>
        ) || (
          <Fragment>
            <FillBar
              volume={beakerCurrentVolume}
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
