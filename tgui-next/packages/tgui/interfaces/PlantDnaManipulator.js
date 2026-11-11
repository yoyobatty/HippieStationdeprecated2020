import { Fragment } from 'inferno';
import { useBackend } from '../backend';
import { Box, Button, Flex, LabeledList, NoticeBox, Section } from '../components';

// hippie -- the plant DNA manipulator
// (hippiestation/.../hydroponics/gene_modder_tgui.dm)

const Gene = props => {
  const { gene, act } = props;
  const pick = op => act('gene', { ref: gene.ref, op });
  return (
    <Flex className="candystripe" p={0.5} align="center">
      <Flex.Item grow={1}>
        {gene.name}
        {!!gene.limit && (
          <Box inline ml={1} color="average">
            {'(extracts at ' + gene.limit + ')'}
          </Box>
        )}
      </Flex.Item>
      <Flex.Item>
        {!!gene.can_extract && (
          <Button
            icon="download"
            content="Extract"
            onClick={() => pick('extract')} />
        )}
        {!!gene.can_replace && (
          <Button
            icon="exchange-alt"
            content="Replace"
            onClick={() => pick('replace')} />
        )}
        {!!gene.can_remove && (
          <Button
            icon="trash"
            content="Remove"
            color="bad"
            onClick={() => pick('remove')} />
        )}
      </Flex.Item>
    </Flex>
  );
};

const GeneList = props => {
  const { title, genes, empty, insert, act } = props;
  let buttons = null;
  if (insert) {
    buttons = (
      <Button
        icon="upload"
        content={'Insert ' + insert}
        onClick={() => act('insert')} />
    );
  }
  return (
    <Section title={title} buttons={buttons}>
      {genes.length === 0 && <Box color="label">{empty}</Box>}
      {genes.map(gene => (
        <Gene key={gene.ref} gene={gene} act={act} />
      ))}
    </Section>
  );
};

const Confirm = props => {
  const { data, act } = props;
  const confirm = () => {
    if (data.operation === 'insert') {
      act('insert');
      return;
    }
    act('gene', { ref: data.target_ref, op: data.operation });
  };
  return (
    <Section title="Confirm operation">
      <Box mb={1}>{data.question}</Box>
      {(data.warnings || []).map(warning => (
        <Box key={warning} color="bad" mb={1}>{warning}</Box>
      ))}
      <Button
        icon="check"
        content="Confirm"
        color="good"
        onClick={confirm} />
      <Button
        icon="times"
        content="Abort"
        onClick={() => act('abort')} />
    </Section>
  );
};

export const PlantDnaManipulator = props => {
  const { act, data } = useBackend(props);
  const busy = !!data.operation;
  const seed = data.seed;
  const disk = data.disk;
  let seedLine = <Box color="label">None</Box>;
  if (seed) {
    seedLine = (
      <Box>
        {!!seed.icon && (
          <img
            src={seed.icon}
            width="24px"
            height="24px"
            style={{
              '-ms-interpolation-mode': 'nearest-neighbor',
              'vertical-align': 'middle',
              'margin': '-6px 6px -6px 0',
            }} />
        )}
        {seed.name}
      </Box>
    );
  }
  let diskLine = (
    <Box color="label">No disk.</Box>
  );
  if (disk) {
    diskLine = (
      <Box>
        {disk.gene || 'Empty disk'}
        {!!disk.read_only && (
          <Box inline ml={1} color="average">(read-only)</Box>
        )}
      </Box>
    );
  }
  let body = (
    <NoticeBox>
      No sample. Put some seeds in to work on the plant&apos;s genes.
    </NoticeBox>
  );
  if (busy) {
    body = <Confirm data={data} act={act} />;
  }
  else if (seed) {
    body = (
      <Fragment>
        <GeneList
          title="Core genes"
          genes={data.core || []}
          empty="None."
          act={act} />
        {!!data.has_contents && (
          <GeneList
            title="Content genes"
            genes={data.contents || []}
            empty="No content genes in this sample."
            insert={data.insert_reagent}
            act={act} />
        )}
        {!!data.has_contents && (
          <GeneList
            title="Trait genes"
            genes={data.traits || []}
            empty="No trait genes in this sample."
            insert={data.insert_trait}
            act={act} />
        )}
      </Fragment>
    );
  }
  return (
    <Fragment>
      <Section>
        <LabeledList>
          <LabeledList.Item
            label="Sample"
            buttons={(
              <Button
                icon={seed ? 'eject' : 'sign-in-alt'}
                content={seed ? 'Eject' : 'Insert'}
                disabled={busy || (!seed && !data.holding_seed)}
                onClick={() => act('eject_seed')} />
            )}>
            {seedLine}
          </LabeledList.Item>
          <LabeledList.Item
            label="Disk"
            buttons={(
              <Button
                icon={disk ? 'eject' : 'sign-in-alt'}
                content={disk ? 'Eject' : 'Insert'}
                disabled={busy || (!disk && !data.holding_disk)}
                onClick={() => act('eject_disk')} />
            )}>
            {diskLine}
          </LabeledList.Item>
        </LabeledList>
      </Section>
      {body}
    </Fragment>
  );
};
