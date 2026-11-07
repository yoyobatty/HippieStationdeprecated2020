import { Component, Fragment } from 'inferno';
import { useBackend } from '../backend';
import { Button, Icon, Input } from '../components';

// hippie -- Questions: mentorhelps as tickets, for mentors and admins. Who's
// answering which, how long each has waited, the conversation and a box to
// answer in, saved replies, Done, and To admins for one that's really an
// ahelp. No antagonists, logs or notes here: mentors see what a player could.
// Data and actions from hippiestation/code/modules/mentor/questions.dm.
// Styles: the Tickets window's (Tickets.scss).

const QuestionItem = props => {
  const { q, selected, onPick } = props;
  return (
    <div
      className={'Tickets__item'
        + (selected ? ' Tickets__item--selected' : '')
        + (q.waiting_long ? ' Tickets__item--late' : '')}
      onClick={onPick}>
      <div className="Tickets__itemTop">
        <span className="Tickets__itemId">Q{q.id}</span>
        <span className="Tickets__itemKey">{q.key}</span>
        {!q.online && (
          <span className="Tickets__tag Tickets__tag--off">gone</span>
        )}
        <span className="Tickets__spacer" />
        <span className="Tickets__muted Tickets__nowrap">{q.age}</span>
      </div>
      <div className="Tickets__itemTitle">{q.title}</div>
      <div className="Tickets__itemBottom">
        {!!q.waiting && (
          <span className={'Tickets__wait'
            + (q.waiting_long ? ' Tickets__wait--late' : '')}>
            <Icon name="hourglass-half" mr={0.5} />
            {q.waiting}
          </span>
        )}
        {!q.waiting && !!q.open && (
          <span className="Tickets__muted">answered</span>
        )}
        <span className="Tickets__spacer" />
        {!!q.claimed && (
          <span className={'Tickets__tag'
            + (q.mine ? ' Tickets__tag--mine' : '')}>
            <Icon name="user-check" mr={0.5} />{q.claimed}
          </span>
        )}
        {!q.claimed && !!q.open && (
          <span className="Tickets__tag Tickets__tag--free">unclaimed</span>
        )}
      </div>
    </div>
  );
};

export class Questions extends Component {
  constructor() {
    super();
    this.drafts = {};
    this.state = { saving: false, editReplies: false };
  }

  draft(id) {
    return this.drafts[id] || '';
  }

  setDraft(id, text) {
    this.drafts[id] = text;
    this.setState({});
  }

  send(q) {
    const { act } = useBackend(this.props);
    const text = this.draft(q.id).trim();
    if (!text) {
      return;
    }
    act('reply', { text });
    this.setDraft(q.id, '');
  }

