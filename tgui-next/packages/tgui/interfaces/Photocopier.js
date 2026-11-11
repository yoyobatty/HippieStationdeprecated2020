import { Fragment } from 'inferno';
import { useBackend } from '../backend';
import { Box, Button, Icon, LabeledList, NoticeBox, ProgressBar, Section } from '../components';

// hippie -- the photocopier
// (hippiestation/code/modules/paperwork/photocopier_tgui.dm)

const KINDS = {
  paper: 'file-alt',
  photo: 'image',
  documents: 'folder',
  ass: 'user',
};

const PAGE = {
  'background-color': '#f2efe6',
  'color': '#222222',
  'font-family': 'Verdana, sans-serif',
  'font-size': '11px',
  'padding': '6px 8px',
  'max-height': '96px',
  'overflow': 'hidden',
  'white-space': 'pre-wrap',
  'border-radius': '2px',
  'box-shadow': '0 1px 3px rgba(0, 0, 0, 0.6)',
};

export const Photocopier = props => {
  const { act, data } = useBackend(props);
  const kind = data.kind;
  let status = 'Copy';
  if (data.copies_left > 0) {
    status = 'Printing... ' + data.copies_left + ' to go';
  }
  else if (data.busy) {
    status = 'Printing...';
  }
  return (
    <Fragment>
      <Section
        title="On the glass"
        buttons={!!kind && (
          <Button
            icon="eject"
            content={kind === 'ass' ? 'Shoo' : 'Take out'}
            onClick={() => act('remove')} />
        )}>
        {!kind && (
          <Box color="label">
            Empty.
          </Box>
        )}
        {!!kind && (
          <Box bold mb={kind === 'paper' ? 1 : 0}>
            <Icon name={KINDS[kind]} mr={1} />
            {kind === 'ass' ? data.what + ', sat on it' : data.what}
          </Box>
        )}
        {kind === 'paper' && (
          <Box style={PAGE}>
            {data.preview || <Box inline color="#888888">Blank.</Box>}
          </Box>
        )}
        {kind === 'ass' && !!data.clothed && (
          <NoticeBox mt={1}>
            They&apos;ve still got their clothes on.
          </NoticeBox>
        )}
      </Section>
      <Section title="Copies">
        <LabeledList>
          <LabeledList.Item label="How many">
            <Button
              icon="minus"
              disabled={data.copies <= 1 || data.busy}
              onClick={() => act('copies', { by: -1 })} />
            <Box inline bold mx={1}>{data.copies}</Box>
            <Button
              icon="plus"
              disabled={data.copies >= data.max_copies || data.busy}
              onClick={() => act('copies', { by: 1 })} />
          </LabeledList.Item>
          {kind === 'photo' && (
            <LabeledList.Item label="Print in">
              <Button
                content="Greyscale"
                selected={data.greyscale}
                onClick={() => act('colour', { greyscale: 1 })} />
              <Button
                content="Colour"
                selected={!data.greyscale}
                onClick={() => act('colour', { greyscale: 0 })} />
            </LabeledList.Item>
          )}
          <LabeledList.Item label="Toner">
            <ProgressBar
              value={data.toner}
              maxValue={data.max_toner}
              ranges={{
                good: [data.max_toner * 0.5, Infinity],
                average: [data.max_toner * 0.2, data.max_toner * 0.5],
                bad: [-Infinity, data.max_toner * 0.2],
              }}
              content={data.toner + ' / ' + data.max_toner} />
          </LabeledList.Item>
        </LabeledList>
        {data.toner <= 0 && (
          <NoticeBox mt={1}>
            Out of toner.
          </NoticeBox>
        )}
        <Button
          mt={1}
          fluid
          icon={data.busy ? 'spinner' : 'copy'}
          iconSpin={data.busy}
          textAlign="center"
          content={status}
          disabled={!kind || !data.enough || data.busy}
          onClick={() => act('copy')} />
      </Section>
      {!!data.ai && (
        <Section>
          <Button
            icon="camera"
            content="Print a photo from my camera"
            disabled={data.toner < 5 || data.busy}
            onClick={() => act('aipic')} />
        </Section>
      )}
    </Fragment>
  );
};
