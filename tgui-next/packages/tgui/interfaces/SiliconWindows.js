import { Component } from 'inferno';
import { useBackend } from '../backend';
import { Icon } from '../components';

// hippie -- the AI's and cyborgs' windows, in the law board's look:
// Current Station Alerts, Remote Robot Control and Announcement Help (the
// VOX words). Data and actions from
// hippiestation/code/modules/mob/living/silicon/silicon_windows_tgui.dm.

const ALARM_ICONS = {
  Fire: 'fire',
  Atmosphere: 'wind',
  Power: 'bolt',
  Motion: 'running',
  Camera: 'video',
  Burglar: 'user-secret',
};

const ALARM_ORDER = ['Fire', 'Atmosphere', 'Power', 'Burglar', 'Motion',
  'Camera'];

export const SiliconAlerts = props => {
  const { act, data } = useBackend(props);
  const categories = (data.categories || []).slice().sort((a, b) => {
    const ai = ALARM_ORDER.indexOf(a.name);
    const bi = ALARM_ORDER.indexOf(b.name);
    return (ai < 0 ? 99 : ai) - (bi < 0 ? 99 : bi);
  });
  let active = 0;
  for (let cat of categories) {
    active += cat.alarms.length;
  }
  return (
    <div className="Sil">
      <div className="Sil__head">
        <div className="Sil__title">
          <Icon name="exclamation-triangle" />
          Station alerts
        </div>
        <div className={'Sil__count' + (active ? ' Sil__count--bad' : '')}>
          {active ? active + ' active' : 'All clear'}
        </div>
      </div>
      <div className="Sil__list">
        {categories.map(cat => (
          <div
            key={cat.name}
            className={'Sil__cat' + (cat.alarms.length ? ' Sil__cat--on' : '')}>
            <div className="Sil__catHead">
              <Icon name={ALARM_ICONS[cat.name] || 'bell'} />
              <span className="Sil__catName">{cat.name}</span>
              <span className="Sil__catState">
                {cat.alarms.length
                  ? cat.alarms.length
                    + (cat.alarms.length === 1 ? ' alarm' : ' alarms')
                  : 'Nominal'}
              </span>
            </div>
            {cat.alarms.map(alarm => (
              <div key={alarm.area} className="Sil__alarm">
                <div className="Sil__alarmArea">
                  {alarm.area}
                  {alarm.sources > 1 && (
                    <span className="Sil__muted">
                      {' '}{alarm.sources} sources
                    </span>
                  )}
                </div>
                {!!data.cameras && (
                  <div className="Sil__chips">
                    {alarm.cameras.length === 0 && (
                      <span className="Sil__muted">No camera</span>
                    )}
                    {alarm.cameras.map(cam => (
                      <div
                        key={cam.ref}
                        className="Sil__chip"
                        title="Jump to this camera"
                        onClick={() => act('camera', { ref: cam.ref })}>
                        <Icon name="video" /> {cam.name}
                      </div>
                    ))}
                  </div>
                )}
              </div>
            ))}
          </div>
        ))}
      </div>
    </div>
  );
};

const MODE_COLORS = {
  good: '#54cb70',
  average: '#efcf57',
  bad: '#ff7266',
};

export class AiBotControl extends Component {
  constructor() {
    super();
    this.state = { search: '' };
  }

  render() {
    const { act, data } = useBackend(this.props);
    const query = this.state.search.toLowerCase();
    const bots = (data.bots || []).filter(bot => !query
      || bot.name.toLowerCase().includes(query)
      || (bot.model || '').toLowerCase().includes(query)
      || bot.location.toLowerCase().includes(query));
    return (
      <div className="Sil">
        <div className="Sil__head">
          <div className="Sil__title">
            <Icon name="robot" />
            Robot control
          </div>
          <input
            className="Sil__search"
            placeholder="Search bots, models, rooms..."
            value={this.state.search}
            onInput={e => this.setState({ search: e.target.value })} />
        </div>
        {!!data.waypoint && (
          <div className="Sil__banner">
            <Icon name="map-marker-alt" />
            {' '}Click a spot in view to send {data.calling || 'the bot'}
            <div className="Sil__chip" onClick={() => act('cancel_call')}>
              Cancel
            </div>
          </div>
        )}
        {!!data.disabled && (
          <div className="Sil__banner Sil__banner--bad">
            <Icon name="ban" /> Wireless control is disabled
          </div>
        )}
        <div className="Sil__list">
          {bots.length === 0 && (
            <div className="Sil__none">
              {query ? 'No bot matches that.' : 'No bots on the network.'}
            </div>
          )}
          {bots.map(bot => (
            <div key={bot.ref} className="Sil__bot">
              <div className="Sil__botMain">
                <div className="Sil__botName">
                  {!!bot.hacked && (
                    <span className="Sil__hacked" title="Tampered with">
                      (!){' '}
                    </span>
                  )}
                  {bot.name}
                  <span className="Sil__muted"> {bot.model}</span>
                </div>
                <div className="Sil__botWhere">
                  <span style={{ color: MODE_COLORS[bot.mode_color] }}>
                    {bot.mode}
                  </span>
                  <span className="Sil__muted"> · {bot.location}</span>
                </div>
              </div>
              <div
                className="Sil__chip"
                onClick={() => act('interface', { ref: bot.ref })}>
                <Icon name="sliders-h" /> Interface
              </div>
              <div
                className="Sil__chip"
                onClick={() => act('call', { ref: bot.ref })}>
                <Icon name="map-marker-alt" /> Call
              </div>
            </div>
          ))}
        </div>
      </div>
    );
  }
}

