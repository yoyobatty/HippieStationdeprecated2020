import { Component, Fragment } from 'inferno';
import { useBackend } from '../backend';
import { Box, Button, Icon, Input, NoticeBox, ProgressBar } from '../components';
import { SampleBoard } from './Experiments';

// The R&D console (hippiestation/code/modules/research/rdconsole_tgui.dm).
// Research as cards, one search over every node, what it says and the
// designs it unlocks, the way to any node from what's researched, and the
// linked protolathe, imprinter and analyzer as tabs. RdFabricator is the
// fabricator panel on its own, for a department lathe or techfab.

// Cards and design rows drawn at a time, more with "Load more"
const PAGE_SIZE = 40;

const TAB_RESEARCH = 'research';
const TAB_LATHE = 'lathe';
const TAB_IMPRINTER = 'imprinter';
const TAB_ANALYZER = 'analyzer';
const TAB_SAMPLES = 'samples';
const TAB_DISKS = 'disks';
const TAB_SETTINGS = 'settings';

const FILTER_AVAILABLE = 'available';
const FILTER_LOCKED = 'locked';
const FILTER_RESEARCHED = 'researched';

const STATUS_COLORS = {
  researched: '#5baa27',
  available: '#d9b804',
  locked: 'rgba(255, 255, 255, 0.15)',
  hidden: 'rgba(255, 255, 255, 0.15)',
};

// Where a design can be made, as icons
const BUILD_ICONS = [
  ['protolathe', 'flask', 'Protolathe'],
  ['imprinter', 'microchip', 'Circuit imprinter'],
  ['autolathe', 'cog', 'Autolathe'],
  ['mechfab', 'robot', 'Exosuit fabricator'],
  ['biogenerator', 'seedling', 'Biogenerator'],
  ['limbgrower', 'hand-paper', 'Limb grower'],
  ['smelter', 'fire', 'Smelter'],
];

const formatNumber = value => String(Math.round(value || 0))
  .replace(/\B(?=(\d{3})+(?!\d))/g, ',');

const toSet = list => {
  const set = {};
  for (let id of list || []) {
    set[id] = true;
  }
  return set;
};

// Lookups over the static data, built once for it
let lookupCache = null;
const getLookups = data => {
  if (lookupCache && lookupCache.nodes === data.nodes) {
    return lookupCache;
  }
  const byId = {};
  const nodesOfDesign = {};
  for (let node of data.nodes || []) {
    byId[node.id] = node;
    for (let designId of node.designs) {
      if (!nodesOfDesign[designId]) {
        nodesOfDesign[designId] = [];
      }
      nodesOfDesign[designId].push(node.id);
    }
  }
  lookupCache = {
    nodes: data.nodes,
    byId,
    nodesOfDesign,
  };
  return lookupCache;
};

// Where each node stands just now, what it costs, and what's been researched
const getResearch = data => {
  const lookups = getLookups(data);
  const researched = toSet(data.researched);
  const available = toSet(data.available);
  const hidden = toSet(data.hidden);
  const costs = data.costs || {};
  const designs = toSet(data.extra_designs);
  for (let id of data.researched || []) {
    const node = lookups.byId[id];
    if (node) {
      for (let designId of node.designs) {
        designs[designId] = true;
      }
    }
  }
  const statusOf = id => {
    if (researched[id]) {
      return 'researched';
    }
    if (available[id]) {
      return 'available';
    }
    if (hidden[id]) {
      return 'hidden';
    }
    return 'locked';
  };
  const costOf = id => {
    if (costs[id] !== undefined) {
      return costs[id];
    }
    const node = lookups.byId[id];
    return node ? node.cost : 0;
  };
  return {
    ...lookups,
    researched,
    available,
    hidden,
    researchedDesigns: designs,
    statusOf,
    costOf,
  };
};

// The nodes still to research on the way to `id`, prerequisites first
const getPath = (id, research) => {
  const order = [];
  const seen = {};
  const visit = nodeId => {
    if (seen[nodeId] || research.researched[nodeId]) {
      return;
    }
    seen[nodeId] = true;
    const node = research.byId[nodeId];
    if (!node) {
      return;
    }
    for (let prereq of node.prereqs) {
      visit(prereq);
    }
    order.push(nodeId);
  };
  visit(id);
  return order;
};

const pathCost = (path, research) => path
  .reduce((sum, id) => sum + research.costOf(id), 0);

// Costs the machine's parts don't change: sheets on the R&D machines, every
// stack on the autolathe
const isFlat = (design, fab) => (fab && fab.stacks_flat
  ? design.stack
  : design.flat);

// How many of a design the materials and chemicals in a fabricator make
const maxPrintable = (design, fab) => {
  if (!fab || fab.disabled) {
    return 0;
  }
  const have = {};
  for (let mat of fab.mats || []) {
    have[mat.id] = mat.amount;
  }
  for (let chem of fab.chems || []) {
    have[chem.id] = chem.volume;
  }
  const coeff = isFlat(design, fab) ? 1 : (fab.coeff || 1);
  let most = 50;
  for (let key of Object.keys(design.mats)) {
    const need = Math.max(1, design.mats[key] / coeff);
    most = Math.min(most, Math.floor((have[key] || 0) / need));
  }
  return most;
};

const buildsHere = (design, fab) => !!fab
  && (design.build & fab.buildtype) !== 0
  && (fab.dept === null || fab.dept === undefined
    || (design.dept & fab.dept) !== 0);

const DesignIcon = props => {
  const { design, size = 32 } = props;
  if (!design || !design.icon) {
    return (
      <Box
        inline
        width={size + 'px'}
        height={size + 'px'}
        textAlign="center"
        lineHeight={size + 'px'}
        style={{ 'vertical-align': 'middle' }}>
        <Icon name="cube" color="label" />
      </Box>
    );
  }
  const match = /(\d+)x(\d+)/.exec(design.icon);
  const native = match ? parseInt(match[1], 10) : 32;
  return (
    <Box
      inline
      position="relative"
      width={size + 'px'}
      height={size + 'px'}
      title={design.name}
      style={{ 'overflow': 'hidden', 'vertical-align': 'middle' }}>
      <Box
        className={design.icon}
        style={{
          'transform': 'scale(' + (size / native) + ')',
          'transform-origin': 'top left',
        }} />
    </Box>
  );
};

