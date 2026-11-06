import { Component, Fragment } from 'inferno';
import { useBackend } from '../backend';
import { Box, Button, Icon, LabeledList, NoticeBox, NumberInput, ProgressBar, Section, Table } from '../components';

// hippie -- cargo and mining machines moved off their old HTML windows: the
// bounty console, the ore silo, the smelter's console, the coin press and
// the auxiliary base console. Data from hippiestation/code/modules/mining/
// cargo_mining_tgui.dm.

// "3/5" or "120/200 u" as a fraction, for a progress bar
const fractionOf = text => {
  const match = /(\d+(?:\.\d+)?)\s*\/\s*(\d+(?:\.\d+)?)/.exec(text || '');
  if (!match || Number(match[2]) <= 0) {
    return null;
  }
  return Math.min(1, Number(match[1]) / Number(match[2]));
};

const bountyOrder = bounty => (bounty.can_claim && 0)
  || (bounty.claimed && 3)
  || (bounty.priority && 1)
  || 2;

export class BountyConsole extends Component {
  constructor() {
    super();
    this.state = { hideClaimed: false };
  }

  render() {
    const { act, data } = useBackend(this.props);
    const { hideClaimed } = this.state;
    const bounties = (data.bounties || [])
      .filter(bounty => !hideClaimed || !bounty.claimed)
      .sort((a, b) => bountyOrder(a) - bountyOrder(b));
    return (
      <Fragment>
        <Section>
          <Box inline fontSize="18px" bold>
            {data.credits} cr
          </Box>
          <Box inline color="label" ml={1}>Cargo budget</Box>
          <Box inline style={{ float: 'right' }}>
            <Button.Checkbox
              checked={hideClaimed}
              content="Hide claimed"
              onClick={() => this.setState({ hideClaimed: !hideClaimed })} />
            <Button
              icon="print"
              content="Print"
              onClick={() => act('print')} />
          </Box>
        </Section>
        <div className="CargoMining__cards">
          {bounties.map(bounty => {
            const fraction = fractionOf(bounty.completion);
            return (
              <div
                key={bounty.ref}
                className={'CargoMining__card'
                  + (bounty.claimed ? ' CargoMining__card--done' : '')
                  + (bounty.priority ? ' CargoMining__card--priority' : '')}>
                <Box bold mb={0.5}>
                  {bounty.name}
                  {!!bounty.priority && (
                    <Box inline color="average" ml={1} fontSize="11px">
                      HIGH PRIORITY
                    </Box>
                  )}
                </Box>
                <Box fontSize="11px" color="label" mb={0.5}>
                  {bounty.description}
                </Box>
                <Box mb={0.5}>
                  <Icon name="coins" color="yellow" mr={1} />
                  {bounty.reward}
                </Box>
                {fraction !== null && (
                  <ProgressBar
                    value={fraction}
                    color={fraction >= 1 ? 'good' : 'teal'}>
                    {bounty.completion}
                  </ProgressBar>
                ) || (
                  <Box>{bounty.completion}</Box>
                )}
                <Box mt={0.5} textAlign="right">
                  {bounty.claimed && (
                    <Box color="label">Claimed</Box>
                  ) || (
                    <Button
                      icon="check"
                      content="Claim"
                      color={bounty.can_claim ? 'good' : 'default'}
                      disabled={!bounty.can_claim}
                      onClick={() => act('claim', { ref: bounty.ref })} />
                  )}
                </Box>
              </div>
            );
          })}
        </div>
      </Fragment>
    );
  }
}

const EJECT_AMOUNTS = [1, 5, 20, 50];

