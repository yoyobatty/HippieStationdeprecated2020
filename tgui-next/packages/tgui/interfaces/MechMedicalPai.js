import { decodeHtmlEntities } from 'common/string';
import { Component, Fragment } from 'inferno';
import { useBackend } from '../backend';
import { Box, Button, Icon, Input, LabeledList, NoticeBox, ProgressBar, Section } from '../components';

// hippie -- the mech sleeper's patient statistics, the mech syringe gun's
// reagent synthesizer and the pAI card, moved off their old HTML pages. Data
// from hippiestation/code/game/mecha/mech_medical_tgui.dm and hippiestation/
// code/game/objects/items/devices/paicard_tgui.dm.

const STATS = ['Conscious', 'Unconscious', 'DEAD'];

const DAMAGES = [
  ['brute', 'Brute Damage', 'bad'],
  ['oxy', 'Respiratory Damage', 'blue'],
  ['tox', 'Toxin Content', 'green'],
  ['burn', 'Burn Severity', 'orange'],
];

export const MechSleeper = props => {
  const { act, data } = useBackend(props);
  const patient = data.patient;
  if (!patient) {
    return <NoticeBox>No occupant.</NoticeBox>;
  }
  return (
    <Fragment>
      <Section
        title={patient.name}
        buttons={(
          <Button
            icon="eject"
            content="Eject"
            onClick={() => act('eject')} />
        )}>
        <LabeledList>
          <LabeledList.Item
            label="Health"
            color={patient.stat > 1 ? 'bad' : null}>
            {patient.stat > 1 && 'DEAD' || (
              <ProgressBar
                value={patient.health / 100}
                minValue={-1}
                ranges={{
                  good: [0.5, Infinity],
                  average: [0, 0.5],
                  bad: [-Infinity, 0],
                }}>
                {patient.health}% ({STATS[patient.stat]})
              </ProgressBar>
            )}
          </LabeledList.Item>
          <LabeledList.Item label="Core Temperature">
            {patient.temperature} °C
          </LabeledList.Item>
          {DAMAGES.map(damage => (
            <LabeledList.Item key={damage[0]} label={damage[1]}>
              <ProgressBar
                value={patient[damage[0]] / 100}
                color={patient[damage[0]] < 60 ? damage[2] : 'bad'}>
                {Math.round(patient[damage[0]])}%
              </ProgressBar>
            </LabeledList.Item>
          ))}
        </LabeledList>
        {!!patient.clone && (
          <Box color="bad" mt={0.5}>
            Subject appears to have cellular damage.
          </Box>
        )}
        {!!patient.brain && (
          <Box color="bad">Significant brain damage detected.</Box>
        )}
        {!!patient.traumas && (
          <Box color="bad">Brain Traumas detected.</Box>
        )}
      </Section>
      <Section title="Reagents in bloodstream">
        {(data.blood || []).length === 0 && (
          <Box color="label">None</Box>
        )}
        {(data.blood || []).map(reagent => (
          <Box key={reagent.name}>
            {reagent.name}: {reagent.volume}
          </Box>
        ))}
      </Section>
      <Section title={'Inject (' + data.inject_amount + ' u)'}>
        {(data.injectable || []).length === 0 && (
          <Box color="label">No syringe gun reagents.</Box>
        )}
        {(data.injectable || []).map(reagent => (
          <Button
            key={reagent.ref}
            icon="syringe"
            content={reagent.name + ' (' + reagent.volume + ')'}
            onClick={() => act('inject', { ref: reagent.ref })} />
        ))}
      </Section>
    </Fragment>
  );
};

export const MechSyringeGun = props => {
  const { act, data } = useBackend(props);
  const reagents = data.reagents || [];
  const known = data.known || [];
  const producing = known.filter(reagent => reagent.on).length;
  return (
    <Fragment>
      <Section
        title="Current reagents"
        buttons={(
          <Button
            icon="trash"
            content="Purge All"
            disabled={!reagents.length}
            onClick={() => act('purge_all')} />
        )}>
        <ProgressBar value={data.max ? data.total / data.max : 0}>
          {data.total} / {data.max} u
        </ProgressBar>
        {reagents.map(reagent => (
          <Box key={reagent.path} mt={0.5}>
            {reagent.name}: {reagent.volume}
            <Button
              ml={1}
              icon="trash"
              content="Purge"
              onClick={() => act('purge', { path: reagent.path })} />
          </Box>
        ))}
        <Box mt={0.5} color="label">
          Syringes: {data.syringes} / {data.max_syringes}
        </Box>
      </Section>
      <Section
        title={'Production (' + producing + '/' + data.synth_speed + ')'}>
        {known.length === 0 && (
          <Box color="label">No known reagents</Box>
        )}
        {known.map(reagent => (
          <Button.Checkbox
            key={reagent.path}
            checked={reagent.on}
            content={reagent.name}
            onClick={() => act('produce', { path: reagent.path })} />
        ))}
      </Section>
    </Fragment>
  );
};

