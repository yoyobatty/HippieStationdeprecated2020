import { pureComponentHooks } from 'common/react';
import { Component, Fragment } from 'inferno';
import { Box, Button, Chart, ColorBox, Icon, Input, ProgressBar, Section } from '../components';
import { formatPower } from './common/PowerBits';

// hippie -- the power monitor redone: supply, draw and what's spare up top,
// a bigger chart of the last minutes, and the areas with a search, filters
// for low cells and channels that are off, sorting either way, and a charge
// bar each. The raw numbers come from hippiestation/code/modules/power/
// power_tgui.dm.

const PEAK_DRAW = 500000;
const LOW_CELL = 30;

const SORTS = {
  name: { label: 'Name', key: area => area.name.toLowerCase() },
  charge: { label: 'Charge', key: area => area.charge },
  draw: { label: 'Draw', key: area => area.loadRaw || 0 },
};

const channelsOff = area => [area.eqp, area.lgt, area.env]
  .some(status => !(status & 2));

const Stat = props => {
  const { label, value, color } = props;
  return (
    <div className="Power__stat">
      <Box color="label">{label}</Box>
      <Box fontSize="20px" bold color={color}>
        {formatPower(value)}
      </Box>
    </div>
  );
};

const AreaCharge = props => {
  const { area } = props;
  if (!area.hasCell && area.hasCell !== undefined) {
    return <Box color="bad">No cell</Box>;
  }
  const icon = area.charging === 2 && 'battery-full'
    || area.charging === 1 && 'bolt'
    || (area.charge > 50 ? 'battery-half' : 'battery-quarter');
  const color = area.charging === 2 && 'good'
    || area.charging === 1 && 'average'
    || (area.charge > LOW_CELL ? 'average' : 'bad');
  return (
    <Box nowrap>
      <Icon name={icon} color={color} width="16px" textAlign="center" />
      <Box inline width="70px" ml={0.5} style={{ 'vertical-align': 'middle' }}>
        <ProgressBar
          value={area.charge / 100}
          ranges={{
            good: [0.5, Infinity],
            average: [LOW_CELL / 100, 0.5],
            bad: [-Infinity, LOW_CELL / 100],
          }}>
          {Math.round(area.charge)}%
        </ProgressBar>
      </Box>
    </Box>
  );
};

AreaCharge.defaultHooks = pureComponentHooks;

const ChannelBox = props => {
  const { status, name } = props;
  const on = Boolean(status & 2);
  const auto = Boolean(status & 1);
  return (
    <ColorBox
      color={on ? 'good' : 'bad'}
      content={auto ? undefined : 'M'}
      title={name + ': ' + (on ? 'on' : 'off')
        + (auto ? ' (auto)' : ' (set by hand)')} />
  );
};

ChannelBox.defaultHooks = pureComponentHooks;

export class PowerMonitor extends Component {
  constructor() {
    super();
    this.state = {
      sortBy: 'draw',
      descending: true,
      search: '',
      lowOnly: false,
      offOnly: false,
    };
  }

  setSort(field) {
    const { sortBy, descending } = this.state;
    if (sortBy === field) {
      this.setState({ descending: !descending });
    }
    else {
      this.setState({ sortBy: field, descending: field !== 'name' });
    }
  }

