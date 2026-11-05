import { Component, Fragment } from 'inferno';
import { useBackend } from '../backend';
import { Box, Button, Flex, Input, NoticeBox, Section } from '../components';

// hippie -- the mining equipment vendor
// (hippiestation/.../mining/machine_vending_tgui.dm)

const GROUPS = ['Equipment', 'Minebot', 'Kinetic accelerator mods', 'Comforts'];

const Prize = props => {
  const { prize, points, hasId, act } = props;
  const affordable = hasId && points >= prize.cost;
  return (
    <Flex className="candystripe" p={0.5} align="center">
      <Flex.Item style={{ 'width': '32px', 'flex-shrink': 0 }} mr={1}>
        {!!prize.icon && (
          <img
            src={prize.icon}
            width="32px"
            height="32px"
            style={{ '-ms-interpolation-mode': 'nearest-neighbor' }} />
        )}
      </Flex.Item>
      <Flex.Item grow={1} color={affordable ? null : 'label'}>
        {prize.name}
      </Flex.Item>
      <Flex.Item mr={1} color={affordable ? 'good' : 'label'}>
        {prize.cost + ' pts'}
      </Flex.Item>
      <Flex.Item>
        <Button
          icon="shopping-cart"
          content="Buy"
          disabled={!affordable}
          onClick={() => act('purchase', { index: prize.index })} />
      </Flex.Item>
    </Flex>
  );
};

class Shop extends Component {
  constructor() {
    super();
    this.state = { search: '' };
  }

  render() {
    const { data, act } = this.props;
    const query = this.state.search.toLowerCase();
    const prizes = (data.prizes || [])
      .filter(p => !query || p.name.toLowerCase().includes(query));
    const hasId = !!data.id;
    return (
      <Section
        title="For sale"
        buttons={(
          <Input
            width="180px"
            placeholder="Search..."
            value={this.state.search}
            onInput={(e, value) => this.setState({ search: value })} />
        )}>
        {prizes.length === 0 && (
          <Box color="label">Nothing matches that.</Box>
        )}
        {GROUPS.map(group => {
          const list = prizes.filter(p => p.group === group);
          if (!list.length) {
            return null;
          }
          return (
            <Box key={group} mb={1}>
              <Box bold color="label" mb={0.5}>{group}</Box>
              {list.map(prize => (
                <Prize
                  key={prize.index}
                  prize={prize}
                  points={data.points}
                  hasId={hasId}
                  act={act} />
              ))}
            </Box>
          );
        })}
      </Section>
    );
  }
}

export const MiningVendor = props => {
  const { act, data } = useBackend(props);
  let idButton = (
    <Button
      icon="id-card"
      content="Insert ID"
      disabled={!data.holding_id}
      onClick={() => act('insert')} />
  );
  let points = (
    <NoticeBox>
      Insert an ID to spend the mining points collected at the ore
      redemption machine.
    </NoticeBox>
  );
  if (data.id) {
    idButton = (
      <Button
        icon="eject"
        content="Eject ID"
        onClick={() => act('eject')} />
    );
    points = (
      <Box>
        <Box inline bold color="good" fontSize="18px">{data.points}</Box>
        <Box inline ml={1} color="label">mining points to spend</Box>
      </Box>
    );
  }
  return (
    <Fragment>
      <Section title={data.id || 'No ID inserted'} buttons={idButton}>
        {points}
      </Section>
      <Shop data={data} act={act} />
    </Fragment>
  );
};
