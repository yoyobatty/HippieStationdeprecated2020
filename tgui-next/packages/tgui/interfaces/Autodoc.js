import { Fragment } from 'inferno';
import { useBackend } from '../backend';
import { Box, Button, Icon, Section, Table } from '../components';

// hippie -- the Auto-Doc Mark IX
// (hippiestation/code/game/machinery/autodoc.dm), was
// tgui/src/interfaces/autodoc.ract

// Laid out like the target doll: the patient faces you, so their right is on
// the left
const BODY = [
  [null, ['eyes', 'Eyes'], ['head', 'Head'], ['mouth', 'Mouth'], null],
  [
    ['r_arm', 'Right Arm'], null, ['chest', 'Chest'], null,
    ['l_arm', 'Left Arm'],
  ],
  [null, null, ['groin', 'Groin'], null, null],
  [null, ['r_leg', 'Right Leg'], null, ['l_leg', 'Left Leg'], null],
];

export const Autodoc = props => {
  const { act, data } = useBackend(props);
  if (data.mode === 2) {
    const steps = data.steps || [];
    const current = steps.findIndex(step => step.current);
    return (
      <Section title={data.s_name + ' in progress'}>
        {steps.map((step, i) => (
          <Box
            key={i}
            py={0.5}
            bold={step.current}
            color={step.current ? 'good' : i < current ? 'label' : 'average'}>
            <Icon
              mr={1}
              name={step.current ? 'cog' : i < current ? 'check' : 'circle-o'}
              spin={step.current} />
            {step.name}
          </Box>
        ))}
      </Section>
    );
  }
  const surgeries = data.surgeries || [];
  const chosen = surgeries.find(surgery => surgery.selected);
  return (
    <Fragment>
      <Section title="Target">
        <Table>
          {BODY.map((row, y) => (
            <Table.Row key={y}>
              {row.map((part, x) => (
                <Table.Cell
                  key={x}
                  textAlign="center"
                  style={{ width: '20%', padding: '2px' }}>
                  {!!part && (
                    <Button
                      fluid
                      selected={data.target === part[0]}
                      content={part[1]}
                      onClick={() => act('target', { part: part[0] })} />
                  )}
                </Table.Cell>
              ))}
            </Table.Row>
          ))}
        </Table>
      </Section>
      <Section title="Surgeries">
        {surgeries.length === 0 && (
          <Box color="label">
            Nothing it can do there.
          </Box>
        )}
        {surgeries.map(surgery => (
          <Button
            key={surgery.path}
            selected={surgery.selected}
            content={surgery.name}
            onClick={() => act('surgery', { path: surgery.path })} />
        ))}
      </Section>
      <Button
        fluid
        icon="play"
        color="good"
        textAlign="center"
        disabled={!chosen}
        content={chosen ? 'Start ' + chosen.name : 'Pick a surgery'}
        onClick={() => act('start')} />
    </Fragment>
  );
};
