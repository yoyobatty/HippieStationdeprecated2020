import { Component, createRef, Fragment } from 'inferno';
import { useBackend } from '../backend';
import { Button, Icon, Input } from '../components';
import { kindClass, Who } from './LogSearch';

// hippie -- Tickets: every ahelp ticket in one window. The list on the left
// (waiting ones first), the conversation with a reply box and saved replies,
// who the player is and what happened to them lately, and the round log
// lines about them, the people they named and the room they asked from;
// the kills among them, judged for admins only; where everyone was on a map
// you can scrub through; notes only admins see.
// Data and actions from hippiestation/code/modules/admin/tickets.dm.

const ACTIVE = 1;
const CLOSED = 2;
const RESOLVED = 3;

// 0: the mentors' questions (questions.dm), opened in their own window
const LISTS = [
  [ACTIVE, 'Open'],
  [RESOLVED, 'Resolved'],
  [CLOSED, 'Closed'],
  [0, 'Questions'],
];

const STATE_NAMES = {
  [ACTIVE]: 'Open',
  [CLOSED]: 'Closed',
  [RESOLVED]: 'Resolved',
};

const EMPTY_LISTS = {
  [ACTIVE]: 'No open tickets.',
  0: 'No open questions.',
};

const MINUTES = [2, 5, 15, 30];

const FIRST_STRIKE = {
  victim: 'the dead one',
  killer: 'the killer',
};

const MOB_BUTTONS = [
  ['pp', 'PP', 'Player panel'],
  ['vv', 'VV', 'View variables'],
  ['flw', 'FLW', 'Follow'],
  ['sm', 'SM', 'Subtle message'],
  ['jmp', 'JMP', 'Jump to them'],
];

const MobLinks = props => {
  const { onPick } = props;
  return (
    <span className="Tickets__links">
      {MOB_BUTTONS.map(b => (
        <a key={b[0]} title={b[2]} onClick={() => onPick(b[0])}>{b[1]}</a>
      ))}
    </span>
  );
};

const Chip = props => (
  <span className={'Tickets__chip Tickets__chip--' + props.tone}>
    {props.text}
  </span>
);

const TicketItem = props => {
  const { t, selected, onPick } = props;
  return (
    <div
      className={'Tickets__item'
        + (selected ? ' Tickets__item--selected' : '')
        + (t.waiting_long ? ' Tickets__item--late' : '')}
      onClick={onPick}>
      <div className="Tickets__itemTop">
        <span className="Tickets__itemId">{t.question ? 'Q' : '#'}{t.id}</span>
        <span className="Tickets__itemKey">{t.key}</span>
        {!t.online && (
          <span className="Tickets__tag Tickets__tag--off">gone</span>
        )}
        <span className="Tickets__spacer" />
        <span className="Tickets__muted Tickets__nowrap">{t.age}</span>
      </div>
      <div className="Tickets__itemTitle">{t.title}</div>
      <div className="Tickets__itemBottom">
        {!!t.waiting && (
          <span className={'Tickets__wait'
            + (t.waiting_long ? ' Tickets__wait--late' : '')}>
            <Icon name="hourglass-half" mr={0.5} />
            {t.waiting}
          </span>
        )}
        {!t.waiting && t.state === ACTIVE && (
          <span className="Tickets__muted">answered</span>
        )}
        <span className="Tickets__spacer" />
        {!!t.kind && <span className="Tickets__tag">{t.kind}</span>}
        {!!t.antag && (
          <span className="Tickets__tag Tickets__tag--bad">{t.antag}</span>
        )}
        {t.claimed
          ? (
            <span className={'Tickets__tag'
              + (t.mine ? ' Tickets__tag--mine' : '')}>
              <Icon name="user-check" mr={0.5} />{t.claimed}
            </span>
          )
          : t.state === ACTIVE && (
            <span className="Tickets__tag Tickets__tag--free">unclaimed</span>
          )}
      </div>
    </div>
  );
};

// The station map with everyone on it at the picked time (the crew
// monitor's map: crew_monitor_map() rows of . # _)
const WHERE_MAP_SIZE = 470;
const WHERE_MAP_COLORS = { '#': '#5b6372', _: '#2c3139' };

class WhereMap extends Component {
  constructor() {
    super();
    this.canvasRef = createRef();
  }

  componentDidMount() {
    this.draw();
  }

  componentDidUpdate(prevProps) {
    if (prevProps.map !== this.props.map) {
      this.draw();
    }
  }

