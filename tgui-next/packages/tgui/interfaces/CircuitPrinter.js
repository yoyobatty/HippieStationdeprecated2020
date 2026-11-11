import { decodeHtmlEntities } from 'common/string';
import { Component, Fragment } from 'inferno';
import { act } from '../byond';
import { Box, Button, Icon, LabeledList, ProgressBar, Section } from '../components';

// hippie -- the integrated circuit printer as a shop grid (the user's ruling,
// 2026-11-07): categories down the side, a search across all of them, each
// part a tile with its picture and metal cost, the picked one's description
// and Print in a panel above. Programs are pasted into the window. Pictures
// come from the "circuits" sprite sheet in
// hippiestation/code/modules/integrated_electronics/core/circuits_tgui.dm.

const plain = text => decodeHtmlEntities(String(text || ''));

const Picture = props => (
  <div className={'CircuitPrinter__picture'
    + (props.big ? ' CircuitPrinter__picture--big' : '')}>
    {props.icon && (
      <span className={'circuits32x32 ' + props.icon} />
    ) || (
      <Icon name="microchip" size={1.5} color="label" />
    )}
  </div>
);

export class CircuitPrinter extends Component {
  constructor() {
    super();
    this.state = {
      category: null,
      search: '',
      picked: null,
      code: '',
    };
  }

