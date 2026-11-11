/**
 * Draws a design with the real tgui-next components, the way the game's
 * Layout would. Every node's element carries a "dn-<id>" class so the
 * designer can find, outline and drop next to it.
 */

import { clamp, toFixed } from 'common/math';
import { classes } from 'common/react';
import { AnimatedNumber, BlockQuote, Box, Button, Collapsible, ColorBox, Dropdown, Flex, Grid, Icon, Input, LabeledList, NoticeBox, NumberInput, Section, Table, Tabs, TitleBar } from 'tgui/components';
import { UI_INTERACTIVE } from 'tgui/constants';
import { evaluate, fillTemplate, makeScope } from '../shared/expr';
import { findPropDef, stylePropsOf } from '../shared/registry';
import { rangesObject } from '../shared/ranges';

const addError = (ctx, node, where, message) => {
  const list = ctx.errors[node.id] || (ctx.errors[node.id] = []);
  const text = where + ': ' + message;
  if (!list.includes(text)) {
    list.push(text);
  }
};

const pv = (node, name, ctx) => {
  const p = node.props[name];
  if (!p) {
    return undefined;
  }
  if (p.x !== undefined) {
    const res = evaluate(p.x, ctx.scope);
    if (res.error) {
      addError(ctx, node, name, res.error);
    }
    return res.value;
  }
  const def = findPropDef(node.type, name);
  if (def && def.kind === 'text' && typeof p.v === 'string') {
    const res = fillTemplate(p.v, ctx.scope);
    res.errors.forEach(err => addError(ctx, node, name, err));
    return res.value;
  }
  if (def && def.kind === 'ranges') {
    return rangesObject(p.v);
  }
  return p.v;
};

const styleOf = (node, ctx) => {
  const style = {};
  for (const def of stylePropsOf(node.type)) {
    const value = pv(node, def.name, ctx);
    if (value !== undefined && value !== '' && value !== false
      && value !== null) {
      style[def.name] = value;
    }
  }
  return style;
};

/** An act() call for test mode, or undefined in design mode. */
const handlerOf = (node, name, ctx) => {
  const p = node.props[name];
  if (!p || !p.action || ctx.mode !== 'test') {
    return undefined;
  }
  const vars = ctx.vars;
  return value => {
    const params = {};
    for (const key of Object.keys(p.params || {})) {
      const res = evaluate(p.params[key], makeScope({ ...vars, value }));
      params[key] = res.error ? undefined : res.value;
    }
    ctx.opts.onAct(p.action, params, node.id);
  };
};

const emptyBox = (node, slot, ctx, label) => {
  if (ctx.mode !== 'design') {
    return null;
  }
  return (
    <div className="dz-empty" data-dslot={node.id + '|' + slot}>
      {label || 'Drop here'}
    </div>
  );
};

const slotChip = (node, slot, ctx) => {
  if (ctx.mode !== 'design' || !ctx.opts.dragging) {
    return null;
  }
  return (
    <span className="dz-slot" data-dslot={node.id + '|' + slot}>
      + {slot}
    </span>
  );
};

/** A ProgressBar that takes a className (the real one drops it). */
const Bar = props => {
  const {
    className, value, minValue = 0, maxValue = 1, ranges = {}, content,
  } = props;
  const scaled = (value - minValue) / (maxValue - minValue);
  let color = props.color;
  if (!color) {
    for (const rangeName of Object.keys(ranges)) {
      const range = ranges[rangeName];
      if (range && value >= range[0] && value <= range[1]) {
        color = rangeName;
        break;
      }
    }
  }
  const hasContent = content !== undefined && content !== '';
  return (
    <div
      className={classes([
        'ProgressBar',
        'ProgressBar--color--' + (color || 'default'),
        className,
      ])}>
      <div
        className="ProgressBar__fill"
        style={{ width: (clamp(scaled || 0, 0, 1) * 100) + '%' }} />
      <div className="ProgressBar__content">
        {hasContent ? content : toFixed((scaled || 0) * 100) + '%'}
      </div>
    </div>
  );
};

const listOf = (node, slot) => (slot === 'children'
  ? (node.children || [])
  : ((node.slots && node.slots[slot]) || []));

const renderList = (node, slot, ctx) => {
  const out = [];
  for (const child of listOf(node, slot)) {
    const rendered = renderNode(child, ctx);
    if (Array.isArray(rendered)) {
      out.push(...rendered);
    }
    else if (rendered) {
      out.push(rendered);
    }
  }
  return out;
};

