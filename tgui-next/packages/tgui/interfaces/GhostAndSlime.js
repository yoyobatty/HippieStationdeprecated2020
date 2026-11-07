import { useBackend } from '../backend';
import { Box, Button, LabeledList, NoticeBox, ProgressBar, Section } from '../components';

// hippie -- the ghosts' notification preferences, the haunted 8-ball's vote and
// the slimeperson's body swap (were tgui/src/interfaces/notificationpanel.ract,
// eightball.ract and slime_swap_body.ract)

// A role's "enabled" is its pop-ups being ignored: lit ones still ask
export const NotificationPanel = props => {
  const { act, data } = useBackend(props);
  const roles = data.ignore || [];
  const asking = roles.filter(role => !role.enabled).length;
  return (
    <div className="GhostPops">
      <div className="GhostPops__head">
        Ghost role pop-ups
        <span className="GhostPops__count">
          {asking + ' / ' + roles.length + ' on'}
        </span>
      </div>
      <div className="GhostPops__grid">
        {roles.map(role => (
          <div
            key={role.key}
            className={'GhostPops__role'
              + (role.enabled ? '' : ' GhostPops__role--on')}
            onClick={() => act('toggle_ignore', { key: role.key })}>
            <span className="GhostPops__led" />
            {role.desc}
          </div>
        ))}
      </div>
    </div>
  );
};

export const Eightball = props => {
  const { act, data } = useBackend(props);
  const { shaking, question, answers = [] } = data;
  if (!shaking) {
    return (
      <NoticeBox>
        Nobody&apos;s shaking the 8-ball right now.
      </NoticeBox>
    );
  }
  const total = answers.reduce((sum, answer) => sum + answer.amount, 0);
  return (
    <Section title={'"' + question + '"'}>
      <Box color="label" mb={1}>
        The spirits&apos; answer is whichever gets the most votes.
      </Box>
      {answers.map(answer => (
        <Box key={answer.answer} mb={0.5}>
          <Button
            fluid
            selected={answer.selected}
            onClick={() => act('vote', { answer: answer.answer })}>
            <Box inline style={{ width: '45%' }}>
              {answer.answer}
            </Box>
            <Box inline style={{ width: '50%' }}>
              <ProgressBar
                color="good"
                value={total ? answer.amount / total : 0}
                content={answer.amount
                  + (answer.amount === 1 ? ' vote' : ' votes')} />
            </Box>
          </Button>
        </Box>
      ))}
    </Section>
  );
};

const STATUS_COLOR = {
  Conscious: 'good',
  Unconscious: 'average',
  Dead: 'bad',
};

export const SlimeBodySwapper = props => {
  const { act, data } = useBackend(props);
  const bodies = data.bodies || [];
  return (
    <Box>
      {bodies.map(body => (
        <Section
          key={body.ref}
          title={(
            <Box inline>
              <Box
                inline
                mr={1}
                style={{
                  width: '10px',
                  height: '10px',
                  'border-radius': '50%',
                  background: body.htmlcolor,
                  'box-shadow': '0 0 4px ' + body.htmlcolor,
                }} />
              {body.name}
            </Box>
          )}
          buttons={(
            <Button
              icon={body.occupied === 'owner' ? 'user' : 'exchange-alt'}
              selected={body.occupied === 'owner'}
              color={body.occupied === 'stranger' ? 'bad' : null}
              disabled={body.occupied !== 'owner' && !body.swappable}
              content={body.occupied === 'owner'
                ? 'You are here'
                : body.occupied === 'stranger' ? 'Occupied' : 'Swap'}
              onClick={() => act('swap', { ref: body.ref })} />
          )}>
          <LabeledList>
            <LabeledList.Item label="Status" color={STATUS_COLOR[body.status]}>
              {body.status}
            </LabeledList.Item>
            <LabeledList.Item label="Jelly">
              {Math.round(body.exoticblood)}
            </LabeledList.Item>
            <LabeledList.Item label="Location">
              {body.area}
            </LabeledList.Item>
          </LabeledList>
        </Section>
      ))}
    </Box>
  );
};
