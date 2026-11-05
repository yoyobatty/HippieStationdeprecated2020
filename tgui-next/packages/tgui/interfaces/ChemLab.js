import { Component, Fragment } from 'inferno';
import { useBackend } from '../backend';
import { AnimatedNumber, Box, Button, Input, LabeledList, NoticeBox, NumberInput, ProgressBar, Section, Table } from '../components';

// hippie -- Hippie's chemistry machines
// (hippiestation/code/modules/reagents/chemistry/machinery/lcasschem.dm) and
// the material forge and analyser
// (hippiestation/code/game/machinery/reagent_forge.dm,
// reagent_material_manipulator.dm), were tgui/src/interfaces/chem_*.ract

const Beaker = props => {
  const { act, data, children } = props;
  const {
    isBeakerLoaded,
    beakerCurrentVolume,
    beakerMaxVolume,
    beakerContents = [],
  } = data;
  return (
    <Section
      title="Beaker"
      buttons={!!isBeakerLoaded && (
        <Fragment>
          <Box inline color="label" mr={1}>
            <AnimatedNumber
              value={beakerCurrentVolume}
              format={v => Math.round(v)} />
            {' / ' + beakerMaxVolume + 'u'}
          </Box>
          <Button
            icon="eject"
            content="Eject"
            onClick={() => act('eject')} />
        </Fragment>
      )}>
      {!isBeakerLoaded && (
        <Box color="average">No beaker. Put one in by hand.</Box>
      ) || (
        <Fragment>
          {children}
          {beakerContents.length === 0 && (
            <Box color="bad">Empty</Box>
          )}
          {beakerContents.map(reagent => (
            <Box key={reagent.name} color="highlight">
              {reagent.volume.toFixed(2)} units of {reagent.name}
            </Box>
          ))}
        </Fragment>
      )}
    </Section>
  );
};

const PowerButton = props => {
  const { act, on, disabled } = props;
  return (
    <Button
      icon="power-off"
      selected={on}
      disabled={disabled}
      content={on ? 'On' : 'Off'}
      onClick={() => act('power')} />
  );
};

export const ChemPressure = props => {
  const { act, data } = useBackend(props);
  return (
    <Fragment>
      <Section
        title="Pressure chamber"
        buttons={<PowerButton act={act} on={data.isActive} />}>
        <LabeledList>
          <LabeledList.Item label="Chamber">
            <ProgressBar
              value={data.internalPressure / 100}
              ranges={{
                bad: [0.8, Infinity],
                average: [0.5, 0.8],
                good: [-Infinity, 0.5],
              }}>
              <AnimatedNumber value={Math.round(data.internalPressure)} /> bar
            </ProgressBar>
          </LabeledList.Item>
        </LabeledList>
      </Section>
      <Beaker act={act} data={data}>
        <Box mb={1}>
          Pressure:{' '}
          <AnimatedNumber value={Math.round(data.currentPressure || 0)} />
          {' bar'}
        </Box>
      </Beaker>
    </Fragment>
  );
};

export const ChemRadioactive = props => {
  const { act, data } = useBackend(props);
  return (
    <Fragment>
      <Section
        title="Particle detector"
        buttons={(
          <PowerButton
            act={act}
            on={data.isActive}
            disabled={!data.isBeakerLoaded} />
        )}>
        <LabeledList>
          <LabeledList.Item label="Target">
            <NumberInput
              value={data.targetRadioactivity}
              unit="PBq"
              minValue={0}
              maxValue={20}
              step={1}
              stepPixelSize={6}
              width="72px"
              onChange={(e, value) => act('irradiate', { target: value })} />
          </LabeledList.Item>
          <LabeledList.Item label="Uranium">
            <ProgressBar value={data.materialAmount / 50000} color="good">
              <AnimatedNumber value={Math.round(data.materialAmount)} />
              {' cm³'}
            </ProgressBar>
          </LabeledList.Item>
        </LabeledList>
      </Section>
      <Beaker act={act} data={data}>
        <Box mb={1} bold color={data.currentRadioactivity ? 'bad' : 'label'}>
          Radioactivity:{' '}
          <AnimatedNumber
            value={Math.round(data.currentRadioactivity || 0)} />
          {' PBq'}
        </Box>
      </Beaker>
    </Fragment>
  );
};