const kids = (node, ctx, emptyLabel) => {
  const list = renderList(node, 'children', ctx);
  if (list.length === 0) {
    const box = emptyBox(node, 'children', ctx, emptyLabel);
    return box ? [box] : [];
  }
  return list;
};

const buttonsOf = (node, ctx) => {
  const list = renderList(node, 'buttons', ctx);
  if (list.length === 0) {
    return slotChip(node, 'buttons', ctx);
  }
  return list.length === 1 ? list[0] : list;
};

/** Draws one instance of a node (show-if and repeat already handled). */
const renderBody = (node, ctx, cls, key) => {
  const p = name => pv(node, name, ctx);
  switch (node.type) {
    case 'Section':
      return (
        <Section
          key={key}
          className={cls}
          title={p('title')}
          level={p('level')}
          buttons={buttonsOf(node, ctx)}
          {...styleOf(node, ctx)}>
          {kids(node, ctx)}
        </Section>
      );
    case 'LabeledList': {
      const list = renderList(node, 'children', ctx);
      return (
        <table key={key} className={classes(['LabeledList', cls])}>
          {list.length ? list : ctx.mode === 'design' && (
            <tr>
              <td colSpan={3}>{emptyBox(node, 'children', ctx)}</td>
            </tr>
          )}
        </table>
      );
    }
    case 'LabeledList.Item':
      return (
        <LabeledList.Item
          key={key}
          className={cls}
          label={p('label')}
          labelColor={p('labelColor') || 'label'}
          color={p('color')}
          buttons={buttonsOf(node, ctx)}>
          {renderList(node, 'children', ctx)}
        </LabeledList.Item>
      );
    case 'LabeledList.Divider': {
      const size = p('size') || 1;
      return (
        <tr key={key} className={classes(['LabeledList__row', cls])}>
          <td style={{ 'padding-bottom': (size * 6) + 'px' }} />
        </tr>
      );
    }
    case 'Flex':
      return (
        <Flex
          key={key}
          className={cls}
          direction={p('direction')}
          align={p('align')}
          justify={p('justify')}
          wrap={p('wrap')}
          spacing={p('spacing')}
          {...styleOf(node, ctx)}>
          {kids(node, ctx)}
        </Flex>
      );
    case 'Flex.Item':
      return (
        <Flex.Item
          key={key}
          className={cls}
          grow={p('grow')}
          align={p('align')}
          {...styleOf(node, ctx)}>
          {kids(node, ctx)}
        </Flex.Item>
      );
    case 'Grid':
      return (
        <Grid key={key} className={cls}>
          {kids(node, ctx)}
        </Grid>
      );
    case 'Grid.Column':
      return (
        <Grid.Column
          key={key}
          className={cls}
          size={p('size')}
          {...styleOf(node, ctx)}>
          {kids(node, ctx)}
        </Grid.Column>
      );
    case 'Table': {
      const list = renderList(node, 'children', ctx);
      return (
        <Table
          key={key}
          className={cls}
          collapsing={p('collapsing')}
          {...styleOf(node, ctx)}>
          {list.length ? list : ctx.mode === 'design' && (
            <tr>
              <td>{emptyBox(node, 'children', ctx)}</td>
            </tr>
          )}
        </Table>
      );
    }
    case 'Table.Row': {
      const list = renderList(node, 'children', ctx);
      return (
        <Table.Row
          key={key}
          className={cls}
          header={p('header')}
          {...styleOf(node, ctx)}>
          {list.length ? list : ctx.mode === 'design' && (
            <td>{emptyBox(node, 'children', ctx)}</td>
          )}
        </Table.Row>
      );
    }
    case 'Table.Cell':
      return (
        <Table.Cell
          key={key}
          className={cls}
          header={p('header')}
          collapsing={p('collapsing')}
          {...styleOf(node, ctx)}>
          {kids(node, ctx)}
        </Table.Cell>
      );
    case 'Tabs': {
      const tabs = renderList(node, 'children', ctx)
        .filter(tab => tab && tab.props && tab.props.__tab__);
      if (!tabs.length) {
        return (
          <Box key={key} className={cls}>
            {emptyBox(node, 'children', ctx, 'Drop tabs here')}
          </Box>
        );
      }
      const active = ctx.mode === 'design'
        ? ctx.opts.activeTabs && ctx.opts.activeTabs[node.id]
        : undefined;
      return (
        <Tabs
          key={key + (ctx.mode === 'design' ? ':d' : ':t')}
          className={cls}
          vertical={p('vertical')}
          activeTab={active}
          {...styleOf(node, ctx)}>
          {tabs}
        </Tabs>
      );
    }
    case 'Tabs.Tab': {
      const onClick = handlerOf(node, 'onClick', ctx);
      return (
        <Tabs.Tab
          key={key}
          __tab__
          className={cls}
          label={p('label') || ' '}
          icon={p('icon') || undefined}
          highlight={p('highlight')}
          onClick={onClick && (() => onClick())}>
          {kids(node, ctx)}
        </Tabs.Tab>
      );
    }
    case 'Collapsible': {
      const open = ctx.mode === 'design' ? true : !!p('open');
      return (
        <Collapsible
          key={key + (ctx.mode === 'design' ? ':d' : ':t' + open)}
          className={cls}
          title={p('title')}
          color={p('color') || 'default'}
          open={open}
          buttons={buttonsOf(node, ctx)}>
          {kids(node, ctx)}
        </Collapsible>
      );
    }
    case 'Box':
      return (
        <Box key={key} className={cls} {...styleOf(node, ctx)}>
          {kids(node, ctx, 'Empty box')}
        </Box>
      );
    case 'Text':
      return (
        <Box key={key} className={cls} {...styleOf(node, ctx)}>
          {p('text')}
        </Box>
      );
    case 'NoticeBox':
      return (
        <NoticeBox key={key} className={cls} {...styleOf(node, ctx)}>
          {p('text')}
          {renderList(node, 'children', ctx)}
        </NoticeBox>
      );
    case 'BlockQuote':
      return (
        <BlockQuote key={key} className={cls} {...styleOf(node, ctx)}>
          {p('text')}
        </BlockQuote>
      );
    case 'ProgressBar': {
      const min = p('minValue');
      const max = p('maxValue');
      return (
        <Bar
          key={key}
          className={cls}
          value={Number(p('value')) || 0}
          minValue={min === undefined || min === '' ? 0 : Number(min)}
          maxValue={max === undefined || max === '' ? 1 : Number(max)}
          ranges={p('ranges')}
          color={p('color')}
          content={p('content')} />
      );
    }
    case 'AnimatedNumber': {
      const decimals = p('decimals');
      const hasDecimals = decimals !== undefined && decimals !== '';
      return (
        <span key={key} className={cls}>
          <AnimatedNumber
            value={p('value')}
            format={hasDecimals
              ? (value => toFixed(value, Number(decimals)))
              : undefined} />
        </span>
      );
    }
    case 'Icon':
      return (
        <Icon
          key={key}
          className={cls}
          name={p('name') || 'question'}
          size={p('size')}
          spin={p('spin')}
          rotation={p('rotation')}
          {...styleOf(node, ctx)} />
      );
    case 'ColorBox':
      return (
        <ColorBox
          key={key}
          className={cls}
          color={p('color')}
          content={p('content')}
          {...styleOf(node, ctx)} />
      );
    case 'Button': {
      const onClick = handlerOf(node, 'onClick', ctx);
      return (
        <Button
          key={key}
          className={cls}
          content={p('content')}
          icon={p('icon') || undefined}
          color={p('color')}
          selected={p('selected')}
          disabled={p('disabled')}
          tooltip={p('tooltip') || undefined}
          tooltipPosition={p('tooltipPosition')}
          fluid={p('fluid')}
          onClick={onClick && (() => onClick())}
          {...styleOf(node, ctx)} />
      );
    }
    case 'Button.Checkbox': {
      const onClick = handlerOf(node, 'onClick', ctx);
      return (
        <Button.Checkbox
          key={key}
          className={cls}
          content={p('content')}
          checked={p('checked')}
          disabled={p('disabled')}
          tooltip={p('tooltip') || undefined}
          onClick={onClick && (() => onClick())}
          {...styleOf(node, ctx)} />
      );
    }
    case 'Input': {
      const onChange = handlerOf(node, 'onChange', ctx);
      return (
        <Input
          key={key}
          className={cls}
          value={p('value')}
          placeholder={p('placeholder')}
          maxLength={p('maxLength')}
          fluid={p('fluid')}
          onChange={onChange && ((e, value) => onChange(value))}
          {...styleOf(node, ctx)} />
      );
    }
    case 'NumberInput': {
      const onChange = handlerOf(node, 'onChange', ctx);
      const drag = !!p('whileDragging');
      const min = p('minValue');
      const max = p('maxValue');
      const step = p('step');
      const pps = p('stepPixelSize');
      return (
        <NumberInput
          key={key}
          className={cls}
          value={Number(p('value')) || 0}
          minValue={min === undefined || min === '' ? -Infinity : min}
          maxValue={max === undefined || max === '' ? Infinity : max}
          step={step || 1}
          stepPixelSize={pps || 1}
          unit={p('unit')}
          width={p('width')}
          animated={p('animated')}
          onChange={!drag && onChange
            ? ((e, value) => onChange(value)) : undefined}
          onDrag={drag && onChange
            ? ((e, value) => onChange(value)) : undefined} />
      );
    }
    case 'Dropdown': {
      const onSelected = handlerOf(node, 'onSelected', ctx);
      const options = p('options');
      const selected = p('selected');
      return (
        <Dropdown
          key={key + ':' + selected}
          className={cls}
          options={Array.isArray(options) ? options.map(String) : []}
          selected={selected}
          width={p('width')}
          over={p('over')}
          onSelected={value => onSelected && onSelected(value)}
          {...styleOf(node, ctx)} />
      );
    }
    default:
      return (
        <Box key={key} className={cls} color="bad">
          Unknown component {node.type}
        </Box>
      );
  }
};

