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

const EQ_BARS = 14;

// 0..n-1; the build turns [...Array(n).keys()] into one item
const range = n => {
  const out = [];
  for (let i = 0; i < n; i++) {
    out.push(i);
  }
  return out;
};

export const Jukebox = props => {
  const { act, data } = useBackend(props);
  const tracks = data.tracks || [];
  const elapsed = data.active ? data.length - data.time_left : 0;
  return (
    <Fragment>
      <div className="Jukebox__screen">
        <Box color="label" fontSize="10px" mb={0.5}>
          {data.active ? 'NOW PLAYING' : 'STOPPED'}
        </Box>
        <div className="Jukebox__title">
          {data.selected || 'No track'}
        </div>
        <div
          className={'Jukebox__eq'
            + (data.active ? ' Jukebox__eq--playing' : '')}>
          {range(EQ_BARS).map(i => (
            <span
              key={i}
              className="Jukebox__bar"
              style={{ 'animation-delay': (-(i * 37) % 600) + 'ms' }} />
          ))}
        </div>
        <div className="Jukebox__time">
          <span>{formatTime(elapsed)}</span>
          <div className="Jukebox__track">
            <div
              className="Jukebox__progress"
              style={{
                width: (data.length ? elapsed / data.length * 100 : 0) + '%',
              }} />
          </div>
          <span>{formatTime(data.length)}</span>
        </div>
        <div className="Jukebox__controls">
          <div
            className={'Jukebox__play'
              + (data.active ? ' Jukebox__play--stop' : '')
              + (!data.active && data.cooldown > 0
                ? ' Jukebox__play--off'
                : '')}
            title={data.active ? 'SHUT IT DOWN' : 'BREAK IT DOWN'}
            onClick={() => (data.active || !data.cooldown)
              && act('toggle')}>
            <Icon name={data.active ? 'stop' : 'play'} />
          </div>
          <Box mt={0.5} bold fontSize="11px"
            color={data.active ? 'bad' : 'good'}>
            {data.active
              ? 'SHUT IT DOWN'
              : (data.cooldown > 0
                ? 'Resetting ' + formatTime(data.cooldown)
                : 'BREAK IT DOWN')}
          </Box>
        </div>
      </div>
      <Section title={'Tracks (' + tracks.length + ')'}>
        {tracks.map((track, i) => {
          const picked = track.name === data.selected;
          return (
            <div
              key={track.name}
              className={'Jukebox__row'
                + (picked ? ' Jukebox__row--picked' : '')
                + (data.active ? ' Jukebox__row--locked' : '')}
              onClick={() => !data.active && !picked
                && act('select', { name: track.name })}>
              <span className="Jukebox__num">
                {picked
                  ? <Icon name={data.active ? 'volume-up' : 'compact-disc'} />
                  : i + 1}
              </span>
              <span className="Jukebox__name">{track.name}</span>
              <span className="Jukebox__len">{formatTime(track.length)}</span>
            </div>
          );
        })}
      </Section>
    </Fragment>
  );
};

// The reels' symbols come as the old window's HTML: <font color='x'>c</font>,
// in HTML colour names; shades that read on the cream reel strips
const REEL_COLORS = {
  red: '#d01818',
  orange: '#e06a00',
  yellow: '#c99a00',
  green: '#1d9a35',
  blue: '#1f5fd6',
  grey: '#6b6b6b',
  white: '#2a2a2a',
  fuchsia: '#c21ab4',
};

const symbolOf = text => {
  const match = /color='(\w+)'>([^<]+)</.exec(text || '');
  return match
    ? {
      color: REEL_COLORS[match[1]] || match[1],
      char: decodeHtmlEntities(match[2]),
    }
    : { color: '#2a2a2a', char: text || ' ' };
};

// The cells in a run of three or more of the same symbol on a line, as
// get_lines() (slotmachine.dm) counts a win
const winningCells = reels => {
  const cells = {};
  reels.forEach((row, r) => {
    let start = 0;
    for (let c = 1; c <= row.length; c++) {
      if (c === row.length || row[c] !== row[start]) {
        if (c - start >= 3) {
          for (let k = start; k < c; k++) {
            cells[r + ':' + k] = true;
          }
        }
        start = c;
      }
    }
  });
  return cells;
};

const PAYTABLE = [
  ['7 7 7 7 7', 'middle line', 'JACKPOT'],
  ['5 in a row', 'any line', '1000'],
  ['4 in a row', 'any line', '400'],
  ['3 in a row', 'any line', 'free games'],
];

export const SlotMachine = props => {
  const { act, data } = useBackend(props);
  const reels = data.reels || [];
  const spinning = data.spinning || [];
  const wins = data.working ? {} : winningCells(reels);
  const canSpin = !data.working && data.balance >= data.price;
  return (
    <div className="Slots__cabinet">
      <div className="Slots__marquee">
        <div className="Slots__lights">
          {range(12).map(i => (
            <span key={i}
              className={'Slots__light'
                + (data.working ? ' Slots__light--chase' : '')}
              style={{ 'animation-delay': (i * 80) + 'ms' }} />
          ))}
        </div>
        <div className="Slots__jackpotLabel">JACKPOT</div>
        <div className="Slots__led Slots__led--big">{data.money}</div>
      </div>
      <div className="Slots__body">
        <div className="Slots__window">
          {[0, 1, 2, 3, 4].map(col => (
            <div
              key={col}
              className={'Slots__reel'
                + (spinning[col] ? ' Slots__reel--spinning' : '')}>
              <div className="Slots__strip">
                {reels.map((row, r) => {
                  const symbol = symbolOf(row[col]);
                  return (
                    <div
                      key={r}
                      className={'Slots__symbol'
                        + (wins[r + ':' + col] ? ' Slots__symbol--win' : '')}
                      style={{ color: symbol.color }}>
                      {symbol.char}
                    </div>
                  );
                })}
              </div>
            </div>
          ))}
          <div className="Slots__payline" />
        </div>
        <div
          className={'Slots__lever'
            + (data.working ? ' Slots__lever--pulled' : '')
            + (canSpin ? '' : ' Slots__lever--off')}
          title={'Pull (' + data.price + ' cr)'}
          onClick={() => canSpin && act('spin')}>
          <div className="Slots__knob" />
          <div className="Slots__stick" />
        </div>
      </div>
      <div className="Slots__panel">
        <div className="Slots__readout">
          <div className="Slots__readoutLabel">CREDIT</div>
          <div className="Slots__led">{data.balance}</div>
        </div>
        <div className="Slots__readout">
          <div className="Slots__readoutLabel">BET</div>
          <div className="Slots__led">{data.price}</div>
        </div>
        <div className="Slots__buttons">
          <div
            className={'Slots__button Slots__button--spin'
              + (canSpin ? '' : ' Slots__button--off')}
            onClick={() => canSpin && act('spin')}>
            {data.working ? 'SPINNING' : 'SPIN'}
          </div>
          <div
            className={'Slots__button'
              + (data.balance > 0 && !data.working
                ? ''
                : ' Slots__button--off')}
            onClick={() => data.balance > 0 && !data.working
              && act('refund')}>
            CASH OUT
          </div>
        </div>
      </div>
      <div className="Slots__paytable">
        {PAYTABLE.map(line => (
          <div key={line[0]} className="Slots__payline-row">
            <span>{line[0]}</span>
            <span className="Slots__payWhere">{line[1]}</span>
            <span className="Slots__payWin">{line[2]}</span>
          </div>
        ))}
        <div className="Slots__stats">
          {data.plays} plays · {data.jackpots} jackpots
        </div>
      </div>
    </div>
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