export const OreSilo = props => {
  const { act, data } = useBackend(props);
  const materials = (data.materials || []).filter(mat => mat.sheets > 0);
  const machines = data.machines || [];
  const logs = data.logs || [];
  return (
    <Fragment>
      <Section title="Stored">
        {materials.length === 0 && (
          <Box color="label">Empty</Box>
        )}
        <Table>
          {materials.map(mat => (
            <Table.Row key={mat.id} className="candystripe">
              <Table.Cell bold>{mat.name}</Table.Cell>
              <Table.Cell collapsing textAlign="right" pr={1}>
                {mat.sheets} sheets
              </Table.Cell>
              <Table.Cell collapsing>
                {EJECT_AMOUNTS.map(amount => (
                  <Button
                    key={amount}
                    content={amount}
                    disabled={mat.sheets < amount}
                    onClick={() => act('eject', { id: mat.id, amount })} />
                ))}
                <Button
                  content="All"
                  disabled={mat.sheets < 1}
                  onClick={() => act('eject', {
                    id: mat.id,
                    amount: Math.floor(mat.sheets),
                  })} />
              </Table.Cell>
            </Table.Row>
          ))}
        </Table>
      </Section>
      <Section title={'Connected (' + machines.length + ')'}>
        {machines.length === 0 && (
          <Box color="label">None</Box>
        )}
        <Table>
          {machines.map(machine => (
            <Table.Row key={machine.ref} className="candystripe">
              <Table.Cell bold>{machine.name}</Table.Cell>
              <Table.Cell color="label">{machine.area}</Table.Cell>
              <Table.Cell collapsing>
                <Button
                  icon={machine.held ? 'pause' : 'play'}
                  content={machine.held ? 'Held' : 'Allowed'}
                  color={machine.held ? 'average' : 'good'}
                  onClick={() => act(machine.held ? 'allow' : 'hold', {
                    key: machine.hold_key,
                  })} />
                <Button
                  icon="unlink"
                  content="Remove"
                  onClick={() => act('remove', { ref: machine.ref })} />
              </Table.Cell>
            </Table.Row>
          ))}
        </Table>
      </Section>
      <Section title="Access log">
        {logs.length === 0 && (
          <Box color="label">Empty</Box>
        )}
        <Table>
          {logs.map((entry, i) => (
            <Table.Row key={i} className="candystripe">
              <Table.Cell collapsing color="label">{entry.time}</Table.Cell>
              <Table.Cell>
                <b>{entry.machine}</b>
                <Box inline color="label" ml={1}>{entry.area}</Box>
                <Box fontSize="11px">{entry.action}</Box>
              </Table.Cell>
              <Table.Cell
                textAlign="right"
                color={entry.out ? 'bad' : 'good'}>
                {entry.changes}
              </Table.Cell>
            </Table.Row>
          ))}
        </Table>
      </Section>
    </Fragment>
  );
};

export const SmelterConsole = props => {
  const { act, data } = useBackend(props);
  const materials = data.materials || [];
  const alloys = data.alloys || [];
  return (
    <Fragment>
      <Section>
        <Button
          fluid
          textAlign="center"
          fontSize="14px"
          icon="power-off"
          color={data.on ? 'good' : 'default'}
          content={data.on ? 'On' : 'Off'}
          onClick={() => act('power')} />
      </Section>
      <Section title="Materials">
        <Table>
          {materials.map(mat => (
            <Table.Row key={mat.id} className="candystripe">
              <Table.Cell bold>{mat.name}</Table.Cell>
              <Table.Cell collapsing textAlign="right" pr={1}>
                <Box color={mat.amount > 0 ? null : 'label'}>
                  {mat.sheets} sheets
                </Box>
              </Table.Cell>
              <Table.Cell collapsing>
                <Button
                  icon={mat.selected ? 'fire' : 'circle'}
                  content={mat.selected ? 'Smelting' : 'Smelt'}
                  selected={mat.selected}
                  onClick={() => act('material', { id: mat.id })} />
              </Table.Cell>
            </Table.Row>
          ))}
        </Table>
      </Section>
      <Section title="Alloys">
        {alloys.length === 0 && (
          <Box color="label">None</Box>
        )}
        <Table>
          {alloys.map(alloy => (
            <Table.Row key={alloy.id} className="candystripe">
              <Table.Cell bold>{alloy.name}</Table.Cell>
              <Table.Cell collapsing>
                <Button
                  icon={alloy.selected ? 'fire' : 'circle'}
                  content={alloy.selected ? 'Smelting' : 'Smelt'}
                  selected={alloy.selected}
                  onClick={() => act('alloy', { id: alloy.id })} />
              </Table.Cell>
            </Table.Row>
          ))}
        </Table>
      </Section>
    </Fragment>
  );
};

