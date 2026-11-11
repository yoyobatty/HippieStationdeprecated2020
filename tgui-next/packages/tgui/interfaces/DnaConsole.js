import { Component, Fragment } from 'inferno';
import { useBackend } from '../backend';
import { Box, Button, Flex, Input, LabeledList, NoticeBox, ProgressBar, Section } from '../components';

// hippie -- the DNA scanner access console
// (hippiestation/.../computer/dna_console_tgui.dm). Genes go by alias.

const task = (act, name, params = {}) => act('task', Object.assign({
  task: name,
}, params));

const ScannerStatus = props => {
  const { data, act } = props;
  const { scanner } = data;
  const subject = scanner.subject;
  let scannerText = <Box color="bad">Error: No scanner detected</Box>;
  if (scanner.present && scanner.open) {
    scannerText = 'Open';
  } else if (scanner.present) {
    scannerText = (
      <Fragment>
        {'Closed '}
        <Box inline color={scanner.locked ? 'bad' : 'good'}>
          {scanner.locked ? '(Locked)' : '(Unlocked)'}
        </Box>
      </Fragment>
    );
  }
  let subjectText = <Box color="bad">No subject detected</Box>;
  if (scanner.invalid) {
    subjectText = <Box color="bad">Invalid DNA structure</Box>;
  } else if (subject) {
    subjectText = (
      <Fragment>
        {subject.name + ' => '}
        <Box inline color={subject.status_color}>{subject.status}</Box>
      </Fragment>
    );
  } else if (!scanner.present) {
    subjectText = <Box color="bad">----</Box>;
  }
  return (
    <Section
      title="DNA scanner"
      buttons={(
        <Fragment>
          <Button
            icon={scanner.open ? 'door-closed' : 'door-open'}
            content={(scanner.open ? 'Close' : 'Open') + ' Scanner'}
            disabled={!scanner.present}
            onClick={() => task(act, 'toggleopen')} />
          <Button
            icon={scanner.locked ? 'lock-open' : 'lock'}
            content={(scanner.locked ? 'Unlock' : 'Lock') + ' Scanner'}
            disabled={!scanner.present || scanner.open}
            onClick={() => task(act, 'togglelock')} />
          <Button
            icon="random"
            content="Scramble DNA"
            disabled={!data.can_scramble}
            onClick={() => task(act, 'scramble')} />
        </Fragment>
      )}>
      <Flex>
        <Flex.Item grow={1} basis={0}>
          <LabeledList>
            <LabeledList.Item label="Scanner">{scannerText}</LabeledList.Item>
            <LabeledList.Item label="Subject">{subjectText}</LabeledList.Item>
            {!!subject && (
              <Fragment>
                <LabeledList.Item label="Health">
                  <ProgressBar
                    value={subject.health / 100}
                    color="good"
                    content={subject.health + ' %'} />
                </LabeledList.Item>
                <LabeledList.Item label="Radiation">
                  <ProgressBar
                    value={subject.radiation / 100}
                    color="bad"
                    content={subject.radiation + ' %'} />
                </LabeledList.Item>
                <LabeledList.Item label="Unique enzymes">
                  <Box color="average">{subject.ue}</Box>
                </LabeledList.Item>
                <LabeledList.Item label="Last operation">
                  {data.last_operation || '----'}
                </LabeledList.Item>
              </Fragment>
            )}
          </LabeledList>
        </Flex.Item>
        <Flex.Item grow={1} basis={0} ml={2}>
          <LabeledList>
            <LabeledList.Item label="Output level">
              {data.radstrength}
            </LabeledList.Item>
            <LabeledList.Item label="Mutation">
              {data.mutation_range}
            </LabeledList.Item>
            <LabeledList.Item label="Pulse duration">
              {data.radduration}
            </LabeledList.Item>
            <LabeledList.Item label="Accuracy">
              {data.accuracy}
            </LabeledList.Item>
          </LabeledList>
        </Flex.Item>
      </Flex>
    </Section>
  );
};

const SCREENS = [
  ['mainmenu', 'Genetic Sequencer', 'dna'],
  ['ui', 'Unique Identifiers', 'fingerprint'],
  ['mutations', 'Mutations', 'flask'],
  ['disk', 'Disk', 'save'],
];

// The screens, as tabs
const Controls = props => {
  const { data, act } = props;
  return (
    <Box mb={1}>
      {SCREENS.map(([screen, title, icon]) => (
        <Button
          key={screen}
          icon={icon}
          content={title}
          selected={data.screen === screen}
          disabled={screen === 'disk' && !data.has_disk}
          onClick={() => task(act, 'screen', { text: screen })} />
      ))}
    </Box>
  );
};

