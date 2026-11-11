import { Component, Fragment } from 'inferno';
import { useBackend } from '../backend';
import { Box, Button, Icon, Input, LabeledList, NoticeBox, NumberInput, Section, Table } from '../components';

// hippie -- the magnetic controller, stacking machine console, food cart and
// ice cream vat (hippiestation/code/game/machinery/misc_machines_tgui.dm)

export class MagnetController extends Component {
  constructor() {
    super();
    this.state = { path: null };
  }

  render() {
    const { act, data } = useBackend(this.props);
    const {
      autolink,
      frequency,
      code,
      speed,
      moving,
      magnets = [],
    } = data;
    const path = this.state.path === null ? data.path : this.state.path;
    return (
      <Fragment>
        <Section
          title="Magnets"
          buttons={(
            <Button
              icon="power-off"
              content="Toggle power"
              onClick={() => act('togglepower')} />
          )}>
          {!autolink && (
            <Box color="label" mb={1}>
              Frequency {frequency}, code {code}
            </Box>
          )}
          {magnets.length === 0 && (
            <Box color="label">No magnets found.</Box>
          )}
          {magnets.map((magnet, i) => (
            <Box key={i}>
              <Icon name="magnet" mr={1}
                color={magnet.on ? 'good' : 'label'} />
              Magnet {i + 1}: {magnet.on ? 'on' : 'off'},
              electricity {magnet.electricity}, field {magnet.field}
            </Box>
          ))}
          <LabeledList>
            <LabeledList.Item label="Electricity (all)">
              <Button icon="minus" onClick={() => act('minuselec')} />
              <Button icon="plus" onClick={() => act('pluselec')} />
            </LabeledList.Item>
            <LabeledList.Item label="Field (all)">
              <Button icon="minus" onClick={() => act('minusmag')} />
              <Button icon="plus" onClick={() => act('plusmag')} />
            </LabeledList.Item>
          </LabeledList>
        </Section>
        <Section
          title="Movement"
          buttons={(
            <Button
              icon={moving ? 'stop' : 'play'}
              selected={moving}
              content={moving ? 'Moving' : 'Stopped'}
              onClick={() => act('togglemoving')} />
          )}>
          <LabeledList>
            <LabeledList.Item label="Speed">
              <Button icon="minus" onClick={() => act('minusspeed')} />
              <Box inline mx={1} bold>{speed}</Box>
              <Button icon="plus" onClick={() => act('plusspeed')} />
            </LabeledList.Item>
            <LabeledList.Item label="Path">
              <Input
                width="200px"
                value={path}
                onInput={(e, value) => this.setState({ path: value })} />
              <Button
                content="Set"
                onClick={() => {
                  act('setpath', { path });
                  this.setState({ path: null });
                }} />
            </LabeledList.Item>
          </LabeledList>
          <Box color="label" mt={1}>
            Path letters: N, S, E, W to move, C back to the centre, R anywhere.
          </Box>
        </Section>
      </Fragment>
    );
  }
}

export const StackingConsole = props => {
  const { act, data } = useBackend(props);
  const { linked, stackAmount, sheets = [] } = data;
  if (!linked) {
    return (
      <NoticeBox>
        No stacking machine linked.
      </NoticeBox>
    );
  }
  return (
    <Section title={'Stacks of ' + stackAmount}>
      {sheets.length === 0 && (
        <Box color="label">Nothing stacked yet.</Box>
      )}
      <Table>
        {sheets.map(sheet => (
          <Table.Row key={sheet.type}>
            <Table.Cell>{sheet.name}</Table.Cell>
            <Table.Cell collapsing textAlign="right" pr={1}>
              {sheet.amount}
            </Table.Cell>
            <Table.Cell collapsing>
              <Button
                icon="eject"
                content="Release"
                onClick={() => act('release', { type: sheet.type })} />
            </Table.Cell>
          </Table.Row>
        ))}
      </Table>
    </Section>
  );
};

const ReagentRows = props => {
  const { list = [], buttons, empty } = props;
  if (!list.length) {
    return <Box color="label">{empty}</Box>;
  }
  return (
    <Table>
      {list.map(reagent => (
        <Table.Row key={reagent.type}>
          <Table.Cell>{reagent.name}</Table.Cell>
          <Table.Cell collapsing textAlign="right" pr={1} color="label">
            {reagent.volume}u
          </Table.Cell>
          <Table.Cell collapsing>{buttons(reagent)}</Table.Cell>
        </Table.Row>
      ))}
    </Table>
  );
};

