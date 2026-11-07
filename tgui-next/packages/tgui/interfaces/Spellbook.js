import { useBackend } from '../backend';
import { Icon } from '../components';

// hippie -- the wizard's spellbook as a tome: points as gems, the categories
// as ribbons, each spell or item a page entry with its cost, cooldown, whether
// it needs the robes, how far you've improved it, and Learn and Refund. Data
// and actions from hippiestation/code/modules/antagonists/wizard/equipment/
// spellbook_tgui.dm; learning and refunding go through the book's Topic().

const LEVEL_NAMES = ['', 'Efficient', 'Quickened', 'Free', 'Instant'];

const Gems = props => {
  const { count, max, small } = props;
  const gems = [];
  for (let i = 0; i < max; i++) {
    gems.push(
      <span
        key={i}
        className={'Spellbook__gem'
          + (i < count ? ' Spellbook__gem--lit' : '')
          + (small ? ' Spellbook__gem--small' : '')} />,
    );
  }
  return <span className="Spellbook__gems">{gems}</span>;
};

const Entry = props => {
  const { act, entry, points } = props;
  const short = !entry.can_buy && entry.cost > points;
  const levels = entry.level_max || 0;
  return (
    <div className={'Spellbook__entry'
      + (entry.known ? ' Spellbook__entry--known' : '')}>
      <div className="Spellbook__entryHead">
        <div className="Spellbook__entryName">
          {entry.known && entry.known_name ? entry.known_name : entry.name}
        </div>
        <div className="Spellbook__cost" title={entry.cost + ' points'}>
          {entry.cost > 0 ? (
            <Gems count={entry.cost} max={entry.cost} small />
          ) : 'free'}
        </div>
      </div>
      <div className="Spellbook__meta">
        {entry.kind === 'spell' && entry.cooldown !== undefined && (
          <span title="Cooldown">
            <Icon name="hourglass-half" /> {entry.cooldown} s
          </span>
        )}
        {entry.kind === 'spell' && (
          <span title={entry.garb ? 'Needs the robes' : 'No robes needed'}>
            <Icon name="hat-wizard" />
            {entry.garb ? ' robes' : ' no robes'}
          </span>
        )}
        {entry.kind === 'spell' && !!entry.staff && (
          <span title="Needs a staff">
            <Icon name="magic" /> staff
          </span>
        )}
        {entry.kind === 'item' && (
          <span><Icon name="box-open" /> item</span>
        )}
        {entry.kind === 'ritual' && (
          <span><Icon name="globe" /> ritual</span>
        )}
        {entry.left !== undefined && <span>{entry.left} left</span>}
        {!!entry.active && (
          <span className="Spellbook__done">already cast</span>
        )}
        {entry.known && levels > 0 && (
          <span title={LEVEL_NAMES[entry.level] || 'Learned'}>
            <Gems count={entry.level} max={levels} small />
          </span>
        )}
      </div>
      <div className="Spellbook__desc">{entry.desc}</div>
      <div className="Spellbook__actions">
        {!!entry.can_refund && (
          <div
            className="Spellbook__seal Spellbook__seal--refund"
            onClick={() => act('refund', { index: entry.index })}>
            Refund
          </div>
        )}
        <div
          className={'Spellbook__seal'
            + (entry.can_buy ? '' : ' Spellbook__seal--off')}
          title={short ? 'Not enough points' : ''}
          onClick={entry.can_buy
            ? () => act('buy', { index: entry.index })
            : null}>
          {entry.known && entry.kind === 'spell' ? 'Improve' : entry.buy_word}
        </div>
      </div>
    </div>
  );
};

export const Spellbook = props => {
  const { act, data } = useBackend(props);
  const { points, tab, owner } = data;
  const categories = data.categories || [];
  const entries = (data.entries || []).filter(e => e.category === tab);
  const current = categories.find(c => c.name === tab);
  return (
    <div className="Spellbook">
      <div className="Spellbook__ribbons">
        {categories.map(category => (
          <div
            key={category.name}
            className={'Spellbook__ribbon'
              + (category.name === tab ? ' Spellbook__ribbon--on' : '')}
            onClick={() => act('page', { tab: category.name })}>
            {category.name}
          </div>
        ))}
      </div>
      <div className="Spellbook__page">
        <div className="Spellbook__top">
          <div>
            <div className="Spellbook__chapter">{tab}</div>
            <div className="Spellbook__owner">bound to {owner}</div>
          </div>
          <div className="Spellbook__points">
            <Gems count={points} max={Math.max(points, 10)} />
            <div className="Spellbook__pointsLabel">
              {points} point{points === 1 ? '' : 's'} left
            </div>
          </div>
        </div>
        {!!current && !!current.header && (
          <div className="Spellbook__header">{current.header}</div>
        )}
        <div className="Spellbook__entries">
          {entries.map(entry => (
            <Entry
              key={entry.index}
              act={act}
              entry={entry}
              points={points} />
          ))}
        </div>
      </div>
    </div>
  );
};
