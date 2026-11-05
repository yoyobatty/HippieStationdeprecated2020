import { Fragment } from 'inferno';
import { useBackend } from '../backend';
import { Box, Button, Collapsible, Section, Table, Tabs } from '../components';

// hippie -- the clockwork slab (was tgui/src/interfaces/clockwork_slab.ract),
// on the brass theme (styles/themes/clockwork.scss). The slab sends its text as
// the game's own HTML (colours and all), as it did to the old window.

const Html = props => {
  const { html, ...rest } = props;
  // eslint-disable-next-line react/no-danger
  return <Box {...rest} dangerouslySetInnerHTML={{ __html: html }} />;
};

const TIERS = [
  ['Driver', 'Drivers'],
  ['Script', 'Scripts'],
  ['Application', 'Applications'],
];

const Scripture = props => {
  const { act, data } = props;
  const scripture = data.scripture || [];
  return (
    <Fragment>
      <Section>
        <Html html={data.power} />
      </Section>
      <Tabs activeTab={data.selected}>
        {TIERS.map(tier => (
          <Tabs.Tab
            key={tier[0]}
            label={tier[1]}
            onClick={() => act('select', { category: tier[0] })} />
        ))}
      </Tabs>
      <Html html={data.tier_info} mb={1} />
      <Collapsible title="What the colours mean">
        <Html html={data.scripturecolors} mb={1} />
      </Collapsible>
      <Table>
        {scripture.map(item => (
          <Table.Row key={item.type}>
            <Table.Cell collapsing py={0.5} pr={1}>
              <Button
                icon="cog"
                content="Recite"
                tooltip={item.tip}
                tooltipPosition="right"
                onClick={() => act('recite', { category: item.type })} />
            </Table.Cell>
            <Table.Cell>
              <Html inline html={item.name} />
              {' '}
              <Html inline html={item.descname} />
              <Box color="label">
                {item.required}
                {!!item.invokers && (
                  <Fragment>
                    {' · '}
                    <Html inline html={item.invokers} />
                  </Fragment>
                )}
              </Box>
            </Table.Cell>
            <Table.Cell collapsing textAlign="right">
              {!!item.quickbind && (
                <Button
                  selected={!!item.bound}
                  onClick={() => act('bind', { category: item.type })}>
                  {item.bound
                    ? (
                      <Fragment>
                        Unbind <Html inline html={item.bound} />
                      </Fragment>
                    )
                    : 'Quickbind'}
                </Button>
              )}
            </Table.Cell>
          </Table.Row>
        ))}
      </Table>
    </Fragment>
  );
};

const Recollection = props => {
  const { act, data } = props;
  const categories = data.recollection_categories || [];
  return (
    <Section>
      <Html html={data.rec_text} />
      <Box my={1}>
        {categories.map(category => (
          <Button
            key={category.name}
            fluid
            icon="book"
            onClick={() => act('rec_category', { category: category.name })}>
            <b>{category.name}</b>
            <Box inline color="label" ml={1}>
              {category.desc}
            </Box>
          </Button>
        ))}
      </Box>
      <Html html={data.rec_section} />
      <Html html={data.rec_binds} />
    </Section>
  );
};

export const ClockworkSlab = props => {
  const { act, data } = useBackend(props);
  return (
    <Fragment>
      <Box mb={1}>
        <Button
          icon={data.recollection ? 'cogs' : 'book'}
          content={data.recollection
            ? 'Back to recital'
            : 'Recollection: the guide to serving Ratvar'}
          onClick={() => act('toggle')} />
      </Box>
      {data.recollection
        ? <Recollection act={act} data={data} />
        : <Scripture act={act} data={data} />}
    </Fragment>
  );
};
