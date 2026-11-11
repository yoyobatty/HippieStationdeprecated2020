/**
 * The tree of what's in the window. Click to select, drag to move, the
 * arrow folds a branch. Rows show the item's text, and marks for a
 * show-if (eye), a repeat (loop) and an error (red dot).
 */

import { Component } from 'inferno';
import { canDrop, findNode, isContainer } from '../shared/model';
import { getDef, labelOf, ROOT_TYPE } from '../shared/registry';

const summary = node => {
  const def = getDef(node.type);
  const prop = def && def.textProp && node.props[def.textProp];
  if (!prop) {
    return '';
  }
  const text = prop.x !== undefined ? '{' + prop.x + '}' : prop.v;
  if (text === undefined || text === null || text === '') {
    return '';
  }
  const s = String(text).replace(/\s+/g, ' ');
  return s.length > 28 ? s.slice(0, 27) + '…' : s;
};

export class Outline extends Component {
  constructor(props) {
    super(props);
    this.state = { collapsed: {} };
  }

  toggle(id) {
    this.setState(state => ({
      collapsed: { ...state.collapsed, [id]: !state.collapsed[id] },
    }));
  }

  /** The drop target for a page point over a row, or null. */
  dropAt(px, py, type, movingId) {
    const { design } = this.props;
    const els = document.elementsFromPoint(px, py);
    const row = els.find(el => el.getAttribute
      && el.getAttribute('data-oid'));
    if (!row) {
      return null;
    }
    const id = row.getAttribute('data-oid');
    const rect = row.getBoundingClientRect();
    const r = (py - rect.top) / rect.height;
    if (id === 'root') {
      if (canDrop(design, type, 'root', 'children', movingId)) {
        return {
          parentId: 'root', slot: 'children',
          index: design.root.children.length,
          orow: 'root', opos: 'inside', source: 'outline',
        };
      }
      return null;
    }
    const found = findNode(design, id);
    if (!found) {
      return null;
    }
    const slotName = row.getAttribute('data-oslot');
    if (slotName) {
      // A "buttons" heading row: into that slot
      if (canDrop(design, type, id, slotName, movingId)) {
        return {
          parentId: id, slot: slotName,
          index: ((found.node.slots || {})[slotName] || []).length,
          orow: id + '|' + slotName, opos: 'inside', source: 'outline',
        };
      }
      return null;
    }
    if (isContainer(found.node.type) && r > 0.3 && r < 0.7
      && canDrop(design, type, id, 'children', movingId)) {
      return {
        parentId: id, slot: 'children',
        index: found.node.children.length,
        orow: id, opos: 'inside', source: 'outline',
      };
    }
    if (found.parent
      && canDrop(design, type, found.parent.id, found.slot, movingId)) {
      const before = r < 0.5;
      return {
        parentId: found.parent.id,
        slot: found.slot,
        index: found.index + (before ? 0 : 1),
        orow: id, opos: before ? 'before' : 'after', source: 'outline',
      };
    }
    return null;
  }

  renderRows(node, depth, rows) {
    const { selectedId, errors, onSelect, onStartDrag, dropTarget }
      = this.props;
    const collapsed = this.state.collapsed[node.id];
    const isRoot = node.type === ROOT_TYPE;
    const kids = node.children || [];
    const buttons = (node.slots && node.slots.buttons) || [];
    const hasKids = kids.length > 0 || buttons.length > 0;
    const drop = dropTarget && dropTarget.source === 'outline'
      && dropTarget.orow === node.id ? dropTarget.opos : null;
    const def = getDef(node.type);
    const { onHover } = this.props;
    const row = (
      <div
        key={node.id}
        data-oid={node.id}
        className={'orow'
          + (selectedId === node.id ? ' orow--selected' : '')
          + (drop ? ' orow--drop-' + drop : '')}
        style={{ 'padding-left': (6 + depth * 14) + 'px' }}
        onMouseEnter={() => onHover(isRoot ? null : node.id)}
        onMouseDown={e => {
          if (e.button !== 0 || e.target.closest('.orow__caret')) {
            return;
          }
          e.preventDefault();
          onSelect(isRoot ? null : node.id);
          if (!isRoot) {
            onStartDrag({ kind: 'move', id: node.id }, e.clientX,
              e.clientY);
          }
        }}>
        <span
          className={'orow__caret' + (hasKids ? '' : ' orow__caret--none')}
          onClick={() => hasKids && this.toggle(node.id)}>
          <i className={'fas fa-caret-' + (collapsed ? 'right' : 'down')} />
        </span>
        <i className={'orow__icon fas fa-'
          + (isRoot ? 'window-restore' : (def ? def.icon : 'question'))} />
        <span className="orow__type">
          {isRoot ? 'Window' : labelOf(node.type)}
        </span>
        <span className="orow__text">{isRoot ? '' : summary(node)}</span>
        {node.showIf && (
          <i
            className="orow__badge fas fa-eye"
            title={'Shown if ' + node.showIf} />
        )}
        {node.repeat && node.repeat.list && (
          <i
            className="orow__badge fas fa-redo"
            title={'One per ' + node.repeat.as + ' in '
              + node.repeat.list} />
        )}
        {errors[node.id] && (
          <i
            className="orow__badge orow__badge--error fas fa-circle"
            title={errors[node.id].join('\n')} />
        )}
      </div>
    );
    rows.push(row);
    if (collapsed) {
      return;
    }
    if (buttons.length) {
      const slotDrop = dropTarget && dropTarget.source === 'outline'
        && dropTarget.orow === node.id + '|buttons';
      const slotRow = (
        <div
          key={node.id + '|buttons'}
          data-oid={node.id}
          data-oslot="buttons"
          className={'orow orow--slot'
            + (slotDrop ? ' orow--drop-inside' : '')}
          style={{ 'padding-left': (6 + (depth + 1) * 14) + 'px' }}>
          <span className="orow__caret orow__caret--none" />
          <span className="orow__type">buttons</span>
        </div>
      );
      rows.push(slotRow);
      buttons.forEach(child => this.renderRows(child, depth + 2, rows));
    }
    kids.forEach(child => this.renderRows(child, depth + 1, rows));
  }

  render() {
    const rows = [];
    this.renderRows(this.props.design.root, 0, rows);
    return (
      <div className="outline" onMouseLeave={() => this.props.onHover(null)}>
        {rows}
      </div>
    );
  }
}
