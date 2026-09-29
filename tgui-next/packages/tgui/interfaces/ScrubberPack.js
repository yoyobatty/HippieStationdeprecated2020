import { Fragment } from 'inferno';
import { useBackend } from '../backend';
import { Box, Button, LabeledList, ProgressBar, Section } from '../components';
import { getGasLabel } from '../constants';

// Backpack air scrubber
// (hippiestation/code/game/objects/items/devices/scrubber_pack.dm)
export const ScrubberPack = props => {
  const { act, data } = useBackend(props);
  const contents = data.contents || [];
  const filterTypes = data.filter_types || [];
  return (
    <Fragment>
      <Section
        title="Status"
        buttons={(
          <Button
            icon={data.on ? 'power-off' : 'times'}
            content={data.on ? 'On' : 'Off'}
            selected={data.on}
            onClick={() => act('power')} />
        )}>
        <LabeledList>
          <LabeledList.Item label="Tank">
            <ProgressBar
              value={data.fill}
              content={data.pressure + ' / ' + data.max_pressure + ' kPa'}
              ranges={{
                good: [-Infinity, 0.7],
                average: [0.7, 0.9],
                bad: [0.9, Infinity],
              }} />
          </LabeledList.Item>
        </LabeledList>
      </Section>
      <Section
        title="Caught"
        buttons={(
          <Button
            icon="wind"
            color="bad"
            content="Vent"
            disabled={contents.length === 0}
            onClick={() => act('vent')} />
        )}>
        {contents.length === 0 && (
          <Box color="label">
            The tank is empty.
          </Box>
        ) || (
          <LabeledList>
            {contents.map(gas => (
              <LabeledList.Item
                key={gas.gas_id}
                label={getGasLabel(gas.gas_id, gas.gas_name)}>
                {gas.moles} mol
              </LabeledList.Item>
            ))}
          </LabeledList>
        )}
      </Section>
      <Section title="Filters">
        {filterTypes.map(filter => (
          <Button
            key={filter.gas_id}
            icon={filter.enabled ? 'check-square-o' : 'square-o'}
            content={getGasLabel(filter.gas_id, filter.gas_name)}
            selected={filter.enabled}
            onClick={() => act('toggle_filter', {
              val: filter.gas_id,
            })} />
        ))}
      </Section>
    </Fragment>
  );
};
