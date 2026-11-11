import { Component, Fragment } from 'inferno';
import { useBackend } from '../backend';
import { Box, Button, Input, LabeledList, NumberInput, Section, Tabs } from '../components';
import { ColorDot, FillBar, ReagentTable } from './common/ReagentBits';

// hippie -- the ChemMaster redone (extra data in hippiestation/code/modules/
// reagents/chemistry/machinery/chemistry_tgui.dm): the beaker and buffer drawn
// in their colours with amounts to move each reagent, and the pills, patches
// and bottles made from one panel where how many, how big and the name are set
// in the window, where they were pop-ups

const AMOUNTS = [1, 5, 10];

const MoveButtons = props => {
  const { act, reagent, to, custom } = props;
  return (
    <Fragment>
      {AMOUNTS.map(amount => (
        <Button
          key={amount}
          content={amount}
          onClick={() => act('transfer', { id: reagent.id, amount, to })} />
      ))}
      <Button
        content="All"
        onClick={() => act('transfer', {
          id: reagent.id,
          amount: reagent.volume,
          to,
        })} />
      <Button
        icon="ellipsis-h"
        tooltip={'Move ' + custom + 'u'}
        onClick={() => act('transfer', {
          id: reagent.id,
          amount: custom,
          to,
        })} />
      <Button
        icon="search"
        tooltip="Analyse"
        onClick={() => act('analyze', { id: reagent.id })} />
    </Fragment>
  );
};

const PACKAGES = [
  ['pill', 'Pills', 'capsules', 50],
  ['patch', 'Patches', 'band-aid', 40],
  ['bottle', 'Bottles', 'wine-bottle', 30],
];
const CONDIMENTS = [
  ['condimentPack', 'Packs', 'mortar-pestle', 10],
  ['condimentBottle', 'Bottles', 'wine-bottle', 50],
];

const Analysis = props => {
  const { act, analyzeVars = {} } = props;
  return (
    <Section
      title={analyzeVars.name}
      buttons={(
        <Button
          icon="arrow-left"
          content="Back"
          onClick={() => act('goScreen', { screen: 'home' })} />
      )}>
      <LabeledList>
        <LabeledList.Item label="State">{analyzeVars.state}</LabeledList.Item>
        <LabeledList.Item label="Colour">
          <ColorDot color={analyzeVars.color} />
          {analyzeVars.color}
        </LabeledList.Item>
        <LabeledList.Item label="Description">
          {analyzeVars.description}
        </LabeledList.Item>
        <LabeledList.Item label="Metabolism">
          {analyzeVars.metaRate}u a minute
        </LabeledList.Item>
        <LabeledList.Item label="Overdose">
          {analyzeVars.overD ? analyzeVars.overD + 'u' : 'None'}
        </LabeledList.Item>
        <LabeledList.Item label="Addiction">
          {analyzeVars.addicD ? analyzeVars.addicD + 'u' : 'None'}
        </LabeledList.Item>
      </LabeledList>
    </Section>
  );
};

export class ChemMaster extends Component {
  constructor() {
    super();
    this.state = {
      custom: 15,
      kind: null,
      count: 1,
      volume: 0,
      name: '',
    };
  }

