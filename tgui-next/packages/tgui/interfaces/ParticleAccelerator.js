import { useBackend } from '../backend';
import { Box, Button, LabeledList, ProgressBar, Section } from '../components';

// hippie -- the particle accelerator's control console
// (hippiestation/.../singularity/particle_control_tgui.dm)

const strengthColor = (strength, max) => {
  if (strength > 2 || strength > max) {
    return 'bad';
  }
  if (strength === 2) {
    return 'average';
  }
  return 'good';
};

export const ParticleAccelerator = props => {
  const { act, data } = useBackend(props);
  const { assembled, active, strength } = data;
  const max = data.max_strength;
  return (
    <Section>
      <LabeledList>
        <LabeledList.Item
          label="Parts"
          buttons={(
            <Button
              icon="sync"
              content="Run scan"
              onClick={() => act('scan')} />
          )}>
          <Box color={assembled ? 'good' : 'bad'}>
            {assembled ? 'All parts in place' : 'Unable to detect all parts'}
          </Box>
        </LabeledList.Item>
        <LabeledList.Item label="Power">
          <Button
            icon="power-off"
            content={active ? 'On' : 'Off'}
            selected={!!active}
            disabled={!assembled}
            onClick={() => act('power')} />
        </LabeledList.Item>
        <LabeledList.Item label="Particle strength">
          <Box style={{ 'display': 'flex', 'align-items': 'center' }}>
            <Button
              content="-"
              disabled={!assembled || strength <= 0}
              onClick={() => act('strength_down')} />
            <Box mx={1} style={{ 'flex-grow': 1 }}>
              <ProgressBar
                value={max ? strength / max : 0}
                color={strengthColor(strength, max)}
                content={strength + ' of ' + max} />
            </Box>
            <Button
              content="+"
              disabled={!assembled || strength >= max}
              onClick={() => act('strength_up')} />
          </Box>
        </LabeledList.Item>
      </LabeledList>
    </Section>
  );
};
