import { Component, Fragment } from 'inferno';
import { useBackend } from '../backend';
import { Box, Button, Dropdown, Flex, Input, LabeledList, NoticeBox, Section } from '../components';

// hippie -- the newscaster (hippiestation/.../machinery/newscaster_tgui.dm).
// It opens onto a front page of the latest stories; a security unit has its
// censor and D-Notice buttons on the stories themselves.

const PRE = { 'white-space': 'pre-wrap' };

// Camera photos are small: scaled up, they stay sharp
const PHOTO = {
  '-ms-interpolation-mode': 'nearest-neighbor',
  'image-rendering': 'pixelated',
};

const FRONT_PAGE_STORIES = 15;

const goTo = (act, screen) => act('screen', { screen });

// What the last button did
const Notice = props => {
  const { notice } = props;
  if (!notice) {
    return null;
  }
  const good = notice[1] === 'good';
  return (
    <Box
      mb={1}
      p={1}
      color={good ? 'good' : 'bad'}
      style={{
        'background-color': good
          ? 'rgba(91, 170, 39, 0.15)'
          : 'rgba(219, 40, 40, 0.15)',
        'border-left': '3px solid currentColor',
      }}>
      {notice[0]}
    </Box>
  );
};

const Toolbar = props => {
  const { data, act } = props;
  const screen = data.screen;
  const items = [
    ['newspaper', 'Front page', screen === 0, () => goTo(act, 0)],
    ['list', 'Channels', screen === 1 || screen === 9,
      () => act('view')],
    ['pen', 'New story', screen === 3 || screen === 6,
      () => act('create_feed_story')],
    ['plus', 'New channel', screen === 2 || screen === 7,
      () => act('create_channel')],
  ];
  if (data.security) {
    items.push(['user-secret', 'Wanted', screen === 14 || screen === 16,
      () => act('menu_wanted')]);
  }
  return (
    <Flex mb={1}>
      {items.map(([icon, title, selected, onClick]) => (
        <Flex.Item key={title} grow={1} basis={0} mr={0.5}>
          <Button
            fluid
            textAlign="center"
            icon={icon}
            content={title}
            selected={selected}
            onClick={onClick} />
        </Flex.Item>
      ))}
      <Flex.Item grow={1} basis={0}>
        <Button
          fluid
          textAlign="center"
          icon="print"
          content={'Print (' + data.paper + ')'}
          tooltip={data.paper
            ? 'Print a newspaper: ' + data.paper + ' left in it'
            : 'Out of paper'}
          tooltipPosition="bottom-left"
          disabled={!data.paper}
          onClick={() => act('print_paper')} />
      </Flex.Item>
    </Flex>
  );
};

const WantedBanner = props => {
  const { data, act } = props;
  if (!data.wanted || data.screen === 18) {
    return null;
  }
  return (
    <Box
      mb={1}
      p={1}
      style={{
        'background-color': 'rgba(219, 40, 40, 0.2)',
        'border': '1px solid rgba(219, 40, 40, 0.6)',
      }}>
      <Flex align="center">
        <Flex.Item grow={1} bold color="bad">
          {'WANTED: ' + data.wanted.criminal}
        </Flex.Item>
        <Flex.Item>
          <Button
            color="bad"
            content="Read"
            onClick={() => act('view_wanted')} />
        </Flex.Item>
      </Flex>
    </Box>
  );
};

class CommentBox extends Component {
  constructor() {
    super();
    this.state = { text: '' };
  }

  render() {
    const { story, act } = this.props;
    return (
      <Flex mt={0.5}>
        <Flex.Item grow={1}>
          <Input
            fluid
            maxLength={140}
            placeholder="Write a comment..."
            value={this.state.text}
            onInput={(e, value) => this.setState({ text: value })} />
        </Flex.Item>
        <Flex.Item ml={0.5}>
          <Button
            icon="comment"
            content="Comment"
            disabled={!this.state.text}
            onClick={() => {
              act('comment', { ref: story.ref, text: this.state.text });
              this.setState({ text: '' });
            }} />
        </Flex.Item>
      </Flex>
    );
  }
}

