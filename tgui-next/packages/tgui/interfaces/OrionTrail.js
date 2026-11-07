import { useBackend } from '../backend';
import { Icon } from '../components';

// hippie -- the Orion Trail as a voyage: the route with the ship on it, the
// screen (a stop, an event, the spaceport, the title, game over), supplies
// and crew. The game is unchanged (code/game/machinery/computer/arcade.dm):
// the state comes from ui_data in hippiestation/code/game/machinery/
// computer/arcade_tgui.dm, and an event's words and choices from the game's
// own page for it. Every choice goes back as a "link", as the game's Topic()
// takes it.

// "byond://?src=...;continue=1" -> { continue: '1' }
const linkParams = href => {
  const params = {};
  const query = href.substring(href.indexOf('?') + 1);
  for (let pair of query.split(/[;&]/)) {
    const eq = pair.indexOf('=');
    if (eq > 0) {
      params[decodeURIComponent(pair.substring(0, eq))]
        = decodeURIComponent(pair.substring(eq + 1));
    }
  }
  delete params.src;
  return params;
};

// The game's page for an event: its title, its words, its choices
const readScreen = html => {
  const root = document.createElement('div');
  root.innerHTML = html || '';
  const heading = root.querySelector('h1, h2');
  const title = heading ? heading.textContent.trim() : '';
  const choices = [];
  const links = root.querySelectorAll('a');
  for (let i = 0; i < links.length; i++) {
    const params = linkParams(links[i].getAttribute('href') || '');
    if (!params.close) {
      choices.push({ label: links[i].textContent.trim(), params });
    }
  }
  const drop = root.querySelectorAll('h1, h2, p, center');
  for (let i = 0; i < drop.length; i++) {
    if (drop[i].parentNode) {
      drop[i].parentNode.removeChild(drop[i]);
    }
  }
  const text = root.innerHTML
    .replace(/^(\s*<br\s*\/?>\s*)+/i, '')
    .replace(/(\s*<br\s*\/?>\s*)+$/i, '');
  return { title, text, choices };
};

const Html = props => (
  // eslint-disable-next-line react/no-danger
  <div className={props.className} dangerouslySetInnerHTML={{
    __html: props.html,
  }} />
);

const Choice = props => {
  const { label, params, act, danger, disabled, note } = props;
  return (
    <div
      className={'Orion__choice'
        + (danger ? ' Orion__choice--danger' : '')
        + (disabled ? ' Orion__choice--disabled' : '')}
      onClick={disabled ? null : () => act('link', params)}>
      {label}
      {!!note && <span className="Orion__choiceNote">{note}</span>}
    </div>
  );
};

// The route: every stop a light, the ship at the one you're at
const Route = props => {
  const { stops = [], turn, phase } = props;
  const sailing = phase !== 'start' && phase !== 'gameover';
  return (
    <div className="Orion__route">
      <div className="Orion__routeLine" />
      {stops.map((stop, i) => {
        const index = i + 1;
        const here = sailing && index === turn;
        const passed = sailing && index < turn;
        return (
          <div
            key={stop}
            title={stop}
            className={'Orion__stop'
              + (passed ? ' Orion__stop--passed' : '')
              + (here ? ' Orion__stop--here' : '')
              + (index === stops.length ? ' Orion__stop--goal' : '')}>
            {here ? <Icon name="space-shuttle" /> : <div />}
          </div>
        );
      })}
    </div>
  );
};

const Gauge = props => {
  const { label, value, icon } = props;
  const top = Math.max(100, value);
  const low = value < 20;
  return (
    <div className={'Orion__gauge' + (low ? ' Orion__gauge--low' : '')}>
      <div className="Orion__gaugeLabel">
        <Icon name={icon} /> {label}
        <span className="Orion__gaugeValue">{value}</span>
      </div>
      <div className="Orion__gaugeTrack">
        <div
          className="Orion__gaugeFill"
          style={{ width: Math.max(0, value / top * 100) + '%' }} />
      </div>
    </div>
  );
};

const Supplies = props => {
  const { data } = props;
  const crew = data.crew || [];
  return (
    <div className="Orion__supplies">
      <div className="Orion__gauges">
        <Gauge label="Food" icon="drumstick-bite" value={data.food} />
        <Gauge label="Fuel" icon="gas-pump" value={data.fuel} />
      </div>
      <div className="Orion__parts">
        <span title="Engine parts">
          <Icon name="cog" /> {data.engine}
        </span>
        <span title="Hull plates">
          <Icon name="shield-alt" /> {data.hull}
        </span>
        <span title="Spare electronics">
          <Icon name="microchip" /> {data.electronics}
        </span>
      </div>
      <div className="Orion__crew">
        {crew.map((name, i) => (
          <span key={i} className="Orion__crewmember">
            <Icon name="user-astronaut" /> {name}
          </span>
        ))}
      </div>
    </div>
  );
};

const TitleScreen = props => {
  const { act, data } = props;
  return (
    <div className="Orion__title">
      <div className="Orion__logo">THE ORION TRAIL</div>
      <div className="Orion__tagline">
        {data.emagged
          ? 'Realism Edition. Try not to die.'
          : 'Experience the journey of your ancestors!'}
      </div>
      <div className="Orion__titleShip">
        <Icon name="space-shuttle" />
      </div>
      <Choice label="New Game" params={{ newgame: 1 }} act={act} />
    </div>
  );
};

