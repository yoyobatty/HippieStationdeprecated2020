import { Fragment } from 'inferno';
import { useBackend } from '../backend';
import { Box, Button, ByondUi, ColorBox, Dropdown, Input, LabeledList, NoticeBox, NumberInput, Section, Table, Tabs } from '../components';

// hippie -- character setup (hippiestation/code/modules/client/
// preferences_tgui.dm): the old window's tabs and settings, with occupations
// and quirks as tabs, the character drawn on the left, and choices made here
// where the old one asked in pop-ups. Colours open BYOND's colour picker.

const TAB_CHARACTER = 0;
const TAB_GAME = 1;
const TAB_OOC = 2;
const TAB_KEYS = 3;
const TAB_LOADOUT = 4;
const TAB_JOBS = 5;
const TAB_QUIRKS = 6;

// A setting: shown and changed the way its row says (preferences_tgui.dm)
const Row = props => {
  const { act, row } = props;
  const link = params => act('link', params);
  const set = value => act('set', { key: row.key, value });
  const stepper = !!(row.prev || row.next) && (
    <Fragment>
      <Button icon="chevron-left" onClick={() => link(row.prev)} />
      <Button icon="chevron-right" onClick={() => link(row.next)} />
    </Fragment>
  );
  let content;
  switch (row.kind) {
    case 'toggle':
      content = (
        <Button
          selected={row.on}
          color={row.bad ? 'bad' : null}
          content={row.value}
          onClick={() => link(row.link)} />
      );
      break;
    case 'pick':
      content = (
        <Box inline>
          <Dropdown
            key={row.key + row.value}
            width="230px"
            options={row.options || []}
            selected={row.value === null ? '...' : String(row.value)}
            onSelected={value => set(value)} />
          {stepper}
        </Box>
      );
      break;
    case 'text':
      content = (
        <Box inline>
          <Input
            width="230px"
            value={row.value}
            onChange={(e, value) => set(value)} />
          {!!row.random && (
            <Button
              icon="dice"
              tooltip="Random"
              onClick={() => link(row.random)} />
          )}
        </Box>
      );
      break;
    case 'number':
      content = (
        <Box inline>
          <NumberInput
            width="60px"
            value={row.value}
            minValue={row.min}
            maxValue={row.max}
            step={1}
            stepPixelSize={4}
            onChange={(e, value) => set(value)} />
          {!!row.hint && (
            <Box inline color="label" ml={1}>{row.hint}</Box>
          )}
        </Box>
      );
      break;
    case 'color':
      content = (
        <Box inline>
          <ColorBox color={row.value} mr={1} />
          <Button
            icon="palette"
            content="Change"
            onClick={() => link(row.link)} />
        </Box>
      );
      break;
    default:
      content = (
        <Box inline>
          <Box inline color={row.bad ? 'bad' : null} mr={1}>
            {row.value}
          </Box>
          {stepper}
        </Box>
      );
  }
  return (
    <LabeledList.Item label={row.label}>
      {content}
    </LabeledList.Item>
  );
};

const Sections = props => {
  const { act, sections = [] } = props;
  return (
    <Box>
      {sections.map(section => (
        <Section
          key={section.title}
          title={section.title}
          buttons={!!section.random && (
            <Button
              icon="dice"
              content="Randomise"
              onClick={() => act('link', section.random)} />
          )}>
          {!!section.note && (
            <NoticeBox>{section.note}</NoticeBox>
          )}
          <LabeledList>
            {section.rows.map((row, i) => (
              <Row key={i} act={act} row={row} />
            ))}
          </LabeledList>
        </Section>
      ))}
    </Box>
  );
};

const LEVELS = [
  ['Never', 4, 0],
  ['Low', 3, 1],
  ['Medium', 2, 2],
  ['High', 1, 3],
];

const Jobs = props => {
  const { act, jobs = {} } = props;
  if (!jobs.ready) {
    return (
      <NoticeBox>The jobs aren&apos;t set up yet. Try again soon.</NoticeBox>
    );
  }
  const setLevel = (title, level) => act('link', {
    preference: 'job',
    task: 'setJobLevel',
    level,
    text: title,
  });
  return (
    <Section
      title="Occupations"
      buttons={(
        <Button
          icon="undo"
          content="Reset"
          onClick={() => act('link', { preference: 'job', task: 'reset' })} />
      )}>
      <Box mb={1}>
        <Button
          icon="random"
          content={jobs.jobless}
          onClick={() => act('link', { preference: 'job', task: 'random' })} />
      </Box>
      <Table>
        {jobs.jobs.map(job => (
          <Table.Row key={job.title} className="Preferences__job">
            <Table.Cell
              style={{ 'border-left': '6px solid ' + job.color }}
              pl={1}
              bold={job.head}>
              {job.title}
            </Table.Cell>
            <Table.Cell collapsing textAlign="right">
              {!!job.locked && (
                <Button
                  color="transparent"
                  textColor={job.soft ? 'average' : 'bad'}
                  content={job.locked}
                  onClick={() => job.link && act('link', job.link)} />
              ) || job.overflow && (
                <Button
                  selected={job.level > 0}
                  content={job.level > 0 ? 'Yes' : 'No'}
                  onClick={() => setLevel(job.title, 3)} />
              ) || LEVELS.map(level => (
                <Button
                  key={level[0]}
                  selected={job.level === level[2]}
                  color={job.level === level[2] && level[2] === 0
                    ? 'bad'
                    : null}
                  content={level[0]}
                  onClick={() => setLevel(job.title, level[1])} />
              ))}
            </Table.Cell>
          </Table.Row>
        ))}
      </Table>
    </Section>
  );
};