export const FoodCart = props => {
  const { act, data } = useBackend(props);
  const { glasses, portion, reagents, mixer, food = [] } = data;
  const noGlass = glasses <= 0;
  return (
    <Fragment>
      <Section title="Drinks">
        <LabeledList>
          <LabeledList.Item label="Glasses" color={noGlass ? 'bad' : null}>
            {glasses}
          </LabeledList.Item>
          <LabeledList.Item label="Portion">
            <NumberInput
              value={portion}
              unit="u"
              minValue={0}
              maxValue={50}
              width="60px"
              onChange={(e, value) => act('portion', { amount: value })} />
          </LabeledList.Item>
        </LabeledList>
        <Box mt={1}>
          <ReagentRows
            list={reagents}
            empty="The tank is empty."
            buttons={reagent => (
              <Fragment>
                <Button
                  icon="glass-whiskey"
                  disabled={noGlass}
                  content="Pour"
                  onClick={() => act('pour', { type: reagent.type })} />
                <Button
                  icon="blender"
                  content="Mix"
                  onClick={() => act('mix', { type: reagent.type })} />
                <Button
                  icon="trash"
                  tooltip="Purge"
                  onClick={() => act('disposeI', { type: reagent.type })} />
              </Fragment>
            )} />
        </Box>
      </Section>
      <Section title="Mixer">
        <ReagentRows
          list={mixer}
          empty="The mixer is empty."
          buttons={reagent => (
            <Fragment>
              <Button
                icon="glass-whiskey"
                disabled={noGlass}
                content="Pour"
                onClick={() => act('m_pour', { type: reagent.type })} />
              <Button
                icon="undo"
                content="Back"
                tooltip="Back into the tank"
                onClick={() => act('transfer', { type: reagent.type })} />
            </Fragment>
          )} />
      </Section>
      <Section title="Food">
        {food.length === 0 && (
          <Box color="label">No food stored.</Box>
        )}
        {food.map(item => (
          <Button
            key={item.name}
            icon="hamburger"
            content={item.name + ' (' + item.amount + ')'}
            onClick={() => act('dispense', { name: item.name })} />
        ))}
      </Section>
    </Fragment>
  );
};

export const IcecreamVat = props => {
  const { act, data } = useBackend(props);
  const { selected, products = [], reagents } = data;
  const productRow = product => (
    <Table.Row key={product.id}>
      <Table.Cell>
        <Box bold>{product.name}</Box>
        <Box color="label">{product.ingredients}</Box>
      </Table.Cell>
      <Table.Cell collapsing textAlign="right" pr={1}>
        {product.amount} left
      </Table.Cell>
      <Table.Cell collapsing>
        {product.cone && (
          <Button
            icon="ice-cream"
            disabled={product.amount < 1}
            content="Dispense"
            onClick={() => act('cone', { id: product.id })} />
        ) || (
          <Button
            icon={selected === product.id ? 'check' : 'ice-cream'}
            selected={selected === product.id}
            content={selected === product.id ? 'Scooping' : 'Scoop'}
            onClick={() => act('select', { id: product.id })} />
        )}
        <Button
          content="Make"
          onClick={() => act('make', { id: product.id, amount: 1 })} />
        <Button
          content="x5"
          onClick={() => act('make', { id: product.id, amount: 5 })} />
      </Table.Cell>
    </Table.Row>
  );
  return (
    <Fragment>
      <Section title="Ice cream">
        <Table>
          {products.filter(product => !product.cone).map(productRow)}
        </Table>
      </Section>
      <Section title="Cones">
        <Table>
          {products.filter(product => product.cone).map(productRow)}
        </Table>
      </Section>
      <Section title="Vat">
        <ReagentRows
          list={reagents}
          empty="The vat is empty."
          buttons={reagent => (
            <Button
              icon="trash"
              tooltip="Purge"
              onClick={() => act('disposeI', { type: reagent.type })} />
          )} />
      </Section>
    </Fragment>
  );
};
