import { Component } from 'inferno';
import { useBackend } from '../backend';
import { Icon } from '../components';
import { closePlayerMenus } from './common/PlayerLink';
import { AdminAlerts } from './AdminAlerts';
import { AdminFind } from './AdminFind';
import { BanWindow } from './BanWindow';
import { LogSearch } from './LogSearch';
import { PlayerProfile } from './PlayerProfile';
import { Questions } from './Questions';
import { Tickets } from './Tickets';

// hippie -- the admin hub: the admin tools as tabs across the top, with
// counts, and a player's profile as a panel at the right. Each tab is the
// same tool its own window shows: the server hands over that tool's data,
// and passes the tab's actions to it (the profile panel's go with "p:" in
// front). Data and actions from hippiestation/code/modules/admin/admin_hub.dm.

const TABS = [
  ['tickets', 'Tickets', 'question-circle', Tickets],
  ['questions', 'Questions', 'comments', Questions],
  ['alerts', 'Alerts', 'bell', AdminAlerts],
  ['logs', 'Logs', 'stream', LogSearch],
  ['find', 'Find', 'search-location', AdminFind],
  ['bans', 'Bans', 'gavel', BanWindow],
];

// The search box (the user's ruling: a dropdown as you type): what's typed
// goes to the server a moment after the last key; the results come back
// grouped, and arrows and Enter, or a click, go to one
class HubSearch extends Component {
  constructor() {
    super();
    this.state = { text: '', picked: 0, open: false };
    this.timer = null;
    this.onDocDown = e => {
      if (this.box && !this.box.contains(e.target)) {
        this.setState({ open: false });
      }
    };
  }

  componentDidMount() {
    document.addEventListener('mousedown', this.onDocDown);
  }

  componentWillUnmount() {
    document.removeEventListener('mousedown', this.onDocDown);
    clearTimeout(this.timer);
  }

  typed(text) {
    const { act } = this.props;
    this.setState({ text, picked: 0, open: true });
    clearTimeout(this.timer);
    this.timer = setTimeout(() => {
      act(text.trim() ? 'hub_search' : 'hub_search_clear', { text });
    }, 250);
  }

  go(item) {
    const { act } = this.props;
    act('hub_go', { kind: item.kind, id: item.id });
    this.setState({ text: '', open: false, picked: 0 });
  }

  render() {
    const { search } = this.props;
    const { text, picked, open } = this.state;
    const answered = !!search && search.text === text.trim();
    const groups = answered
      ? (search.results || []).filter(g => g.items.length > 0)
      : [];
    const flat = [];
    groups.forEach(g => g.items.forEach(item => flat.push(item)));
    const current = Math.min(picked, Math.max(0, flat.length - 1));
    let n = 0;
    return (
      <div className="AdminHub__search"
        ref={el => {
          this.box = el;
        }}>
        <Icon name="search" className="AdminHub__searchIcon" />
        <input
          className="AdminHub__searchInput"
          value={text}
          placeholder="Player, ticket #, place, words..."
          onInput={e => this.typed(e.target.value)}
          onFocus={() => this.setState({ open: true })}
          onKeyDown={e => {
            if (e.keyCode === 40) {
              e.preventDefault();
              this.setState({ picked: Math.min(current + 1, flat.length - 1) });
            }
            else if (e.keyCode === 38) {
              e.preventDefault();
              this.setState({ picked: Math.max(current - 1, 0) });
            }
            else if (e.keyCode === 13 && flat[current]) {
              e.preventDefault();
              this.go(flat[current]);
            }
            else if (e.keyCode === 27) {
              this.setState({ open: false });
            }
          }} />
        {open && text.trim().length > 0 && (
          <div className="AdminHub__results">
            {groups.length === 0 && (
              <div className="AdminHub__resultsEmpty">
                {answered ? 'Nothing found.' : 'Looking...'}
              </div>
            )}
            {groups.map(g => (
              <div key={g.name}>
                <div className="AdminHub__resultsHead">{g.name}</div>
                {g.items.map(item => {
                  const index = n++;
                  return (
                    <div key={item.kind + item.id}
                      className={'AdminHub__result'
                        + (index === current ? ' AdminHub__result--on' : '')}
                      onMouseEnter={() => this.setState({ picked: index })}
                      onClick={() => this.go(item)}>
                      <span className="AdminHub__resultLabel">
                        {item.label}
                      </span>
                      {!!item.hint && (
                        <span className="AdminHub__resultHint">
                          {item.hint}
                        </span>
                      )}
                    </div>
                  );
                })}
              </div>
            ))}
          </div>
        )}
      </div>
    );
  }
}

// The keys (the user's ruling: single keys, Gmail style), only while not
// typing in a box. On the window, capturing, ahead of the passthrough to the
// game (hotkeys.js), which leaves a key alone once it's been handled.
const KEYS_HELP = 'Keys (when not typing): J/K next/previous ticket, '
  + 'R reply, N note, C claim, Shift+R resolve, Shift+I IC issue, '
  + '/ search, 1-6 tabs, B back, Esc leave a box or close a menu';

const focusBox = (mode, selector) => {
  if (mode) {
    const tab = Array.prototype.slice
      .call(document.querySelectorAll('.Tickets__mode'))
      .find(el => el.textContent.trim().indexOf(mode) === 0);
    if (tab) {
      tab.click();
    }
  }
  setTimeout(() => {
    const box = document.querySelector(selector);
    if (box) {
      box.focus();
    }
  }, 30);
};

class HubKeys extends Component {
  componentDidMount() {
    this.handled = {};
    this.down = e => this.onKey(e);
    this.up = e => {
      if (this.handled[e.keyCode]) {
        e.preventDefault();
        delete this.handled[e.keyCode];
      }
    };
    window.addEventListener('keydown', this.down, true);
    window.addEventListener('keyup', this.up, true);
  }

