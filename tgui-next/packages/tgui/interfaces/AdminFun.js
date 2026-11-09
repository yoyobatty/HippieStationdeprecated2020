// hippie -- more admin windows (admin_fun_tgui.dm): dynamic mode, Trigger
// Event, the reagent container spawner and a sound emitter's settings.
import { decodeHtmlEntities } from 'common/string';
import { Component, Fragment } from 'inferno';
import { useBackend } from '../backend';
import { Box, Button, Icon, Input, NoticeBox, NumberInput, ProgressBar, Section, Tabs } from '../components';

const text = value => decodeHtmlEntities(String(value || ''));

const seconds = s => {
  const n = Math.round(s || 0);
  return n >= 60 ? Math.floor(n / 60) + 'm ' + (n % 60) + 's' : n + 's';
};

// ---------------------------------------------------------------------------
// Dynamic mode
// ---------------------------------------------------------------------------

const TOGGLES = [
  ['forced_extended', 'Force extended', 'No rulesets drafted.'],
  ['no_stacking', 'No stacking',
    'Only one round-ender unless threat goes over the stacking limit.'],
  ['classic_secret', 'Classic secret',
    'One roundstart ruleset, then only traitors and minor roles.'],
];

// [key, label, unit, min, max, step, before the round only]
const NUMBERS = [
  ['forced_threat', 'Forced threat', '', -1, 100, 1, true],
  ['high_pop_limit', 'High pop limit', 'players', 0, 200, 1, true],
  ['stacking_limit', 'Stacking limit', 'threat', 0, 101, 1, false],
  ['curve_centre', 'Curve centre', '', -5, 5, 0.5, true],
  ['curve_width', 'Curve width', '', 0.5, 4, 0.5, true],
  ['latejoin_min', 'Latejoin delay min', 'min', 1, 120, 1, true],
  ['latejoin_max', 'Latejoin delay max', 'min', 1, 120, 1, true],
  ['midround_min', 'Midround delay min', 'min', 1, 120, 1, true],
  ['midround_max', 'Midround delay max', 'min', 1, 120, 1, true],
];

const DynamicOptions = props => {
  const { data, act } = props;
  const options = data.options || {};
  return (
    <Fragment>
      {!data.is_dynamic && (
        <NoticeBox>
          {"The mode isn't dynamic" + (data.started ? '.' : ' yet.')}
        </NoticeBox>
      )}
      <Section title="Rules">
        {TOGGLES.map(([key, label, about]) => (
          <Box key={key} className="AdminFun__option">
            <Box className="AdminFun__optionText">
              <b>{label}</b>
              <Box className="AdminFun__muted">{about}</Box>
            </Box>
            <Button icon={options[key] ? 'toggle-on' : 'toggle-off'}
              content={options[key] ? 'On' : 'Off'}
              selected={!!options[key]}
              onClick={() => act('toggle', { option: key })} />
          </Box>
        ))}
      </Section>
      <Section title="Numbers">
        {NUMBERS.map(([key, label, unit, min, max, step, before]) => (
          <Box key={key} className="AdminFun__option">
            <Box className="AdminFun__optionText">
              {label}
              {before && !!data.started && (
                <span className="AdminFun__muted"> (set before the round)</span>
              )}
            </Box>
            <NumberInput value={options[key]} unit={unit}
              minValue={min} maxValue={max} step={step} width="90px"
              onChange={(e, value) => act('set', {
                option: key,
                value,
              })} />
          </Box>
        ))}
      </Section>
    </Fragment>
  );
};

class DynamicRound extends Component {
  constructor() {
    super();
    this.state = { amount: 10 };
  }

