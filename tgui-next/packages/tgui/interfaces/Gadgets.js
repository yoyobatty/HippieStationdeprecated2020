import { Fragment } from 'inferno';
import { useBackend } from '../backend';
import { Box, Button, LabeledList, NoticeBox, Section } from '../components';

// hippie -- the implant pad, hand teleporter, safe, destination tagger and
// secure storage keypad (hippiestation/code/modules/assembly/gadgets_tgui.dm)

// The implant's read-out is the game's own HTML, as in the old window
const Html = props => (
  // eslint-disable-next-line react/no-danger
  <div {...props} dangerouslySetInnerHTML={{ __html: props.html }} />
);

export const ImplantPad = props => {
  const { act, data } = useBackend(props);
  return (
    <Fragment>
      <Section
        title="Implant case"
        buttons={!!data.case && (
          <Button
            icon="eject"
            content="Eject"
            onClick={() => act('eject')} />
        )}>
        {!data.case && (
          <Box color="label">Empty. Put an implant case in.</Box>
        )}
        {!!data.case && !data.implant && (
          <Box color="label">The case is empty.</Box>
        )}
        {!!data.implant && <Box bold>{data.implant}</Box>}
      </Section>
      {!!data.info && (
        <Section title="Read-out">
          <Html html={data.info} />
        </Section>
      )}
    </Fragment>
  );
};

export const HandTeleporter = props => {
  const { act, data } = useBackend(props);
  const full = data.portals >= data.max_portals;
  const places = data.destinations || [];
  return (
    <Fragment>
      <Section>
        <LabeledList>
          <LabeledList.Item label="Portals open">
            <Box inline bold color={full ? 'bad' : null}>
              {data.portals + ' of ' + data.max_portals}
            </Box>
            {full && <Box inline ml={1} color="label">recharging</Box>}
          </LabeledList.Item>
        </LabeledList>
        {!!data.blocked && (
          <NoticeBox mt={1}>It&apos;s malfunctioning here.</NoticeBox>
        )}
      </Section>
      <Section title="Lock on to">
        {places.length === 0 && (
          <Box color="label">No teleporter has a target set.</Box>
        )}
        {places.map(place => (
          <Box
            key={place.ref}
            className="candystripe"
            style={{ 'display': 'flex', 'align-items': 'center',
              'padding': '3px 2px' }}>
            <Box style={{ 'flex-grow': 1 }}>
              {place.name.replace(/ \((Active|Inactive)\)$/, '')}
              <Box
                inline
                ml={1}
                fontSize="11px"
                color={place.active ? 'good' : 'label'}>
                {place.active ? 'active' : 'inactive'}
              </Box>
            </Box>
            <Button
              icon="dot-circle"
              content="Open portal"
              disabled={full || data.blocked}
              onClick={() => act('portal', { ref: place.ref })} />
          </Box>
        ))}
        <Button
          mt={1}
          icon="random"
          color="bad"
          content="Somewhere close by (dangerous)"
          disabled={full || data.blocked}
          onClick={() => act('portal', { ref: 'random' })} />
      </Section>
    </Fragment>
  );
};

const Dial = props => {
  const { value } = props;
  const ticks = [];
  for (let i = 0; i < 72; i++) {
    const angle = (i / 72) * 2 * Math.PI - Math.PI / 2;
    const long = i % 6 === 0;
    const r1 = long ? 70 : 76;
    ticks.push(
      <line
        key={i}
        x1={90 + r1 * Math.cos(angle)}
        y1={90 + r1 * Math.sin(angle)}
        x2={90 + 82 * Math.cos(angle)}
        y2={90 + 82 * Math.sin(angle)}
        stroke={long ? '#c9c9c9' : '#6b6b6b'}
        strokeWidth={long ? 2 : 1} />,
    );
  }
  const pointer = (value / 72) * 2 * Math.PI - Math.PI / 2;
  return (
    <svg width="180" height="180" viewBox="0 0 180 180">
      <circle cx="90" cy="90" r="86" fill="#2b2b2b" stroke="#111111"
        strokeWidth="3" />
      {ticks}
      <circle cx="90" cy="90" r="56" fill="#3a3a3a" stroke="#1a1a1a"
        strokeWidth="2" />
      <line
        x1="90"
        y1="90"
        x2={90 + 62 * Math.cos(pointer)}
        y2={90 + 62 * Math.sin(pointer)}
        stroke="#d9a400"
        strokeWidth="4"
        strokeLinecap="round" />
      <circle cx="90" cy="90" r="8" fill="#d9a400" />
      <text x="90" y="128" fill="#ffffff" fontSize="20"
        fontFamily="monospace" textAnchor="middle">
        {value}
      </text>
    </svg>
  );
};