export class AiVox extends Component {
  constructor() {
    super();
    this.state = { search: '', text: null };
  }

  render() {
    const { act, data } = useBackend(this.props);
    const known = {};
    const words = data.words || [];
    for (let word of words) {
      known[word] = true;
    }
    const text = this.state.text === null ? (data.last || '') : this.state.text;
    const typed = text.split(' ').map(w => w.trim().toLowerCase())
      .filter(w => w.length);
    const unknown = typed.filter(w => !known[w]);
    const tooMany = typed.length > data.max_words;
    const query = this.state.search.toLowerCase();
    const shown = query ? words.filter(w => w.includes(query)) : words;
    const ready = typed.length && !unknown.length && !tooMany
      && !data.cooldown && !data.disabled;
    const append = word => this.setState({
      text: (text.trim() ? text.trim() + ' ' : '') + word,
    });
    return (
      <div className="Sil">
        <div className="Sil__head">
          <div className="Sil__title">
            <Icon name="bullhorn" />
            Vocal announcement
          </div>
          <div className="Sil__count">
            {data.cooldown ? 'Ready in ' + data.cooldown + ' s' : 'Ready'}
          </div>
        </div>
        <div className="Sil__compose">
          <input
            className="Sil__sentence"
            placeholder="Type words from the list, separated by spaces"
            value={text}
            onInput={e => this.setState({ text: e.target.value })}
            onKeyDown={e => {
              if (e.keyCode === 13 && ready) {
                act('announce', { text });
              }
            }} />
          <div className="Sil__words">
            {typed.map((word, i) => (
              <span
                key={i}
                className={'Sil__word'
                  + (known[word] ? '' : ' Sil__word--bad')
                  + (i >= data.max_words ? ' Sil__word--over' : '')}>
                {word}
              </span>
            ))}
          </div>
          <div className="Sil__composeFoot">
            <span className={tooMany ? 'Sil__bad' : 'Sil__muted'}>
              {typed.length} / {data.max_words} words
            </span>
            {unknown.length > 0 && (
              <span className="Sil__bad">
                {'\u00a0· not in the list: ' + unknown.join(', ')}
              </span>
            )}
            <div
              className={'Sil__announce' + (ready ? '' : ' Sil__announce--off')}
              onClick={() => ready && act('announce', { text })}>
              <Icon name="bullhorn" /> Announce
            </div>
          </div>
          <div className="Sil__rules">
            {'Misuse gets you job banned. Pause with a spaced full stop or'
              + ' comma ("alpha . bravo"), numbers as words, sound effects'
              + ' start with s (scensor).'}
          </div>
        </div>
        <div className="Sil__head Sil__head--sub">
          <div className="Sil__title Sil__title--small">
            {shown.length} words · click to hear, + to add
          </div>
          <input
            className="Sil__search"
            placeholder="Search words..."
            value={this.state.search}
            onInput={e => this.setState({ search: e.target.value })} />
        </div>
        <div className="Sil__list Sil__wordList">
          {shown.map(word => (
            <span key={word} className="Sil__vword">
              <span
                className="Sil__vwordName"
                title="Hear it"
                onClick={() => act('preview', { word })}>
                {word}
              </span>
              <span
                className="Sil__vwordAdd"
                title="Add to the announcement"
                onClick={() => append(word)}>
                +
              </span>
            </span>
          ))}
        </div>
      </div>
    );
  }
}
