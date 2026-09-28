import { Component, Fragment } from 'inferno';
import { useBackend } from '../backend';
import { Box, Button, Dimmer, Icon, Input, NoticeBox } from '../components';

const MODE_CRAFTING = 0;
const MODE_COOKING = 1;

const TAB_CATEGORY = 'category';
const TAB_MATERIAL = 'material';
const TAB_FOODTYPE = 'foodtype';

const CAN_MAKE = 'Can Make';

// Recipes rendered per "page", more are added with the "Load more" button
const PAGE_SIZE = 40;
const PAGE_SIZE_COMPACT = 80;

const TOOL_NAMES = {
  crowbar: 'Crowbar',
  multitool: 'Multitool',
  screwdriver: 'Screwdriver',
  wirecutter: 'Wirecutters',
  wrench: 'Wrench',
  welder: 'Welding tool',
  analyzer: 'Analyzer',
  mining: 'Pickaxe',
  shovel: 'Shovel',
};

const TOOL_ICONS = {
  crowbar: 'toolbox',
  multitool: 'microchip',
  screwdriver: 'screwdriver',
  wirecutter: 'cut',
  wrench: 'wrench',
  welder: 'fire',
  analyzer: 'search',
  mining: 'hammer',
  shovel: 'hammer',
};

const CATEGORY_ICONS = {
  [CAN_MAKE]: 'check',
  'Weapons': 'gavel',
  'Ammunition': 'box',
  'Robots': 'robot',
  'Misc': 'shapes',
  'Tribal': 'campground',
  'Clothing': 'tshirt',
  'Learned': 'book',
  'Breads': 'bread-slice',
  'Burgers': 'hamburger',
  'Cakes': 'birthday-cake',
  'Egg-Based Food': 'egg',
  'Meats': 'drumstick-bite',
  'Misc. Food': 'utensils',
  'Pastries': 'cookie',
  'Pies': 'chart-pie',
  'Pizzas': 'pizza-slice',
  'Salads': 'leaf',
  'Sandwiches': 'hotdog',
  'Soups': 'mug-hot',
  'Spaghettis': 'stream',
};

const getCategoryIcon = category => {
  if (CATEGORY_ICONS[category]) {
    return CATEGORY_ICONS[category];
  }
  if (category.indexOf('Magic') === 0) {
    return 'hat-wizard';
  }
  return 'circle';
};

const getDietColor = (foodtype, diet) => {
  if (!diet) {
    return;
  }
  if (diet.toxic_food.includes(foodtype)) {
    return 'bad';
  }
  if (diet.disliked_food.includes(foodtype)) {
    return 'average';
  }
  if (diet.liked_food.includes(foodtype)) {
    return 'good';
  }
};

const getAtom = (atomData, id) => atomData[Number(id) - 1] || {};

/**
 * Draws the sprite of an atom from the crafting spritesheet, scaled to fit
 * a size x size box. Reagents have no sprite, so they get a droplet glyph.
 */
const AtomIcon = props => {
  const { atom, size = 32 } = props;
  if (!atom.icon) {
    return (
      <Box
        inline
        width={size + 'px'}
        height={size + 'px'}
        textAlign="center"
        lineHeight={size + 'px'}
        style={{ 'vertical-align': 'middle' }}>
        <Icon
          name={atom.is_reagent ? 'tint' : 'question'}
          color={atom.is_reagent ? 'blue' : 'label'}
          size={size / 24} />
      </Box>
    );
  }
  const nativeSize = parseInt(atom.icon_size, 10) || 32;
  return (
    <Box
      inline
      position="relative"
      width={size + 'px'}
      height={size + 'px'}
      style={{ 'overflow': 'hidden', 'vertical-align': 'middle' }}>
      <Box
        className={atom.icon}
        style={{
          'transform': 'scale(' + (size / nativeSize) + ')',
          'transform-origin': 'top left',
        }} />
    </Box>
  );
};

const Ingredient = props => {
  const { atom, amount } = props;
  return (
    <Box
      inline
      mr={1}
      mb={0.5}
      style={{
        'padding': '0 3px',
        'border': '1px solid rgba(255, 255, 255, 0.1)',
        'border-radius': '2px',
      }}>
      <AtomIcon atom={atom} size={16} />
      <Box inline ml={0.5}>
        {atom.is_reagent ? amount + 'u ' : amount + 'x '}
        {atom.name}
      </Box>
    </Box>
  );
};

const ToolList = props => {
  const { recipe, atomData } = props;
  return (
    <Fragment>
      {recipe.tool_behaviors.map(tool => (
        <Box key={tool} inline mr={1}>
          <Icon name={TOOL_ICONS[tool] || 'wrench'} mr={0.5} />
          {TOOL_NAMES[tool] || tool}
        </Box>
      ))}
      {recipe.tool_paths.map(id => (
        <Box key={id} inline mr={1}>
          <AtomIcon atom={getAtom(atomData, id)} size={16} />
          <Box inline ml={0.5}>
            {getAtom(atomData, id).name}
          </Box>
        </Box>
      ))}
    </Fragment>
  );
};

