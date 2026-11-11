import { decodeHtmlEntities } from 'common/string';
import { Component } from 'inferno';
import { useBackend } from '../backend';

// hippie -- the pAI's windows as an amber retro terminal (the user's pick,
// 2026-11-08): the pAI OS (numbered programs down the left, the open one on
// the right behind a > prompt, RAM in the status line), a ghost's pAI
// personality, and a silicon's PDA message log. Data and actions from
// hippiestation/code/modules/mob/living/silicon/pai/pai_tgui.dm.

// Installed software -> its screen (or a one-shot action) in the menu
const PROGRAMS = [
  { soft: 'digital messenger', screen: 'pdamessage', label: 'Messenger',
    icon: 'envelope', kind: 'Basic' },
  { soft: 'crew manifest', screen: 'manifest', label: 'Crew manifest',
    icon: 'users', kind: 'Basic' },
  { soft: 'host scan', screen: 'hostscan', label: 'Host scan',
    icon: 'heartbeat', kind: 'Basic' },
  { soft: 'medical records', screen: 'medicalrecord', label: 'Medical records',
    icon: 'notes-medical', kind: 'Basic' },
  { soft: 'security records', screen: 'securityrecord',
    label: 'Security records', icon: 'id-badge', kind: 'Basic' },
  { soft: 'remote signaller', screen: 'signaller', label: 'Signaller',
    icon: 'rss', kind: 'Basic' },
  { soft: 'loudness booster', screen: 'loudness', label: 'Synthesizer',
    icon: 'music', kind: 'Basic' },
  { soft: 'newscaster', action: 'news', label: 'Newscaster',
    icon: 'newspaper', kind: 'Basic' },
  { soft: 'camera zoom', action: 'camzoom', label: 'Camera zoom',
    icon: 'search-plus', kind: 'Advanced' },
  { soft: 'atmosphere sensor', screen: 'atmosensor', label: 'Air sensor',
    icon: 'wind', kind: 'Advanced' },
  { soft: 'security HUD', screen: 'securityhud', label: 'Facial recognition',
    icon: 'user-shield', kind: 'Advanced', flag: 'sec_hud' },
  { soft: 'medical HUD', screen: 'medicalhud', label: 'Medical analysis',
    icon: 'stethoscope', kind: 'Advanced', flag: 'med_hud' },
  { soft: 'encryption keys', screen: 'encryptionkeys',
    label: 'Encryption ports', icon: 'key', kind: 'Advanced',
    flag: 'encrypt' },
  { soft: 'universal translator', screen: 'translator', label: 'Translator',
    icon: 'language', kind: 'Advanced', flag: 'translator' },
  { soft: 'door jack', screen: 'doorjack', label: 'Door jack',
    icon: 'door-open', kind: 'Advanced' },
];

// The card's faces, as the terminal draws them
const FACES = [':)', '=^.^=', ':D', ':|', 'XD', '_ _', ':(', '>:(', 'o_O'];

// RAM as a text bar: [#######---]
const ramBar = ram => {
  const filled = Math.round(Math.max(0, Math.min(100, ram)) / 10);
  return '[' + '#'.repeat(filled) + '-'.repeat(10 - filled) + ']';
};

const pad3 = n => ('00' + n).slice(-3);

const NavItem = props => {
  const { number, label, active, flag, onClick } = props;
  return (
    <div
      className={'PaiOs__nav' + (active ? ' PaiOs__nav--on' : '')}
      onClick={onClick}>
      <span className="PaiOs__num">{active ? '>' : number}</span>
      <span className="PaiOs__navLabel">{label}</span>
      {flag !== undefined && (
        <span className={'PaiOs__led' + (flag ? ' PaiOs__led--on' : '')}>
          {flag ? 'ON' : '--'}
        </span>
      )}
    </div>
  );
};

const Btn = props => {
  const { icon, children, onClick, disabled, danger } = props;
  return (
    <div
      className={'PaiOs__btn'
        + (disabled ? ' PaiOs__btn--off' : '')
        + (danger ? ' PaiOs__btn--danger' : '')}
      onClick={() => !disabled && onClick && onClick()}>
      {children}
    </div>
  );
};

