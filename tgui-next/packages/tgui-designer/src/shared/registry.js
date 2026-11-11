/**
 * Every component the designer offers: its props, where it may go, what it
 * holds and what a fresh one looks like. The preview, the properties panel
 * and both code generators read from here.
 *
 * Prop kinds:
 *   text     - a string; {expr} parts are filled in from data
 *   number, bool
 *   select   - one of `options`
 *   color    - a tgui color name or any CSS color
 *   icon     - a Font Awesome 5 name
 *   expr     - always a JS expression (a bar's value, a list)
 *   list     - a fixed list of strings (or an expression)
 *   action   - an act() call: { action, params: { name: expr } }
 *   ranges   - ProgressBar color ranges
 */

export const COLORS = [
  'good', 'average', 'bad', 'label',
  'white', 'black', 'red', 'orange', 'yellow', 'olive', 'green', 'teal',
  'blue', 'violet', 'purple', 'pink', 'brown', 'grey',
];

export const BUTTON_COLORS = [
  'default', 'transparent', 'caution', 'danger',
  'good', 'average', 'bad',
  'red', 'orange', 'yellow', 'olive', 'green', 'teal',
  'blue', 'violet', 'purple', 'pink', 'brown', 'grey', 'black', 'white',
];

export const THEMES = [
  'nanotrasen', 'ntos', 'syndicate', 'retro', 'mecha', 'clockwork',
];

export const UI_STATES = [
  'default_state', 'physical_state', 'hands_state', 'notcontained_state',
  'contained_state', 'deep_inventory_state', 'inventory_state',
  'always_state', 'conscious_state', 'not_incapacitated_state',
  'human_adjacent_state', 'self_state', 'observer_state', 'z_state',
  'admin_state',
];

/** Box style props, shown in the Style group on most components. */
export const STYLE_PROPS = [
  { name: 'color', kind: 'color', label: 'Text color' },
  { name: 'backgroundColor', kind: 'color', label: 'Background' },
  { name: 'bold', kind: 'bool' },
  { name: 'italic', kind: 'bool' },
  { name: 'textAlign', kind: 'select', label: 'Align',
    options: ['left', 'center', 'right'] },
  { name: 'fontSize', kind: 'number', label: 'Font size' },
  { name: 'inline', kind: 'bool' },
  { name: 'nowrap', kind: 'bool', label: 'No wrap' },
  { name: 'width', kind: 'size' },
  { name: 'minWidth', kind: 'size', label: 'Min width' },
  { name: 'maxWidth', kind: 'size', label: 'Max width' },
  { name: 'height', kind: 'size' },
  { name: 'mt', kind: 'number', label: 'Margin top' },
  { name: 'mb', kind: 'number', label: 'Margin bottom' },
  { name: 'ml', kind: 'number', label: 'Margin left' },
  { name: 'mr', kind: 'number', label: 'Margin right' },
  { name: 'm', kind: 'number', label: 'Margin' },
  { name: 'opacity', kind: 'number' },
];

const TOOLTIP_POSITIONS = [
  'bottom', 'top', 'left', 'right',
  'bottom-left', 'bottom-right', 'top-left', 'top-right',
];

const t = (type, props = {}, children = [], slots = {}) => ({
  type, props, children, slots,
});
const v = value => ({ v: value });
const x = expr => ({ x: expr });

const text = (s, extra = {}) => t('Text', { text: v(s), ...extra });

/**
 * The component table. `jsx` is the tag the code uses, `parent` the only
 * types it may sit in (it gets wrapped in `wrapOut` elsewhere), `accepts`
 * the only children a container takes (others get wrapped in `wrapIn`).
 */