  render() {
    const { act, data } = useBackend(this.props);
    const {
      screen,
      condi,
      mode,
      isBeakerLoaded,
      beakerCurrentVolume,
      beakerMaxVolume,
      beakerColor,
      bufferColor,
      bufferMaxVolume,
      isPillBottleLoaded,
      pillBottleCurrentAmount,
      pillBottleMaxAmount,
      chosenPillStyle,
      pillStyles = [],
    } = data;
    if (screen === 'analyze') {
      return <Analysis act={act} analyzeVars={data.analyzeVars} />;
    }
    const { custom, count, volume, name } = this.state;
    const packages = condi ? CONDIMENTS : PACKAGES;
    const kind = packages.find(each => each[0] === this.state.kind)
      || packages[0];
    const bufferContents = data.bufferContents || [];
    const bufferVolume = bufferContents
      .reduce((sum, reagent) => sum + reagent.volume, 0);
    const autoEach = Math.min(kind[3],
      Math.floor(bufferVolume / Math.max(count, 1) * 100) / 100);
    const each = volume > 0 ? Math.min(volume, autoEach) : autoEach;
    const master = bufferContents.reduce((best, reagent) => (
      !best || reagent.volume > best.volume ? reagent : best), null);
    const sized = kind[0] === 'pill' || kind[0] === 'patch';
    let defaultName = master ? master.name : '';
    if (master && sized) {
      defaultName += ' (' + each + 'u)';
    }
    return (
      <Fragment>
        <Section
          title="Beaker"
          buttons={!!isBeakerLoaded && (
            <Fragment>
              <Box inline color="label" mr={1}>Custom</Box>
              <NumberInput
                width="45px"
                unit="u"
                value={custom}
                minValue={1}
                maxValue={300}
                onChange={(e, value) => this.setState({ custom: value })} />
              <Button
                icon="eject"
                content="Eject"
                onClick={() => act('eject')} />
            </Fragment>
          )}>
          {!isBeakerLoaded && (
            <Box color="label">No beaker.</Box>
          ) || (
            <Fragment>
              <FillBar
                volume={beakerCurrentVolume}
                maxVolume={beakerMaxVolume}
                color={beakerColor} />
              <ReagentTable
                contents={data.beakerContents}
                empty="The beaker is empty."
                buttons={reagent => (
                  <MoveButtons
                    act={act}
                    reagent={reagent}
                    to="buffer"
                    custom={custom} />
                )} />
            </Fragment>
          )}
        </Section>
        <Section
          title="Buffer"
          buttons={(
            <Button
              icon={mode ? 'exchange-alt' : 'trash'}
              color={mode ? null : 'bad'}
              content={mode ? 'Moving to beaker' : 'Destroying'}
              tooltip="What the buttons below do"
              onClick={() => act('toggleMode')} />
          )}>
          <FillBar
            volume={bufferVolume}
            maxVolume={bufferMaxVolume}
            color={bufferColor} />
          <ReagentTable
            contents={bufferContents}
            empty="The buffer is empty."
            buttons={reagent => (
              <MoveButtons
                act={act}
                reagent={reagent}
                to="beaker"
                custom={custom} />
            )} />
        </Section>
        <Section
          title="Packaging"
          buttons={!!isPillBottleLoaded && (
            <Fragment>
              <Box inline color="label" mr={1}>
                Pill bottle {pillBottleCurrentAmount}/{pillBottleMaxAmount}
              </Box>
              <Button
                icon="eject"
                onClick={() => act('ejectPillBottle')} />
            </Fragment>
          )}>
          <Tabs activeTab={kind[0]}>
            {packages.map(each => (
              <Tabs.Tab
                key={each[0]}
                label={each[1]}
                icon={each[2]}
                onClick={() => this.setState({ kind: each[0], volume: 0 })} />
            ))}
          </Tabs>
          {kind[0] === 'pill' && (
            <Box mb={1}>
              {pillStyles.map(pill => (
                <Button
                  key={pill.id}
                  width="30px"
                  selected={pill.id === chosenPillStyle}
                  textAlign="center"
                  color="transparent"
                  onClick={() => act('pillStyle', { id: pill.id })}>
                  <Box mx={-1} className={pill.className} />
                </Button>
              ))}
            </Box>
          )}
          <LabeledList>
            <LabeledList.Item label="How many">
              <NumberInput
                width="45px"
                value={count}
                minValue={1}
                maxValue={10}
                onChange={(e, value) => this.setState({ count: value })} />
            </LabeledList.Item>
            <LabeledList.Item label="Each">
              <NumberInput
                width="55px"
                unit="u"
                value={each}
                minValue={0}
                maxValue={kind[3]}
                onChange={(e, value) => this.setState({ volume: value })} />
              <Box inline color="label" ml={1}>
                up to {kind[3]}u
              </Box>
            </LabeledList.Item>
            <LabeledList.Item label="Name">
              <Input
                width="200px"
                placeholder={defaultName}
                value={name}
                onInput={(e, value) => this.setState({ name: value })} />
            </LabeledList.Item>
          </LabeledList>
          <Button
            mt={1}
            fluid
            icon={kind[2]}
            color="good"
            textAlign="center"
            disabled={!bufferVolume || each <= 0}
            content={'Make ' + count + ' x ' + each + 'u'}
            onClick={() => act('create', {
              type: kind[0],
              amount: count,
              volume: each,
              name: name || defaultName,
            })} />
        </Section>
      </Fragment>
    );
  }
}