const Chip = props => {
  const { color, children } = props;
  return (
    <Box
      inline
      mr={0.5}
      style={{
        'padding': '0 4px',
        'border-radius': '2px',
        'border': '1px solid ' + (color || 'rgba(255, 255, 255, 0.2)'),
        'font-size': '11px',
        'white-space': 'nowrap',
      }}>
      {children}
    </Box>
  );
};

const StatusChip = props => {
  const { status, cost, affordable } = props;
  if (status === 'researched') {
    return (
      <Chip color={STATUS_COLORS.researched}>
        <Icon name="check" mr={0.5} />
        Researched
      </Chip>
    );
  }
  if (status === 'available') {
    return (
      <Chip color={affordable ? STATUS_COLORS.available : '#db2828'}>
        {formatNumber(cost) + ' pts'}
      </Chip>
    );
  }
  return (
    <Chip>
      <Icon name="lock" mr={0.5} />
      {formatNumber(cost) + ' pts'}
    </Chip>
  );
};

const NodeCard = props => {
  const { node, research, data, selected, onSelect, act } = props;
  const status = research.statusOf(node.id);
  const cost = research.costOf(node.id);
  const affordable = data.points >= cost;
  const path = status === 'locked' ? getPath(node.id, research) : null;
  const shown = node.designs.slice(0, 12);
  return (
    <Box
      mb={1}
      onClick={() => onSelect(node.id)}
      style={{
        'cursor': 'pointer',
        'padding': '6px 8px',
        'background-color': selected
          ? 'rgba(255, 255, 255, 0.12)'
          : 'rgba(0, 0, 0, 0.33)',
        'border-left': '3px solid ' + STATUS_COLORS[status],
      }}>
      <Box style={{ 'display': 'flex', 'align-items': 'center' }}>
        <Box bold fontSize="13px" style={{ 'flex-grow': 1 }}>
          {node.name}
        </Box>
        <StatusChip status={status} cost={cost} affordable={affordable} />
        {status === 'available' && !!data.research_control && (
          <Button
            ml={0.5}
            icon="flask"
            content="Research"
            disabled={!affordable}
            tooltip={affordable
              ? null
              : formatNumber(cost - data.points) + ' points short'}
            tooltipPosition="left"
            onClick={e => {
              e.stopPropagation();
              act('research', { id: node.id });
            }} />
        )}
      </Box>
      <Box
        color="label"
        fontSize="11px"
        style={{
          'white-space': 'nowrap',
          'overflow': 'hidden',
          'text-overflow': 'ellipsis',
        }}>
        {node.desc}
      </Box>
      {shown.length > 0 && (
        <Box mt={0.5}>
          {shown.map(designId => (
            <DesignIcon
              key={designId}
              design={data.designs[designId]}
              size={24} />
          ))}
          {node.designs.length > shown.length && (
            <Box inline color="label" ml={0.5}>
              {'+' + (node.designs.length - shown.length)}
            </Box>
          )}
        </Box>
      )}
      {!!path && path.length > 1 && (
        <Box color="label" fontSize="11px" mt={0.5}>
          <Icon name="route" mr={0.5} />
          {path.length + ' nodes to go, '
            + formatNumber(pathCost(path, research)) + ' pts in all'}
        </Box>
      )}
    </Box>
  );
};

const NodeLink = props => {
  const { id, research, onSelect } = props;
  const node = research.byId[id];
  const status = research.statusOf(id);
  if (!node || status === 'hidden') {
    return (
      <Box color="label" italic>
        <Icon name="eye-slash" mr={0.5} />
        A hidden technology
      </Box>
    );
  }
  return (
    <Box
      onClick={() => onSelect(id)}
      style={{
        'cursor': 'pointer',
        'padding': '1px 6px',
        'margin-bottom': '2px',
        'border-left': '3px solid ' + STATUS_COLORS[status],
        'background-color': 'rgba(0, 0, 0, 0.25)',
      }}>
      {node.name}
      <Box inline color="label" ml={1} fontSize="11px">
        {status === 'researched'
          ? 'researched'
          : formatNumber(research.costOf(id)) + ' pts'}
      </Box>
    </Box>
  );
};

const PrintButtons = props => {
  const { design, fab, onPrint, compact } = props;
  if (!fab) {
    return null;
  }
  const most = maxPrintable(design, fab);
  const verb = fab.busy || (fab.queue && fab.queue.length) ? 'Queue' : 'Print';
  // Stacks come by the handful: rods, glass, cable
  let amounts = [1, 5, 10];
  if (compact) {
    amounts = [1];
  } else if (design.stack) {
    amounts = [1, 10, 25, 50];
  }
  return (
    <Box inline style={{ 'white-space': 'nowrap' }}>
      {amounts.map(amount => (
        <Button
          key={amount}
          icon={amount === 1 ? (verb === 'Queue' ? 'list' : 'print') : null}
          content={amount === 1 ? verb : 'x' + amount}
          disabled={most < amount}
          tooltip={most < amount ? 'Not enough materials' : null}
          tooltipPosition="left"
          onClick={e => {
            e.stopPropagation();
            onPrint(design.id, amount);
          }} />
      ))}
    </Box>
  );
};

