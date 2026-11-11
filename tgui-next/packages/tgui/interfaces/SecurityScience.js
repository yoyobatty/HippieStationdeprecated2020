import { decodeHtmlEntities } from 'common/string';
import { Component, Fragment } from 'inferno';
import { useBackend } from '../backend';
import { Box, Button, Icon, Input, LabeledList, NoticeBox, NumberInput, ProgressBar, Section, Table } from '../components';

// hippie -- security and science machines moved off their old HTML
// windows: the prisoner management console, the AI system integrity
// restorer, the tachyon-doppler array and the automated announcement
// system. Data from hippiestation/code/game/machinery/computer/
// security_science_tgui.dm.

export class PrisonerConsole extends Component {
  constructor() {
    super();
    this.state = { messages: {} };
  }

  render() {
    const { act, data } = useBackend(this.props);
    const { messages } = this.state;
    const card = data.card;
    const chems = data.chem_implants || [];
    const trackers = data.tracking_implants || [];
    if (!data.unlocked) {
      return (
        <Section>
          <Button
            fluid
            textAlign="center"
            fontSize="14px"
            icon="lock"
            content="Unlock Console"
            onClick={() => act('lock')} />
        </Section>
      );
    }
    const setMessage = (ref, value) => this.setState({
      messages: { ...messages, [ref]: value },
    });
    return (
      <Fragment>
        <Section
          title="Prisoner ID"
          buttons={(
            <Button
              icon="lock"
              content="Lock Console"
              onClick={() => act('lock')} />
          )}>
          {card && (
            <Fragment>
              <Box mb={0.5}>
                <b>{card.name}</b>
                <Button
                  ml={1}
                  icon="eject"
                  content="Eject"
                  onClick={() => act('eject')} />
              </Box>
              <ProgressBar
                value={card.goal ? card.points / card.goal : 0}
                color={card.goal && card.points >= card.goal
                  ? 'good'
                  : 'average'}>
                {card.points} / {card.goal} points
              </ProgressBar>
              <Box mt={0.5}>
                <Box inline color="label" mr={1}>Goal</Box>
                <NumberInput
                  width="70px"
                  value={card.goal}
                  minValue={0}
                  maxValue={1000}
                  step={10}
                  onChange={(e, value) => act('goal', { goal: value })} />
                <Button
                  icon="undo"
                  content="Reset points"
                  onClick={() => act('reset')} />
              </Box>
              <Box mt={0.5} color="label" fontSize="11px">
                Space Law: 100 points per minute of brig time.
              </Box>
            </Fragment>
          ) || (
            <Button
              icon="id-card"
              content="Insert Prisoner ID"
              disabled={!data.holding_card}
              onClick={() => act('insert')} />
          )}
        </Section>
        <Section title={'Chemical Implants (' + chems.length + ')'}>
          {chems.length === 0 && (
            <Box color="label">None</Box>
          )}
          <Table>
            {chems.map(implant => (
              <Table.Row key={implant.ref} className="candystripe">
                <Table.Cell bold>{implant.name}</Table.Cell>
                <Table.Cell collapsing pr={1} color="label">
                  {implant.units} u
                </Table.Cell>
                <Table.Cell collapsing>
                  {[1, 5, 10].map(amount => (
                    <Button
                      key={amount}
                      color="bad"
                      content={'Inject ' + amount}
                      disabled={implant.units <= 0}
                      onClick={() => act('inject', {
                        ref: implant.ref,
                        amount,
                      })} />
                  ))}
                </Table.Cell>
              </Table.Row>
            ))}
          </Table>
        </Section>
        <Section title={'Tracking Implants (' + trackers.length + ')'}>
          {trackers.length === 0 && (
            <Box color="label">None</Box>
          )}
          {trackers.map(implant => (
            <Box key={implant.ref} className="candystripe" p={0.5}>
              <Box>
                <b>{implant.name}</b>
                <Box inline color="label" ml={1}>
                  <Icon name="map-marker-alt" mr={0.5} />
                  {implant.location}
                </Box>
              </Box>
              <Box mt={0.5}>
                <Input
                  width="300px"
                  placeholder="Message Holder"
                  value={messages[implant.ref] || ''}
                  onInput={(e, value) => setMessage(implant.ref, value)} />
                <Button
                  icon="comment"
                  content="Send"
                  disabled={!messages[implant.ref]}
                  onClick={() => {
                    act('warn', {
                      ref: implant.ref,
                      message: messages[implant.ref],
                    });
                    setMessage(implant.ref, '');
                  }} />
              </Box>
            </Box>
          ))}
        </Section>
      </Fragment>
    );
  }
}

const LAW_COLORS = {
  zeroth: 'bad',
  hacked: 'bad',
  ion: 'average',
  normal: null,
};