export class PaiCard extends Component {
  constructor() {
    super();
    this.state = { laws: '', wiping: false };
  }

  render() {
    const { act, data } = useBackend(this.props);
    const { laws, wiping } = this.state;
    const pai = data.pai;
    if (!pai) {
      const candidates = data.candidates || [];
      return (
        <Section
          title="No personality installed"
          buttons={(
            <Button
              icon={data.searching ? 'sync' : 'search'}
              content={data.searching ? 'Ask again' : 'Find a personality'}
              onClick={() => act('request')} />
          )}>
          {!data.searching && (
            <Box color="label">
              Not searching.
            </Box>
          )}
          {!!data.searching && candidates.length === 0 && (
            <NoticeBox>
              No candidates.
            </NoticeBox>
          )}
          {candidates.map(c => (
            <Section
              key={c.ref}
              level={2}
              title={c.name || 'Unnamed'}
              buttons={(
                <Button
                  icon="download"
                  content="Download"
                  onClick={() => act('download', { ref: c.ref })} />
              )}>
              <LabeledList>
                {!!c.description && (
                  <LabeledList.Item label="Description">
                    {decodeHtmlEntities(c.description)}
                  </LabeledList.Item>
                )}
                {!!c.role && (
                  <LabeledList.Item label="Preferred role">
                    {decodeHtmlEntities(c.role)}
                  </LabeledList.Item>
                )}
                {!!c.comments && (
                  <LabeledList.Item label="OOC">
                    {decodeHtmlEntities(c.comments)}
                  </LabeledList.Item>
                )}
              </LabeledList>
            </Section>
          ))}
        </Section>
      );
    }
    return (
      <Fragment>
        <Section title={pai.name}>
          <LabeledList>
            <LabeledList.Item label="Master">
              {pai.has_master && pai.master || (
                <Button
                  icon="fingerprint"
                  content="Imprint Master DNA"
                  onClick={() => act('setdna')} />
              )}
            </LabeledList.Item>
            <LabeledList.Item label="Prime directive">
              {decodeHtmlEntities(pai.zeroth || '')}
            </LabeledList.Item>
            {(pai.supplied || []).filter(law => !!law).map((law, i) => (
              <LabeledList.Item key={i} label="Additional directive">
                {decodeHtmlEntities(law)}
              </LabeledList.Item>
            ))}
          </LabeledList>
          <Box mt={1}>
            <Input
              width="280px"
              placeholder="Additional directive"
              value={laws}
              onInput={(e, value) => this.setState({ laws: value })} />
            <Button
              icon="pen"
              content="Set"
              disabled={!laws}
              onClick={() => {
                act('setlaws', { laws });
                this.setState({ laws: '' });
              }} />
          </Box>
        </Section>
        <Section title="Device Settings">
          {pai.radio && (
            <LabeledList>
              <LabeledList.Item label="Transmit">
                <Button
                  icon="broadcast-tower"
                  selected={pai.transmit}
                  content={pai.transmit ? 'Enabled' : 'Disabled'}
                  onClick={() => act('transmit')} />
              </LabeledList.Item>
              <LabeledList.Item label="Receive">
                <Button
                  icon="headphones"
                  selected={pai.receive}
                  content={pai.receive ? 'Enabled' : 'Disabled'}
                  onClick={() => act('receive')} />
              </LabeledList.Item>
              {!!pai.is_master && (
                <LabeledList.Item label="Holomatrix">
                  <Button
                    icon="user-astronaut"
                    selected={pai.holo}
                    content={pai.holo ? 'Enabled' : 'Disabled'}
                    onClick={() => act('holo')} />
                </LabeledList.Item>
              )}
            </LabeledList>
          ) || (
            <Box color="bad" italic>
              Radio firmware not loaded.
            </Box>
          )}
          <Box mt={1}>
            {wiping && (
              <Fragment>
                <Box inline color="bad" mr={1}>
                  <Icon name="exclamation-triangle" mr={1} />
                  Delete the current personality?
                </Box>
                <Button
                  color="bad"
                  content="Yes"
                  onClick={() => {
                    act('wipe');
                    this.setState({ wiping: false });
                  }} />
                <Button
                  content="No"
                  onClick={() => this.setState({ wiping: false })} />
              </Fragment>
            ) || (
              <Button
                icon="eraser"
                color="bad"
                content="Wipe current pAI personality"
                onClick={() => this.setState({ wiping: true })} />
            )}
          </Box>
        </Section>
      </Fragment>
    );
  }
}
