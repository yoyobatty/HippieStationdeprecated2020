import { Component } from 'inferno';
import { useBackend } from '../backend';
import { Icon } from '../components';

// hippie -- a character's Notes (the IC Notes verb): their notes, the
// antagonists' notes, the objectives with conspirators, and a box to add a
// note. Data and actions from hippiestation/code/datums/manifest_notes_tgui.dm.

export class MindNotes extends Component {
  constructor() {
    super();
    this.state = { text: '' };
  }

  render() {
    const { act, data } = useBackend(this.props);
    const notes = data.notes || [];
    const antagNotes = data.antag_notes || [];
    const objectives = data.objectives || [];
    const add = () => {
      if (this.state.text.trim()) {
        act('add', { text: this.state.text });
        this.setState({ text: '' });
      }
    };
    return (
      <div className="Manifest">
        <div className="Manifest__head">
          <div className="Manifest__title">
            <Icon name="sticky-note" /> {data.name + '’s notes'}
          </div>
        </div>
        <div className="Manifest__list">
          {objectives.length > 0 && (
            <div className="Manifest__dept Manifest__dept--objectives">
              <div className="Manifest__deptHead">
                <Icon name="crosshairs" /> Objectives
              </div>
              {objectives.map((objective, i) => (
                <div key={i} className="Notes__objective">
                  <span className="Notes__number">{i + 1}</span>
                  <div className="Notes__text">
                    {objective.text}
                    {objective.conspirators.length > 0 && (
                      <div className="Notes__with">
                        <Icon name="user-friends" />
                        {' '}With {objective.conspirators.join(', ')}
                      </div>
                    )}
                  </div>
                </div>
              ))}
            </div>
          )}
          {antagNotes.map(note => (
            <div
              key={note.role}
              className="Manifest__dept Manifest__dept--objectives">
              <div className="Manifest__deptHead">
                <Icon name="user-secret" /> {note.role}
              </div>
              <div className="Notes__note">{note.text}</div>
            </div>
          ))}
          <div className="Manifest__dept Manifest__dept--other">
            <div className="Manifest__deptHead">
              <Icon name="book" /> Notes
              <span className="Manifest__deptCount">{notes.length}</span>
            </div>
            {notes.length === 0 && (
              <div className="Notes__note Manifest__none">Nothing yet.</div>
            )}
            {notes.map((note, i) => (
              <div key={i} className="Notes__note">{note}</div>
            ))}
          </div>
        </div>
        {!!data.can_add && (
          <div className="Notes__add">
            <input
              className="Manifest__search Notes__input"
              placeholder="Write a note..."
              value={this.state.text}
              onInput={e => this.setState({ text: e.target.value })}
              onKeyDown={e => {
                if (e.keyCode === 13) {
                  add();
                }
              }} />
            <div className="Notes__button" onClick={add}>
              <Icon name="plus" /> Add
            </div>
          </div>
        )}
      </div>
    );
  }
}