const SecurityStoryButtons = props => {
  const { story, act } = props;
  return (
    <Box mt={0.5}>
      <Button
        icon="eye-slash"
        color={story.body_censored ? 'average' : null}
        content={story.body_censored ? 'Undo censorship' : 'Censor story'}
        onClick={() => act('censor_story_body', { ref: story.ref })} />
      <Button
        icon="user-slash"
        color={story.author_censored ? 'average' : null}
        content={story.author_censored
          ? 'Undo author censorship'
          : 'Censor author'}
        onClick={() => act('censor_story_author', { ref: story.ref })} />
    </Box>
  );
};

// A story. On the front page it says which channel and how many comments;
// in its channel it shows them, and the box to write one
const Story = props => {
  const { story, act, security, front } = props;
  const comments = story.comments || [];
  const count = comments.length + ' comment'
    + (comments.length === 1 ? '' : 's');
  return (
    <Section
      level={2}
      title={front && (
        <Button
          color="transparent"
          onClick={() => act('show_channel', { ref: story.channel_ref })}>
          <Box inline bold color="white">{story.channel}</Box>
        </Button>
      )}
      buttons={front && <Box color="label">{story.time}</Box>}>
      <Box style={PRE}>{story.body}</Box>
      {!!story.photo && (
        <Box mt={1}>
          <img src={story.photo} width="180px" style={PHOTO} />
          {!!story.caption && <Box color="label">{story.caption}</Box>}
        </Box>
      )}
      <Box color="label" fontSize="11px" mt={0.5}>
        {'Story by ' + story.author + (front ? '' : ' - ' + story.time)}
      </Box>
      {!!security && <SecurityStoryButtons story={story} act={act} />}
      {!!front && (
        <Box mt={0.5}>
          <Button
            icon="comments"
            color="transparent"
            content={count}
            onClick={() => act('show_channel', { ref: story.channel_ref })} />
        </Box>
      )}
      {!front && (
        <Box mt={1}>
          <Box bold fontSize="11px">
            {count}
            {!!story.can_lock && (
              <Button
                ml={1}
                icon={story.locked ? 'lock-open' : 'lock'}
                content={story.locked ? 'Unlock comments' : 'Lock comments'}
                onClick={() => act('lock_comment', { ref: story.ref })} />
            )}
          </Box>
          {comments.map(comment => (
            <Box key={comment.ref} ml={1} mt={0.5}>
              <Box style={PRE}>
                {comment.body}
                {!!security && (
                  <Button
                    ml={1}
                    icon="times"
                    color="bad"
                    tooltip="Delete"
                    onClick={() => act('del_comment', {
                      story: story.ref,
                      ref: comment.ref,
                    })} />
                )}
              </Box>
              <Box color="label" fontSize="10px">
                {comment.author + ' ' + comment.time}
              </Box>
            </Box>
          ))}
          {!!story.locked && (
            <Box bold color="label" mt={0.5}>Comments locked</Box>
          )}
          {!story.locked && <CommentBox story={story} act={act} />}
        </Box>
      )}
    </Section>
  );
};

const DNOTICE = 'This channel has been deemed as threatening to the welfare '
  + 'of the station, and marked with a Nanotrasen D-Notice. No further feed '
  + 'story additions are allowed while the D-Notice is in effect.';

const FrontPage = props => {
  const { data, act } = props;
  const stories = (data.front || [])
    .slice()
    .sort((a, b) => b.order - a.order)
    .slice(0, FRONT_PAGE_STORIES);
  return (
    <Section title="Latest stories">
      {stories.length === 0 && (
        <Box color="label">
          No stories yet. Start a channel, or write one for a channel
          that takes public stories.
        </Box>
      )}
      {stories.map(story => (
        <Story
          key={story.ref}
          story={story}
          act={act}
          security={data.security}
          front />
      ))}
    </Section>
  );
};

const ChannelList = props => {
  const { data, act } = props;
  const channels = data.channels || [];
  return (
    <Section title="Station Feed Channels">
      {channels.length === 0 && (
        <Box color="label">No active channels found...</Box>
      )}
      {channels.map(channel => (
        <Flex key={channel.ref} className="candystripe" p={0.5} align="center">
          <Flex.Item grow={1}>
            <Button
              color={channel.admin ? 'good' : 'transparent'}
              content={channel.name}
              onClick={() => act('show_channel', { ref: channel.ref })} />
            {!!channel.censored && (
              <Box inline color="bad" ml={1}>D-Notice</Box>
            )}
          </Flex.Item>
          <Flex.Item color="label">
            {'by ' + channel.author + ', ' + channel.stories + ' stor'
              + (channel.stories === 1 ? 'y' : 'ies')}
          </Flex.Item>
        </Flex>
      ))}
    </Section>
  );
};

