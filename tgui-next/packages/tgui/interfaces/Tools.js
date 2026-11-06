import { decodeHtmlEntities } from 'common/string';
import { Component, Fragment } from 'inferno';
import { useBackend } from '../backend';
import { Box, Button, Collapsible, Input, LabeledList, NoticeBox, Section, Tabs } from '../components';

// hippie -- blueprints, the camera bug and the RCD's airlock access moved
// off their old HTML windows. Data from hippiestation/code/game/objects/
// items/tools_tgui.dm.

export class Blueprints extends Component {
  constructor() {
    super();
    this.state = { search: '' };
  }

  render() {
    const { act, data } = useBackend(this.props);
    const { search } = this.state;
    const term = search.toLowerCase();
    const wiresets = (data.wiresets || [])
      .filter(set => !term || String(set.name).toLowerCase().includes(term));
    return (
      <Fragment>
        <Section title={data.station}>
          <Box italic color="label" mb={1}>{data.fluff}</Box>
          <LabeledList>
            <LabeledList.Item label="Area">
              {data.area_type === 'station' && (
                <Input
                  width="240px"
                  value={decodeHtmlEntities(data.area || '')}
                  onChange={(e, value) => act('rename', { name: value })} />
              ) || (
                <Box color="label">
                  {data.area_type === 'space'
                    ? 'Unclaimed territory'
                    : 'Not noted on the blueprints'}
                </Box>
              )}
            </LabeledList.Item>
            <LabeledList.Item label="Structural data">
              {data.viewing && (
                <Fragment>
                  <Button
                    icon="sync"
                    content="Refresh"
                    onClick={() => act('refresh')} />
                  <Button
                    icon="eye-slash"
                    content="Hide"
                    onClick={() => act('hide')} />
                </Fragment>
              ) || (
                <Button
                  icon="eye"
                  content="View"
                  onClick={() => act('view')} />
              )}
            </LabeledList.Item>
          </LabeledList>
          <Box mt={1}>
            <Button
              icon="drafting-compass"
              content="Create or modify an existing area"
              onClick={() => act('create_area')} />
          </Box>
        </Section>
        <Section
          title="Wire colour legend"
          buttons={(
            <Input
              width="150px"
              placeholder="Search..."
              value={search}
              onInput={(e, value) => this.setState({ search: value })} />
          )}>
          {wiresets.map(set => (
            <Collapsible key={set.name} title={set.name}>
              <Box px={1} pb={1}>
                {set.wires.map(wire => (
                  <Box key={wire.color}>
                    <Box inline width="90px" bold
                      style={{ color: wire.color }}>
                      {wire.color}
                    </Box>
                    {wire.name}
                  </Box>
                ))}
              </Box>
            </Collapsible>
          ))}
        </Section>
      </Fragment>
    );
  }
}

const BUGMODE_LIST = 0;
const BUGMODE_MONITOR = 1;
const BUGMODE_TRACK = 2;

export class CameraBug extends Component {
  constructor() {
    super();
    this.state = { search: '' };
  }

