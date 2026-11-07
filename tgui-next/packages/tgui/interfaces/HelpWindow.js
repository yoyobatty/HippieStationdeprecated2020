import { Component } from 'inferno';
import { useBackend } from '../backend';
import { Button, Icon } from '../components';

// hippie -- Ask for help: the player's side of ahelps. The form (what kind,
// who it's about, what happened), then their own ticket: what they and the
// admins said, its status, and a box to answer in. A Question goes to the
// mentors. Data and actions from
// hippiestation/code/modules/admin/help_window.dm.

const KIND_ICONS = {
  report: 'user-shield',
  bug: 'bug',
  question: 'question',
  other: 'comment',
};

const KIND_ORDER = ['report', 'bug', 'question', 'other'];

const STATUS_WORDS = {
  ahelp: {
    waiting: 'Waiting for an admin',
    claimed: 'An admin is handling it',
  },
  question: {
    waiting: 'Waiting for a mentor',
    claimed: 'A mentor is answering',
  },
};

const PLACEHOLDERS = {
  report: 'What happened, where, and when?',
  bug: 'What you did, and what went wrong.',
  question: 'What do you want to know?',
  other: 'What do you need?',
};

export class HelpWindow extends Component {
  constructor() {
    super();
    this.state = { kind: 'report', about: 0, text: '', reply: '' };
  }

  renderForm() {
    const { act, data } = useBackend(this.props);
    const { kind, about, text } = this.state;
    const kinds = data.kinds || {};
    const people = data.about || [];
    const toMentors = kind === 'question';
    const blocked = !toMentors && !data.can_ask;
    return (
      <div className="HelpWindow__form">
        <div className="HelpWindow__label">What is it?</div>
        <div className="HelpWindow__kinds">
          {KIND_ORDER.map(k => (
            <div key={k}
              className={'HelpWindow__kind'
                + (kind === k ? ' HelpWindow__kind--on' : '')}
              onClick={() => this.setState({ kind: k })}>
              <Icon name={KIND_ICONS[k]} size={1.4} />
              <div>{kinds[k]}</div>
            </div>
          ))}
        </div>
        <div className="HelpWindow__to">
          {toMentors
            ? 'Goes to the mentors (' + data.mentors_on + ' on).'
            : 'Goes to the admins (' + data.admins_on + ' on).'}
        </div>
        {kind !== 'question' && kind !== 'bug' && (
          <div>
            <div className="HelpWindow__label">Who is it about?</div>
            <div className="HelpWindow__people">
              <span
                className={'HelpWindow__person'
                  + (!about ? ' HelpWindow__person--on' : '')}
                onClick={() => this.setState({ about: 0 })}>
                Nobody here
              </span>
              {people.map(p => (
                <span key={p.index}
                  className={'HelpWindow__person'
                    + (about === p.index ? ' HelpWindow__person--on' : '')}
                  onClick={() => this.setState({ about: p.index })}>
                  {p.name}
                  <span className="HelpWindow__why">{p.why}</span>
                </span>
              ))}
            </div>
          </div>
        )}
        <textarea
          className="HelpWindow__textarea"
          value={text}
          maxLength={1024}
          placeholder={PLACEHOLDERS[kind]}
          onInput={e => this.setState({ text: e.target.value })} />
        <div className="HelpWindow__actions">
          {blocked && (
            <span className="HelpWindow__muted">
              You asked a moment ago: wait a little.
            </span>
          )}
          <span className="HelpWindow__spacer" />
          <Button icon="paper-plane" content="Send" color="good"
            disabled={!text.trim() || blocked}
            onClick={() => {
              act('send', {
                kind,
                about: kind === 'question' || kind === 'bug' ? 0 : about,
                text,
              });
              this.setState({ text: '', about: 0 });
            }} />
        </div>
      </div>
    );
  }

  renderTicket(which, t) {
    const { act } = useBackend(this.props);
    const { reply } = this.state;
    const staff = which === 'question' ? 'mentor' : 'admin';
    const words = STATUS_WORDS[which];
    let status = words.waiting;
    if (t.claimed) {
      status = words.claimed;
    }
    if (!t.waiting && t.claimed) {
      status = 'Answered: reply below if there\'s more';
    }
    return (
      <div className="HelpWindow__ticket">
        <div className="HelpWindow__head">
          <div className="HelpWindow__title">
            {which === 'question' ? 'Your question' : 'Your ahelp'}
            {!!t.kind && <span className="HelpWindow__tag">{t.kind}</span>}
          </div>
          <div className={'HelpWindow__status'
            + (t.waiting ? ' HelpWindow__status--waiting' : '')}>
            <Icon name={t.waiting ? 'hourglass-half' : 'user-check'} mr={1} />
            {status}
          </div>
        </div>
        <div className="HelpWindow__lines">
          {(t.lines || []).map((line, i) => (
            <div key={i}
              className={'HelpWindow__line HelpWindow__line--' + line.kind}>
              {line.kind !== 'event' && (
                <div className="HelpWindow__who">
                  {line.who}
                  <span className="HelpWindow__time">{line.time}</span>
                </div>
              )}
              <div>{line.text}</div>
            </div>
          ))}
        </div>
        <textarea
          className="HelpWindow__textarea HelpWindow__textarea--reply"
          value={reply}
          maxLength={1024}
          placeholder={'Reply to the ' + staff + 's (Ctrl+Enter sends)'}
          onInput={e => this.setState({ reply: e.target.value })}
          onKeyDown={e => {
            if (e.keyCode === 13 && e.ctrlKey && reply.trim()) {
              e.preventDefault();
              act('reply', { which, text: reply });
              this.setState({ reply: '' });
            }
          }} />
        <div className="HelpWindow__actions">
          <span className="HelpWindow__spacer" />
          <Button icon="paper-plane" content="Send" color="good"
            disabled={!reply.trim()}
            onClick={() => {
              act('reply', { which, text: reply });
              this.setState({ reply: '' });
            }} />
        </div>
      </div>
    );
  }

  render() {
    const { act, data } = useBackend(this.props);
    const showing = data.showing;
    return (
      <div className="HelpWindow">
        {!!data.notice && (
          <div className={'HelpWindow__notice'
            + (data.notice_bad ? ' HelpWindow__notice--bad' : '')}>
            {data.notice}
          </div>
        )}
        {!!data.ahelp && !!data.question && (
          <div className="HelpWindow__tabs">
            <span
              className={'HelpWindow__tab'
                + (showing === 'ahelp' ? ' HelpWindow__tab--on' : '')}
              onClick={() => act('show', { which: 'ahelp' })}>
              Ahelp
            </span>
            <span
              className={'HelpWindow__tab'
                + (showing === 'question' ? ' HelpWindow__tab--on' : '')}
              onClick={() => act('show', { which: 'question' })}>
              Question
            </span>
          </div>
        )}
        {!showing && this.renderForm()}
        {showing === 'ahelp' && !!data.ahelp
          && this.renderTicket('ahelp', data.ahelp)}
        {showing === 'question' && !!data.question
          && this.renderTicket('question', data.question)}
      </div>
    );
  }
}
