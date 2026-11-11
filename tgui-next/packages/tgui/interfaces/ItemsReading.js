import { decodeHtmlEntities } from 'common/string';
import { Fragment } from 'inferno';
import { useBackend } from '../backend';
import { Box, Button, Icon, NoticeBox, Section } from '../components';

// hippie -- small things to read or pick from: a hand of cards, the
// newspaper, the hand teleporter's locator and a valentine. Data and actions
// from hippiestation/code/game/objects/items/items_reading_tgui.dm.

const SUITS = {
  hearts: ['♥', '#d42a2a'],
  diamonds: ['♦', '#d42a2a'],
  clubs: ['♣', '#1b1b1b'],
  spades: ['♠', '#1b1b1b'],
};

// "Ace of Hearts" -> its suit's mark and colour, for the card face
const suitOf = card => {
  const lower = card.toLowerCase();
  for (let suit of Object.keys(SUITS)) {
    if (lower.includes(suit)) {
      return SUITS[suit];
    }
  }
  return ['★', '#3a5ea8'];
};

export const CardHand = props => {
  const { act, data } = useBackend(props);
  const cards = data.cards || [];
  return (
    <div className="Cards">
      <div className="Cards__hint">Which card will you take out?</div>
      <div className="Cards__fan">
        {cards.map(card => {
          const [mark, color] = suitOf(card);
          return (
            <div
              key={card}
              className="Cards__card"
              style={{ color }}
              onClick={() => act('pick', { card })}>
              <div className="Cards__corner">{mark}</div>
              <div className="Cards__mark">{mark}</div>
              <div className="Cards__name">{card}</div>
            </div>
          );
        })}
      </div>
    </div>
  );
};

export const Newspaper = props => {
  const { act, data } = useBackend(props);
  const nav = (
    <div className="News__nav">
      <Button
        icon="chevron-left"
        content="Previous"
        disabled={data.screen === 0}
        onClick={() => act('prev')} />
      <span className="News__pageNo">
        Page {data.page + 1} of {data.pages}
      </span>
      <Button
        icon="chevron-right"
        content="Next"
        disabled={data.screen === 2}
        onClick={() => act('next')} />
    </div>
  );
  return (
    <div className="News">
      <div className="News__paper">
        {data.screen === 0 && (
          <Fragment>
            <div className="News__masthead">The Griffon</div>
            <div className="News__tagline">
              Nanotrasen-standard newspaper, for use on Nanotrasen space
              facilities
            </div>
            {(data.contents || []).length === 0 && !data.wanted && (
              <div className="News__empty">
                Other than the title, the rest of the newspaper is
                unprinted...
              </div>
            )}
            {((data.contents || []).length > 0 || !!data.wanted) && (
              <div className="News__contents">
                <div className="News__h">Contents</div>
                {!!data.wanted && (
                  <div className="News__line News__line--wanted">
                    <span>** Important Security Announcement **</span>
                    <span>page {data.wanted_page}</span>
                  </div>
                )}
                {(data.contents || []).map(item => (
                  <div key={item.page} className="News__line">
                    <span>{decodeHtmlEntities(item.name)}</span>
                    <span>page {item.page}</span>
                  </div>
                ))}
              </div>
            )}
          </Fragment>
        )}
        {data.screen === 1 && !!data.channel && (
          <Fragment>
            <div className="News__channel">
              {decodeHtmlEntities(data.channel.name)}
            </div>
            <div className="News__byline">
              created by {decodeHtmlEntities(data.channel.author)}
            </div>
            {!!data.channel.dnotice && (
              <div className="News__dnotice">
                This channel was deemed dangerous to the general welfare of
                the station and marked with a D-Notice. Its contents were not
                printed.
              </div>
            )}
            {!data.channel.dnotice && data.channel.stories.length === 0 && (
              <div className="News__empty">
                No stories stem from this channel...
              </div>
            )}
            {data.channel.stories.map((story, i) => (
              <div key={i} className="News__story">
                <div>{decodeHtmlEntities(story.body)}</div>
                {!!story.img && (
                  <img className="News__img" src={story.img} />
                )}
                <div className="News__byline">
                  Story by {decodeHtmlEntities(story.author)}
                </div>
              </div>
            ))}
          </Fragment>
        )}
        {data.screen === 2 && (
          <Fragment>
            {!data.wanted_issue && (
              <div className="News__empty">
                Apart from some uninteresting classified ads, there&#39;s
                nothing on this page...
              </div>
            )}
            {!!data.wanted_issue && (
              <div className="News__wanted">
                <div className="News__wantedHead">WANTED</div>
                <div className="News__h">
                  {decodeHtmlEntities(data.wanted_issue.criminal)}
                </div>
                <div>{decodeHtmlEntities(data.wanted_issue.body)}</div>
                {!!data.wanted_issue.img && (
                  <img className="News__img" src={data.wanted_issue.img} />
                )}
              </div>
            )}
          </Fragment>
        )}
        {!!data.scribble && (
          <div className="News__scribble">
            A small scribble near the end of the page reads:
            {' "' + decodeHtmlEntities(data.scribble) + '"'}
          </div>
        )}
      </div>
      {nav}
    </div>
  );
};

const SignalList = props => {
  const { title, items, icon } = props;
  return (
    <Section title={title} level={2}>
      {items.length === 0 && <Box color="label">None in range.</Box>}
      {items.map((item, i) => (
        <Box key={i} className="Locator__row">
          <Icon name={icon} mr={1} />
          <span className="Locator__name">{item.name}</span>
          <span className="Locator__dir">{item.dir}</span>
          <span className={'Locator__str Locator__str--'
            + item.strength.replace(' ', '-')}>
            {item.strength}
          </span>
        </Box>
      ))}
    </Section>
  );
};

export const Locator = props => {
  const { act, data } = useBackend(props);
  const scan = data.scan;
  return (
    <Section
      title="Signals"
      buttons={(
        <Fragment>
          <Button
            icon="sync"
            content="Refresh"
            onClick={() => act('refresh')} />
          {!!scan && (
            <Button icon="times" content="Clear"
              onClick={() => act('clear')} />
          )}
        </Fragment>
      )}>
      {!scan && <Box color="label">No signals.</Box>}
      {!!scan && !!scan.error && <NoticeBox>{scan.error}</NoticeBox>}
      {!!scan && !scan.error && (
        <Fragment>
          <SignalList
            title="Beacons"
            items={scan.beacons}
            icon="broadcast-tower" />
          <SignalList title="Tracking implants" items={scan.implants}
            icon="user" />
          <Box mt={1} color="label">
            You are at [{scan.x}, {scan.y}, {scan.z}] in orbital coordinates.
          </Box>
        </Fragment>
      )}
    </Section>
  );
};

// "valentine - To: Maya From: Hugo" -> "To Maya, from Hugo"
const valentineFrom = name => {
  const text = decodeHtmlEntities(name || '');
  const match = text.match(/To: (.*) From: (.*)$/);
  return match ? 'To ' + match[1] + ', from ' + match[2] : text;
};

export const Valentine = props => {
  const { data } = useBackend(props);
  return (
    <div className="Valentine">
      <div className="Valentine__card">
        <div className="Valentine__heart">{'♥'}</div>
        <div className="Valentine__msg">{decodeHtmlEntities(data.message)}</div>
        <div className="Valentine__name">{valentineFrom(data.name)}</div>
      </div>
    </div>
  );
};