const TravelScreen = props => {
  const { act, data } = props;
  const blackHole = data.turn === 7;
  return (
    <div className="Orion__screen">
      <div className="Orion__stopName">{data.stops[data.turn - 1]}</div>
      <div className="Orion__stopCount">
        Stop {data.turn} of {data.stops.length}
      </div>
      <div className="Orion__text">{data.blurb}</div>
      <div className="Orion__choices">
        {blackHole ? (
          <Choice
            label="Go Around"
            note="3x supplies"
            params={{ pastblack: 1 }}
            act={act} />
        ) : null}
        <Choice
          label={blackHole ? 'Fly Through' : 'Continue'}
          params={blackHole ? { blackhole: 1 } : { continue: 1 }}
          act={act} />
        <Choice
          label="Kill a Crewmember"
          danger
          params={{ killcrew: 1 }}
          act={act} />
      </div>
    </div>
  );
};

const EventScreen = props => {
  const { act, data, over } = props;
  const screen = readScreen(data.screen);
  return (
    <div className={'Orion__screen' + (over ? ' Orion__screen--over' : '')}>
      <div className="Orion__eventName">
        {screen.title === 'BlackHole' ? 'Black Hole' : screen.title}
      </div>
      <Html className="Orion__text" html={screen.text} />
      <div className="Orion__choices">
        {screen.choices.map(choice => (
          <Choice
            key={choice.label}
            label={choice.label}
            params={choice.params}
            danger={!!choice.params.killcrew}
            act={act} />
        ))}
      </div>
    </div>
  );
};

const Shop = props => {
  const { act, data } = props;
  const { food, fuel, raided, last_action } = data;
  const crew = (data.crew || []).length;
  const pity = /The traders of the spaceport take pity[^<]*/
    .exec(data.screen || '');
  if (raided) {
    return (
      <div className="Orion__screen">
        <div className="Orion__eventName">Spaceport</div>
        <div className="Orion__text">
          The spaceport is on high alert. You have been barred from docking
          after your raid.
        </div>
        {!!last_action && (
          <div className="Orion__news">{last_action}</div>
        )}
        <div className="Orion__choices">
          <Choice
            label="Depart"
            params={{ leave_spaceport: 1 }}
            act={act} />
        </div>
      </div>
    );
  }
  return (
    <div className="Orion__screen">
      <div className="Orion__eventName">Spaceport</div>
      <div className="Orion__text">
        A spaceport, a lucky find: home to travellers who never reached
        Orion, but found another home.
      </div>
      {!!pity && <div className="Orion__news">{pity[0]}</div>}
      {!!last_action && <div className="Orion__news">{last_action}</div>}
      <div className="Orion__shop">
        <div className="Orion__shopGroup">Crew</div>
        <Choice
          label="Hire"
          note="-10 fuel, -10 food"
          disabled={food < 10 || fuel < 10}
          params={{ buycrew: 1 }}
          act={act} />
        <Choice
          label="Sell"
          note="+7 fuel, +7 food"
          disabled={crew <= 1}
          params={{ sellcrew: 1 }}
          act={act} />
        <div className="Orion__shopGroup">Parts</div>
        <Choice
          label="Engine parts"
          note="-5 fuel"
          disabled={fuel <= 5}
          params={{ buyparts: 1 }}
          act={act} />
        <Choice
          label="Hull plates"
          note="-5 fuel"
          disabled={fuel <= 5}
          params={{ buyparts: 2 }}
          act={act} />
        <Choice
          label="Electronics"
          note="-5 fuel"
          disabled={fuel <= 5}
          params={{ buyparts: 3 }}
          act={act} />
        <div className="Orion__shopGroup">Trade</div>
        <Choice
          label="Fuel for food"
          note="-5 fuel, +5 food"
          disabled={fuel <= 5}
          params={{ trade: 1 }}
          act={act} />
        <Choice
          label="Food for fuel"
          note="-5 food, +5 fuel"
          disabled={food <= 5}
          params={{ trade: 2 }}
          act={act} />
      </div>
      <div className="Orion__choices">
        <Choice
          label="Raid the Spaceport"
          danger
          params={{ raid_spaceport: 1 }}
          act={act} />
        <Choice
          label="Depart"
          params={{ leave_spaceport: 1 }}
          act={act} />
      </div>
    </div>
  );
};

export const ArcadeOrion = props => {
  const { act, data } = useBackend(props);
  const { phase, emagged } = data;
  let screen;
  if (phase === 'travel') {
    screen = <TravelScreen act={act} data={data} />;
  } else if (phase === 'event') {
    screen = <EventScreen act={act} data={data} />;
  } else if (phase === 'market') {
    screen = <Shop act={act} data={data} />;
  } else if (phase === 'gameover') {
    screen = <EventScreen act={act} data={data} over />;
  } else {
    screen = <TitleScreen act={act} data={data} />;
  }
  const sailing = phase !== 'start';
  return (
    <div className={'Orion' + (emagged ? ' Orion--emagged' : '')}>
      {sailing && (
        <Route stops={data.stops} turn={data.turn} phase={phase} />
      )}
      <div className="Orion__main">
        {screen}
      </div>
      {sailing && phase !== 'gameover' && <Supplies data={data} />}
    </div>
  );
};