// Good ones cost points, bad ones give them
const quirkColor = value => {
  if (value > 0) {
    return 'good';
  }
  return value < 0 ? 'bad' : 'label';
};

const Quirks = props => {
  const { act, quirkList = {} } = props;
  if (!quirkList.ready) {
    return (
      <NoticeBox>
        The quirks aren&apos;t set up yet. Try again soon.
      </NoticeBox>
    );
  }
  return (
    <Section
      title="Quirks"
      buttons={(
        <Button
          icon="undo"
          content="Reset"
          onClick={() => act('link', { preference: 'trait', task: 'reset' })} />
      )}>
      <Box color="label" mb={1}>
        Negative quirks pay for positive ones. They&apos;re applied at
        round start and can&apos;t normally be removed.
      </Box>
      <Box mb={1}>
        Balance: <b>{quirkList.balance}</b>
        {' · '}Positive quirks: <b>{quirkList.positive}</b>
        {' / ' + quirkList.maxPositive}
      </Box>
      <Table>
        {quirkList.quirks.map(quirk => (
          <Table.Row key={quirk.name}>
            <Table.Cell collapsing py={0.5} pr={1}>
              {!!quirk.locked && (
                <Box color="bad">{quirk.locked}</Box>
              ) || (
                <Button
                  fluid
                  selected={quirk.has}
                  content={quirk.has ? 'Remove' : 'Take'}
                  onClick={() => act('link', {
                    preference: 'trait',
                    task: 'update',
                    trait: quirk.name,
                  })} />
              )}
            </Table.Cell>
            <Table.Cell
              collapsing
              pr={1}
              textAlign="right"
              color={quirkColor(quirk.value)}>
              {quirk.value > 0 ? '-' + quirk.value : '+' + (-quirk.value)}
            </Table.Cell>
            <Table.Cell>
              <Box bold color={quirkColor(quirk.value)}>
                {quirk.name}
              </Box>
              <Box color="label">{quirk.desc}</Box>
            </Table.Cell>
          </Table.Row>
        ))}
      </Table>
    </Section>
  );
};

const Keybinds = props => {
  const { act, keybinds = [] } = props;
  const capture = (bind, key) => act('link', {
    preference: 'keybindings_capture',
    keybinding: bind.name,
    old_key: key,
  });
  return (
    <Fragment>
      <Box mb={1}>
        <Button
          icon="undo"
          content="Reset to defaults"
          onClick={() => act('link', { preference: 'keybindings_reset' })} />
        <Box inline color="label" ml={1}>
          Click a key to rebind it.
        </Box>
      </Box>
      {keybinds.map(category => (
        <Section key={category.name} title={category.name}>
          <Table>
            {category.binds.map(bind => (
              <Table.Row key={bind.name}>
                <Table.Cell>{bind.fullName}</Table.Cell>
                <Table.Cell collapsing>
                  {bind.keys.length === 0 && (
                    <Button
                      color="transparent"
                      content="Unbound"
                      onClick={() => capture(bind, 'Unbound')} />
                  )}
                  {bind.keys.map(key => (
                    <Button
                      key={key}
                      content={key}
                      onClick={() => capture(bind, key)} />
                  ))}
                  {!!bind.canAdd && (
                    <Button
                      icon="plus"
                      tooltip="Add a second key"
                      onClick={() => act('link', {
                        preference: 'keybindings_capture',
                        keybinding: bind.name,
                      })} />
                  )}
                </Table.Cell>
                <Table.Cell collapsing color="label" pl={1}>
                  {bind.defaults ? 'Default: ' + bind.defaults : ''}
                </Table.Cell>
              </Table.Row>
            ))}
          </Table>
        </Section>
      ))}
    </Fragment>
  );
};

