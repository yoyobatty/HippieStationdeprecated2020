import { Fragment } from 'inferno';
import { useBackend } from '../backend';
import { Box, Button, Dropdown, LabeledList, NumberInput, Section, Table } from '../components';

const AlarmList = props => {
  const { alarms, onClear } = props;
  if (!alarms.length) {
    return <Box color="good">Systems Nominal</Box>;
  }
  return (
    <Table>
      {alarms.map(alarm => (
        <Table.Row key={alarm}>
          <Table.Cell color="average">{alarm}</Table.Cell>
          {onClear && (
            <Table.Cell collapsing>
              <Button
                icon="bell-slash"
                content="Clear"
                onClick={() => onClear(alarm)} />
            </Table.Cell>
          )}
        </Table.Row>
      ))}
    </Table>
  );
};

// A trip point: kelvin, or Off (null). Hot goes Off only when emagged.
const TripPoint = props => {
  const { value, min, max, canOff, editable, onSet } = props;
  if (!editable) {
    return <Box inline>{value === null ? 'Off' : value + ' K'}</Box>;
  }
  return (
    <Fragment>
      {value === null ? (
        <Box inline color="bad" mr={1}>Off</Box>
      ) : (
        <NumberInput
          width="80px"
          value={Math.round(value)}
          unit="K"
          minValue={min}
          maxValue={max}
          step={5}
          onChange={(e, newValue) => onSet(newValue)} />
      )}
      {!!canOff && (
        <Button
          ml={1}
          content={value === null ? 'On' : 'Off'}
          selected={value === null}
          onClick={() => onSet(value === null ? min : 'off')} />
      )}
    </Fragment>
  );
};

export const StationAlertConsole = props => {
  const { act, data } = useBackend(props);
  const categories = data.alarms || [];
  const fire = categories['Fire'] || [];
  const atmos = categories['Atmosphere'] || [];
  const power = categories['Power'] || [];
  const edit = !!data.can_edit;
  const emagged = !!data.emagged;
  const hotMax = emagged ? data.emagged_max : data.hot_max;
  const areaTrips = data.area_trips || [];
  const owned = areaTrips.map(area => area.ref);
  const choices = (data.alarm_areas || [])
    .filter(area => !owned.includes(area.ref));
  const set = (ref, which, value) => act('set', { ref, which, value });
  return (
    <Fragment>
      <Section
        title="Fire Alarms"
        buttons={!!data.emagged && (
          <Box inline color="bad" bold>Limits off</Box>
        )}>
        <AlarmList
          alarms={fire}
          onClear={edit && (name => act('reset', { name }))} />
      </Section>
      <Section title="Atmospherics Alarms">
        <AlarmList alarms={atmos} />
      </Section>
      <Section title="Power Alarms">
        <AlarmList alarms={power} />
      </Section>
      <Section title="Fire Alarm Trip Points">
        <LabeledList>
          <LabeledList.Item label="Station hot">
            <TripPoint
              value={data.station_hot}
              min={data.hot_min}
              max={hotMax}
              canOff={edit && !!data.emagged}
              editable={edit}
              onSet={value => set('station', 'hot', value)} />
          </LabeledList.Item>
          <LabeledList.Item label="Station cold">
            <TripPoint
              value={data.station_cold}
              min={0}
              max={data.cold_max}
              canOff={edit}
              editable={edit}
              onSet={value => set('station', 'cold', value)} />
          </LabeledList.Item>
        </LabeledList>
        {areaTrips.length > 0 && (
          <Table mt={1}>
            <Table.Row header>
              <Table.Cell>Area</Table.Cell>
              <Table.Cell>Hot</Table.Cell>
              <Table.Cell>Cold</Table.Cell>
              <Table.Cell collapsing />
            </Table.Row>
            {areaTrips.map(area => (
              <Table.Row key={area.ref}>
                <Table.Cell>{area.name}</Table.Cell>
                <Table.Cell>
                  <TripPoint
                    value={area.hot}
                    min={data.hot_min}
                    max={hotMax}
                    canOff={edit && !!data.emagged}
                    editable={edit}
                    onSet={value => set(area.ref, 'hot', value)} />
                </Table.Cell>
                <Table.Cell>
                  <TripPoint
                    value={area.cold}
                    min={0}
                    max={data.cold_max}
                    canOff={edit}
                    editable={edit}
                    onSet={value => set(area.ref, 'cold', value)} />
                </Table.Cell>
                <Table.Cell collapsing>
                  {edit && (
                    <Button
                      icon="undo"
                      tooltip="Station's"
                      onClick={() => act('unown', { ref: area.ref })} />
                  )}
                </Table.Cell>
              </Table.Row>
            ))}
          </Table>
        )}
        {edit && choices.length > 0 && (
          <Box mt={1}>
            <Dropdown
              width="260px"
              selected="Own trip points for..."
              options={choices.map(area => area.name)}
              onSelected={name => {
                const area = choices.find(choice => choice.name === name);
                if (area) {
                  act('own', { ref: area.ref });
                }
              }} />
          </Box>
        )}
      </Section>
    </Fragment>
  );
};
