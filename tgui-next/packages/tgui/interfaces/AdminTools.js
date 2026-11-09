import { Component, Fragment } from 'inferno';
import { useBackend } from '../backend';
import { Box, Button, Icon, Input, LabeledList, NumberInput, Section, Table } from '../components';

// hippie -- admin tools designed for tgui: the spawner (Create Object, Turf,
// Mob, Quick Create), the outfit manager and editor, and Manage Free Slots.
// Data and actions from hippiestation/code/modules/admin/admin_tools_tgui.dm.

const Picture = props => (props.icon
  ? (
    <img
      className="AdminTools__pic"
      src={props.icon}
      onError={e => {
        e.target.style.visibility = 'hidden';
      }} />
  )
  : (
    <span className="AdminTools__pic AdminTools__pic--none">
      <Icon name="cube" />
    </span>
  ));

// "/obj/item/gun/energy" under "/obj/item" reads "…/gun/energy"
const shortPath = (path, root) => (root && path.indexOf(root) === 0
  && path !== root
  ? '…' + path.substr(root.length)
  : path);

const DIRS = [
  [0, 'Any'], [1, 'N'], [2, 'S'], [4, 'E'], [8, 'W'],
  [5, 'NE'], [9, 'NW'], [6, 'SE'], [10, 'SW'],
];

const WHERE = [
  ['onfloor', 'Below me'],
  ['frompod', 'Below me, by pod'],
  ['inhand', 'In my hand'],
  ['inmarked', 'In marked'],
];

export class AdminSpawner extends Component {
  constructor() {
    super();
    this.state = { query: '' };
  }

  render() {
    const { act, data } = useBackend(this.props);
    const picked = data.picked || [];
    const pickedPaths = picked.map(p => p.path);
    const results = data.results || [];
    const search = () => act('search', { query: this.state.query });
    return (
      <Fragment>
        <Section>
          <Box className="AdminTools__searchRow"
            onKeyDown={e => e.keyCode === 13 && search()}>
            <input
              className="AdminTools__search"
              placeholder={'Search ' + data.total + ' types under '
                + data.root + ' (words, any order)'}
              value={this.state.query}
              onInput={e => this.setState({ query: e.target.value })} />
            <Button icon="search" content="Search" onClick={search} />
          </Box>
          <div className="AdminTools__results">
            {!data.query && (
              <Box color="label" p={1}>Type part of a path and search.</Box>
            )}
            {!!data.query && results.length === 0 && (
              <Box color="label" p={1}>No types match.</Box>
            )}
            {results.map(path => (
              <div
                key={path}
                className={'AdminTools__result'
                  + (pickedPaths.includes(path)
                    ? ' AdminTools__result--on'
                    : '')}
                onClick={() => act('pick', { path })}>
                {shortPath(path, data.root)}
              </div>
            ))}
            {results.length >= 200 && (
              <Box color="label" p={1}>First 200 shown: narrow it down.</Box>
            )}
          </div>
        </Section>
        <Section
          title={'To spawn (' + picked.length + ' of 5)'}
          buttons={picked.length > 0 && (
            <Button icon="times" content="Clear" onClick={() => act('clear')} />
          )}>
          {picked.length === 0 && (
            <Box color="label">Click results to pick up to five types.</Box>
          )}
          {picked.map(p => (
            <div key={p.path} className="AdminTools__picked">
              <Picture icon={p.icon} />
              <span className="AdminTools__pickedPath">{p.path}</span>
              <Button icon="times"
                onClick={() => act('pick', { path: p.path })} />
            </div>
          ))}
          <LabeledList>
            <LabeledList.Item label="Where">
              {WHERE.map(([value, label]) => (
                <Button key={value} content={label}
                  selected={data.where === value}
                  disabled={value === 'inmarked' && !data.marked}
                  tooltip={value === 'inmarked' && data.marked
                    ? data.marked
                    : null}
                  onClick={() => act('set', { field: 'where', value })} />
              ))}
            </LabeledList.Item>
            {(data.where === 'onfloor' || data.where === 'frompod') && (
              <LabeledList.Item label="Offset">
                <Input value={data.offset} width="90px"
                  onChange={(e, value) => act('set',
                    { field: 'offset', value })} />
                <Button content="Relative"
                  selected={data.offset_type === 'relative'}
                  onClick={() => act('set',
                    { field: 'offset_type', value: 'relative' })} />
                <Button content="Absolute"
                  selected={data.offset_type === 'absolute'}
                  onClick={() => act('set',
                    { field: 'offset_type', value: 'absolute' })} />
              </LabeledList.Item>
            )}
            <LabeledList.Item label="How many">
              <NumberInput value={data.count} minValue={1} maxValue={100}
                width="60px"
                onChange={(e, value) => act('set',
                  { field: 'count', value })} />
            </LabeledList.Item>
            <LabeledList.Item label="Facing">
              {DIRS.map(([value, label]) => (
                <Button key={value} content={label}
                  selected={data.dir === value}
                  onClick={() => act('set', { field: 'dir', value })} />
              ))}
            </LabeledList.Item>
            <LabeledList.Item label="Name">
              <Input value={data.name} width="220px" placeholder="(its own)"
                onChange={(e, value) => act('set',
                  { field: 'name', value })} />
            </LabeledList.Item>
          </LabeledList>
          <Button mt={1} icon="magic" content="Spawn" color="good"
            disabled={picked.length === 0}
            onClick={() => act('spawn')} />
        </Section>
      </Fragment>
    );
  }
}

