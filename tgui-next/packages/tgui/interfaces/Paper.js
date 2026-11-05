import { Component, Fragment } from 'inferno';
import { useBackend } from '../backend';
import { Box, Button, Collapsible, LabeledList, Section } from '../components';

// hippie -- a sheet of paper, to read and write on
// (hippiestation/code/modules/paperwork/paperwork_tgui.dm)

const PAGE = {
  'background-color': '#f7f4ea',
  'color': '#000000',
  'padding': '18px 22px',
  'font-family': 'Verdana, sans-serif',
  'font-size': '13px',
  'min-height': '260px',
  'box-shadow': '0 2px 6px rgba(0, 0, 0, 0.7)',
  'word-wrap': 'break-word',
  'border-radius': '2px',
};

const FIELD = {
  'background-color': 'rgba(0, 0, 0, 0.4)',
  'color': '#ffffff',
  'border': '1px solid #404b6e',
  'padding': '4px',
  'box-sizing': 'border-box',
  'width': '100%',
};

const HELP = [
  ['# text', 'a heading'],
  ['|text|', 'centred'],
  ['**text**', 'bold'],
  ['*text*', 'italic'],
  ['^text^', 'bigger'],
  ['%s', 'your signature'],
  ['%f', 'a field to fill in later, as on a form'],
  ['((text))', 'smaller (pens only)'],
  ['* item', 'a bulleted list (pens only)'],
  ['---', 'a line across (pens only)'],
  ['\\', 'before any of these, to write it as it is'],
];

// The page and its stamps are HTML: what's typed is escaped before pen code
// becomes tags (paper.dm parsepencode()), and the stamps are the paper
// spritesheet's own tags, as in the old window, which showed the same HTML.
const Html = props => (
  // eslint-disable-next-line react/no-danger
  <div {...props} dangerouslySetInnerHTML={{ __html: props.html }} />
);

const pageStyle = chosen => {
  let css = '.Paper__page .paper_field[data-field] {'
    + ' display: inline-block; min-width: 4em;'
    + ' border-bottom: 1px dashed #8a8a8a; }'
    + '.Paper__page--writing .paper_field[data-field] {'
    + ' cursor: pointer; background-color: rgba(64, 128, 255, 0.10); }'
    + '.Paper__page--writing .paper_field[data-field]:hover {'
    + ' background-color: rgba(64, 128, 255, 0.25); }'
    + '.Paper__page a { pointer-events: none; color: inherit; }'
    + '.Paper__stamps span { display: inline-block; margin: 2px; }';
  if (chosen) {
    css += '.Paper__page .paper_field[data-field="' + chosen + '"] {'
      + ' background-color: rgba(255, 196, 0, 0.45); }';
  }
  return css;
};

class PaperWindow extends Component {
  constructor() {
    super();
    this.state = { text: '', field: '', label: '' };
  }

  render() {
    const { act, data } = useBackend(this.props);
    const fields = [];
    for (let i = 1; i <= data.fields; i++) {
      fields.push(String(i));
    }
    const chosen = data.writing ? this.state.field : '';
    const pickField = e => {
      if (!data.writing) {
        return;
      }
      let node = e.target;
      while (node && node !== e.currentTarget) {
        const field = node.getAttribute && node.getAttribute('data-field');
        if (field) {
          this.setState({ field: field });
          return;
        }
        node = node.parentNode;
      }
    };
    const write = () => {
      if (!this.state.text) {
        return;
      }
      act('write', { text: this.state.text, field: this.state.field });
      this.setState({ text: '' });
    };
    return (
      <Fragment>
        <style>{pageStyle(chosen)}</style>
        <div
          className={'Paper__page'
            + (data.writing ? ' Paper__page--writing' : '')}
          style={PAGE}
          onClick={pickField}>
          <Html html={data.text || ''} />
          {!data.text && (
            <Box color="#999999" italic>
              Blank.
            </Box>
          )}
          {!!data.stamps && (
            <Html
              className="Paper__stamps"
              style={{ 'margin-top': '16px' }}
              html={data.stamps} />
          )}
        </div>
        {!!data.writing && (
          <Section
            mt={1}
            title={'Writing with ' + data.with}>
            <Box mb={1}>
              <Box inline color="label" mr={1}>Where:</Box>
              <Button
                content="At the end"
                selected={!this.state.field}
                onClick={() => this.setState({ field: '' })} />
              {fields.map(field => (
                <Button
                  key={field}
                  content={'Field ' + field}
                  selected={this.state.field === field}
                  onClick={() => this.setState({ field: field })} />
              ))}
              {fields.length > 0 && (
                <Box color="label" fontSize="11px" mt={0.5}>
                  Or click a field on the page.
                </Box>
              )}
            </Box>
            <textarea
              value={this.state.text}
              rows={6}
              placeholder="What to write..."
              onInput={e => this.setState({ text: e.target.value })}
              style={Object.assign({ 'resize': 'vertical' }, FIELD)} />
            <Box mt={0.5}>
              <Button
                icon="pen-nib"
                content="Write it"
                disabled={!this.state.text}
                onClick={write} />
              <Button
                icon="eraser"
                content="Clear"
                disabled={!this.state.text}
                onClick={() => this.setState({ text: '' })} />
            </Box>
            <Collapsible mt={1} title="Pen code">
              <LabeledList>
                {HELP.map(row => (
                  <LabeledList.Item key={row[0]} label={row[0]}>
                    {row[1]}
                  </LabeledList.Item>
                ))}
              </LabeledList>
              {!!data.crayon && (
                <Box mt={0.5} color="average">
                  A crayon writes big and bold, and only the first six.
                </Box>
              )}
            </Collapsible>
          </Section>
        )}
        {!!data.in_hand && (
          <Section mt={1}>
            <Box style={{ 'display': 'flex', 'align-items': 'center' }}>
              <Box color="label" mr={1}>Label</Box>
              <input
                value={this.state.label}
                placeholder={data.name}
                maxLength={42}
                onInput={e => this.setState({ label: e.target.value })}
                style={FIELD} />
              <Button
                ml={0.5}
                content="Set"
                disabled={!this.state.label}
                onClick={() => {
                  act('rename', { name: this.state.label });
                  this.setState({ label: '' });
                }} />
            </Box>
          </Section>
        )}
      </Fragment>
    );
  }
}

export const Paper = props => (
  <PaperWindow state={props.state} dispatch={props.dispatch} />
);
