// hippie -- sandbox mode's windows (sandbox_tgui.dm): the Sandbox Panel and
// the airlock maker.
import { decodeHtmlEntities } from 'common/string';
import { Component, Fragment } from 'inferno';
import { useBackend } from '../backend';
import { Box, Button, Icon, Input, NoticeBox, Section, Tabs } from '../components';

const text = value => decodeHtmlEntities(String(value || ''));

const KINDS = [
  ['cloth', 'Clothes'],
  ['reag', 'Reagent containers'],
  ['obj', 'Other items'],
];

export class SandboxPanel extends Component {
  constructor(props) {
    super(props);
    this.state = { query: '' };
  }

  render() {
    const { act, data } = useBackend(this.props);
    const search = (kind, query) => act('search', { kind, query });
    return (
      <Fragment>
        {!data.spawning && (
          <NoticeBox>An admin turned item spawning off.</NoticeBox>
        )}
        {!!data.admin && (
          <Box mb={1}>
            <Button icon={data.spawning ? 'toggle-on' : 'toggle-off'}
              content={'Item spawning ' + (data.spawning ? 'on' : 'off')}
              selected={!!data.spawning}
              onClick={() => act('toggle_spawning')} />
          </Box>
        )}
        {(data.sections || []).map(section => (
          <Section key={section.name} title={section.name}>
            {section.buttons.map(label => (
              <Button key={label} content={label}
                className="Sandbox__button"
                onClick={() => act('button', {
                  section: section.name,
                  label,
                })} />
            ))}
          </Section>
        ))}
        <Section title="Find an item">
          <Tabs>
            {KINDS.map(([kind, label]) => (
              <Tabs.Tab key={kind} label={label}
                selected={data.search_kind === kind}
                onClick={() => search(kind, this.state.query)} />
            ))}
          </Tabs>
          <Input fluid placeholder="Type at least two letters..."
            value={this.state.query}
            onInput={(e, value) => this.setState({ query: value })}
            onChange={(e, value) => search(data.search_kind, value)} />
          <Box className="Sandbox__results">
            {(data.results || []).map(r => (
              <Box key={r.path} className="Sandbox__item"
                title={r.path}
                onClick={() => act('spawn_item', { path: r.path })}>
                {r.icon ? (
                  <img className="Sandbox__pic" src={r.icon}
                    onError={e => {
                      e.target.style.visibility = 'hidden';
                    }} />
                ) : <Icon name="cube" className="Sandbox__pic" />}
                <Box className="Sandbox__itemName">{text(r.name)}</Box>
              </Box>
            ))}
          </Box>
          {!!data.search_query && (data.results || []).length === 0 && (
            <Box color="label">Nothing found.</Box>
          )}
        </Section>
      </Fragment>
    );
  }
}

const PAINT_COLORS = {
  none: '#8a93a3',
  engineering: '#d6b23c',
  atmos: '#3ca6d6',
  security: '#c43b3b',
  command: '#3b6fc4',
  medical: '#e8e8e8',
  research: '#9b59b6',
  mining: '#a0743c',
  maintenance: '#6b6b6b',
  external: '#c45f3b',
  highsecurity: '#444',
};

export const AirlockMaker = props => {
  const { act, data } = useBackend(props);
  const access = data.access || [];
  const accessTitle = 'Access (' + (access.length
    ? access.length + ', ' + (data.require_all ? 'all' : 'any one')
    : 'anyone can open it') + ')';
  const accessButton = (
    <Button content={data.require_all ? 'Needs all' : 'Needs any one'}
      onClick={() => act('reqall')} />
  );
  return (
    <Fragment>
      <Box className="Sandbox__hint">
        Move the model airlock where you want it, then Build.
      </Box>
      <Section title="Door">
        <Box className="Sandbox__row">
          <Box className="Sandbox__label">Name</Box>
          <Input value={text(data.name)} width="220px"
            onChange={(e, value) => act('rename', { name: value })} />
        </Box>
        <Box className="Sandbox__row">
          <Box className="Sandbox__label">Paint</Box>
          <Box>
            {(data.paints || []).map(paint => (
              <Button key={paint} selected={data.paint === paint}
                onClick={() => act('paint', { paint })}>
                <span className="Sandbox__swatch"
                  style={{ background: PAINT_COLORS[paint] }} />
                {paint}
              </Button>
            ))}
          </Box>
        </Box>
        <Box className="Sandbox__row">
          <Box className="Sandbox__label">Glass</Box>
          <Button icon={data.glass ? 'toggle-on' : 'toggle-off'}
            content={data.glass ? 'Yes' : 'No'} selected={!!data.glass}
            onClick={() => act('glass')} />
        </Box>
      </Section>
      <Section title={accessTitle} buttons={accessButton}>
        {(data.regions || []).map(region => (
          <Box key={region.name} className="Sandbox__region">
            <Box className="Sandbox__regionName">{region.name}</Box>
            {region.accesses.map(a => (
              <Button key={a.id} content={a.name}
                selected={access.includes(a.id)}
                onClick={() => act('access', { id: a.id })} />
            ))}
          </Box>
        ))}
      </Section>
      <Box className="Sandbox__row">
        <Button icon="hammer" content="Build" color="good"
          onClick={() => act('done')} />
        <Button icon="trash" content="Cancel" color="bad"
          onClick={() => act('cancel')} />
      </Box>
    </Fragment>
  );
};
