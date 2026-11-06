import { decodeHtmlEntities } from 'common/string';
import { Component, Fragment } from 'inferno';
import { useBackend } from '../backend';
import { Box, Button, Icon, Input, LabeledList, NoticeBox, ProgressBar, Section, Table, Tabs } from '../components';

// hippie -- service and misc machines moved off their old HTML windows: the
// jukebox, slot machine, holopad, seed extractor, limb grower, nav beacon,
// bank vault and the airlock/vent controllers. Data from hippiestation/code/
// game/machinery/service_tgui.dm.

const formatTime = deciseconds => {
  const seconds = Math.round(deciseconds / 10);
  return Math.floor(seconds / 60) + ':'
    + String(seconds % 60).padStart(2, '0');
};

export const Jukebox = props => {
  const { act, data } = useBackend(props);
  const tracks = data.tracks || [];
  return (
    <Fragment>
      <Section>
        <Box fontSize="16px" bold mb={0.5}>
          <Icon name="music" mr={1} color={data.active ? 'good' : 'label'} />
          {data.selected || 'No track'}
        </Box>
        {!!data.active && (
          <Box mb={1}>
            <ProgressBar
              value={data.length
                ? 1 - data.time_left / data.length
                : 0}>
              {formatTime(data.length - data.time_left)}
              {' / '}
              {formatTime(data.length)}
            </ProgressBar>
          </Box>
        )}
        <Button
          fluid
          textAlign="center"
          fontSize="14px"
          icon={data.active ? 'stop' : 'play'}
          color={data.active ? 'bad' : 'good'}
          disabled={!data.active && data.cooldown > 0}
          content={data.active
            ? 'SHUT IT DOWN'
            : (data.cooldown > 0
              ? 'Resetting (' + formatTime(data.cooldown) + ')'
              : 'BREAK IT DOWN')}
          onClick={() => act('toggle')} />
      </Section>
      <Section title="Tracks">
        {tracks.map(track => (
          <Button
            key={track.name}
            fluid
            icon={track.name === data.selected ? 'compact-disc' : 'circle'}
            selected={track.name === data.selected}
            disabled={data.active}
            onClick={() => act('select', { name: track.name })}>
            {track.name}
            <Box inline style={{ float: 'right' }} color="label">
              {formatTime(track.length)}
            </Box>
          </Button>
        ))}
      </Section>
    </Fragment>
  );
};

// The reels' symbols come as the old window's HTML: <font color='x'>c</font>,
// in HTML colour names; brighter shades so they read on the dark reels
const REEL_COLORS = {
  red: '#ff4d4d',
  orange: '#ff9f40',
  yellow: '#ffe14d',
  green: '#4ddd6a',
  blue: '#5c9dff',
  grey: '#b0b0b0',
  white: '#ffffff',
  fuchsia: '#ff5cf0',
};

const symbolOf = text => {
  const match = /color='(\w+)'>([^<]+)</.exec(text || '');
  return match
    ? {
      color: REEL_COLORS[match[1]] || match[1],
      char: decodeHtmlEntities(match[2]),
    }
    : { color: '#ffffff', char: text || ' ' };
};

export const SlotMachine = props => {
  const { act, data } = useBackend(props);
  const reels = data.reels || [];
  return (
    <Fragment>
      <Section>
        <div className="Service__reels">
          {reels.map((row, i) => (
            <div key={i}
              className={'Service__reelRow'
                + (i === 1 ? ' Service__reelRow--middle' : '')}>
              {row.map((cell, j) => {
                const symbol = symbolOf(cell);
                return (
                  <span
                    key={j}
                    className="Service__reel"
                    style={{ color: symbol.color }}>
                    {symbol.char}
                  </span>
                );
              })}
            </div>
          ))}
        </div>
        <Button
          fluid
          mt={1}
          textAlign="center"
          fontSize="14px"
          icon={data.working ? 'cog' : 'play'}
          iconSpin={data.working}
          color="good"
          disabled={data.working || data.balance < data.price}
          content={data.working
            ? 'Spinning...'
            : 'Play (' + data.price + ' cr)'}
          onClick={() => act('spin')} />
      </Section>
      <Section>
        <LabeledList>
          <LabeledList.Item
            label="Credit"
            buttons={!!data.balance && !data.working && (
              <Button
                icon="undo"
                content="Refund"
                onClick={() => act('refund')} />
            )}>
            {data.balance}
          </LabeledList.Item>
          <LabeledList.Item label="Prize money">
            {data.money}
          </LabeledList.Item>
          <LabeledList.Item label="Plays">
            {data.plays} ({data.jackpots} jackpots)
          </LabeledList.Item>
        </LabeledList>
      </Section>
    </Fragment>
  );
};

