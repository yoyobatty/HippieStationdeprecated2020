/**
 * New, Open and the overwrite question.
 */

import { Component, createRef } from 'inferno';

const Modal = props => (
  <div className="modal" onMouseDown={e => {
    if (e.target === e.currentTarget) {
      props.onClose();
    }
  }}>
    <div className="modal__box">
      <div className="modal__title">
        {props.title}
        <span className="iconbtn" onClick={props.onClose}>
          <i className="fas fa-times" />
        </span>
      </div>
      {props.children}
    </div>
  </div>
);

export class NewDialog extends Component {
  constructor(props) {
    super(props);
    this.state = { name: '' };
    this.inputRef = createRef();
  }

  componentDidMount() {
    if (this.inputRef.current) {
      this.inputRef.current.focus();
    }
  }

  render() {
    const { onCreate, onClose } = this.props;
    const name = this.state.name;
    const ok = /^[A-Z][A-Za-z0-9]*$/.test(name);
    const create = () => ok && onCreate(name);
    return (
      <Modal title="New window" onClose={onClose}>
        <p>
          Name it the way interfaces are named, like GravityGenerator. The
          key, title and DM file follow from it; change them under Window.
        </p>
        <input
          ref={this.inputRef}
          className="tin__input tin__input--code modal__input"
          value={name}
          placeholder="MyMachine"
          spellCheck={false}
          onInput={e => this.setState({
            name: e.target.value.replace(/[^A-Za-z0-9]/g, ''),
          })}
          onKeyDown={e => e.key === 'Enter' && create()} />
        {name && !ok && (
          <div className="warn">Start with a capital letter.</div>
        )}
        <div className="modal__buttons">
          <span className="btn" onClick={onClose}>Cancel</span>
          <span
            className={'btn btn--primary' + (ok ? '' : ' btn--disabled')}
            onClick={create}>
            Create
          </span>
        </div>
      </Modal>
    );
  }
}

export class OpenDialog extends Component {
  constructor(props) {
    super(props);
    this.state = { filter: '' };
  }

  render() {
    const { designs, error, onOpen, onClose, current } = this.props;
    const filter = this.state.filter.toLowerCase();
    const list = (designs || []).filter(d => !filter
      || d.name.toLowerCase().includes(filter)
      || (d.title || '').toLowerCase().includes(filter));
    return (
      <Modal title="Open a design" onClose={onClose}>
        <input
          className="tin__input modal__input"
          placeholder="Filter"
          value={this.state.filter}
          onInput={e => this.setState({ filter: e.target.value })} />
        {error && <div className="warn">{error}</div>}
        {!designs && !error && <div className="hint">Loading…</div>}
        {designs && designs.length === 0 && (
          <div className="hint">
            No saved designs yet. Saves go to
            packages/tgui-designer/designs.
          </div>
        )}
        <div className="openlist">
          {list.map(d => (
            <div
              key={d.name}
              className={'openlist__item'
                + (d.name === current ? ' openlist__item--current' : '')}
              onClick={() => onOpen(d.name)}>
              <span className="openlist__name">{d.name}</span>
              <span className="openlist__title">{d.title}</span>
              <span className="openlist__time">{d.modified}</span>
            </div>
          ))}
        </div>
      </Modal>
    );
  }
}

export const ConflictDialog = props => {
  const { conflicts, onOverwrite, onClose } = props;
  return (
    <Modal title="Edited outside the designer" onClose={onClose}>
      <p>These files changed since the designer last wrote them:</p>
      <ul>
        {conflicts.map(c => <li key={c.file}><code>{c.file}</code></li>)}
      </ul>
      <p>
        Saving writes them again from the design, and the changes made
        there are lost.
      </p>
      <div className="modal__buttons">
        <span className="btn" onClick={onClose}>Cancel</span>
        <span className="btn btn--danger" onClick={onOverwrite}>
          Overwrite them
        </span>
      </div>
    </Modal>
  );
};