const Switch = props => {
  const { on, onText, offText } = props;
  return (
    <span className={'PaiOs__state' + (on ? ' PaiOs__state--on' : '')}>
      {on ? (onText || 'Enabled') : (offText || 'Disabled')}
    </span>
  );
};

const Home = props => {
  const { act, data } = props;
  return (
    <div>
      <div className="PaiOs__h">Display</div>
      <div className="PaiOs__faces">
        {(data.faces || []).map((face, i) => (
          <div
            key={face}
            className="PaiOs__face"
            onClick={() => act('face', { index: i + 1 })}>
            <div className="PaiOs__faceArt">{FACES[i]}</div>
            <div>{face}</div>
          </div>
        ))}
      </div>
      <div className="PaiOs__h">Radio</div>
      <Btn icon="broadcast-tower" onClick={() => act('radio')}>
        Radio configuration
      </Btn>
      <div className="PaiOs__p PaiOs__muted">
        {data.software.length} programs installed, {data.ram} RAM free.
      </div>
    </div>
  );
};

const Directives = props => {
  const { act, data } = props;
  return (
    <div>
      <div className="PaiOs__card">
        {data.master
          ? (
            <span>
              Bound to <b>{data.master}</b>
              <span className="PaiOs__muted"> ({data.master_dna})</span>
            </span>
          )
          : <span>Bound to no one</span>}
        <div className="PaiOs__row">
          <Btn
            icon="fingerprint"
            disabled={!data.carried}
            onClick={() => act('getdna')}>
            Request carrier DNA
          </Btn>
          {!data.carried && (
            <span className="PaiOs__muted">Nobody is carrying you.</span>
          )}
        </div>
      </div>
      <div className="PaiOs__h">Prime directive</div>
      <div className="PaiOs__law PaiOs__law--prime">{data.zeroth}</div>
      <div className="PaiOs__h">Supplemental directives</div>
      {(data.supplied || []).length === 0 && (
        <div className="PaiOs__muted">None</div>
      )}
      {(data.supplied || []).map((law, i) => (
        <div key={i} className="PaiOs__law">{law}</div>
      ))}
    </div>
  );
};

const Shop = props => {
  const { act, data } = props;
  return (
    <div>
      <div className="PaiOs__h">
        Software trunks
        <span className="PaiOs__muted" style={{ 'margin-left': '10px' }}>
          {data.ram + ' RAM free'}
        </span>
      </div>
      {(data.shop || []).map(item => {
        const owned = data.software.includes(item.name);
        return (
          <div key={item.name} className="PaiOs__shop">
            <span className="PaiOs__shopName">{item.name}</span>
            <span className="PaiOs__cost">{item.cost}</span>
            {owned
              ? <span className="PaiOs__state PaiOs__state--on">Installed</span>
              : (
                <Btn
                  icon="download"
                  disabled={data.ram < item.cost}
                  onClick={() => act('buy', { name: item.name })}>
                  Download
                </Btn>
              )}
          </div>
        );
      })}
    </div>
  );
};

const LogList = props => {
  const log = props.log || [];
  if (!log.length) {
    return <div className="PaiOs__muted">No messages.</div>;
  }
  return (
    <div>
      {log.slice().reverse().map((entry, i) => (
        <div
          key={i}
          className={'PaiOs__msg' + (entry.out ? ' PaiOs__msg--out' : '')}>
          <div className="PaiOs__msgHead">
            {entry.out ? '>> To ' : '<< From '}
            <b>{entry.name}</b>
            {!!entry.job && <span> ({entry.job})</span>}
            <span className="PaiOs__muted"> {entry.time}</span>
          </div>
          {entry.text}
        </div>
      ))}
    </div>
  );
};

class Messenger extends Component {
  constructor() {
    super();
    this.state = { search: '' };
  }