export class Holopad extends Component {
  constructor() {
    super();
    this.state = { search: '' };
  }

  render() {
    const { act, data } = useBackend(this.props);
    const { search } = this.state;
    const calls = data.calls || [];
    const term = search.toLowerCase();
    const areas = (data.areas || [])
      .filter(area => !term || area.toLowerCase().includes(term));
    return (
      <Fragment>
        {!!data.notice && (
          <NoticeBox>
            {data.notice}
            <Button
              ml={1}
              icon="times"
              content={data.outgoing ? 'Hang up' : 'OK'}
              onClick={() => act('main_menu')} />
          </NoticeBox>
        )}
        {calls.length > 0 && (
          <Section title="Calls">
            {calls.map(call => (
              <Box key={call.ref} mb={0.5}>
                {call.answered && (
                  <Button
                    icon="phone-slash"
                    color="bad"
                    content={'Disconnect ' + call.caller}
                    onClick={() => act('disconnect', { ref: call.ref })} />
                ) || (
                  <Button
                    icon="phone"
                    color="good"
                    content={'Answer ' + call.from}
                    onClick={() => act('answer', { ref: call.ref })} />
                )}
              </Box>
            ))}
          </Section>
        )}
        {!!data.on_network && (
          <Section
            title={data.elevated ? 'Connect' : 'Call'}
            buttons={(
              <Button
                icon="robot"
                content="Request AI"
                onClick={() => act('request_ai')} />
            )}>
            {!data.on_pad && (
              <Box color="average" mb={0.5}>
                Stand on the holopad to call.
              </Box>
            )}
            <Input
              fluid
              placeholder="Search..."
              value={search}
              onInput={(e, value) => this.setState({ search: value })} />
            <div className="Service__list">
              {areas.map(area => (
                <Button
                  key={area}
                  fluid
                  icon="phone-alt"
                  content={area}
                  disabled={!data.on_pad || data.outgoing}
                  onClick={() => act('call', { area })} />
              ))}
            </div>
          </Section>
        )}
        {!!data.disk && (
          <Section
            title="Holodisk"
            buttons={(
              <Button
                icon="eject"
                content="Eject"
                disabled={data.replay_mode}
                onClick={() => act('disk_eject')} />
            )}>
            {data.disk_record && (
              <Fragment>
                {data.replay_mode && (
                  <Button
                    icon="stop"
                    content="Stop"
                    onClick={() => act('replay_stop')} />
                ) || (
                  <Fragment>
                    <Button
                      icon="play"
                      content="Replay"
                      onClick={() => act('replay_start')} />
                    <Button
                      icon="redo"
                      content="Loop"
                      onClick={() => act('loop_start')} />
                  </Fragment>
                )}
                <Button
                  icon="trash"
                  content="Clear"
                  disabled={data.replay_mode}
                  onClick={() => act('record_clear')} />
              </Fragment>
            ) || (data.record_mode && (
              <Button
                icon="stop"
                color="bad"
                content="Stop recording"
                onClick={() => act('record_stop')} />
            ) || (
              <Button
                icon="circle"
                content="Record"
                onClick={() => act('record_start')} />
            ))}
          </Section>
        )}
      </Fragment>
    );
  }
}

const SEED_STATS = [
  ['lifespan', 'Life'],
  ['endurance', 'End'],
  ['maturation', 'Mat'],
  ['production', 'Prod'],
  ['yield', 'Yield'],
  ['potency', 'Pot'],
];

export class SeedExtractor extends Component {
  constructor() {
    super();
    this.state = { search: '', sortBy: 'name' };
  }

