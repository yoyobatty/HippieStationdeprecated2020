import { decodeHtmlEntities } from 'common/string';
import { Component } from 'inferno';
import { useBackend } from '../backend';
import { Box, Button, Input, Section, Table } from '../components';

// hippie -- the admin Secrets panel (by section, the round-changing ones in
// red, with a search) and the searchable list window its logs and lists open
// in. Data from hippiestation/code/modules/admin/secrets_tgui.dm.

export class AdminSecrets extends Component {
  constructor() {
    super();
    this.state = { search: '' };
  }

  render() {
    const { act, data } = useBackend(this.props);
    const query = this.state.search.toLowerCase();
    const sections = (data.sections || []).map(section => ({
      name: section.name,
      items: section.items.filter(item => !query
        || item.label.toLowerCase().includes(query)),
    })).filter(section => section.items.length);
    return (
      <Box>
        <Box mb={1}>
          <Input
            fluid
            placeholder="Search secrets..."
            value={this.state.search}
            onInput={(e, value) => this.setState({ search: value })} />
        </Box>
        {sections.map(section => (
          <Section key={section.name} title={section.name}>
            {section.items.map(item => (
              <Button
                key={item.id}
                content={item.label}
                color={item.danger ? 'bad' : null}
                onClick={() => act('secret', { id: item.id })} />
            ))}
          </Section>
        ))}
      </Box>
    );
  }
}

export class AdminList extends Component {
  constructor() {
    super();
    this.state = { search: '' };
  }

  render() {
    const { data } = useBackend(this.props);
    const query = this.state.search.toLowerCase();
    const rows = (data.rows || []).filter(row => !query
      || row.some(cell => String(cell).toLowerCase().includes(query)));
    const columns = data.columns;
    return (
      <Section
        title={rows.length + ' of ' + (data.rows || []).length}
        buttons={(
          <Input
            placeholder="Search..."
            value={this.state.search}
            onInput={(e, value) => this.setState({ search: value })} />
        )}>
        {rows.length === 0 && <Box color="label">Nothing here.</Box>}
        <Table>
          {!!columns && (
            <Table.Row header>
              {columns.map(column => (
                <Table.Cell key={column}>{column}</Table.Cell>
              ))}
            </Table.Row>
          )}
          {rows.map((row, i) => (
            <Table.Row key={i} className="candystripe">
              {row.map((cell, j) => (
                <Table.Cell key={j} py={0.5}>
                  {decodeHtmlEntities(String(cell))}
                </Table.Cell>
              ))}
            </Table.Row>
          ))}
        </Table>
      </Section>
    );
  }
}
