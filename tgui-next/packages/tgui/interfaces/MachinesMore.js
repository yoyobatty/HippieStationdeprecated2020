import { decodeHtmlEntities } from 'common/string';
import { Component, Fragment } from 'inferno';
import { useBackend } from '../backend';
import { Box, Button, Icon, LabeledList, NoticeBox, NumberInput, ProgressBar, Section, Table } from '../components';
import { paintCss } from './Exosuit';

// hippie -- more machines: an exosuit's maintenance and access panels (in
// the mech's own paint), the telepad control console, a gas analyzer's scan
// history, the prototype cloning console and the bluespace artillery. Data
// and actions from hippiestation/code/modules/tgui/machines_more_tgui.dm.

export const ExosuitMaint = props => {
  const { act, data } = useBackend(props);
  if (data.screen === 'access') {
    return (
      <Fragment>
        <style>{paintCss(data.paint)}</style>
        <Section
          title="Operation keycodes"
          buttons={(
            <Button icon="arrow-left" content="Back"
              onClick={() => act('back')} />
          )}>
          {data.required.length === 0 && (
            <Box color="label">None: anyone can pilot it.</Box>
          )}
          {data.required.map(a => (
            <Box key={a.id} className="ExoMaint__row">
              <span>{a.name}</span>
              <Button icon="times" content="Delete"
                onClick={() => act('remove', { id: a.id })} />
            </Box>
          ))}
        </Section>
        <Section title="On the card">
          {data.on_card.length === 0 && (
            <Box color="label">Nothing more to add.</Box>
          )}
          {data.on_card.map(a => (
            <Box key={a.id} className="ExoMaint__row">
              <span>{a.name}</span>
              <Button icon="plus" content="Add"
                onClick={() => act('add', { id: a.id })} />
            </Box>
          ))}
        </Section>
        <Section>
          <Button icon="lock" content="Finish" onClick={() => act('finish')} />
          <Box mt={1} color="bad">
            The ID upload panel locks; only the exosuit interface unlocks it.
          </Box>
        </Section>
      </Fragment>
    );
  }
  return (
    <Fragment>
      <style>{paintCss(data.paint)}</style>
      <Section title={data.name}>
        {!data.can_edit_access && !data.can_maint && (
          <Box color="label">This card has no maintenance rights here.</Box>
        )}
        {!!data.can_edit_access && (
          <Button fluid icon="key" content="Edit operation keycodes"
            onClick={() => act('access')} />
        )}
        {!!data.can_maint && (
          <Button fluid icon="wrench"
            content={(data.maint_on ? 'Terminate' : 'Initiate')
              + ' maintenance protocol'}
            onClick={() => act('maint')} />
        )}
        {!!data.maint_on && (
          <LabeledList>
            <LabeledList.Item label="Cabin pressure">
              <NumberInput
                value={data.pressure}
                unit="kPa"
                minValue={0}
                maxValue={1000}
                step={5}
                onChange={(e, value) => act('pressure', { value })} />
            </LabeledList.Item>
          </LabeledList>
        )}
      </Section>
    </Fragment>
  );
};

export const Telescience = props => {
  const { act, data } = useBackend(props);
  if (!data.telepad) {
    return (
      <NoticeBox>
        No telepad located. Upload its data with a multitool.
      </NoticeBox>
    );
  }
  return (
    <Fragment>
      <Section>
        <Box className="Telesci__screen">
          {!!data.maintenance && (
            <div>Telepad undergoing physical maintenance operations.</div>
          )}
          {decodeHtmlEntities(data.message || '')}
        </Box>
      </Section>
      <Section title="Coordinates">
        <LabeledList>
          <LabeledList.Item label="Bearing">
            <NumberInput width="90px" value={data.rotation}
              unit="°" minValue={-900}
              maxValue={900} step={1} stepPixelSize={4}
              onChange={(e, value) => act('rotation', { value })} />
          </LabeledList.Item>
          <LabeledList.Item label="Elevation">
            <NumberInput width="90px" value={data.angle}
              unit="°" minValue={1}
              maxValue={9999} step={0.1} stepPixelSize={2}
              onChange={(e, value) => act('angle', { value })} />
          </LabeledList.Item>
          <LabeledList.Item label="Sector">
            <NumberInput width="90px" value={data.sector} minValue={1}
              maxValue={10}
              onChange={(e, value) => act('sector', { value })} />
          </LabeledList.Item>
          <LabeledList.Item label="Power">
            {data.powers.map(p => (
              <Button
                key={p.index}
                content={p.power}
                selected={p.power === data.power}
                disabled={!p.usable}
                onClick={() => act('power', { index: p.index })} />
            ))}
          </LabeledList.Item>
        </LabeledList>
        <Box mt={1}>
          <Button icon="upload" content="Send" disabled={data.teleporting}
            onClick={() => act('send')} />
          <Button icon="download" content="Receive"
            disabled={data.teleporting}
            onClick={() => act('receive')} />
        </Box>
      </Section>
      <Section title="Crystals">
        <LabeledList>
          <LabeledList.Item label="Slots">
            {data.crystals} / {data.max_crystals}
          </LabeledList.Item>
          <LabeledList.Item label="GPS">
            {data.gps || 'None'}
            {!!data.gps && (
              <Button ml={1} icon="eject" content="Eject"
                onClick={() => act('eject_gps')} />
            )}
          </LabeledList.Item>
        </LabeledList>
        <Box mt={1}>
          <Button icon="sync" content="Recalibrate"
            onClick={() => act('recalibrate')} />
          <Button icon="eject" content="Eject crystals"
            disabled={!data.crystals}
            onClick={() => act('eject')} />
        </Box>
      </Section>
      <Section title="Last teleport">
        {!data.last && <Box color="label">No teleport data found.</Box>}
        {!!data.last && (
          <LabeledList>
            <LabeledList.Item label="Source">
              ({data.last.x}, {data.last.y})
            </LabeledList.Item>
            <LabeledList.Item label="Time">{data.last.time} s</LabeledList.Item>
          </LabeledList>
        )}
      </Section>
    </Fragment>
  );
};

