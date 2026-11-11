import { Component, Fragment } from 'inferno';
import { useBackend } from '../backend';
import { Box, Button, Icon, NoticeBox, Section } from '../components';

// hippie -- folders, clipboards, filing cabinets and notice boards
// (hippiestation/code/modules/paperwork/paperwork_tgui.dm)

const ICONS = {
  paper: 'file-alt',
  photo: 'image',
  documents: 'folder',
  folder: 'folder-open',
};

const TITLES = {
  folder: 'In the folder',
  clipboard: 'On the clipboard',
  cabinet: 'In the drawers',
  noticeboard: 'Pinned up',
};

const ROW = {
  'display': 'flex',
  'align-items': 'center',
  'padding': '3px 2px',
};

const BADGE = {
  'background-color': '#40628a',
  'color': '#ffffff',
  'border-radius': '8px',
  'padding': '0 6px',
  'font-size': '11px',
};

const SEARCH = {
  'background-color': 'rgba(0, 0, 0, 0.4)',
  'color': '#ffffff',
  'border': '1px solid #404b6e',
  'padding': '3px',
  'box-sizing': 'border-box',
  'width': '100%',
};

class PaperListWindow extends Component {
  constructor() {
    super();
    this.state = { search: '' };
  }

  render() {
    const { act, data } = useBackend(this.props);
    const kind = data.kind;
    const all = data.items || [];
    const search = this.state.search.trim().toLowerCase();
    const items = search
      ? all.filter(item => item.name.toLowerCase().includes(search))
      : all;
    let title = TITLES[kind] + ' (' + all.length + ')';
    if (kind === 'noticeboard') {
      title = TITLES[kind] + ' (' + all.length + ' of ' + data.slots + ')';
    }
    return (
      <Fragment>
        {kind === 'clipboard' && (
          <Section title="Pen">
            {!!data.pen && (
              <Box style={ROW}>
                <Icon name="pen" mr={1} />
                <Box style={{ 'flex-grow': 1 }}>{data.pen}</Box>
                <Button
                  icon="hand-paper"
                  content="Take it"
                  onClick={() => act('pen_out')} />
              </Box>
            )}
            {!data.pen && (
              <Box style={ROW}>
                <Box color="label" style={{ 'flex-grow': 1 }}>
                  No pen clipped in.
                </Box>
                <Button
                  icon="pen"
                  content="Clip pen"
                  disabled={!data.holding_pen}
                  onClick={() => act('pen_in')} />
              </Box>
            )}
          </Section>
        )}
        <Section title={title}>
          {!!data.locked && (
            <NoticeBox>
              Access required.
            </NoticeBox>
          )}
          {kind === 'cabinet' && all.length > 6 && (
            <Box mb={1}>
              <input
                value={this.state.search}
                placeholder="Search the drawers..."
                onInput={e => this.setState({ search: e.target.value })}
                style={SEARCH} />
            </Box>
          )}
          {all.length === 0 && <Box color="label">Nothing in it.</Box>}
          {all.length > 0 && items.length === 0 && (
            <Box color="label">Nothing by that name.</Box>
          )}
          {items.map(item => (
            <Box key={item.ref} className="candystripe" style={ROW}>
              <Icon name={ICONS[item.kind]} mr={1} />
              <Box style={{ 'flex-grow': 1 }}>
                {item.name}
                {!!item.top && <Box inline ml={1} style={BADGE}>on top</Box>}
              </Box>
              {!!data.can_read && (
                <Button
                  icon="eye"
                  content="Read"
                  onClick={() => act('read', { ref: item.ref })} />
              )}
              {!!data.can_write && item.kind === 'paper' && (
                <Button
                  icon="pen-nib"
                  content="Write"
                  onClick={() => act('write', { ref: item.ref })} />
              )}
              {kind === 'clipboard' && !item.top && (
                <Button
                  icon="arrow-up"
                  tooltip="Move to the top"
                  tooltipPosition="left"
                  onClick={() => act('top', { ref: item.ref })} />
              )}
              {!!data.can_take && (
                <Button
                  icon="hand-paper"
                  content="Take out"
                  onClick={() => act('take', { ref: item.ref })} />
              )}
            </Box>
          ))}
        </Section>
      </Fragment>
    );
  }
}

export const PaperList = props => (
  <PaperListWindow state={props.state} dispatch={props.dispatch} />
);