export const CoinPress = props => {
  const { act, data } = useBackend(props);
  const materials = (data.materials || [])
    .filter(mat => mat.amount > 0 || mat.id === data.chosen);
  const chosen = (data.materials || []).find(mat => mat.id === data.chosen);
  return (
    <Fragment>
      <Section title="Material">
        {materials.length === 0 && (
          <Box color="label">Empty</Box>
        )}
        <Table>
          {materials.map(mat => (
            <Table.Row key={mat.id} className="candystripe">
              <Table.Cell bold>{mat.name}</Table.Cell>
              <Table.Cell collapsing textAlign="right" pr={1}>
                {mat.amount} cm³
              </Table.Cell>
              <Table.Cell collapsing textAlign="right" pr={1} color="label">
                {mat.coins} coins
              </Table.Cell>
              <Table.Cell collapsing>
                <Button
                  content={mat.id === data.chosen ? 'Chosen' : 'Choose'}
                  selected={mat.id === data.chosen}
                  disabled={data.processing}
                  onClick={() => act('choose', { id: mat.id })} />
              </Table.Cell>
            </Table.Row>
          ))}
        </Table>
      </Section>
      <Section title="Press">
        <LabeledList>
          <LabeledList.Item label="Coins">
            {[-10, -1].map(step => (
              <Button
                key={step}
                content={step}
                disabled={data.processing || data.count + step < 0}
                onClick={() => act('count', { count: data.count + step })} />
            ))}
            <NumberInput
              width="60px"
              value={data.count}
              minValue={0}
              maxValue={1000}
              onChange={(e, value) => act('count', { count: value })} />
            {[1, 10].map(step => (
              <Button
                key={step}
                content={'+' + step}
                disabled={data.processing || data.count + step > 1000}
                onClick={() => act('count', { count: data.count + step })} />
            ))}
          </LabeledList.Item>
          <LabeledList.Item label="Material">
            {chosen ? chosen.name : 'None'}
          </LabeledList.Item>
          <LabeledList.Item label="Made">
            {data.made}
          </LabeledList.Item>
        </LabeledList>
        <Box mt={1}>
          <Button
            fluid
            textAlign="center"
            icon={data.processing ? 'cog' : 'coins'}
            iconSpin={data.processing}
            content={data.processing ? 'Pressing...' : 'Make coins'}
            disabled={data.processing || !data.count
              || !chosen || chosen.coins < 1}
            onClick={() => act('make')} />
        </Box>
      </Section>
    </Fragment>
  );
};

const TURRET_COLORS = {
  'ERROR': 'bad',
  'Disabled': 'label',
  'Firing': 'average',
  'All Clear': 'good',
};

export const AuxBase = props => {
  const { act, data } = useBackend(props);
  const destinations = data.destinations || [];
  const turrets = data.turrets || [];
  return (
    <Fragment>
      <Section title="Base">
        <Box mb={1}>
          {data.docked
            ? 'Docking clamps engaged. Standing by.'
            : 'Mining Shuttle Uplink: ' + data.status}
        </Box>
        {destinations.map(dest => (
          <Button
            key={dest.id}
            icon="plane-departure"
            content={'Send to ' + dest.name}
            onClick={() => act('move', { id: dest.id })} />
        ))}
        {!!data.blind_drop && (
          <Button
            icon="exclamation-triangle"
            color="bad"
            content="Blind drop (Dangerous)"
            onClick={() => act('random')} />
        )}
        {!destinations.length && !data.blind_drop && (
          <Box color="label">No landing zones.</Box>
        )}
      </Section>
      {turrets.length > 0 && (
        <Section
          title={'Perimeter defense (' + turrets.length + ')'}
          buttons={(
            <Fragment>
              <Button
                icon="power-off"
                content="Enable all"
                onClick={() => act('turrets', { state: 'on' })} />
              <Button
                icon="times"
                content="Disable all"
                onClick={() => act('turrets', { state: 'off' })} />
            </Fragment>
          )}>
          <Table>
            {turrets.map(turret => (
              <Table.Row key={turret.ref} className="candystripe">
                <Table.Cell bold>{turret.name}</Table.Cell>
                <Table.Cell collapsing>
                  <Box width="70px">
                    <ProgressBar
                      value={turret.integrity / 100}
                      ranges={{
                        good: [0.6, Infinity],
                        average: [0.3, 0.6],
                        bad: [-Infinity, 0.3],
                      }}>
                      {turret.integrity}%
                    </ProgressBar>
                  </Box>
                </Table.Cell>
                <Table.Cell
                  collapsing
                  px={1}
                  color={TURRET_COLORS[turret.status]}>
                  {turret.status}
                </Table.Cell>
                <Table.Cell collapsing color="label" pr={1}>
                  {turret.direction} {turret.distance}m
                </Table.Cell>
                <Table.Cell collapsing>
                  <Button
                    icon="power-off"
                    content="Toggle"
                    onClick={() => act('turret', { ref: turret.ref })} />
                </Table.Cell>
              </Table.Row>
            ))}
          </Table>
        </Section>
      )}
      {!data.online && (
        <NoticeBox>Shuttle offline.</NoticeBox>
      )}
    </Fragment>
  );
};
