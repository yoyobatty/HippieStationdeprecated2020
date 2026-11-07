import { Component } from 'inferno';
import { useBackend } from '../backend';
import { Icon } from '../components';
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
      <div className="AdminHub__tabs">
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
