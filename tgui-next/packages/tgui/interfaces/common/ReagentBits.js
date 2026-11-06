import { Box, Table } from '../../components';

// hippie -- pieces the chemistry windows share: a container's fill drawn in
// the colour of its mix, and its reagents with their own colours

export const ColorDot = props => (
  <Box
    inline
    mr={1}
    style={{
      width: '10px',
      height: '10px',
      'border-radius': '50%',
      'vertical-align': 'middle',
      'background-color': props.color || '#888',
      'box-shadow': '0 0 3px ' + (props.color || '#888'),
      border: '1px solid rgba(255, 255, 255, 0.35)',
    }} />
);

export const FillBar = props => {
  const { volume = 0, maxVolume = 1, color } = props;
  const fraction = Math.max(0, Math.min(1, volume / (maxVolume || 1)));
  return (
    <Box
      position="relative"
      mb={1}
      style={{
        height: '22px',
        'border-radius': '3px',
        'background-color': 'rgba(0, 0, 0, 0.4)',
        border: '1px solid rgba(255, 255, 255, 0.15)',
        overflow: 'hidden',
      }}>
      <Box
        style={{
          width: (fraction * 100) + '%',
          height: '100%',
          'background-color': color || '#3e6189',
          opacity: 0.85,
          transition: 'width 200ms, background-color 200ms',
        }} />
      <Box
        position="absolute"
        style={{
          top: '2px',
          left: 0,
          right: 0,
          'text-align': 'center',
          'text-shadow': '0 0 3px #000',
        }}>
        {Math.round(volume * 100) / 100} / {maxVolume}u
      </Box>
    </Box>
  );
};

// Each reagent's row, with whatever buttons the window wants on the right
export const ReagentTable = props => {
  const { contents = [], empty, buttons } = props;
  if (!contents.length) {
    return <Box color="label">{empty || 'Empty.'}</Box>;
  }
  return (
    <Table>
      {contents.map(reagent => (
        <Table.Row key={reagent.id || reagent.name}>
          <Table.Cell py={0.25}>
            <ColorDot color={reagent.color} />
            {reagent.name}
          </Table.Cell>
          <Table.Cell collapsing textAlign="right" color="label" px={1}>
            {Math.round(reagent.volume * 100) / 100}u
          </Table.Cell>
          {!!buttons && (
            <Table.Cell collapsing>{buttons(reagent)}</Table.Cell>
          )}
        </Table.Row>
      ))}
    </Table>
  );
};