export const Safe = props => {
  const { act, data } = useBackend(props);
  const inside = data.contents || [];
  return (
    <Fragment>
      <Section textAlign="center">
        <Dial value={data.dial} />
        <Box mt={1}>
          <Button
            icon="undo"
            content="5"
            onClick={() => act('turn', { by: -5 })} />
          <Button
            icon="undo"
            content="1"
            onClick={() => act('turn', { by: -1 })} />
          <Button
            icon="redo"
            content="1"
            onClick={() => act('turn', { by: 1 })} />
          <Button
            icon="redo"
            content="5"
            onClick={() => act('turn', { by: 5 })} />
        </Box>
        <Button
          mt={1}
          icon={data.open ? 'door-closed' : 'door-open'}
          content={data.open ? 'Close the safe' : 'Open the safe'}
          onClick={() => act('open')} />
        <Box mt={1} color="label" fontSize="11px">
          {data.stethoscope
            ? 'With the stethoscope you hear the tumblers as they turn.'
            : 'A stethoscope in hand would let you hear the tumblers.'}
        </Box>
      </Section>
      {!!data.open && (
        <Section title={'Inside (' + inside.length + ')'}>
          {inside.length === 0 && <Box color="label">Nothing.</Box>}
          {inside.map(item => (
            <Box
              key={item.ref}
              className="candystripe"
              style={{ 'display': 'flex', 'align-items': 'center',
                'padding': '3px 2px' }}>
              <Box style={{ 'flex-grow': 1 }}>{item.name}</Box>
              <Button
                icon="hand-paper"
                content="Take out"
                onClick={() => act('retrieve', { ref: item.ref })} />
            </Box>
          ))}
        </Section>
      )}
    </Fragment>
  );
};

export const DestinationTagger = props => {
  const { act, data } = useBackend(props);
  const places = data.destinations || [];
  return (
    <Section
      title={'Tagged for: '
        + (data.current ? places[data.current - 1] : 'nowhere yet')}>
      <Box
        style={{ 'display': 'grid',
          'grid-template-columns': 'repeat(4, 1fr)', 'grid-gap': '2px' }}>
        {places.map((place, i) => (
          <Button
            key={place}
            fluid
            content={place}
            selected={data.current === i + 1}
            onClick={() => act('tag', { index: i + 1 })} />
        ))}
      </Box>
    </Section>
  );
};

const KEYS = ['1', '2', '3', '4', '5', '6', '7', '8', '9', 'R', '0', 'E'];

const KEY_COLOURS = { R: 'bad', E: 'good' };

const KEY_TIPS = { R: 'Lock and clear', E: 'Enter' };

export const SecureStorage = props => {
  const { act, data } = useBackend(props);
  return (
    <Section>
      <Box
        mb={1}
        textAlign="right"
        style={{ 'background-color': '#0d1a0d', 'color': '#5bff5b',
          'font-family': 'monospace', 'font-size': '22px',
          'padding': '4px 10px', 'border': '1px solid #2a4a2a',
          'letter-spacing': '4px', 'min-height': '30px' }}>
        {data.display || ''}
      </Box>
      <Box
        mb={1}
        bold
        textAlign="center"
        color={data.locked ? 'bad' : 'good'}>
        {data.locked ? 'LOCKED' : 'UNLOCKED'}
      </Box>
      {!data.code_set && !data.memory_error && (
        <NoticeBox>No code set. Type five digits and press E.</NoticeBox>
      )}
      {!!data.memory_error && (
        <NoticeBox>ALERT: MEMORY SYSTEM ERROR - 6040 201</NoticeBox>
      )}
      <Box
        style={{ 'display': 'grid',
          'grid-template-columns': 'repeat(3, 1fr)', 'grid-gap': '4px' }}>
        {KEYS.map(key => (
          <Button
            key={key}
            fluid
            textAlign="center"
            fontSize="18px"
            color={KEY_COLOURS[key]}
            content={key}
            tooltip={KEY_TIPS[key]}
            onClick={() => act('key', { key: key })} />
        ))}
      </Box>
    </Section>
  );
};