  render() {
    const { act, data } = this.props;
    const query = this.state.search.toLowerCase();
    const pdas = (data.pdas || []).filter(pda => !query
      || pda.name.toLowerCase().includes(query));
    return (
      <div>
        <div className="PaiOs__row">
          <Btn icon="power-off" onClick={() => act('pda_toggle')}>
            Send/receive <Switch on={data.pda_on} onText="On" offText="Off" />
          </Btn>
          <Btn icon="bell" onClick={() => act('pda_ringer')}>
            Ringer <Switch on={data.ringer} onText="On" offText="Off" />
          </Btn>
        </div>
        {!!data.pda_on && (
          <div>
            <div className="PaiOs__h">
              Send to
              <input
                className="PaiOs__search"
                placeholder="Search PDAs..."
                value={this.state.search}
                onInput={e => this.setState({ search: e.target.value })} />
            </div>
            <div className="PaiOs__pdas">
              {pdas.map(pda => (
                <div
                  key={pda.ref}
                  className="PaiOs__pda"
                  onClick={() => act('pda_send', { ref: pda.ref })}>
                  {pda.name}
                </div>
              ))}
            </div>
          </div>
        )}
        <div className="PaiOs__h">Messages</div>
        <LogList log={data.log} />
      </div>
    );
  }
}

const Manifest = props => {
  const { data } = props;
  return (
    <div>
      {(data.departments || []).filter(dept => dept.crew.length).map(dept => (
        <div key={dept.name}>
          <div className="PaiOs__h">{dept.name}</div>
          {dept.crew.map(person => (
            <div key={person.name + person.rank} className="PaiOs__line">
              <span>{person.name}</span>
              <span className="PaiOs__muted">{person.rank}</span>
            </div>
          ))}
        </div>
      ))}
    </div>
  );
};

class Records extends Component {
  constructor() {
    super();
    this.state = { search: '' };
  }

  render() {
    const { act, data } = this.props;
    if (data.subscreen === 1) {
      const record = data.record;
      return (
        <div>
          <Btn icon="arrow-left" onClick={() => act('record_back')}>Back</Btn>
          {!record && (
            <div className="PaiOs__muted">Record not found.</div>
          )}
          {!!record && (
            <div className="PaiOs__card">
              <div className="PaiOs__big">{record.name}</div>
              <div className="PaiOs__muted">
                {record.rank} · ID {record.id} · {record.gender},{' '}
                {record.age}
              </div>
              <div className="PaiOs__line">
                <span>Fingerprint</span><span>{record.fingerprint}</span>
              </div>
              <div className="PaiOs__line">
                <span>Physical status</span><span>{record.p_stat}</span>
              </div>
              <div className="PaiOs__line">
                <span>Mental status</span><span>{record.m_stat}</span>
              </div>
            </div>
          )}
          {(data.detail || []).map((field, i) => (
            <div key={i} className="PaiOs__line">
              <span className="PaiOs__muted">{field.label}</span>
              <span>{field.value}</span>
            </div>
          ))}
        </div>
      );
    }
    const query = this.state.search.toLowerCase();
    const records = (data.records || []).filter(r => !query
      || r.name.toLowerCase().includes(query)
      || r.rank.toLowerCase().includes(query));
    return (
      <div>
        <input
          className="PaiOs__search PaiOs__search--wide"
          placeholder="Search names and jobs..."
          value={this.state.search}
          onInput={e => this.setState({ search: e.target.value })} />
        {records.map(r => (
          <div
            key={r.id}
            className="PaiOs__line PaiOs__line--click"
            onClick={() => act('record', { id: r.id })}>
            <span>{r.name}</span>
            <span className="PaiOs__muted">{r.rank}</span>
          </div>
        ))}
      </div>
    );
  }
}

const Toggle = props => {
  const { act, data, flag, text, once, label } = props;
  const on = !!data[flag];
  return (
    <div>
      <div className="PaiOs__p">{text}</div>
      <div className="PaiOs__row">
        <Switch on={on} />
        {!(once && on) && (
          <Btn
            icon={once ? 'plug' : 'power-off'}
            onClick={() => act('toggle')}>
            {label}
          </Btn>
        )}
      </div>
      {!!once && (
        <div className="PaiOs__p PaiOs__muted">Once on, it stays on.</div>
      )}
    </div>
  );
};

