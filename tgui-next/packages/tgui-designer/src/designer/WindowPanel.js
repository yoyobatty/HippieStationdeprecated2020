/**
 * The window's own settings (name, key, title, size, theme) and where its
 * DM goes (type, file, UI state).
 */

import { Component } from 'inferno';
import { dmFileFor, toSnake } from '../shared/model';
import { THEMES, UI_STATES } from '../shared/registry';
import { api } from './api';
import { NumberBox, Row, Select } from './editors';

export class WindowPanel extends Component {
  constructor(props) {
    super(props);
    this.state = {
      check: null,
      typeExists: null,
      types: [],
    };
    this.timer = null;
    this.lastChecked = null;
  }

  componentDidMount() {
    this.scheduleCheck();
  }

  componentDidUpdate() {
    this.scheduleCheck();
  }

  componentWillUnmount() {
    clearTimeout(this.timer);
  }

  scheduleCheck() {
    const { design } = this.props.app.state;
    const key = design.name + '|' + design.route + '|' + design.dm.type;
    if (key === this.lastChecked) {
      return;
    }
    this.lastChecked = key;
    clearTimeout(this.timer);
    this.timer = setTimeout(async () => {
      const check = await api.check(design.name, design.route);
      const type = await api.typeExists(design.dm.type);
      this.setState({
        check: check.error ? null : check,
        typeExists: type.error ? null : type.exists,
      });
    }, 400);
  }

  render() {
    const { app } = this.props;
    const { design } = app.state;
    const { check, typeExists } = this.state;
    const set = (fn, key) => app.change(fn, 'window:' + key);
    const dm = design.dm;
    return (
      <div className="insp">
        <div className="insp__section">
          <div className="insp__sub">Window</div>
          <Row label="Name" title="The interface's component name">
            <input
              className="tin__input tin__input--code"
              value={design.name}
              spellCheck={false}
              onInput={e => {
                const name = e.target.value.replace(/[^A-Za-z0-9]/g, '');
                set(d => {
                  d.name = name;
                  if (!d.meta.routeLocked) {
                    d.route = toSnake(name);
                  }
                  if (!d.meta.fileLocked) {
                    d.dm.file = dmFileFor(d.route);
                  }
                  if (!d.meta.typeLocked && d.dm.declareType) {
                    d.dm.type = '/obj/machinery/' + d.route;
                  }
                }, 'name');
              }} />
          </Row>
          {check && check.jsExists && !check.jsOurs && (
            <div className="warn">
              interfaces/{design.name}.js is a hand-written window. Pick
              another name.
            </div>
          )}
          <Row label="Key" title="The interface key DM opens it by">
            <input
              className="tin__input tin__input--code"
              value={design.route}
              spellCheck={false}
              onInput={e => set(d => {
                d.route = e.target.value.toLowerCase()
                  .replace(/[^a-z0-9_]/g, '');
                d.meta.routeLocked = true;
                if (!d.meta.fileLocked) {
                  d.dm.file = dmFileFor(d.route);
                }
              }, 'route')} />
          </Row>
          {check && check.routeExists && !check.routeOurs && (
            <div className="warn">
              The key {design.route} already opens {check.routeComponent}.
              Pick another key.
            </div>
          )}
          <Row label="Title">
            <input
              className="tin__input"
              value={design.title}
              onInput={e => set(d => {
                d.title = e.target.value;
              }, 'title')} />
          </Row>
          <Row label="Size">
            <div className="tin__row">
              <NumberBox
                value={design.width}
                onChange={n => set(d => {
                  d.width = Number(n) || 0;
                }, 'width')} />
              <span className="times">×</span>
              <NumberBox
                value={design.height}
                onChange={n => set(d => {
                  d.height = Number(n) || 0;
                }, 'height')} />
            </div>
          </Row>
          <Row label="Theme">
            <Select
              value={design.theme}
              empty={false}
              options={THEMES}
              onChange={theme => set(d => {
                d.theme = theme;
              }, 'theme')} />
          </Row>
          <Row label="Scrolls" title="Content scrolls when it doesn't fit">
            <input
              type="checkbox"
              checked={design.scrollable}
              onChange={e => set(d => {
                d.scrollable = e.target.checked;
              }, 'scroll')} />
          </Row>
        </div>
        <div className="insp__section">
          <div className="insp__sub">DM</div>
          <Row label="Type" title="The object whose window this is">
            <input
              className="tin__input tin__input--code"
              value={dm.type}
              list="dl-wp-types"
              spellCheck={false}
              onInput={async e => {
                const value = e.target.value.trim();
                set(d => {
                  d.dm.type = value;
                  d.meta.typeLocked = true;
                }, 'type');
                if (value.length >= 4) {
                  const res = await api.types(value);
                  if (!res.error) {
                    this.setState({ types: res.types });
                  }
                }
              }} />
          </Row>
          <datalist id="dl-wp-types">
            {this.state.types.map(t => <option key={t} value={t} />)}
          </datalist>
          {typeExists !== null && (
            <div className={typeExists && dm.declareType ? 'warn' : 'hint'}>
              {typeExists
                ? (dm.declareType
                  ? 'This type already exists; untick Declare type so its '
                    + 'vars aren\'t declared twice.'
                  : 'Existing type.')
                : (dm.declareType
                  ? 'New type: the DM file declares it and its vars.'
                  : 'No such type yet. Tick Declare type to make it.')}
            </div>
          )}
          <Row
            label="Declare type"
            title="Declare the type and a var per field">
            <input
              type="checkbox"
              checked={dm.declareType}
              onChange={e => set(d => {
                d.dm.declareType = e.target.checked;
              }, 'declare')} />
          </Row>
          <Row label="File">
            <input
              className="tin__input tin__input--code"
              value={dm.file}
              spellCheck={false}
              onInput={e => set(d => {
                d.dm.file = e.target.value.replace(/\\/g, '/');
                d.meta.fileLocked = true;
              }, 'file')} />
          </Row>
          <Row label="UI state" title="Who may use the window and how">
            <Select
              value={dm.state}
              empty={false}
              options={UI_STATES}
              onChange={s => set(d => {
                d.dm.state = s;
              }, 'state')} />
          </Row>
          <Row label="Title is name" title="Use the object's name as the title">
            <input
              type="checkbox"
              checked={dm.titleFromName}
              onChange={e => set(d => {
                d.dm.titleFromName = e.target.checked;
              }, 'titleFromName')} />
          </Row>
        </div>
      </div>
    );
  }
}