  render() {
    const { data, act } = this.props;
    const round = data.round;
    if (!round) {
      return <NoticeBox>No dynamic round is running.</NoticeBox>;
    }
    return (
      <Fragment>
        <Box className="AdminFun__stats">
          <Box className="AdminFun__stat">
            <Box className="AdminFun__statValue">{round.threat_level}</Box>
            <Box className="AdminFun__muted">Threat level</Box>
          </Box>
          <Box className="AdminFun__stat AdminFun__stat--wide">
            <ProgressBar value={round.threat / Math.max(1, round.threat_level)}
              color="bad">
              {round.threat + ' left to spend'}
            </ProgressBar>
            <Box className="AdminFun__muted" mt={0.5}>
              {round.peaceful + '% of rounds are more peaceful'}
            </Box>
          </Box>
          <Button icon="code" content="VV" onClick={() => act('vv')} />
        </Box>
        <Section title="Threat">
          <NumberInput value={this.state.amount} minValue={1} maxValue={100}
            width="60px"
            onChange={(e, value) => this.setState({ amount: value })} />
          <Button ml={1} icon="plus" content="Add"
            onClick={() => act('adjust_threat', {
              amount: this.state.amount,
            })} />
          <Button icon="minus" content="Spend"
            onClick={() => act('adjust_threat', {
              amount: -this.state.amount,
            })} />
        </Section>
        <Section title={'Injections (' + round.injection_chance + '% chance)'}>
          <Box className="AdminFun__option">
            <Box className="AdminFun__optionText">
              Latejoin in {seconds(round.latejoin_in)}
            </Box>
            <Button content="Now" onClick={() => act('inject_late')} />
          </Box>
          <Box className="AdminFun__option">
            <Box className="AdminFun__optionText">
              Midround in {seconds(round.midround_in)}
            </Box>
            <Button content="Now" onClick={() => act('inject_mid')} />
          </Box>
        </Section>
        <Section title="Rulesets run">
          {(round.executed || []).length === 0 && (
            <Box color="label">None.</Box>
          )}
          {(round.executed || []).map((r, i) => (
            <Box key={i} className="AdminFun__ruleset">
              <span className="AdminFun__tag">{r.type}</span>
              {r.name}
            </Box>
          ))}
        </Section>
      </Fragment>
    );
  }
}

export const AdminDynamic = props => {
  const { act, data } = useBackend(props);
  const tab = data.tab;
  return (
    <Fragment>
      <Tabs>
        <Tabs.Tab selected={tab === 'options'} label="Options"
          onClick={() => act('tab', { tab: 'options' })} />
        <Tabs.Tab selected={tab === 'round'} label="This round"
          onClick={() => act('tab', { tab: 'round' })} />
        <Tabs.Tab selected={tab === 'log'} label="Threat log"
          onClick={() => act('tab', { tab: 'log' })} />
      </Tabs>
      {!!data.notice && (
        <Box className={'AdminFun__notice'
          + (data.notice[1] ? '' : ' AdminFun__notice--bad')}>
          {data.notice[0]}
        </Box>
      )}
      {tab === 'options' && <DynamicOptions data={data} act={act} />}
      {tab === 'round' && <DynamicRound data={data} act={act} />}
      {tab === 'log' && (
        <Fragment>
          {!data.round && <NoticeBox>No dynamic round is running.</NoticeBox>}
          {(data.log || []).map((line, i) => (
            <Box key={i} className="AdminFun__logLine">{text(line)}</Box>
          ))}
        </Fragment>
      )}
    </Fragment>
  );
};

// ---------------------------------------------------------------------------
// Trigger Event
// ---------------------------------------------------------------------------

const EVENT_KINDS = [
  ['station', 'Station'],
  ['wizard', 'Wizard'],
  ['holiday', 'Holiday'],
];

export class AdminEvents extends Component {
  constructor() {
    super();
    this.state = { search: '', kind: 'station' };
  }

  render() {
    const { act, data } = useBackend(this.props);
    const events = data.events || [];
    const query = this.state.search.toLowerCase();
    const shown = events
      .filter(e => query
        ? e.name.toLowerCase().includes(query)
        : e.kind === this.state.kind)
      .sort((a, b) => a.name < b.name ? -1 : 1);
    return (
      <Fragment>
        <Box mb={1}>
          <Input fluid placeholder="Search every event..."
            value={this.state.search}
            onInput={(e, value) => this.setState({ search: value })} />
        </Box>
        {!query && (
          <Tabs>
            {EVENT_KINDS.map(([kind, label]) => (
              <Tabs.Tab key={kind} selected={this.state.kind === kind}
                label={label + ' ('
                  + events.filter(e => e.kind === kind).length + ')'}
                onClick={() => this.setState({ kind })} />
            ))}
          </Tabs>
        )}
        <Box className="AdminFun__muted" mb={1}>
          {data.players + ' players alive. Grey tags are why an event'
            + ' won\'t fire by itself, Run fires it anyway.'}
        </Box>
        {shown.map(e => (
          <Box key={e.ref} className="AdminFun__event">
            <Box className="AdminFun__eventMain">
              <b>{e.name}</b>
              <span className="AdminFun__muted">
                {' weight ' + e.weight + ' · ran ' + e.ran + '/' + e.max}
              </span>
              <Box>
                {(e.stops || []).map(s => (
                  <span key={s} className="AdminFun__stop">{s}</span>
                ))}
              </Box>
            </Box>
            <Button icon="play" content="Run" color="caution"
              onClick={() => act('run', { ref: e.ref })} />
          </Box>
        ))}
        {shown.length === 0 && <Box color="label">Nothing matches.</Box>}
      </Fragment>
    );
  }
}

