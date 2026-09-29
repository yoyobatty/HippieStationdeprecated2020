import { Fragment } from 'inferno';
import { useBackend } from '../backend';
import { Section, Box, Button, Table } from '../components';
import { Searchable } from './common/Searchable';

// What a buy button says: the price for the quantity picked
const priceLabel = (free, price, amount) => {
  if (amount > 1) {
    return (free ? 'FREE' : '$' + price * amount) + ' (' + amount + 'x)';
  }
  return free ? 'FREE' : '$' + price;
};

const VendingRow = props => {
  const { product, custom, act, data, amount } = props;
  const free = ((data.department && data.user
    && data.department === data.user.department)
    || product.price === 0 || !data.onstation || !data.scanid
    || (data.user && data.user.unlimited));
  const stock = custom ? product.amount : data.stock[product.name];
  return (
    <Table.Row>
      <Table.Cell>
        {product.base64 && (
          <img src={`data:image/jpeg;base64,${product.img}`}
            style={{
              'vertical-align': 'middle',
              'horizontal-align': 'middle',
            }} />
        ) || (
          <span className={['vending32x32', product.path].join(' ')}
            style={{
              'vertical-align': 'middle',
              'horizontal-align': 'middle',
            }} />
        )}
        <b>{product.name}</b>
      </Table.Cell>
      <Table.Cell>
        <Box color={custom
          ? 'good'
          : stock <= 0
            ? 'bad'
            : stock <= (product.max_amount / 2)
              ? 'average'
              : 'good'}>
          {stock} in stock
        </Box>
      </Table.Cell>
      <Table.Cell>
        {custom && (
          <Button
            content={priceLabel(data.access, product.price, amount)}
            onClick={() => act('dispense', {
              'item': product.name,
              'amount': amount,
            })} />
        ) || (
          <Button
            disabled={(!free && (!data.user
                || (product.price > data.user.cash)))
                || stock === 0}
            content={priceLabel(free, product.price, amount)}
            onClick={() => act('vend', {
              'ref': product.ref,
              'amount': amount,
            })} />
        )}
      </Table.Cell>
    </Table.Row>
  );
};

export const Vending = props => {
  const { act, data } = useBackend(props);
  let inventory;
  let custom = false;
  if (data.vending_machine_input) {
    inventory = data.vending_machine_input;
    custom = true;
  } else if (data.extended_inventory) {
    inventory = [...data.product_records,
      ...data.coin_records,
      ...data.hidden_records];
  } else {
    inventory = [...data.product_records, ...data.coin_records];
  }
  return (
    <Fragment>
      <Section
        title="User">
        {data.user && (
          <Box>
            Welcome, <b>{data.user.name}</b>,
            <b>{data.user.job || "Unemployed"}</b>!<br />
            Your balance is{' '}
            <b>
              {data.user.unlimited ? 'unlimited' : '$' + data.user.cash}
            </b>.
          </Box>
        ) || (
          <Box color="light-gray">
            No registered ID card!<br />
            Please contact your local HoP!
          </Box>
        )}
      </Section>
      <Section
        title="Products">
        <Searchable placeholder="Search products..." amountMax={10}>
          {(matches, searching, amount) => (
            <Table>
              {inventory
                .filter(product => matches(product.name))
                .map(product => (
                  <VendingRow
                    key={product.name}
                    product={product}
                    custom={custom}
                    act={act}
                    data={data}
                    amount={amount} />
                ))}
            </Table>
          )}
        </Searchable>
      </Section>
    </Fragment>
  );
};
