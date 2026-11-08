import { decodeHtmlEntities } from 'common/string';
import { Component, Fragment } from 'inferno';
import { useBackend } from '../backend';
import { Box, Button, Icon, Input, LabeledList, NoticeBox, Section } from '../components';

// hippie -- the antagonists' windows: the malf AI's module picker, the
// arcane tome, the gang tool, the apprentice contract, the teleportation
// scroll, the radioactive microlaser, the pirates' cargo hold console and
// the role tips. Data and actions from
// hippiestation/code/modules/antagonists/antag_windows_tgui.dm.

// The malfunctioning AI's modules: a shop of processing time
export const MalfModules = props => {
  const { act, data } = useBackend(props);
  const modules = data.modules || [];
  const group = (title, large) => (
    <Section title={title}>
      {modules.filter(m => !!m.large === large).map(m => (
        <div key={m.key} className="Malf__module">
          <div className="Malf__head">
            <span className="Malf__name">{m.name}</span>
            {!!m.owned && (
              <span className="Malf__owned">
                {m.uses !== null && m.uses !== undefined
                  ? m.uses + (m.uses === 1 ? ' use' : ' uses')
                  : 'Installed'}
              </span>
            )}
            <Button
              icon="microchip"
              content={m.cost}
              disabled={m.cost > data.points}
              tooltip={m.owned ? 'Add uses' : 'Install'}
              onClick={() => act('buy', { key: m.key })} />
          </div>
          <div className="Malf__desc">{m.desc}</div>
        </div>
      ))}
    </Section>
  );
  return (
    <Fragment>
      <Box className="Malf__points">
        <Icon name="microchip" /> {data.points} processing time left
      </Box>
      {!!data.notice && <NoticeBox>{data.notice}</NoticeBox>}
      {group('Large modules', true)}
      {group('Small modules', false)}
    </Fragment>
  );
};

// The arcane tome: scribe a rune, or read the archives
export class ArcaneTome extends Component {
  constructor() {
    super();
    this.state = { part: 'Runes' };
  }

  render() {
    const { act, data } = useBackend(this.props);
    const pages = data.pages || [];
    const parts = [];
    for (let page of pages) {
      if (!parts.includes(page.part)) {
        parts.push(page.part);
      }
    }
    return (
      <div className="Tome">
        <div className="Tome__head">
          <div className="Tome__title">Archives of the Dark One</div>
          <div
            className="Tome__scribe"
            onClick={() => act('scribe')}>
            Scribe a rune
          </div>
        </div>
        <div className="Tome__tabs">
          {parts.map(part => (
            <div
              key={part}
              className={'Tome__tab'
                + (part === this.state.part ? ' Tome__tab--on' : '')}
              onClick={() => this.setState({ part })}>
              {part}
            </div>
          ))}
        </div>
        <div className="Tome__pages">
          {this.state.part === 'Runes' && (
            <div className="Tome__note">
              Examine a rune to learn its name and effects.
            </div>
          )}
          {pages.filter(page => page.part === this.state.part).map(page => (
            <div key={page.name} className="Tome__page">
              <div className="Tome__name">
                {page.name}
                {!!page.need && (
                  <span className="Tome__need">needed for your goals</span>
                )}
              </div>
              <div>{page.text}</div>
            </div>
          ))}
        </div>
      </div>
    );
  }
}

// The gang tool: the gang's standing, messages and the shop
export class GangTool extends Component {
  constructor() {
    super();
    this.state = { message: '' };
  }

