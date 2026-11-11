import { Component, Fragment } from 'inferno';
import { useBackend } from '../backend';
import { Box, Button, Collapsible, Dropdown, Input, LabeledList, NoticeBox, Section, Table } from '../components';

// hippie -- the security and medical records consoles
// (hippiestation/.../computer/records_tgui.dm)

const SECURITY_COLORS = {
  '*Arrest*': '#cc2222',
  'Incarcerated': '#cd6500',
  'Paroled': '#cd6500',
  'Discharged': '#2a7ab0',
  'None': '#4f7529',
};

const medicalColor = record => {
  if (record.m_stat === '*Insane*' || record.p_stat === '*Deceased*') {
    return '#cc2222';
  }
  if (record.p_stat === '*Unconscious*' || record.m_stat === '*Unstable*') {
    return '#cd6500';
  }
  if (record.p_stat === 'Physically Unfit' || record.m_stat === '*Watch*') {
    return '#2a7ab0';
  }
  return '#4f7529';
};

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

// One line of text and its button, emptied once sent
class SendBox extends Component {
  constructor() {
    super();
    this.state = {
      text: '',
    };
  }

  render() {
    const { placeholder, button, icon, onSend } = this.props;
    const { text } = this.state;
    return (
      <Box style={{ 'display': 'flex' }} mt={0.5}>
        <Input
          style={{ 'flex-grow': 1 }}
          placeholder={placeholder}
          value={text}
          onInput={(e, value) => this.setState({ text: value })} />
        <Button
          ml={0.5}
          icon={icon || 'plus'}
          content={button}
          disabled={!text.trim()}
          onClick={() => {
            onSend(text);
            this.setState({ text: '' });
          }} />
      </Box>
    );
  }
}

// A field that sends its value when Enter is pressed or it loses focus
const EditField = props => {
  const { act, field, value, width } = props;
  return (
    <Input
      width={width || '260px'}
      value={value === null || value === undefined ? '' : String(value)}
      onChange={(e, newValue) => act('edit', { field, value: newValue })} />
  );
};

const LoginBar = props => {
  const { data, act, tabs } = props;
  const { scan, holding_id, silicon, authenticated, rank } = data;
  return (
    <Section>
      <Box
        style={{
          'display': 'flex',
          'align-items': 'center',
          'white-space': 'nowrap',
        }}>
        <Button
          icon={scan ? 'eject' : 'id-card'}
          content={scan
            || (holding_id && !silicon ? 'Insert held ID' : 'Your ID: empty')}
          tooltip="Your ID"
          disabled={!scan && (!holding_id || silicon)}
          onClick={() => act('eject_id')} />
        <Box style={{ 'flex-grow': 1 }} ml={1}>
          {tabs}
        </Box>
        {authenticated ? (
          <Fragment>
            <Box color="good" mr={1} title={rank}>
              {authenticated}
            </Box>
            <Button
              icon="sign-out-alt"
              content="Log out"
              onClick={() => act('logout')} />
          </Fragment>
        ) : (
          <Button
            icon="sign-in-alt"
            content="Log in"
            disabled={!scan && !silicon}
            onClick={() => act('login')} />
        )}
      </Box>
    </Section>
  );
};

const Temp = props => {
  const { data, act } = props;
  if (!data.temp) {
    return null;
  }
  return (
    <NoticeBox>
      <Box style={{ 'white-space': 'pre-wrap' }}>{data.temp}</Box>
      <Button
        mt={0.5}
        content="Clear"
        onClick={() => act('clear_temp')} />
    </NoticeBox>
  );
};

class RecordList extends Component {
  constructor() {
    super();
    this.state = {
      search: '',
      sort: 'name',
    };
  }