  render() {
    const { state } = this.props;
    const { data } = state;
    const { history } = data;
    const { sortBy, descending, search, lowOnly, offOnly } = this.state;
    const lastOf = list => list[list.length - 1] || 0;
    const supply = data.supplyRaw !== undefined
      ? data.supplyRaw
      : lastOf(history.supply);
    const demand = data.demandRaw !== undefined
      ? data.demandRaw
      : lastOf(history.demand);
    const spare = supply - demand;
    const supplyData = history.supply.map((value, i) => [i, value]);
    const demandData = history.demand.map((value, i) => [i, value]);
    const maxValue = Math.max(PEAK_DRAW, ...history.supply,
      ...history.demand);
    const allAreas = data.areas || [];
    const lowCount = allAreas
      .filter(area => area.hasCell !== false && area.charge < LOW_CELL)
      .length;
    const offCount = allAreas.filter(channelsOff).length;
    const term = search.toLowerCase();
    const sortKey = SORTS[sortBy].key;
    const areas = allAreas
      .filter(area => (!term || area.name.toLowerCase().includes(term))
        && (!lowOnly || (area.hasCell !== false && area.charge < LOW_CELL))
        && (!offOnly || channelsOff(area)))
      .sort((a, b) => {
        const ka = sortKey(a);
        const kb = sortKey(b);
        const order = ka < kb ? -1 : ka > kb ? 1 : 0;
        return descending ? -order : order;
      });
    if (!data.attached) {
      return (
        <Section>
          <Box color="bad">
            <Icon name="times-circle" mr={1} />
            Not connected to a power network. Build it on a cable.
          </Box>
        </Section>
      );
    }
    return (
      <Fragment>
        <Section>
          <div className="Power__stats">
            <Stat label="Supply" value={supply} color="teal" />
            <Stat label="Draw" value={demand} color="pink" />
            <Stat
              label={spare >= 0 ? 'Spare' : 'Short by'}
              value={Math.abs(spare)}
              color={spare >= 0 ? 'good' : 'bad'} />
          </div>
          <div className="Power__chart">
            <Chart.Line
              fillPositionedParent
              data={supplyData}
              rangeX={[0, Math.max(1, supplyData.length - 1)]}
              rangeY={[0, maxValue]}
              strokeColor="rgba(0, 181, 173, 1)"
              fillColor="rgba(0, 181, 173, 0.25)" />
            <Chart.Line
              fillPositionedParent
              data={demandData}
              rangeX={[0, Math.max(1, demandData.length - 1)]}
              rangeY={[0, maxValue]}
              strokeColor="rgba(224, 57, 151, 1)"
              fillColor="rgba(224, 57, 151, 0.25)" />
          </div>
          <Box color="label" mt={0.5}>
            <Box inline color="teal" mr={1}>&#9632; supply</Box>
            <Box inline color="pink" mr={2}>&#9632; draw</Box>
            the last {Math.round(data.stored * data.interval / 60)} minutes
          </Box>
        </Section>
        <Section
          title={'Areas (' + areas.length + ')'}
          buttons={(
            <Input
              width="140px"
              placeholder="Search..."
              value={search}
              onInput={(e, value) => this.setState({ search: value })} />
          )}>
          <Box mb={1}>
            <Button.Checkbox
              checked={lowOnly}
              color={lowCount ? 'bad' : 'default'}
              content={'Low cells (' + lowCount + ')'}
              onClick={() => this.setState({ lowOnly: !lowOnly })} />
            <Button.Checkbox
              checked={offOnly}
              color={offCount ? 'average' : 'default'}
              content={'Channels off (' + offCount + ')'}
              onClick={() => this.setState({ offOnly: !offOnly })} />
            <Box inline color="label" ml={1} mr={1}>Sort:</Box>
            {Object.keys(SORTS).map(field => (
              <Button
                key={field}
                selected={sortBy === field}
                icon={sortBy === field
                  ? (descending ? 'sort-amount-down' : 'sort-amount-up')
                  : undefined}
                content={SORTS[field].label}
                onClick={() => this.setSort(field)} />
            ))}
          </Box>
          <table className="Table">
            <tr className="Table__row Table__row--header">
              <td className="Table__cell">Area</td>
              <td className="Table__cell">Cell</td>
              <td className="Table__cell text-right">Draw</td>
              <td className="Table__cell text-center" title="Equipment">
                Eqp
              </td>
              <td className="Table__cell text-center" title="Lighting">
                Lgt
              </td>
              <td className="Table__cell text-center" title="Environment">
                Env
              </td>
            </tr>
            {areas.map((area, i) => (
              <tr
                key={area.ref || area.name + i}
                className="Table__row candystripe">
                <td className="Table__cell">{area.name}</td>
                <td className="Table__cell text-nowrap Table__cell--collapsing">
                  <AreaCharge area={area} />
                </td>
                <td className="Table__cell text-right text-nowrap">
                  {area.loadRaw !== undefined
                    ? formatPower(area.loadRaw)
                    : area.load}
                </td>
                <td className="Table__cell text-center Table__cell--collapsing">
                  <ChannelBox status={area.eqp} name="Equipment" />
                </td>
                <td className="Table__cell text-center Table__cell--collapsing">
                  <ChannelBox status={area.lgt} name="Lighting" />
                </td>
                <td className="Table__cell text-center Table__cell--collapsing">
                  <ChannelBox status={area.env} name="Environment" />
                </td>
              </tr>
            ))}
          </table>
          {areas.length === 0 && (
            <Box color="label" mt={1}>No areas match.</Box>
          )}
        </Section>
      </Fragment>
    );
  }
}