  render() {
    const { config, data } = this.props.state;
    const { ref } = config;
    const {
      categories = [],
      metal,
      max_metal,
      debug,
      upgraded,
      cloning_allowed,
      fast_clone,
      cloning,
      idlock,
      program,
    } = data;
    const { search, picked, code } = this.state;
    const category = categories.find(cat => cat.name === this.state.category)
      || categories[0];
    const term = search.toLowerCase();
    const all = [];
    categories.forEach(cat => cat.items.forEach(item => all.push(item)));
    const items = term
      ? all.filter(item => (item.name + ' ' + item.desc).toLowerCase()
        .includes(term))
      : (category ? category.items : []);
    const pickedItem = picked && all.find(item => item.path === picked);
    const locked = item => !!item.research && !upgraded;
    const afford = item => debug || metal >= item.cost;
    return (
      <Fragment>
        <Section>
          <LabeledList>
            <LabeledList.Item label="Metal">
              {debug ? (
                <Box color="good">Unlimited (debug)</Box>
              ) : (
                <ProgressBar
                  value={metal / Math.max(1, max_metal)}
                  content={metal + ' / ' + max_metal} />
              )}
            </LabeledList.Item>
            <LabeledList.Item label="Designs">
              {upgraded ? 'Advanced' : 'Regular'}
            </LabeledList.Item>
            <LabeledList.Item label="ID lock"
              buttons={!!idlock && (
                <Button icon="unlock" content="Reset"
                  onClick={() => act(ref, 'id_lock')} />
              )}>
              {idlock ? plain(idlock) : 'None'}
            </LabeledList.Item>
          </LabeledList>
        </Section>
        {!!cloning_allowed && (
          <Section
            title={'Program' + (fast_clone ? ' (instant)' : '')}
            buttons={!!program && !cloning && (
              <Button icon="times" content="Unload"
                onClick={() => act(ref, 'unload')} />
            )}>
            {!program && (
              <Fragment>
                <textarea
                  className="CircuitPrinter__code"
                  rows={3}
                  placeholder="Paste a program here"
                  value={code}
                  onInput={e => this.setState({ code: e.target.value })} />
                <Button icon="upload" content="Load"
                  disabled={!code.trim()}
                  onClick={() => {
                    act(ref, 'load', { code });
                    this.setState({ code: '' });
                  }} />
              </Fragment>
            )}
            {!!program && (
              <Fragment>
                <LabeledList>
                  <LabeledList.Item label="Assembly">
                    {plain(program.name)}
                  </LabeledList.Item>
                  <LabeledList.Item label="Space">
                    {program.space} / {program.max_space}
                  </LabeledList.Item>
                  <LabeledList.Item label="Complexity">
                    {program.complexity} / {program.max_complexity}
                  </LabeledList.Item>
                  <LabeledList.Item label="Metal">
                    <Box inline
                      color={afford(program) ? null : 'bad'}>
                      {program.cost}
                    </Box>
                  </LabeledList.Item>
                </LabeledList>
                {!!program.needs_upgrade && !upgraded && (
                  <Box color="bad" mt={0.5}>
                    Needs upgrade disk.
                  </Box>
                )}
                {!!program.unsupported && (
                  <Box color="bad" mt={0.5}>
                    Parts the assembly type can&apos;t hold.
                  </Box>
                )}
                <Box mt={0.5}>
                  {cloning ? (
                    <Fragment>
                      <Box inline color="average" mr={1}>
                        <Icon name="cog" spin /> Printing
                      </Box>
                      <Button icon="ban" content="Cancel" color="bad"
                        onClick={() => act(ref, 'cancel')} />
                    </Fragment>
                  ) : (
                    <Button icon="print"
                      content={fast_clone ? 'Print' : 'Begin printing'}
                      disabled={!afford(program)
                        || (!!program.needs_upgrade && !upgraded)
                        || (!!program.unsupported && !debug)}
                      onClick={() => act(ref, 'print')} />
                  )}
                </Box>
              </Fragment>
            )}
          </Section>
        )}
        <Box mb={0.5}>
          <input
            className="CircuitPrinter__code"
            style={{ width: '220px' }}
            placeholder="Search..."
            value={search}
            onInput={e => this.setState({ search: e.target.value })} />
        </Box>
        <div className="CircuitPrinter__layout">
          <div className="CircuitPrinter__categories">
            {categories.map(cat => (
              <Button
                key={cat.name}
                fluid
                color="transparent"
                selected={!term && category && cat.name === category.name}
                onClick={() => this.setState({
                  category: cat.name,
                  search: '',
                })}>
                {cat.name}
                <Box inline color="label" ml={0.5}>{cat.items.length}</Box>
              </Button>
            ))}
          </div>
          <div className="CircuitPrinter__main">
            {!!pickedItem && (
              <div className="CircuitPrinter__panel">
                <Picture icon={pickedItem.icon} big />
                <div className="CircuitPrinter__panelText">
                  <Box bold fontSize="14px">{plain(pickedItem.name)}</Box>
                  <Box my={0.5}>{plain(pickedItem.desc)}</Box>
                  {locked(pickedItem) && (
                    <Box color="bad" mb={0.5}>
                      Needs upgrade disk.
                    </Box>
                  )}
                  <Button
                    icon="print"
                    content={'Print (' + pickedItem.cost + ' metal)'}
                    disabled={locked(pickedItem) || !afford(pickedItem)}
                    onClick={() => act(ref, 'build', {
                      path: pickedItem.path })} />
                  <Button icon="times" content="Close"
                    onClick={() => this.setState({ picked: null })} />
                </div>
              </div>
            )}
            <Section title={term
              ? items.length + ' found'
              : category && category.name}>
              {items.length === 0 && <Box color="label">Nothing.</Box>}
              <div className="CircuitPrinter__grid">
                {items.map(item => (
                  <div
                    key={item.path}
                    className={'CircuitPrinter__tile'
                      + (picked === item.path
                        ? ' CircuitPrinter__tile--picked'
                        : '')
                      + (locked(item) ? ' CircuitPrinter__tile--locked' : '')}
                    title={plain(item.desc)}
                    onClick={() => this.setState({
                      picked: picked === item.path ? null : item.path,
                    })}
                    onDblClick={() => !locked(item) && afford(item)
                      && act(ref, 'build', { path: item.path })}>
                    <Picture icon={item.icon} />
                    <div className="CircuitPrinter__tileName">
                      {plain(item.name)}
                    </div>
                    <div className="CircuitPrinter__cost">
                      {locked(item) ? (
                        <Fragment><Icon name="lock" /> Advanced</Fragment>
                      ) : item.cost + ' metal'}
                    </div>
                  </div>
                ))}
              </div>
            </Section>
          </div>
        </div>
      </Fragment>
    );
  }
}
