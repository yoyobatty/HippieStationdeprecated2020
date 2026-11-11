import { Component, Fragment } from 'inferno';
import { useBackend } from '../backend';
import { Box, Button, Collapsible, LabeledList, NoticeBox, ProgressBar, Section } from '../components';

// hippie -- the cloning console (hippiestation/.../computer/cloning_tgui.dm)

// A button that asks once more before it acts
class ConfirmButton extends Component {
  constructor() {
    super();
    this.state = {
      asking: false,
    };
  }

  render() {
    const { content, confirm, icon, color, disabled, onClick } = this.props;
    if (this.state.asking) {
      return (
        <Fragment>
          <Button
            icon="check"
            color="bad"
            content={confirm || 'Confirm'}
            onClick={() => {
              this.setState({ asking: false });
              onClick();
            }} />
          <Button
            icon="times"
            content="Cancel"
            onClick={() => this.setState({ asking: false })} />
        </Fragment>
      );
    }
    return (
      <Button
        icon={icon}
        color={color}
        content={content}
        disabled={disabled}
        onClick={() => this.setState({ asking: true })} />
    );
  }
}

const ScannerSection = props => {
  const { data, act } = props;
  const { scanner, loading } = data;
  if (!scanner) {
    return (
      <Section title="Scanner">
        <NoticeBox>No scanner connected.</NoticeBox>
      </Section>
    );
  }
  return (
    <Section
      title="Scanner"
      buttons={(
        <Button
          icon={scanner.locked ? 'lock' : 'lock-open'}
          content={scanner.locked ? 'Locked' : 'Unlocked'}
          selected={scanner.locked}
          disabled={!scanner.operational || (!scanner.occupant
            && !scanner.locked)}
          onClick={() => act('lock')} />
      )}>
      <LabeledList>
        <LabeledList.Item label="Occupant">
          {scanner.occupant || 'Empty'}
        </LabeledList.Item>
        <LabeledList.Item label="Scan">
          {loading ? 'Scanning...' : scanner.status}
        </LabeledList.Item>
      </LabeledList>
      <Box mt={1}>
        <Button
          icon="dna"
          content="Scan"
          disabled={!scanner.occupant || loading || !scanner.operational}
          onClick={() => act('scan')} />
        <Button
          icon="male"
          content="Body-only scan"
          disabled={!scanner.occupant || loading || !scanner.operational}
          onClick={() => act('scan', { body_only: 1 })} />
      </Box>
    </Section>
  );
};

const PodsSection = props => {
  const { data } = props;
  return (
    <Section title="Pods">
      {data.pods.length === 0 && (
        <NoticeBox>No pod connected.</NoticeBox>
      )}
      {data.pods.map((pod, index) => (
        <Box key={index} mb={0.5}
          style={{ 'display': 'flex', 'align-items': 'center' }}>
          <Box width="180px" color="label">
            {pod.name + (pod.efficient ? ' (upgraded)' : '')}
          </Box>
          <Box style={{ 'flex-grow': 1 }}>
            {pod.occupant && (
              <ProgressBar
                value={pod.progress / 100}
                color="good"
                content={pod.occupant + ': ' + pod.progress + '%'} />
            )}
            {!pod.occupant && !!pod.mess && (
              <Box color="bad">Pod jammed: failed clone.</Box>
            )}
            {!pod.occupant && !pod.mess && (
              <Box color={pod.working ? 'good' : 'bad'}>
                {pod.working ? 'Ready' : 'Not working'}
              </Box>
            )}
          </Box>
        </Box>
      ))}
    </Section>
  );
};