const MaterialCosts = props => {
  const { design, fab, matNames } = props;
  const have = {};
  if (fab) {
    for (let mat of fab.mats || []) {
      have[mat.id] = mat.amount;
    }
    for (let chem of fab.chems || []) {
      have[chem.id] = chem.volume;
    }
  }
  const coeff = !fab || isFlat(design, fab) ? 1 : (fab.coeff || 1);
  return (
    <Box color="label" fontSize="11px">
      {Object.keys(design.mats).map(key => {
        const need = Math.round(design.mats[key] / coeff);
        const short = !!fab && (have[key] || 0) < need;
        return (
          <Box key={key} inline mr={1} color={short ? 'bad' : null}>
            {formatNumber(need) + ' ' + (matNames[key] || key)}
          </Box>
        );
      })}
    </Box>
  );
};

// A design as a row: where it's made, what it costs, and the print buttons
// for whichever linked machine makes it
const DesignRow = props => {
  const {
    design,
    data,
    research,
    fab,
    onPrint,
    onSelectNode,
    showNodes,
  } = props;
  const researched = research.researchedDesigns[design.id];
  const fromNodes = research.nodesOfDesign[design.id] || [];
  return (
    <Box
      className="candystripe"
      style={{
        'display': 'flex',
        'align-items': 'center',
        'padding': '3px 6px',
      }}>
      <DesignIcon design={design} size={32} />
      <Box ml={1} style={{ 'flex-grow': 1, 'min-width': 0 }}>
        <Box bold color={researched ? null : 'label'}>
          {design.name}
          {BUILD_ICONS
            .filter(entry => design.build & data.build_types[entry[0]])
            .map(entry => (
              <Box key={entry[0]} inline ml={0.5} color="label"
                title={entry[2]}>
                <Icon name={entry[1]} />
              </Box>
            ))}
        </Box>
        <MaterialCosts design={design} fab={fab} matNames={data.mat_names} />
        {!!showNodes && !researched && fromNodes.length > 0 && (
          <Box fontSize="11px">
            {'From: '}
            {fromNodes.map(id => (
              <Box
                key={id}
                inline
                mr={1}
                color="average"
                style={{ 'cursor': 'pointer' }}
                onClick={() => onSelectNode(id)}>
                {research.statusOf(id) === 'hidden'
                  ? 'a hidden technology'
                  : research.byId[id].name}
              </Box>
            ))}
          </Box>
        )}
      </Box>
      {!!researched && !!fab && (
        <PrintButtons design={design} fab={fab} onPrint={onPrint} />
      )}
    </Box>
  );
};

const NodeDetails = props => {
  const { node, research, data, act, onSelect, printer } = props;
  if (!node) {
    return (
      <NoticeBox>
        Pick a node to see what it needs, what it unlocks and the way there.
      </NoticeBox>
    );
  }
  const status = research.statusOf(node.id);
  const cost = research.costOf(node.id);
  const path = status === 'researched' ? [] : getPath(node.id, research);
  const total = pathCost(path, research);
  const next = path.find(id => research.available[id]);
  const boosted = cost < node.cost;
  return (
    <Box>
      <Box bold fontSize="16px">
        {node.name}
      </Box>
      <Box color="label" italic mb={1}>
        {node.desc}
      </Box>
      <Box mb={1}>
        <StatusChip
          status={status}
          cost={cost}
          affordable={data.points >= cost} />
        {boosted && (
          <Chip color="#2185d0">
            {'Boosted from ' + formatNumber(node.cost)}
          </Chip>
        )}
      </Box>
      {status === 'available' && !!data.research_control && (
        <Button
          icon="flask"
          content={'Research for ' + formatNumber(cost) + ' points'}
          disabled={data.points < cost}
          onClick={() => act('research', { id: node.id })} />
      )}
      {path.length > 1 && (
        <Box
          mt={1}
          mb={1}
          style={{
            'padding': '6px',
            'background-color': 'rgba(0, 0, 0, 0.33)',
          }}>
          <Box bold mb={0.5}>
            <Icon name="route" mr={0.5} />
            {'The way there: ' + path.length + ' nodes, '
              + formatNumber(total) + ' points'}
          </Box>
          {path.map(id => (
            <NodeLink
              key={id}
              id={id}
              research={research}
              onSelect={onSelect} />
          ))}
          {!!next && !!data.research_control && (
            <Button
              mt={0.5}
              icon="forward"
              content={'Research next: ' + research.byId[next].name}
              disabled={data.points < research.costOf(next)}
              tooltip={data.points < research.costOf(next)
                ? formatNumber(research.costOf(next) - data.points)
                  + ' points short'
                : null}
              onClick={() => act('research', { id: next })} />
          )}
          {!next && (
            <Box color="label" italic>
              A hidden technology stands in the way: something has to go
              through the destructive analyzer first.
            </Box>
          )}
        </Box>
      )}
      {node.prereqs.length > 0 && (
        <Box mt={1}>
          <Box color="label" bold mb={0.5}>Needs</Box>
          {node.prereqs.map(id => (
            <NodeLink
              key={id}
              id={id}
              research={research}
              onSelect={onSelect} />
          ))}
        </Box>
      )}
      {node.unlocks.length > 0 && (
        <Box mt={1}>
          <Box color="label" bold mb={0.5}>Leads to</Box>
          {node.unlocks.map(id => (
            <NodeLink
              key={id}
              id={id}
              research={research}
              onSelect={onSelect} />
          ))}
        </Box>
      )}
      {node.designs.length > 0 && (
        <Box mt={1}>
          <Box color="label" bold mb={0.5}>
            {'Designs (' + node.designs.length + ')'}
          </Box>
          {node.designs
            .filter(id => data.designs[id])
            .map(id => (
              <DesignRow
                key={id}
                design={{ ...data.designs[id], id }}
                data={data}
                research={research}
                fab={printer(data.designs[id])}
                onPrint={(designId, amount) => act('print', {
                  machine: printer.key(data.designs[id]),
                  id: designId,
                  amount,
                })}
                onSelectNode={onSelect} />
            ))}
        </Box>
      )}
    </Box>
  );
};

