import { Component, Fragment } from 'inferno';
import { useBackend } from '../backend';
import { Box, Button, Flex, Icon, Input, LabeledList, NoticeBox, Section, Table } from '../components';

// hippie -- the ID console (hippiestation/.../computer/card_tgui.dm)

const DEPT_ORDER = [
  'Command',
  'Security',
  'Engineering',
  'Medical',
  'Science',
  'Supply',
  'Service',
  'Other',
];

// can_open_job()/can_close_job(): 1 allowed, 0 denied, -1 limit, -2 cooldown
const SLOT_ALLOWED = 1;
const SLOT_COOLDOWN = -2;

const formatWait = seconds => {
  const mins = Math.floor(seconds / 60);
  const secs = seconds % 60;
  return mins + ':' + (secs < 10 ? '0' : '') + secs;
};

const CardSlots = props => {
  const { data, act } = props;
  const { scan, modify, holding_id, silicon, authenticated } = data;
  const slotButton = (card, action, emptyText) => (
    <Button
      fluid
      icon={card ? 'eject' : 'id-card'}
      content={card || (holding_id && !silicon ? 'Insert held ID' : emptyText)}
      disabled={!card && (!holding_id || silicon)}
      onClick={() => act(action)} />
  );
  let status = 'Not logged in';
  if (authenticated === 2) {
    status = 'Logged in: full access';
  } else if (authenticated === 1) {
    status = 'Logged in: own department';
  }
  return (
    <Section>
      <Flex align="center">
        <Flex.Item grow={1} mr={1}>
          <Box color="label" mb={0.5}>Your ID</Box>
          {slotButton(scan, 'eject_scan', 'Empty')}
        </Flex.Item>
        <Flex.Item grow={1} mr={1}>
          <Box color="label" mb={0.5}>ID to change</Box>
          {slotButton(modify && modify.name, 'eject_modify', 'Empty')}
        </Flex.Item>
        <Flex.Item>
          <Box color={authenticated ? 'good' : 'label'} mb={0.5}>
            {status}
          </Box>
          {authenticated ? (
            <Button
              icon="sign-out-alt"
              content="Log out"
              onClick={() => act('logout')} />
          ) : (
            <Button
              icon="sign-in-alt"
              content="Log in"
              disabled={!modify || (!scan && !silicon)}
              onClick={() => act('login')} />
          )}
        </Flex.Item>
      </Flex>
    </Section>
  );
};

class CardTab extends Component {
  constructor() {
    super();
    this.state = {
      search: '',
      custom: '',
    };
  }

