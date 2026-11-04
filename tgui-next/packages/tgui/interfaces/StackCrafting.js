import { Component, Fragment } from 'inferno';
import { useBackend } from '../backend';
import { Box, Button, Collapsible, Icon, Input, NoticeBox, Section } from '../components';

// hippie -- what using a stack in hand opens
// (hippiestation/.../stacks/stack_tgui.dm)

const MULTIPLIERS = [5, 10, 25];

// How many of a recipe the stack can make in one go, as the old window
// worked it out
const mostOf = (recipe, amount) => {
  let most = Math.floor(amount / recipe.req);
  if (recipe.max_res > 1 && most > 1) {
    most = Math.min(most, Math.floor(recipe.max_res / recipe.res));
  }
  return most;
};

const RecipeRow = props => {
  const { recipe, group, groupTitle, data, act } = props;
  const most = mostOf(recipe, data.amount);
  const make = multiplier => act('make', {
    index: recipe.index,
    group,
    multiplier,
  });
  const amounts = [];
  if (recipe.max_res > 1 && most > 1) {
    for (let n of MULTIPLIERS) {
      if (most >= n) {
        amounts.push(n);
      }
    }
    if (amounts.indexOf(most) === -1) {
      amounts.push(most);
    }
  }
  const cost = recipe.req + ' ' + data.singular + (recipe.req > 1 ? 's' : '');
  return (
    <Box
      className="candystripe"
      p={0.5}
      style={{ 'display': 'flex', 'align-items': 'center' }}>
      <Box style={{ 'flex-grow': 1 }}>
        <Box color={most < 1 ? 'label' : null}>
          {(recipe.res > 1 ? recipe.res + 'x ' : '') + recipe.title}
        </Box>
        <Box color="label" fontSize="11px">
          {cost}
          {recipe.time > 0 && (
            <Box inline ml={1}>
              <Icon name="clock" mr={0.5} />
              {recipe.time / 10 + 's'}
            </Box>
          )}
          {!!groupTitle && (
            <Box inline ml={1}>{'in ' + groupTitle}</Box>
          )}
        </Box>
      </Box>
      <Box style={{ 'white-space': 'nowrap' }}>
        <Button
          icon="hammer"
          content="Make"
          disabled={most < 1}
          onClick={() => make(1)} />
        {amounts.map(n => (
          <Button
            key={n}
            content={n * recipe.res + 'x'}
            onClick={() => make(n)} />
        ))}
      </Box>
    </Box>
  );
};

class StackCraftingMenu extends Component {
  constructor() {
    super();
    this.state = {
      search: '',
    };
  }

  render() {
    const { data, act } = this.props;
    const query = this.state.search.toLowerCase();
    const entries = data.recipes || [];
    let body;
    if (query) {
      // Every recipe that matches, groups and all
      const found = [];
      for (let entry of entries) {
        if (entry.kind === 'recipe') {
          if (entry.title.toLowerCase().includes(query)) {
            found.push({ recipe: entry, group: null, groupTitle: null });
          }
        } else if (entry.kind === 'group') {
          for (let recipe of entry.recipes) {
            if (recipe.kind === 'recipe' && (recipe.title.toLowerCase()
              .includes(query) || entry.title.toLowerCase()
              .includes(query))) {
              found.push({
                recipe,
                group: entry.index,
                groupTitle: entry.title,
              });
            }
          }
        }
      }
      body = <NoticeBox>Nothing matches that.</NoticeBox>;
      if (found.length) {
        body = found.map(item => (
          <RecipeRow
            key={(item.group || 0) + '-' + item.recipe.index}
            recipe={item.recipe}
            group={item.group}
            groupTitle={item.groupTitle}
            data={data}
            act={act} />
        ));
      }
    } else {
      body = entries.map((entry, i) => {
        if (entry.kind === 'spacer') {
          return (
            <Box
              key={'spacer' + i}
              my={0.5}
              style={{ 'border-top': '1px solid rgba(255, 255, 255, 0.1)' }} />
          );
        }
        if (entry.kind === 'group') {
          return (
            <Collapsible key={'group' + entry.index} title={entry.title}>
              <Box ml={1}>
                {entry.recipes
                  .filter(recipe => recipe.kind === 'recipe')
                  .map(recipe => (
                    <RecipeRow
                      key={recipe.index}
                      recipe={recipe}
                      group={entry.index}
                      data={data}
                      act={act} />
                  ))}
              </Box>
            </Collapsible>
          );
        }
        return (
          <RecipeRow
            key={entry.index}
            recipe={entry}
            group={null}
            data={data}
            act={act} />
        );
      });
    }
    return (
      <Section
        title={data.amount + ' ' + data.singular
          + (data.amount === 1 ? '' : 's') + ' left'}
        buttons={(
          <Input
            width="160px"
            placeholder="Search..."
            value={this.state.search}
            onInput={(e, value) => this.setState({ search: value })} />
        )}>
        {body}
      </Section>
    );
  }
}

export const StackCrafting = props => {
  const { act, data } = useBackend(props);
  return <StackCraftingMenu data={data} act={act} />;
};