const Screen = props => {
  const { act, data } = props;
  switch (data.screen) {
    case 'directives':
      return <Directives act={act} data={data} />;
    case 'buy':
      return <Shop act={act} data={data} />;
    case 'pdamessage':
      return <Messenger act={act} data={data} />;
    case 'manifest':
      return <Manifest data={data} />;
    case 'medicalrecord':
    case 'securityrecord':
      return <Records act={act} data={data} />;
    case 'securityhud':
      return (
        <Toggle act={act} data={data} flag="sec_hud" label="Toggle"
          text="Flags wanted crew in view." />
      );
    case 'medicalhud':
      return (
        <Toggle act={act} data={data} flag="med_hud" label="Toggle"
          text="Crew health in view." />
      );
    case 'encryptionkeys':
      return (
        <Toggle act={act} data={data} flag="encrypt" once
          label="Activate the key ports"
          text={'Lets your radio take up to two encryption keys for'
            + ' department channels.'} />
      );
    case 'translator':
      return (
        <Toggle act={act} data={data} flag="translator" once
          label="Activate the translator"
          text="Speak and understand every known language, for good." />
      );
    case 'hostscan':
      return (
        <div>
          <div className="PaiOs__p">
            Scans whoever is carrying you (the Host Scan button).
          </div>
          <div className="PaiOs__line">
            <span>Scan for</span>
            <span>
              {data.scan_chems ? 'Chemicals' : 'Health'}{' '}
              <Btn icon="exchange-alt" onClick={() => act('toggle')}>
                Switch
              </Btn>
            </span>
          </div>
          <div className="PaiOs__line">
            <span>Limb damage</span>
            <span>
              <Switch on={data.verbose} onText="Shown" offText="Hidden" />
              {' '}
              <Btn icon="exchange-alt" onClick={() => act('verbosity')}>
                Switch
              </Btn>
            </span>
          </div>
        </div>
      );
    case 'atmosensor':
      return (
        <div>
          {data.pressure === undefined && (
            <div className="PaiOs__muted">Unable to obtain a reading.</div>
          )}
          {data.pressure !== undefined && (
            <div className="PaiOs__card">
              <div className="PaiOs__readings">
                <div>
                  <div className="PaiOs__big">{data.pressure}</div>
                  <div className="PaiOs__muted">kPa</div>
                </div>
                <div>
                  <div className="PaiOs__big">{data.temperature}</div>
                  <div className="PaiOs__muted">°C</div>
                </div>
              </div>
              {(data.gases || []).map(gas => (
                <div key={gas.name} className="PaiOs__line">
                  <span>{gas.name}</span>
                  <span>{gas.percent}%</span>
                </div>
              ))}
            </div>
          )}
          <Btn
            icon="sync"
            onClick={() => act('screen', { screen: 'atmosensor' })}>
            Refresh
          </Btn>
        </div>
      );
    case 'doorjack':
      return (
        <div>
          <div className="PaiOs__line">
            <span>Cable</span>
            <span className={'PaiOs__cable PaiOs__cable--' + data.cable}>
              {data.cable}
            </span>
          </div>
          {data.cable === 'retracted' && (
            <Btn icon="plug" onClick={() => act('cable')}>Extend cable</Btn>
          )}
          {data.cable === 'extended' && (
            <div className="PaiOs__muted">
              Cable not connected.
            </div>
          )}
          {data.cable === 'connected' && !data.door && (
            <div className="PaiOs__muted">
              That device does not speak airlock.
            </div>
          )}
          {data.cable === 'connected' && !!data.door && !data.hacking && (
            <Btn icon="unlock" onClick={() => act('jack')}>
              Begin airlock jack
            </Btn>
          )}
          {!!data.hacking && (
            <div>
              <div className="PaiOs__bar">
                <div
                  className="PaiOs__barFill"
                  style={{ width: data.progress + '%' }} />
                <span>{data.progress}%</span>
              </div>
              <div className="PaiOs__muted PaiOs__p">
                Cracking...
              </div>
              <Btn icon="times" danger onClick={() => act('jack_cancel')}>
                Cancel
              </Btn>
            </div>
          )}
        </div>
      );
    case 'signaller':
      return (
        <div className="PaiOs__card">
          <div className="PaiOs__line">
            <span>Frequency</span>
            <span className="PaiOs__stepper">
              <Btn onClick={() => act('freq', { by: -10 })}>«</Btn>
              <Btn onClick={() => act('freq', { by: -2 })}>‹</Btn>
              <b>{data.frequency}</b>
              <Btn onClick={() => act('freq', { by: 2 })}>›</Btn>
              <Btn onClick={() => act('freq', { by: 10 })}>»</Btn>
            </span>
          </div>
          <div className="PaiOs__line">
            <span>Code</span>
            <span className="PaiOs__stepper">
              <Btn onClick={() => act('code', { by: -5 })}>«</Btn>
              <Btn onClick={() => act('code', { by: -1 })}>‹</Btn>
              <b>{data.code}</b>
              <Btn onClick={() => act('code', { by: 1 })}>›</Btn>
              <Btn onClick={() => act('code', { by: 5 })}>»</Btn>
            </span>
          </div>
          <Btn icon="rss" onClick={() => act('signal')}>Send signal</Btn>
        </div>
      );
    case 'loudness':
      return (
        <div>
          <div className="PaiOs__p">
            {data.instrument || 'Sound synthesizer'}
          </div>
          <div className="PaiOs__row">
            <Btn icon="music" onClick={() => act('synth')}>
              Open the synthesizer
            </Btn>
            <Btn icon="guitar" onClick={() => act('synth_type')}>
              Choose the instrument
            </Btn>
          </div>
        </div>
      );
    default:
      return <Home act={act} data={data} />;
  }
};

