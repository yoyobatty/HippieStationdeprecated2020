import { Fragment } from 'inferno';
import { useBackend } from '../backend';
import { Button, Icon } from '../components';

// hippie -- Player profile, for admins: who they are now, how long they've
// been coming, alt keys and whether those are banned, bans, notes, tickets
// this round and before, rounds played, and this round by the log. Data and
// actions from hippiestation/code/modules/admin/player_profile.dm.

const STATUS = {
  online: 'Online',
  left: 'Left this round',
  seen: 'Seen before',
  unknown: 'Never seen here',
};

const OUTCOME_TONES = {
  'open': 'bad',
  'resolved': 'good',
  'IC issue': 'info',
  'rejected': 'warn',
  'closed': 'info',
};

const CHIP_BAD = 'PlayerProfile__chip PlayerProfile__chip--bad';
const ROW_TOP = 'PlayerProfile__row PlayerProfile__row--top';

const NOTE_KINDS = {
  'note': 'Note',
  'message': 'Message',
  'message sent': 'Message (read)',
  'watchlist entry': 'Watchlist',
};

const Section = props => (
  <div className="PlayerProfile__section">
    <div className="PlayerProfile__sectionHead">
      {props.title}
      {props.count !== undefined && (
        <span className="PlayerProfile__count">{props.count}</span>
      )}
      <span className="PlayerProfile__spacer" />
      {props.buttons}
    </div>
    {props.children}
  </div>
);

const Empty = props => (
  <div className="PlayerProfile__empty">{props.text}</div>
);

