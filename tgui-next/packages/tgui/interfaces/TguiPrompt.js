import { decodeHtmlEntities } from 'common/string';
import { Component, createRef } from 'inferno';
import { useBackend } from '../backend';
import { winset } from '../byond';
import { Box, Button, Flex, Section } from '../components';

// tgui stand-ins for BYOND's input() and alert(), opened by
// hippiestation/code/modules/tgui/tgui_prompt.dm. One window, four kinds:
// alert (buttons), list (searchable pick list), text/message, num.

const ROW_HEIGHT = 22;
const KEY_ENTER = 13;
const KEY_ESCAPE = 27;
const KEY_PAGEUP = 33;
const KEY_PAGEDOWN = 34;
const KEY_END = 35;
const KEY_HOME = 36;
const KEY_LEFT = 37;
const KEY_UP = 38;
const KEY_RIGHT = 39;
const KEY_DOWN = 40;

const Message = props => {
  const { text } = props;
  if (!text) {
    return null;
  }
  return (
    <Box mb={1} style={{ 'white-space': 'pre-wrap' }}>
      {decodeHtmlEntities(text)}
    </Box>
  );
};

const TimeLeft = props => {
  const { seconds } = props;
  if (seconds === null || seconds === undefined) {
    return null;
  }
  return (
    <Box inline color="label" mr={1}>
      {seconds}s
    </Box>
  );
};

export class TguiPrompt extends Component {
  constructor(props) {
    super(props);
    const { data } = useBackend(props);
    const choices = data.choices || [];
    const start = data.default_index ? data.default_index - 1 : 0;
    const hasDefault = data.default_value !== null
      && data.default_value !== undefined;
    this.state = {
      search: '',
      selected: Math.max(0, Math.min(start, choices.length - 1)),
      scrollTop: 0,
      value: hasDefault ? String(data.default_value) : '',
      sent: false,
    };
    this.fieldRef = createRef();
    this.listRef = createRef();
    this.onKey = e => this.handleKey(e);
    this.onWindowFocus = () => this.focusField(false);
  }

  componentDidMount() {
    window.addEventListener('keydown', this.onKey, true);
    window.addEventListener('focus', this.onWindowFocus);
    // Take the keyboard the way native input() does: the window first
    // (from here, so the page is surely loaded), then the field, after
    // Layout's own mount has put the focus on the page body.
    const { config } = useBackend(this.props);
    if (config && config.window) {
      winset(config.window, 'focus', true);
    }
    this.focusTimer = setTimeout(() => this.focusField(true), 0);
    this.scrollToSelected();
  }

  componentWillUnmount() {
    window.removeEventListener('keydown', this.onKey, true);
    window.removeEventListener('focus', this.onWindowFocus);
    clearTimeout(this.focusTimer);
  }

  focusField(select) {
    const field = this.fieldRef.current;
    if (!field || document.activeElement === field) {
      return;
    }
    field.focus();
    if (select && field.select) {
      field.select();
    }
  }

  getData() {
    return useBackend(this.props).data;
  }

  // The rows a list shows: [index into choices, text], filtered by search.
  getRows() {
    const data = this.getData();
    const choices = data.choices || [];
    const search = this.state.search.trim().toLowerCase();
    const rows = [];
    for (let i = 0; i < choices.length; i++) {
      const text = decodeHtmlEntities(String(choices[i]));
      if (!search || text.toLowerCase().includes(search)) {
        rows.push([i, text]);
      }
    }
    return rows;
  }

  send(action, params = {}) {
    if (this.state.sent) {
      return;
    }
    this.setState({ sent: true });
    useBackend(this.props).act(action, params);
  }

  cancel() {
    this.send('cancel');
  }

  submitList() {
    const rows = this.getRows();
    const row = rows[this.state.selected];
    if (row) {
      this.send('submit', { index: row[0] + 1 });
    }
  }

  submitValue() {
    const data = this.getData();
    const value = this.state.value;
    if (data.kind === 'num') {
      const n = parseFloat(value);
      if (isNaN(n)) {
        return;
      }
      this.send('submit', { value: String(n) });
      return;
    }
    this.send('submit', { value });
  }