  scale() {
    const rows = this.props.map.rows || [];
    const width = rows.length ? rows[0].length : 1;
    return Math.max(1, Math.min(WHERE_MAP_SIZE / width,
      WHERE_MAP_SIZE / Math.max(1, rows.length)));
  }

  draw() {
    const canvas = this.canvasRef.current;
    const { map } = this.props;
    if (!canvas || !map) {
      return;
    }
    const scale = this.scale();
    const context = canvas.getContext('2d');
    context.clearRect(0, 0, canvas.width, canvas.height);
    map.rows.forEach((row, y) => {
      for (let x = 0; x < row.length; x++) {
        const fill = WHERE_MAP_COLORS[row[x]];
        if (fill) {
          context.fillStyle = fill;
          context.fillRect(x * scale, y * scale,
            Math.ceil(scale), Math.ceil(scale));
        }
      }
    });
  }

  render() {
    const { map, dots, picked, onPick } = this.props;
    if (!map.rows || !map.rows.length) {
      return <div className="Tickets__empty">No map of this level.</div>;
    }
    const scale = this.scale();
    const width = Math.ceil(map.rows[0].length * scale);
    const height = Math.ceil(map.rows.length * scale);
    // the player and the people they named drawn last, on top
    const order = { other: 0, named: 1, player: 2 };
    const sorted = dots.slice().sort((a, b) => order[a.role] - order[b.role]);
    return (
      <div className="Tickets__map"
        style={{ width: width + 'px', height: height + 'px' }}>
        <canvas ref={this.canvasRef} width={width} height={height} />
        {sorted.map(d => (
          <div key={d.ckey}
            className={'Tickets__mapDot Tickets__mapDot--' + d.role
              + (d.state === 'dead' || d.state === 'ghost'
                ? ' Tickets__mapDot--dead'
                : '')
              + (picked === d.ckey ? ' Tickets__mapDot--picked' : '')}
            title={d.name + ' (' + d.ckey + '), ' + d.state}
            style={{
              left: ((d.x - map.minx + 0.5) * scale) + 'px',
              top: ((map.maxy - d.y + 0.5) * scale) + 'px',
            }}
            onClick={() => onPick(d.ckey)} />
        ))}
      </div>
    );
  }
}

export class Tickets extends Component {
  constructor() {
    super();
    this.drafts = {};
    this.maps = {};
    this.mapAsked = {};
    this.state = {
      retitle: null,
      saving: false,
      editReplies: false,
      noteMode: false,
      tab: 'lines',
      mapDot: null,
    };
  }

  draft(id) {
    return this.drafts[id] || '';
  }

  setDraft(id, text) {
    this.drafts[id] = text;
    this.setState({});
  }

  send(t, note) {
    const { act } = useBackend(this.props);
    const text = this.draft(t.id).trim();
    if (!text) {
      return;
    }
    act(note ? 'note' : 'reply', { text });
    this.setDraft(t.id, '');
  }

