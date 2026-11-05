import { Component, Fragment } from 'inferno';
import { useBackend } from '../backend';
import { Box, Button, Input, NoticeBox, ProgressBar, Section, Table } from '../components';

// hippie -- the power flow control console
// (hippiestation/.../computer/apc_control_tgui.dm)

// An APC channel: 0 off, 1 off by itself, 2 on, 3 on by itself
const Channel = props => {
  const { name, short, status, failed } = props;
  const on = status >= 2 && !failed;
  const auto = status === 1 || status === 3;
  return (
    <Box
      inline
      mr={1}
      color={on ? 'good' : 'bad'}
      title={name + ': ' + (on ? 'on' : 'off') + (auto ? ' (auto)' : '')}>
      {short}
    </Box>
  );
};

const chargeColor = charge => {
  if (charge >= 50) {
    return 'good';
  }
  if (charge >= 15) {
    return 'average';
  }
  return 'bad';
};

const CHARGING = ['', ' charging', ' full'];

class ApcList extends Component {
  constructor() {
    super();
    this.state = {
      search: '',
      above: '',
      below: '',
      unresponsive: false,
    };
  }

  render() {
    const { data, act } = this.props;
    const { search, unresponsive } = this.state;
    const above = parseInt(this.state.above, 10);
    const below = parseInt(this.state.below, 10);
    const query = search.toLowerCase();
    const apcs = (data.apcs || []).filter(apc => {
      if (query && !apc.name.toLowerCase().includes(query)
        && !apc.area.toLowerCase().includes(query)) {
        return false;
      }
      if (!isNaN(above) && (apc.charge === null || apc.charge < above)) {
        return false;
      }
      if (!isNaN(below) && apc.charge !== null && apc.charge > below) {
        return false;
      }
      if (unresponsive && apc.responds) {
        return false;
      }
      return true;
    });
    // In a grid failure, the order the reset brings them back in
    if (data.down || data.resetting) {
      apcs.sort((a, b) => a.dist - b.dist);
    }
    return (
      <Section
        title={apcs.length + ' APCs'}
        buttons={(
          <Fragment>
            <Input
              width="140px"
              placeholder="Name or area..."
              value={search}
              onInput={(e, value) => this.setState({ search: value })} />
            <Box inline ml={1} color="label">Charge</Box>
            <Input
              width="36px"
              ml={0.5}
              placeholder={'>%'}
              value={this.state.above}
              onInput={(e, value) => this.setState({ above: value })} />
            <Input
              width="36px"
              placeholder={'<%'}
              value={this.state.below}
              onInput={(e, value) => this.setState({ below: value })} />
            <Button.Checkbox
              ml={1}
              checked={unresponsive}
              content="Unresponsive only"
              onClick={() => this.setState({
                unresponsive: !unresponsive,
              })} />
          </Fragment>
        )}>
        {apcs.length === 0 && (
          <NoticeBox>No APCs match that.</NoticeBox>
        )}
        <Table>
          {apcs.map(apc => (
            <Table.Row key={apc.ref} className="candystripe">
              <Table.Cell py={0.5} px={0.5}>
                <Box>{apc.area}</Box>
                <Box
                  color={apc.failed ? 'bad' : 'label'}
                  fontSize="11px">
                  {rowNote(apc)}
                </Box>
              </Table.Cell>
              <Table.Cell width="130px" px={0.5}>
                {apc.charge === null && (
                  <Box color="bad">No cell</Box>
                )}
                {apc.charge !== null && (
                  <ProgressBar
                    value={apc.charge / 100}
                    color={chargeColor(apc.charge)}
                    content={apc.charge + '%' + CHARGING[apc.charging]} />
                )}
              </Table.Cell>
              <Table.Cell width="110px" px={0.5} nowrap>
                <Channel
                  name="Equipment"
                  short="Eqp"
                  status={apc.equipment}
                  failed={apc.failed} />
                <Channel
                  name="Lighting"
                  short="Lgt"
                  status={apc.lighting}
                  failed={apc.failed} />
                <Channel
                  name="Environment"
                  short="Env"
                  status={apc.environ}
                  failed={apc.failed} />
              </Table.Cell>
              <Table.Cell collapsing px={0.5}>
                <Button
                  icon="plug"
                  content="Access"
                  selected={data.active === apc.ref}
                  disabled={!apc.responds}
                  onClick={() => act('access', { ref: apc.ref })} />
              </Table.Cell>
            </Table.Row>
          ))}
        </Table>
      </Section>
    );
  }
}