const signed = (value, unit) => (value >= 0 ? '+' : '') + value + ' ' + unit;

export const AnalyzerHistory = props => {
  const { act, data } = useBackend(props);
  const rows = data.rows || [];
  return (
    <Section
      title={rows.length + ' readings, newest first'}
      buttons={(
        <Button icon="trash" content="Clear history" disabled={!rows.length}
          onClick={() => act('clear')} />
      )}>
      {rows.length === 0 && <Box color="label">No readings stored.</Box>}
      {rows.length > 0 && (
        <Table>
          <Table.Row header>
            <Table.Cell>Time</Table.Cell>
            <Table.Cell>Where</Table.Cell>
            <Table.Cell>Pressure</Table.Cell>
            <Table.Cell>Temperature</Table.Cell>
            <Table.Cell>Mix</Table.Cell>
            <Table.Cell>Change</Table.Cell>
          </Table.Row>
          {rows.map((row, i) => (
            <Table.Row key={i} className="candystripe">
              <Table.Cell color="label">{row.stamp}</Table.Cell>
              <Table.Cell>{decodeHtmlEntities(row.label)}</Table.Cell>
              <Table.Cell>{row.pressure} kPa</Table.Cell>
              <Table.Cell>
                {row.kelvin} K
                <Box color="label">{row.celsius} °C</Box>
              </Table.Cell>
              <Table.Cell>
                {row.gases.length === 0 && <Box color="label">empty</Box>}
                {row.gases.map(gas => (
                  <Box key={gas.name}>{gas.name} {gas.percent}%</Box>
                ))}
              </Table.Cell>
              <Table.Cell>
                {row.d_pressure === null
                  ? <Box color="label">first</Box>
                  : (
                    <Fragment>
                      <Box color={row.d_pressure ? 'average' : 'label'}>
                        {signed(row.d_pressure, 'kPa')}
                      </Box>
                      <Box color={row.d_temperature ? 'average' : 'label'}>
                        {signed(row.d_temperature, 'K')}
                      </Box>
                    </Fragment>
                  )}
              </Table.Cell>
            </Table.Row>
          ))}
        </Table>
      )}
    </Section>
  );
};

export const PrototypeCloning = props => {
  const { act, data } = useBackend(props);
  return (
    <Fragment>
      <Section
        title="Pod status"
        buttons={(
          <Button icon="sync" content="Refresh"
            onClick={() => act('refresh')} />
        )}>
        <Box>{decodeHtmlEntities(data.status || '') || 'Idle.'}</Box>
        {!data.scanner && <Box color="bad">ERROR: No scanner detected!</Box>}
        {!data.pods && <Box color="bad">ERROR: No pod detected!</Box>}
      </Section>
      {!!data.scanner && (
        <Section title="Cloning">
          <LabeledList>
            <LabeledList.Item label="Scanner">
              {data.occupant || 'Unoccupied'}
              {!!data.occupant && (
                <Box inline ml={1} color="label">
                  {data.loading ? 'Scanning...' : 'Ready to clone'}
                </Box>
              )}
            </LabeledList.Item>
            {!!data.scan_status && (
              <LabeledList.Item label="Last scan">
                {decodeHtmlEntities(data.scan_status)}
              </LabeledList.Item>
            )}
          </LabeledList>
          <Box mt={1}>
            <Button icon="dna" content="Clone"
              disabled={!data.occupant || data.loading}
              onClick={() => act('clone')} />
            <Button
              icon={data.locked ? 'unlock' : 'lock'}
              content={data.locked ? 'Unlock scanner' : 'Lock scanner'}
              disabled={!data.occupant}
              onClick={() => act('lock')} />
          </Box>
        </Section>
      )}
    </Fragment>
  );
};

export class ArtilleryControl extends Component {
  constructor() {
    super();
    this.state = { search: '', target: null };
  }

  render() {
    const { act, data } = useBackend(this.props);
    const query = this.state.search.toLowerCase();
    const areas = (data.areas || []).filter(a => !query
      || a.toLowerCase().includes(query));
    const ready = data.reload >= data.reload_cooldown;
    return (
      <Fragment>
        <Section title="Bluespace artillery">
          <ProgressBar
            value={data.reload / data.reload_cooldown}
            color={ready ? 'good' : 'average'}>
            {ready
              ? 'Charged'
              : 'Charging ' + data.reload + ' / ' + data.reload_cooldown}
          </ProgressBar>
          <Box mt={1} color="label">
            Deployment authorized by Nanotrasen Naval Command. Friendly fire
            is grounds for termination of your contract and life.
          </Box>
        </Section>
        <Section
          title="Target"
          buttons={(
            <Button
              icon="crosshairs"
              color="bad"
              content={this.state.target
                ? 'Open fire on ' + this.state.target
                : 'Open fire'}
              disabled={!ready || !this.state.target}
              onClick={() => act('fire', { area: this.state.target })} />
          )}>
          <input
            className="Artillery__search"
            placeholder="Search areas..."
            value={this.state.search}
            onInput={e => this.setState({ search: e.target.value })} />
          {areas.map(area => (
            <Box
              key={area}
              className={'Artillery__area'
                + (area === this.state.target ? ' Artillery__area--on' : '')}
              onClick={() => this.setState({ target: area })}>
              {area === this.state.target && <Icon name="crosshairs" mr={1} />}
              {area}
            </Box>
          ))}
        </Section>
      </Fragment>
    );
  }
}