  render() {
    const { act, data } = useBackend(this.props);
    const { search, sortBy } = this.state;
    const term = search.toLowerCase();
    const seeds = (data.seeds || [])
      .filter(seed => !term || seed.name.toLowerCase().includes(term))
      .sort((a, b) => (sortBy === 'name'
        ? a.name.localeCompare(b.name)
        : b[sortBy] - a[sortBy]));
    return (
      <Section
        title={'Stored seeds (' + seeds.length + ')'}
        buttons={(
          <Input
            width="160px"
            placeholder="Search..."
            value={search}
            onInput={(e, value) => this.setState({ search: value })} />
        )}>
        {seeds.length === 0 && (
          <Box color="label">No seeds</Box>
        )}
        {seeds.length > 0 && (
          <Table>
            <Table.Row header>
              <Table.Cell
                className="Service__sortable"
                onClick={() => this.setState({ sortBy: 'name' })}>
                Name
              </Table.Cell>
              {SEED_STATS.map(stat => (
                <Table.Cell
                  key={stat[0]}
                  collapsing
                  textAlign="center"
                  className="Service__sortable"
                  color={sortBy === stat[0] ? 'good' : null}
                  onClick={() => this.setState({ sortBy: stat[0] })}>
                  {stat[1]}
                </Table.Cell>
              ))}
              <Table.Cell collapsing />
            </Table.Row>
            {seeds.map(seed => (
              <Table.Row key={seed.ref} className="candystripe">
                <Table.Cell bold>{seed.name}</Table.Cell>
                {SEED_STATS.map(stat => (
                  <Table.Cell key={stat[0]} collapsing textAlign="center">
                    {seed[stat[0]]}
                  </Table.Cell>
                ))}
                <Table.Cell collapsing>
                  <Button
                    content={'Vend (' + seed.amount + ')'}
                    onClick={() => act('vend', { ref: seed.ref })} />
                </Table.Cell>
              </Table.Row>
            ))}
          </Table>
        )}
      </Section>
    );
  }
}

export class LimbGrower extends Component {
  constructor() {
    super();
    this.state = { tab: null };
  }

  render() {
    const { act, data } = useBackend(this.props);
    const categories = data.categories || [];
    const tab = this.state.tab || (categories[0] && categories[0].name);
    const category = categories.find(cat => cat.name === tab);
    return (
      <Fragment>
        <Section
          title="Chemicals"
          buttons={!!data.busy && (
            <Box inline color="average">
              <Icon name="cog" spin mr={1} />
              Growing {data.building}
            </Box>
          )}>
          <ProgressBar
            value={data.max_volume ? data.volume / data.max_volume : 0}
            color="pink">
            {data.volume} / {data.max_volume} u
          </ProgressBar>
          <Table mt={0.5}>
            {(data.reagents || []).map(reagent => (
              <Table.Row key={reagent.path}>
                <Table.Cell>{reagent.name}</Table.Cell>
                <Table.Cell collapsing textAlign="right" pr={1}>
                  {reagent.volume} u
                </Table.Cell>
                <Table.Cell collapsing>
                  <Button
                    icon="trash"
                    content="Purge"
                    disabled={data.busy}
                    onClick={() => act('purge', { path: reagent.path })} />
                </Table.Cell>
              </Table.Row>
            ))}
          </Table>
        </Section>
        <Section>
          <Tabs activeTab={tab}>
            {categories.map(cat => (
              <Tabs.Tab
                key={cat.name}
                label={cat.name}
                onClick={() => this.setState({ tab: cat.name })} />
            ))}
          </Tabs>
          {category && category.designs.map(design => (
            <Box key={design.id} className="candystripe" py={0.25}>
              <Button
                icon="dna"
                content={design.name}
                disabled={data.busy || !design.can_build}
                onClick={() => act('make', { id: design.id })} />
              <Box inline ml={1}
                color={design.cost <= data.synthflesh ? 'label' : 'bad'}>
                {design.cost} Synthetic flesh
              </Box>
            </Box>
          ))}
        </Section>
      </Fragment>
    );
  }
}

export class NavBeacon extends Component {
  constructor() {
    super();
    this.state = { newKey: '', newValue: '' };
  }

