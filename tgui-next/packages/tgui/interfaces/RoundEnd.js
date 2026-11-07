import { useBackend } from '../backend';
import { clock } from './common/LobbyDesigns';

// hippie -- the round-end report as the boarding pass's paperwork. Data from
// hippiestation/code/modules/roundend/roundend_tgui.dm; the antagonist, law,
// goal and medal parts are the game's own HTML.

const OUTCOME_TONE = {
  Escaped: 'good',
  Survived: 'good',
  Marooned: 'warn',
  Died: 'bad',
  Lost: 'bad',
  Observed: 'quiet',
};

const percent = (part, whole) => (
  whole ? Math.round(100 * part / whole) + '%' : '-'
);

const Fact = props => (
  <div className="RoundEnd__fact">
    <div className="LobbyPass__label">{props.label}</div>
    <div className="LobbyPass__value">{props.value}</div>
  </div>
);

const Card = props => (
  <div className="RoundEnd__card">
    <div className="RoundEnd__cardTitle">{props.title}</div>
    {props.children}
  </div>
);

const Html = props => (
  <div
    className="RoundEnd__html"
    // The game's own report: names, objectives, laws (code/__HELPERS/
    // roundend.dm and each antagonist's roundend_report())
    // eslint-disable-next-line react/no-danger
    dangerouslySetInnerHTML={{ __html: props.html }} />
);

// / The roll call: departments in three columns, each to the shortest so far
const RollCall = props => {
  const { crew } = props;
  const columns = [[], [], []];
  const heights = [0, 0, 0];
  crew.forEach(dept => {
    let best = 0;
    for (let i = 1; i < columns.length; i++) {
      if (heights[i] < heights[best]) {
        best = i;
      }
    }
    columns[best].push(dept);
    heights[best] += dept.people.length + 2;
  });
  return (
    <div className="LateJoinPass__columns">
      {columns.map((column, i) => (
        <div key={i} className="LateJoinPass__column">
          {column.map(dept => (
            <div key={dept.name} className="RoundEnd__dept">
              <div className="RoundEnd__deptName">{dept.name}</div>
              {dept.people.map((person, j) => (
                <div key={j} className="RoundEnd__person">
                  <div className="RoundEnd__who">
                    <div className="RoundEnd__name">{person.name}</div>
                    <div className="RoundEnd__job">
                      {person.job}
                      {!!person.antag && (
                        <span className="RoundEnd__antag">{person.antag}</span>
                      )}
                    </div>
                  </div>
                  <span className={'RoundEnd__outcome RoundEnd__outcome--'
                    + (OUTCOME_TONE[person.outcome] || 'quiet')}>
                    {person.outcome}
                  </span>
                </div>
              ))}
            </div>
          ))}
        </div>
      ))}
    </div>
  );
};

export const RoundEnd = props => {
  const { data } = useBackend(props);
  const personal = data.personal || { outcome: 'Observed' };
  const sections = data.sections || [];
  const crew = data.crew || [];
  const death = data.first_death;
  const tone = OUTCOME_TONE[personal.outcome] || 'quiet';
  return (
    <div className={'RoundEnd' + (data.dark ? ' Pass--dark' : '')}>
      <div className="RoundEnd__head">
        <div className="LobbyPass__band">
          <span className="LobbyPass__logo">NT</span>
          <span>Shift Report</span>
          {!!data.round_id && (
            <span className="LobbyPass__class">
              {'Shift ' + data.round_id}
            </span>
          )}
        </div>
        <div className="RoundEnd__top">
          <div className="RoundEnd__station">
            <div className="LobbyPass__label">Station</div>
            <div className="RoundEnd__stationName">{data.station}</div>
            {!!personal.name && (
              <div className="RoundEnd__you">
                {personal.name}
                {personal.job ? ', ' + personal.job : ''}
              </div>
            )}
          </div>
          <div
            key={personal.outcome}
            className={'RoundEnd__stamp RoundEnd__stamp--' + tone}>
            {personal.outcome}
          </div>
        </div>
        <div className="RoundEnd__facts">
          <Fact label="Duration" value={clock(data.duration || 0)} />
          <Fact
            label="Integrity"
            value={data.nuked ? 'Destroyed' : data.integrity + '%'} />
          <Fact label="Crew" value={data.population} />
          {!!data.evacuated && (
            <Fact
              label="Escaped"
              value={data.escapees + ' (' + percent(data.escapees,
                data.population) + ')'} />
          )}
          <Fact
            label="Survived"
            value={data.survivors + ' (' + percent(data.survivors,
              data.population) + ')'} />
          {data.threat !== undefined && (
            <Fact label="Threat" value={data.threat} />
          )}
          <Fact label="Gate" value={data.map} />
        </div>
        <div className="RoundEnd__death">
          {death ? (
            <span>
              <span className="LobbyPass__label">First death </span>
              <b>{death.name}</b>, {death.role}, in {death.area}
              {!!death.words && (
                <span className="RoundEnd__words">
                  {' — “' + death.words + '”'}
                </span>
              )}
            </span>
          ) : (
            <span className="LobbyPass__label">Nobody died this shift</span>
          )}
        </div>
      </div>
      {sections.map(section => (
        <Card key={section.title} title={section.title}>
          <Html html={section.html} />
        </Card>
      ))}
      {crew.length > 0 && (
        <Card title="Roll Call">
          <RollCall crew={crew} />
        </Card>
      )}
    </div>
  );
};