  renderHead(t) {
    const { act } = useBackend(this.props);
    const { retitle } = this.state;
    const open = t.state === ACTIVE;
    return (
      <div className="Tickets__head">
        <div className="Tickets__titleRow">
          <span className="Tickets__bigId">#{t.id}</span>
          {retitle !== null
            ? (
              <Input
                className="Tickets__retitle"
                value={retitle}
                onInput={(e, value) => {
                  this.retitleText = value;
                }}
                onChange={(e, value) => {
                  act('retitle', { title: value });
                  this.retitleText = null;
                  this.setState({ retitle: null });
                }} />
            )
            : (
              <span className="Tickets__title" title="Rename"
                onClick={() => this.setState({ retitle: t.title })}>
                {t.title}
                <Icon name="pen" ml={1} className="Tickets__pen" />
              </span>
            )}
          {!!t.kind && <span className="Tickets__tag">{t.kind}</span>}
          <span className={'Tickets__state Tickets__state--' + t.state}>
            {STATE_NAMES[t.state]}
          </span>
        </div>
        <div className="Tickets__metaRow">
          <span>{t.key}</span>
          {!t.online && (
            <span className="Tickets__tag Tickets__tag--off">
              disconnected
            </span>
          )}
          <span className="Tickets__muted">
            opened {t.opened} ({t.age} ago)
            {t.closed ? ', closed ' + t.closed : ''}
          </span>
          {!!t.waiting && (
            <span className="Tickets__wait Tickets__wait--late">
              <Icon name="hourglass-half" mr={0.5} />
              waiting {t.waiting}
            </span>
          )}
          <span className="Tickets__spacer" />
          {t.claimed
            ? (
              <span className={'Tickets__tag'
                + (t.mine ? ' Tickets__tag--mine' : '')}>
                <Icon name="user-check" mr={0.5} />
                {t.mine ? 'yours' : t.claimed}
              </span>
            )
            : open && (
              <span className="Tickets__tag Tickets__tag--free">
                unclaimed
              </span>
            )}
        </div>
        <div className="Tickets__actRow">
          {open && (
            <Fragment>
              {t.mine
                ? (
                  <Button icon="user-times" content="Unclaim"
                    onClick={() => act('unclaim')} />
                )
                : (
                  <Button icon="user-check" content="Claim" color="good"
                    title={t.claimed ? 'Take it over from ' + t.claimed : ''}
                    onClick={() => act('claim')} />
                )}
              <Button icon="check" content="Resolve"
                title="Handled: they get the Adminhelp verb back"
                onClick={() => act('resolve')} />
              <Button icon="theater-masks" content="IC issue"
                title="Tells them it's in character, and resolves"
                onClick={() => act('icissue')} />
              <Button icon="undo" content="Reject"
                title="Unclear: they're told to ask again"
                onClick={() => act('reject')} />
              <Button icon="times" content="Close"
                onClick={() => act('close')} />
            </Fragment>
          )}
          {!open && (
            <Button icon="folder-open" content="Reopen"
              onClick={() => act('reopen')} />
          )}
          <span className="Tickets__spacer" />
          <Button icon="sync" content="Refresh"
            title="Read their notes and record again"
            onClick={() => act('refresh')} />
        </div>
      </div>
    );
  }

  renderPlayer(t) {
    const { act } = useBackend(this.props);
    const p = t.player || {};
    const who = [p.name, p.job].filter(x => !!x).join(', ');
    const pick = what => act('player', { what });
    return (
      <div className="Tickets__player">
        <div className="Tickets__playerRow">
          <Icon name="user" mr={1} />
          <span className="Tickets__playerName">
            {who || (p.state === 'lobby' ? 'In the lobby' : 'No body')}
          </span>
          {!!p.has_mob && <MobLinks onPick={pick} />}
          <span className="Tickets__spacer" />
          <span className="Tickets__links">
            <a title="Everything known about them"
              onClick={() => pick('profile')}>PROFILE
            </a>
            <a title="Search Logs for them" onClick={() => pick('logs')}>
              LOGS
            </a>
            <a title="Their notes" onClick={() => pick('notes')}>NOTES</a>
            <a title="New note on them, with this ticket and the quoted lines"
              onClick={() => pick('note_add')}>NOTE+
            </a>
            <a title="New ban for them, with this ticket and the quoted lines"
              onClick={() => pick('ban')}>BAN
            </a>
          </span>
        </div>
        <div className="Tickets__chips">
          {(p.chips || []).map((chip, i) => (
            <Chip key={i} text={chip.text} tone={chip.tone} />
          ))}
          {p.connections !== undefined && p.connections !== null && (
            <span className="Tickets__muted Tickets__small Tickets__nowrap">
              {p.connections} connection{p.connections === 1 ? '' : 's'}
              {p.first_days >= 7 && ', first seen ' + p.first_days + ' d ago'}
            </span>
          )}
        </div>
        {!!t.opened_where && (
          <div className="Tickets__small Tickets__muted">
            Asked from {t.opened_where}
            {t.opened_name ? ' as ' + t.opened_name : ''}
            {t.opened_antag ? ' (' + t.opened_antag + ')' : ''}
            <span className="Tickets__links">
              <a title="Jump to where they asked from"
                onClick={() => pick('where')}>JMP
              </a>
            </span>
          </div>
        )}
        {(p.notes || []).map((n, i) => (
          <div key={i} className="Tickets__note">
            <span className={'Tickets__sev Tickets__sev--'
              + (n.severity || 'none')} />
            <span className="Tickets__noteText">{n.text}</span>
            <span className="Tickets__muted">
              {' '}&mdash; {n.admin}, {n.age_days >= 1 && n.age_days + ' d ago'}
              {!(n.age_days >= 1) && 'today'}
            </span>
          </div>
        ))}
        {p.note_count > (p.notes || []).length && (
          <div className="Tickets__small Tickets__muted">
            {p.note_count - p.notes.length} more in NOTES
          </div>
        )}
      </div>
    );
  }