  render() {
    const { data, act, sorts, colorOf, statusOf, purge } = this.props;
    const { search, sort } = this.state;
    const query = search.toLowerCase();
    const selectedRef = data.selected && data.selected.general
      ? data.selected.general.ref
      : null;
    const records = data.records
      .filter(record => !query || [record.name, record.id, record.rank,
        record.fingerprint, record.b_dna, statusOf(record)]
        .some(value => value
          && String(value).toLowerCase().includes(query)))
      .sort((a, b) => String(a[sort] || '')
        .localeCompare(String(b[sort] || '')));
    return (
      <Box
        style={{
          'position': 'absolute',
          'top': 0,
          'bottom': 0,
          'left': 0,
          'width': '300px',
          'padding': '6px',
          'box-sizing': 'border-box',
          'overflow-y': 'auto',
          'background-color': 'rgba(0, 0, 0, 0.33)',
        }}>
        <Input
          fluid
          placeholder="Search names, IDs, jobs..."
          value={search}
          onInput={(e, value) => this.setState({ search: value })} />
        <Box mt={0.5} mb={0.5}>
          <Box inline color="label" mr={0.5}>Sort:</Box>
          {sorts.map(entry => (
            <Button
              key={entry[0]}
              content={entry[1]}
              selected={sort === entry[0]}
              onClick={() => this.setState({ sort: entry[0] })} />
          ))}
        </Box>
        <Button
          fluid
          icon="plus"
          content="New record"
          onClick={() => act('new_record')} />
        <Box mt={0.5}>
          {records.map(record => (
            <Box
              key={record.ref}
              className="candystripe"
              p={0.5}
              style={{
                'cursor': 'pointer',
                'border-left': '4px solid ' + colorOf(record),
                'background-color': record.ref === selectedRef
                  ? 'rgba(255, 255, 255, 0.12)'
                  : null,
              }}
              onClick={() => act('select', { ref: record.ref })}>
              <Box bold>{record.name}</Box>
              <Box color="label" fontSize="11px">
                {record.rank + ' · ' + statusOf(record)}
              </Box>
            </Box>
          ))}
          {records.length === 0 && (
            <Box color="label" italic mt={0.5}>Nobody matches that.</Box>
          )}
        </Box>
        <Box mt={1}>
          <Collapsible title="Records maintenance">
            <ConfirmButton
              icon="trash"
              color="bad"
              content={purge}
              confirm="Delete them all"
              onClick={() => act('purge')} />
          </Collapsible>
        </Box>
      </Box>
    );
  }
}

const Photos = props => {
  const { photos, act, canUpdate } = props;
  return (
    <Box style={{ 'display': 'flex' }} mb={1}>
      {['front', 'side'].map(side => (
        <Box key={side} mr={1} textAlign="center">
          <Box
            width="96px"
            height="96px"
            mb={0.5}
            style={{
              'background-color': 'rgba(0, 0, 0, 0.5)',
              'cursor': photos[side] ? 'pointer' : null,
            }}
            onClick={() => photos[side] && act('photo_show', { side })}>
            {photos[side] ? (
              <img
                src={photos[side]}
                width="96px"
                height="96px"
                style={{
                  '-ms-interpolation-mode': 'nearest-neighbor',
                  'image-rendering': 'pixelated',
                }} />
            ) : (
              <Box color="label" pt={4}>No photo</Box>
            )}
          </Box>
          {canUpdate && (
            <Fragment>
              <Button
                icon="camera"
                tooltip="From the photo in your hand"
                onClick={() => act('photo_update', { side })} />
              <Button
                icon="print"
                disabled={!photos[side]}
                onClick={() => act('photo_print', { side })} />
            </Fragment>
          )}
        </Box>
      ))}
    </Box>
  );
};

const Comments = props => {
  const { record, act } = props;
  return (
    <Section level={2} title="Comments">
      {record.comments.length === 0 && (
        <Box color="label" italic>None.</Box>
      )}
      {record.comments.map(comment => (
        <Box
          key={comment.index}
          mb={0.5}
          p={0.5}
          style={{ 'background-color': 'rgba(0, 0, 0, 0.25)' }}>
          {comment.deleted ? (
            <Box color="label" italic>Deleted</Box>
          ) : (
            <Box style={{ 'display': 'flex' }}>
              <Box style={{ 'flex-grow': 1, 'white-space': 'pre-wrap' }}>
                {comment.text}
              </Box>
              <Button
                icon="times"
                onClick={() => act('delete_comment', {
                  index: comment.index,
                })} />
            </Box>
          )}
        </Box>
      ))}
      <SendBox
        placeholder="Add a comment"
        button="Add"
        onSend={text => act('add_comment', { text })} />
    </Section>
  );
};

class CrimeTable extends Component {
  constructor() {
    super();
    this.state = {
      name: '',
      details: '',
    };
  }