const KIND_TITLE = {
  extra: 'Extra mutation',
  discovered: 'Discovered mutation',
  undiscovered: 'Undiscovered mutation',
};

const Sequencer = props => {
  const { data, act } = props;
  const sequence = data.sequence || [];
  return (
    <Fragment>
      <Section title="Genetic sequence">
        {sequence.length === 0 && (
          <Box color="label">----------</Box>
        )}
        {sequence.map(gene => (
          <Box
            key={gene.location}
            inline
            mr={0.5}
            title={KIND_TITLE[gene.kind]}
            style={{
              'cursor': 'pointer',
              'border': '2px solid '
                + (gene.selected ? '#5baa27' : 'transparent'),
            }}
            onClick={() => task(act, 'inspect', { num: gene.location })}>
            <img
              src={'dna_' + gene.kind + '.png'}
              width="65px"
              style={{ 'display': 'block' }} />
          </Box>
        ))}
      </Section>
      {!!data.gene && (
        <GeneView gene={data.gene} data={data} act={act} />
      )}
    </Fragment>
  );
};

const GENES = ['A', 'T', 'G', 'C', 'X'];

class GeneView extends Component {
  constructor() {
    super();
    this.state = { picking: null };
  }

  render() {
    const { gene, data, act } = this.props;
    const { picking } = this.state;
    const base = (b, i) => (
      <Button
        key={i}
        width="24px"
        textAlign="center"
        content={b.base}
        selected={picking && picking.num === b.num}
        disabled={!gene.editable}
        onClick={() => this.setState({ picking: b })} />
    );
    const choices = GENES.slice();
    if (data.joker_ready) {
      choices.push('JOKER');
    }
    let title = <Box inline>{gene.alias}</Box>;
    if (gene.discovered && !gene.scrambled) {
      title = (
        <Fragment>
          <Box inline color={gene.quality}>{gene.name}</Box>
          <Box inline ml={1} color="label" fontSize="11px">
            {'(' + gene.alias + ')'}
          </Box>
        </Fragment>
      );
    }
    const slot = gene.storage_slot;
    const chromosomes = gene.chromosomes || [];
    return (
      <Section title={title}>
        <LabeledList>
          {gene.instability !== undefined && (
            <LabeledList.Item label="Instability">
              {gene.instability}
            </LabeledList.Item>
          )}
          <LabeledList.Item label="Description">{gene.desc}</LabeledList.Item>
          {!!gene.chromosome && (
            <LabeledList.Item label="Chromosome">
              {gene.chromosome}
              {chromosomes.map(chromosome => (
                <Button
                  key={chromosome.index}
                  ml={1}
                  icon="plus"
                  content={'Apply ' + chromosome.name}
                  onClick={() => act('apply_chromosome', {
                    mutation_index: gene.mutation_index,
                    chromosome: chromosome.index,
                  })} />
              ))}
            </LabeledList.Item>
          )}
        </LabeledList>
        {!!picking && (
          <Box mt={1}>
            <Box inline mr={1} color="label">
              {'Base ' + picking.num + ', from ' + picking.base + ' to'}
            </Box>
            {choices.map(choice => (
              <Button
                key={choice}
                content={choice}
                color={choice === 'JOKER' ? 'average' : null}
                onClick={() => {
                  act('gene', {
                    alias: gene.alias,
                    num: picking.num,
                    gene: choice,
                  });
                  this.setState({ picking: null });
                }} />
            ))}
            <Button
              content="Cancel"
              color="transparent"
              onClick={() => this.setState({ picking: null })} />
          </Box>
        )}
        <Box mt={1}>
          {!!gene.scrambled && (
            <Box color="bad">
              Sequence unreadable due to unpredictable mutation.
            </Box>
          )}
          {(gene.blocks || []).map((block, i) => (
            <Box key={i} inline mr={2} mb={1} textAlign="center">
              <Box>{block.top.map(base)}</Box>
              <Box color="label">
                {block.top.map((b, j) => (
                  <Box key={j} inline width="24px" mx="1px">|</Box>
                ))}
              </Box>
              <Box>{block.bottom.map(base)}</Box>
            </Box>
          ))}
        </Box>
        <Box>
          <Button
            icon="syringe"
            content="Print Activator"
            disabled={!gene.can_print}
            onClick={() => task(act, 'activator', {
              alias: gene.alias,
              slot,
            })} />
          <Button
            icon="syringe"
            content="Print Mutator"
            disabled={!gene.can_print}
            onClick={() => task(act, 'mutator', {
              alias: gene.alias,
              slot,
            })} />
          {!!gene.can_store && (
            <Button
              icon="download"
              content="Store"
              onClick={() => task(act, 'savemut', { alias: gene.alias })} />
          )}
          {!!slot && (
            <Fragment>
              <Button
                icon="trash"
                content="Delete"
                onClick={() => task(act, 'deletemut', { num: slot })} />
              <Button
                icon="save"
                content="Export"
                disabled={!gene.can_export}
                onClick={() => task(act, 'exportdiskmut', {
                  alias: gene.alias,
                })} />
              <Button
                icon="arrow-left"
                content="Back"
                onClick={() => task(act, 'screen', { text: 'mutations' })} />
            </Fragment>
          )}
          {!slot && (
            <Button
              icon="ban"
              content="Nullify"
              disabled={!gene.can_nullify}
              onClick={() => task(act, 'nullify')} />
          )}
        </Box>
      </Section>
    );
  }
}