export const COMPONENTS = {
  'Section': {
    group: 'Layout',
    icon: 'window-maximize',
    jsx: 'Section',
    slots: ['children', 'buttons'],
    style: true,
    textProp: 'title',
    props: [
      { name: 'title', kind: 'text' },
      { name: 'level', kind: 'select', options: [1, 2, 3] },
    ],
    create: () => t('Section', { title: v('Section') }),
  },
  'LabeledList': {
    group: 'Layout',
    label: 'Labeled list',
    icon: 'list',
    jsx: 'LabeledList',
    slots: ['children'],
    accepts: ['LabeledList.Item', 'LabeledList.Divider'],
    wrapIn: 'LabeledList.Item',
    props: [],
    create: () => t('LabeledList', {}, [
      t('LabeledList.Item', { label: v('Label') }, [text('Value')]),
    ]),
  },
  'LabeledList.Item': {
    group: 'Layout',
    label: 'Labeled row',
    icon: 'grip-lines',
    jsx: 'LabeledList.Item',
    slots: ['children', 'buttons'],
    parent: ['LabeledList'],
    wrapOut: 'LabeledList',
    textProp: 'label',
    props: [
      { name: 'label', kind: 'text' },
      { name: 'labelColor', kind: 'color', label: 'Label color' },
      { name: 'color', kind: 'color' },
    ],
    create: () => t('LabeledList.Item', { label: v('Label') }, [
      text('Value'),
    ]),
  },
  'LabeledList.Divider': {
    group: 'Layout',
    label: 'Row gap',
    icon: 'minus',
    jsx: 'LabeledList.Divider',
    parent: ['LabeledList'],
    wrapOut: 'LabeledList',
    props: [
      { name: 'size', kind: 'number' },
    ],
    create: () => t('LabeledList.Divider', {}),
  },
  'Flex': {
    group: 'Layout',
    label: 'Columns (Flex)',
    icon: 'columns',
    jsx: 'Flex',
    slots: ['children'],
    accepts: ['Flex.Item'],
    wrapIn: 'Flex.Item',
    style: true,
    props: [
      { name: 'direction', kind: 'select', options: ['row', 'column'] },
      { name: 'align', kind: 'select',
        options: ['stretch', 'center', 'flex-start', 'flex-end',
          'baseline'] },
      { name: 'justify', kind: 'select',
        options: ['flex-start', 'center', 'flex-end', 'space-between',
          'space-around'] },
      { name: 'wrap', kind: 'select', options: ['nowrap', 'wrap'] },
      { name: 'spacing', kind: 'select', options: [0, 1, 2] },
    ],
    create: () => t('Flex', { spacing: v(1) }, [
      t('Flex.Item', { grow: v(1) }, [text('Left')]),
      t('Flex.Item', { grow: v(1) }, [text('Right')]),
    ]),
  },
  'Flex.Item': {
    group: 'Layout',
    label: 'Column (Flex item)',
    icon: 'square',
    jsx: 'Flex.Item',
    slots: ['children'],
    parent: ['Flex'],
    wrapOut: 'Flex',
    style: true,
    props: [
      { name: 'grow', kind: 'number' },
      { name: 'align', kind: 'select',
        options: ['stretch', 'center', 'flex-start', 'flex-end',
          'baseline'] },
    ],
    create: () => t('Flex.Item', { grow: v(1) }),
  },
  'Grid': {
    group: 'Layout',
    icon: 'th-large',
    jsx: 'Grid',
    slots: ['children'],
    accepts: ['Grid.Column'],
    wrapIn: 'Grid.Column',
    props: [],
    create: () => t('Grid', {}, [
      t('Grid.Column', {}, [text('Left')]),
      t('Grid.Column', {}, [text('Right')]),
    ]),
  },
  'Grid.Column': {
    group: 'Layout',
    label: 'Grid column',
    icon: 'square',
    jsx: 'Grid.Column',
    slots: ['children'],
    parent: ['Grid'],
    wrapOut: 'Grid',
    style: true,
    props: [
      { name: 'size', kind: 'number', label: 'Size (%)' },
    ],
    create: () => t('Grid.Column'),
  },
  'Table': {
    group: 'Layout',
    icon: 'table',
    jsx: 'Table',
    slots: ['children'],
    accepts: ['Table.Row'],
    wrapIn: 'Table.Row',
    style: true,
    props: [
      { name: 'collapsing', kind: 'bool' },
    ],
    create: () => t('Table', {}, [
      t('Table.Row', { header: v(true) }, [
        t('Table.Cell', {}, [text('Name')]),
        t('Table.Cell', {}, [text('Amount')]),
      ]),
      t('Table.Row', {}, [
        t('Table.Cell', {}, [text('Thing')]),
        t('Table.Cell', {}, [text('1')]),
      ]),
    ]),
  },
  'Table.Row': {
    group: 'Layout',
    label: 'Table row',
    icon: 'grip-horizontal',
    jsx: 'Table.Row',
    slots: ['children'],
    accepts: ['Table.Cell'],
    wrapIn: 'Table.Cell',
    parent: ['Table'],
    wrapOut: 'Table',
    style: true,
    props: [
      { name: 'header', kind: 'bool' },
    ],
    create: () => t('Table.Row', {}, [
      t('Table.Cell', {}, [text('Cell')]),
      t('Table.Cell', {}, [text('Cell')]),
    ]),
  },
  'Table.Cell': {
    group: 'Layout',
    label: 'Table cell',
    icon: 'square',
    jsx: 'Table.Cell',
    slots: ['children'],
    parent: ['Table.Row'],
    wrapOut: 'Table.Row',
    style: true,
    props: [
      { name: 'header', kind: 'bool' },
      { name: 'collapsing', kind: 'bool' },
    ],
    create: () => t('Table.Cell', {}, [text('Cell')]),
  },
  'Tabs': {
    group: 'Layout',
    icon: 'folder',
    jsx: 'Tabs',
    slots: ['children'],
    accepts: ['Tabs.Tab'],
    wrapIn: 'Tabs.Tab',
    style: true,
    props: [
      { name: 'vertical', kind: 'bool' },
    ],
    create: () => t('Tabs', {}, [
      t('Tabs.Tab', { label: v('First') }, [text('First tab')]),
      t('Tabs.Tab', { label: v('Second') }, [text('Second tab')]),
    ]),
  },
  'Tabs.Tab': {
    group: 'Layout',
    label: 'Tab',
    icon: 'folder-open',
    jsx: 'Tabs.Tab',
    slots: ['children'],
    parent: ['Tabs'],
    wrapOut: 'Tabs',
    textProp: 'label',
    props: [
      { name: 'label', kind: 'text' },
      { name: 'icon', kind: 'icon' },
      { name: 'highlight', kind: 'bool' },
      { name: 'onClick', kind: 'action', label: 'On click' },
    ],
    create: () => t('Tabs.Tab', { label: v('Tab') }),
  },
  'Collapsible': {
    group: 'Layout',
    icon: 'caret-square-down',
    jsx: 'Collapsible',
    slots: ['children', 'buttons'],
    textProp: 'title',
    props: [
      { name: 'title', kind: 'text' },
      { name: 'color', kind: 'buttonColor' },
      { name: 'open', kind: 'bool', label: 'Starts open' },
    ],
    create: () => t('Collapsible', { title: v('More') }, [text('Hidden')]),
  },
  'Box': {
    group: 'Layout',
    icon: 'square-full',
    jsx: 'Box',
    slots: ['children'],
    style: true,
    props: [],
    create: () => t('Box'),
  },
  'Text': {
    group: 'Content',
    icon: 'font',
    jsx: 'Box',
    style: true,
    textProp: 'text',
    props: [
      { name: 'text', kind: 'text', multiline: true },
    ],
    create: () => text('Text'),
  },
  'NoticeBox': {
    group: 'Content',
    label: 'Notice',
    icon: 'exclamation-triangle',
    jsx: 'NoticeBox',
    slots: ['children'],
    style: true,
    textProp: 'text',
    props: [
      { name: 'text', kind: 'text', multiline: true },
    ],
    create: () => t('NoticeBox', { text: v('Notice') }),
  },
  'BlockQuote': {
    group: 'Content',
    label: 'Quote',
    icon: 'quote-left',
    jsx: 'BlockQuote',
    style: true,
    textProp: 'text',
    props: [
      { name: 'text', kind: 'text', multiline: true },
    ],
    create: () => t('BlockQuote', { text: v('Quote') }),
  },
  'ProgressBar': {
    group: 'Content',
    label: 'Progress bar',
    icon: 'battery-half',
    jsx: 'ProgressBar',
    textProp: 'content',
    props: [
      { name: 'value', kind: 'expr' },
      { name: 'minValue', kind: 'number', label: 'Min' },
      { name: 'maxValue', kind: 'number', label: 'Max' },
      { name: 'ranges', kind: 'ranges', label: 'Colors' },
      { name: 'color', kind: 'buttonColor', label: 'Fixed color' },
      { name: 'content', kind: 'text', label: 'Text',
        placeholder: 'percent' },
    ],
    create: () => t('ProgressBar', { value: v(0.5) }),
  },
  'AnimatedNumber': {
    group: 'Content',
    label: 'Number',
    icon: 'sort-numeric-up',
    jsx: 'AnimatedNumber',
    props: [
      { name: 'value', kind: 'expr' },
      { name: 'decimals', kind: 'number' },
    ],
    create: () => t('AnimatedNumber', { value: v(42) }),
  },
  'Icon': {
    group: 'Content',
    icon: 'icons',
    jsx: 'Icon',
    style: true,
    props: [
      { name: 'name', kind: 'icon' },
      { name: 'size', kind: 'number' },
      { name: 'spin', kind: 'bool' },
      { name: 'rotation', kind: 'number' },
    ],
    create: () => t('Icon', { name: v('cog') }),
  },
  'ColorBox': {
    group: 'Content',
    label: 'Color box',
    icon: 'palette',
    jsx: 'ColorBox',
    style: true,
    props: [
      { name: 'color', kind: 'expr', label: 'Color' },
      { name: 'content', kind: 'text' },
    ],
    create: () => t('ColorBox', { color: v('#4aa3ff') }),
  },
  'Button': {
    group: 'Controls',
    icon: 'hand-pointer',
    jsx: 'Button',
    style: true,
    textProp: 'content',
    props: [
      { name: 'content', kind: 'text', label: 'Text' },
      { name: 'icon', kind: 'icon' },
      { name: 'onClick', kind: 'action', label: 'On click' },
      { name: 'color', kind: 'buttonColor' },
      { name: 'selected', kind: 'bool' },
      { name: 'disabled', kind: 'bool' },
      { name: 'tooltip', kind: 'text' },
      { name: 'tooltipPosition', kind: 'select', label: 'Tooltip side',
        options: TOOLTIP_POSITIONS },
      { name: 'fluid', kind: 'bool', label: 'Full width' },
    ],
    create: () => t('Button', { content: v('Button') }),
  },
  'Button.Checkbox': {
    group: 'Controls',
    label: 'Checkbox',
    icon: 'check-square',
    jsx: 'Button.Checkbox',
    style: true,
    textProp: 'content',
    props: [
      { name: 'content', kind: 'text', label: 'Text' },
      { name: 'checked', kind: 'bool' },
      { name: 'onClick', kind: 'action', label: 'On click' },
      { name: 'disabled', kind: 'bool' },
      { name: 'tooltip', kind: 'text' },
    ],
    create: () => t('Button.Checkbox', {
      content: v('Checkbox'), checked: v(true),
    }),
  },
  'Input': {
    group: 'Controls',
    label: 'Text input',
    icon: 'i-cursor',
    jsx: 'Input',
    style: true,
    props: [
      { name: 'value', kind: 'text' },
      { name: 'placeholder', kind: 'text' },
      { name: 'onChange', kind: 'action', label: 'On enter',
        valueVar: true },
      { name: 'maxLength', kind: 'number', label: 'Max length' },
      { name: 'fluid', kind: 'bool', label: 'Full width' },
    ],
    create: () => t('Input', { placeholder: v('Type here') }),
  },
  'NumberInput': {
    group: 'Controls',
    label: 'Number input',
    icon: 'sort-numeric-down',
    jsx: 'NumberInput',
    props: [
      { name: 'value', kind: 'expr' },
      { name: 'minValue', kind: 'number', label: 'Min' },
      { name: 'maxValue', kind: 'number', label: 'Max' },
      { name: 'step', kind: 'number' },
      { name: 'stepPixelSize', kind: 'number', label: 'Pixels per step' },
      { name: 'unit', kind: 'text' },
      { name: 'width', kind: 'size' },
      { name: 'animated', kind: 'bool' },
      { name: 'onChange', kind: 'action', label: 'On change',
        valueVar: true },
      { name: 'whileDragging', kind: 'bool', label: 'Send while dragging' },
    ],
    create: () => t('NumberInput', {
      value: v(50), minValue: v(0), maxValue: v(100), width: v('60px'),
    }),
  },
  'Dropdown': {
    group: 'Controls',
    icon: 'caret-square-down',
    jsx: 'Dropdown',
    style: true,
    props: [
      { name: 'options', kind: 'list' },
      { name: 'selected', kind: 'text' },
      { name: 'onSelected', kind: 'action', label: 'On pick',
        valueVar: true },
      { name: 'width', kind: 'size' },
      { name: 'over', kind: 'bool', label: 'Opens upward' },
    ],
    create: () => t('Dropdown', {
      options: v(['One', 'Two', 'Three']),
      selected: v('One'),
      width: v('120px'),
    }),
  },
};

export const GROUPS = ['Layout', 'Content', 'Controls'];

export const getDef = type => COMPONENTS[type];

export const labelOf = type => {
  const def = COMPONENTS[type];
  return def ? (def.label || type) : type;
};

/** The Style group of a type, less any prop the type has itself. */
export const stylePropsOf = type => {
  const def = COMPONENTS[type];
  if (!def || !def.style) {
    return [];
  }
  return STYLE_PROPS.filter(s => !def.props.some(p => p.name === s.name));
};

/** All prop definitions of a type, the Style group included. */
export const propDefsOf = type => {
  const def = COMPONENTS[type];
  if (!def) {
    return [];
  }
  return [...def.props, ...stylePropsOf(type)];
};

export const findPropDef = (type, name) => (
  propDefsOf(type).find(p => p.name === name)
);

export const hasSlot = (type, slot) => {
  const def = COMPONENTS[type];
  return !!def && !!def.slots && def.slots.includes(slot);
};

export const ROOT_TYPE = 'Window';
