import { Component } from 'inferno';
import { useBackend } from '../backend';
import { Icon, Input } from '../components';

// hippie -- the ghost's Orbit menu: everything to orbit, in tabs, each with
// a dot for what it is and a person's job under their name. Data from
// hippiestation/code/modules/mob/dead/observer/orbit_menu.dm (built on open
// and on Refresh).

// [data key, tab, dot]
const SECTIONS = [
  ['antagonists', 'Antagonists', 'antag'],
  ['alive', 'Alive', 'alive'],
  ['npcs', 'Bots/NPCs', 'npc'],
  ['misc', 'Points', 'poi'],
  ['dead', 'Dead', 'dead'],
  ['ghosts', 'Ghosts', 'ghost'],
];

export class Orbit extends Component {
  constructor() {
    super();
    this.state = { tab: 'all', search: '' };
  }

  render() {
    const { act, data } = useBackend(this.props);
    const { tab, search } = this.state;
    const needle = search.toLowerCase();
    const matches = entry => !needle
      || (entry.name + ' ' + (entry.job || '') + ' ' + (entry.antag || ''))
        .toLowerCase().indexOf(needle) >= 0;
    const present = SECTIONS
      .filter(section => (data[section[0]] || []).length);
    const shown = present
      .filter(section => tab === 'all' || tab === section[0]);
    return (
      <div className="Orbit">
        <div className="Orbit__bar">
          <Icon name="search" mr={1} />
          <Input
            className="Orbit__search"
            placeholder="Search"
            value={search}
            onInput={(e, value) => this.setState({ search: value })} />
          <div className="Orbit__refresh" onClick={() => act('refresh')}>
            <Icon name="sync" />
          </div>
        </div>
        <div className="Orbit__tabs">
          <div
            className={'Orbit__tab' + (tab === 'all' ? ' Orbit__tab--on' : '')}
            onClick={() => this.setState({ tab: 'all' })}>
            All
          </div>
          {present.map(section => (
            <div
              key={section[0]}
              className={'Orbit__tab'
                + (tab === section[0] ? ' Orbit__tab--on' : '')}
              onClick={() => this.setState({ tab: section[0] })}>
              <span className={'Orbit__dot Orbit__dot--' + section[2]} />
              {section[1]}
              <span className="Orbit__count">{data[section[0]].length}</span>
            </div>
          ))}
        </div>
        <div className="Orbit__list">
          {shown.map(section => {
            const entries = data[section[0]].filter(matches);
            if (!entries.length) {
              return null;
            }
            return (
              <div key={section[0]} className="Orbit__group">
                {tab === 'all' && (
                  <div className="Orbit__groupTitle">{section[1]}</div>
                )}
                <div className="Orbit__entries">
                  {entries.map(entry => (
                    <div
                      key={entry.ref}
                      className="Orbit__entry"
                      title={entry.antag}
                      onClick={() => act('orbit', { ref: entry.ref })}>
                      <span className={'Orbit__dot Orbit__dot--'
                        + section[2]} />
                      <div className="Orbit__who">
                        <div className="Orbit__name">{entry.name}</div>
                        {!!(entry.job || entry.antag) && (
                          <div className="Orbit__job">
                            {entry.antag || entry.job}
                          </div>
                        )}
                      </div>
                    </div>
                  ))}
                </div>
              </div>
            );
          })}
        </div>
      </div>
    );
  }
}
