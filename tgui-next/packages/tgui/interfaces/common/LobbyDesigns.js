import { Fragment } from 'inferno';
import { Icon } from '../../components';

// hippie -- the lobby's looks (Lobby.js picks one): a hologram HUD, a
// boarding pass, a departures board and a green-screen terminal. All take
// the same data and send the same actions.

export const NOT_READY = 0;
export const READY = 1;
export const OBSERVE = 2;

const pad = n => (n < 10 ? '0' : '') + n;

export const clock = secs => {
  const h = Math.floor(secs / 3600);
  const m = Math.floor(secs / 60) % 60;
  const s = secs % 60;
  return (h ? h + ':' + pad(m) : m) + ':' + pad(s);
};

// / The big time: to the start before the round, the round's length after
const bigTime = data => {
  if (data.pregame) {
    if (data.startup || data.delayed) {
      return '--:--';
    }
    return clock(data.time_left || 0);
  }
  return clock(data.round_time || 0);
};

const roundStatus = data => {
  if (data.startup) {
    return 'Initializing';
  }
  if (data.pregame) {
    return data.delayed ? 'Delayed' : 'Boarding';
  }
  if (data.setting_up) {
    return 'Departing';
  }
  if (data.ended) {
    return 'Round over';
  }
  return data.evac || 'In progress';
};

const statusGood = data => !data.delayed && !data.ended && !data.evac;

const joinText = data => {
  if (data.ended) {
    return 'Round over';
  }
  if (data.queue) {
    return 'Queued (' + data.queue + ')';
  }
  return 'Join Game';
};

const headcount = data => (data.pregame ? data.players : data.crew);

const Portrait = props => {
  const { data } = props;
  if (!data.portrait) {
    return null;
  }
  return <img src={data.portrait} />;
};

// / A clickable box: a plain div so each look styles it its own way
const Btn = props => {
  const { className, on, disabled, onClick, children } = props;
  const base = className.split(' ')[0];
  return (
    <div
      className={className
        + (on ? ' ' + base + '--on' : '')
        + (disabled ? ' ' + base + '--disabled' : '')}
      onClick={() => !disabled && onClick()}>
      {children}
    </div>
  );
};

// / What each look needs to act
const actions = (act, data) => ({
  setup: () => act('setup'),
  ready: value => act('ready', { value }),
  toggle: () => act('ready', {
    value: data.ready === READY ? NOT_READY : READY,
  }),
  join: () => act('join'),
  manifest: () => act('manifest'),
  observe: () => act('ready', { value: OBSERVE }),
  polls: () => act('polls'),
});

// 1. Hologram HUD

const HudRing = props => {
  const { fraction, children } = props;
  const r = 54;
  const c = 2 * Math.PI * r;
  return (
    <div className="LobbyHud__ring">
      <svg viewBox="0 0 128 128">
        <circle className="LobbyHud__ringSpin" cx="64" cy="64" r="61" />
        <circle className="LobbyHud__ringTrack" cx="64" cy="64" r={r} />
        <circle
          className="LobbyHud__ringFill"
          cx="64"
          cy="64"
          r={r}
          strokeDasharray={c}
          strokeDashoffset={c * (1 - fraction)}
          transform="rotate(-90 64 64)" />
      </svg>
      <div className="LobbyHud__ringText">{children}</div>
    </div>
  );
};

const HudStat = props => (
  <div className="LobbyHud__stat">
    <div className="LobbyHud__statLabel">{props.label}</div>
    <div className="LobbyHud__statValue">{props.value}</div>
  </div>
);