export const AiFixer = props => {
  const { act, data } = useBackend(props);
  const ai = data.ai;
  if (!ai) {
    return (
      <NoticeBox>No AI stored.</NoticeBox>
    );
  }
  return (
    <Fragment>
      <Section title={ai.name}>
        <LabeledList>
          <LabeledList.Item label="System integrity">
            <ProgressBar
              value={ai.integrity / 100}
              ranges={{
                good: [0.75, Infinity],
                average: [0.4, 0.75],
                bad: [-Infinity, 0.4],
              }}>
              {Math.round(ai.integrity)}%
            </ProgressBar>
          </LabeledList.Item>
          <LabeledList.Item label="Status" color={ai.dead ? 'bad' : 'good'}>
            {ai.dead ? 'AI non-functional' : 'AI functional'}
          </LabeledList.Item>
        </LabeledList>
        <Box mt={1}>
          {data.active && (
            <Box color="average">
              <Icon name="cog" spin mr={1} />
              Reconstruction in process, please wait.
            </Box>
          ) || (
            <Button
              icon="wrench"
              content="Begin Reconstruction"
              disabled={ai.integrity >= 100}
              onClick={() => act('fix')} />
          )}
        </Box>
      </Section>
      <Section title="Laws">
        {ai.laws.length === 0 && (
          <Box color="label">None</Box>
        )}
        {ai.laws.map((law, i) => (
          <Box key={i} mb={0.5} color={LAW_COLORS[law.kind]}>
            <b>{law.number}:</b> {law.text}
          </Box>
        ))}
      </Section>
    </Fragment>
  );
};

// A log entry as sense_explosion() (doppler_array.dm) writes it
const parseBlast = text => {
  const grid = /grid \((\d+),(\d+)\)/.exec(text);
  const took = /tachyons: ([\d.]+) seconds/.exec(text);
  const factual = /Factual: Epicenter radius: (-?\d+)\. Outer radius: (-?\d+)\. Shockwave radius: (-?\d+)/.exec(text);
  const theory = /Theoretical: Epicenter radius: (-?\d+)\. Outer radius: (-?\d+)\. Shockwave radius: (-?\d+)/.exec(text);
  if (!factual) {
    return null;
  }
  return {
    grid: grid && grid[1] + ', ' + grid[2],
    took: took && took[1],
    factual: factual.slice(1, 4),
    theory: theory && theory.slice(1, 4),
  };
};

const Radii = props => {
  const { radii, label, color } = props;
  return (
    <Box>
      <Box inline width="80px" color="label">{label}</Box>
      <Box inline bold color={color}>
        {radii[0]} / {radii[1]} / {radii[2]}
      </Box>
    </Box>
  );
};

export const DopplerArray = props => {
  const { act, data } = useBackend(props);
  const logs = data.logs || [];
  return (
    <Fragment>
      <Section>
        <LabeledList>
          <LabeledList.Item label="Dish facing">
            {data.facing}
          </LabeledList.Item>
          {data.best !== undefined && (
            <LabeledList.Item label="Largest bomb">
              <ProgressBar
                value={data.cap ? data.best / data.cap : 0}
                color="purple">
                {Math.round(data.best)} / {data.cap} points
              </ProgressBar>
            </LabeledList.Item>
          )}
        </LabeledList>
      </Section>
      <Section
        title={'Logs (' + logs.length + ')'}
        buttons={(
          <Button
            icon="trash"
            content="Delete logs"
            disabled={!logs.length}
            onClick={() => act('delete')} />
        )}>
        {logs.length === 0 && (
          <Box color="label">No explosions recorded.</Box>
        )}
        {logs.map((text, i) => {
          const blast = parseBlast(text);
          return (
            <div key={i} className="SecSci__log">
              <Box bold mb={0.5}>
                Log recording #{i + 1}
                {blast && blast.grid && (
                  <Box inline color="label" ml={1}>
                    grid ({blast.grid})
                  </Box>
                )}
              </Box>
              {blast && (
                <Fragment>
                  <Radii radii={blast.factual} label="Factual" />
                  {blast.theory && (
                    <Radii
                      radii={blast.theory}
                      label="Theoretical"
                      color="average" />
                  )}
                  <Box color="label" fontSize="11px" mt={0.5}>
                    Epicenter / Outer / Shockwave radius
                    {blast.took && ' · ' + blast.took + ' s displacement'}
                  </Box>
                </Fragment>
              ) || (
                <Box>{text}</Box>
              )}
            </div>
          );
        })}
      </Section>
    </Fragment>
  );
};

const Announcement = props => {
  const { act, title, text, on, toggleAction, setAction } = props;
  return (
    <Section
      title={title}
      buttons={(
        <Button
          icon="power-off"
          selected={on}
          content={on ? 'On' : 'Off'}
          onClick={() => act(toggleAction)} />
      )}>
      <Input
        fluid
        value={decodeHtmlEntities(text || '')}
        onChange={(e, value) => act(setAction, { text: value })} />
    </Section>
  );
};

export const AnnouncementSystem = props => {
  const { act, data } = useBackend(props);
  return (
    <Fragment>
      <Announcement
        act={act}
        title="Arrival Announcement"
        text={data.arrival}
        on={data.arrival_on}
        toggleAction="toggle_arrival"
        setAction="arrival" />
      <Announcement
        act={act}
        title="Departmental Head Announcement"
        text={data.newhead}
        on={data.newhead_on}
        toggleAction="toggle_newhead"
        setAction="newhead" />
      <Box color="label" fontSize="11px">
        %PERSON, %RANK
      </Box>
    </Fragment>
  );
};