  render() {
    const { act, data } = useBackend(this.props);
    const { newKey, newValue } = this.state;
    const codes = data.codes || [];
    const editable = data.editable;
    return (
      <Fragment>
        {!!data.locked && (
          <NoticeBox>Swipe card to unlock controls.</NoticeBox>
        )}
        <Section title="Location">
          {editable && (
            <Input
              fluid
              value={decodeHtmlEntities(data.location || '')}
              onChange={(e, value) => act('location', { value })} />
          ) || (
            <Box>{decodeHtmlEntities(data.location || '(none)')}</Box>
          )}
        </Section>
        <Section title="Transponder Codes">
          <Table>
            {codes.map(code => (
              <Table.Row key={code.key} className="candystripe">
                <Table.Cell bold>
                  {editable && (
                    <Input
                      width="120px"
                      value={decodeHtmlEntities(code.key)}
                      onChange={(e, value) => act('edit', {
                        old: code.key,
                        key: value,
                        value: code.value,
                      })} />
                  ) || decodeHtmlEntities(code.key)}
                </Table.Cell>
                <Table.Cell>
                  {editable && (
                    <Input
                      width="120px"
                      value={decodeHtmlEntities(code.value)}
                      onChange={(e, value) => act('edit', {
                        old: code.key,
                        key: code.key,
                        value,
                      })} />
                  ) || decodeHtmlEntities(code.value)}
                </Table.Cell>
                <Table.Cell collapsing>
                  {!!editable && (
                    <Button
                      icon="trash"
                      content="Delete"
                      onClick={() => act('delete', { key: code.key })} />
                  )}
                </Table.Cell>
              </Table.Row>
            ))}
          </Table>
          {!!editable && (
            <Box mt={1}>
              <Input
                width="120px"
                placeholder="Key"
                value={newKey}
                onInput={(e, value) => this.setState({ newKey: value })} />
              <Input
                width="120px"
                placeholder="Value"
                value={newValue}
                onInput={(e, value) => this.setState({ newValue: value })} />
              <Button
                icon="plus"
                content="Add"
                disabled={!newKey || !newValue}
                onClick={() => {
                  act('add', { key: newKey, value: newValue });
                  this.setState({ newKey: '', newValue: '' });
                }} />
            </Box>
          )}
        </Section>
      </Fragment>
    );
  }
}

export const BankVault = props => {
  const { act, data } = useBackend(props);
  return (
    <Section>
      <Box color="label" mb={1}>
        {data.station} secure vault. Authorized personnel only.
      </Box>
      <LabeledList>
        <LabeledList.Item label="Cargo budget">
          <Box inline fontSize="16px" bold>
            {data.balance === null ? 'N/A' : data.balance + ' cr'}
          </Box>
        </LabeledList.Item>
        {!!data.siphoning && (
          <LabeledList.Item label="Siphoned" color="average">
            {data.siphoned} cr
          </LabeledList.Item>
        )}
      </LabeledList>
      <Box mt={1}>
        {data.siphoning && (
          <Button
            fluid
            textAlign="center"
            icon="stop"
            color="bad"
            content="Halt Credit Siphon"
            onClick={() => act('halt')} />
        ) || (
          <Button
            fluid
            textAlign="center"
            icon="money-bill"
            content="Siphon Credits"
            onClick={() => act('siphon')} />
        )}
      </Box>
    </Section>
  );
};

export const AirlockController = props => {
  const { act, data } = useBackend(props);
  const status = data.status || [];
  const commands = data.commands || [];
  return (
    <Fragment>
      {status.length > 0 && (
        <Section title="Status">
          <LabeledList>
            {status.map(line => (
              <LabeledList.Item key={line[0]} label={line[0]} color={line[2]}>
                {line[1]}
              </LabeledList.Item>
            ))}
          </LabeledList>
        </Section>
      )}
      <Section title="Controls">
        {commands.length === 0 && (
          <Box color="label">No commands.</Box>
        )}
        {commands.map(command => (
          <Button
            key={command[1]}
            fluid
            color={command[2] === 'bad' ? 'bad' : 'default'}
            disabled={!!data.busy}
            content={command[0]}
            onClick={() => act('command', { command: command[1] })} />
        ))}
      </Section>
    </Fragment>
  );
};
