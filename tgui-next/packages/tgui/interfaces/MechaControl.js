import { Component } from 'inferno';
import { useBackend } from '../backend';
import { Box, Button, LabeledList, ProgressBar, Section } from '../components';

// hippie -- the exosuit control console
// (hippiestation/code/game/mecha/mecha_control_tgui.dm)

const barColor = percent => {
  if (percent < 30) {
    return 'bad';
  }
  return percent < 60 ? 'average' : 'good';
};

class MechCard extends Component {
  constructor() {
    super();
    this.state = { text: '', sure: false };
  }

  render() {
    const { mech, act } = this.props;
    const send = () => {
      if (!this.state.text) {
        return;
      }
      act('message', { ref: mech.ref, text: this.state.text });
      this.setState({ text: '' });
    };
    let pulse = (
      <Button
        icon="bolt"
        content="EMP pulse"
        color="bad"
        disabled={mech.recharging}
        onClick={() => this.setState({ sure: true })} />
    );
    if (mech.recharging) {
      pulse = <Button icon="bolt" content="Recharging..." disabled />;
    }
    else if (this.state.sure) {
      pulse = (
        <Button
          icon="exclamation-triangle"
          content="Sure?"
          color="bad"
          onClick={() => {
            act('shock', { ref: mech.ref });
            this.setState({ sure: false });
          }} />
      );
    }
    return (
      <Section
        title={mech.name}
        buttons={(
          <Box inline>
            {!!mech.ai && (
              <Box inline color="average" mr={1}>AI beacon</Box>
            )}
            {pulse}
          </Box>
        )}>
        <LabeledList>
          <LabeledList.Item label="Integrity">
            <ProgressBar
              value={mech.integrity}
              maxValue={100}
              color={barColor(mech.integrity)}
              content={mech.integrity + '%'} />
          </LabeledList.Item>
          <LabeledList.Item label="Power">
            {mech.cell === null && <Box color="bad">No power cell</Box>}
            {mech.cell !== null && (
              <ProgressBar
                value={mech.cell}
                maxValue={100}
                color={barColor(mech.cell)}
                content={mech.cell + '%'} />
            )}
          </LabeledList.Item>
          <LabeledList.Item label="Pilot" color={mech.pilot ? null : 'label'}>
            {mech.pilot || 'Nobody'}
          </LabeledList.Item>
          <LabeledList.Item label="Location">{mech.location}</LabeledList.Item>
          <LabeledList.Item label="In hand">
            {mech.active || 'Nothing'}
          </LabeledList.Item>
          <LabeledList.Item label="Airtank">
            {mech.airtank === null ? 'Not fitted' : mech.airtank + ' kPa'}
          </LabeledList.Item>
          {mech.cargo !== undefined && (
            <LabeledList.Item label="Cargo">
              {mech.cargo + '% full'}
            </LabeledList.Item>
          )}
        </LabeledList>
        <Box mt={1} style={{ 'display': 'flex' }}>
          <input
            value={this.state.text}
            placeholder={'A message to ' + (mech.pilot || 'its pilot')
              + '...'}
            maxLength={1024}
            onInput={e => this.setState({ text: e.target.value })}
            onKeyDown={e => {
              if (e.keyCode === 13) {
                send();
              }
            }}
            style={{
              'flex-grow': 1,
              'background-color': 'rgba(0, 0, 0, 0.4)',
              'color': '#ffffff',
              'border': '1px solid #344f6d',
              'padding': '3px',
            }} />
          <Button
            ml={0.5}
            icon="paper-plane"
            content="Send"
            disabled={!this.state.text}
            onClick={send} />
        </Box>
      </Section>
    );
  }
}

export const MechaControl = props => {
  const { act, data } = useBackend(props);
  const mechs = data.mechs || [];
  if (!mechs.length) {
    return (
      <Section>
        <Box color="label">
          No exosuits with tracking beacons.
        </Box>
      </Section>
    );
  }
  return mechs.map(mech => (
    <MechCard key={mech.ref} mech={mech} act={act} />
  ));
};
