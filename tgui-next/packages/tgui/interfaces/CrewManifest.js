import { Component } from 'inferno';
import { useBackend } from '../backend';
import { Icon } from '../components';

// hippie -- the crew manifest (the lobby, ghosts, the AI and pAI): the crew
// by department, heads first and starred, with a search. Data from
// hippiestation/code/datums/manifest_notes_tgui.dm.

const DEPT_ICONS = {
  Command: 'star',
  Security: 'shield-alt',
  Engineering: 'wrench',
  Medical: 'medkit',
  Science: 'flask',
  Supply: 'box',
  Service: 'concierge-bell',
  Silicon: 'robot',
  Other: 'user',
};

export class CrewManifest extends Component {
  constructor() {
    super();
    this.state = { search: '' };
  }

  render() {
    const { data } = useBackend(this.props);
    const query = this.state.search.toLowerCase();
    const depts = (data.departments || []).map(dept => {
      const crew = dept.crew.filter(person => !query
        || person.name.toLowerCase().includes(query)
        || person.rank.toLowerCase().includes(query));
      crew.sort((a, b) => (b.head ? 1 : 0) - (a.head ? 1 : 0));
      return { name: dept.name, crew };
    }).filter(dept => dept.crew.length);
    return (
      <div className="Manifest">
        <div className="Manifest__head">
          <div className="Manifest__title">
            <Icon name="users" /> Crew manifest
            <span className="Manifest__total">{data.total} aboard</span>
          </div>
          <input
            className="Manifest__search"
            placeholder="Search names and jobs..."
            value={this.state.search}
            onInput={e => this.setState({ search: e.target.value })} />
        </div>
        <div className="Manifest__list">
          {depts.length === 0 && (
            <div className="Manifest__none">
              {query ? 'Nobody matches that.' : 'Nobody on the manifest yet.'}
            </div>
          )}
          {depts.map(dept => (
            <div
              key={dept.name}
              className={'Manifest__dept Manifest__dept--'
                + dept.name.toLowerCase()}>
              <div className="Manifest__deptHead">
                <Icon name={DEPT_ICONS[dept.name] || 'user'} />
                {' '}{dept.name}
                <span className="Manifest__deptCount">{dept.crew.length}</span>
              </div>
              {dept.crew.map(person => (
                <div
                  key={person.name + person.rank}
                  className={'Manifest__row'
                    + (person.head ? ' Manifest__row--head' : '')}>
                  <span className="Manifest__name">
                    {!!person.head && <Icon name="star" mr={0.5} />}
                    {person.name}
                  </span>
                  <span className="Manifest__rank">{person.rank}</span>
                </div>
              ))}
            </div>
          ))}
        </div>
      </div>
    );
  }
}