  moveSelection(delta, absolute) {
    const rows = this.getRows();
    if (!rows.length) {
      return;
    }
    const last = rows.length - 1;
    this.setState(prev => {
      const next = absolute !== undefined
        ? absolute
        : prev.selected + delta;
      return { selected: Math.max(0, Math.min(last, next)) };
    }, () => this.scrollToSelected());
  }

  scrollToSelected() {
    const list = this.listRef.current;
    if (!list) {
      return;
    }
    const top = this.state.selected * ROW_HEIGHT;
    if (top < list.scrollTop) {
      list.scrollTop = top;
    }
    else if (top + ROW_HEIGHT > list.scrollTop + list.clientHeight) {
      list.scrollTop = top + ROW_HEIGHT - list.clientHeight;
    }
    this.setState({ scrollTop: list.scrollTop });
  }

  handleKey(e) {
    const data = this.getData();
    const kind = data.kind;
    const key = e.keyCode;
    const stop = () => {
      e.preventDefault();
      e.stopPropagation();
    };
    if (key === KEY_ESCAPE) {
      stop();
      // Alerts and pick lists without Cancel need an answer, as natively
      if (data.allow_cancel) {
        this.cancel();
      }
      return;
    }
    if (kind === 'alert') {
      const count = (data.choices || []).length;
      if (key === KEY_LEFT || key === KEY_RIGHT) {
        stop();
        const step = key === KEY_LEFT ? -1 : 1;
        this.setState(prev => ({
          selected: (prev.selected + step + count) % count,
        }));
        return;
      }
      if (key === KEY_ENTER) {
        stop();
        this.send('submit', { index: this.state.selected + 1 });
        return;
      }
      // 1-9 press the matching button
      if (key >= 49 && key <= 57 && key - 48 <= count) {
        stop();
        this.send('submit', { index: key - 48 });
      }
      return;
    }
    if (kind === 'list') {
      const page = Math.max(1, Math.floor(
        ((this.listRef.current && this.listRef.current.clientHeight)
          || 200) / ROW_HEIGHT) - 1);
      const moves = {
        [KEY_UP]: [-1],
        [KEY_DOWN]: [1],
        [KEY_PAGEUP]: [-page],
        [KEY_PAGEDOWN]: [page],
      };
      if (moves[key]) {
        stop();
        this.moveSelection(moves[key][0]);
        return;
      }
      if ((key === KEY_HOME || key === KEY_END) && e.ctrlKey) {
        stop();
        this.moveSelection(0, key === KEY_HOME ? 0 : 1e9);
        return;
      }
      if (key === KEY_ENTER) {
        stop();
        this.submitList();
      }
      return;
    }
    if (key === KEY_ENTER) {
      // A message box takes newlines; Ctrl+Enter sends it.
      if (kind === 'message' && !e.ctrlKey) {
        return;
      }
      stop();
      this.submitValue();
    }
  }

  renderButtons(okLabel, onOk, okDisabled) {
    const data = this.getData();
    return (
      <Flex mt={1} align="center">
        <Flex.Item grow={1}>
          <TimeLeft seconds={data.time_left} />
        </Flex.Item>
        <Flex.Item>
          <Button
            content={okLabel}
            color="good"
            disabled={okDisabled}
            onClick={onOk} />
          {!!data.allow_cancel && (
            <Button
              content="Cancel"
              onClick={() => this.cancel()} />
          )}
        </Flex.Item>
      </Flex>
    );
  }

  renderAlert() {
    const data = this.getData();
    const choices = data.choices || [];
    return (
      <Section>
        <Message text={data.message} />
        <Flex mt={1} align="center" wrap="wrap">
          <Flex.Item grow={1}>
            <TimeLeft seconds={data.time_left} />
          </Flex.Item>
          {choices.map((choice, i) => (
            <Flex.Item key={i} ml={1}>
              <Button
                content={decodeHtmlEntities(String(choice))}
                selected={i === this.state.selected}
                onClick={() => this.send('submit', { index: i + 1 })} />
            </Flex.Item>
          ))}
        </Flex>
      </Section>
    );
  }

