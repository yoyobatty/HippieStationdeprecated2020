import { Fragment } from 'inferno';
import { useBackend } from '../backend';
import { Box, Button, Icon, NumberInput, ProgressBar, Section } from '../components';
import { formatDuration, formatPower } from './common/PowerBits';

// hippie -- the SMES redone as the flow it is: power from the grid goes in
// through the input, sits in the battery, and goes back out through the
// output to the load. Each side has its switch, its level typed in kW or
// stepped, and what it's moving now. The raw numbers come from
// hippiestation/code/modules/power/power_tgui.dm.

const FlowArrow = props => (
  <Box textAlign="center" color={props.active ? 'good' : 'label'} my={0.5}>
    <Icon name="arrow-down" mr={1} />
    {props.children}
  </Box>
);

const LevelControl = props => {
  const { act, action, level, levelMax, disabled } = props;
  return (
    <Box>
      <Box mb={0.5}>
        <ProgressBar value={levelMax > 0 ? level / levelMax : 0}>
          {formatPower(level)} of {formatPower(levelMax)}
        </ProgressBar>
      </Box>
      <Box textAlign="center">
        <Button
          icon="fast-backward"
          disabled={disabled || level === 0}
          onClick={() => act(action, { target: 'min' })} />
        <Button
          icon="backward"
          disabled={disabled || level === 0}
          onClick={() => act(action, { adjust: -10000 })} />
        <NumberInput
          width="90px"
          unit="kW"
          step={5}
          stepPixelSize={2}
          value={Math.round(level / 1000)}
          minValue={0}
          maxValue={Math.round(levelMax / 1000)}
          onChange={(e, value) => act(action, { target: value * 1000 })} />
        <Button
          icon="forward"
          disabled={disabled || level === levelMax}
          onClick={() => act(action, { adjust: 10000 })} />
        <Button
          icon="fast-forward"
          disabled={disabled || level === levelMax}
          onClick={() => act(action, { target: 'max' })} />
      </Box>
    </Box>
  );
};

export const Smes = props => {
  const { act, data } = useBackend(props);
  const full = data.capacityPercent >= 100;
  const inputState = full && { color: 'good', text: 'Full' }
    || data.inputting && { color: 'average', text: 'Charging' }
    || { color: 'bad', text: 'Not charging' };
  const outputState = data.outputting && { color: 'good', text: 'Sending' }
    || data.charge > 0 && { color: 'average', text: 'Not sending' }
    || { color: 'bad', text: 'Empty' };
  const charging = data.inputting
    ? Math.min(data.inputLevel, data.inputAvailableRaw || 0)
    : 0;
  return (
    <Fragment>
      <Section
        title="Input"
        buttons={(
          <Button
            icon={data.inputAttempt ? 'sync-alt' : 'times'}
            selected={data.inputAttempt}
            content={data.inputAttempt ? 'Auto' : 'Off'}
            onClick={() => act('tryinput')} />
        )}>
        <Box mb={1}>
          <Box inline color={inputState.color} bold mr={2}>
            {inputState.text}
          </Box>
          <Box inline color="label">
            Grid has {formatPower(data.inputAvailableRaw)} spare
          </Box>
        </Box>
        <LevelControl
          act={act}
          action="input"
          level={data.inputLevel}
          levelMax={data.inputLevelMax} />
      </Section>
      <FlowArrow active={charging > 0}>
        {formatPower(charging)} in
      </FlowArrow>
      <Section title="Stored">
        <ProgressBar
          value={data.capacityPercent / 100}
          ranges={{
            good: [0.5, Infinity],
            average: [0.15, 0.5],
            bad: [-Infinity, 0.15],
          }}>
          <Box bold fontSize="14px">
            {Math.round(data.capacityPercent)}%
          </Box>
        </ProgressBar>
        <Box mt={0.5} color="label" textAlign="center">
          {data.fullSeconds !== null && data.fullSeconds !== undefined && (
            <Fragment>
              <Icon name="hourglass-half" mr={1} />
              Full in about {formatDuration(data.fullSeconds)}
            </Fragment>
          )}
          {data.emptySeconds !== null && data.emptySeconds !== undefined && (
            <Box inline color="average">
              <Icon name="hourglass-half" mr={1} />
              Empty in about {formatDuration(data.emptySeconds)}
            </Box>
          )}
          {(data.fullSeconds === null || data.fullSeconds === undefined)
            && (data.emptySeconds === null
              || data.emptySeconds === undefined)
            && (full ? 'Holding full' : 'Holding steady')}
        </Box>
      </Section>
      <FlowArrow active={data.outputting}>
        {formatPower(data.outputting ? data.outputUsedRaw : 0)} out
      </FlowArrow>
      <Section
        title="Output"
        buttons={(
          <Button
            icon={data.outputAttempt ? 'power-off' : 'times'}
            selected={data.outputAttempt}
            content={data.outputAttempt ? 'On' : 'Off'}
            onClick={() => act('tryoutput')} />
        )}>
        <Box mb={1}>
          <Box inline color={outputState.color} bold>
            {outputState.text}
          </Box>
        </Box>
        <LevelControl
          act={act}
          action="output"
          level={data.outputLevel}
          levelMax={data.outputLevelMax} />
      </Section>
    </Fragment>
  );
};