  render() {
    const { crimes, kind, title, act } = this.props;
    const { name, details } = this.state;
    return (
      <Section level={2} title={title}>
        {crimes.length === 0 && (
          <Box color="label" italic>None.</Box>
        )}
        {crimes.length > 0 && (
          <Table>
            <Table.Row header>
              <Table.Cell>Crime</Table.Cell>
              <Table.Cell>Details</Table.Cell>
              <Table.Cell collapsing>By</Table.Cell>
              <Table.Cell collapsing>At</Table.Cell>
              <Table.Cell collapsing />
            </Table.Row>
            {crimes.map(crime => (
              <Table.Row key={crime.id} className="candystripe">
                <Table.Cell>{crime.name}</Table.Cell>
                <Table.Cell>{crime.details}</Table.Cell>
                <Table.Cell collapsing>{crime.author}</Table.Cell>
                <Table.Cell collapsing>{crime.time}</Table.Cell>
                <Table.Cell collapsing>
                  <Button
                    icon="times"
                    onClick={() => act('delete_crime', {
                      kind,
                      id: crime.id,
                    })} />
                </Table.Cell>
              </Table.Row>
            ))}
          </Table>
        )}
        <Box style={{ 'display': 'flex' }} mt={0.5}>
          <Input
            width="160px"
            placeholder="Crime"
            value={name}
            onInput={(e, value) => this.setState({ name: value })} />
          <Input
            ml={0.5}
            style={{ 'flex-grow': 1 }}
            placeholder="Details"
            value={details}
            onInput={(e, value) => this.setState({ details: value })} />
          <Button
            ml={0.5}
            icon="plus"
            content="Add"
            disabled={!name.trim()}
            onClick={() => {
              act('add_crime', { kind, name, details });
              this.setState({ name: '', details: '' });
            }} />
        </Box>
      </Section>
    );
  }
}

class PosterForm extends Component {
  constructor(props) {
    super(props);
    this.state = {
      alias: props.name || '',
      header: props.missing ? 'MISSING' : 'WANTED',
      text: props.defaultText || '',
    };
  }

  render() {
    const { act, missing, onDone } = this.props;
    const { alias, header, text } = this.state;
    return (
      <Box
        mt={1}
        p={1}
        style={{ 'background-color': 'rgba(0, 0, 0, 0.25)' }}>
        <LabeledList>
          <LabeledList.Item label="Alias">
            <Input
              width="260px"
              value={alias}
              onInput={(e, value) => this.setState({ alias: value })} />
          </LabeledList.Item>
          <LabeledList.Item label="Heading">
            <Input
              width="120px"
              maxLength={7}
              value={header}
              onInput={(e, value) => this.setState({ header: value })} />
          </LabeledList.Item>
          <LabeledList.Item label="Description">
            <Input
              fluid
              value={text}
              onInput={(e, value) => this.setState({ text: value })} />
          </LabeledList.Item>
        </LabeledList>
        <Box mt={0.5}>
          <Button
            icon="print"
            content={missing ? 'Print missing poster' : 'Print wanted poster'}
            disabled={!alias.trim() || !text.trim()}
            onClick={() => {
              act('poster', {
                kind: missing ? 'missing' : 'wanted',
                alias,
                header,
                text,
              });
              onDone();
            }} />
          <Button
            icon="times"
            content="Cancel"
            onClick={() => onDone()} />
        </Box>
      </Box>
    );
  }
}

class SecurityRecord extends Component {
  constructor() {
    super();
    this.state = {
      poster: null,
    };
  }