  render() {
    const { data, act } = this.props;
    const { search, custom } = this.state;
    const { modify, authenticated } = data;
    if (!modify) {
      return (
        <NoticeBox>
          No ID inserted.
        </NoticeBox>
      );
    }
    if (!authenticated) {
      return (
        <Fragment>
          <Section title="ID card">
            <LabeledList>
              <LabeledList.Item label="Name">
                {modify.owner || 'Unregistered'}
              </LabeledList.Item>
              <LabeledList.Item label="Assignment">
                {modify.assignment}
              </LabeledList.Item>
            </LabeledList>
          </Section>
          <NoticeBox>
            Log in with an ID that can change IDs, or a head of staff&apos;s
            for their own department.
          </NoticeBox>
        </Fragment>
      );
    }
    const has = {};
    for (let id of modify.access || []) {
      has[id] = true;
    }
    const allowed = {};
    for (let id of data.regions_allowed || []) {
      allowed[id] = true;
    }
    const query = search.toLowerCase();
    const regions = data.regions
      .filter(region => authenticated === 2 || allowed[region.id])
      .map(region => ({
        ...region,
        shown: region.accesses.filter(access => !query
          || access.name.toLowerCase().includes(query)),
      }))
      .filter(region => region.shown.length > 0);
    return (
      <Fragment>
        <Section title="ID card">
          <LabeledList>
            <LabeledList.Item label="Name">
              <Input
                width="250px"
                value={modify.owner || ''}
                onChange={(e, value) => act('rename', { name: value })} />
            </LabeledList.Item>
            <LabeledList.Item label="Assignment">
              {modify.assignment}
              {authenticated === 1 && (
                <Button
                  ml={1}
                  icon="user-minus"
                  content="Demote"
                  disabled={!data.can_demote}
                  tooltip={data.can_demote
                    ? null
                    : 'Not one of your department'}
                  onClick={() => act('demote')} />
              )}
            </LabeledList.Item>
          </LabeledList>
        </Section>
        {authenticated === 2 && (
          <Section title="Job">
            <Box mb={1}>
              <Button
                content="Unassigned"
                selected={modify.assignment === 'Unassigned'}
                onClick={() => act('assign', { job: 'Unassigned' })} />
              <Input
                ml={1}
                width="180px"
                placeholder="Custom assignment"
                value={custom}
                onInput={(e, value) => this.setState({ custom: value })} />
              <Button
                icon="pen"
                content="Set"
                disabled={!custom}
                onClick={() => act('assign_custom', { title: custom })} />
            </Box>
            {data.job_groups.map(group => (
              <Box key={group.name} mb={0.5}>
                <Box inline bold width="100px">{group.name}</Box>
                {group.jobs.map(job => (
                  <Button
                    key={job}
                    content={job}
                    selected={modify.assignment === job}
                    onClick={() => act('assign', { job })} />
                ))}
              </Box>
            ))}
          </Section>
        )}
        <Section
          title="Access"
          buttons={(
            <Input
              width="200px"
              placeholder="Search access..."
              value={search}
              onInput={(e, value) => this.setState({ search: value })} />
          )}>
          {regions.length === 0 && (
            <NoticeBox>Nothing matches that.</NoticeBox>
          )}
          <Flex wrap="wrap">
            {regions.map(region => (
              <Box
                key={region.id}
                width="210px"
                mr={1}
                mb={1}
                p={0.5}
                style={{ 'background-color': 'rgba(0, 0, 0, 0.25)' }}>
                <Box bold mb={0.5}>
                  {region.name}
                </Box>
                <Box mb={0.5}>
                  <Button
                    icon="check-double"
                    content="Grant all"
                    onClick={() => act('region', {
                      region: region.id,
                      allowed: 1,
                    })} />
                  <Button
                    icon="times"
                    content="Revoke all"
                    onClick={() => act('region', {
                      region: region.id,
                      allowed: 0,
                    })} />
                </Box>
                {region.shown.map(access => (
                  <Button
                    key={access.id}
                    fluid
                    icon={has[access.id] ? 'check' : null}
                    content={access.name}
                    selected={!!has[access.id]}
                    onClick={() => act('access', {
                      access: access.id,
                      allowed: has[access.id] ? 0 : 1,
                    })} />
                ))}
              </Box>
            ))}
          </Flex>
        </Section>
      </Fragment>
    );
  }
}