  renderConversation(t, replies) {
    const { act } = useBackend(this.props);
    const { saving, editReplies, noteMode } = this.state;
    const open = t.state === ACTIVE;
    const draft = this.draft(t.id);
    return (
      <div className="Tickets__convo">
        <div className="Tickets__colHead">Conversation</div>
        <div className="Tickets__messages">
          {(t.messages || []).map((m, i) => (
            <div key={i} className={'Tickets__msg Tickets__msg--' + m.kind}>
              <div className="Tickets__msgHead">
                <span className="Tickets__msgTime">{m.time}</span>
                {!!m.who && <span className="Tickets__msgWho">{m.who}</span>}
                {m.kind === 'note' && (
                  <span className="Tickets__noteTag">
                    <Icon name="eye-slash" mr={0.5} />note, admins only
                  </span>
                )}
              </div>
              <div className="Tickets__msgText">{m.text}</div>
            </div>
          ))}
        </div>
        <div className="Tickets__reply">
          {!!t.secret_warning && (
            <div className="Tickets__secret">
              <Icon name="user-secret" mr={1} />
              {t.secret_warning}
            </div>
          )}
          <div className="Tickets__modeRow">
            {open && (
              <span
                className={'Tickets__mode'
                  + (!noteMode ? ' Tickets__mode--on' : '')}
                onClick={() => this.setState({ noteMode: false })}>
                Reply
              </span>
            )}
            <span
              className={'Tickets__mode'
                + (noteMode || !open ? ' Tickets__mode--on' : '')}
              onClick={() => this.setState({ noteMode: true })}>
              <Icon name="eye-slash" mr={0.5} />Note
            </span>
            <span className="Tickets__spacer" />
            {open && !noteMode && (
              <span className="Tickets__savedEdit"
                onClick={() => this.setState({ editReplies: !editReplies })}>
                {editReplies ? 'Done' : 'Edit saved'}
              </span>
            )}
          </div>
          {open && !noteMode && (
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
                    this.setDraft(t.id, before ? before + ' ' + text : text);
                  }}>
                  {title}
                  {editReplies && (
                    <Icon name="times" ml={0.5}
                      className="Tickets__savedX"
                      onClick={() => act('reply_remove', { title })} />
                  )}
                </span>
              ))}
            </div>
          )}
          <textarea
            className={'Tickets__textarea'
              + (noteMode || !open ? ' Tickets__textarea--note' : '')}
            value={draft}
            placeholder={noteMode || !open
              ? 'Note for admins: ' + t.key + ' never sees it'
              : (t.online
                ? 'Reply to ' + t.key + ' (Ctrl+Enter sends)'
                : t.key + ' is disconnected')}
            onInput={e => this.setDraft(t.id, e.target.value)}
            onKeyDown={e => {
              if (e.keyCode === 13 && e.ctrlKey) {
                e.preventDefault();
                this.send(t, noteMode || !open);
              }
            }} />
          <div className="Tickets__replyActs">
            {open && !noteMode && saving && (
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
            {open && !noteMode && !saving && (
              <Button icon="bookmark" content="Save as reply"
                disabled={!draft.trim()}
                onClick={() => this.setState({ saving: true })} />
            )}
            <span className="Tickets__spacer" />
            {noteMode || !open
              ? (
                <Button icon="eye-slash" content="Add note" color="average"
                  disabled={!draft.trim()}
                  onClick={() => this.send(t, true)} />
              )
              : (
                <Button icon="paper-plane" content="Send" color="good"
                  disabled={!draft.trim() || !t.online}
                  onClick={() => this.send(t)} />
              )}
          </div>
        </div>
      </div>
    );
  }

  renderLines(t) {
    const { act } = useBackend(this.props);
    const rows = t.context || [];
    const named = t.named || [];
    const quoted = t.quoted || [];
    let marked = false;
    const lines = [];
    const mark = (
      <div key="mark" className="Tickets__mark">
        <span>ahelp #{t.id} at {t.opened}</span>
      </div>
    );
    rows.forEach(row => {
      if (!marked && row.id > t.opened_log_id) {
        marked = true;
        lines.push(mark);
      }
      const isQuoted = quoted.indexOf(row.id) >= 0;
      lines.push(
        <div key={row.id}
          className={'LogSearch__line'
            + (isQuoted ? ' Tickets__line--quoted' : '')}>
          <div className="LogSearch__time">{row.time}</div>
          <div className="LogSearch__kindCol">
            <span className={kindClass(row.kind)} />
            {row.kind.replace('Investigate: ', '')}
          </div>
          <div className="LogSearch__body">
            <div className="LogSearch__text">{row.text}</div>
            <div className="LogSearch__meta">
              <Who act={act} row={row} prefix=""
                ckey={row.ckey} name={row.name}
                alive={row.actor} mob={row.actor_mob} />
              {(!!row.tckey || !!row.tname) && (
                <span className="LogSearch__arrowText">to</span>
              )}
              <Who act={act} row={row} prefix="t_"
                ckey={row.tckey} name={row.tname}
                alive={row.target} mob={row.target_mob} />
              {!!row.where && (
                <span className="LogSearch__where">
                  <Icon name="map-marker-alt" mr={0.5} />
                  {row.area}
                  <span className="LogSearch__acts">
                    <a onClick={() => act('jmp', { id: row.id })}
                      title={'Jump to ' + row.where}>JMP
                    </a>
                  </span>
                </span>
              )}
              <span className="LogSearch__acts">
                <a onClick={() => act('quote', { id: row.id })}
                  title="Quote it in a Ban or Note from this ticket">
                  {isQuoted ? 'UNQUOTE' : 'QUOTE'}
                </a>
              </span>
            </div>
            {!!row.seen && (
              <div className="Tickets__seen">
                <Icon name="eye" mr={0.5} />seen by {row.seen}
              </div>
            )}
          </div>
        </div>,
      );
    });
    if (!marked && rows.length) {
      lines.push(mark);
    }
    const source = (key, label, on, title) => (
      <span
        className={'LogSearch__chip' + (on ? ' LogSearch__chip--on' : '')}
        title={title}
        onClick={() => act('context', { source: key })}>
        {label}
      </span>
    );
    return (
      <Fragment>
        <div className="Tickets__sources">
          {source('player', 'Them', t.show_player,
            'Lines where they did something or had something done to them')}
          {source('named', 'Named (' + named.length + ')', t.show_named,
            'Lines about the people their messages name')}
          {source('seen', 'Saw', t.show_seen,
            'Fights, deaths and bombs they could see')}
          {source('heard', 'Heard', t.show_heard,
            'What was said within earshot of them')}
          {source('area', 'Room', t.show_area,
            'Everything in the room they asked from, up to the ahelp')}
          <span className="Tickets__spacer" />
          {MINUTES.map(m => (
            <span key={m}
              className={'Tickets__min'
                + (t.context_minutes === m ? ' Tickets__min--on' : '')}
              title={m + ' minutes before the ahelp, and since'}
              onClick={() => act('context', { minutes: m })}>
              {m}m
            </span>
          ))}
        </div>
        {quoted.length > 0 && (
          <div className="Tickets__quoteBar">
            <Icon name="quote-left" mr={1} />
            {quoted.length} line{quoted.length === 1 ? '' : 's'} quoted:
            BAN and NOTE+ put {quoted.length === 1 ? 'it' : 'them'} in
            <span className="Tickets__spacer" />
            <a onClick={() => act('unquote_all')}>clear</a>
          </div>
        )}
        {named.length > 0 && (
          <div className="Tickets__named">
            {named.map(n => (
              <div key={n.index} className="Tickets__namedRow">
                <span className="Tickets__namedName">
                  {n.name}{n.ckey ? ' (' + n.ckey + ')' : ''}
                </span>
                <span className="Tickets__muted Tickets__small">
                  {[n.job, n.state !== 'alive' ? n.state : null,
                    n.bot ? 'bot' : null].filter(x => !!x).join(', ')}
                </span>
                {!!n.antag && (
                  <span className="Tickets__tag Tickets__tag--bad">
                    {n.antag}
                  </span>
                )}
                <span className="Tickets__spacer" />
                <MobLinks onPick={what => act('named', {
                  index: n.index,
                  what,
                })} />
              </div>
            ))}
          </div>
        )}
        <div className="Tickets__lines">
          {rows.length === 0 && (
            <div className="Tickets__empty">
              Nothing logged.
            </div>
          )}
          {lines}
        </div>
      </Fragment>
    );
  }

  renderKills(t) {
    const kills = t.kills || [];
    const side = (s, label) => {
      if (!s) {
        return (
          <div className="Tickets__killSide">
            <span className="Tickets__muted">{label}: nobody hit them</span>
          </div>
        );
      }
      return (
        <div className="Tickets__killSide">
          <span className="Tickets__muted">{label} </span>
          <b>{s.name}</b>
          {!!s.ckey && <span className="Tickets__muted"> ({s.ckey})</span>}
          {!!s.job && ', ' + s.job}
          {!!s.antag && (
            <span className="Tickets__tag Tickets__tag--bad">{s.antag}</span>
          )}
          {!!s.security && <span className="Tickets__tag">Security</span>}
          {!!s.wanted && (
            <span className="Tickets__tag Tickets__tag--warn">
              set to {s.wanted}
            </span>
          )}
          {!!s.cuffed && <span className="Tickets__tag">cuffed</span>}
          {!!s.bot && <span className="Tickets__tag">bot</span>}
          {(s.objectives || []).map((o, i) => (
            <div key={i} className="Tickets__objective">
              <Icon name="bullseye" mr={0.5} />{o}
            </div>
          ))}
        </div>
      );
    };
    return (
      <div className="Tickets__lines">
        <div className="Tickets__killNote">
          <Icon name="user-secret" mr={1} />
          Admins only: none of this goes to the player.
        </div>
        {kills.length === 0 && (
          <div className="Tickets__empty">
            No deaths of them or the people they named in the last 30 min.
          </div>
        )}
        {kills.map(k => (
          <div key={k.id} className="Tickets__kill">
            <div className="Tickets__killHead">
              <span className="Tickets__msgTime">{k.time}</span>
              <b>{k.victim.name}</b> died in {k.area || 'somewhere'}
            </div>
            {side(k.killer, 'Killer')}
            {side(k.victim, 'Dead')}
            {!!k.how && (
              <div className="Tickets__small Tickets__muted">
                Last hit: {k.how}
              </div>
            )}
            {!!k.killer && (
              <div className="Tickets__small">
                <span className="Tickets__muted">Struck first: </span>
                {FIRST_STRIKE[k.first] || 'unknown'}
              </div>
            )}
            {!!k.seen && (
              <div className="Tickets__seen">
                <Icon name="eye" mr={0.5} />seen by {k.seen}
              </div>
            )}
            {!!k.killer && (
              <div className="Tickets__reasons">
                {(k.reasons || []).length === 0
                  ? (
                    <span className="Tickets__chip Tickets__chip--bad">
                      {'no reason found: neither is an antagonist, the dead'
                        + ' one didn\'t strike first, no arrest'}
                    </span>
                  )
                  : k.reasons.map((r, i) => (
                    <span key={i} className="Tickets__chip Tickets__chip--ok">
                      {r}
                    </span>
                  ))}
              </div>
            )}
          </div>
        ))}
      </div>
    );
  }

  renderMap(t) {
    const { act } = useBackend(this.props);
    const w = t.whereabouts;
    if (!w) {
      return <div className="Tickets__empty">Loading...</div>;
    }
    if (w.none) {
      return (
        <div className="Tickets__empty">
          {'No positions kept yet: they\'re taken every 5 seconds once'
            + ' the round starts.'}
        </div>
      );
    }
    if (w.map) {
      this.maps[w.z] = w.map;
    }
    const map = this.maps[w.z];
    if (!map && !this.mapAsked[w.z]) {
      this.mapAsked[w.z] = true;
      act('map_need');
    }
    const picked = this.state.mapDot;
    const pickedDot = (w.dots || []).find(d => d.ckey === picked);
    return (
      <div className="Tickets__mapPane">
        <div className="Tickets__mapBar">
          <span className="Tickets__mapTime">{w.time}</span>
          <input
            className="Tickets__slider"
            type="range"
            min={w.min}
            max={w.max}
            step={50}
            value={w.t}
            onChange={e => act('map_time', { t: e.target.value })} />
          <a title="Back to the ahelp"
            onClick={() => act('map_time', { t: w.ahelp_t })}>ahelp
          </a>
          <a title="Now" onClick={() => act('map_time', { t: w.max })}>now</a>
          {(w.levels || []).length > 1 && w.levels.map(z => (
            <span key={z}
              className={'Tickets__min'
                + (z === w.z ? ' Tickets__min--on' : '')}
              onClick={() => act('map_z', { z })}>
              z{z}
            </span>
          ))}
        </div>
        <div className="Tickets__mapLegend">
          <span className="Tickets__dot Tickets__dot--player" /> them
          <span className="Tickets__dot Tickets__dot--named" /> named
          <span className="Tickets__dot Tickets__dot--other" /> others
          <span className="Tickets__dot Tickets__dot--dead" /> dead
        </div>
        <div className="Tickets__mapScroll">
          {!map && <div className="Tickets__empty">Loading the map...</div>}
          {!!map && (
            <WhereMap map={map} dots={w.dots || []} picked={picked}
              onPick={ckey => this.setState({ mapDot: ckey })} />
          )}
        </div>
        {!!pickedDot && (
          <div className="Tickets__mapPicked">
            <b>{pickedDot.name}</b> ({pickedDot.ckey}), {pickedDot.state}
            {' '}at {pickedDot.x}, {pickedDot.y}
            <MobLinks onPick={what => act('map_dot', {
              ckey: pickedDot.ckey,
              what,
            })} />
          </div>
        )}
      </div>
    );
  }

  renderContext(t) {
    const { act } = useBackend(this.props);
    const tab = this.state.tab || 'lines';
    const pick = name => {
      if ((name === 'map') !== (tab === 'map')) {
        act('map_open', { open: name === 'map' ? 1 : 0 });
      }
      this.setState({ tab: name });
    };
    const kills = t.kills || [];
    return (
      <div className="Tickets__context">
        <div className="Tickets__ctxTabs">
          <span
            className={'Tickets__ctxTab'
              + (tab === 'lines' ? ' Tickets__ctxTab--on' : '')}
            onClick={() => pick('lines')}>
            <Icon name="stream" mr={0.5} />What happened
          </span>
          <span
            className={'Tickets__ctxTab'
              + (tab === 'kills' ? ' Tickets__ctxTab--on' : '')}
            onClick={() => pick('kills')}>
            <Icon name="skull" mr={0.5} />Kills
            {kills.length > 0 && (
              <span className="Tickets__count">{kills.length}</span>
            )}
          </span>
          <span
            className={'Tickets__ctxTab'
              + (tab === 'map' ? ' Tickets__ctxTab--on' : '')}
            onClick={() => pick('map')}>
            <Icon name="map" mr={0.5} />Map
          </span>
        </div>
        {tab === 'lines' && this.renderLines(t)}
        {tab === 'kills' && this.renderKills(t)}
        {tab === 'map' && this.renderMap(t)}
      </div>
    );
  }

  render() {
    const { act, data } = useBackend(this.props);
    const tickets = data.tickets || [];
    const t = data.ticket;
    const counts = data.counts || {};
    return (
      <div className="Tickets">
        <div className="Tickets__list">
          <div className="Tickets__tabs">
            {LISTS.map(l => (
              <span key={l[0]}
                className={'Tickets__tab'
                  + (data.list_state === l[0] ? ' Tickets__tab--on' : '')}
                onClick={() => act('list', { state: l[0] })}>
                {l[1]}
                <span className="Tickets__count">{counts[l[0]] || 0}</span>
              </span>
            ))}
          </div>
          <div className="Tickets__items">
            {tickets.length === 0 && (
              <div className="Tickets__empty">
                {EMPTY_LISTS[data.list_state] || 'None.'}
              </div>
            )}
            {tickets.map(item => (
              <TicketItem key={item.id} t={item}
                selected={!!t && t.id === item.id}
                onPick={() => {
                  if (item.question) {
                    act('question', { id: item.id });
                    return;
                  }
                  this.setState({
                    retitle: null,
                    saving: false,
                    mapDot: null,
                  });
                  act('select', { id: item.id });
                }} />
            ))}
          </div>
        </div>
        <div className="Tickets__main">
          {!!data.notice && (
            <div className={'Tickets__notice'
              + (data.notice_bad ? ' Tickets__notice--bad' : '')}>
              {data.notice}
            </div>
          )}
          {!t && (
            <div className="Tickets__empty Tickets__empty--big">
              {tickets.length ? 'Pick a ticket.' : 'No tickets.'}
            </div>
          )}
          {!!t && (
            <Fragment>
              {this.renderHead(t)}
              {this.renderPlayer(t)}
              <div className="Tickets__body">
                {this.renderConversation(t, data.replies || {})}
                {this.renderContext(t)}
              </div>
            </Fragment>
          )}
        </div>
      </div>
    );
  }
}