const ChannelView = props => {
  const { data, act } = props;
  const channel = data.viewing;
  if (!channel) {
    return <NoticeBox>No channel selected.</NoticeBox>;
  }
  const stories = channel.messages || [];
  const hidden = channel.censored && !data.security;
  return (
    <Section
      title={channel.name}
      buttons={!!data.security && (
        <Fragment>
          <Button
            icon="user-slash"
            content={channel.author_censored
              ? 'Undo author censorship'
              : 'Censor author'}
            onClick={() => act('censor_channel_author', {
              ref: channel.ref,
            })} />
          <Button
            icon="ban"
            color={channel.censored ? 'good' : 'bad'}
            content={channel.censored ? 'Lift D-Notice' : 'D-Notice'}
            onClick={() => act('toggle_d_notice', { ref: channel.ref })} />
        </Fragment>
      )}>
      <Box color="label" mb={1}>
        {'Created by ' + channel.author
          + (channel.public ? '' : ', closed to public stories')}
      </Box>
      {!!channel.censored && <NoticeBox>{DNOTICE}</NoticeBox>}
      {!hidden && stories.length === 0 && (
        <Box color="label">No feed messages found in channel...</Box>
      )}
      {!hidden && stories.map(story => (
        <Story
          key={story.ref}
          story={story}
          act={act}
          security={data.security} />
      ))}
    </Section>
  );
};

const Errors = props => {
  const { title, errors, act, to } = props;
  return (
    <Section title={title}>
      {(errors || []).map(error => (
        <Box key={error} color="bad">{error}</Box>
      ))}
      <Box mt={1}>
        <Button
          icon="arrow-left"
          content="Back to it"
          onClick={() => to(act)} />
      </Box>
    </Section>
  );
};

class StoryForm extends Component {
  constructor(props) {
    super(props);
    this.state = { text: props.data.msg || '' };
  }

  render() {
    const { data, act } = this.props;
    const receiving = data.receiving || [];
    return (
      <Section title="New feed story">
        <LabeledList>
          <LabeledList.Item label="Channel">
            <Dropdown
              width="260px"
              options={receiving}
              selected={data.channel_name || 'Choose a channel'}
              onSelected={value => act('set_channel_receiving', {
                text: value,
              })} />
          </LabeledList.Item>
          <LabeledList.Item label="Author">
            <Box color="good">{data.user}</Box>
          </LabeledList.Item>
          <LabeledList.Item label="Photo">
            <Button
              icon="camera"
              content={data.photo_attached
                ? 'Photo attached'
                : 'Attach the photo in your hand'}
              selected={data.photo_attached}
              onClick={() => act('set_attachment')} />
          </LabeledList.Item>
          <LabeledList.Item label="Comments">
            <Button.Checkbox
              checked={data.allow_comments}
              content={data.allow_comments ? 'Allowed' : 'Off'}
              onClick={() => act('set_comment')} />
          </LabeledList.Item>
        </LabeledList>
        <textarea
          value={this.state.text}
          placeholder="Write your story..."
          onInput={e => this.setState({ text: e.target.value })}
          style={{
            'margin-top': '8px',
            'width': '100%',
            'height': '200px',
            'box-sizing': 'border-box',
            'background-color': 'rgba(0, 0, 0, 0.4)',
            'color': '#ffffff',
            'border': '1px solid #404b6e',
            'font-family': 'Verdana, sans-serif',
            'font-size': '12px',
          }} />
        <Box mt={1}>
          <Button
            icon="paper-plane"
            content="Submit"
            onClick={() => act('submit_story', { text: this.state.text })} />
        </Box>
      </Section>
    );
  }
}

const ChannelForm = props => {
  const { data, act } = props;
  return (
    <Section title="New feed channel">
      <LabeledList>
        <LabeledList.Item label="Name">
          <Input
            width="260px"
            value={data.channel_name}
            onChange={(e, value) => act('set_channel_name', { text: value })} />
        </LabeledList.Item>
        <LabeledList.Item label="Author">
          <Box color="good">{data.user}</Box>
        </LabeledList.Item>
        <LabeledList.Item label="Public stories">
          <Button.Checkbox
            checked={!data.c_locked}
            content={data.c_locked ? 'Only mine' : 'Anyone can post'}
            onClick={() => act('set_channel_lock')} />
        </LabeledList.Item>
      </LabeledList>
      <Box mt={1}>
        <Button
          icon="check"
          content="Submit"
          onClick={() => act('submit_channel')} />
      </Box>
    </Section>
  );
};