const Loadout = props => {
  const { act, loadout = {} } = props;
  const items = loadout.items || [];
  return (
    <Section
      title={loadout.points + ' loadout points left'}
      buttons={(
        <Button
          icon="trash"
          content="Clear loadout"
          onClick={() => act('link', {
            preference: 'gear',
            clear_loadout: 1,
          })} />
      )}>
      <Box color="label" mb={1}>
        One item per category, unless it goes in your backpack or hands.
      </Box>
      <Tabs activeTab={loadout.category}>
        {(loadout.categories || []).map(category => (
          <Tabs.Tab
            key={category}
            label={category}
            onClick={() => act('link', {
              preference: 'gear',
              select_category: category,
            })} />
        ))}
      </Tabs>
      <Table>
        {items.map(item => (
          <Table.Row key={item.name}>
            <Table.Cell collapsing py={0.5} pr={1}>
              <Button
                fluid
                selected={item.chosen}
                disabled={!item.chosen && loadout.points < item.cost}
                content={item.chosen ? 'Remove' : 'Take'}
                onClick={() => act('link', {
                  preference: 'gear',
                  toggle_gear_path: item.name,
                  toggle_gear: item.chosen ? 0 : 1,
                })} />
            </Table.Cell>
            <Table.Cell collapsing pr={1} color="label">
              {item.cost}
            </Table.Cell>
            <Table.Cell>
              <Box bold>{item.name}</Box>
              {!!item.desc && <Box color="label">{item.desc}</Box>}
              {!!item.restricted && (
                <Box color="average">Only for: {item.restricted}</Box>
              )}
            </Table.Cell>
          </Table.Row>
        ))}
      </Table>
    </Section>
  );
};

export const Preferences = props => {
  const { act, data, config } = useBackend(props);
  const {
    tab,
    previewMap,
    guest,
    noAccount,
    name,
    slot,
    slots = [],
    quirksEnabled,
    quirks = [],
  } = data;
  const tabs = [
    ['Character', TAB_CHARACTER, { preference: 'tab', tab: TAB_CHARACTER }],
    ['Occupations', TAB_JOBS, { preference: 'job', task: 'menu' }],
    quirksEnabled && ['Quirks', TAB_QUIRKS,
      { preference: 'trait', task: 'menu' }],
    ['Loadout', TAB_LOADOUT, { preference: 'tab', tab: TAB_LOADOUT }],
    ['Game', TAB_GAME, { preference: 'tab', tab: TAB_GAME }],
    ['OOC', TAB_OOC, { preference: 'tab', tab: TAB_OOC }],
    ['Keybindings', TAB_KEYS, { preference: 'tab', tab: TAB_KEYS }],
  ].filter(Boolean);
  return (
    <div className="Preferences">
      <div className="Preferences__left">
        <Box bold textAlign="center" mb={1}>{name}</Box>
        <ByondUi
          className="Preferences__preview"
          params={{
            id: previewMap,
            parent: config.window,
            type: 'map',
            'background-color': '#1a1a1a',
          }} />
        <Box textAlign="center" mt={1}>
          <Button
            icon="undo"
            tooltip="Turn left"
            onClick={() => act('turn', { way: 'left' })} />
          <Button
            icon="redo"
            tooltip="Turn right"
            onClick={() => act('turn', { way: 'right' })} />
        </Box>
        {slots.length > 0 && (
          <Section title="Characters" mt={1}>
            {slots.map(each => (
              <Button
                key={each.num}
                fluid
                ellipsis
                selected={each.num === slot}
                content={each.name}
                onClick={() => act('link', {
                  preference: 'changeslot',
                  num: each.num,
                })} />
            ))}
          </Section>
        )}
        {!!noAccount && (
          <NoticeBox>Log in with a BYOND account to save.</NoticeBox>
        )}
        <Box mt={1}>
          {!guest && (
            <Fragment>
              <Button
                fluid
                icon="save"
                color="good"
                content="Save setup"
                onClick={() => act('link', { preference: 'save' })} />
              <Button
                fluid
                icon="undo"
                content="Undo changes"
                onClick={() => act('link', { preference: 'load' })} />
            </Fragment>
          )}
        </Box>
      </div>
      <div className="Preferences__right">
        <Tabs activeTab={'tab' + tab}>
          {tabs.map(each => (
            <Tabs.Tab
              key={'tab' + each[1]}
              label={each[0]}
              onClick={() => act('link', each[2])} />
          ))}
        </Tabs>
        <div className="Preferences__content">
          {tab === TAB_CHARACTER && quirksEnabled && (
            <Box mb={1} color="label">
              Quirks: {quirks.length ? quirks.join(', ') : 'none'}
            </Box>
          )}
          {(tab === TAB_CHARACTER || tab === TAB_GAME || tab === TAB_OOC)
            && <Sections act={act} sections={data.sections} />}
          {tab === TAB_JOBS && <Jobs act={act} jobs={data.jobs} />}
          {tab === TAB_QUIRKS && (
            <Quirks act={act} quirkList={data.quirkList} />
          )}
          {tab === TAB_KEYS && (
            <Keybinds act={act} keybinds={data.keybinds} />
          )}
          {tab === TAB_LOADOUT && (
            <Loadout act={act} loadout={data.loadout} />
          )}
        </div>
      </div>
    </div>
  );
};