const SlotsTab = props => {
  const { data, act } = props;
  if (data.target_dept) {
    return (
      <NoticeBox>
        Slots: main console only.
      </NoticeBox>
    );
  }
  const slotCell = (job, state, action, label) => {
    if (state === SLOT_COOLDOWN) {
      return (
        <Box color="average">
          <Icon name="hourglass-half" mr={0.5} />
          {formatWait(job.wait)}
        </Box>
      );
    }
    return (
      <Button
        content={label}
        disabled={state !== SLOT_ALLOWED || !data.can_slots}
        onClick={() => act(action, { job: job.title })} />
    );
  };
  return (
    <Fragment>
      {!data.can_slots && (
        <NoticeBox>
          Authorized ID required.
        </NoticeBox>
      )}
      <Section>
        <Table>
          <Table.Row header>
            <Table.Cell>Job</Table.Cell>
            <Table.Cell collapsing>Slots</Table.Cell>
            <Table.Cell collapsing>Open</Table.Cell>
            <Table.Cell collapsing>Close</Table.Cell>
            <Table.Cell collapsing>Priority</Table.Cell>
          </Table.Row>
          {data.slots.map(job => (
            <Table.Row key={job.title} className="candystripe">
              <Table.Cell>
                {job.title}
                {!!job.prioritized && (
                  <Icon name="star" ml={0.5} color="average" />
                )}
              </Table.Cell>
              <Table.Cell collapsing>
                {job.current + ' / ' + job.total}
              </Table.Cell>
              <Table.Cell collapsing>
                {slotCell(job, job.open, 'open_slot', 'Open')}
              </Table.Cell>
              <Table.Cell collapsing>
                {slotCell(job, job.close, 'close_slot', 'Close')}
              </Table.Cell>
              <Table.Cell collapsing>
                <Button
                  icon="star"
                  content={job.prioritized ? 'Prioritized' : 'Prioritize'}
                  selected={!!job.prioritized}
                  disabled={!data.can_slots || !job.can_prioritize}
                  onClick={() => act('prioritize', { job: job.title })} />
              </Table.Cell>
            </Table.Row>
          ))}
        </Table>
      </Section>
    </Fragment>
  );
};

class ManifestTab extends Component {
  constructor() {
    super();
    this.state = {
      search: '',
    };
  }

  render() {
    const { data, act } = this.props;
    const { search } = this.state;
    const query = search.toLowerCase();
    const groups = {};
    for (let entry of data.manifest) {
      if (query && !entry.name.toLowerCase().includes(query)
        && !entry.rank.toLowerCase().includes(query)) {
        continue;
      }
      (groups[entry.dept] = groups[entry.dept] || []).push(entry);
    }
    const depts = DEPT_ORDER.filter(dept => groups[dept]);
    return (
      <Section
        title="Crew manifest"
        buttons={(
          <Fragment>
            <Input
              width="200px"
              placeholder="Search names and jobs..."
              value={search}
              onInput={(e, value) => this.setState({ search: value })} />
            <Button
              icon="print"
              content={data.printing ? 'Printing...' : 'Print'}
              disabled={data.printing}
              onClick={() => act('print')} />
          </Fragment>
        )}>
        {depts.length === 0 && (
          <NoticeBox>
            {query ? 'Nobody matches that.' : 'Nobody on the manifest.'}
          </NoticeBox>
        )}
        {depts.map(dept => (
          <Box key={dept} mb={1}>
            <Box bold color="label" mb={0.5}>
              {dept + ' (' + groups[dept].length + ')'}
            </Box>
            <Table>
              {groups[dept].map(entry => (
                <Table.Row key={entry.name + entry.rank}
                  className="candystripe">
                  <Table.Cell width="300px">{entry.name}</Table.Cell>
                  <Table.Cell color="label">{entry.rank}</Table.Cell>
                </Table.Row>
              ))}
            </Table>
          </Box>
        ))}
      </Section>
    );
  }
}

class IdConsoleMenu extends Component {
  constructor() {
    super();
    this.state = {
      tab: 'card',
    };
  }

  render() {
    const { data, act } = this.props;
    const { tab } = this.state;
    const tabs = [
      ['card', 'id-card', 'ID card'],
      ['slots', 'briefcase', 'Job slots'],
      ['manifest', 'users', 'Crew manifest'],
    ];
    return (
      <Fragment>
        <CardSlots data={data} act={act} />
        <Box mb={1}>
          {tabs.map(entry => (
            <Button
              key={entry[0]}
              icon={entry[1]}
              content={entry[2]}
              selected={tab === entry[0]}
              onClick={() => this.setState({ tab: entry[0] })} />
          ))}
        </Box>
        {tab === 'card' && <CardTab data={data} act={act} />}
        {tab === 'slots' && <SlotsTab data={data} act={act} />}
        {tab === 'manifest' && <ManifestTab data={data} act={act} />}
      </Fragment>
    );
  }
}

export const IdConsole = props => {
  const { act, data } = useBackend(props);
  return <IdConsoleMenu data={data} act={act} />;
};
