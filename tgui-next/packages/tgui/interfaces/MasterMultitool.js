import { Fragment } from 'inferno';
import { useBackend } from '../backend';
import { Box, Button, LabeledList, Section } from '../components';

// Master multitool
// (hippiestation/code/game/objects/items/devices/master_multitool.dm)
export const MasterMultitool = props => {
  const { act, data } = useBackend(props);
  const slots = data.slots || [];
  const links = data.links || [];
  const selected = data.selected;
  return (
    <Fragment>
      <Section title="Buffers">
        <LabeledList>
          {slots.map(slot => (
            <LabeledList.Item
              key={slot.index}
              label={'Buffer ' + slot.index}
              buttons={(
                <Fragment>
                  <Button
                    icon={slot.active ? 'dot-circle-o' : 'circle-o'}
                    content="Use"
                    selected={slot.active}
                    onClick={() => act('select_slot', { slot: slot.index })} />
                  <Button
                    icon="eraser"
                    disabled={!slot.name}
                    onClick={() => act('clear_slot', { slot: slot.index })} />
                </Fragment>
              )}>
              {slot.name || (
                <Box color="label">Empty</Box>
              )}
            </LabeledList.Item>
          ))}
        </LabeledList>
      </Section>
      <Section
        title={'Link probes (' + links.length + '/' + data.max_links + ')'}
        buttons={(
          <Button
            icon="link"
            content={data.linking
              ? 'Linking: use it on a machine'
              : 'Link a machine'}
            selected={data.linking}
            disabled={!data.linking && links.length >= data.max_links}
            onClick={() => act('toggle_linking')} />
        )}>
        {links.length === 0 && (
          <Box color="label">
            No probes placed. Open a machine&apos;s maintenance panel,
            press Link a machine, then use this on it.
          </Box>
        )}
        {links.length > 0 && (
          <LabeledList>
            {links.map(link => (
              <LabeledList.Item
                key={link.ref}
                label={link.name}
                color={link.problem ? 'average' : 'good'}
                buttons={(
                  <Fragment>
                    <Button
                      icon="plug"
                      content="Wires"
                      selected={link.selected}
                      onClick={() => act('select_link', { ref: link.ref })} />
                    <Button
                      icon="unlink"
                      onClick={() => act('unlink', { ref: link.ref })} />
                  </Fragment>
                )}>
                {link.area}
                {link.distance !== null && ' (' + link.distance + 'm)'}
                {!!link.problem && ' - ' + link.problem}
              </LabeledList.Item>
            ))}
          </LabeledList>
        )}
      </Section>
      {!!selected && (
        <Section title={selected.name + ' wires'}>
          {!!selected.problem && (
            <Box color="average" mb={1}>
              Can&apos;t reach it: {selected.problem}.
            </Box>
          )}
          <LabeledList>
            {selected.wires.map(wire => (
              <LabeledList.Item
                key={wire.color}
                className="candystripe"
                label={wire.color}
                labelColor={wire.color}
                color={wire.color}
                buttons={(
                  <Button
                    content="Pulse"
                    disabled={!!selected.problem}
                    onClick={() => act('pulse', { wire: wire.color })} />
                )}>
                {!!wire.cut && (
                  <i>(cut)</i>
                )}
                {!!wire.attached && (
                  <i> (signaler attached)</i>
                )}
              </LabeledList.Item>
            ))}
          </LabeledList>
          {(selected.status || []).map(status => (
            <Box key={status} mt={1}>
              {status}
            </Box>
          ))}
        </Section>
      )}
    </Fragment>
  );
};