const BufferSlot = props => {
  const { slot, data, act } = props;
  const subject = !!data.scanner.subject;
  const n = slot.index;
  const occupantButtons = kind => (
    <Fragment>
      <Button
        content="Occupant"
        disabled={!subject}
        onClick={() => task(act, 'transferbuffer', { num: n, text: kind })} />
      <Button
        content="Occupant: Delayed"
        onClick={() => task(act, 'setdelayed', {
          num: n,
          delayaction: { ui: 2, ue: 3, mixed: 4 }[kind],
        })} />
      <Button
        icon="syringe"
        content="Injector"
        disabled={!data.injector_ready}
        onClick={() => task(act, 'injector', { num: n, text: kind })} />
    </Fragment>
  );
  const common = (
    <Box mt={0.5}>
      <Button
        icon="download"
        content="Save to Buffer"
        disabled={!subject}
        onClick={() => task(act, 'setbuffer', { num: n })} />
      <Button
        icon="trash"
        content="Clear Buffer"
        disabled={slot.empty}
        onClick={() => task(act, 'clearbuffer', { num: n })} />
      <Button
        icon="upload"
        content="Load from Disk"
        disabled={!data.has_disk}
        onClick={() => task(act, 'loaddisk', { num: n })} />
      <Button
        icon="save"
        content="Save to Disk"
        disabled={slot.empty || !data.has_disk || data.disk_read_only}
        onClick={() => task(act, 'savedisk', { num: n })} />
    </Box>
  );
  if (slot.empty) {
    return (
      <Section level={2} title={'Slot ' + n}>
        <Box color="label">No data</Box>
        {common}
      </Section>
    );
  }
  return (
    <Section
      level={2}
      title={'Slot ' + n}
      buttons={data.delayed === n && (
        <Box color="average">Delayed action set</Box>
      )}>
      <LabeledList>
        <LabeledList.Item label="Label">
          <Input
            value={slot.label}
            onChange={(e, value) => act('label', { num: n, label: value })} />
        </LabeledList.Item>
        <LabeledList.Item label="Subject">{slot.name}</LabeledList.Item>
        <LabeledList.Item label="Blood type">
          {slot.has_ue ? slot.blood_type : 'No data'}
        </LabeledList.Item>
        <LabeledList.Item
          label="UE"
          buttons={!!slot.has_ue && occupantButtons('ue')}>
          {slot.has_ue ? slot.ue : 'No data'}
        </LabeledList.Item>
        <LabeledList.Item
          label="UI"
          buttons={!!slot.ui && occupantButtons('ui')}>
          {slot.ui || 'No data'}
        </LabeledList.Item>
        {!!(slot.has_ue && slot.ui) && (
          <LabeledList.Item
            label="UI + UE"
            buttons={occupantButtons('mixed')}>
            Both
          </LabeledList.Item>
        )}
      </LabeledList>
      {common}
    </Section>
  );
};

