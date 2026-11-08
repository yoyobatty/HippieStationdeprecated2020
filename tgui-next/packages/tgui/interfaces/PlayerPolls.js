import { decodeHtmlEntities } from 'common/string';
import { Component, Fragment } from 'inferno';
import { useBackend } from '../backend';
import { Box, Button, Icon, NoticeBox, Section } from '../components';

// hippie -- player polls: the open polls, and one poll to answer (a pick,
// a written reply, ratings, several picks, or a ranking). Data and actions
// from hippiestation/code/modules/mob/dead/new_player/polls_tgui.dm.

const TYPE_NAMES = {
  OPTION: 'Pick one',
  TEXT: 'Written reply',
  NUMVAL: 'Rate each',
  MULTICHOICE: 'Pick several',
  IRV: 'Rank them',
};

const text = value => decodeHtmlEntities(String(value || ''));

class PollForm extends Component {
  constructor(props) {
    super(props);
    const poll = props.poll;
    const voted = poll.voted || [];
    let order = (poll.options || []).map(o => o.id);
    if (poll.type === 'IRV' && Array.isArray(voted) && voted.length) {
      order = voted.concat(order.filter(id => !voted.includes(id)));
    }
    this.state = {
      option: null,
      text: poll.reply ? text(poll.reply) : '',
      picked: {},
      order,
    };
  }

  render() {
    const { poll, act } = this.props;
    const options = poll.options || [];
    const voted = poll.voted || [];
    const byId = {};
    for (let o of options) {
      byId[o.id] = o;
    }
    const send = extra => act('vote', extra);
    switch (poll.type) {
      case 'OPTION': {
        const done = voted.length > 0;
        return (
          <Fragment>
            {options.map(o => {
              const chosen = done
                ? voted.includes(o.id)
                : this.state.option === o.id;
              return (
                <div
                  key={o.id}
                  className={'Polls__option'
                    + (chosen ? ' Polls__option--on' : '')
                    + (done ? ' Polls__option--done' : '')}
                  onClick={() => !done && this.setState({ option: o.id })}>
                  <Icon name={chosen ? 'dot-circle' : 'circle'} mr={1} />
                  {text(o.text)}
                </div>
              );
            })}
            {done
              ? <Box mt={1} color="good">You voted.</Box>
              : (
                <Button mt={1} icon="vote-yea" content="Vote"
                  disabled={!this.state.option}
                  onClick={() => send({ option: this.state.option })} />
              )}
          </Fragment>
        );
      }
      case 'TEXT':
        return (
          <Fragment>
            <textarea
              className="Polls__text"
              value={this.state.text}
              onInput={e => this.setState({ text: e.target.value })} />
            <Button mt={1} icon="paper-plane"
              content={poll.reply ? 'Update reply' : 'Send reply'}
              disabled={!this.state.text.trim()}
              onClick={() => send({ text: this.state.text })} />
          </Fragment>
        );
      case 'NUMVAL': {
        const done = Object.keys(voted).length > 0;
        return (
          <Fragment>
            {options.map(o => {
              const value = done ? voted[o.id] : this.state.picked[o.id];
              const values = [];
              for (let v = o.min; v <= o.max; v++) {
                values.push(v);
              }
              return (
                <Box key={o.id} className="Polls__rating">
                  <Box bold mb={0.5}>{text(o.text)}</Box>
                  {values.map(v => (
                    <Button
                      key={v}
                      content={v}
                      selected={value === v}
                      disabled={done}
                      onClick={() => this.setState(state => ({
                        picked: Object.assign({}, state.picked,
                          { [o.id]: v }),
                      }))} />
                  ))}
                  <Button
                    content="Abstain"
                    selected={value === 'abstain'}
                    disabled={done}
                    onClick={() => this.setState(state => ({
                      picked: Object.assign({}, state.picked,
                        { [o.id]: 'abstain' }),
                    }))} />
                  {(o.desc_min || o.desc_mid || o.desc_max) && (
                    <Box className="Polls__scale">
                      <span>{text(o.desc_min)}</span>
                      <span>{text(o.desc_mid)}</span>
                      <span>{text(o.desc_max)}</span>
                    </Box>
                  )}
                </Box>
              );
            })}
            {done
              ? <Box mt={1} color="good">You voted.</Box>
              : (
                <Button mt={1} icon="vote-yea" content="Vote"
                  disabled={!Object.keys(this.state.picked).length}
                  onClick={() => send({
                    picked: JSON.stringify(this.state.picked),
                  })} />
              )}
          </Fragment>
        );
      }
      case 'MULTICHOICE': {
        const done = voted.length > 0;
        const count = Object.keys(this.state.picked)
          .filter(id => this.state.picked[id]).length;
        return (
          <Fragment>
            <Box color="label" mb={1}>
              Pick up to {poll.max_choices}.
            </Box>
            {options.map(o => {
              const on = done
                ? voted.includes(o.id)
                : !!this.state.picked[o.id];
              return (
                <div
                  key={o.id}
                  className={'Polls__option'
                    + (on ? ' Polls__option--on' : '')
                    + (done ? ' Polls__option--done' : '')}
                  onClick={() => {
                    if (done || (!on && count >= poll.max_choices)) {
                      return;
                    }
                    this.setState(state => ({
                      picked: Object.assign({}, state.picked,
                        { [o.id]: !on }),
                    }));
                  }}>
                  <Icon name={on ? 'check-square' : 'square'} mr={1} />
                  {text(o.text)}
                </div>
              );
            })}
            {done
              ? <Box mt={1} color="good">You voted.</Box>
              : (
                <Button mt={1} icon="vote-yea" content="Vote"
                  disabled={!count}
                  onClick={() => send({
                    picked: JSON.stringify(this.state.picked),
                  })} />
              )}
          </Fragment>
        );
      }
      case 'IRV': {
        const order = this.state.order;
        const move = (i, by) => {
          const next = order.slice();
          const [item] = next.splice(i, 1);
          next.splice(i + by, 0, item);
          this.setState({ order: next });
        };
        return (
          <Fragment>
            <Box color="label" mb={1}>Most preferred at the top.</Box>
            {order.map((id, i) => (
              <div key={id} className="Polls__rank">
                <span className="Polls__rankNo">{i + 1}</span>
                <span className="Polls__rankText">
                  {text(byId[id] && byId[id].text)}
                </span>
                <Button icon="arrow-up" disabled={i === 0}
                  onClick={() => move(i, -1)} />
                <Button icon="arrow-down" disabled={i === order.length - 1}
                  onClick={() => move(i, 1)} />
              </div>
            ))}
            <Button mt={1} icon="vote-yea"
              content={voted.length ? 'Vote again' : 'Vote'}
              onClick={() => send({ order: order.join(',') })} />
          </Fragment>
        );
      }
      default:
        return <Box color="label">This poll type isn&#39;t known.</Box>;
    }
  }
}