// ---------------------------------------------------------------------------
// Spawn reagent container
// ---------------------------------------------------------------------------

const searchList = (list, query, limit) => {
  const q = query.toLowerCase();
  if (!q) {
    return [];
  }
  return list
    .filter(x => (x.name || '').toLowerCase().includes(q)
      || x.path.toLowerCase().includes(q))
    .slice(0, limit);
};

class ContainerEditor extends Component {
  constructor() {
    super();
    this.state = { containerSearch: '', reagentSearch: '' };
  }

  render() {
    const { value, onChange, containers, reagents, title } = this.props;
    const container = containers.find(c => c.path === value.container);
    const total = value.reagents.reduce((sum, r) => sum + r.volume, 0);
    const capacity = container ? container.volume : 0;
    const setReagents = list => onChange({ ...value, reagents: list });
    return (
      <Section title={title} className="AdminFun__container">
        <Box className="AdminFun__picked">
          <Icon name="flask" mr={1} />
          {container ? (
            <Fragment>
              <b>{container.name}</b>
              <span className="AdminFun__muted">
                {' ' + container.volume + 'u'}
              </span>
            </Fragment>
          ) : <span className="AdminFun__muted">No container</span>}
        </Box>
        <Input fluid placeholder="Find a container..."
          value={this.state.containerSearch}
          onInput={(e, v) => this.setState({ containerSearch: v })} />
        {searchList(containers, this.state.containerSearch, 12).map(c => (
          <Box key={c.path} className="AdminFun__pick"
            onClick={() => {
              onChange({ ...value, container: c.path });
              this.setState({ containerSearch: '' });
            }}>
            {c.name}
            <span className="AdminFun__muted">{' ' + c.volume + 'u'}</span>
          </Box>
        ))}
        <Box className="AdminFun__heading">Reagents</Box>
        {value.reagents.map((r, i) => (
          <Box key={r.reagent} className="AdminFun__reagent">
            <span className="AdminFun__reagentName">{r.name}</span>
            <NumberInput value={r.volume} minValue={1} maxValue={10000}
              unit="u" width="70px"
              onChange={(e, v) => setReagents(value.reagents
                .map((x, j) => j === i ? { ...x, volume: v } : x))} />
            <Button icon="times" color="transparent"
              onClick={() => setReagents(value.reagents
                .filter((x, j) => j !== i))} />
          </Box>
        ))}
        <Input fluid placeholder="Add a reagent..."
          value={this.state.reagentSearch}
          onInput={(e, v) => this.setState({ reagentSearch: v })} />
        {searchList(reagents, this.state.reagentSearch, 12).map(r => (
          <Box key={r.path} className="AdminFun__pick"
            onClick={() => {
              if (!value.reagents.some(x => x.reagent === r.path)) {
                setReagents(value.reagents.concat([{
                  reagent: r.path,
                  name: r.name,
                  volume: 10,
                }]));
              }
              this.setState({ reagentSearch: '' });
            }}>
            {r.name}
          </Box>
        ))}
        <Box mt={1}>
          <ProgressBar value={capacity ? total / capacity : 0}
            color={total > capacity ? 'average' : 'good'}>
            {total + ' / ' + capacity + 'u'
              + (total > capacity ? ' (the container gets bigger to fit)' : '')}
          </ProgressBar>
        </Box>
      </Section>
    );
  }
}

const EMPTY = { container: '/obj/item/reagent_containers/glass/beaker/large',
  reagents: [] };

const forServer = c => ({
  container: c.container,
  reagents: c.reagents.map(r => ({ reagent: r.reagent, volume: r.volume })),
});

export class AdminBeakers extends Component {
  constructor() {
    super();
    this.state = {
      mode: 'container',
      first: EMPTY,
      second: EMPTY,
      timer: 5,
    };
  }