const Identifiers = props => {
  const { data, act } = props;
  const identity = data.identity || [];
  const stepper = (name, value) => (
    <Fragment>
      <Button
        content="-"
        onClick={() => task(act, name, { num: value - 1 })} />
      <Box inline width="24px" textAlign="center">{value}</Box>
      <Button
        content="+"
        onClick={() => task(act, name, { num: value + 1 })} />
    </Fragment>
  );
  return (
    <Fragment>
      <Section title="Unique Identifiers">
        <LabeledList>
          <LabeledList.Item label="Output level">
            {stepper('setstrength', data.radstrength)}
          </LabeledList.Item>
          <LabeledList.Item label="Pulse duration">
            {stepper('setduration', data.radduration)}
          </LabeledList.Item>
        </LabeledList>
        <Box mt={1} mb={0.5} color="label">
          Irradiate: select a block
        </Box>
        {identity.length === 0 && <Box color="label">---------</Box>}
        {identity.map((block, i) => (
          <Box key={i} inline mr={1} mb={0.5}>
            <Box inline color="label" mr={0.5}>{i + 1}</Box>
            {block.map(c => (
              <Button
                key={c.num}
                width="20px"
                textAlign="center"
                content={c.char}
                onClick={() => task(act, 'pulseui', { num: c.num })} />
            ))}
          </Box>
        ))}
      </Section>
      <Section title="Buffers">
        {(data.buffers || []).map(slot => (
          <BufferSlot key={slot.index} slot={slot} data={data} act={act} />
        ))}
      </Section>
    </Fragment>
  );
};

const Mutations = props => {
  const { data, act } = props;
  const stored = data.stored || [];
  const chromosomes = data.chromosomes || [];
  return (
    <Fragment>
      <Section
        title={'Mutation storage (' + stored.length + ' of '
          + data.max_storage + ')'}>
        {stored.length === 0 && <Box color="label">Empty.</Box>}
        {stored.map(mutation => (
          <Box key={mutation.index} className="candystripe" p={0.5}>
            <Button
              color="transparent"
              content={mutation.name}
              onClick={() => task(act, 'inspectstorage', {
                num: mutation.index,
              })} />
            <Box inline style={{ 'float': 'right' }}>
              <Button
                icon="save"
                content="Export"
                disabled={!data.has_disk}
                onClick={() => task(act, 'exportdiskmut', {
                  alias: mutation.alias,
                })} />
              <Button
                icon="trash"
                content="Delete"
                onClick={() => task(act, 'deletemut', {
                  num: mutation.index,
                })} />
              <Button
                icon="object-group"
                content="Combine"
                selected={mutation.combining}
                onClick={() => task(act, 'combine', { num: mutation.index })} />
            </Box>
          </Box>
        ))}
      </Section>
      <Section title="Chromosome storage">
        {chromosomes.length === 0 && <Box color="label">Empty.</Box>}
        {chromosomes.map(chromosome => (
          <Box key={chromosome.index} className="candystripe" p={0.5}>
            {chromosome.name}
            <Button
              ml={1}
              icon="eject"
              content="Eject"
              onClick={() => act('eject_chromosome', {
                num: chromosome.index,
              })} />
          </Box>
        ))}
      </Section>
    </Fragment>
  );
};

const Disk = props => {
  const { data, act } = props;
  const disk = data.disk;
  if (!disk) {
    return <NoticeBox>Load diskette to start.</NoticeBox>;
  }
  return (
    <Section
      title={disk.name}
      buttons={(
        <Button
          icon="eject"
          content="Eject Disk"
          onClick={() => task(act, 'ejectdisk')} />
      )}>
      {disk.mutations.length === 0 && (
        <Box color="label">No mutations on it.</Box>
      )}
      {disk.mutations.map(mutation => (
        <Box key={mutation.index} className="candystripe" p={0.5}>
          {mutation.name}
          <Box inline style={{ 'float': 'right' }}>
            <Button
              icon="trash"
              content="Delete"
              disabled={disk.read_only}
              onClick={() => task(act, 'deletediskmut', {
                num: mutation.index,
              })} />
            <Button
              icon="upload"
              content="Import"
              disabled={!disk.can_import}
              onClick={() => task(act, 'importdiskmut', {
                num: mutation.index,
              })} />
          </Box>
        </Box>
      ))}
    </Section>
  );
};

export const DnaConsole = props => {
  const { act, data } = useBackend(props);
  const screen = data.screen;
  let body;
  if (screen === 'working') {
    body = (
      <NoticeBox>
        {'System busy. Working... please wait (' + data.working_time + ')'}
      </NoticeBox>
    );
  } else if (screen === 'ui') {
    body = <Identifiers data={data} act={act} />;
  } else if (screen === 'mutations') {
    body = <Mutations data={data} act={act} />;
  } else if (screen === 'disk') {
    body = <Disk data={data} act={act} />;
  } else if (screen === 'info') {
    body = data.gene
      ? <GeneView gene={data.gene} data={data} act={act} />
      : <NoticeBox>Nothing in that slot.</NoticeBox>;
  } else {
    body = <Sequencer data={data} act={act} />;
  }
  return (
    <Fragment>
      <ScannerStatus data={data} act={act} />
      {screen !== 'working' && <Controls data={data} act={act} />}
      {body}
    </Fragment>
  );
};