  renderQuestion(q, replies) {
    const { act, data } = useBackend(this.props);
    const { saving, editReplies } = this.state;
    const draft = this.draft(q.id);
    return (
      <Fragment>
        <div className="Tickets__head">
          <div className="Tickets__titleRow">
            <span className="Tickets__bigId">Q{q.id}</span>
            <span className="Tickets__title">{q.title}</span>
            <span className={'Tickets__state Tickets__state--'
              + (q.open ? 1 : 3)}>
              {q.open ? 'Open' : 'Done'}
            </span>
          </div>
          <div className="Tickets__metaRow">
            <span>{q.key}</span>
            {!!q.name && (
              <span className="Tickets__muted">
                {q.name}{q.job ? ', ' + q.job : ''}
              </span>
            )}
            {!q.online && (
              <span className="Tickets__tag Tickets__tag--off">
                disconnected
              </span>
            )}
            {!!q.new_player && (
              <span className="Tickets__tag Tickets__tag--warn">
                {q.new_player}
              </span>
            )}
            <span className="Tickets__muted">
              asked {q.opened} ({q.age} ago)
            </span>
            {!!q.waiting && (
              <span className="Tickets__wait Tickets__wait--late">
                <Icon name="hourglass-half" mr={0.5} />
                waiting {q.waiting}
              </span>
            )}
            <span className="Tickets__spacer" />
            {!!q.claimed && (
              <span className={'Tickets__tag'
                + (q.mine ? ' Tickets__tag--mine' : '')}>
                <Icon name="user-check" mr={0.5} />
                {q.mine ? 'yours' : q.claimed}
              </span>
            )}
          </div>
          <div className="Tickets__actRow">
            {!!q.open && (
              <Fragment>
                {q.mine
                  ? (
                    <Button icon="user-times" content="Unclaim"
                      onClick={() => act('unclaim')} />
                  )
                  : (
                    <Button icon="user-check" content="Claim" color="good"
                      title={q.claimed ? 'Take it over from ' + q.claimed : ''}
                      onClick={() => act('claim')} />
                  )}
                <Button icon="check" content="Done"
                  title="Answered: they can mentorhelp again for more"
                  onClick={() => act('done')} />
                <Button icon="gavel" content="To admins"
                  title={'Really an ahelp: it goes to the admins with what\'s'
                    + ' been said'}
                  onClick={() => act('to_admins')} />
              </Fragment>
            )}
            {!q.open && (
              <Button icon="folder-open" content="Reopen"
                onClick={() => act('reopen')} />
            )}
            {!!q.online && (
              <Button icon="eye" content="Follow"
                onClick={() => act('follow')} />
            )}
            {!!q.ahelp && !!data.is_admin && (
              <Button icon="question-circle" content={'Ahelp #' + q.ahelp}
                onClick={() => act('ticket')} />
            )}
          </div>
        </div>
        <div className="Tickets__convo">
          <div className="Tickets__messages">
            {(q.messages || []).map((m, i) => (
              <div key={i}
                className={'Tickets__msg Tickets__msg--'
                  + (m.kind === 'mentor' ? 'admin' : m.kind)}>
                <div className="Tickets__msgHead">
                  <span className="Tickets__msgTime">{m.time}</span>
                  {!!m.who && <span className="Tickets__msgWho">{m.who}</span>}
                </div>
                <div className="Tickets__msgText">{m.text}</div>
              </div>
            ))}
          </div>
          {!!q.open && (
            <div className="Tickets__reply">
              <div className="Tickets__saved">
                {Object.keys(replies).map(title => (
                  <span key={title}
                    className="Tickets__savedChip"
                    title={replies[title]}
                    onClick={() => {
                      if (editReplies) {
                        return;
                      }
                      const text = replies[title];
                      const before = draft.trim();
                      this.setDraft(q.id, before ? before + ' ' + text : text);
                    }}>
                    {title}
                    {editReplies && (
                      <Icon name="times" ml={0.5}
                        className="Tickets__savedX"
                        onClick={() => act('reply_remove', { title })} />
                    )}
                  </span>
                ))}
                <span className="Tickets__savedEdit"
                  onClick={() => this.setState({ editReplies: !editReplies })}>
                  {editReplies ? 'Done' : 'Edit'}
                </span>
              </div>
              <textarea
                className="Tickets__textarea"
                value={draft}
                placeholder={q.online
                  ? 'Answer ' + q.key + ' (Ctrl+Enter sends)'
                  : q.key + ' is disconnected'}
                onInput={e => this.setDraft(q.id, e.target.value)}
                onKeyDown={e => {
                  if (e.keyCode === 13 && e.ctrlKey) {
                    e.preventDefault();
                    this.send(q);
                  }
                }} />
              <div className="Tickets__replyActs">
                {saving && (
                  <Fragment>
                    <Input
                      className="Tickets__saveTitle"
                      value=""
                      placeholder="Name"
                      onInput={(e, value) => {
                        this.saveTitleText = value;
                      }} />
                    <Button icon="save" content="Save"
                      onClick={() => {
                        act('reply_save', {
                          title: this.saveTitleText || '',
                          text: draft,
                        });
                        this.saveTitleText = '';
                        this.setState({ saving: false });
                      }} />
                    <Button content="Cancel"
                      onClick={() => this.setState({ saving: false })} />
                  </Fragment>
                )}
                {!saving && (
                  <Button icon="bookmark" content="Save as reply"
                    disabled={!draft.trim()}
                    onClick={() => this.setState({ saving: true })} />
                )}
                <span className="Tickets__spacer" />
                <Button icon="paper-plane" content="Send" color="good"
                  disabled={!draft.trim() || !q.online}
                  onClick={() => this.send(q)} />
              </div>
            </div>
          )}
        </div>
      </Fragment>
    );
  }

  render() {
    const { act, data } = useBackend(this.props);
    const questions = data.questions || [];
    const q = data.question;
    return (
      <div className="Tickets">
        <div className="Tickets__list">
          <div className="Tickets__tabs">
            <span
              className={'Tickets__tab'
                + (data.show_open ? ' Tickets__tab--on' : '')}
              onClick={() => act('list', { open: 1 })}>
              Open<span className="Tickets__count">{data.open_count}</span>
            </span>
            <span
              className={'Tickets__tab'
                + (!data.show_open ? ' Tickets__tab--on' : '')}
              onClick={() => act('list', { open: 0 })}>
              Done<span className="Tickets__count">{data.done_count}</span>
            </span>
          </div>
          <div className="Tickets__items">
            {questions.length === 0 && (
              <div className="Tickets__empty">
                {data.show_open ? 'No open questions.' : 'None.'}
              </div>
            )}
            {questions.map(item => (
              <QuestionItem key={item.id} q={item}
                selected={!!q && q.id === item.id}
                onPick={() => {
                  this.setState({ saving: false });
                  act('select', { id: item.id });
                }} />
            ))}
          </div>
          <div className="Tickets__listFoot">
            {data.mentors_on} mentor{data.mentors_on === 1 ? '' : 's'}
            {' and '}{data.admins_on} admin{data.admins_on === 1 ? '' : 's'} on
          </div>
        </div>
        <div className="Tickets__main">
          {!!data.notice && (
            <div className={'Tickets__notice'
              + (data.notice_bad ? ' Tickets__notice--bad' : '')}>
              {data.notice}
            </div>
          )}
          {!q && (
            <div className="Tickets__empty Tickets__empty--big">
              {questions.length ? 'Pick a question.' : 'No questions.'}
            </div>
          )}
          {!!q && this.renderQuestion(q, data.replies || {})}
        </div>
      </div>
    );
  }
}