// Materials, chemicals and the queue: the left side of a fabricator
const FabricatorStores = props => {
  const { fab, act, sheet } = props;
  return (
    <Fragment>
      {!!fab.disabled && (
        <NoticeBox>
          The controls aren&apos;t responding: a wire inside is cut.
        </NoticeBox>
      )}
      <Box bold mb={0.5}>
        <Icon name="cubes" mr={0.5} />
        Materials
        {!!fab.silo && (
          <Box inline color="label" ml={1} fontSize="11px">
            from the ore silo
          </Box>
        )}
      </Box>
      {!!fab.on_hold && (
        <NoticeBox>
          The quartermaster has the silo on hold.
        </NoticeBox>
      )}
      {!!fab.storage && (
        <ProgressBar
          mb={0.5}
          value={fab.storage.total}
          maxValue={fab.storage.max || 1}
          content={formatNumber(fab.storage.total / sheet) + ' / '
            + formatNumber(fab.storage.max / sheet) + ' sheets'} />
      )}
      {(fab.mats || []).filter(mat => mat.amount > 0).map(mat => (
        <Box
          key={mat.id}
          style={{
            'display': 'flex',
            'align-items': 'center',
            'margin-bottom': '2px',
          }}>
          <Box style={{ 'flex-grow': 1 }}>
            {mat.name}
            <Box inline color="label" ml={0.5}>
              {(Math.floor(mat.amount / sheet * 10) / 10) + ''}
            </Box>
          </Box>
          <Button
            icon="eject"
            content="1"
            disabled={mat.amount < sheet}
            onClick={() => act('eject_sheets', { mat: mat.id, amount: 1 })} />
          <Button
            content="All"
            disabled={mat.amount < sheet}
            onClick={() => act('eject_sheets', {
              mat: mat.id,
              amount: 50,
            })} />
        </Box>
      ))}
      {!fab.no_chems && (
        <Box bold mt={1} mb={0.5}>
          <Icon name="flask" mr={0.5} />
          {'Chemicals ' + fab.chem_volume + ' / ' + fab.chem_max}
        </Box>
      )}
      {(fab.chems || []).map(chem => (
        <Box key={chem.id} style={{ 'display': 'flex' }}>
          <Box style={{ 'flex-grow': 1 }}>
            {chem.name + ' ' + chem.volume + 'u'}
          </Box>
          <Button
            icon="trash"
            onClick={() => act('purge', { chem: chem.id })} />
        </Box>
      ))}
      {(fab.chems || []).length > 0 && (
        <Button
          fluid
          icon="trash"
          content="Purge all"
          onClick={() => act('purge_all')} />
      )}
      <Box bold mt={1} mb={0.5}>
        <Icon name="list" mr={0.5} />
        {'Queue (' + (fab.queue || []).length + ')'}
        {!!fab.busy && (
          <Box inline ml={1} color="average">
            <Icon name="cog" spin />
            {' printing'}
          </Box>
        )}
      </Box>
      {(fab.queue || []).length === 0 && (
        <Box color="label" italic>
          Nothing waiting.
        </Box>
      )}
      {(fab.queue || []).map((entry, index) => (
        <Box
          key={index}
          style={{ 'display': 'flex', 'align-items': 'center' }}>
          <Box style={{ 'flex-grow': 1 }}>
            {(index + 1) + '. ' + entry.name}
            {entry.amount > 1 && (
              <Box inline color="label" ml={0.5}>
                {'x' + entry.amount}
              </Box>
            )}
          </Box>
          <Button
            icon="times"
            onClick={() => act('queue_remove', { index: index + 1 })} />
        </Box>
      ))}
      {(fab.queue || []).length > 1 && (
        <Button
          fluid
          icon="times"
          content="Clear the queue"
          onClick={() => act('queue_clear')} />
      )}
    </Fragment>
  );
};

class FabricatorPanel extends Component {
  constructor() {
    super();
    this.state = {
      category: null,
      pages: 1,
    };
  }

  render() {
    const { fab, data, research, act, search, onSelectNode } = this.props;
    const { category, pages } = this.state;
    if (!fab) {
      return (
        <NoticeBox>
          Nothing linked. Settings has the button to look for machines nearby.
        </NoticeBox>
      );
    }
    const designs = Object.keys(data.designs)
      .filter(id => research.researchedDesigns[id])
      .map(id => ({ ...data.designs[id], id }))
      .filter(design => buildsHere(design, fab));
    // Its own categories only: designs carry the autolathe's as well
    const own = toSet(fab.categories);
    const hasOwn = (fab.categories || []).length > 0;
    const counts = {};
    for (let design of designs) {
      for (let cat of design.cats || []) {
        if (!hasOwn || own[cat]) {
          counts[cat] = (counts[cat] || 0) + 1;
        }
      }
    }
    const categories = Object.keys(counts).sort();
    const query = search.toLowerCase();
    // A search goes by the design's name, or a category ("stock parts")
    const matches = design => design.name.toLowerCase().includes(query)
      || (design.cats || []).some(cat => (!hasOwn || own[cat])
        && cat.toLowerCase().includes(query));
    const shown = designs
      .filter(design => (query
        ? matches(design)
        : !category || (design.cats || []).includes(category)))
      .sort((a, b) => a.name.localeCompare(b.name));
    const limit = pages * PAGE_SIZE;
    const select = changes => {
      const content = document.getElementById('RdConsole__fabricator');
      if (content) {
        content.scrollTop = 0;
      }
      this.setState({ pages: 1, ...changes });
    };
    return (
      <Box
        style={{
          'position': 'absolute',
          'top': 0,
          'bottom': 0,
          'left': 0,
          'right': 0,
        }}>
        <Box
          style={{
            'position': 'absolute',
            'top': 0,
            'bottom': 0,
            'left': 0,
            'width': '250px',
            'padding': '6px',
            'box-sizing': 'border-box',
            'overflow-y': 'auto',
            'background-color': 'rgba(0, 0, 0, 0.33)',
          }}>
          <FabricatorStores fab={fab} act={act} sheet={fab.sheet || 2000} />
        </Box>
        <Box
          id="RdConsole__fabricator"
          style={{
            'position': 'absolute',
            'top': 0,
            'bottom': 0,
            'left': '250px',
            'right': 0,
            'padding': '6px',
            'overflow-y': 'auto',
          }}>
          {!query && (
            <Box mb={1}>
              <Button
                content={'All (' + designs.length + ')'}
                selected={!category}
                onClick={() => select({ category: null })} />
              {categories.map(cat => (
                <Button
                  key={cat}
                  content={cat + ' (' + counts[cat] + ')'}
                  selected={category === cat}
                  onClick={() => select({ category: cat })} />
              ))}
            </Box>
          )}
          {shown.length === 0 && (
            <NoticeBox>
              {query
                ? 'No designs it can make match that.'
                : 'No designs here yet: research unlocks them.'}
            </NoticeBox>
          )}
          {shown.slice(0, limit).map(design => (
            <DesignRow
              key={design.id}
              design={design}
              data={data}
              research={research}
              fab={fab}
              onPrint={(id, amount) => act('print', { id, amount })}
              onSelectNode={onSelectNode} />
          ))}
          {shown.length > limit && (
            <Button
              fluid
              textAlign="center"
              content={'Load more (' + (shown.length - limit) + ' left)'}
              onClick={() => this.setState({ pages: pages + 1 })} />
          )}
        </Box>
      </Box>
    );
  }
}