const rowNote = apc => {
  if (!apc.responds) {
    return 'does not respond to interface query';
  }
  if (apc.failed) {
    return 'power failure';
  }
  return apc.load + ' used';
};

// A grid failure: how many APCs it timed out, and the reset that brings them
// back one after another
const GridFailure = props => {
  const { data, act } = props;
  if (data.resetting) {
    return (
      <Section title="Resetting the grid">
        <ProgressBar
          value={data.reset_total ? data.reset_done / data.reset_total : 0}
          color="good"
          content={data.reset_done + ' of ' + data.reset_total
            + (data.reset_last ? ' — ' + data.reset_last : '')} />
      </Section>
    );
  }
  if (!data.down) {
    return null;
  }
  return (
    <Section>
      <Box style={{ 'display': 'flex', 'align-items': 'center' }}>
        <Box bold color="bad" style={{ 'flex-grow': 1 }}>
          {'Grid failure: ' + data.down + ' APC'
            + (data.down === 1 ? '' : 's') + ' down'}
        </Box>
        <Button
          icon="power-off"
          color="bad"
          content="Reset all APCs"
          disabled={!data.can_reset}
          tooltip={data.can_reset ? null : 'Needs the Chief Engineer\'s ID'}
          tooltipPosition="left"
          onClick={() => act('reset_all')} />
      </Box>
    </Section>
  );
};

const Logs = props => {
  const { data, act } = props;
  const logs = data.logs || [];
  return (
    <Section
      title="Activity log"
      buttons={!!data.emagged && (
        <Button
          icon="trash"
          color="bad"
          content="@#%! Clear logs"
          onClick={() => act('clear_logs')} />
      )}>
      {logs.length === 0 && (
        <Box color="label">
          No activity has been recorded at this time.
        </Box>
      )}
      {logs.map((entry, i) => (
        <Box key={i} mb={0.5}>{entry}</Box>
      ))}
    </Section>
  );
};

export const ApcControl = props => {
  const { act, data } = useBackend(props);
  if (!data.authenticated) {
    return (
      <Section>
        <NoticeBox>Swipe a valid ID to log in.</NoticeBox>
        <Button
          icon="id-card"
          content="Log in"
          onClick={() => act('log_in')} />
      </Section>
    );
  }
  return (
    <Fragment>
      <Section
        title={'Logged in as ' + data.auth_id}
        buttons={(
          <Fragment>
            <Button
              icon="bolt"
              content="APCs"
              selected={!data.checking_logs}
              onClick={() => act('check_apcs')} />
            <Button
              icon="list"
              content="Logs"
              selected={!!data.checking_logs}
              onClick={() => act('check_logs')} />
            <Button
              icon="sign-out-alt"
              content="Log out"
              onClick={() => act('log_out')} />
          </Fragment>
        )} />
      {!!data.backup_power && (
        <NoticeBox>Running on backup power.</NoticeBox>
      )}
      {!!data.emagged && (
        <NoticeBox>
          WARNING: Logging functionality partially disabled from outside
          source.
          <Button
            ml={1}
            content="Restore logging"
            onClick={() => act('restore_logging')} />
        </NoticeBox>
      )}
      <GridFailure data={data} act={act} />
      {data.checking_logs
        ? <Logs data={data} act={act} />
        : <ApcList data={data} act={act} />}
    </Fragment>
  );
};
