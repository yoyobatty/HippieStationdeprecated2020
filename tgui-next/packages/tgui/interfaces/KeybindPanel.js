import { Component, Fragment } from 'inferno';
import { useBackend } from '../backend';
import { Box, Button, Icon, Input, Table } from '../components';

// The keybind panel (hippiestation/code/modules/keybindings/
// keybind_panel.dm): in Character Setup's Keybindings tab and in the
// Keybindings window. Click a key and press the new one, right here; Escape
// clears it. A modifier on its own counts when it's let go, since it may be
// the start of a combination; anything else counts the moment it's pressed,
// with whatever is held then.

const MODIFIERS = ['Alt', 'Control', 'Shift', 'AltGraph'];

const matches = (search, section, bind) => {
  if (!search) {
    return true;
  }
  const s = search.toLowerCase();
  return bind.name.toLowerCase().includes(s)
    || section.name.toLowerCase().includes(s)
    || bind.keys.some(k => k.label.toLowerCase().includes(s));
};

export class KeybindPanel extends Component {
  constructor(props) {
    super(props);
    this.state = {
      capture: null, // { id, old }: the slot waiting for a key
      search: '',
      collapsed: {},
      resetArmed: false,
    };
    this.onKeyDown = this.onKeyDown.bind(this);
    this.onKeyUp = this.onKeyUp.bind(this);
  }

  // On the window, capturing: ahead of the passthrough to the game
  // (hotkeys.js), which leaves a key alone once it's been handled
  componentDidMount() {
    window.addEventListener('keydown', this.onKeyDown, true);
    window.addEventListener('keyup', this.onKeyUp, true);
  }

  componentWillUnmount() {
    window.removeEventListener('keydown', this.onKeyDown, true);
    window.removeEventListener('keyup', this.onKeyUp, true);
  }

  send(e) {
    const { capture } = this.state;
    this.setState({ capture: null });
    this.props.act('kb_capture', {
      id: capture.id,
      old: capture.old || '',
      clear: e.key === 'Escape' ? 1 : 0,
      key: e.key,
      code: e.code || '',
      alt: e.altKey ? 1 : 0,
      ctrl: e.ctrlKey ? 1 : 0,
      shift: e.shiftKey ? 1 : 0,
    });
  }

  onKeyDown(e) {
    if (!this.state.capture) {
      return;
    }
    e.preventDefault();
    e.stopPropagation();
    if (!e.repeat && !MODIFIERS.includes(e.key)) {
      this.send(e);
    }
  }

  onKeyUp(e) {
    if (!this.state.capture) {
      return;
    }
    e.preventDefault();
    e.stopPropagation();
    if (MODIFIERS.includes(e.key)) {
      this.send(e);
    }
  }

  toggleCapture(id, old) {
    const { capture } = this.state;
    if (capture && capture.id === id && capture.old === old) {
      this.setState({ capture: null });
      return;
    }
    this.setState({ capture: { id, old } });
  }

  isCapturing(id, old) {
    const { capture } = this.state;
    return !!capture && capture.id === id && capture.old === old;
  }