  render() {
    const { act, data } = useBackend(this.props);
    const containers = data.containers || [];
    const reagents = data.reagents || [];
    const { mode, first, second } = this.state;
    return (
      <Fragment>
        <Tabs>
          <Tabs.Tab selected={mode === 'container'} label="Container"
            onClick={() => this.setState({ mode: 'container' })} />
          <Tabs.Tab selected={mode === 'grenade'} label="Grenade"
            onClick={() => this.setState({ mode: 'grenade' })} />
        </Tabs>
        {mode === 'container' && (
          <Fragment>
            <ContainerEditor title="Container" value={first}
              containers={containers} reagents={reagents}
              onChange={v => this.setState({ first: v })} />
            <Button fluid icon="magic" content="Spawn under me"
              color="good" textAlign="center"
              onClick={() => act('spawn_container', {
                container: forServer(first),
              })} />
          </Fragment>
        )}
        {mode === 'grenade' && (
          <Fragment>
            <Box className="AdminFun__pair">
              <ContainerEditor title="Beaker 1" value={first}
                containers={containers} reagents={reagents}
                onChange={v => this.setState({ first: v })} />
              <ContainerEditor title="Beaker 2" value={second}
                containers={containers} reagents={reagents}
                onChange={v => this.setState({ second: v })} />
            </Box>
            <Box className="AdminFun__option">
              <Box className="AdminFun__optionText">Timer</Box>
              <NumberInput value={this.state.timer} minValue={1}
                maxValue={300} unit="s" width="70px"
                onChange={(e, v) => this.setState({ timer: v })} />
            </Box>
            <Button fluid icon="bomb" content="Spawn grenade under me"
              color="bad" textAlign="center"
              onClick={() => act('spawn_grenade', {
                first: forServer(first),
                second: forServer(second),
                timer: this.state.timer,
              })} />
          </Fragment>
        )}
      </Fragment>
    );
  }
}

// ---------------------------------------------------------------------------
// A sound emitter
// ---------------------------------------------------------------------------

export const AdminSoundEmitter = props => {
  const { act, data } = useBackend(props);
  const direct = data.mode === 'direct';
  return (
    <Fragment>
      <Section title="Sound">
        <Box className="AdminFun__option">
          <Box className="AdminFun__optionText">
            <Icon name="music" mr={1} />
            {data.file
              ? <b>{data.file}</b>
              : <span className="AdminFun__muted">No file</span>}
          </Box>
          <Button icon="folder-open" content="Choose"
            onClick={() => act('file')} />
        </Box>
        <Box className="AdminFun__option">
          <Box className="AdminFun__optionText">Volume</Box>
          <NumberInput value={data.volume} minValue={0} maxValue={100}
            unit="%" width="70px"
            onChange={(e, value) => act('volume', { value })} />
        </Box>
        <Box className="AdminFun__option">
          <Box className="AdminFun__optionText">Label</Box>
          <Input value={text(data.label)} width="160px"
            onChange={(e, value) => act('label', { text: value })} />
        </Box>
      </Section>
      <Section title="Who hears it">
        <Box mb={1}>
          <Button content="Like a sound" selected={!direct}
            onClick={() => act('mode', { value: 'local' })} />
          <Button content="Straight to players" selected={direct}
            onClick={() => act('mode', { value: 'direct' })} />
        </Box>
        {direct && (
          <Box>
            <Button content="In a radius" selected={data.range === 'radius'}
              onClick={() => act('range', { value: 'radius' })} />
            <Button content="This z-level" selected={data.range === 'zlevel'}
              onClick={() => act('range', { value: 'zlevel' })} />
            <Button content="Everyone" selected={data.range === 'global'}
              onClick={() => act('range', { value: 'global' })} />
            {data.range === 'radius' && (
              <NumberInput ml={1} value={data.radius} minValue={0}
                maxValue={127} unit="tiles" width="80px"
                onChange={(e, value) => act('radius', { value })} />
            )}
          </Box>
        )}
      </Section>
      <Box className="AdminFun__option">
        <Button icon="play" content="Play" color="good" disabled={!data.file}
          onClick={() => act('play')} />
        <Box className="AdminFun__optionText AdminFun__muted" ml={1}>
          {'At ' + data.x + ',' + data.y + ',' + data.z}
        </Box>
        <Button icon="location-arrow" content="Jump"
          onClick={() => act('jump')} />
      </Box>
    </Fragment>
  );
};
