import { Component, Fragment } from 'inferno';
import { useBackend } from '../backend';
import { Box, Button, Icon, NoticeBox, ProgressBar } from '../components';

// hippie -- the exosuit fabricator, redesigned
// (hippiestation/code/game/mecha/mech_fabricator_tgui.dm)

const COLUMN = {
  'overflow-y': 'auto',
  'overflow-x': 'hidden',
  'background-color': 'rgba(0, 0, 0, 0.33)',
  'box-shadow': 'inset 0 0 5px rgba(0, 0, 0, 0.5)',
  'padding': '6px',
  'box-sizing': 'border-box',
};

const ROW = {
  'display': 'flex',
  'align-items': 'center',
};

const sheets = (amount, sheet) => Math.floor(amount / sheet * 10) / 10;

const timeText = seconds => {
  const s = Math.round(seconds || 0);
  if (s < 60) {
    return s + 's';
  }
  return Math.floor(s / 60) + 'm ' + (s % 60) + 's';
};

const DesignIcon = props => {
  const { design } = props;
  const size = 32;
  if (!design.icon) {
    return (
      <Box inline width="32px" textAlign="center">
        <Icon name="cog" color="label" />
      </Box>
    );
  }
  const match = /(\d+)x(\d+)/.exec(design.icon);
  const native = match ? parseInt(match[1], 10) : 32;
  return (
    <Box
      inline
      position="relative"
      width={size + 'px'}
      height={size + 'px'}
      style={{ 'overflow': 'hidden', 'vertical-align': 'middle' }}>
      <Box
        className={design.icon}
        style={{
          'transform': 'scale(' + (size / native) + ')',
          'transform-origin': 'top left',
        }} />
    </Box>
  );
};

// What a part costs, each material in red where there isn't enough
const Costs = props => {
  const { cost, have, names, sheet } = props;
  return Object.keys(cost).map(id => {
    const short = (have[id] || 0) < cost[id];
    return (
      <Box
        key={id}
        inline
        mr={1}
        color={short ? 'bad' : 'label'}
        style={{ 'white-space': 'nowrap' }}>
        {sheets(cost[id], sheet) + ' ' + (names[id] || id)}
      </Box>
    );
  });
};

const Materials = props => {
  const { data, act } = props;
  const sheet = data.sheet;
  const mats = (data.mats || []).filter(mat => mat.amount > 0);
  return (
    <Fragment>
      <Box bold mb={0.5}>
        <Icon name="cubes" mr={0.5} />
        Materials
        {!!data.silo && (
          <Box inline color="label" ml={1} fontSize="11px">
            from the ore silo
          </Box>
        )}
      </Box>
      {!!data.connected && mats.length === 0 && (
        <Box color="label" italic mb={0.5}>None stored.</Box>
      )}
      {!data.connected && (
        <NoticeBox>No material storage connected.</NoticeBox>
      )}
      {!!data.on_hold && (
        <NoticeBox>The quartermaster has the silo on hold.</NoticeBox>
      )}
      {!!data.storage && !data.silo && (
        <ProgressBar
          mb={1}
          value={data.storage.total}
          maxValue={data.storage.max || 1}
          content={Math.round(data.storage.total / sheet) + ' / '
            + Math.round(data.storage.max / sheet) + ' sheets'} />
      )}
      {mats.map(mat => (
        <Box key={mat.id} mb={0.5} style={ROW}>
          <Box style={{ 'flex-grow': 1 }}>
            <Box inline style={{ 'text-transform': 'capitalize' }}>
              {mat.name}
            </Box>
            <Box inline color={mat.amount ? 'good' : 'label'} ml={0.5}>
              {sheets(mat.amount, sheet)}
            </Box>
          </Box>
          <Button
            icon="eject"
            content="1"
            disabled={mat.amount < sheet}
            onClick={() => act('eject', { mat: mat.id, amount: 1 })} />
          <Button
            content="10"
            disabled={mat.amount < sheet * 10}
            onClick={() => act('eject', { mat: mat.id, amount: 10 })} />
          <Button
            content="All"
            disabled={mat.amount < sheet}
            onClick={() => act('eject', { mat: mat.id, amount: 50 })} />
        </Box>
      ))}
      <Box mt={1} color="label" fontSize="11px">
        {'Parts use ' + data.coeff_mats + '% of their materials and '
          + data.coeff_time + '% of their time here.'}
      </Box>
      <Button
        mt={1}
        fluid
        icon="sync"
        content={data.syncing ? 'Updating designs...' : 'Sync with R&D'}
        disabled={!!data.syncing}
        onClick={() => act('sync')} />
    </Fragment>
  );
};