  componentWillUnmount() {
    window.removeEventListener('keydown', this.down, true);
    window.removeEventListener('keyup', this.up, true);
  }

  onKey(e) {
    const { act, data } = this.props;
    const target = e.target && e.target.localName;
    const typing = target === 'input' || target === 'textarea';
    if (e.keyCode === 27) {
      closePlayerMenus();
      if (typing) {
        e.target.blur();
      }
      return;
    }
    if (typing || e.ctrlKey || e.altKey || e.metaKey) {
      return;
    }
    const tool = data.tool || {};
    const ticket = data.tab === 'tickets' ? tool.ticket : null;
    const open = !!ticket && ticket.state === 1;
    const key = e.key;
    let done = true;
    if (key === 'j' && data.tab === 'tickets') {
      act('step', { dir: 1 });
    }
    else if (key === 'k' && data.tab === 'tickets') {
      act('step', { dir: -1 });
    }
    else if (key === 'r' && open) {
      focusBox('Reply', '.Tickets__textarea');
    }
    else if (key === 'n' && ticket) {
      focusBox('Note', '.Tickets__textarea');
    }
    else if (key === 'c' && open) {
      act(ticket.mine ? 'unclaim' : 'claim');
    }
    else if (key === 'R' && open) {
      act('resolve');
    }
    else if (key === 'I' && open) {
      act('icissue');
    }
    else if (key === '/') {
      focusBox(null, '.AdminHub__searchInput');
    }
    else if (key === 'b' && data.can_back) {
      act('hub_back');
    }
    else if (key >= '1' && key <= String(TABS.length)) {
      act('hub_tab', { tab: TABS[Number(key) - 1][0] });
    }
    else {
      done = false;
    }
    if (done) {
      e.preventDefault();
      e.stopPropagation();
      this.handled[e.keyCode] = true;
    }
  }

  render() {
    return null;
  }
}

// Recent: players and tickets looked at lately, newest first
class HubRecent extends Component {
  constructor() {
    super();
    this.state = { open: false };
    this.onDocDown = e => {
      if (this.box && !this.box.contains(e.target)) {
        this.setState({ open: false });
      }
    };
  }

  componentDidMount() {
    document.addEventListener('mousedown', this.onDocDown);
  }

  componentWillUnmount() {
    document.removeEventListener('mousedown', this.onDocDown);
  }

  render() {
    const { act, recent } = this.props;
    const { open } = this.state;
    return (
      <span className="AdminHub__recent"
        ref={el => {
          this.box = el;
        }}>
        <span className="AdminHub__navButton"
          title="Players and tickets you looked at lately"
          onClick={() => this.setState({ open: !open })}>
          <Icon name="history" mr={0.5} />Recent
        </span>
        {open && (
          <div className="AdminHub__results AdminHub__results--left">
            {recent.length === 0 && (
              <div className="AdminHub__resultsEmpty">Nothing yet.</div>
            )}
            {recent.map((item, i) => (
              <div key={item.kind + item.id}
                className="AdminHub__result"
                onClick={() => {
                  act('hub_recent', { index: i + 1 });
                  this.setState({ open: false });
                }}>
                <Icon name={item.kind === 'player' ? 'user' : 'question-circle'}
                  mr={1} />
                <span className="AdminHub__resultLabel">{item.label}</span>
              </div>
            ))}
          </div>
        )}
      </span>
    );
  }
}

export const AdminHub = props => {
  const { act, data } = useBackend(props);
  const counts = data.counts || {};
  const current = TABS.find(t => t[0] === data.tab) || TABS[0];
  const Tool = current[3];
  // a tool's own props: the same window, its own part of the data
  const withData = part => ({
    ...props,
    state: { ...props.state, data: part || {} },
  });
  return (
    <div className="AdminHub">
      <HubKeys act={act} data={data} />
      <div className="AdminHub__tabs">
        <span
          className={'AdminHub__navButton'
            + (data.can_back ? '' : ' AdminHub__navButton--off')}
          title="Back (B)"
          onClick={() => data.can_back && act('hub_back')}>
          <Icon name="arrow-left" />
        </span>
        <HubRecent act={act} recent={data.recent || []} />
        {TABS.map(t => {
          const c = counts[t[0]];
          return (
            <span key={t[0]}
              className={'AdminHub__tab'
                + (t[0] === current[0] ? ' AdminHub__tab--on' : '')}
              title={c ? c.title : ''}
              onClick={() => act('hub_tab', { tab: t[0] })}>
              <Icon name={t[2]} mr={1} />
              {t[1]}
              {!!c && c.count > 0 && (
                <span className={'AdminHub__count'
                  + (c.hot > 0 ? ' AdminHub__count--hot' : '')}>
                  {c.count}
                </span>
              )}
            </span>
          );
        })}
        <span className="AdminHub__spacer" />
        <span className="AdminHub__keys" title={KEYS_HELP}>
          <Icon name="keyboard" />
        </span>
        <HubSearch act={act} search={data.search} />
      </div>
      <div className="AdminHub__body">
        <div className="AdminHub__tool">
          <Tool key={current[0]} {...withData(data.tool)} />
        </div>
        {!!data.profile && (
          <div className="AdminHub__side">
            <span className="AdminHub__close" title="Close the profile"
              onClick={() => act('hub_profile_close')}>
              <Icon name="times" />
            </span>
            <PlayerProfile {...withData(data.profile)} actPrefix="p:" compact />
          </div>
        )}
      </div>
    </div>
  );
};