  renderList() {
    const data = this.getData();
    const rows = this.getRows();
    const selected = Math.min(this.state.selected, rows.length - 1);
    const listHeight = 260;
    const first = Math.max(0,
      Math.floor(this.state.scrollTop / ROW_HEIGHT) - 5);
    const last = Math.min(rows.length,
      first + Math.ceil(listHeight / ROW_HEIGHT) + 10);
    const shown = rows.slice(first, last);
    return (
      <Section>
        <Message text={data.message} />
        <input
          ref={this.fieldRef}
          className="TguiPrompt__field"
          placeholder={'Search ' + (data.choices || []).length + '...'}
          value={this.state.search}
          onInput={e => this.setState({
            search: e.target.value,
            selected: 0,
            scrollTop: 0,
          }, () => {
            if (this.listRef.current) {
              this.listRef.current.scrollTop = 0;
            }
          })} />
        <div
          ref={this.listRef}
          className="TguiPrompt__list"
          style={{ height: listHeight + 'px' }}
          onScroll={e => this.setState({ scrollTop: e.target.scrollTop })}>
          <div
            style={{
              position: 'relative',
              height: (rows.length * ROW_HEIGHT) + 'px',
            }}>
            {shown.map((row, n) => {
              const at = first + n;
              return (
                <div
                  key={row[0]}
                  className={'TguiPrompt__row'
                    + (at === selected ? ' TguiPrompt__row--selected' : '')}
                  style={{
                    top: (at * ROW_HEIGHT) + 'px',
                    height: ROW_HEIGHT + 'px',
                    'line-height': ROW_HEIGHT + 'px',
                  }}
                  onClick={() => this.setState({ selected: at })}
                  onDblClick={() => this.send('submit',
                    { index: row[0] + 1 })}>
                  {row[1]}
                </div>
              );
            })}
          </div>
        </div>
        {rows.length === 0 && (
          <Box color="label" mt={1}>No matches.</Box>
        )}
        {this.renderButtons('Select', () => this.submitList(),
          rows.length === 0)}
      </Section>
    );
  }

  renderField() {
    const data = this.getData();
    const kind = data.kind;
    const value = this.state.value;
    const maxLength = data.max_length || undefined;
    let invalid = false;
    let hint = null;
    if (kind === 'num') {
      const n = parseFloat(value);
      invalid = isNaN(n);
      const bounds = [];
      if (data.min_value !== null && data.min_value !== undefined) {
        bounds.push('min ' + data.min_value);
      }
      if (data.max_value !== null && data.max_value !== undefined) {
        bounds.push('max ' + data.max_value);
      }
      hint = bounds.join(', ');
    }
    else if (maxLength) {
      hint = value.length + '/' + maxLength;
    }
    const onInput = e => this.setState({ value: e.target.value });
    return (
      <Section>
        <Message text={data.message} />
        {kind === 'message' ? (
          <textarea
            ref={this.fieldRef}
            className="TguiPrompt__field TguiPrompt__field--area"
            maxLength={maxLength}
            value={value}
            onInput={onInput} />
        ) : (
          <input
            ref={this.fieldRef}
            className={'TguiPrompt__field'
              + (invalid && value !== '' ? ' TguiPrompt__field--bad' : '')}
            maxLength={maxLength}
            value={value}
            onInput={onInput} />
        )}
        {!!hint && (
          <Box color="label" textAlign="right" fontSize="11px">
            {hint}
          </Box>
        )}
        {this.renderButtons(
          kind === 'message' ? 'Send (Ctrl+Enter)' : 'Ok',
          () => this.submitValue(),
          kind === 'num' && invalid)}
      </Section>
    );
  }

  render() {
    const data = this.getData();
    switch (data.kind) {
      case 'alert':
        return this.renderAlert();
      case 'list':
        return this.renderList();
      default:
        return this.renderField();
    }
  }
}