const AnalyzerPanel = props => {
  const { analyzer, act, onSelectNode } = props;
  if (!analyzer) {
    return (
      <NoticeBox>
        No destructive analyzer linked.
      </NoticeBox>
    );
  }
  if (!analyzer.item) {
    return (
      <NoticeBox>
        The analyzer is empty. Put something in it to see what destroying it
        would do for the research.
      </NoticeBox>
    );
  }
  const STATE_TEXT = {
    researched: 'already researched',
    revealed: 'already revealed',
    boosted: 'already boosted',
    reveal: 'reveals it',
    boost: 'takes points off it',
  };
  return (
    <Box>
      <Box bold fontSize="16px" mb={1}>
        <Icon name="atom" mr={1} />
        {analyzer.item}
        <Button
          ml={1}
          icon="eject"
          content="Eject"
          disabled={analyzer.busy}
          onClick={() => act('eject_item')} />
      </Box>
      {!!analyzer.sample && (
        <Box
          mb={1}
          style={{
            'display': 'flex',
            'align-items': 'center',
            'padding': '6px 8px',
            'background-color': 'rgba(91, 170, 39, 0.12)',
            'border-left': '3px solid #5baa27',
          }}>
          <Box style={{ 'flex-grow': 1 }}>
            <Box color="label" fontSize="11px">Sample board</Box>
            <Box bold>{analyzer.sample.name}</Box>
            {analyzer.sample.needed > 1 && (
              <Box color="label" fontSize="11px">
                {analyzer.sample.got} / {analyzer.sample.needed}
                {analyzer.sample.unit}, this gives {analyzer.sample.gives}
              </Box>
            )}
          </Box>
          <Button
            icon="vial"
            color="good"
            content={'Hand in (' + formatNumber(analyzer.sample.reward)
              + ' pts)'}
            disabled={analyzer.busy}
            onClick={() => act('hand_in')} />
        </Box>
      )}
      {(analyzer.options || []).length === 0 && (
        <Box color="label" italic mb={1}>
          Nothing in the research would be any the wiser for it.
        </Box>
      )}
      {(analyzer.options || []).map(option => (
        <Box
          key={option.id}
          mb={0.5}
          style={{
            'display': 'flex',
            'align-items': 'center',
            'padding': '4px 6px',
            'background-color': 'rgba(0, 0, 0, 0.33)',
          }}>
          <Box style={{ 'flex-grow': 1 }}>
            <Box
              inline
              bold
              style={{ 'cursor': 'pointer' }}
              onClick={() => onSelectNode(option.id)}>
              {option.name}
            </Box>
            <Box inline color="label" ml={1}>
              {STATE_TEXT[option.state] + (option.amount
                ? ', ' + formatNumber(option.amount) + ' points'
                : '')}
            </Box>
          </Box>
          <Button
            icon="radiation"
            content="Destroy for this"
            disabled={analyzer.busy
              || (option.state !== 'reveal' && option.state !== 'boost')}
            onClick={() => act('decon', { id: option.id })} />
        </Box>
      ))}
      <Box mt={1}>
        {analyzer.points > 0 && (
          <Button
            icon="coins"
            content={analyzer.points_claimed
              ? 'Its points have been claimed already'
              : 'Destroy for ' + formatNumber(analyzer.points) + ' points'}
            disabled={analyzer.busy || analyzer.points_claimed}
            onClick={() => act('decon', { id: 'reclaim' })} />
        )}
        {!analyzer.indestructible && (
          <Button
            icon="recycle"
            content={analyzer.materials
              ? 'Reclaim the materials'
              : 'Destroy it'}
            disabled={analyzer.busy}
            onClick={() => act('decon', { id: 'reclaim' })} />
        )}
      </Box>
    </Box>
  );
};