  render() {
    const { data, act } = this.props;
    const { poster } = this.state;
    const { general, record, photos } = data.selected;
    const crimesText = record
      ? record.major.concat(record.minor).map(crime => crime.name).join(', ')
      : '';
    return (
      <Fragment>
        <Section
          title={general ? general.name : 'General record lost'}
          buttons={(
            <Button
              icon="times"
              content="Close"
              onClick={() => act('close')} />
          )}>
          {general && (
            <Box style={{ 'display': 'flex' }}>
              <Photos photos={photos} act={act} canUpdate />
              <Box style={{ 'flex-grow': 1 }}>
                <LabeledList>
                  <LabeledList.Item label="Name">
                    <EditField act={act} field="name" value={general.name} />
                  </LabeledList.Item>
                  <LabeledList.Item label="ID">
                    <EditField act={act} field="id" value={general.id} />
                  </LabeledList.Item>
                  <LabeledList.Item label="Rank">
                    {data.can_rank ? (
                      <Dropdown
                        width="200px"
                        options={data.jobs}
                        selected={general.rank}
                        onSelected={value => act('rank', { rank: value })} />
                    ) : general.rank}
                  </LabeledList.Item>
                  <LabeledList.Item label="Gender">
                    <Button
                      content={general.gender}
                      onClick={() => act('gender')} />
                  </LabeledList.Item>
                  <LabeledList.Item label="Age">
                    <EditField
                      act={act}
                      field="age"
                      width="60px"
                      value={general.age} />
                  </LabeledList.Item>
                  <LabeledList.Item label="Species">
                    <Dropdown
                      width="200px"
                      options={data.species}
                      selected={general.species}
                      onSelected={value => act('edit', {
                        field: 'species',
                        value,
                      })} />
                  </LabeledList.Item>
                  <LabeledList.Item label="Fingerprint">
                    <EditField
                      act={act}
                      field="fingerprint"
                      value={general.fingerprint} />
                  </LabeledList.Item>
                  <LabeledList.Item label="Physical">
                    {general.p_stat}
                  </LabeledList.Item>
                  <LabeledList.Item label="Mental">
                    {general.m_stat}
                  </LabeledList.Item>
                </LabeledList>
              </Box>
            </Box>
          )}
        </Section>
        {record ? (
          <Section title="Security record">
            <LabeledList>
              <LabeledList.Item label="Status">
                {data.statuses.map(status => (
                  <Button
                    key={status.key}
                    content={status.name}
                    selected={record.criminal === status.name}
                    color={record.criminal === status.name
                      && status.key === 'arrest'
                      ? 'bad'
                      : null}
                    onClick={() => act('criminal', { status: status.key })} />
                ))}
              </LabeledList.Item>
              <LabeledList.Item label="Notes">
                <EditField
                  act={act}
                  field="notes"
                  width="420px"
                  value={record.notes} />
              </LabeledList.Item>
            </LabeledList>
            <CrimeTable
              act={act}
              kind="major"
              title="Major crimes"
              crimes={record.major} />
            <CrimeTable
              act={act}
              kind="minor"
              title="Minor crimes"
              crimes={record.minor} />
            <Comments record={record} act={act} />
          </Section>
        ) : (
          <Section title="Security record">
            <NoticeBox>There&apos;s no security record for them.</NoticeBox>
            <Button
              icon="plus"
              content="Make a security record"
              onClick={() => act('new_security_record')} />
          </Section>
        )}
        <Section title="Print and delete">
          <Button
            icon="print"
            content={data.printing ? 'Printing...' : 'Print record'}
            disabled={data.printing}
            onClick={() => act('print')} />
          <Button
            icon="user-secret"
            content="Wanted poster"
            disabled={data.printing || !general || !photos.front}
            tooltip={photos.front ? null : 'Needs a front photo'}
            onClick={() => this.setState({ poster: 'wanted' })} />
          <Button
            icon="question"
            content="Missing poster"
            disabled={data.printing || !general || !photos.front}
            tooltip={photos.front ? null : 'Needs a front photo'}
            onClick={() => this.setState({ poster: 'missing' })} />
          {!!record && (
            <ConfirmButton
              icon="trash"
              content="Delete security record"
              onClick={() => act('delete_security')} />
          )}
          <ConfirmButton
            icon="trash"
            color="bad"
            content="Delete all their records"
            onClick={() => act('delete_all')} />
          {!!poster && !!general && (
            <PosterForm
              key={poster}
              act={act}
              missing={poster === 'missing'}
              name={general.name}
              defaultText={poster === 'missing'
                ? 'A poster declaring ' + general.name + ' to be a missing'
                  + ' individual, missed by Nanotrasen. Report any sightings'
                  + ' to security immediately.'
                : 'A poster declaring ' + general.name + ' to be a dangerous'
                  + ' individual, wanted by Nanotrasen. Report any sightings'
                  + ' to security immediately.'
                  + (crimesText ? ' Wanted for: ' + crimesText + '.' : '')}
              onDone={() => this.setState({ poster: null })} />
          )}
        </Section>
      </Fragment>
    );
  }
}

const OptionButtons = props => {
  const { options, current, action, act } = props;
  return options.map(option => (
    <Button
      key={option.key}
      content={option.name}
      selected={current === option.name}
      onClick={() => act(action, { key: option.key })} />
  ));
};

