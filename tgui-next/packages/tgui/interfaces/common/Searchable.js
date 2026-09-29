import { Component, Fragment } from 'inferno';
import { Box, Icon, Input, NumberInput } from '../../components';

/**
 * A search box for interfaces that are otherwise stateless. It's a class
 * because the search text has to live somewhere between backend updates.
 *
 * children is a function (matches, searching, amount) => content, where
 * matches(...strings) is true when the search is empty or any of the strings
 * contains it (ignoring case), and searching is true while there's a search.
 *
 * Give it amountMax and it also shows a quantity box (1 to amountMax) beside
 * the search, for buttons that order or dispense several at once; amount is
 * what it's set to (always 1 without amountMax).
 */
export class Searchable extends Component {
  constructor() {
    super();
    this.state = {
      search: '',
      amount: 1,
    };
  }

  render() {
    const { children, placeholder = 'Search...', amountMax } = this.props;
    const { search } = this.state;
    const amount = amountMax ? Math.min(this.state.amount, amountMax) : 1;
    const term = search.trim().toLowerCase();
    const matches = (...strings) => !term || strings.some(string => (
      String(string || '').toLowerCase().includes(term)
    ));
    return (
      <Fragment>
        <Box mb={1}>
          <Icon name="search" mr={1} color="label" />
          <Input
            width="60%"
            value={search}
            placeholder={placeholder}
            onInput={(e, value) => this.setState({ search: value })} />
          {!!amountMax && (
            <Box inline ml={2}>
              <Box inline color="label" mr={1}>
                Qty
              </Box>
              <NumberInput
                width="40px"
                value={amount}
                minValue={1}
                maxValue={amountMax}
                step={1}
                stepPixelSize={15}
                onChange={(e, value) => this.setState({
                  amount: Math.round(value),
                })} />
            </Box>
          )}
        </Box>
        {children(matches, !!term, amount)}
      </Fragment>
    );
  }
}