export const LobbyHud = props => {
  const { data } = props;
  const a = actions(props.act, data);
  let fraction = 1;
  if (data.pregame) {
    fraction = data.countdown
      ? Math.min(1, (data.time_left || 0) / data.countdown)
      : 0;
  }
  return (
    <div className="LobbyHud">
      <div className="LobbyHud__grid" />
      <div className="LobbyHud__header">
        <div className="LobbyHud__station">{data.station}</div>
        <div className="LobbyHud__sub">
          {data.map}{data.round_id ? ' · Round ' + data.round_id : ''}
        </div>
      </div>
      <div className="LobbyHud__middle">
        <div className="LobbyHud__holo">
          <div className="LobbyHud__beam" />
          <div className="LobbyHud__holoImg">
            <Portrait data={data} />
          </div>
          <div className="LobbyHud__projector" />
        </div>
        <HudRing fraction={fraction}>
          <div className="LobbyHud__time">{bigTime(data)}</div>
          <div className="LobbyHud__timeLabel">
            {data.pregame ? 'Shift start' : 'Shift time'}
          </div>
        </HudRing>
      </div>
      <div className="LobbyHud__ident">
        <div className="LobbyHud__name">{data.character || 'Unknown'}</div>
        <div className="LobbyHud__job">{data.job || 'No assignment'}</div>
      </div>
      <div className="LobbyHud__stats">
        <HudStat label="Status" value={roundStatus(data)} />
        <HudStat
          label={data.pregame ? 'Players' : 'Crew'}
          value={headcount(data)} />
        {data.players_ready !== undefined && !!data.pregame && (
          <HudStat label="Ready" value={data.players_ready} />
        )}
      </div>
      {data.pregame ? (
        <Btn
          className="LobbyHud__btn LobbyHud__big"
          on={data.ready === READY}
          onClick={() => a.toggle()}>
          {data.ready === READY ? 'Ready' : 'Not Ready'}
        </Btn>
      ) : (
        <Btn
          className="LobbyHud__btn LobbyHud__big"
          on={!data.ended}
          disabled={!!data.ended || !!data.setting_up}
          onClick={() => a.join()}>
          {joinText(data)}
        </Btn>
      )}
      <div className="LobbyHud__row">
        <Btn className="LobbyHud__btn" onClick={() => a.setup()}>Setup</Btn>
        {!data.pregame && (
          <Btn className="LobbyHud__btn"
            onClick={() => a.manifest()}>
            Manifest
          </Btn>
        )}
        <Btn className="LobbyHud__btn" onClick={() => a.observe()}>Observe</Btn>
        {!!data.polls && (
          <Btn className="LobbyHud__btn" on={!!data.new_polls}
            onClick={() => a.polls()}>
            Polls
          </Btn>
        )}
      </div>
    </div>
  );
};

// 2. Boarding pass

const Barcode = props => {
  const seed = props.seed || 'NT';
  const bars = [];
  let h = 7;
  for (let i = 0; i < 44; i++) {
    h = (h * 31 + seed.charCodeAt(i % seed.length)) % 997;
    bars.push(
      <span
        key={i}
        className="LobbyPass__bar"
        style={{
          'width': (1 + h % 3) + 'px',
          'margin-right': (1 + (h >> 2) % 2) + 'px',
        }} />,
    );
  }
  return <div className="LobbyPass__barcode">{bars}</div>;
};

const PassField = props => (
  <div className="LobbyPass__field">
    <div className="LobbyPass__label">{props.label}</div>
    <div className={'LobbyPass__value'
      + (props.big ? ' LobbyPass__value--big' : '')}>
      {props.value}
    </div>
  </div>
);

const passStamp = data => {
  if (data.pregame) {
    if (data.ready === READY) {
      return ['Boarding confirmed', 'good'];
    }
    return null;
  }
  if (data.ended) {
    return ['Closed', 'late'];
  }
  return ['Late boarding', 'late'];
};