export const ChemBluespace = props => {
  const { act, data } = useBackend(props);
  return (
    <Fragment>
      <Section
        title="Bluespace emitter"
        buttons={(
          <PowerButton
            act={act}
            on={data.isActive}
            disabled={!data.isBeakerLoaded} />
        )}>
        <LabeledList>
          <LabeledList.Item label="Intensity">
            <NumberInput
              value={data.intensity}
              unit="B"
              minValue={0}
              maxValue={30}
              step={1}
              stepPixelSize={4}
              width="72px"
              onChange={(e, value) => act('bluespace', { target: value })} />
          </LabeledList.Item>
          <LabeledList.Item label="Crystals">
            <ProgressBar value={data.crystalAmount / 10} color="purple">
              {data.crystalAmount} / 10
            </ProgressBar>
          </LabeledList.Item>
        </LabeledList>
      </Section>
      <Beaker act={act} data={data}>
        <Box mb={1} bold color={data.isBluespaced ? 'bad' : 'good'}>
          {data.isBluespaced
            ? 'Bluespace activity confirmed'
            : 'No abnormal activity'}
        </Box>
      </Beaker>
    </Fragment>
  );
};

export const ChemCentrifuge = props => {
  const { act, data } = useBackend(props);
  return (
    <Fragment>
      <Section
        title="Centrifuge"
        buttons={<PowerButton act={act} on={data.isActive} />}>
        <LabeledList>
          <LabeledList.Item label="Time left">
            <ProgressBar value={data.timeRemaining / 30} color="teal">
              <AnimatedNumber
                value={Math.max(0, Math.round(data.timeRemaining))} />
              {' s'}
            </ProgressBar>
          </LabeledList.Item>
        </LabeledList>
      </Section>
      <Beaker act={act} data={data} />
    </Fragment>
  );
};

const TraitTable = props => {
  const { traits = [], onAdd, canAdd } = props;
  if (!traits.length) {
    return <Box color="label">None.</Box>;
  }
  return (
    <Table>
      <Table.Row header>
        <Table.Cell>Trait</Table.Cell>
        <Table.Cell collapsing textAlign="right">Chance</Table.Cell>
        {!!onAdd && <Table.Cell collapsing />}
      </Table.Row>
      {traits.map(trait => (
        <Table.Row key={trait.name}>
          <Table.Cell py={0.5}>
            <Box bold>{trait.name}</Box>
            <Box color="label">{trait.desc}</Box>
          </Table.Cell>
          <Table.Cell collapsing textAlign="right">
            {trait.effectiveness}%
          </Table.Cell>
          {!!onAdd && (
            <Table.Cell collapsing pl={1}>
              <Button
                icon="plus"
                disabled={!canAdd}
                content="Add"
                onClick={() => onAdd(trait.name)} />
            </Table.Cell>
          )}
        </Table.Row>
      ))}
    </Table>
  );
};