const WantedForm = props => {
  const { data, act } = props;
  const wanted = data.wanted;
  return (
    <Section title="Wanted issue">
      {!!wanted && (
        <Box color="label" mb={1}>
          A wanted issue is already in circulation. You can edit or take it
          down here.
        </Box>
      )}
      <LabeledList>
        <LabeledList.Item label="Criminal">
          <Input
            width="260px"
            value={data.channel_name}
            onChange={(e, value) => act('set_wanted_name', { text: value })} />
        </LabeledList.Item>
        <LabeledList.Item label="Description">
          <Input
            fluid
            value={data.msg}
            onChange={(e, value) => act('set_wanted_desc', { text: value })} />
        </LabeledList.Item>
        <LabeledList.Item label="Photo">
          <Button
            icon="camera"
            content={data.photo_attached
              ? 'Photo attached'
              : 'Attach the photo in your hand'}
            selected={data.photo_attached}
            onClick={() => act('set_attachment')} />
        </LabeledList.Item>
        <LabeledList.Item label={wanted ? 'Created by' : 'Prosecutor'}>
          <Box color="good">{wanted ? wanted.author : data.user}</Box>
        </LabeledList.Item>
      </LabeledList>
      <Box mt={1}>
        <Button
          icon="check"
          content={wanted ? 'Edit Issue' : 'Submit'}
          disabled={wanted && wanted.admin}
          onClick={() => act('submit_wanted')} />
        {!!wanted && (
          <Button
            icon="trash"
            color="bad"
            content="Take down Issue"
            disabled={wanted.admin}
            onClick={() => act('cancel_wanted')} />
        )}
      </Box>
    </Section>
  );
};

const WantedView = props => {
  const { data } = props;
  const wanted = data.wanted;
  if (!wanted) {
    return (
      <Section title="Wanted issue">
        <Box>No current wanted issue found.</Box>
      </Section>
    );
  }
  return (
    <Section title="-- STATIONWIDE WANTED ISSUE --">
      <Box color="label" mb={1}>{'Submitted by ' + wanted.author}</Box>
      <LabeledList>
        <LabeledList.Item label="Criminal">
          <Box bold color="bad">{wanted.criminal}</Box>
        </LabeledList.Item>
        <LabeledList.Item label="Description">
          <Box style={PRE}>{wanted.body}</Box>
        </LabeledList.Item>
        <LabeledList.Item label="Photo">
          {wanted.photo
            ? <img src={wanted.photo} width="180px" style={PHOTO} />
            : 'None'}
        </LabeledList.Item>
      </LabeledList>
    </Section>
  );
};

export const Newscaster = props => {
  const { act, data } = useBackend(props);
  const screen = data.screen;
  let body;
  switch (screen) {
    case 1:
      body = <ChannelList data={data} act={act} />;
      break;
    case 2:
      body = <ChannelForm data={data} act={act} />;
      break;
    case 3:
      body = <StoryForm data={data} act={act} />;
      break;
    case 6:
      body = (
        <Errors
          act={act}
          errors={data.errors}
          to={a => a('create_feed_story')}
          title="Could not submit the story" />
      );
      break;
    case 7:
      body = (
        <Errors
          act={act}
          errors={data.errors}
          to={a => a('create_channel')}
          title="Could not create the channel" />
      );
      break;
    case 9:
      body = <ChannelView data={data} act={act} />;
      break;
    case 14:
      body = <WantedForm data={data} act={act} />;
      break;
    case 16:
      body = (
        <Errors
          act={act}
          errors={data.errors}
          to={a => a('menu_wanted')}
          title="Wanted issue rejected by the network" />
      );
      break;
    case 18:
      body = <WantedView data={data} act={act} />;
      break;
    default:
      body = <FrontPage data={data} act={act} />;
  }
  return (
    <Fragment>
      <Toolbar data={data} act={act} />
      <Notice notice={data.notice} />
      <WantedBanner data={data} act={act} />
      {body}
      <Box color="label" mt={1}>
        {'The newscaster recognises you as: '}
        <Box inline color="good">{data.user}</Box>
      </Box>
    </Fragment>
  );
};