  render() {
    const { act, data } = useBackend(this.props);
    if (data.mode !== 'vigilante' && !data.registered) {
      return (
        <Section title="Unregistered device">
          {!!data.is_boss && (
            <Fragment>
              {!!data.promotable && !!data.promotion_open && (
                <Box mb={1}>
                  Give this to another member to promote them to Lieutenant,
                  or keep it as your spare.
                </Box>
              )}
              <Button
                icon="id-card"
                content="Register as spare"
                onClick={() => act('register')} />
            </Fragment>
          )}
          {!data.is_boss && !!data.promotable && (
            data.promotion_open
              ? (
                <Fragment>
                  <Box mb={1}>You have been selected for a promotion!</Box>
                  <Button
                    icon="star"
                    content="Accept promotion"
                    onClick={() => act('register')} />
                </Fragment>
              )
              : <Box>No promotions available: all positions filled.</Box>
          )}
          {!data.is_boss && !data.promotable && (
            <Box>This device is not authorized to promote.</Box>
          )}
        </Section>
      );
    }
    const vigilante = data.mode === 'vigilante';
    const color = vigilante ? '#4a90d9' : (data.color || '#888');
    return (
      <Fragment>
        <div className="Gang__card" style={{ 'border-color': color }}>
          <div className="Gang__name" style={{ color }}>
            {vigilante ? 'Vigilante' : data.gang + ' Gang'}
            <span className="Gang__rank">
              {vigilante ? '' : data.mode === 'boss' ? 'Boss' : 'Gangster'}
            </span>
          </div>
          <div className="Gang__stats">
            {!vigilante && (
              <Fragment>
                <span><Icon name="users" /> {data.members} members</span>
                <span><Icon name="map" /> {data.territories} territories</span>
              </Fragment>
            )}
            <span><Icon name="coins" /> {data.influence} influence</span>
            {!!data.next_influence && (
              <span className="Gang__muted">
                +more in {data.next_influence}
              </span>
            )}
          </div>
          {!!data.takeover && (
            <div className="Gang__takeover">
              Takeover in progress: {data.takeover} remain
            </div>
          )}
        </div>
        {vigilante && (
          <Section>
            <Button
              fluid
              icon="trash"
              color="bad"
              content="Destroy held contraband for influence"
              onClick={() => act('destroy')} />
          </Section>
        )}
        {!vigilante && (
          <Section title="Gang">
            <Box className="Gang__send">
              <Input
                fluid
                placeholder="Message the gang..."
                value={this.state.message}
                onInput={(e, value) => this.setState({ message: value })} />
              <Button
                icon="paper-plane"
                content="Send"
                disabled={!this.state.message}
                onClick={() => {
                  act('message', { text: this.state.message });
                  this.setState({ message: '' });
                }} />
            </Box>
            {!!data.can_recall && (
              <Button
                mt={1}
                icon="undo"
                content={data.recalling ? 'Recalling...' : 'Recall shuttle'}
                disabled={data.recalling}
                onClick={() => act('recall')} />
            )}
          </Section>
        )}
        {(data.categories || []).map(cat => (
          <Section key={cat.name} title={cat.name}>
            {cat.items.map(item => (
              <div key={item.id} className="Gang__item">
                <div className="Gang__itemMain">
                  <div>{item.name}</div>
                  {!!item.extra && (
                    <div className="Gang__muted">{item.extra}</div>
                  )}
                </div>
                <Button
                  content={item.cost || 'Get'}
                  disabled={!item.can_buy}
                  onClick={() => act('buy', { id: item.id, cat: cat.name })} />
              </div>
            ))}
          </Section>
        ))}
      </Fragment>
    );
  }
}

// The wizard's contract of apprenticeship
export const ApprenticeContract = props => {
  const { act, data } = useBackend(props);
  return (
    <div className="Arcane">
      <div className="Arcane__title">Contract of Apprenticeship</div>
      {!!data.used && (
        <div className="Arcane__para">
          You have already summoned your apprentice.
        </div>
      )}
      {!data.used && (
        <Fragment>
          <div className="Arcane__para">
            Summon an apprentice to aid you. If none answers, feed the
            contract back to the spellbook for your points.
          </div>
          {!!data.waiting && (
            <div className="Arcane__para Arcane__waiting">
              Reaching out to an apprentice...
            </div>
          )}
          <div className="Arcane__sub">Which school are they studying?</div>
          {(data.schools || []).map(school => (
            <div
              key={school.id}
              className={'Arcane__choice'
                + (data.waiting ? ' Arcane__choice--off' : '')}
              onClick={() => !data.waiting
                && act('school', { id: school.id })}>
              <div className="Arcane__choiceName">{school.name}</div>
              <div>{school.desc}</div>
            </div>
          ))}
        </Fragment>
      )}
    </div>
  );
};

// The scroll of teleportation
export class TeleportScroll extends Component {
  constructor() {
    super();
    this.state = { search: '' };
  }