const DisksPanel = props => {
  const { data, research, act, search, onSelectNode } = props;
  const { tdisk, ddisk } = data;
  if (!tdisk && !ddisk) {
    return (
      <NoticeBox>
        No disk in the console. A technology or design disk goes in its slot.
      </NoticeBox>
    );
  }
  const query = search.toLowerCase();
  const picks = query
    ? Object.keys(research.researchedDesigns)
      .filter(id => data.designs[id]
        && data.designs[id].name.toLowerCase().includes(query))
      .slice(0, 30)
    : [];
  return (
    <Box>
      {!!tdisk && (
        <Box mb={2}>
          <Box bold fontSize="14px" mb={0.5}>
            <Icon name="save" mr={0.5} />
            {'Technology disk: ' + tdisk.nodes.length + ' nodes'}
          </Box>
          <Box mb={0.5}>
            <Button
              icon="upload"
              content="Onto the network"
              onClick={() => act('tdisk_upload')} />
            <Button
              icon="download"
              content="From the network"
              onClick={() => act('tdisk_download')} />
            <Button
              icon="trash"
              content="Wipe"
              onClick={() => act('tdisk_clear')} />
            <Button
              icon="eject"
              content="Eject"
              onClick={() => act('tdisk_eject')} />
          </Box>
          {tdisk.nodes.map(id => (
            <NodeLink
              key={id}
              id={id}
              research={research}
              onSelect={onSelectNode} />
          ))}
        </Box>
      )}
      {!!ddisk && (
        <Box>
          <Box bold fontSize="14px" mb={0.5}>
            <Icon name="save" mr={0.5} />
            Design disk
            <Button
              ml={1}
              icon="upload"
              content="Upload all"
              onClick={() => act('ddisk_upload', { slot: 0 })} />
            <Button
              icon="trash"
              content="Wipe"
              onClick={() => act('ddisk_clear', { slot: 0 })} />
            <Button
              icon="eject"
              content="Eject"
              onClick={() => act('ddisk_eject')} />
          </Box>
          {ddisk.slots.map((id, index) => (
            <Box
              key={index}
              mb={0.5}
              style={{
                'display': 'flex',
                'align-items': 'center',
                'padding': '3px 6px',
                'background-color': 'rgba(0, 0, 0, 0.33)',
              }}>
              <Box style={{ 'flex-grow': 1 }}>
                {'Slot ' + (index + 1) + ': '}
                {id && data.designs[id]
                  ? data.designs[id].name
                  : (
                    <Box inline color="label" italic>
                      empty
                    </Box>
                  )}
              </Box>
              {!!id && (
                <Fragment>
                  <Button
                    icon="upload"
                    content="Upload"
                    onClick={() => act('ddisk_upload', { slot: index + 1 })} />
                  <Button
                    icon="trash"
                    onClick={() => act('ddisk_clear', { slot: index + 1 })} />
                </Fragment>
              )}
            </Box>
          ))}
          <Box mt={1} color="label">
            Search a researched design to copy it onto an empty slot.
          </Box>
          {picks.map(designId => (
            <Box
              key={designId}
              style={{ 'display': 'flex', 'align-items': 'center' }}>
              <DesignIcon design={data.designs[designId]} size={24} />
              <Box ml={1} style={{ 'flex-grow': 1 }}>
                {data.designs[designId].name}
              </Box>
              {ddisk.slots.map((id, index) => !id && (
                <Button
                  key={index}
                  content={'To slot ' + (index + 1)}
                  onClick={() => act('ddisk_copy', {
                    slot: index + 1,
                    id: designId,
                  })} />
              ))}
            </Box>
          ))}
        </Box>
      )}
    </Box>
  );
};

const SettingsPanel = props => {
  const { data, act } = props;
  const machines = [
    ['lathe', 'Protolathe', data.lathe],
    ['imprinter', 'Circuit imprinter', data.imprinter],
    ['analyzer', 'Destructive analyzer', data.analyzer],
  ];
  return (
    <Box>
      <Box bold fontSize="14px" mb={0.5}>Linked machines</Box>
      {machines.map(entry => (
        <Box key={entry[0]} mb={0.5}>
          <Icon
            name={entry[2] ? 'link' : 'unlink'}
            color={entry[2] ? 'good' : 'label'}
            mr={1} />
          {entry[1]}
          {entry[2]
            ? (
              <Button
                ml={1}
                content="Disconnect"
                onClick={() => act('disconnect', { machine: entry[0] })} />
            )
            : (
              <Box inline color="label" ml={1}>
                not linked
              </Box>
            )}
        </Box>
      ))}
      <Button
        icon="sync"
        content="Look for machines within three tiles"
        onClick={() => act('resync')} />
      <Box bold fontSize="14px" mt={2} mb={0.5}>Security</Box>
      <Box mb={0.5}>
        {'Security protocols: '}
        <Box inline color={data.emagged ? 'bad' : 'good'}>
          {data.emagged ? 'Disabled' : 'Enabled'}
        </Box>
      </Box>
      <Button
        icon="lock"
        content="Lock the console"
        disabled={data.emagged}
        onClick={() => act('lock')} />
    </Box>
  );
};

const TabButton = props => {
  const { icon, label, selected, onClick } = props;
  return (
    <Button
      icon={icon}
      content={label}
      selected={selected}
      onClick={onClick} />
  );
};

class RdConsoleMenu extends Component {
  constructor() {
    super();
    this.state = {
      tab: TAB_RESEARCH,
      filter: FILTER_AVAILABLE,
      selected: null,
      search: '',
      pages: 1,
    };
  }

  setTab(tab) {
    this.setState({ tab, pages: 1 });
  }

  selectNode(id) {
    this.setState({ tab: TAB_RESEARCH, selected: id });
  }

  setFilter(filter) {
    const list = document.getElementById('RdConsole__list');
    if (list) {
      list.scrollTop = 0;
    }
    this.setState({ filter, pages: 1 });
  }