const CraftButtons = props => {
  const { recipe, craftable, busy, act } = props;
  return (
    <Fragment>
      <Button
        icon="cog"
        content="Craft"
        disabled={!craftable || busy}
        onClick={() => act('make', { recipe: recipe.ref })} />
      <Button
        icon="cogs"
        tooltip="Craft all"
        tooltipPosition="left"
        disabled={!craftable || busy}
        onClick={() => act('make_mass', { recipe: recipe.ref })} />
    </Fragment>
  );
};

const RecipeCompact = props => {
  const { recipe, atomData, craftable } = props;
  const reqText = Object.keys(recipe.reqs)
    .map(id => recipe.reqs[id] + ' ' + getAtom(atomData, id).name)
    .join(', ');
  return (
    <Box
      className="candystripe"
      style={{
        'display': 'flex',
        'align-items': 'center',
        'padding': '3px 6px',
      }}>
      <AtomIcon atom={getAtom(atomData, recipe.id)} size={32} />
      <Box ml={1} style={{ 'flex-grow': 1, 'min-width': 0 }}>
        <Box bold color={craftable ? 'good' : null}>
          {recipe.name}
        </Box>
        <Box color="label" fontSize="11px">
          {reqText}
        </Box>
      </Box>
      <Box ml={1} style={{ 'white-space': 'nowrap' }}>
        <CraftButtons {...props} />
      </Box>
    </Box>
  );
};

const RecipeCard = props => {
  const { recipe, atomData, craftable, diet } = props;
  const catalysts = Object.keys(recipe.chem_catalysts);
  const hasTools = recipe.tool_behaviors.length > 0
    || recipe.tool_paths.length > 0;
  return (
    <Box
      mb={1}
      style={{
        'display': 'flex',
        'padding': '6px',
        'background-color': 'rgba(0, 0, 0, 0.33)',
        'border-left': '3px solid '
          + (craftable ? '#5baa27' : 'rgba(255, 255, 255, 0.1)'),
      }}>
      <AtomIcon atom={getAtom(atomData, recipe.id)} size={64} />
      <Box ml={1} style={{ 'flex-grow': 1, 'min-width': 0 }}>
        <Box bold fontSize="14px">
          {recipe.name}
          {!!recipe.learned && (
            <Icon name="book" color="purple" ml={1} />
          )}
        </Box>
        {!!recipe.desc && (
          <Box color="label" italic mb={0.5}>
            {recipe.desc}
          </Box>
        )}
        <Box>
          {Object.keys(recipe.reqs).map(id => (
            <Ingredient
              key={id}
              atom={getAtom(atomData, id)}
              amount={recipe.reqs[id]} />
          ))}
        </Box>
        {catalysts.length > 0 && (
          <Box color="label">
            {'Catalysts: '}
            {catalysts.map(id => (
              <Ingredient
                key={id}
                atom={getAtom(atomData, id)}
                amount={recipe.chem_catalysts[id]} />
            ))}
          </Box>
        )}
        {hasTools && (
          <Box color="label">
            {'Tools: '}
            <ToolList recipe={recipe} atomData={atomData} />
          </Box>
        )}
        {!!recipe.foodtypes && recipe.foodtypes.length > 0 && (
          <Box mt={0.5}>
            {recipe.foodtypes.map(foodtype => (
              <Box
                key={foodtype}
                inline
                mr={1}
                color={getDietColor(foodtype, diet) || 'label'}>
                {foodtype}
              </Box>
            ))}
          </Box>
        )}
      </Box>
      <Box ml={1} textAlign="right" style={{ 'white-space': 'nowrap' }}>
        <Box color="label" mb={0.5}>
          <Icon name="clock" mr={0.5} />
          {recipe.time + 's'}
        </Box>
        <CraftButtons {...props} />
      </Box>
    </Box>
  );
};

const SidebarEntry = props => {
  const { selected, icon, iconColor, label, count, onClick } = props;
  return (
    <Button
      fluid
      color="transparent"
      selected={selected}
      onClick={onClick}>
      <Box style={{ 'display': 'flex', 'align-items': 'center' }}>
        {icon}
        <Box
          ml={1}
          color={iconColor}
          style={{
            'flex-grow': 1,
            'overflow': 'hidden',
            'text-overflow': 'ellipsis',
          }}>
          {label}
        </Box>
        {count !== undefined && (
          <Box color="label" ml={1}>
            {count}
          </Box>
        )}
      </Box>
    </Button>
  );
};