const PartRow = props => {
  const { design, data, act, have, open, onToggle } = props;
  let canBuild = true;
  for (const id of Object.keys(design.cost)) {
    if ((have[id] || 0) < design.cost[id]) {
      canBuild = false;
    }
  }
  return (
    <Box
      className="candystripe"
      style={{ 'padding': '4px', 'border-radius': '2px' }}>
      <Box style={ROW}>
        <DesignIcon design={design} />
        <Box ml={1} style={{ 'flex-grow': 1, 'min-width': 0 }}>
          <Box bold>{design.name}</Box>
          <Box fontSize="11px">
            <Costs
              cost={design.cost}
              have={have}
              names={data.mat_names}
              sheet={data.sheet} />
            <Box inline color="label">
              <Icon name="clock" mr={0.5} />
              {timeText(design.time)}
            </Box>
          </Box>
        </Box>
        <Button
          icon="info"
          color="transparent"
          selected={open}
          tooltip="What it is"
          tooltipPosition="left"
          onClick={onToggle} />
        <Button
          icon="plus"
          content="Queue"
          onClick={() => act('queue', { id: design.id })} />
        <Button
          icon="hammer"
          content="Build"
          disabled={!canBuild}
          onClick={() => act('build', { id: design.id })} />
      </Box>
      {!!open && (
        <Box mt={0.5} ml={5} color="label" fontSize="11px">
          {design.desc || 'No description.'}
        </Box>
      )}
    </Box>
  );
};

// The queue, what's printing and what it all needs
const Queue = props => {
  const { data, act, byId, have } = props;
  const queue = data.queue || [];
  const building = data.building;
  const needed = {};
  let seconds = 0;
  for (const entry of queue) {
    const design = byId[entry.id];
    if (!design) {
      continue;
    }
    seconds += design.time;
    for (const id of Object.keys(design.cost)) {
      needed[id] = (needed[id] || 0) + design.cost[id];
    }
  }
  const short = Object.keys(needed).filter(id => (have[id] || 0) < needed[id]);
  return (
    <Fragment>
      <Box bold mb={0.5}>
        <Icon name="industry" mr={0.5} />
        Now
      </Box>
      {!building && (
        <Box color="label" italic mb={1}>Nothing being built.</Box>
      )}
      {!!building && (
        <ProgressBar
          mb={1}
          color="good"
          value={building.length - building.left}
          maxValue={building.length || 1}
          content={building.name + ' - ' + timeText(building.left)} />
      )}
      <Box bold mb={0.5} style={ROW}>
        <Box style={{ 'flex-grow': 1 }}>
          <Icon name="list" mr={0.5} />
          {'Queue (' + queue.length + ')'}
        </Box>
        {!!data.processing && (
          <Box color="average" fontSize="11px">
            <Icon name="cog" spin mr={0.5} />
            running
          </Box>
        )}
      </Box>
      {queue.length === 0 && (
        <Box color="label" italic>Nothing waiting.</Box>
      )}
      {queue.map((entry, index) => {
        const design = byId[entry.id];
        let affordable = true;
        if (design) {
          for (const id of Object.keys(design.cost)) {
            if ((have[id] || 0) < design.cost[id]) {
              affordable = false;
            }
          }
        }
        return (
          <Box key={index} style={ROW} className="candystripe">
            <Box
              style={{ 'flex-grow': 1, 'min-width': 0 }}
              color={affordable ? null : 'bad'}>
              {(index + 1) + '. ' + entry.name}
            </Box>
            <Button
              icon="arrow-up"
              color="transparent"
              disabled={index === 0}
              onClick={() => act('queue_move', { index: index + 1, by: -1 })} />
            <Button
              icon="arrow-down"
              color="transparent"
              disabled={index === queue.length - 1}
              onClick={() => act('queue_move', { index: index + 1, by: 1 })} />
            <Button
              icon="times"
              color="transparent"
              onClick={() => act('queue_remove', { index: index + 1 })} />
          </Box>
        );
      })}
      {queue.length > 0 && (
        <Box mt={1}>
          <Box color="label" fontSize="11px" mb={0.5}>
            {'All of it: ' + timeText(seconds)}
          </Box>
          {short.length > 0 && (
            <Box color="bad" fontSize="11px" mb={0.5}>
              {'Short of ' + short.map(id => (
                sheets(needed[id] - (have[id] || 0), data.sheet) + ' '
                + (data.mat_names[id] || id))).join(', ')}
            </Box>
          )}
          <Button
            icon="play"
            content="Process queue"
            disabled={!!data.processing || !!building}
            onClick={() => act('process')} />
          <Button
            icon="trash"
            content="Clear"
            onClick={() => act('queue_clear')} />
        </Box>
      )}
    </Fragment>
  );
};

