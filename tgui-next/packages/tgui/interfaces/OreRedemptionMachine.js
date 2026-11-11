import { toTitleCase } from 'common/string';
import { Component, Fragment } from 'inferno';
import { useBackend } from '../backend';
import { Box, Button, LabeledList, NumberInput, Section, Table } from '../components';

const RELEASE_AMOUNTS = [1, 10, 50];
const SMELT_AMOUNTS = [1, 10];

const alloyName = name => toTitleCase(name).replace('Alloy', '').trim();

// "0.5 Metal, 1 Glass": what one sheet of an alloy takes
const costText = cost => (cost || [])
  .map(part => part.sheets + ' ' + part.name)
  .join(', ');

const StorageStatus = props => {
  const { data } = props;
  if (data.storage === 'none') {
    return <Box color="bad">No storage</Box>;
  }
  if (data.storage === 'local') {
    return <Box color="average">Local</Box>;
  }
  return (
    <Fragment>
      <Box inline color={data.onHold ? 'bad' : 'good'}>
        {data.onHold ? 'Silo, on hold' : 'Silo'}
      </Box>
      <Box inline color="label" ml={1}>
        {data.siloArea}
        {data.sharedWith > 0 && (
          ', shared with ' + data.sharedWith
          + (data.sharedWith === 1 ? ' machine' : ' machines')
        )}
      </Box>
    </Fragment>
  );
};

export const OreRedemptionMachine = props => {
  const { act, data } = useBackend(props);
  const {
    unclaimedPoints,
    materials = [],
    alloys = [],
    diskDesigns = [],
    hasDisk,
    hasID,
    idName,
    claimedPoints,
    wornName,
    wornPoints,
    access,
  } = data;
  const canTake = access && data.storage !== 'none' && !data.onHold;
  const claimTo = hasID ? idName : wornName;
  return (
    <Fragment>
      <Section>
        <LabeledList>
          <LabeledList.Item label="Storage">
            <StorageStatus data={data} />
          </LabeledList.Item>
          <LabeledList.Item
            label="Points"
            buttons={(
              <Button
                icon="coins"
                content={claimTo ? 'Claim to ' + claimTo : 'Claim'}
                disabled={!unclaimedPoints || !claimTo}
                onClick={() => act('Claim')} />
            )}>
            <Box inline bold>{unclaimedPoints}</Box>
            <Box inline color="label" ml={1}>unclaimed</Box>
          </LabeledList.Item>
          <LabeledList.Item
            label="ID"
            buttons={hasID ? (
              <Button
                icon="eject"
                content="Eject"
                onClick={() => act('Eject')} />
            ) : (
              <Button
                icon="id-card"
                content="Insert"
                onClick={() => act('Insert')} />
            )}>
            {hasID && (
              <Fragment>
                {idName}
                <Box inline color="label" ml={1}>
                  {claimedPoints} pts
                </Box>
              </Fragment>
            ) || wornName && (
              <Fragment>
                {wornName}
                <Box inline color="label" ml={1}>
                  {wornPoints} pts, worn
                </Box>
              </Fragment>
            ) || (
              <Box color="label">None</Box>
            )}
          </LabeledList.Item>
        </LabeledList>
        <Box color="label" mt={1} fontSize="11px">
          Ore only. No gibtonite or slag.
          {data.sheetsPerOre !== 1 && (
            ' ' + data.sheetsPerOre + ' sheets per ore.'
          )}
        </Box>
      </Section>
      <Section
        title="Materials"
        buttons={!access && <Box color="bad">No access</Box>}>
        <Table>
          {materials.map(material => (
            <StockRow
              key={material.id}
              name={material.name}
              amount={material.amount}
              note={material.value
                ? material.value
                  + (material.value === 1 ? ' pt/ore' : ' pts/ore')
                : ''}
              quick={RELEASE_AMOUNTS}
              disabled={!canTake}
              onTake={amount => act('Release', {
                id: material.id,
                sheets: amount,
              })}
              onTakeAll={() => act('Release', {
                id: material.id,
                all: 1,
              })} />
          ))}
        </Table>
      </Section>
      <Section title="Alloys">
        <Table>
          {alloys.map(alloy => (
            <StockRow
              key={alloy.id}
              name={alloyName(alloy.name)}
              amount={alloy.amount}
              note={costText(alloy.cost)}
              quick={SMELT_AMOUNTS}
              disabled={!canTake}
              onTake={amount => act('Smelt', {
                id: alloy.id,
                sheets: amount,
              })}
              onTakeAll={() => act('Smelt', {
                id: alloy.id,
                all: 1,
              })} />
          ))}
        </Table>
      </Section>
      <Section
        title="Design disk"
        buttons={hasDisk ? (
          <Button
            icon="eject"
            content="Eject"
            onClick={() => act('diskEject')} />
        ) : (
          <Button
            icon="save"
            content="Insert"
            onClick={() => act('diskInsert')} />
        )}>
        {!hasDisk && <Box color="label">No disk</Box>}
        {hasDisk && diskDesigns.length === 0 && (
          <Box color="label">Blank</Box>
        )}
        <Table>
          {diskDesigns.map(design => (
            <Table.Row key={design.index}>
              <Table.Cell>
                {design.index}: {design.name}
              </Table.Cell>
              <Table.Cell collapsing>
                <Button
                  content="Upload"
                  disabled={!design.canupload}
                  onClick={() => act('diskUpload', {
                    design: design.index,
                  })} />
              </Table.Cell>
            </Table.Row>
          ))}
        </Table>
      </Section>
    </Fragment>
  );
};

// One material or alloy: what's there, a note, quick amounts, All, and a
// count of your own
class StockRow extends Component {
  constructor() {
    super();
    this.state = {
      amount: 1,
    };
  }

  render() {
    const {
      name,
      amount: stocked,
      note,
      quick,
      disabled,
      onTake,
      onTakeAll,
    } = this.props;
    const { amount } = this.state;
    const empty = stocked < 1;
    return (
      <Table.Row className="candystripe">
        <Table.Cell bold={!empty} color={empty ? 'label' : null}>
          {name}
        </Table.Cell>
        <Table.Cell
          collapsing
          textAlign="right"
          pr={1}
          color={empty ? 'label' : null}>
          {stocked}
        </Table.Cell>
        <Table.Cell color="label" fontSize="11px">
          {note}
        </Table.Cell>
        <Table.Cell collapsing>
          {quick.map(count => (
            <Button
              key={count}
              content={count}
              disabled={disabled || stocked < count}
              onClick={() => onTake(count)} />
          ))}
          <Button
            content="All"
            disabled={disabled || empty}
            onClick={() => onTakeAll()} />
          <NumberInput
            width="36px"
            ml={1}
            step={1}
            stepPixelSize={5}
            minValue={1}
            maxValue={Math.max(stocked, 1)}
            value={amount}
            onChange={(e, value) => this.setState({
              amount: value,
            })} />
          <Button
            content="Release"
            disabled={disabled || stocked < amount}
            onClick={() => onTake(amount)} />
        </Table.Cell>
      </Table.Row>
    );
  }
}