  render() {
    const { act, data } = useBackend(this.props);
    const query = this.state.search.toLowerCase();
    const areas = (data.areas || []).filter(a => !query
      || a.toLowerCase().includes(query));
    return (
      <div className="Arcane">
        <div className="Arcane__title">Scroll of Teleportation</div>
        <div className="Arcane__para">
          {data.uses} {data.uses === 1 ? 'use' : 'uses'} left. Use them
          wisely, and bring your gear: most spells need it.
        </div>
        <input
          className="Arcane__search"
          placeholder="Where to?"
          value={this.state.search}
          onInput={e => this.setState({ search: e.target.value })} />
        <div className="Arcane__areas">
          {areas.map(area => (
            <div
              key={area}
              className={'Arcane__area'
                + (data.uses ? '' : ' Arcane__choice--off')}
              onClick={() => data.uses && act('teleport', { area })}>
              {area}
            </div>
          ))}
        </div>
        <div className="Arcane__sign">Kind regards, Wizards Federation</div>
      </div>
    );
  }
}

const SCAN_MODES = ['Health', 'Reagents', 'Off'];

const Stepper = props => {
  const { value, act, action } = props;
  return (
    <Fragment>
      <Button icon="angle-double-left"
        onClick={() => act(action, { by: -5 })} />
      <Button icon="angle-left" onClick={() => act(action, { by: -1 })} />
      <Box inline bold mx={1} style={{ 'min-width': '30px' }}
        textAlign="center">
        {value}
      </Box>
      <Button icon="angle-right" onClick={() => act(action, { by: 1 })} />
      <Button icon="angle-double-right"
        onClick={() => act(action, { by: 5 })} />
    </Fragment>
  );
};

// The radioactive microlaser
export const RadLaser = props => {
  const { act, data } = useBackend(props);
  return (
    <Section title="Microlaser">
      <LabeledList>
        <LabeledList.Item label="Irradiation">
          <Button
            icon="radiation"
            content={data.irradiate ? 'On' : 'Off'}
            selected={data.irradiate}
            onClick={() => act('irradiate')} />
        </LabeledList.Item>
        <LabeledList.Item label="Stealth">
          <Button
            icon="user-secret"
            content={data.stealth ? 'On' : 'Off'}
            selected={data.stealth}
            disabled={!data.irradiate}
            onClick={() => act('stealth')} />
        </LabeledList.Item>
        <LabeledList.Item label="Scan">
          <Button
            icon="search"
            content={SCAN_MODES[data.scanmode] || 'Off'}
            onClick={() => act('mode')} />
        </LabeledList.Item>
        <LabeledList.Item label="Intensity">
          <Stepper value={data.intensity} act={act} action="intensity" />
        </LabeledList.Item>
        <LabeledList.Item label="Delay">
          <Stepper value={data.wavelength + ' s'} act={act}
            action="wavelength" />
        </LabeledList.Item>
        <LabeledList.Item label="Cooldown">
          {data.cooldown}
          {!!data.cooling && (
            <Box inline color="average" ml={1}>(cooling)</Box>
          )}
        </LabeledList.Item>
      </LabeledList>
    </Section>
  );
};

// The pirates' cargo hold console
export const PiratePad = props => {
  const { act, data } = useBackend(props);
  return (
    <Section
      title="Cargo hold"
      buttons={(
        <Box inline bold color="good">
          <Icon name="coins" /> {data.points}
        </Box>
      )}>
      {!data.pad && <NoticeBox>No pad located.</NoticeBox>}
      {!!data.pad && (
        <Fragment>
          <Box mb={1}>
            {!data.sending && (
              <Fragment>
                <Button icon="calculator" content="Recalculate value"
                  onClick={() => act('recalc')} />
                <Button icon="paper-plane" content="Send"
                  onClick={() => act('send')} />
              </Fragment>
            )}
            {!!data.sending && (
              <Button icon="stop" color="bad" content="Stop sending"
                onClick={() => act('stop')} />
            )}
          </Box>
          {(data.report || []).map((line, i) => (
            <Box key={i} color={i === 0 ? 'label' : null}>
              {decodeHtmlEntities(line)}
            </Box>
          ))}
        </Fragment>
      )}
    </Section>
  );
};

// The role tips, as the HTML page they always were
export const AntagTips = props => {
  const { data } = useBackend(props);
  return (
    <div
      className="AntagTips"
      // The tips are this server's own pages (hippiestation/html/antagtips)
      // eslint-disable-next-line react/no-danger
      dangerouslySetInnerHTML={{ __html: data.html }} />
  );
};
