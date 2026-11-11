import { toFixed } from 'common/math';
import { Component, Fragment } from 'inferno';
import { useBackend } from '../backend';
import { Box, Button, Input, NoticeBox, ProgressBar, Section } from '../components';
import { FillBar, ReagentTable } from './common/ReagentBits';

// hippie -- the chem dispenser redone (extra data in hippiestation/code/
// modules/reagents/chemistry/machinery/chemistry_tgui.dm): each chemical a
// button in its own colour, searchable; the beaker drawn in the colour of its
// mix; recipes saved and cleared in the window, where they were pop-ups

export class ChemDispenser extends Component {
  constructor() {
    super();
    this.state = {
      search: '',
      adding: false,
      recipeName: '',
      recipeText: '',
      confirmClear: false,
    };
  }

  render() {
    const { act, data } = useBackend(this.props);
    const {
      search,
      adding,
      recipeName,
      recipeText,
      confirmClear,
    } = this.state;
    const {
      amount,
      energy,
      maxEnergy,
      isBeakerLoaded,
      beakerCurrentVolume,
      beakerMaxVolume,
      beakerColor,
      chemColors = {},
      recipes = [],
    } = data;
    const transferAmounts = data.beakerTransferAmounts || [];
    const term = search.toLowerCase();
    const chemicals = (data.chemicals || [])
      .filter(chem => !term || chem.title.toLowerCase().includes(term));
    return (
      <Fragment>
        <Section>
          <ProgressBar
            value={energy / maxEnergy}
            ranges={{
              good: [0.5, Infinity],
              average: [0.2, 0.5],
              bad: [-Infinity, 0.2],
            }}>
            {toFixed(energy) + ' units of energy'}
          </ProgressBar>
        </Section>
        <Section
          title="Dispense"
          buttons={(
            <Fragment>
              <Box inline color="label" mr={1}>Amount</Box>
              {transferAmounts.map(each => (
                <Button
                  key={each}
                  selected={each === amount}
                  content={each}
                  onClick={() => act('amount', { target: each })} />
              ))}
            </Fragment>
          )}>
          {!isBeakerLoaded && (
            <NoticeBox>No beaker.</NoticeBox>
          )}
          <Input
            fluid
            mb={1}
            placeholder="Search chemicals..."
            value={search}
            onInput={(e, value) => this.setState({ search: value })} />
          <div className="ChemDispenser__grid">
            {chemicals.map(chem => (
              <Button
                key={chem.id}
                className="ChemDispenser__chem"
                disabled={!isBeakerLoaded}
                style={{
                  'border-left': '6px solid '
                    + (chemColors[chem.id] || '#888'),
                }}
                content={chem.title}
                onClick={() => act('dispense', { reagent: chem.id })} />
            ))}
          </div>
        </Section>
        <Section
          title="Recipes"
          buttons={(
            <Fragment>
              <Button
                icon="plus"
                selected={adding}
                content="New"
                onClick={() => this.setState({ adding: !adding })} />
              <Button
                icon={confirmClear ? 'check' : 'trash'}
                color={confirmClear ? 'bad' : null}
                disabled={!recipes.length}
                content={confirmClear ? 'Sure?' : 'Clear all'}
                onClick={() => {
                  if (confirmClear) {
                    act('clear_recipes', { confirmed: 1 });
                  }
                  this.setState({ confirmClear: !confirmClear });
                }} />
            </Fragment>
          )}>
          {adding && (
            <Box mb={1}>
              <Input
                width="120px"
                placeholder="Name"
                value={recipeName}
                onInput={(e, value) => this.setState({ recipeName: value })} />
              <Input
                ml={0.5}
                width="230px"
                placeholder="water=10;sugar=5"
                value={recipeText}
                onInput={(e, value) => this.setState({ recipeText: value })} />
              <Button
                icon="save"
                disabled={!recipeName || !recipeText}
                content="Save"
                onClick={() => {
                  act('add_recipe', { name: recipeName, recipe: recipeText });
                  this.setState({
                    adding: false,
                    recipeName: '',
                    recipeText: '',
                  });
                }} />
              <Box color="label" mt={0.5}>
                Chemical IDs with amounts, separated by semicolons.
              </Box>
            </Box>
          )}
          {recipes.length === 0 && !adding && (
            <Box color="label">No recipes saved.</Box>
          )}
          {recipes.map(recipe => (
            <Button
              key={recipe.name}
              icon="flask"
              disabled={!isBeakerLoaded}
              content={recipe.name}
              tooltip={recipe.contents}
              onClick={() => act('dispense_recipe', {
                recipe: recipe.contents,
              })} />
          ))}
        </Section>
        <Section
          title="Beaker"
          buttons={!!isBeakerLoaded && (
            <Fragment>
              <Box inline color="label" mr={1}>Remove</Box>
              {transferAmounts.map(each => (
                <Button
                  key={each}
                  content={each}
                  onClick={() => act('remove', { amount: each })} />
              ))}
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
                empty="The beaker is empty." />
            </Fragment>
          )}
        </Section>
      </Fragment>
    );
  }
}
