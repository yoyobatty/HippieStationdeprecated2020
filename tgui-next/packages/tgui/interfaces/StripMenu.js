import { useBackend } from '../backend';
import { Box, Button, Section } from '../components';

// hippie -- what dragging someone onto yourself opens
// (hippiestation/.../carbon/strip_menu_tgui.dm)

// The item's picture, or the same width of nothing so the buttons line up
const Picture = props => {
  const { icon } = props;
  if (!icon) {
    return <Box width="32px" mr="6px" style={{ 'flex-shrink': 0 }} />;
  }
  return (
    <img
      src={icon}
      width="32px"
      height="32px"
      style={{
        'flex-shrink': 0,
        'margin-right': '6px',
        '-ms-interpolation-mode': 'nearest-neighbor',
        'image-rendering': 'pixelated',
      }} />
  );
};

// One slot: its name, the picture, and the buttons beside it, wrapping there
// rather than under the picture
const Line = props => {
  const { label, muted, icon, children } = props;
  return (
    <Box
      mb="2px"
      style={{
        'display': 'flex',
        'align-items': 'center',
        'min-height': '24px',
      }}>
      <Box
        width="100px"
        color={muted ? 'grey' : 'label'}
        style={{ 'flex-shrink': 0 }}>
        {label + ':'}
      </Box>
      <Picture icon={icon} />
      <Box style={{ 'flex-grow': 1 }}>
        {children}
      </Box>
    </Box>
  );
};

const SlotContent = props => {
  const { row, label, holding, act } = props;
  if (row.blocked) {
    return <Line label={label} muted />;
  }
  if (row.obscured) {
    return (
      <Line label={label} muted>
        <Box inline color="label" ml="6px">Obscured</Box>
      </Line>
    );
  }
  if (row.pockets) {
    const pocket = side => {
      const full = row.pockets[side];
      const name = side === 'left' ? 'Left' : 'Right';
      return (
        <Button
          content={name + (full ? ' (Full)' : ' (Empty)')}
          color={full ? null : 'transparent'}
          tooltip={!full && holding ? 'Slip ' + holding + ' in' : null}
          onClick={() => act('pockets', { side })} />
      );
    };
    return (
      <Line label={label}>
        {pocket('left')}
        {pocket('right')}
      </Line>
    );
  }
  let tooltip = null;
  if (row.cuffs) {
    tooltip = 'Remove';
  } else if (!row.item && holding) {
    tooltip = 'Put ' + holding + ' here';
  }
  return (
    <Line label={label} icon={row.icon}>
      <Button
        content={row.item || 'Empty'}
        color={row.item ? null : 'transparent'}
        tooltip={tooltip}
        onClick={() => act('item', { slot: row.slot, hand: row.hand })} />
      {!!row.internals && (
        <Button
          icon="wind"
          content={row.internals === 'close'
            ? 'Disable internals'
            : 'Set internals'}
          onClick={() => act('internal', { slot: row.slot })} />
      )}
    </Line>
  );
};

export const StripMenu = props => {
  const { act, data } = useBackend(props);
  const rows = data.rows || [];
  const items = [];
  rows.forEach((row, i) => {
    if (row.gap && i > 0) {
      items.push(<Box key={'gap' + i} height="8px" />);
    }
    items.push(
      <SlotContent
        key={row.label + i}
        row={row}
        label={(row.sub ? '↳ ' : '') + row.label}
        holding={data.holding}
        act={act} />,
    );
  });
  return (
    <Section>
      {items}
    </Section>
  );
};