const RecordsSection = props => {
  const { data, act } = props;
  const { records, disk } = data;
  return (
    <Section title={'Records (' + records.length + ')'}>
      {records.length === 0 && (
        <Box color="label" italic>No scan loaded.</Box>
      )}
      {records.map(record => (
        <Collapsible
          key={record.id}
          title={record.name + (record.body_only ? ' (body only)' : '')}>
          <Box px={1} mb={1}>
            <Box mb={1}>
              {!record.body_only && (
                <Button
                  icon="user-plus"
                  content="Clone"
                  disabled={!data.revival}
                  tooltip={data.revival ? null : 'Revival cloning is off'}
                  onClick={() => act('clone', { id: record.id })} />
              )}
              <Button
                icon="user"
                content="Empty clone"
                onClick={() => act('clone', { id: record.id, empty: 1 })} />
              <ConfirmButton
                icon="trash"
                content="Delete"
                confirm="Delete the record"
                onClick={() => act('delete', { id: record.id })} />
              {!!disk && (
                <Fragment>
                  <Button
                    icon="save"
                    content="Save to disk"
                    disabled={disk.read_only}
                    onClick={() => act('disk_save', { id: record.id })} />
                  <Button
                    icon="upload"
                    content="Load from disk"
                    disabled={!data.can_load}
                    tooltip={data.can_load ? null : 'Access denied'}
                    onClick={() => act('disk_load', { id: record.id })} />
                </Fragment>
              )}
            </Box>
            <LabeledList>
              <LabeledList.Item label="Scan ID">{record.id}</LabeledList.Item>
              <LabeledList.Item label="Health">
                <Box style={{ 'white-space': 'pre-wrap' }}>
                  {record.health || 'Unable to locate the health implant.'}
                </Box>
              </LabeledList.Item>
            </LabeledList>
            <Box mt={1}>
              <Collapsible title="Genetic data">
                <Box
                  px={1}
                  fontSize="11px"
                  style={{ 'word-break': 'break-all' }}>
                  <Box mb={0.5}>{'Identifier: ' + record.ui}</Box>
                  {record.mutations.length === 0 && 'No mutations.'}
                  {record.mutations.map(mutation => (
                    <Box key={mutation.name}>
                      {mutation.name + ': ' + mutation.value}
                    </Box>
                  ))}
                </Box>
              </Collapsible>
            </Box>
          </Box>
        </Collapsible>
      ))}
    </Section>
  );
};

const DiskSection = props => {
  const { data, act } = props;
  const { disk } = data;
  if (!disk) {
    return null;
  }
  const parts = [
    ['ui', 'Identifier', disk.has_ui, data.include_ui],
    ['ue', 'Enzymes (name and blood)', disk.has_ue, data.include_ue],
    ['se', 'Mutations', disk.has_se, data.include_se],
  ];
  return (
    <Section
      title="Data disk"
      buttons={(
        <Button
          icon="eject"
          content="Eject"
          onClick={() => act('disk_eject')} />
      )}>
      <LabeledList>
        <LabeledList.Item label="Disk">
          {disk.name + (disk.read_only ? ' (read only)' : '')}
        </LabeledList.Item>
        <LabeledList.Item label="On it">
          {disk.contents.length ? disk.contents.join(' + ') : 'Nothing'}
        </LabeledList.Item>
        <LabeledList.Item label="Loading">
          {parts.filter(part => part[2]).map(part => (
            <Button
              key={part[0]}
              icon={part[3] ? 'check-square' : 'square'}
              content={part[1]}
              selected={part[3]}
              onClick={() => act('include', { part: part[0] })} />
          ))}
        </LabeledList.Item>
      </LabeledList>
    </Section>
  );
};

export const CloningConsole = props => {
  const { act, data } = useBackend(props);
  return (
    <Fragment>
      <Section
        title="Status"
        buttons={(
          <Fragment>
            <Button
              icon="sync"
              content="Refresh"
              onClick={() => act('refresh')} />
            <Button
              icon="robot"
              content={data.autoprocess ? 'Autoprocess on' : 'Autoprocess'}
              selected={data.autoprocess}
              disabled={!data.can_autoprocess && !data.autoprocess}
              tooltip={data.can_autoprocess
                ? null
                : 'Needs T3 scanner and pod'}
              tooltipPosition="left"
              onClick={() => act('autoprocess')} />
          </Fragment>
        )}>
        <Box style={{ 'white-space': 'pre-wrap' }}>{data.temp}</Box>
      </Section>
      <ScannerSection data={data} act={act} />
      <PodsSection data={data} />
      <RecordsSection data={data} act={act} />
      <DiskSection data={data} act={act} />
    </Fragment>
  );
};