  render() {
    const { act, data } = useBackend(this.props);
    const { search } = this.state;
    const term = search.toLowerCase();
    const cameras = (data.cameras || [])
      .filter(cam => !term || cam.name.toLowerCase().includes(term));
    const tracking = data.tracking;
    return (
      <Fragment>
        {data.mode === BUGMODE_LIST && !!data.current && (
          <NoticeBox>
            Viewing {data.current}
            <Button
              ml={1}
              icon="times"
              content="Cancel camera view"
              onClick={() => act('cancel_view')} />
          </NoticeBox>
        )}
        {data.mode === BUGMODE_MONITOR && !!data.current && (
          <Section
            title={'Analyzing ' + data.current}
            buttons={(
              <Button
                icon="list"
                content="Select Camera"
                onClick={() => act('list')} />
            )}>
            {!!data.offline && (
              <Box color="bad">Camera Offline</Box>
            )}
            {!data.offline && (data.report || []).length === 0 && (
              <Box color="label">No motion detected.</Box>
            )}
            {(data.report || []).map(entry => (
              <Box key={entry.ref} mb={0.5}>
                <b>{entry.name}</b>
                {!!entry.state && (
                  <Box inline color="label" ml={1}>({entry.state})</Box>
                )}
                <Button
                  ml={1}
                  icon="crosshairs"
                  content="Track"
                  onClick={() => act('track', { ref: entry.ref })} />
              </Box>
            ))}
          </Section>
        )}
        {data.mode === BUGMODE_TRACK && !!tracking && (
          <Section
            title={'Tracking ' + tracking.name}
            buttons={(
              <Button
                icon="times"
                content="Cancel Tracking"
                onClick={() => act('list')} />
            )}>
            {tracking.last_found && (
              <Box>
                Last seen near{' '}
                {tracking.last_cam && (
                  <Button
                    content={tracking.last_found}
                    onClick={() => act('view', { ref: tracking.last_cam })} />
                ) || tracking.last_found}
                <Box inline color="label" ml={1}>
                  {tracking.seconds < 15
                    ? '(now)'
                    : '(' + Math.floor(tracking.seconds / 60) + ':'
                      + String(tracking.seconds % 60).padStart(2, '0')
                      + ' ago)'}
                </Box>
                {!!tracking.bugged && (
                  <Button
                    ml={1}
                    icon="bolt"
                    color="bad"
                    content="Disable"
                    onClick={() => act('emp', { ref: tracking.last_cam })} />
                )}
              </Box>
            ) || (
              <Box color="label">Not yet seen.</Box>
            )}
          </Section>
        )}
        <Section
          title={'Cameras (' + cameras.length + ')'}
          buttons={(
            <Input
              width="150px"
              placeholder="Search..."
              value={search}
              onInput={(e, value) => this.setState({ search: value })} />
          )}>
          {cameras.length === 0 && (
            <Box color="label">No bugged cameras found.</Box>
          )}
          {cameras.map(cam => (
            <Box key={cam.ref} className="candystripe" py={0.25}>
              <Button
                icon="video"
                content={cam.name}
                selected={cam.name === data.current}
                onClick={() => act('view', { ref: cam.ref })} />
              <Button
                icon="search"
                content="Monitor"
                onClick={() => act('monitor', { ref: cam.ref })} />
              {!!cam.bugged && (
                <Button
                  icon="bolt"
                  color="bad"
                  content="Disable"
                  onClick={() => act('emp', { ref: cam.ref })} />
              )}
            </Box>
          ))}
        </Section>
      </Fragment>
    );
  }
}

export class RcdAccess extends Component {
  constructor() {
    super();
    this.state = { region: null };
  }

  render() {
    const { act, data } = useBackend(this.props);
    const regions = data.regions || [];
    const region = this.state.region || (regions[0] && regions[0].name);
    const current = regions.find(each => each.name === region);
    return (
      <Fragment>
        <Section>
          <LabeledList>
            <LabeledList.Item label="Restriction Type">
              <Button
                content={data.one_access
                  ? 'At least one access required'
                  : 'All accesses required'}
                onClick={() => act('one')} />
            </LabeledList.Item>
            <LabeledList.Item label="Required">
              {data.count || 'None'}
              <Button
                ml={1}
                icon="eraser"
                content="Remove All"
                disabled={!data.count}
                onClick={() => act('clear')} />
            </LabeledList.Item>
          </LabeledList>
        </Section>
        <Section>
          <Tabs activeTab={region}>
            {regions.map(each => (
              <Tabs.Tab
                key={each.name}
                label={each.name + ' ('
                  + each.accesses.filter(a => a.on).length + ')'}
                onClick={() => this.setState({ region: each.name })} />
            ))}
          </Tabs>
          {current && current.accesses.map(access => (
            <Button.Checkbox
              key={access.id}
              checked={access.on}
              content={access.name}
              onClick={() => act('access', { id: access.id })} />
          ))}
        </Section>
      </Fragment>
    );
  }
}
