import { decodeHtmlEntities } from 'common/string';
import { Component, Fragment } from 'inferno';
import { act } from '../byond';
import { Box, Button, Icon, Input, Section } from '../components';

// hippie -- the uplink redone as a shop: categories down the side, the items
// as cards with their pictures (or a list), a panel with the picked item's
// description and Buy, and stock left on the limited ones. Pictures come from
// the uplink sprite sheet in hippiestation/code/modules/uplink/
// uplink_tgui.dm.

const ItemPicture = props => {
  const { item, big } = props;
  return (
    <div
      className={'Uplink__picture' + (big ? ' Uplink__picture--big' : '')}>
      {item.icon && (
        <span className={'uplink32x32 ' + item.icon} />
      ) || (
        <Icon name="box" size={big ? 2 : 1.5} color="label" />
      )}
    </div>
  );
};

export class Uplink extends Component {
  constructor() {
    super();
    this.state = {
      category: null,
      search: '',
      picked: null,
    };
  }

  render() {
    const { state } = this.props;
    const { config, data } = state;
    const { ref } = config;
    const {
      compact_mode,
      lockable,
      telecrystals,
      stock = {},
      categories = [],
    } = data;
    const { search, picked } = this.state;
    const shown = categories.filter(cat => cat.items && cat.items.length);
    const category = shown.find(cat => cat.name === this.state.category)
      || shown[0];
    const term = search.toLowerCase();
    const items = term
      ? shown
        .flatMap(cat => cat.items)
        .filter(item => (item.name + item.desc).toLowerCase().includes(term))
      : (category ? category.items : []);
    const allItems = shown.flatMap(cat => cat.items);
    const pickedItem = picked && allItems.find(item => item.name === picked);
    const left = item => (stock[item.name] === undefined
      ? -1
      : stock[item.name]);
    const canBuy = item => telecrystals >= item.cost && left(item) !== 0;
    const buy = item => act(ref, 'buy', { item: item.name });
    const pick = item => this.setState({
      picked: picked === item.name ? null : item.name,
    });
    return (
      <Fragment>
        <Section>
          <Box inline fontSize="20px" bold
            color={telecrystals > 0 ? 'good' : 'bad'}>
            {telecrystals} TC
          </Box>
          <Box inline style={{ float: 'right' }}>
            <Input
              width="180px"
              placeholder="Search..."
              value={search}
              onInput={(e, value) => this.setState({ search: value })} />
            <Button
              icon={compact_mode ? 'th' : 'list'}
              content={compact_mode ? 'Grid' : 'List'}
              onClick={() => act(ref, 'compact_toggle')} />
            {!!lockable && (
              <Button
                icon="lock"
                content="Lock"
                onClick={() => act(ref, 'lock')} />
            )}
          </Box>
        </Section>
        <div className="Uplink__layout">
          <div className="Uplink__categories">
            {shown.map(cat => (
              <Button
                key={cat.name}
                fluid
                selected={!term && category && cat.name === category.name}
                color={cat.name === 'Discounted Gear' ? 'good' : 'transparent'}
                onClick={() => this.setState({
                  category: cat.name,
                  search: '',
                })}>
                {cat.name}
                <Box inline color="label" ml={0.5}>{cat.items.length}</Box>
              </Button>
            ))}
          </div>
          <div className="Uplink__main">
            {!!pickedItem && (
              <div className="Uplink__panel">
                <ItemPicture item={pickedItem} big />
                <div className="Uplink__panelText">
                  <Box bold fontSize="14px">
                    {decodeHtmlEntities(pickedItem.name)}
                    {left(pickedItem) >= 0 && (
                      <Box inline color="average" ml={1} fontSize="11px">
                        {left(pickedItem)} left
                      </Box>
                    )}
                    {!!pickedItem.refundable && (
                      <Box inline color="good" ml={1} fontSize="11px">
                        refundable
                      </Box>
                    )}
                  </Box>
                  <Box my={0.5}>{decodeHtmlEntities(pickedItem.desc)}</Box>
                  <Button
                    icon="shopping-cart"
                    content={'Buy (' + pickedItem.cost + ' TC)'}
                    disabled={!canBuy(pickedItem)}
                    onClick={() => buy(pickedItem)} />
                  <Button
                    icon="times"
                    content="Close"
                    onClick={() => this.setState({ picked: null })} />
                </div>
              </div>
            )}
            <Section
              title={term
                ? items.length + ' found'
                : category && category.name}>
              {items.length === 0 && (
                <Box color="label">No items.</Box>
              )}
              {!compact_mode && (
                <div className="Uplink__grid">
                  {items.map(item => (
                    <div
                      key={item.name}
                      className={'Uplink__card'
                        + (picked === item.name ? ' Uplink__card--picked' : '')
                        + (left(item) === 0 ? ' Uplink__card--gone' : '')}
                      title={decodeHtmlEntities(item.desc)}
                      onClick={() => pick(item)}>
                      <ItemPicture item={item} />
                      <div className="Uplink__name">
                        {decodeHtmlEntities(item.name)}
                      </div>
                      <Button
                        fluid
                        content={item.cost + ' TC'}
                        disabled={!canBuy(item)}
                        onClick={e => {
                          e.stopPropagation();
                          buy(item);
                        }} />
                    </div>
                  ))}
                </div>
              ) || items.map(item => (
                <div
                  key={item.name}
                  className={'Uplink__row'
                    + (picked === item.name ? ' Uplink__card--picked' : '')}
                  onClick={() => pick(item)}>
                  <ItemPicture item={item} />
                  <div className="Uplink__rowText">
                    <Box bold>{decodeHtmlEntities(item.name)}</Box>
                    <div className="Uplink__rowDesc">
                      {decodeHtmlEntities(item.desc)}
                    </div>
                  </div>
                  <Button
                    content={item.cost + ' TC'}
                    disabled={!canBuy(item)}
                    onClick={e => {
                      e.stopPropagation();
                      buy(item);
                    }} />
                </div>
              ))}
            </Section>
          </div>
        </div>
      </Fragment>
    );
  }
}
