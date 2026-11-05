import { classes } from 'common/react';
import { Fragment } from 'inferno';
import { useBackend } from '../backend';
import { Box, Button, NoticeBox, Section } from '../components';

// hippie -- the pipe, disposal pipe and transit tube dispensers
// (hippiestation/.../pipe/pipe_dispenser_tgui.dm). The pictures are the
// RPD's sprite sheet.

const Piece = props => {
  const { item, group, bent, act } = props;
  return (
    <Box inline width="50%" p="2px">
      <Button
        fluid
        color="transparent"
        style={{
          'display': 'flex',
          'align-items': 'center',
          'height': '38px',
        }}
        onClick={() => act('make', {
          group,
          index: item.index,
          bent: bent ? 1 : 0,
        })}>
        <Box
          className={classes([
            'pipes32x32',
            (bent ? 'northeast' : 'south') + '-' + item.icon_state,
          ])}
          style={{ 'flex-shrink': 0, 'margin-right': '6px' }} />
        <Box style={{
          'white-space': 'normal',
          'line-height': '14px',
          'color': 'rgba(255, 255, 255, 0.9)',
        }}>
          {(bent ? 'Bent ' : '') + item.name}
        </Box>
      </Button>
    </Box>
  );
};

export const PipeDispenser = props => {
  const { act, data } = useBackend(props);
  const groups = data.groups || [];
  const layers = [];
  for (let i = 1; i <= data.layers; i++) {
    layers.push(i);
  }
  return (
    <Fragment>
      {layers.length > 0 && (
        <Section
          title="Piping layer"
          buttons={layers.map(layer => (
            <Button
              key={layer}
              content={layer}
              selected={data.piping_layer === layer}
              onClick={() => act('layer', { layer })} />
          ))}>
          {!data.anchored && (
            <NoticeBox>It has to be bolted down to dispense.</NoticeBox>
          )}
        </Section>
      )}
      {groups.map(group => (
        <Section key={group.name} title={group.name}>
          {group.items.map(item => (
            <Fragment key={item.index}>
              <Piece item={item} group={group.name} act={act} />
              {!!item.bendable && (
                <Piece item={item} group={group.name} bent act={act} />
              )}
            </Fragment>
          ))}
        </Section>
      ))}
    </Fragment>
  );
};