export const OutfitManager = props => {
  const { act, data } = useBackend(props);
  const outfits = data.outfits || [];
  return (
    <Section
      title="Custom outfits"
      buttons={(
        <Fragment>
          <Button icon="plus" content="Create" onClick={() => act('create')} />
          <Button icon="file-import" content="Load from file"
            onClick={() => act('load')} />
        </Fragment>
      )}>
      {outfits.length === 0 && (
        <Box color="label">No custom outfits this round.</Box>
      )}
      {outfits.map(outfit => (
        <div key={outfit.ref} className="AdminTools__picked">
          <Icon name="tshirt" mr={1} />
          <span className="AdminTools__pickedPath">
            {outfit.name}
            {!!outfit.vv && <Box inline color="label" ml={1}>(VV)</Box>}
          </span>
          <Button icon="save" content="Save"
            onClick={() => act('save', { ref: outfit.ref })} />
          <Button icon="trash" color="bad"
            onClick={() => act('delete', { ref: outfit.ref })} />
        </div>
      ))}
    </Section>
  );
};

export class OutfitEditor extends Component {
  constructor() {
    super();
    this.state = { query: '' };
  }

  render() {
    const { act, data } = useBackend(this.props);
    const slots = data.slots || [];
    const editing = slots.find(s => s.key === data.editing);
    const search = () => act('search', { query: this.state.query });
    return (
      <Fragment>
        <Section>
          <LabeledList>
            <LabeledList.Item label="Outfit name">
              <Input value={data.name} width="260px"
                onChange={(e, value) => act('name', { value })} />
            </LabeledList.Item>
          </LabeledList>
        </Section>
        {!!editing && (
          <Section
            title={'Pick: ' + editing.label}
            buttons={(
              <Button icon="times" content="Cancel"
                onClick={() => act('done')} />
            )}>
            <Box className="AdminTools__searchRow"
              onKeyDown={e => e.keyCode === 13 && search()}>
              <input
                className="AdminTools__search"
                placeholder={'Search under ' + editing.root}
                value={this.state.query}
                onInput={e => this.setState({ query: e.target.value })} />
              <Button icon="search" content="Search" onClick={search} />
            </Box>
            <div className="AdminTools__results AdminTools__results--short">
              {(data.results || []).map(path => (
                <div key={path} className="AdminTools__result"
                  onClick={() => act('choose', { path })}>
                  {shortPath(path, editing.root)}
                </div>
              ))}
            </div>
          </Section>
        )}
        <Section title="Slots">
          <div className="AdminTools__slots">
            {slots.map(slot => (
              <div key={slot.key}
                className={'AdminTools__slot'
                  + (slot.key === data.editing
                    ? ' AdminTools__slot--on'
                    : '')}>
                <Picture icon={slot.icon} />
                <div className="AdminTools__slotMain"
                  onClick={() => act('edit', { slot: slot.key })}>
                  <div className="AdminTools__slotLabel">{slot.label}</div>
                  <div>{slot.name || 'Empty'}</div>
                </div>
                {!!slot.path && (
                  <Button icon="times"
                    onClick={() => act('empty', { slot: slot.key })} />
                )}
              </div>
            ))}
          </div>
          <Button mt={1} icon="check" content="Create outfit" color="good"
            onClick={() => act('create')} />
        </Section>
      </Fragment>
    );
  }
}

export class JobSlots extends Component {
  constructor() {
    super();
    this.state = { search: '' };
  }

  render() {
    const { act, data } = useBackend(this.props);
    const jobs = data.jobs || [];
    const deptOf = {};
    for (let dept of data.departments || []) {
      for (let title of dept.jobs) {
        if (!deptOf[title]) {
          deptOf[title] = dept.name;
        }
      }
    }
    const query = this.state.search.toLowerCase();
    const groups = {};
    for (let job of jobs) {
      if (query && !job.title.toLowerCase().includes(query)) {
        continue;
      }
      const dept = deptOf[job.title] || 'Other';
      (groups[dept] = groups[dept] || []).push(job);
    }
    // The departments in their usual order, the rest last
    const order = (data.departments || []).map(d => d.name)
      .concat(['Other']).filter(dept => groups[dept]);
    return (
      <Fragment>
        <Box mb={1}>
          <Input fluid placeholder="Search jobs..." value={this.state.search}
            onInput={(e, value) => this.setState({ search: value })} />
        </Box>
        {order.map(dept => (
          <Section key={dept} title={dept}>
            <Table>
              {groups[dept].map(job => (
                <Table.Row key={job.title} className="candystripe">
                  <Table.Cell>{job.title}</Table.Cell>
                  <Table.Cell collapsing textAlign="right" pr={1}>
                    <b>{job.current}</b>
                    {' / '}
                    {job.total < 0 ? '∞' : job.total}
                  </Table.Cell>
                  <Table.Cell collapsing textAlign="right">
                    {job.total >= 0 && (
                      <Fragment>
                        <Button icon="minus"
                          disabled={job.total <= job.current}
                          onClick={() => act('remove', { job: job.title })} />
                        <Button icon="plus"
                          onClick={() => act('add', { job: job.title })} />
                        <Button icon="pen" tooltip="Set a number"
                          onClick={() => act('custom', { job: job.title })} />
                        <Button icon="infinity" tooltip="Unlimit"
                          onClick={() => act('unlimit', { job: job.title })} />
                      </Fragment>
                    )}
                    {job.total < 0 && (
                      <Button icon="lock" content="Limit"
                        onClick={() => act('limit', { job: job.title })} />
                    )}
                  </Table.Cell>
                </Table.Row>
              ))}
            </Table>
          </Section>
        ))}
      </Fragment>
    );
  }
}