/** A node with its show-if and repeat applied: a vnode, a list or null. */
const renderNode = (node, ctx) => {
  const ghostOf = hidden => classes([
    'dn-' + node.id,
    hidden && 'dz-ghost',
  ]);
  const showIf = (scopeCtx, index) => {
    if (!node.showIf || !String(node.showIf).trim()) {
      return true;
    }
    const res = evaluate(node.showIf, scopeCtx.scope);
    if (res.error) {
      addError(ctx, node, 'show if', res.error);
      return ctx.mode === 'design';
    }
    return !!res.value;
  };
  const instance = (scopeCtx, key) => {
    const shown = showIf(scopeCtx);
    if (!shown && !(ctx.mode === 'design' && ctx.opts.showHidden)) {
      return null;
    }
    return renderBody(node, scopeCtx, ghostOf(!shown), key);
  };
  if (!node.repeat || !node.repeat.list) {
    return instance(ctx, node.id);
  }
  const res = evaluate(node.repeat.list, ctx.scope);
  if (res.error) {
    addError(ctx, node, 'repeat', res.error);
  }
  const as = node.repeat.as || 'item';
  const items = Array.isArray(res.value) ? res.value : [];
  if (!items.length) {
    // Keep an empty list's template visible while designing
    if (ctx.mode !== 'design') {
      return null;
    }
    const vars = { ...ctx.vars, [as]: {} };
    const sub = { ...ctx, vars, scope: makeScope(vars) };
    return renderBody(node, sub, ghostOf(true), node.id + ':ghost');
  }
  const out = [];
  items.forEach((item, i) => {
    const vars = { ...ctx.vars, [as]: item };
    const sub = { ...ctx, vars, scope: makeScope(vars) };
    const vnode = instance(sub, node.id + ':' + i);
    if (vnode) {
      out.push(vnode);
    }
  });
  return out;
};

/**
 * The whole window. Returns { vnode, errors } where errors maps node ids
 * to what went wrong evaluating them.
 */
export const renderDesign = (design, data, opts) => {
  const vars = { ...data };
  const ctx = {
    design,
    mode: opts.mode,
    opts,
    vars,
    scope: makeScope(vars),
    errors: {},
  };
  const content = kids(design.root, ctx, 'Drag components here');
  const theme = design.theme || 'nanotrasen';
  const vnode = (
    <div className={'theme-' + theme}>
      <div className="Layout">
        <TitleBar
          className="Layout__titleBar"
          title={design.title || design.name || ''}
          status={UI_INTERACTIVE}
          fancy={1}
          onDragStart={() => null}
          onClose={() => null} />
        <div
          id="Layout__content"
          className={classes([
            'Layout__content',
            design.scrollable && 'Layout__content--scrollable',
          ])}>
          <Box m={1}>
            {content}
          </Box>
        </div>
      </div>
    </div>
  );
  return { vnode, errors: ctx.errors };
};
