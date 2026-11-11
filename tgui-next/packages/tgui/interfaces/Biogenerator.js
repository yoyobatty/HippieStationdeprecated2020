import { Component, Fragment } from 'inferno';
import { useBackend } from '../backend';
import { Box, Button, Flex, Icon, Input, LabeledList, ProgressBar, Section } from '../components';

// hippie -- the biogenerator
// (hippiestation/.../hydroponics/biogenerator_tgui.dm)

// A stack is made all at once; anything else one at a time for as long
// as the biomass lasts, so it needs only enough for the first.
const tooDear = (design, points, amount) => {
  const needed = design.stack ? design.cost * amount : design.cost;
  return needed > points;
};

// Every row the height of a picture, with one or not
const PICTURE = { 'width': '32px', 'height': '32px', 'flex-shrink': 0 };

const Product = props => {
  const { design, points, canMake, act } = props;
  const make = amount => act('create', { id: design.id, amount });
  const affordable = canMake && design.cost <= points;
  return (
    <Flex className="candystripe" p={0.5} align="center">
      <Flex.Item style={PICTURE} mr={1}>
        {!!design.icon && (
          <img
            src={design.icon}
            width="32px"
            height="32px"
            style={{ '-ms-interpolation-mode': 'nearest-neighbor' }} />
        )}
        {!design.icon && !!design.reagent && (
          <Box textAlign="center" color="label" lineHeight="32px">
            <Icon name="flask" size={1.5} />
          </Box>
        )}
      </Flex.Item>
      <Flex.Item grow={1} color={affordable ? null : 'label'}>
        {design.name}
      </Flex.Item>
      <Flex.Item mr={1} color={affordable ? 'good' : 'label'}>
        {design.cost}
      </Flex.Item>
      <Flex.Item>
        <Button
          content="Make"
          disabled={!canMake || tooDear(design, points, 1)}
          onClick={() => make(1)} />
        {!!design.times5 && (
          <Button
            content="x5"
            disabled={!canMake || tooDear(design, points, 5)}
            onClick={() => make(5)} />
        )}
        {!!design.stack && (
          <Button
            content="x10"
            disabled={!canMake || tooDear(design, points, 10)}
            onClick={() => make(10)} />
        )}
      </Flex.Item>
    </Flex>
  );
};

class Products extends Component {
  constructor() {
    super();
    this.state = { search: '' };
  }

  render() {
    const { data, act } = this.props;
    const query = this.state.search.toLowerCase();
    const canMake = !!data.beaker && !data.processing;
    const groups = (data.categories || []).map(category => ({
      name: category.name,
      designs: category.designs
        .filter(d => !query || d.name.toLowerCase().includes(query)),
    })).filter(category => category.designs.length);
    return (
      <Section
        title="Products"
        buttons={(
          <Input
            width="180px"
            placeholder="Search..."
            value={this.state.search}
            onInput={(e, value) => this.setState({ search: value })} />
        )}>
        {groups.length === 0 && (
          <Box color="label">Nothing matches that.</Box>
        )}
        {groups.map(category => (
          <Box key={category.name} mb={1}>
            <Box bold color="label" mb={0.5}>{category.name}</Box>
            {category.designs.map(design => (
              <Product
                key={design.id}
                design={design}
                points={data.points}
                canMake={canMake}
                act={act} />
            ))}
          </Box>
        ))}
      </Section>
    );
  }
}

export const Biogenerator = props => {
  const { act, data } = useBackend(props);
  const beaker = data.beaker;
  let container = (
    <Box color="bad">No container.</Box>
  );
  if (beaker) {
    container = (
      <Flex align="center">
        <Flex.Item grow={1}>
          <ProgressBar value={beaker.volume / beaker.max}>
            {beaker.name + ': ' + beaker.volume + ' / ' + beaker.max + 'u'}
          </ProgressBar>
        </Flex.Item>
        <Flex.Item ml={1}>
          <Button
            icon="eject"
            content="Detach"
            disabled={data.processing}
            onClick={() => act('detach')} />
        </Flex.Item>
      </Flex>
    );
  }
  let status = null;
  if (data.processing) {
    status = <Box color="average">Processing. Please wait...</Box>;
  }
  else if (data.notice) {
    status = (
      <Box color={data.notice_good ? 'good' : 'bad'}>{data.notice}</Box>
    );
  }
  return (
    <Fragment>
      <Section
        title="Biomass"
        buttons={(
          <Button
            icon="cog"
            content="Activate"
            disabled={data.processing || !data.growns}
            onClick={() => act('activate')} />
        )}>
        <LabeledList>
          <LabeledList.Item label="Biomass">
            <Box inline bold color="good" fontSize="18px">{data.points}</Box>
            <Box inline ml={1} color="label">units</Box>
          </LabeledList.Item>
          <LabeledList.Item label="Reactor">
            <ProgressBar value={data.growns / data.max_items}>
              {data.growns + ' / ' + data.max_items + ' growns'}
            </ProgressBar>
          </LabeledList.Item>
          <LabeledList.Item label="Container">
            {container}
          </LabeledList.Item>
          {!!status && (
            <LabeledList.Item label="Status">
              {status}
            </LabeledList.Item>
          )}
        </LabeledList>
      </Section>
      <Products data={data} act={act} />
    </Fragment>
  );
};
