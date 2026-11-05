import { useBackend } from '../backend';
import { Box, Button, LabeledList, NumberInput, Section } from '../components';

// hippie -- the signaler, timer, proximity sensor, infrared laser and
// health sensor (hippiestation/code/modules/assembly/assembly_tgui.dm)

const clock = seconds => {
  const s = seconds % 60;
  return Math.floor(seconds / 60) + ':' + (s < 10 ? '0' : '') + s;
};

const Clock = props => {
  const { act, time, timing, label } = props;
  return (
    <LabeledList.Item label={label}>
      <Button
        icon="fast-backward"
        disabled={timing}
        onClick={() => act('time', { by: -30 })} />
      <Button
        icon="backward"
        disabled={timing}
        onClick={() => act('time', { by: -1 })} />
      <Box
        inline
        bold
        mx={1}
        fontSize="16px"
        color={timing ? 'average' : null}
        style={{ 'font-family': 'monospace' }}>
        {clock(time)}
      </Box>
      <Button
        icon="forward"
        disabled={timing}
        onClick={() => act('time', { by: 1 })} />
      <Button
        icon="fast-forward"
        disabled={timing}
        onClick={() => act('time', { by: 30 })} />
    </LabeledList.Item>
  );
};

const Signaler = props => {
  const { act, data } = props;
  return (
    <Section>
      <LabeledList>
        <LabeledList.Item label="Frequency">
          <NumberInput
            animated
            unit="kHz"
            step={0.2}
            stepPixelSize={6}
            minValue={data.min_frequency / 10}
            maxValue={data.max_frequency / 10}
            value={data.frequency / 10}
            format={value => value.toFixed(1)}
            width="90px"
            onDrag={(e, value) => act('frequency', { frequency: value })} />
        </LabeledList.Item>
        <LabeledList.Item label="Code">
          <NumberInput
            animated
            step={1}
            stepPixelSize={6}
            minValue={1}
            maxValue={100}
            value={data.code}
            width="90px"
            onDrag={(e, value) => act('code', { code: value })} />
        </LabeledList.Item>
      </LabeledList>
      <Box mt={1}>
        <Button
          icon="broadcast-tower"
          content="Send signal"
          onClick={() => act('send')} />
        <Button
          icon="undo"
          content="Default"
          tooltip={(data.default_frequency / 10).toFixed(1) + ' kHz, code '
            + data.default_code}
          disabled={data.frequency === data.default_frequency
            && data.code === data.default_code}
          onClick={() => act('reset')} />
      </Box>
      <Box mt={1} color="label" fontSize="11px">
        Drag a number up or down, or double-click it to type one.
      </Box>
    </Section>
  );
};

const Electropack = props => {
  const { act, data } = props;
  return (
    <Section>
      {!!data.worn && (
        <Box mb={1} color="average">
          It can&apos;t be set while it&apos;s on your back.
        </Box>
      )}
      <LabeledList>
        <LabeledList.Item label="Power">
          <Button
            icon="power-off"
            content={data.on ? 'On' : 'Off'}
            selected={data.on}
            disabled={data.worn}
            onClick={() => act('power')} />
        </LabeledList.Item>
        <LabeledList.Item label="Frequency">
          <NumberInput
            animated
            unit="kHz"
            step={0.2}
            stepPixelSize={6}
            minValue={data.min_frequency / 10}
            maxValue={data.max_frequency / 10}
            value={data.frequency / 10}
            format={value => value.toFixed(1)}
            width="90px"
            onDrag={(e, value) => act('frequency', { frequency: value })} />
        </LabeledList.Item>
        <LabeledList.Item label="Code">
          <NumberInput
            animated
            step={1}
            stepPixelSize={6}
            minValue={1}
            maxValue={100}
            value={data.code}
            width="90px"
            onDrag={(e, value) => act('code', { code: value })} />
        </LabeledList.Item>
      </LabeledList>
    </Section>
  );
};