const TITLES = {
  main: 'Home',
  directives: 'Directives',
  buy: 'Download software',
};

export const PaiOs = props => {
  const { act, data } = useBackend(props);
  if (data.dead) {
    return (
      <div className="PaiOs PaiOs--dead">
        <div className="PaiOs__glitch">ÈRrÖR Ða†Ä ÇÖRrÚþ†Ìoñ</div>
        <span className="PaiOs__cursor" />
        <div className="PaiOs__muted">Program index hash not found</div>
      </div>
    );
  }
  const installed = PROGRAMS.filter(p => data.software.includes(p.soft));
  const open = PROGRAMS.find(p => p.screen && p.screen === data.screen);
  const go = screen => act('screen', { screen });
  // Numbered in menu order: home and directives first, the shop last
  const numbered = [];
  for (let kind of ['Basic', 'Advanced']) {
    for (let p of installed) {
      if (p.kind === kind) {
        numbered.push(p);
      }
    }
  }
  const navFor = p => (
    <NavItem
      key={p.soft}
      number={numbered.indexOf(p) + 3}
      label={p.label}
      flag={p.flag ? !!data[p.flag] : undefined}
      active={p.screen && p.screen === data.screen}
      onClick={() => (p.action ? act(p.action) : go(p.screen))} />
  );
  return (
    <div className="PaiOs">
      <div className="PaiOs__top">
        <span className="PaiOs__logo">PAI-OS v2.5</span>
        <span className="PaiOs__name">[{data.name}]</span>
        <span className="PaiOs__ram">
          RAM {ramBar(data.ram)} {pad3(data.ram)}
        </span>
      </div>
      <div className="PaiOs__body">
        <div className="PaiOs__side">
          <NavItem number={1} label="Home" active={data.screen === 'main'}
            onClick={() => go('main')} />
          <NavItem number={2} label="Directives"
            active={data.screen === 'directives'}
            onClick={() => go('directives')} />
          {['Basic', 'Advanced'].map(kind => {
            const list = installed.filter(p => p.kind === kind);
            return list.length > 0 && (
              <div key={kind}>
                <div className="PaiOs__kind">{kind}</div>
                {list.map(navFor)}
              </div>
            );
          })}
          <div className="PaiOs__kind" />
          <NavItem number={0} label="Download software"
            active={data.screen === 'buy'}
            onClick={() => go('buy')} />
        </div>
        <div className="PaiOs__main">
          <div className="PaiOs__title">
            {'> ' + (open ? open.label : (TITLES[data.screen] || 'Home'))}
            <span className="PaiOs__cursor" />
          </div>
          {!!data.notice && (
            <div className="PaiOs__notice">{'!! ' + data.notice}</div>
          )}
          <Screen act={act} data={data} />
        </div>
      </div>
    </div>
  );
};