export const LobbyPass = props => {
  const { data } = props;
  const a = actions(props.act, data);
  const stamp = passStamp(data);
  return (
    <div className={'LobbyPass' + (data.dark ? ' Pass--dark' : '')}>
      <div className="LobbyPass__ticket">
        <div className="LobbyPass__band">
          <span className="LobbyPass__logo">NT</span>
          <span>Crew Transfer</span>
          {!!data.round_id && (
            <span className="LobbyPass__class">
              {'Shift ' + data.round_id}
            </span>
          )}
        </div>
        <div className="LobbyPass__body">
          <div className="LobbyPass__photo">
            <Portrait data={data} />
          </div>
          <div className="LobbyPass__fields">
            <PassField label="Passenger" value={data.character || '-'} big />
            <PassField label="Assignment" value={data.job || '-'} />
            <PassField label="Destination" value={data.station} />
            <div className="LobbyPass__pair">
              <PassField
                label={data.pregame ? 'Departs' : 'Departed'}
                value={bigTime(data)} />
              <PassField label="Gate" value={data.map} />
            </div>
          </div>
        </div>
        <div className="LobbyPass__tear" />
        <div className="LobbyPass__stub">
          <Barcode seed={(data.character || '') + data.round_id} />
          {!!stamp && (
            <div
              key={stamp[0]}
              className={'LobbyPass__stamp LobbyPass__stamp--' + stamp[1]}>
              {stamp[0]}
            </div>
          )}
          <div className="LobbyPass__status">
            <div className="LobbyPass__statusBig">{roundStatus(data)}</div>
            {headcount(data)} {data.pregame ? 'waiting' : 'aboard'}
            {data.players_ready !== undefined && !!data.pregame && (
              ' · ' + data.players_ready + ' ready'
            )}
          </div>
        </div>
      </div>
      {data.pregame ? (
        <div className="LobbyPass__row">
          <Btn className="LobbyPass__btn" on={data.ready === READY}
            onClick={() => a.ready(READY)}>
            Ready
          </Btn>
          <Btn className="LobbyPass__btn" on={data.ready === NOT_READY}
            onClick={() => a.ready(NOT_READY)}>
            Not Ready
          </Btn>
          <Btn className="LobbyPass__btn"
            onClick={() => a.observe()}>
            Observe
          </Btn>
        </div>
      ) : (
        <Fragment>
          <Btn
            className="LobbyPass__btn LobbyPass__go"
            disabled={!!data.ended || !!data.setting_up}
            onClick={() => a.join()}>
            {joinText(data)}
          </Btn>
          <div className="LobbyPass__row">
            <Btn className="LobbyPass__btn" onClick={() => a.manifest()}>
              Crew Manifest
            </Btn>
            <Btn className="LobbyPass__btn"
              onClick={() => a.observe()}>
              Observe
            </Btn>
          </div>
        </Fragment>
      )}
      <div className="LobbyPass__row">
        <Btn className="LobbyPass__btn LobbyPass__quiet"
          onClick={() => a.setup()}>
          Setup Character
        </Btn>
        {!!data.polls && (
          <Btn className="LobbyPass__btn LobbyPass__quiet"
            on={!!data.new_polls} onClick={() => a.polls()}>
            Polls
          </Btn>
        )}
      </div>
    </div>
  );
};

// 3. Departures board

const FLAPS = 17;

const Flaps = props => {
  const { text, tone } = props;
  const chars = String(text === undefined || text === null ? '' : text)
    .toUpperCase()
    .padEnd(FLAPS)
    .slice(0, FLAPS)
    .split('');
  return (
    <span className={'LobbyBoard__flaps'
      + (tone ? ' LobbyBoard__flaps--' + tone : '')}>
      {chars.map((c, i) => (
        <span key={i + ':' + c} className="LobbyBoard__flap">
          {c === ' ' ? ' ' : c}
        </span>
      ))}
    </span>
  );
};

const BoardRow = props => (
  <div className="LobbyBoard__row">
    <span className="LobbyBoard__key">{props.label}</span>
    <Flaps text={props.text} tone={props.tone} />
  </div>
);

export const LobbyBoard = props => {
  const { data } = props;
  const a = actions(props.act, data);
  let pax = String(headcount(data));
  if (data.players_ready !== undefined && data.pregame) {
    pax += ' / ' + data.players_ready + ' RDY';
  }
  return (
    <div className="LobbyBoard">
      <div className="LobbyBoard__panel">
        <div className="LobbyBoard__title">
          <Icon name="space-shuttle" mr={1} />
          Departures
          <span className="LobbyBoard__round">
            {data.round_id ? 'RND ' + data.round_id : ''}
          </span>
        </div>
        <BoardRow label="DEST" text={data.station} />
        <BoardRow
          label={data.pregame ? 'DEPARTS' : 'ELAPSED'}
          text={bigTime(data)} />
        <BoardRow
          label="STATUS"
          text={roundStatus(data)}
          tone={statusGood(data) ? 'good' : 'bad'} />
        <BoardRow label={data.pregame ? 'PAX' : 'CREW'} text={pax} />
        <BoardRow label="GATE" text={data.map} />
      </div>
      <div className="LobbyBoard__pax">
        <div className="LobbyBoard__paxImg"><Portrait data={data} /></div>
        <div className="LobbyBoard__paxText">
          <div className="LobbyBoard__paxName">{data.character || '-'}</div>
          <div className="LobbyBoard__paxJob">
            {data.job || 'No assignment'}
          </div>
        </div>
        <Btn className="LobbyBoard__btn LobbyBoard__small"
          onClick={() => a.setup()}>
          <Icon name="user-cog" />
        </Btn>
      </div>
      {data.pregame ? (
        <div className="LobbyBoard__btns">
          <Btn className="LobbyBoard__btn" on={data.ready === READY}
            onClick={() => a.ready(READY)}>
            <span className="LobbyBoard__led" />Ready
          </Btn>
          <Btn className="LobbyBoard__btn" on={data.ready === NOT_READY}
            onClick={() => a.ready(NOT_READY)}>
            <span className="LobbyBoard__led" />Not Ready
          </Btn>
          <Btn className="LobbyBoard__btn" onClick={() => a.observe()}>
            <span className="LobbyBoard__led" />Observe
          </Btn>
        </div>
      ) : (
        <Fragment>
          <Btn
            className="LobbyBoard__btn LobbyBoard__go"
            disabled={!!data.ended || !!data.setting_up}
            onClick={() => a.join()}>
            {joinText(data)}
          </Btn>
          <div className="LobbyBoard__btns">
            <Btn className="LobbyBoard__btn" onClick={() => a.manifest()}>
              Manifest
            </Btn>
            <Btn className="LobbyBoard__btn"
              onClick={() => a.observe()}>
              Observe
            </Btn>
          </div>
        </Fragment>
      )}
      {!!data.polls && (
        <div className="LobbyBoard__btns">
          <Btn className="LobbyBoard__btn" on={!!data.new_polls}
            onClick={() => a.polls()}>
            <span className="LobbyBoard__led" />Player Polls
          </Btn>
        </div>
      )}
    </div>
  );
};