  render() {
    const { act, data } = this.props;
    const { tab, filter, selected, search, pages } = this.state;
    const research = getResearch(data);
    const onSelect = id => this.selectNode(id);
    // The linked machine a design is made on: the protolathe first
    const printer = design => {
      if (buildsHere(design, data.lathe)) {
        return data.lathe;
      }
      if (buildsHere(design, data.imprinter)) {
        return data.imprinter;
      }
      return null;
    };
    printer.key = design => (buildsHere(design, data.lathe)
      ? 'lathe'
      : 'imprinter');
    const actFor = machine => (action, params) => act(action, {
      ...params,
      machine,
    });
    const tabs = [
      [TAB_RESEARCH, 'flask', 'Research', true],
      [TAB_LATHE, 'cubes', 'Protolathe', !!data.lathe],
      [TAB_IMPRINTER, 'microchip', 'Imprinter', !!data.imprinter],
      [TAB_ANALYZER, 'atom', 'Analyzer', !!data.analyzer],
      [TAB_SAMPLES, 'vial', 'Samples', !!data.samples],
      [TAB_DISKS, 'save', 'Disks', !!data.tdisk || !!data.ddisk],
      [TAB_SETTINGS, 'cog', 'Settings', true],
    ];
    const placeholder = {
      [TAB_RESEARCH]: 'Search nodes, what they say and their designs...',
      [TAB_LATHE]: 'Search what the protolathe makes...',
      [TAB_IMPRINTER]: 'Search what the imprinter makes...',
      [TAB_DISKS]: 'Search researched designs to copy to the disk...',
    }[tab];
    return (
      <Box
        style={{
          'position': 'absolute',
          'top': 0,
          'bottom': 0,
          'left': 0,
          'right': 0,
        }}>
        {!!data.locked && (
          <Box
            style={{
              'position': 'absolute',
              'top': 0,
              'bottom': 0,
              'left': 0,
              'right': 0,
              'z-index': 10,
              'background-color': 'rgba(0, 0, 0, 0.85)',
              'text-align': 'center',
              'padding-top': '200px',
            }}>
            <Box fontSize="24px" mb={2}>
              <Icon name="lock" mr={1} />
              Console locked
            </Box>
            <Button
              icon="unlock"
              content="Unlock"
              onClick={() => act('unlock')} />
          </Box>
        )}
        <Box
          style={{
            'position': 'absolute',
            'top': 0,
            'left': 0,
            'right': 0,
            'height': '78px',
            'padding': '6px 8px',
            'box-sizing': 'border-box',
            'background-color': 'rgba(0, 0, 0, 0.33)',
          }}>
          <Box style={{ 'display': 'flex', 'align-items': 'center' }}>
            <Box style={{ 'flex-grow': 1 }}>
              <Box bold fontSize="14px">
                {data.org + ' Research Network'}
              </Box>
              {!!data.emagged && (
                <Box color="bad" fontSize="11px">
                  Security protocols disabled
                </Box>
              )}
            </Box>
            <Box textAlign="right" mr={1}>
              <Box fontSize="18px" bold color="good">
                <Icon name="flask" mr={0.5} />
                {formatNumber(data.points)}
              </Box>
              <Box color="label" fontSize="11px">
                {'General Research, +' + formatNumber(data.per_minute)
                  + ' a minute'}
              </Box>
            </Box>
          </Box>
          <Box mt={0.5} style={{ 'display': 'flex' }}>
            <Box style={{ 'flex-grow': 1 }} mr={1}>
              {!!placeholder && (
                <Input
                  fluid
                  value={search}
                  placeholder={placeholder}
                  onInput={(e, value) => this.setState({
                    search: value,
                    pages: 1,
                  })} />
              )}
            </Box>
            {tabs.filter(entry => entry[3]).map(entry => (
              <TabButton
                key={entry[0]}
                icon={entry[1]}
                label={entry[2]}
                selected={tab === entry[0]}
                onClick={() => this.setTab(entry[0])} />
            ))}
          </Box>
        </Box>
        <Box
          style={{
            'position': 'absolute',
            'top': '78px',
            'bottom': 0,
            'left': 0,
            'right': 0,
          }}>
          {tab === TAB_RESEARCH && this.renderResearch(research, {
            act,
            data,
            filter,
            selected,
            search,
            pages,
            onSelect,
            printer,
          })}
          {tab === TAB_LATHE && (
            <FabricatorPanel
              fab={data.lathe}
              data={data}
              research={research}
              act={actFor('lathe')}
              search={search}
              onSelectNode={onSelect} />
          )}
          {tab === TAB_IMPRINTER && (
            <FabricatorPanel
              fab={data.imprinter}
              data={data}
              research={research}
              act={actFor('imprinter')}
              search={search}
              onSelectNode={onSelect} />
          )}
          {tab === TAB_ANALYZER && (
            <Box p={1}>
              <AnalyzerPanel
                analyzer={data.analyzer}
                act={act}
                onSelectNode={onSelect} />
            </Box>
          )}
          {tab === TAB_SAMPLES && (
            <Box
              style={{
                'overflow-y': 'auto',
                'height': '100%',
                'padding': '6px 8px',
              }}>
              <SampleBoard board={data.samples} />
            </Box>
          )}
          {tab === TAB_DISKS && (
            <Box p={1} style={{ 'overflow-y': 'auto', 'height': '100%' }}>
              <DisksPanel
                data={data}
                research={research}
                act={act}
                search={search}
                onSelectNode={onSelect} />
            </Box>
          )}
          {tab === TAB_SETTINGS && (
            <Box p={1}>
              <SettingsPanel data={data} act={act} />
            </Box>
          )}
        </Box>
      </Box>
    );
  }