const MedicalRecord = props => {
  const { data, act } = props;
  const { general, record, photos } = data.selected;
  const textFields = [
    ['b_dna', 'DNA'],
    ['mi_dis', 'Minor disabilities'],
    ['mi_dis_d', 'Details'],
    ['ma_dis', 'Major disabilities'],
    ['ma_dis_d', 'Details'],
    ['alg', 'Allergies'],
    ['alg_d', 'Details'],
    ['cdi', 'Current diseases'],
    ['cdi_d', 'Details'],
    ['notes', 'Notes'],
  ];
  return (
    <Fragment>
      <Section
        title={general.name}
        buttons={(
          <Button
            icon="times"
            content="Close"
            onClick={() => act('close')} />
        )}>
        <Box style={{ 'display': 'flex' }}>
          <Photos photos={photos} act={act} />
          <Box style={{ 'flex-grow': 1 }}>
            <LabeledList>
              <LabeledList.Item label="ID">{general.id}</LabeledList.Item>
              <LabeledList.Item label="Rank">{general.rank}</LabeledList.Item>
              <LabeledList.Item label="Gender">
                <Button
                  content={general.gender}
                  onClick={() => act('gender')} />
              </LabeledList.Item>
              <LabeledList.Item label="Age">
                <EditField
                  act={act}
                  field="age"
                  width="60px"
                  value={general.age} />
              </LabeledList.Item>
              <LabeledList.Item label="Species">
                <EditField act={act} field="species" value={general.species} />
              </LabeledList.Item>
              <LabeledList.Item label="Fingerprint">
                <EditField
                  act={act}
                  field="fingerprint"
                  value={general.fingerprint} />
              </LabeledList.Item>
              <LabeledList.Item label="Physical">
                <OptionButtons
                  act={act}
                  action="p_stat"
                  options={data.p_stats}
                  current={general.p_stat} />
              </LabeledList.Item>
              <LabeledList.Item label="Mental">
                <OptionButtons
                  act={act}
                  action="m_stat"
                  options={data.m_stats}
                  current={general.m_stat} />
              </LabeledList.Item>
            </LabeledList>
          </Box>
        </Box>
      </Section>
      {record ? (
        <Section title="Medical record">
          <LabeledList>
            <LabeledList.Item label="Blood type">
              <OptionButtons
                act={act}
                action="blood_type"
                options={data.blood_types}
                current={record.blood_type} />
            </LabeledList.Item>
            {textFields.map(entry => (
              <LabeledList.Item key={entry[0]} label={entry[1]}>
                <EditField
                  act={act}
                  field={entry[0]}
                  width="420px"
                  value={record[entry[0]]} />
              </LabeledList.Item>
            ))}
          </LabeledList>
          <Comments record={record} act={act} />
        </Section>
      ) : (
        <Section title="Medical record">
          <NoticeBox>There&apos;s no medical record for them.</NoticeBox>
          <Button
            icon="plus"
            content="Make a medical record"
            onClick={() => act('new_record')} />
        </Section>
      )}
      <Section title="Print and delete">
        <Button
          icon="print"
          content={data.printing ? 'Printing...' : 'Print record'}
          disabled={data.printing}
          onClick={() => act('print')} />
        {!!record && (
          <ConfirmButton
            icon="trash"
            color="bad"
            content="Delete medical record"
            onClick={() => act('delete_medical')} />
        )}
      </Section>
    </Fragment>
  );
};

class VirusDatabase extends Component {
  constructor() {
    super();
    this.state = {
      search: '',
    };
  }

  render() {
    const { data } = this.props;
    const query = this.state.search.toLowerCase();
    const viruses = data.viruses
      .filter(virus => !query || virus.name.toLowerCase().includes(query))
      .sort((a, b) => a.name.localeCompare(b.name));
    return (
      <Section
        title="Virus database"
        buttons={(
          <Input
            width="200px"
            placeholder="Search..."
            value={this.state.search}
            onInput={(e, value) => this.setState({ search: value })} />
        )}>
        {viruses.map(virus => (
          <Collapsible key={virus.name} title={virus.name}>
            <Box px={1} mb={1}>
              <LabeledList>
                <LabeledList.Item label="Stages">
                  {virus.stages}
                </LabeledList.Item>
                <LabeledList.Item label="Spread">
                  {virus.spread}
                </LabeledList.Item>
                <LabeledList.Item label="Cure">{virus.cure}</LabeledList.Item>
                <LabeledList.Item label="Affects">
                  {virus.affects}
                </LabeledList.Item>
                <LabeledList.Item label="Severity">
                  {virus.severity}
                </LabeledList.Item>
                <LabeledList.Item label="Notes">{virus.desc}</LabeledList.Item>
              </LabeledList>
            </Box>
          </Collapsible>
        ))}
      </Section>
    );
  }
}

