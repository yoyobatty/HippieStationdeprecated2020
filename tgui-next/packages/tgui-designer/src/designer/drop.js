/**
 * Where a dragged component lands in the preview. Works on the iframe's
 * DOM in its own coordinates: finds the node under the pointer, then
 * either goes inside it (a container, away from its edges) or before or
 * after it, climbing to the parent when the drop isn't allowed there.
 *
 * A target is { parentId, slot, index, line } or { ..., box } where line
 * and box are rectangles to draw, in iframe coordinates.
 */

import { canDrop, findNode, isContainer, isInside } from '../shared/model';

export const nodeIdOf = el => {
  let cur = el;
  while (cur && cur.getAttribute) {
    const cls = cur.getAttribute('class') || '';
    const m = cls.match(/\bdn-(n\d+)\b/);
    if (m) {
      return m[1];
    }
    cur = cur.parentNode;
  }
  return null;
};

/** The element drawn for a node that holds `el`, or its first one. */
const elementOf = (doc, id, el) => {
  let cur = el;
  while (cur && cur.getAttribute) {
    const cls = cur.getAttribute('class') || '';
    if (new RegExp('\\bdn-' + id + '\\b').test(cls)) {
      return cur;
    }
    cur = cur.parentNode;
  }
  return doc.querySelector('.dn-' + id);
};

const rectOf = el => {
  const r = el.getBoundingClientRect();
  return { x: r.left, y: r.top, w: r.width, h: r.height };
};

const listOf = (node, slot) => (slot === 'children'
  ? (node.children || [])
  : ((node.slots && node.slots[slot]) || []));

/** Do a slot's children run across ('x') or down ('y')? */
const axisOf = (doc, node, slot) => {
  if (slot !== 'children') {
    return 'x';
  }
  if (node.type === 'Flex') {
    const dir = node.props.direction && node.props.direction.v;
    return dir === 'column' ? 'y' : 'x';
  }
  if (node.type === 'Table.Row' || node.type === 'Grid') {
    return 'x';
  }
  const kids = listOf(node, slot);
  const first = kids[0] && doc.querySelector('.dn-' + kids[0].id);
  const second = kids[1] && doc.querySelector('.dn-' + kids[1].id);
  if (first && second) {
    const a = first.getBoundingClientRect();
    const b = second.getBoundingClientRect();
    const sideBySide = b.left >= a.right - 2 && b.top < a.bottom - 2;
    return sideBySide ? 'x' : 'y';
  }
  if (first) {
    const view = doc.defaultView;
    const display = view.getComputedStyle(first).display;
    if (/^inline/.test(display)) {
      return 'x';
    }
  }
  return 'y';
};

/** Going inside a container: the index the pointer is closest to. */
const insideTarget = (doc, design, parentId, slot, px, py, el) => {
  const parent = parentId === 'root'
    ? design.root : findNode(design, parentId).node;
  const kids = listOf(parent, slot);
  const holder = parentId === 'root'
    ? doc.querySelector('.Layout__content > div')
    : el || doc.querySelector('.dn-' + parentId);
  const empty = doc.querySelector(
    `[data-dslot="${parentId}|${slot}"]`);
  if (!kids.length) {
    const boxEl = empty || holder;
    return {
      parentId, slot, index: 0,
      box: boxEl ? rectOf(boxEl) : null,
    };
  }
  const axis = axisOf(doc, parent, slot);
  const rects = kids.map(kid => {
    const kidEl = doc.querySelector('.dn-' + kid.id);
    return kidEl ? rectOf(kidEl) : null;
  });
  let index = kids.length;
  for (let i = 0; i < kids.length; i++) {
    const r = rects[i];
    if (!r) {
      continue;
    }
    const mid = axis === 'y' ? r.y + r.h / 2 : r.x + r.w / 2;
    const pos = axis === 'y' ? py : px;
    // In a wrapped row, a later line counts as after
    const sameLine = axis === 'y' || (py >= r.y && py <= r.y + r.h);
    if (pos < mid && (sameLine || py < r.y)) {
      index = i;
      break;
    }
  }
  const lineAt = (r, before) => (axis === 'y'
    ? { x: r.x, y: before ? r.y : r.y + r.h, w: r.w, h: 0 }
    : { x: before ? r.x : r.x + r.w, y: r.y, w: 0, h: r.h });
  let line = null;
  if (index < kids.length && rects[index]) {
    line = lineAt(rects[index], true);
  }
  else {
    const last = rects.filter(Boolean).pop();
    if (last) {
      line = lineAt(last, false);
    }
  }
  return { parentId, slot, index, line };
};

/**
 * The drop target at (px, py) in the iframe, for a new component of
 * `type` or the moving node `movingId`.
 */
export const dropTarget = (doc, design, type, movingId, px, py) => {
  let el = doc.elementFromPoint(px, py);
  if (!el) {
    return null;
  }
  // An empty slot's placeholder
  const slotEl = el.closest && el.closest('[data-dslot]');
  if (slotEl) {
    const [parentId, slot] = slotEl.getAttribute('data-dslot').split('|');
    if (canDrop(design, type, parentId, slot, movingId)) {
      return { parentId, slot, index: 0, box: rectOf(slotEl) };
    }
  }
  let id = nodeIdOf(el);
  if (id && movingId && (id === movingId
    || isInside(design, id, movingId))) {
    id = movingId;
    el = elementOf(doc, id, el);
  }
  while (id) {
    const found = findNode(design, id);
    if (!found) {
      break;
    }
    const node = found.node;
    const nodeEl = elementOf(doc, id, el);
    const r = nodeEl ? rectOf(nodeEl) : null;
    // Inside a container, away from its edges
    if (r && id !== movingId && isContainer(node.type)
      && canDrop(design, type, id, 'children', movingId)) {
      // Thin edges: a section's padding is about 6px, and pointing into
      // it should mean "at the end of this section", not "after it"
      const edgeY = Math.min(4, r.h / 4);
      const edgeX = Math.min(4, r.w / 4);
      const nearEdge = py < r.y + edgeY || py > r.y + r.h - edgeY
        || (found.parent && found.parent.type === 'Flex'
          && (px < r.x + edgeX || px > r.x + r.w - edgeX));
      if (!nearEdge || !found.parent) {
        return insideTarget(doc, design, id, 'children', px, py, nodeEl);
      }
    }
    // Before or after it
    if (r && found.parent) {
      const parentId = found.parent.id;
      if (canDrop(design, type, parentId, found.slot, movingId)) {
        const axis = axisOf(doc, found.parent, found.slot);
        const before = axis === 'y'
          ? py < r.y + r.h / 2
          : px < r.x + r.w / 2;
        return {
          parentId,
          slot: found.slot,
          index: found.index + (before ? 0 : 1),
          line: axis === 'y'
            ? { x: r.x, y: before ? r.y : r.y + r.h, w: r.w, h: 0 }
            : { x: before ? r.x : r.x + r.w, y: r.y, w: 0, h: r.h },
        };
      }
    }
    // Not here: try the parent
    if (!found.parent || found.parent.id === 'root') {
      break;
    }
    id = found.parent.id;
    el = nodeEl ? nodeEl.parentNode : el;
  }
  if (canDrop(design, type, 'root', 'children', movingId)) {
    return insideTarget(doc, design, 'root', 'children', px, py, null);
  }
  return null;
};
