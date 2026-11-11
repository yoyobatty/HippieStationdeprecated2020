/**
 * Runs inside the designer's iframe. The designer page calls
 * window.tguiPreview.render() with the design and data (as JSON, so the
 * objects belong to this frame), and gets mouse and key events back
 * through the hooks it hands over.
 *
 * In design mode every mouse press is caught before the components see
 * it: clicking selects, it never presses a button or opens a dropdown.
 */

import { render } from 'inferno';
import { renderDesign } from './render';

// Nothing here talks to BYOND; note it if a component tries
window.__sendToByond__ = url => {
  // eslint-disable-next-line no-console
  console.log('[byond]', url);
};

const root = document.getElementById('react-root');
let mode = 'design';
let hooks = {};
let hoverId = null;

/** The node id an element belongs to, from its dn-<id> class. */
export const nodeIdOf = el => {
  let cur = el;
  while (cur && cur !== document && cur.getAttribute) {
    const cls = cur.getAttribute('class') || '';
    const m = cls.match(/\bdn-(n\d+)\b/);
    if (m) {
      return m[1];
    }
    cur = cur.parentNode;
  }
  return null;
};

const inDesign = () => mode === 'design';

const swallow = e => {
  if (inDesign()) {
    e.preventDefault();
    e.stopPropagation();
  }
};

window.addEventListener('mousedown', e => {
  if (!inDesign()) {
    return;
  }
  swallow(e);
  if (hooks.onMouseDown) {
    hooks.onMouseDown({
      id: nodeIdOf(e.target),
      x: e.clientX,
      y: e.clientY,
      button: e.button,
      shift: e.shiftKey,
    });
  }
}, true);

for (const type of ['click', 'dblclick', 'mouseup', 'contextmenu',
  'focusin', 'input', 'change']) {
  window.addEventListener(type, swallow, true);
}

window.addEventListener('mousemove', e => {
  if (!inDesign()) {
    return;
  }
  const id = nodeIdOf(e.target);
  if (id !== hoverId) {
    hoverId = id;
    if (hooks.onHover) {
      hooks.onHover(id);
    }
  }
}, true);

document.addEventListener('mouseleave', () => {
  hoverId = null;
  if (hooks.onHover) {
    hooks.onHover(null);
  }
});

window.addEventListener('keydown', e => {
  // Typing into a text box in test mode stays in the text box
  const typing = !inDesign() && e.target && /^(INPUT|TEXTAREA)$/
    .test(e.target.tagName);
  if (typing && !(e.ctrlKey && e.key.toLowerCase() === 's')) {
    return;
  }
  if (hooks.onKeyDown && hooks.onKeyDown({
    key: e.key,
    ctrl: e.ctrlKey || e.metaKey,
    shift: e.shiftKey,
    alt: e.altKey,
    design: inDesign(),
  })) {
    e.preventDefault();
    e.stopPropagation();
  }
}, true);

window.addEventListener('scroll', () => {
  if (hooks.onScroll) {
    hooks.onScroll();
  }
}, true);

window.tguiPreview = {
  setHooks: next => {
    hooks = next || {};
  },
  /** Draws the design; returns its evaluation errors as JSON. */
  render: (designJson, dataJson, optsJson, onAct) => {
    const design = JSON.parse(designJson);
    const data = JSON.parse(dataJson);
    const opts = JSON.parse(optsJson);
    mode = opts.mode;
    document.body.classList.toggle('dz-design', mode === 'design');
    document.body.classList.toggle('dz-dragging', !!opts.dragging);
    opts.onAct = (action, params, nodeId) => {
      if (onAct) {
        onAct(action, JSON.stringify(params), nodeId);
      }
    };
    const { vnode, errors } = renderDesign(design, data, opts);
    render(vnode, root);
    return JSON.stringify(errors);
  },
  /** Every element drawn for each node id: { id: [rect, ...] }. */
  rects: () => {
    const out = {};
    for (const el of document.querySelectorAll('[class*="dn-n"]')) {
      const id = nodeIdOf(el);
      if (!id) {
        continue;
      }
      const r = el.getBoundingClientRect();
      if (r.width === 0 && r.height === 0) {
        continue;
      }
      (out[id] = out[id] || []).push({
        x: r.left, y: r.top, w: r.width, h: r.height,
      });
    }
    return JSON.stringify(out);
  },
};

if (window.parent && window.parent.tguiDesignerReady) {
  window.parent.tguiDesignerReady();
}