export const PlayerProfile = props => {
  const { act, data } = useBackend(props);
  if (!data.ckey) {
    return null;
  }
  const now = data.now || {};
  const counts = data.round_counts || {};
  const alts = data.alts || [];
  const bans = data.bans || [];
  const notes = data.notes || [];
  const tickets = data.tickets || [];
  const rounds = data.rounds || [];
  const activeBans = bans.filter(b => b.status === 'active').length;
  return (
    <div className="PlayerProfile">
      <div className="PlayerProfile__head">
        <div className="PlayerProfile__titleRow">
          {!!data.can_back && (
            <Button icon="arrow-left" title="Back"
              onClick={() => act('back')} />
          )}
          <span className="PlayerProfile__key">{data.key}</span>
          <span className={'PlayerProfile__status PlayerProfile__status--'
            + (now.online ? 'online' : data.status)}>
            {now.online ? 'Online' : (STATUS[data.status] || data.status)}
            {!now.online && !!data.left_ago && ', ' + data.left_ago + ' ago'}
          </span>
          {!!now.antag && (
            <span className={CHIP_BAD}>
              {now.antag}
            </span>
          )}
          {!!now.bot && (
            <span className="PlayerProfile__chip">bot</span>
          )}
          <span className="PlayerProfile__spacer" />
          <Button icon="sync" content="Refresh"
            onClick={() => act('refresh')} />
        </div>
        <div className="PlayerProfile__nowRow">
          {now.name
            ? (
              <span>
                <Icon name="user" mr={1} />
                <b>{now.name}</b>
                {now.job ? ', ' + now.job : ''}
                {now.state !== 'alive' ? ' (' + now.state + ')' : ''}
                {now.area ? ' in ' + now.area : ''}
              </span>
            )
            : (
              <span className="PlayerProfile__muted">
                {now.state === 'lobby' ? 'In the lobby' : 'No body'}
              </span>
            )}
          {!!data.open_ticket && (
            <a className="PlayerProfile__ticketLink"
              onClick={() => act('ticket', { id: data.open_ticket })}>
              <Icon name="question-circle" mr={0.5} />
              ticket #{data.open_ticket} open
            </a>
          )}
        </div>
        <div className="PlayerProfile__actRow">
          {!!now.has_mob && (
            <Fragment>
              <Button content="PP" onClick={() => act('pp')} />
              <Button content="VV" onClick={() => act('vv')} />
              <Button content="FLW" onClick={() => act('flw')} />
            </Fragment>
          )}
          {!!now.online && (
            <Button icon="envelope" content="PM" onClick={() => act('pm')} />
          )}
          <Button icon="search" content="Logs" onClick={() => act('logs')} />
          <Button icon="sticky-note" content="Notes"
            onClick={() => act('notes')} />
          <Button icon="plus" content="Note"
            onClick={() => act('add_note')} />
          <Button icon="gavel" content="Ban" color="bad"
            onClick={() => act('ban')} />
          <Button icon="list" content="Their bans"
            onClick={() => act('bans')} />
        </div>
        <div className="PlayerProfile__recordRow">
          <span>First seen <b>{data.first_seen || '?'}</b></span>
          <span>Last seen <b>{data.last_seen || '?'}</b></span>
          <span>
            <b>{data.connections || 0}</b> connection
            {data.connections === 1 ? '' : 's'}
          </span>
          {!!data.can_see_addresses && (
            <span className="PlayerProfile__muted">
              IP {(data.ips || []).slice(0, 3).join(', ') || '?'}
              {' '}&middot; CID {(data.cids || []).slice(0, 3).join(', ')
                || '?'}
            </span>
          )}
        </div>
      </div>
      <div className="PlayerProfile__body">
        <div className="PlayerProfile__col">
          <Section title="Other keys" count={alts.length}>
            {alts.length === 0 && <Empty text="None seen." />}
            {alts.map(alt => (
              <div key={alt.ckey} className="PlayerProfile__row">
                <a className="PlayerProfile__name"
                  onClick={() => act('profile', { ckey: alt.ckey })}>
                  {alt.key || alt.ckey}
                </a>
                <span className="PlayerProfile__muted">{alt.how}</span>
                {!!alt.online && (
                  <span className="PlayerProfile__chip">online</span>
                )}
                {!!alt.banned && (
                  <span className={CHIP_BAD}>
                    banned
                  </span>
                )}
              </div>
            ))}
          </Section>
          <Section title="Bans" count={bans.length}
            buttons={activeBans > 0 && (
              <span className={CHIP_BAD}>
                {activeBans} active
              </span>
            )}>
            {bans.length === 0 && <Empty text="No bans." />}
            {bans.map((ban, i) => (
              <div key={i} className={'PlayerProfile__card'
                + ' PlayerProfile__card--' + ban.status}>
                <div className="PlayerProfile__cardHead">
                  <b>{ban.server ? 'Server' : ban.roles.join(', ')}</b>
                  <span className="PlayerProfile__spacer" />
                  <span className="PlayerProfile__muted">
                    {ban.length}, {ban.status === 'active' && ban.left}
                    {ban.status !== 'active' && ban.status}
                  </span>
                </div>
                <div>{ban.reason}</div>
                <div className="PlayerProfile__muted PlayerProfile__small">
                  {ban.admin}, {ban.when}
                </div>
              </div>
            ))}
          </Section>
          <Section title="Notes" count={notes.length}>
            {notes.length === 0 && <Empty text="No notes." />}
            {notes.map((note, i) => (
              <div key={i} className="PlayerProfile__note">
                <span className={'PlayerProfile__sev PlayerProfile__sev--'
                  + (note.severity || 'none')} />
                <span className="PlayerProfile__muted">
                  {NOTE_KINDS[note.kind] || note.kind}:
                </span>
                {' '}{note.text}
                <div className="PlayerProfile__muted PlayerProfile__small">
                  {note.admin}, {note.when}
                  {note.severity && note.severity !== 'none'
                    && ' (' + note.severity + ')'}
                </div>
              </div>
            ))}
          </Section>
        </div>
        <div className="PlayerProfile__col">
          <Section title="This round">
            <div className="PlayerProfile__stats">
              <span><b>{counts.attacked || 0}</b> hits on others</span>
              <span><b>{counts.attacked_by || 0}</b> taken</span>
              <span><b>{counts.deaths || 0}</b> deaths</span>
              <span>
                <b>{counts.said || 0}</b>
                {counts.said === 1 ? ' line said' : ' lines said'}
              </span>
            </div>
            {(data.hit_people || []).length > 0 && (
              <div className="PlayerProfile__small">
                <span className="PlayerProfile__muted">Hit </span>
                {data.hit_people.join(', ')}
              </div>
            )}
            {(data.hit_by || []).length > 0 && (
              <div className="PlayerProfile__small">
                <span className="PlayerProfile__muted">Hit by </span>
                {data.hit_by.join(', ')}
              </div>
            )}
          </Section>
          <Section title="Tickets" count={tickets.length}>
            {tickets.length === 0 && <Empty text="No tickets." />}
            {tickets.map((t, i) => (
              <div key={i} className={ROW_TOP}>
                <span className="PlayerProfile__round">
                  {t.now ? 'now' : t.date || t.round_id}
                </span>
                <span className="PlayerProfile__grow">
                  {t.now
                    ? (
                      <a onClick={() => act('ticket', { id: t.id })}>
                        #{t.id} {t.title}
                      </a>
                    )
                    : '#' + t.id + ' ' + t.title}
                  <span className="PlayerProfile__muted PlayerProfile__small">
                    {!!t.closed_by && ' ' + t.outcome + ' by ' + t.closed_by}
                    {!t.closed_by && !!t.handled_by
                      && ' handled by ' + t.handled_by}
                  </span>
                </span>
                <span className={'PlayerProfile__chip PlayerProfile__chip--'
                  + (OUTCOME_TONES[t.outcome] || 'info')}>
                  {t.outcome}
                </span>
              </div>
            ))}
          </Section>
          <Section title="Rounds" count={rounds.length}>
            {rounds.length === 0 && <Empty text="None kept yet." />}
            {rounds.map((r, i) => (
              <div key={i} className="PlayerProfile__row">
                <span className="PlayerProfile__round">{r.date}</span>
                <span className="PlayerProfile__grow">
                  <b>{r.name}</b>{r.job ? ', ' + r.job : ''}
                </span>
                {!!r.antag && (
                  <span className={CHIP_BAD}>
                    {r.antag}
                  </span>
                )}
                <span className="PlayerProfile__muted">{r.end}</span>
              </div>
            ))}
          </Section>
        </div>
      </div>
    </div>
  );
};