const FIELDS = [
  { key: 'name', label: 'Name', multiline: false,
    hint: '' },
  { key: 'description', label: 'Description', multiline: true,
    hint: '' },
  { key: 'role', label: 'Preferred role', multiline: false,
    hint: '' },
  { key: 'comments', label: 'OOC comments', multiline: true,
    hint: '' },
];

export class PaiRecruit extends Component {
  constructor() {
    super();
    this.state = {};
  }

  render() {
    const { act, data } = useBackend(this.props);
    const stored = key => decodeHtmlEntities(data[key] || '');
    const value = key => (this.state[key] !== undefined
      ? this.state[key]
      : stored(key));
    const dirty = FIELDS.some(f => this.state[f.key] !== undefined
      && this.state[f.key] !== stored(f.key));
    const saveFields = () => {
      for (let f of FIELDS) {
        if (this.state[f.key] !== undefined
          && this.state[f.key] !== stored(f.key)) {
          act('set', { field: f.key, value: this.state[f.key] });
        }
      }
      this.setState({ name: undefined, description: undefined,
        role: undefined, comments: undefined });
    };
    return (
      <div className="PaiOs">
        <div className="PaiOs__top">
          <span className="PaiOs__logo">PAI-OS v2.5</span>
          <span className="PaiOs__name">[PERSONALITY UPLOAD]</span>
          {!!data.ready && (
            <span className="PaiOs__state PaiOs__state--on">On offer</span>
          )}
        </div>
        <div className="PaiOs__main PaiOs__main--solo">
          {FIELDS.map(f => (
            <div key={f.key} className="PaiOs__field">
              <div className="PaiOs__h">{f.label}</div>
              {f.multiline
                ? (
                  <textarea
                    className="PaiOs__search PaiOs__text"
                    value={value(f.key)}
                    onInput={e => this.setState({ [f.key]: e.target.value })} />
                )
                : (
                  <input
                    className="PaiOs__search PaiOs__search--wide"
                    value={value(f.key)}
                    onInput={e => this.setState({ [f.key]: e.target.value })} />
                )}
            </div>
          ))}
          <div className="PaiOs__row">
            <Btn icon="check" disabled={!dirty} onClick={saveFields}>
              Apply changes
            </Btn>
            <Btn icon="save" onClick={() => act('save')}>Save</Btn>
            <Btn icon="folder-open" onClick={() => act('load')}>Load</Btn>
            <Btn
              icon="upload"
              onClick={() => {
                saveFields();
                act('submit');
              }}>
              {data.ready ? 'Offer again' : 'Offer personality'}
            </Btn>
          </div>
        </div>
      </div>
    );
  }
}

export const SiliconPdaLog = props => {
  const { act, data } = useBackend(props);
  return (
    <div className="PaiOs">
      <div className="PaiOs__top">
        <span className="PaiOs__logo">MSG-LOG</span>
        <span className="PaiOs__name">[PDA]</span>
        <Btn onClick={() => act('pda_toggle')}>
          TX/RX <Switch on={data.pda_on} onText="On" offText="Off" />
        </Btn>
        <Btn onClick={() => act('pda_ringer')}>
          Ring <Switch on={data.ringer} onText="On" offText="Off" />
        </Btn>
        <Btn icon="paper-plane" disabled={!data.pda_on}
          onClick={() => act('send')}>
          Send
        </Btn>
      </div>
      <div className="PaiOs__main PaiOs__main--solo">
        <LogList log={data.log} />
      </div>
    </div>
  );
};