export const PlayerPolls = props => {
  const { act, data } = useBackend(props);
  const poll = data.poll;
  if (poll && poll.question) {
    return (
      <Section
        title={TYPE_NAMES[poll.type] || 'Poll'}
        buttons={(
          <Button icon="arrow-left" content="All polls"
            onClick={() => act('list')} />
        )}>
        <Box className="Polls__question">{text(poll.question)}</Box>
        <Box color="label" mb={1}>
          Open {poll.start} to {poll.end}
        </Box>
        {!!data.loading && <Box color="label">Loading...</Box>}
        <PollForm key={poll.id + ':' + JSON.stringify(poll.voted)}
          poll={poll} act={act} />
      </Section>
    );
  }
  const polls = data.polls || [];
  return (
    <Section title="Open polls">
      {!!data.error && <NoticeBox>{data.error}</NoticeBox>}
      {!!data.loading && <Box color="label">Loading...</Box>}
      {!data.loading && !data.error && polls.length === 0 && (
        <Box color="label">No polls are open.</Box>
      )}
      {polls.map(p => (
        <div key={p.id} className="Polls__item"
          onClick={() => act('open', { id: p.id })}>
          <Icon name="poll" mr={1} />
          {text(p.question)}
        </div>
      ))}
    </Section>
  );
};

export const HtmlNotice = props => {
  const { data } = useBackend(props);
  return (
    <Section>
      <div
        className="HtmlNotice"
        // The server's own pages (the policy config, the playtime report)
        // eslint-disable-next-line react/no-danger
        dangerouslySetInnerHTML={{ __html: data.html }} />
    </Section>
  );
};