const Medbots = props => {
  const { data } = props;
  return (
    <Section title="Medbots on this level">
      {data.medbots.length === 0 && (
        <Box color="label" italic>None detected.</Box>
      )}
      {data.medbots.length > 0 && (
        <Table>
          <Table.Row header>
            <Table.Cell>Medbot</Table.Cell>
            <Table.Cell>Where</Table.Cell>
            <Table.Cell collapsing>Status</Table.Cell>
            <Table.Cell collapsing>Chemicals</Table.Cell>
          </Table.Row>
          {data.medbots.map((bot, index) => (
            <Table.Row key={index} className="candystripe">
              <Table.Cell>{bot.name}</Table.Cell>
              <Table.Cell>
                {bot.area + ' (' + bot.x + ', ' + bot.y + ')'}
              </Table.Cell>
              <Table.Cell collapsing color={bot.on ? 'good' : 'bad'}>
                {bot.on ? 'Online' : 'Offline'}
              </Table.Cell>
              <Table.Cell collapsing>
                {bot.beaker || 'Its own synthesizer'}
              </Table.Cell>
            </Table.Row>
          ))}
        </Table>
      )}
    </Section>
  );
};

// The list on the left and the record, or another page, on the right
const TwoPanes = props => {
  const { list, children } = props;
  return (
    <Box
      style={{
        'position': 'absolute',
        'top': '58px',
        'bottom': 0,
        'left': 0,
        'right': 0,
      }}>
      {list}
      <Box
        style={{
          'position': 'absolute',
          'top': 0,
          'bottom': 0,
          'left': '300px',
          'right': 0,
          'padding': '6px',
          'overflow-y': 'auto',
        }}>
        {children}
      </Box>
    </Box>
  );
};

const LoggedOut = props => (
  <NoticeBox>
    {props.text}
  </NoticeBox>
);

export const SecurityRecords = props => {
  const { act, data } = useBackend(props);
  if (!data.authenticated) {
    return (
      <Fragment>
        <LoginBar data={data} act={act} />
        <Temp data={data} act={act} />
        <LoggedOut
          text="Insert ID to log in." />
      </Fragment>
    );
  }
  return (
    <Fragment>
      <LoginBar data={data} act={act} />
      <TwoPanes
        list={(
          <RecordList
            data={data}
            act={act}
            purge="Delete all security records"
            sorts={[
              ['name', 'Name'],
              ['rank', 'Rank'],
              ['status', 'Status'],
            ]}
            colorOf={record => SECURITY_COLORS[record.status] || '#555555'}
            statusOf={record => record.status} />
        )}>
        <Temp data={data} act={act} />
        {data.selected ? (
          <SecurityRecord data={data} act={act} />
        ) : (
          <NoticeBox>No record selected.</NoticeBox>
        )}
      </TwoPanes>
    </Fragment>
  );
};

class MedicalRecordsMenu extends Component {
  constructor() {
    super();
    this.state = {
      tab: 'records',
    };
  }

  render() {
    const { data, act } = this.props;
    const { tab } = this.state;
    const tabs = [
      ['records', 'Records'],
      ['viruses', 'Virus database'],
      ['medbots', 'Medbots'],
    ];
    const tabButtons = data.authenticated && tabs.map(entry => (
      <Button
        key={entry[0]}
        content={entry[1]}
        selected={tab === entry[0]}
        onClick={() => this.setState({ tab: entry[0] })} />
    ));
    if (!data.authenticated) {
      return (
        <Fragment>
          <LoginBar data={data} act={act} />
          <Temp data={data} act={act} />
          <LoggedOut
            text="Insert ID to log in." />
        </Fragment>
      );
    }
    let page = <NoticeBox>No record selected.</NoticeBox>;
    if (tab === 'viruses') {
      page = <VirusDatabase data={data} />;
    } else if (tab === 'medbots') {
      page = <Medbots data={data} />;
    } else if (data.selected) {
      page = <MedicalRecord data={data} act={act} />;
    }
    return (
      <Fragment>
        <LoginBar data={data} act={act} tabs={tabButtons} />
        <TwoPanes
          list={(
            <RecordList
              data={data}
              act={act}
              purge="Delete all medical records"
              sorts={[
                ['name', 'Name'],
                ['rank', 'Rank'],
                ['blood_type', 'Blood'],
              ]}
              colorOf={medicalColor}
              statusOf={record => [record.p_stat, record.m_stat]
                .filter(Boolean).join(', ') || 'No status'} />
          )}>
          <Temp data={data} act={act} />
          {page}
        </TwoPanes>
      </Fragment>
    );
  }
}

export const MedicalRecords = props => {
  const { act, data } = useBackend(props);
  return <MedicalRecordsMenu data={data} act={act} />;
};
