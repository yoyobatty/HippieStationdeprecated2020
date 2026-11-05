import { Component, Fragment } from 'inferno';
import { useBackend } from '../backend';
import { Box, Button, Flex, Input, LabeledList, NoticeBox, Section, Table, Tabs } from '../components';

// hippie -- the ID Card Modification laptop program (was
// tgui/src/interfaces/ntos_card.ract), laid out like the ID console
// (IdConsole.js): every department's accesses at once with grant and revoke
// all, the jobs, the name typed in the window
// (hippiestation/code/modules/modular_computers/ntos_tgui.dm)

const JOB_GROUPS = [
  ['Engineering', 'engineering_jobs', 'orange'],
  ['Medical', 'medical_jobs', 'teal'],
  ['Science', 'science_jobs', 'purple'],
  ['Security', 'security_jobs', 'red'],
  ['Cargo', 'cargo_jobs', 'brown'],
  ['Civilian', 'civilian_jobs', 'grey'],
];

class AccessTab extends Component {
  constructor() {
    super();
    this.state = { search: '', custom: '' };
  }

  render() {
    const { act, data } = this.props;
    const { search, custom } = this.state;
    const {
      authenticated,
      has_id,
      id_owner,
      id_rank,
      minor,
      centcom_access,
      regions = [],
      all_centcom_access = [],
    } = data;
    if (!has_id) {
      return <NoticeBox>Put the ID to change in the card slot.</NoticeBox>;
    }
    if (!authenticated) {
      return (
        <NoticeBox>
          Put an ID that can change IDs, or a head of staff&apos;s, in the
          second slot.
        </NoticeBox>
      );
    }
    const query = search.toLowerCase();
    const matches = access => !query
      || access.desc.toLowerCase().includes(query);
    const groups = centcom_access
      ? [{ name: 'Central Command', regid: 0, accesses: all_centcom_access }]
      : regions;
    const shown = groups
      .map(group => ({
        ...group,
        shown: (group.accesses || []).filter(matches),
      }))
      .filter(group => group.shown.length > 0);
    return (
      <Fragment>
        <Section title="ID card">
          <LabeledList>
            <LabeledList.Item label="Name">
              {minor && id_owner || (
                <Input
                  width="250px"
                  value={id_owner}
                  onChange={(e, value) => act('PRG_edit', {
                    name: 1,
                    value,
                  })} />
              )}
            </LabeledList.Item>
            <LabeledList.Item label="Assignment">
              {id_rank}
              {!!minor && (
                <Button
                  ml={1}
                  icon="user-minus"
                  disabled={id_rank === 'Unassigned'}
                  content="Demote"
                  onClick={() => act('PRG_terminate')} />
              )}
            </LabeledList.Item>
          </LabeledList>
        </Section>
        {!minor && (
          <Section title="Job">
            <Box mb={1}>
              {!!centcom_access && (data.centcom_jobs || []).map(job => (
                <Button
                  key={job.job}
                  selected={id_rank === job.job}
                  content={job.display_name}
                  onClick={() => act('PRG_assign', {
                    assign_target: job.job,
                  })} />
              ))}
              <Button
                selected={id_rank === 'Captain'}
                content="Captain"
                onClick={() => act('PRG_assign', {
                  assign_target: 'Captain',
                })} />
              <Input
                ml={1}
                width="180px"
                placeholder="Custom assignment"
                value={custom}
                onInput={(e, value) => this.setState({ custom: value })} />
              <Button
                icon="pen"
                disabled={!custom}
                content="Set"
                onClick={() => act('PRG_assign', {
                  assign_target: 'Custom',
                  value: custom,
                })} />
            </Box>
            {JOB_GROUPS.map(group => (
              <Box key={group[1]} mb={0.5}>
                <Box inline bold width="100px" color={group[2]}>
                  {group[0]}
                </Box>
                {(data[group[1]] || []).map(job => (
                  <Button
                    key={job.job}
                    selected={id_rank === job.job}
                    content={job.display_name}
                    onClick={() => act('PRG_assign', {
                      assign_target: job.job,
                    })} />
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
          {shown.length === 0 && (
            <NoticeBox>Nothing matches that.</NoticeBox>
          )}
          <Flex wrap="wrap">
            {shown.map(group => (
              <Box
                key={group.regid}
                width="175px"
                mr={1}
                mb={1}
                style={{
                  'padding': '4px',
                  'background-color': 'rgba(0, 0, 0, 0.25)',
                }}>
                <Box bold mb={0.5}>{group.name}</Box>
                {!centcom_access && (
                  <Box mb={0.5}>
                    <Button
                      icon="check-double"
                      content="All"
                      onClick={() => act('PRG_region', {
                        region: group.regid,
                        allowed: 1,
                      })} />
                    <Button
                      icon="times"
                      content="None"
                      onClick={() => act('PRG_region', {
                        region: group.regid,
                        allowed: 0,
                      })} />
                  </Box>
                )}
                {group.shown.map(access => (
                  <Button
                    key={access.ref}
                    fluid
                    icon={access.allowed ? 'check' : null}
                    selected={!!access.allowed}
                    content={access.desc}
                    onClick={() => act('PRG_access', {
                      access_target: access.ref,
                      allowed: access.allowed,
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

const JobsTab = props => {
  const { act, data } = props;
  const slots = data.slots || [];
  return (
    <Section title="Job slots">
      <Table>
        <Table.Row header>
          <Table.Cell>Job</Table.Cell>
          <Table.Cell collapsing textAlign="center">Filled</Table.Cell>
          <Table.Cell collapsing />
          <Table.Cell collapsing />
        </Table.Row>
        {slots.map(slot => (
          <Table.Row key={slot.title}>
            <Table.Cell>{slot.title}</Table.Cell>
            <Table.Cell collapsing textAlign="center">
              {slot.current} / {slot.total}
            </Table.Cell>
            <Table.Cell collapsing>
              <Button
                icon="plus"
                disabled={slot.status_open !== 1}
                content={slot.desc_open}
                onClick={() => act('PRG_open_job', { target: slot.title })} />
            </Table.Cell>
            <Table.Cell collapsing>
              <Button
                icon="minus"
                disabled={slot.status_close !== 1}
                content={slot.desc_close}
                onClick={() => act('PRG_close_job', { target: slot.title })} />
            </Table.Cell>
          </Table.Row>
        ))}
      </Table>
    </Section>
  );
};

const ManifestTab = props => {
  const { data } = props;
  const crew = data.manifest || [];
  return (
    <Section title="Crew manifest">
      <Box color="label" mb={1}>
        Change entries at a security records console.
      </Box>
      <Table>
        {crew.map((member, i) => (
          <Table.Row key={i}>
            <Table.Cell>{member.name}</Table.Cell>
            <Table.Cell color="label">{member.rank}</Table.Cell>
          </Table.Row>
        ))}
      </Table>
    </Section>
  );
};

export const NtosCard = props => {
  const { act, data } = useBackend(props);
  const {
    mmode,
    have_id_slot,
    have_printer,
    has_id,
    id_name,
    auth_name,
  } = data;
  const tab = mmode === 1 ? 'mod' : mmode === 2 ? 'manage' : 'manifest';
  return (
    <Fragment>
      {!!have_id_slot && (
        <Section>
          <LabeledList>
            <LabeledList.Item label="To change">
              <Button
                icon="eject"
                disabled={!has_id}
                content={has_id ? id_name : 'Empty'}
                onClick={() => act('PRG_eject', { target: 'id' })} />
            </LabeledList.Item>
            <LabeledList.Item label="Authorised by">
              <Button
                icon="eject"
                disabled={auth_name === '-----'}
                content={auth_name === '-----' ? 'Empty' : auth_name}
                onClick={() => act('PRG_eject', { target: 'auth' })} />
            </LabeledList.Item>
          </LabeledList>
        </Section>
      )}
      <Tabs activeTab={tab}>
        {!!have_id_slot && (
          <Tabs.Tab
            key="mod"
            label="Access"
            icon="id-card"
            onClick={() => act('PRG_switchm', { target: 'mod' })} />
        )}
        <Tabs.Tab
          key="manage"
          label="Job slots"
          icon="briefcase"
          onClick={() => act('PRG_switchm', { target: 'manage' })} />
        <Tabs.Tab
          key="manifest"
          label="Manifest"
          icon="list"
          onClick={() => act('PRG_switchm', { target: 'manifest' })} />
      </Tabs>
      {!!have_printer && (tab === 'manifest' || tab === 'mod' && has_id) && (
        <Box mb={1}>
          <Button
            icon="print"
            content={tab === 'manifest'
              ? 'Print the manifest'
              : 'Print this ID\'s access'}
            onClick={() => act('PRG_print')} />
        </Box>
      )}
      {tab === 'mod' && <AccessTab act={act} data={data} />}
      {tab === 'manage' && <JobsTab act={act} data={data} />}
      {tab === 'manifest' && <ManifestTab data={data} />}
    </Fragment>
  );
};