  renderResearch(research, props) {
    const {
      act,
      data,
      filter,
      selected,
      search,
      pages,
      onSelect,
      printer,
    } = props;
    const query = search.toLowerCase();
    const visible = (data.nodes || [])
      .filter(node => research.statusOf(node.id) !== 'hidden');
    const counts = {
      [FILTER_AVAILABLE]: 0,
      [FILTER_LOCKED]: 0,
      [FILTER_RESEARCHED]: 0,
    };
    for (let node of visible) {
      counts[research.statusOf(node.id)] += 1;
    }
    const matchesNode = node => {
      if (node.name.toLowerCase().includes(query)
        || node.desc.toLowerCase().includes(query)) {
        return true;
      }
      return node.designs.some(id => data.designs[id]
        && data.designs[id].name.toLowerCase().includes(query));
    };
    // Searching looks through every node, whatever the filter: what can be
    // researched now first, then what's nearest, then what's done
    const statusOrder = { available: 0, locked: 1, researched: 2 };
    const nodes = visible
      .filter(node => (query
        ? matchesNode(node)
        : research.statusOf(node.id) === filter))
      .map(node => ({
        node,
        status: research.statusOf(node.id),
        steps: research.statusOf(node.id) === 'locked'
          ? getPath(node.id, research).length
          : 0,
      }))
      .sort((a, b) => (statusOrder[a.status] - statusOrder[b.status])
        || (a.steps - b.steps)
        || (research.costOf(a.node.id) - research.costOf(b.node.id))
        || a.node.name.localeCompare(b.node.name))
      .map(entry => entry.node);
    const designs = query
      ? Object.keys(data.designs)
        .filter(id => data.designs[id].name.toLowerCase().includes(query)
          && (research.researchedDesigns[id]
            || (research.nodesOfDesign[id] || []).some(nodeId => research
              .statusOf(nodeId) !== 'hidden')))
        .map(id => ({ ...data.designs[id], id }))
        .sort((a, b) => ((research.researchedDesigns[b.id] ? 1 : 0)
          - (research.researchedDesigns[a.id] ? 1 : 0))
          || a.name.localeCompare(b.name))
      : [];
    const limit = pages * PAGE_SIZE;
    return (
      <Fragment>
        <Box
          id="RdConsole__list"
          style={{
            'position': 'absolute',
            'top': 0,
            'bottom': 0,
            'left': 0,
            'width': '52%',
            'padding': '6px',
            'box-sizing': 'border-box',
            'overflow-y': 'auto',
          }}>
          {!query && (
            <Box mb={1}>
              {[
                [FILTER_AVAILABLE, 'flask', 'Available'],
                [FILTER_LOCKED, 'lock', 'Locked'],
                [FILTER_RESEARCHED, 'check', 'Researched'],
              ].map(entry => (
                <Button
                  key={entry[0]}
                  icon={entry[1]}
                  content={entry[2] + ' (' + counts[entry[0]] + ')'}
                  selected={filter === entry[0]}
                  onClick={() => this.setFilter(entry[0])} />
              ))}
            </Box>
          )}
          {!!query && (
            <Box bold mb={0.5} color="label">
              {'Nodes (' + nodes.length + ')'}
            </Box>
          )}
          {nodes.length === 0 && !query && (
            <NoticeBox>
              {filter === FILTER_AVAILABLE
                ? 'Nothing to research just now.'
                : 'None.'}
            </NoticeBox>
          )}
          {nodes.slice(0, limit).map(node => (
            <NodeCard
              key={node.id}
              node={node}
              research={research}
              data={data}
              selected={(selected || (nodes[0] && nodes[0].id)) === node.id}
              onSelect={onSelect}
              act={act} />
          ))}
          {nodes.length > limit && (
            <Button
              fluid
              textAlign="center"
              content={'Load more (' + (nodes.length - limit) + ' left)'}
              onClick={() => this.setState({ pages: pages + 1 })} />
          )}
          {!!query && designs.length > 0 && (
            <Box bold mt={1} mb={0.5} color="label">
              {'Designs (' + designs.length + ')'}
            </Box>
          )}
          {designs.slice(0, limit).map(design => (
            <DesignRow
              key={design.id}
              design={design}
              data={data}
              research={research}
              fab={printer(design)}
              showNodes
              onPrint={(id, amount) => act('print', {
                machine: printer.key(design),
                id,
                amount,
              })}
              onSelectNode={onSelect} />
          ))}
          {!!query && nodes.length === 0 && designs.length === 0 && (
            <NoticeBox>
              Nothing matches that.
            </NoticeBox>
          )}
        </Box>
        <Box
          style={{
            'position': 'absolute',
            'top': 0,
            'bottom': 0,
            'left': '52%',
            'right': 0,
            'padding': '8px',
            'box-sizing': 'border-box',
            'overflow-y': 'auto',
            'background-color': 'rgba(0, 0, 0, 0.2)',
          }}>
          <NodeDetails
            node={research.byId[selected] || nodes[0]}
            research={research}
            data={data}
            act={act}
            onSelect={onSelect}
            printer={printer} />
        </Box>
      </Fragment>
    );
  }
}

export const RdConsole = props => {
  const { act, data } = useBackend(props);
  return (
    <RdConsoleMenu act={act} data={data} />
  );
};

// A department lathe, techfab or imprinter, worked at the machine itself
class RdFabricatorMenu extends Component {
  constructor() {
    super();
    this.state = {
      search: '',
    };
  }

  render() {
    const { act, data } = this.props;
    const { search } = this.state;
    const research = {
      researchedDesigns: toSet(data.researched),
      nodesOfDesign: getLookups(data).nodesOfDesign,
      byId: getLookups(data).byId,
      statusOf: () => 'researched',
    };
    return (
      <Box
        style={{
          'position': 'absolute',
          'top': 0,
          'bottom': 0,
          'left': 0,
          'right': 0,
        }}>
        <Box
          style={{
            'position': 'absolute',
            'top': 0,
            'left': 0,
            'right': 0,
            'height': '40px',
            'padding': '6px 8px',
            'box-sizing': 'border-box',
            'display': 'flex',
            'align-items': 'center',
            'background-color': 'rgba(0, 0, 0, 0.33)',
          }}>
          <Box style={{ 'flex-grow': 1 }} mr={1}>
            <Input
              fluid
              value={search}
              placeholder={'Search what the ' + data.name + ' makes...'}
              onInput={(e, value) => this.setState({ search: value })} />
          </Box>
          {!data.no_sync && (
            <Button
              icon="sync"
              content="Sync research"
              onClick={() => act('sync')} />
          )}
        </Box>
        <Box
          style={{
            'position': 'absolute',
            'top': '40px',
            'bottom': 0,
            'left': 0,
            'right': 0,
          }}>
          <FabricatorPanel
            fab={data}
            data={data}
            research={research}
            act={act}
            search={search}
            onSelectNode={() => null} />
        </Box>
      </Box>
    );
  }
}

export const RdFabricator = props => {
  const { act, data } = useBackend(props);
  return (
    <RdFabricatorMenu act={act} data={data} />
  );
};