export const MaterialAnalyser = props => {
  const { act, data } = useBackend(props);
  const {
    item,
    reagent_analyse,
    density,
    traits = [],
    traitsadd = [],
    volume,
    reagent_synthesis,
    analyse_only,
    add_cost,
    trait_room,
  } = data;
  const canAdd = !!item && !!reagent_synthesis && !analyse_only
    && volume >= add_cost && trait_room > 0;
  return (
    <Fragment>
      <Section
        title={item || 'Nothing loaded'}
        buttons={!!item && (
          <Button
            icon="eject"
            content="Eject"
            onClick={() => act('Eject')} />
        )}>
        {!item && (
          <Box color="label">
            Load a forged item, or a beaker holding one material, to read
            its traits.
          </Box>
        ) || (
          <LabeledList>
            <LabeledList.Item label="Material">
              {reagent_analyse || 'Unknown'}
            </LabeledList.Item>
            <LabeledList.Item label="Density">
              {density === null ? 'N/A' : density}
            </LabeledList.Item>
            {!analyse_only && (
              <LabeledList.Item label="Trait slots">
                {trait_room} free
              </LabeledList.Item>
            )}
          </LabeledList>
        )}
        {!!item && (
          <Section level={2} title="Traits">
            <TraitTable traits={traits} />
          </Section>
        )}
      </Section>
      <Section
        title={reagent_synthesis
          ? reagent_synthesis + ' for synthesis'
          : 'Synthesis'}
        buttons={!!reagent_synthesis && (
          <Button
            icon="trash"
            content="Empty"
            onClick={() => act('Empty')} />
        )}>
        {!reagent_synthesis && (
          <Box color="label">
            Pour in a material to give its traits to the loaded item.
          </Box>
        ) || (
          <Fragment>
            <Box mb={1}>
              <ProgressBar value={volume / 100}>
                {Math.round(volume)} / 100u ({add_cost}u a trait)
              </ProgressBar>
            </Box>
            {!!analyse_only && (
              <NoticeBox>
                Analyse only: a bare material&apos;s traits can&apos;t be
                changed.
              </NoticeBox>
            )}
            <TraitTable
              traits={traitsadd}
              canAdd={canAdd}
              onAdd={name => act('Add_Trait', { name })} />
          </Fragment>
        )}
      </Section>
    </Fragment>
  );
};

export class ReagentForge extends Component {
  constructor() {
    super();
    this.state = { amount: 1, search: '' };
  }

  render() {
    const { act, data } = useBackend(this.props);
    const { amount, search } = this.state;
    const {
      recipes = [],
      currently_forging,
      material_amount,
    } = data;
    const forging = currently_forging && currently_forging !== 'Nothing';
    const term = search.toLowerCase();
    const shown = recipes
      .filter(recipe => !term || recipe.name.toLowerCase().includes(term)
        || recipe.category.toLowerCase().includes(term))
      .sort((a, b) => a.category.localeCompare(b.category)
        || a.name.localeCompare(b.name));
    return (
      <Fragment>
        <Section
          title={forging ? 'Forging ' + currently_forging : 'Forge'}
          buttons={!!forging && (
            <Button
              icon="eject"
              content="Eject as sheets"
              onClick={() => act('Dump')} />
          )}>
          <ProgressBar value={material_amount / 200000} color="orange">
            <AnimatedNumber value={Math.round(material_amount)} /> / 200000 cm³
          </ProgressBar>
          {!forging && (
            <Box color="label" mt={1}>
              Put in sheets of a reagent material to forge with it.
            </Box>
          )}
        </Section>
        <Section
          title="Recipes"
          buttons={(
            <Fragment>
              <Box inline color="label" mr={1}>How many</Box>
              <NumberInput
                value={amount}
                minValue={1}
                maxValue={50}
                step={1}
                stepPixelSize={6}
                width="40px"
                onChange={(e, value) => this.setState({ amount: value })} />
            </Fragment>
          )}>
          <Input
            fluid
            placeholder="Search..."
            value={search}
            onInput={(e, value) => this.setState({ search: value })} />
          <Table mt={1}>
            <Table.Row header>
              <Table.Cell>Recipe</Table.Cell>
              <Table.Cell>Type</Table.Cell>
              <Table.Cell collapsing textAlign="right">Cost</Table.Cell>
              <Table.Cell collapsing />
            </Table.Row>
            {shown.map(recipe => (
              <Table.Row key={recipe.name}>
                <Table.Cell>{recipe.name}</Table.Cell>
                <Table.Cell color="label">{recipe.category}</Table.Cell>
                <Table.Cell collapsing textAlign="right">
                  {recipe.cost * amount}
                </Table.Cell>
                <Table.Cell collapsing pl={1}>
                  <Button
                    icon="hammer"
                    disabled={!forging || material_amount < recipe.cost}
                    content="Forge"
                    onClick={() => act('Create', {
                      name: recipe.name,
                      amount,
                    })} />
                </Table.Cell>
              </Table.Row>
            ))}
          </Table>
        </Section>
      </Fragment>
    );
  }
}