const Timer = props => {
  const { act, data } = props;
  return (
    <Section>
      <LabeledList>
        <Clock
          act={act}
          label="Time"
          time={data.time}
          timing={data.timing} />
        <LabeledList.Item label="Repeat">
          <Button
            icon={data.repeat ? 'sync' : 'times'}
            content={data.repeat ? 'Repeats' : 'Once'}
            selected={data.repeat}
            onClick={() => act('repeat')} />
        </LabeledList.Item>
      </LabeledList>
      <Button
        mt={1}
        fluid
        textAlign="center"
        icon={data.timing ? 'stop' : 'play'}
        color={data.timing ? 'average' : null}
        content={data.timing ? 'Stop' : 'Start'}
        onClick={() => act('timing')} />
    </Section>
  );
};

const Prox = props => {
  const { act, data } = props;
  return (
    <Section>
      <LabeledList>
        {!data.armed && (
          <Clock
            act={act}
            label="Arms in"
            time={data.time}
            timing={data.timing} />
        )}
        <LabeledList.Item label="Range">
          <Button
            icon="minus"
            disabled={data.range <= 0}
            onClick={() => act('range', { by: -1 })} />
          <Box inline bold mx={1}>
            {data.range + (data.range === 1 ? ' tile' : ' tiles')}
          </Box>
          <Button
            icon="plus"
            disabled={data.range >= data.max_range}
            onClick={() => act('range', { by: 1 })} />
        </LabeledList.Item>
        <LabeledList.Item label="Sensor">
          <Box inline color={data.armed ? 'bad' : 'label'} bold>
            {data.armed ? 'ARMED: goes off at any movement' : 'Not armed'}
          </Box>
        </LabeledList.Item>
      </LabeledList>
      <Box mt={1}>
        {!data.armed && (
          <Button
            icon={data.timing ? 'stop' : 'stopwatch'}
            content={data.timing ? 'Stop the count' : 'Arm on a count'}
            onClick={() => act('timing')} />
        )}
        <Button
          icon={data.armed ? 'lock-open' : 'bullseye'}
          color={data.armed ? null : 'bad'}
          content={data.armed ? 'Disarm' : 'Arm now'}
          onClick={() => act('arm')} />
      </Box>
    </Section>
  );
};

const Infra = props => {
  const { act, data } = props;
  return (
    <Section>
      <LabeledList>
        <LabeledList.Item label="Laser">
          <Button
            icon="power-off"
            content={data.on ? 'On' : 'Off'}
            selected={data.on}
            onClick={() => act('power')} />
        </LabeledList.Item>
        <LabeledList.Item label="Beam">
          <Button
            icon={data.visible ? 'eye' : 'eye-slash'}
            content={data.visible ? 'Visible' : 'Invisible'}
            selected={data.visible}
            onClick={() => act('visible')} />
        </LabeledList.Item>
      </LabeledList>
    </Section>
  );
};

const Health = props => {
  const { act, data } = props;
  return (
    <Section>
      <LabeledList>
        <LabeledList.Item label="Sensor">
          <Button
            icon="power-off"
            content={data.on ? 'On' : 'Off'}
            selected={data.on}
            onClick={() => act('power')} />
        </LabeledList.Item>
        <LabeledList.Item label="Reading">
          {data.on && data.health !== null
            ? data.health
            : <Box inline color="label">Nobody</Box>}
        </LabeledList.Item>
        <LabeledList.Item label="Goes off at">
          {data.alarm === 'death' ? 'Death' : 'Critical condition'}
        </LabeledList.Item>
      </LabeledList>
      <Box mt={1} color="label" fontSize="11px">
        A multitool switches it between death and critical condition.
      </Box>
    </Section>
  );
};

const KINDS = {
  signaler: Signaler,
  electropack: Electropack,
  timer: Timer,
  prox: Prox,
  infra: Infra,
  health: Health,
};

export const Assembly = props => {
  const { act, data } = useBackend(props);
  const Body = KINDS[data.kind];
  return Body ? <Body act={act} data={data} /> : null;
};
