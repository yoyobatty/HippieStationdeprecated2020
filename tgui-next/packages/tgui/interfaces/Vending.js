import { Component, Fragment } from 'inferno';
import { useBackend } from '../backend';
import { Box, Button, Icon, Input, NoticeBox, NumberInput, Section, Tabs } from '../components';

// hippie -- vending machines as a shop (data from
// hippiestation/code/modules/vending/_vending.dm): a grid of item cards with
// their sprites, stock and price, tabs for premium and contraband stock, your
// card and balance up top

const stockColor = (stock, max) => {
  if (stock <= 0) {
    return 'bad';
  }
  return stock <= max / 2 ? 'average' : 'good';
};

const ItemCard = props => {
  const { product, custom, act, data, amount } = props;
  const free = (data.department && data.user
    && data.department === data.user.department)
    || product.price === 0 || !data.onstation || !data.scanid
    || (data.user && data.user.unlimited);
  const stock = custom ? product.amount : data.stock[product.name];
  const total = product.price * amount;
  const cantAfford = !free && (!data.user || total > data.user.cash);
  const empty = !custom && stock <= 0;
  let price = free ? 'Free' : '$' + total;
  if (custom && data.access) {
    price = 'Take';
  }
  return (
    <div className={'Vending__card' + (empty ? ' Vending__card--empty' : '')}>
      <div className="Vending__picture">
        {!custom && (
          <span className={'vending32x32 ' + product.path} />
        ) || (
          <Icon name="box" size={2} />
        )}
      </div>
      <div className="Vending__name" title={product.name}>
        {product.name}
      </div>
      <Box
        fontSize="11px"
        color={custom ? 'label' : stockColor(stock, product.max_amount)}>
        {empty ? 'Sold out' : stock + ' left'}
      </Box>
      <Button
        fluid
        mt={0.5}
        textAlign="center"
        color={free && !empty ? 'good' : null}
        disabled={empty || (!custom && cantAfford)}
        content={price}
        tooltip={cantAfford && !empty ? 'Not enough money' : null}
        onClick={() => custom
          ? act('dispense', { item: product.name, amount })
          : act('vend', { ref: product.ref, amount })} />
    </div>
  );
};

export class Vending extends Component {
  constructor() {
    super();
    this.state = { tab: 'products', search: '', amount: 1 };
  }

  render() {
    const { act, data } = useBackend(this.props);
    const { search, amount } = this.state;
    const custom = !!data.vending_machine_input;
    const premium = data.coin_records || [];
    const contraband = (data.extended_inventory && data.hidden_records)
      || [];
    let tab = this.state.tab;
    if ((tab === 'premium' && !premium.length)
      || (tab === 'contraband' && !contraband.length)) {
      tab = 'products';
    }
    let inventory = custom ? data.vending_machine_input : data.product_records;
    if (tab === 'premium') {
      inventory = premium;
    }
    if (tab === 'contraband') {
      inventory = contraband;
    }
    const term = search.toLowerCase();
    const shown = (inventory || [])
      .filter(product => !term || product.name.toLowerCase().includes(term));
    const user = data.user;
    const departmentFree = data.department && user
      && data.department === user.department;
    return (
      <Fragment>
        <Section>
          {user && (
            <Box>
              <Icon name="id-card" mr={1} />
              <b>{user.name}</b>
              <Box inline color="label" ml={1}>
                {user.job || 'Unemployed'}
              </Box>
              <Box inline style={{ float: 'right' }} bold color="good">
                {user.unlimited ? 'Unlimited' : '$' + user.cash}
              </Box>
              {!!departmentFree && (
                <Box color="good" mt={0.5}>
                  <Icon name="check" mr={1} />
                  Free for your department
                </Box>
              )}
            </Box>
          ) || (
            <NoticeBox mb={0}>
              No ID card with a bank account. See the Head of Personnel.
            </NoticeBox>
          )}
        </Section>
        {!custom && (premium.length > 0 || contraband.length > 0) && (
          <Tabs activeTab={tab}>
            <Tabs.Tab
              key="products"
              label="Products"
              onClick={() => this.setState({ tab: 'products' })} />
            {premium.length > 0 && (
              <Tabs.Tab
                key="premium"
                label="Premium"
                onClick={() => this.setState({ tab: 'premium' })} />
            )}
            {contraband.length > 0 && (
              <Tabs.Tab
                key="contraband"
                label="Contraband"
                onClick={() => this.setState({ tab: 'contraband' })} />
            )}
          </Tabs>
        )}
        <Section
          title={shown.length + (shown.length === 1 ? ' item' : ' items')}
          buttons={(
            <Fragment>
              <Input
                width="150px"
                placeholder="Search..."
                value={search}
                onInput={(e, value) => this.setState({ search: value })} />
              <Box inline ml={1} color="label">Buy</Box>
              <NumberInput
                ml={0.5}
                width="40px"
                value={amount}
                minValue={1}
                maxValue={10}
                onChange={(e, value) => this.setState({ amount: value })} />
            </Fragment>
          )}>
          {shown.length === 0 && (
            <Box color="label">Nothing here.</Box>
          )}
          <div className="Vending__grid">
            {shown.map(product => (
              <ItemCard
                key={product.name}
                product={product}
                custom={custom}
                act={act}
                data={data}
                amount={amount} />
            ))}
          </div>
        </Section>
      </Fragment>
    );
  }
}