// 4. Green-screen terminal

const CrtDots = props => (
  <div className="LobbyCrt__dots">
    <span>{props.label}</span>
    <span className="LobbyCrt__fill" />
    <span>{props.value}</span>
  </div>
);

const CrtCmd = props => (
  <Btn className="LobbyCrt__cmd" on={props.on} disabled={props.disabled}
    onClick={() => props.onClick()}>
    [{props.children}]
  </Btn>
);

export const LobbyCrt = props => {
  const { data } = props;
  const a = actions(props.act, data);
  return (
    <div className="LobbyCrt">
      <div className="LobbyCrt__screen">
        <div>NANOTRASEN CREW REGISTRY v2.6</div>
        <div className="LobbyCrt__dim">
          {data.station}{data.round_id ? ' :: RND ' + data.round_id : ''}
        </div>
        <div className="LobbyCrt__rule" />
        <div className="LobbyCrt__ident">
          <div className="LobbyCrt__photo"><Portrait data={data} /></div>
          <div className="LobbyCrt__idText">
            <CrtDots label="ID" value={data.character || '-'} />
            <CrtDots label="POST" value={data.job || 'NONE'} />
            <CrtDots label="STATUS" value={roundStatus(data)} />
            <CrtDots
              label={data.pregame ? 'ONLINE' : 'CREW'}
              value={headcount(data)
                + (data.players_ready !== undefined && data.pregame
                  ? ' (' + data.players_ready + ' RDY)'
                  : '')} />
            <CrtDots label="SITE" value={data.map} />
          </div>
        </div>
        <div className="LobbyCrt__rule" />
        <div className="LobbyCrt__label">
          {data.pregame ? 'SHIFT START IN' : 'SHIFT TIME'}
        </div>
        <div className="LobbyCrt__big">{bigTime(data)}</div>
        <div className="LobbyCrt__rule" />
        {data.pregame ? (
          <div>
            &gt;{' '}
            <CrtCmd on={data.ready === READY}
              onClick={() => a.ready(READY)}>
              READY
            </CrtCmd>
            <CrtCmd on={data.ready === NOT_READY}
              onClick={() => a.ready(NOT_READY)}>
              NOT READY
            </CrtCmd>
            <CrtCmd onClick={() => a.observe()}>OBSERVE</CrtCmd>
          </div>
        ) : (
          <div>
            &gt;{' '}
            <CrtCmd
              on={!data.ended}
              disabled={!!data.ended || !!data.setting_up}
              onClick={() => a.join()}>
              {joinText(data).toUpperCase()}
            </CrtCmd>
            <CrtCmd onClick={() => a.manifest()}>MANIFEST</CrtCmd>
            <CrtCmd onClick={() => a.observe()}>OBSERVE</CrtCmd>
          </div>
        )}
        <div>
          &gt;{' '}
          <CrtCmd onClick={() => a.setup()}>SETUP</CrtCmd>
          {!!data.polls && (
            <CrtCmd on={!!data.new_polls}
              onClick={() => a.polls()}>
              POLLS
            </CrtCmd>
          )}
        </div>
        <div>
          &gt; <span className="LobbyCrt__cursor">_</span>
        </div>
      </div>
    </div>
  );
};