  renderRow(bind, maxKeys, pending) {
    const { act } = this.props;
    const addingHere = this.isCapturing(bind.id, null);
    const capturingHere = !!this.state.capture
      && this.state.capture.id === bind.id;
    return (
      <Fragment key={bind.id}>
        <Table.Row className="candystripe">
          <Table.Cell style={{ padding: '2px 6px' }}>
            {bind.name}
          </Table.Cell>
          <Table.Cell collapsing style={{ padding: '2px 0' }}>
            {bind.keys.map(k => {
              const here = this.isCapturing(bind.id, k.key);
              const clash = k.clashes.length > 0;
              return (
                <Button
                  key={k.key}
                  minWidth="56px"
                  textAlign="center"
                  selected={here}
                  color={!here && clash ? 'bad' : null}
                  tooltip={!here && clash
                    ? 'Also: ' + k.clashes.join(', ')
                    : null}
                  tooltipPosition="left"
                  content={here ? 'Press a key' : k.label}
                  onClick={() => this.toggleCapture(bind.id, k.key)} />
              );
            })}
            {bind.keys.length < maxKeys && (
              <Button
                minWidth={addingHere ? '56px' : null}
                textAlign="center"
                color={addingHere ? null : 'transparent'}
                selected={addingHere}
                icon={addingHere ? null : 'plus'}
                content={addingHere ? 'Press a key' : null}
                onClick={() => this.toggleCapture(bind.id, null)} />
            )}
          </Table.Cell>
          <Table.Cell
            collapsing
            textAlign="right"
            style={{ padding: '2px 6px 2px 4px' }}>
            {capturingHere && (
              <Box inline color="label" mr={1}>Esc: clear</Box>
            )}
            {!bind.isDefault && (
              <Button
                icon="undo"
                color="transparent"
                tooltip={'Default: ' + (bind.defaults || 'none')}
                tooltipPosition="left"
                onClick={() => act('kb_reset', { id: bind.id })} />
            )}
          </Table.Cell>
        </Table.Row>
        {!!pending && pending.id === bind.id && (
          <Table.Row>
            <Table.Cell colSpan={3} style={{ padding: '4px 6px' }}>
              <Box inline color="average" mr={1}>
                <Icon name="exclamation-triangle" mr={1} />
                {pending.label} is {pending.others.join(', ')}.
              </Box>
              <Button
                content="Move here"
                onClick={() => act('kb_resolve', { choice: 'move' })} />
              <Button
                content="Keep both"
                onClick={() => act('kb_resolve', { choice: 'keep' })} />
              <Button
                content="Cancel"
                onClick={() => act('kb_resolve', { choice: 'cancel' })} />
            </Table.Cell>
          </Table.Row>
        )}
      </Fragment>
    );
  }

  render() {
    const { act, data } = this.props;
    if (!data) {
      return null;
    }
    const { hotkeys, sections = [], maxKeys = 3, pending } = data;
    const { search, collapsed, resetArmed } = this.state;
    return (
      <Box className="KeybindPanel">
        <Box mb={1}>
          <Box inline color="label" mr={1}>Mode</Box>
          <Button
            selected={!!hotkeys}
            content="Hotkey"
            onClick={() => act('kb_mode', { mode: 'hotkey' })} />
          <Button
            selected={!hotkeys}
            content="Classic"
            onClick={() => act('kb_mode', { mode: 'classic' })} />
          <Input
            ml={1}
            width="160px"
            placeholder="Search"
            value={search}
            onInput={(e, value) => this.setState({ search: value })} />
          <Button
            ml={1}
            icon="undo"
            color={resetArmed ? 'bad' : null}
            content={resetArmed ? 'Reset all?' : 'Reset all'}
            onClick={() => {
              if (!resetArmed) {
                this.setState({ resetArmed: true });
                return;
              }
              this.setState({ resetArmed: false });
              act('kb_reset_all');
            }} />
        </Box>
        <Table>
          {sections.map(section => {
            const binds = section.binds.filter(bind => (
              matches(search, section, bind)
            ));
            if (!binds.length) {
              return null;
            }
            const open = !!search || !collapsed[section.name];
            return (
              <Fragment key={section.name}>
                <Table.Row>
                  <Table.Cell colSpan={3} style={{ padding: '4px 0 2px' }}>
                    <Button
                      fluid
                      icon={open ? 'chevron-down' : 'chevron-right'}
                      content={section.name}
                      onClick={() => this.setState({
                        collapsed: {
                          ...collapsed,
                          [section.name]: !collapsed[section.name],
                        },
                      })} />
                  </Table.Cell>
                </Table.Row>
                {open && binds.map(bind => (
                  this.renderRow(bind, maxKeys, pending)
                ))}
              </Fragment>
            );
          })}
        </Table>
      </Box>
    );
  }
}

// The Keybindings window (the verb, OOC tab)
export const Keybindings = props => {
  const { act, data } = useBackend(props);
  return <KeybindPanel act={act} data={data} />;
};
