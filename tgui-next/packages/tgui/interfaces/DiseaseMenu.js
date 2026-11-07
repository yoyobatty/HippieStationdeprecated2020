import { Component } from 'inferno';
import { useBackend } from '../backend';
import { Icon } from '../components';

// hippie -- the sentient disease's Adaptation Menu: its stats and cure, its
// points and cooldown, every adaptation as a card (bought, buyable, locked)
// with the picked one's details, and the hosts to follow. Data and actions
// from hippiestation/code/modules/antagonists/disease/disease_tgui.dm.

const STATS = [
  ['resistance', 'Resistance', 'shield-virus'],
  ['stealth', 'Stealth', 'eye-slash'],
  ['stage_speed', 'Stage speed', 'tachometer-alt'],
  ['transmittable', 'Transmission', 'people-arrows'],
];

const signed = value => (value > 0 ? '+' + value : String(value));

// Stats run from about -12 to 12; the bar fills from the middle
const StatBar = props => {
  const { label, icon, value } = props;
  const span = Math.min(50, Math.abs(value) / 12 * 50);
  return (
    <div className="Disease__stat">
      <div className="Disease__statLabel">
        <Icon name={icon} /> {label}
        <b>{value}</b>
      </div>
      <div className="Disease__statTrack">
        <div className="Disease__statMid" />
        <div
          className={'Disease__statFill'
            + (value < 0 ? ' Disease__statFill--neg' : '')}
          style={value < 0
            ? { right: '50%', width: span + '%' }
            : { left: '50%', width: span + '%' }} />
      </div>
    </div>
  );
};

const Card = props => {
  const { ability, picked, onClick, total } = props;
  const locked = !ability.bought && total < ability.unlock;
  return (
    <div
      className={'Disease__card'
        + (ability.bought ? ' Disease__card--bought' : '')
        + (locked ? ' Disease__card--locked' : '')
        + (picked ? ' Disease__card--picked' : '')}
      onClick={onClick}>
      <div className="Disease__cardName">{ability.name}</div>
      <div className="Disease__cardMeta">
        {locked ? (
          <span><Icon name="lock" /> {ability.unlock}</span>
        ) : (
          <span>{ability.cost} pt{ability.cost === 1 ? '' : 's'}</span>
        )}
        {!!ability.bought && <Icon name="check" />}
      </div>
    </div>
  );
};

export class DiseaseMenu extends Component {
  constructor() {
    super();
    this.state = { picked: null };
  }

  render() {
    const { act, data } = useBackend(this.props);
    const abilities = data.abilities || [];
    const hosts = data.hosts || [];
    const stats = data.stats || {};
    const categories = [];
    abilities.forEach(a => {
      if (!categories.includes(a.category)) {
        categories.push(a.category);
      }
    });
    const picked = abilities.find(a => a.ref === this.state.picked)
      || abilities[0];
    return (
      <div className="Disease">
        <div className="Disease__head">
          <div className="Disease__name">
            <Icon name="biohazard" /> {data.name}
          </div>
          <div className="Disease__points">
            <b>{data.points}</b> / {data.total_points} points
            {data.cooldown > 0 && (
              <span className="Disease__cooldown">
                <Icon name="hourglass-half" /> {data.cooldown} s
              </span>
            )}
          </div>
        </div>
        <div className="Disease__body">
          <div className="Disease__side">
            <div className="Disease__label">Strain</div>
            {STATS.map(stat => (
              <StatBar
                key={stat[0]}
                label={stat[1]}
                icon={stat[2]}
                value={stats[stat[0]] || 0} />
            ))}
            <div className="Disease__label">Cure</div>
            <div className="Disease__cure">{data.cure || 'None'}</div>
            <div className="Disease__label">Hosts ({hosts.length})</div>
            <div className="Disease__hosts">
              {hosts.map(host => (
                <div
                  key={host.ref}
                  className={'Disease__host'
                    + (host.following ? ' Disease__host--on' : '')}
                  onClick={() => act('follow', { ref: host.ref })}>
                  <Icon name={host.following ? 'eye' : 'user'} />
                  {host.name}
                </div>
              ))}
            </div>
          </div>
          <div className="Disease__main">
            {categories.map(category => (
              <div key={category}>
                <div className="Disease__label">{category}</div>
                <div className="Disease__cards">
                  {abilities.filter(a => a.category === category).map(a => (
                    <Card
                      key={a.ref}
                      ability={a}
                      total={data.total_points}
                      picked={picked && picked.ref === a.ref}
                      onClick={() => this.setState({ picked: a.ref })} />
                  ))}
                </div>
              </div>
            ))}
          </div>
          {!!picked && (
            <div className="Disease__detail">
              <div className="Disease__detailName">{picked.name}</div>
              <div className="Disease__detailCat">{picked.category}</div>
              <div className="Disease__detailText">
                {picked.long_desc || picked.short_desc}
              </div>
              {!!picked.stats && (
                <div className="Disease__deltas">
                  {STATS.map(stat => (
                    <span
                      key={stat[0]}
                      className={'Disease__delta'
                        + (picked.stats[stat[0]] < 0
                          ? ' Disease__delta--neg'
                          : '')}>
                      <Icon name={stat[2]} /> {signed(picked.stats[stat[0]])}
                    </span>
                  ))}
                </div>
              )}
              {(picked.thresholds || []).map(t => (
                <div key={t.name} className="Disease__threshold">
                  <b>{t.name}</b> {t.desc}
                </div>
              ))}
              <div className="Disease__actions">
                {picked.bought ? (
                  <div
                    className={'Disease__key'
                      + (picked.can_refund ? '' : ' Disease__key--off')}
                    onClick={picked.can_refund
                      ? () => act('refund', { ref: picked.ref })
                      : null}>
                    Refund
                  </div>
                ) : (
                  <div
                    className={'Disease__key Disease__key--buy'
                      + (picked.can_buy ? '' : ' Disease__key--off')}
                    onClick={picked.can_buy
                      ? () => act('buy', { ref: picked.ref })
                      : null}>
                    Adapt ({picked.cost})
                  </div>
                )}
              </div>
            </div>
          )}
        </div>
      </div>
    );
  }
}