class ExosuitFabricatorMenu extends Component {
  constructor() {
    super();
    this.state = { set: null, search: '', open: null };
  }

  render() {
    const { act, data } = useBackend(this.props);
    const designs = data.designs || [];
    const sets = data.sets || [];
    const byId = {};
    for (const design of designs) {
      byId[design.id] = design;
    }
    const have = {};
    for (const mat of data.mats || []) {
      have[mat.id] = mat.amount;
    }
    const counts = {};
    for (const design of designs) {
      for (const set of design.sets) {
        counts[set] = (counts[set] || 0) + 1;
      }
    }
    const current = this.state.set || sets.find(set => counts[set]) || sets[0];
    const search = this.state.search.trim().toLowerCase();
    let shown = designs.filter(design => design.sets.includes(current));
    if (search) {
      shown = designs.filter(design => (
        design.name.toLowerCase().includes(search)
        || (design.desc || '').toLowerCase().includes(search)));
    }
    return (
      <Box
        style={{
          'position': 'absolute',
          'top': 0,
          'bottom': 0,
          'left': 0,
          'right': 0,
          'display': 'flex',
          'padding': '6px',
          'box-sizing': 'border-box',
        }}>
        <Box style={Object.assign({ 'width': '230px' }, COLUMN)}>
          <Materials data={data} act={act} />
        </Box>
        <Box
          mx={1}
          style={{
            'flex-grow': 1,
            'display': 'flex',
            'flex-direction': 'column',
            'min-width': 0,
          }}>
          <Box mb={0.5}>
            {sets.map(set => (
              <Button
                key={set}
                mb={0.5}
                selected={!search && set === current}
                disabled={!counts[set]}
                onClick={() => this.setState({ set, search: '' })}>
                {set}
                <Box inline ml={0.5} color="label">{counts[set] || 0}</Box>
              </Button>
            ))}
          </Box>
          <Box mb={0.5} style={ROW}>
            <Icon name="search" mr={0.5} />
            <input
              value={this.state.search}
              placeholder="Search every part..."
              onInput={e => this.setState({ search: e.target.value })}
              style={{
                'flex-grow': 1,
                'background-color': 'rgba(0, 0, 0, 0.4)',
                'color': '#ffffff',
                'border': '1px solid #404b6e',
                'padding': '3px',
              }} />
            {!search && (
              <Button
                ml={0.5}
                icon="plus-square"
                content="Queue all"
                disabled={!counts[current]}
                onClick={() => act('queue_set', { set: current })} />
            )}
          </Box>
          <Box style={Object.assign({ 'flex-grow': 1 }, COLUMN)}>
            {shown.length === 0 && (
              <Box color="label" italic>
                {search ? 'Nothing matches.' : 'Nothing researched here.'}
              </Box>
            )}
            {shown.map(design => (
              <PartRow
                key={design.id}
                design={design}
                data={data}
                act={act}
                have={have}
                open={this.state.open === design.id}
                onToggle={() => this.setState(prev => ({
                  open: prev.open === design.id ? null : design.id,
                }))} />
            ))}
          </Box>
        </Box>
        <Box style={Object.assign({ 'width': '270px' }, COLUMN)}>
          <Queue data={data} act={act} byId={byId} have={have} />
        </Box>
      </Box>
    );
  }
}

export const ExosuitFabricator = props => (
  <ExosuitFabricatorMenu state={props.state} dispatch={props.dispatch} />
);