class CraftingMenu extends Component {
  constructor() {
    super();
    this.state = {
      searchText: '',
      tabMode: TAB_CATEGORY,
      activeCategory: null,
      activeMaterial: null,
      activeFoodtype: null,
      pages: 1,
    };
  }

  select(changes) {
    const content = document.getElementById('PersonalCrafting__content');
    if (content) {
      content.scrollTop = 0;
    }
    this.setState({
      searchText: '',
      pages: 1,
      ...changes,
    });
  }

  setMode(mode) {
    const { act, data } = this.props;
    if (data.mode === mode) {
      return;
    }
    this.select({
      tabMode: TAB_CATEGORY,
      activeCategory: null,
      activeMaterial: null,
      activeFoodtype: null,
    });
    act('toggle_mode', { mode });
  }

  render() {
    const { act, data } = this.props;
    const {
      busy,
      mode,
      display_compact,
      display_craftable_only,
      craftability = {},
      recipes = [],
      categories = [],
      atom_data = [],
      foodtypes = [],
      diet,
    } = data;
    const { searchText, tabMode, pages } = this.state;
    const canMakeCount = recipes
      .filter(recipe => craftability[recipe.ref]).length;

    // Ingredients used by more than one recipe, most used first
    const materialCounts = {};
    for (let recipe of recipes) {
      for (let id of Object.keys(recipe.reqs)) {
        materialCounts[id] = (materialCounts[id] || 0) + 1;
      }
    }
    const search = searchText.toLowerCase();
    const materials = Object.keys(materialCounts)
      .filter(id => materialCounts[id] > 1)
      .filter(id => tabMode !== TAB_MATERIAL || !search
        || getAtom(atom_data, id).name.toLowerCase().includes(search))
      .sort((a, b) => materialCounts[b] - materialCounts[a]);

    const activeCategory = this.state.activeCategory
      || (canMakeCount > 0 ? CAN_MAKE : categories[0]);
    const activeMaterial = this.state.activeMaterial || materials[0];
    const activeFoodtype = this.state.activeFoodtype
      || (canMakeCount > 0 ? CAN_MAKE : foodtypes[0]);

    const matchesTab = recipe => {
      if (tabMode === TAB_MATERIAL) {
        return recipe.reqs[activeMaterial] !== undefined;
      }
      if (tabMode === TAB_FOODTYPE) {
        if (activeFoodtype === CAN_MAKE) {
          return !!craftability[recipe.ref];
        }
        return !!recipe.foodtypes
          && recipe.foodtypes.includes(activeFoodtype);
      }
      if (activeCategory === CAN_MAKE) {
        return !!craftability[recipe.ref];
      }
      return recipe.category === activeCategory;
    };
    // Searching looks through every recipe by name and ingredients,
    // ignoring the selected category
    const matchesSearch = recipe => {
      if (recipe.name.toLowerCase().includes(search)) {
        return true;
      }
      return Object.keys(recipe.reqs).some(id => getAtom(atom_data, id).name
        .toLowerCase().includes(search));
    };
    // On the material tab the search box filters the material list instead
    const searchRecipes = !!search && tabMode !== TAB_MATERIAL;
    const shownRecipes = recipes
      .filter(recipe => !display_craftable_only || craftability[recipe.ref])
      .filter(recipe => searchRecipes
        ? matchesSearch(recipe)
        : matchesTab(recipe))
      .sort((a, b) => {
        const craftDiff = (craftability[b.ref] ? 1 : 0)
          - (craftability[a.ref] ? 1 : 0);
        if (craftDiff) {
          return craftDiff;
        }
        return a.name.localeCompare(b.name);
      });
    const displayLimit = pages
      * (display_compact ? PAGE_SIZE_COMPACT : PAGE_SIZE);

    return (
      <Box
        style={{
          'position': 'absolute',
          'top': 0,
          'bottom': 0,
          'left': 0,
          'right': 0,
        }}>
        {!!busy && (
          <Dimmer fontSize="32px" textAlign="center">
            <Box mt={30}>
              <Icon name="cog" spin={1} />
              {' Crafting...'}
            </Box>
          </Dimmer>
        )}
        <Box
          style={{
            'position': 'absolute',
            'top': 0,
            'bottom': 0,
            'left': 0,
            'width': '220px',
            'padding': '6px',
            'box-sizing': 'border-box',
            'overflow-y': 'auto',
            'background-color': 'rgba(0, 0, 0, 0.33)',
          }}>
          <ModeSwitch mode={mode} onMode={m => this.setMode(m)} />
          <Input
            fluid
            mt={1}
            value={searchText}
            placeholder={'Search ' + recipes.length
              + (mode === MODE_COOKING ? ' recipes...' : ' designs...')}
            onInput={(e, value) => this.setState({
              searchText: value,
              pages: 1,
            })} />
          <Box mt={1} mb={1} style={{ 'display': 'flex' }}>
            <TabButton
              label="Category"
              selected={tabMode === TAB_CATEGORY}
              onClick={() => this.select({ tabMode: TAB_CATEGORY })} />
            {mode === MODE_COOKING && (
              <TabButton
                label="Type"
                selected={tabMode === TAB_FOODTYPE}
                onClick={() => this.select({ tabMode: TAB_FOODTYPE })} />
            )}
            <TabButton
              label={mode === MODE_COOKING ? 'Ingredient' : 'Material'}
              selected={tabMode === TAB_MATERIAL}
              onClick={() => this.select({ tabMode: TAB_MATERIAL })} />
          </Box>
          {tabMode === TAB_CATEGORY && [CAN_MAKE, ...categories]
            .map(category => (
              <SidebarEntry
                key={category}
                selected={!searchRecipes && activeCategory === category}
                icon={<Icon name={getCategoryIcon(category)} />}
                label={category}
                count={category === CAN_MAKE ? canMakeCount : undefined}
                onClick={() => this.select({ activeCategory: category })} />
            ))}
          {tabMode === TAB_FOODTYPE && [CAN_MAKE, ...foodtypes]
            .map(foodtype => (
              <SidebarEntry
                key={foodtype}
                selected={!searchRecipes && activeFoodtype === foodtype}
                icon={<Icon name={foodtype === CAN_MAKE ? 'check' : 'tag'} />}
                iconColor={getDietColor(foodtype, diet)}
                label={foodtype}
                count={foodtype === CAN_MAKE ? canMakeCount : undefined}
                onClick={() => this.select({ activeFoodtype: foodtype })} />
            ))}
          {tabMode === TAB_MATERIAL && materials.map(id => (
            <SidebarEntry
              key={id}
              selected={activeMaterial === id}
              icon={<AtomIcon atom={getAtom(atom_data, id)} size={16} />}
              label={getAtom(atom_data, id).name}
              count={materialCounts[id]}
              onClick={() => this.select({
                activeMaterial: id,
                searchText,
              })} />
          ))}
          <Box
            mt={1}
            style={{
              'padding-top': '6px',
              'border-top': '1px solid rgba(255, 255, 255, 0.1)',
            }}>
            <Button.Checkbox
              fluid
              checked={display_craftable_only}
              content="Can make only"
              onClick={() => act('toggle_recipes')} />
            <Button.Checkbox
              fluid
              checked={display_compact}
              content="Compact list"
              onClick={() => act('toggle_compact')} />
          </Box>
        </Box>
        <Box
          id="PersonalCrafting__content"
          style={{
            'position': 'absolute',
            'top': 0,
            'bottom': 0,
            'left': '220px',
            'right': 0,
            'padding': '6px',
            'overflow-y': 'auto',
          }}>
          {shownRecipes.length === 0 && (
            <NoticeBox>
              No recipes found.
            </NoticeBox>
          )}
          {shownRecipes.slice(0, displayLimit).map(recipe => {
            const RecipeComponent = display_compact
              ? RecipeCompact
              : RecipeCard;
            return (
              <RecipeComponent
                key={recipe.ref}
                recipe={recipe}
                atomData={atom_data}
                craftable={!!craftability[recipe.ref]}
                busy={busy}
                diet={diet}
                act={act} />
            );
          })}
          {shownRecipes.length > displayLimit && (
            <Button
              fluid
              textAlign="center"
              content={'Load more ('
                + (shownRecipes.length - displayLimit) + ' left)'}
              onClick={() => this.setState({ pages: pages + 1 })} />
          )}
        </Box>
      </Box>
    );
  }
}

const TabButton = props => {
  const { label, selected, onClick } = props;
  return (
    <Box style={{ 'flex-grow': 1 }}>
      <Button
        fluid
        textAlign="center"
        selected={selected}
        content={label}
        onClick={onClick} />
    </Box>
  );
};

const ModeSwitch = props => {
  const { mode, onMode } = props;
  return (
    <Box style={{ 'display': 'flex' }}>
      <Box style={{ 'flex-grow': 1 }} mr={0.5}>
        <Button
          fluid
          textAlign="center"
          icon="hammer"
          content="Craft"
          selected={mode === MODE_CRAFTING}
          onClick={() => onMode(MODE_CRAFTING)} />
      </Box>
      <Box style={{ 'flex-grow': 1 }}>
        <Button
          fluid
          textAlign="center"
          icon="utensils"
          content="Cook"
          selected={mode === MODE_COOKING}
          onClick={() => onMode(MODE_COOKING)} />
      </Box>
    </Box>
  );
};

export const PersonalCrafting = props => {
  const { act, data } = useBackend(props);
  return (
    <CraftingMenu act={act} data={data} />
  );
};
