/**
 * The window being designed: an iframe at the window's size running the
 * real components (preview.bundle.js), with the selection, hover and drop
 * marks drawn over it, and a corner handle that resizes the window.
 */

import { Component, createRef } from 'inferno';
import { labelOf } from '../shared/registry';
import { findNode } from '../shared/model';
import { dropTarget } from './drop';

export class Canvas extends Component {
  constructor(props) {
    super(props);
    this.frameRef = createRef();
    this.state = {
      rects: {},
    };
    this.lastKey = null;
    this.lastClick = { id: null, at: 0 };
    window.tguiDesignerReady = () => this.frameReady();
  }

  componentDidMount() {
    this.onWindowResize = () => this.refreshRects();
    window.addEventListener('resize', this.onWindowResize);
  }

  componentWillUnmount() {
    window.removeEventListener('resize', this.onWindowResize);
  }

  componentDidUpdate() {
    this.renderPreview();
  }

  preview() {
    const frame = this.frameRef.current;
    return frame && frame.contentWindow && frame.contentWindow.tguiPreview;
  }

  frameReady() {
    const preview = this.preview();
    if (!preview) {
      return;
    }
    preview.setHooks({
      onMouseDown: e => this.handleFrameMouseDown(e),
      onHover: id => this.props.onHover(id),
      onKeyDown: e => this.props.onKeyDown(e),
      onScroll: () => this.refreshRects(),
    });
    this.lastKey = null;
    this.renderPreview();
  }

  handleFrameMouseDown(e) {
    const frame = this.frameRef.current;
    if (!frame) {
      return;
    }
    const r = frame.getBoundingClientRect();
    const zoom = this.props.zoom;
    const x = r.left + e.x * zoom;
    const y = r.top + e.y * zoom;
    const now = Date.now();
    const double = e.id && this.lastClick.id === e.id
      && now - this.lastClick.at < 400;
    this.lastClick = { id: e.id, at: double ? 0 : now };
    this.props.onNodeMouseDown(e.id, x, y, e.button, double);
  }

  renderPreview() {
    const preview = this.preview();
    if (!preview) {
      return;
    }
    const { design, data, mode, showHidden, activeTabs, dragging } = this.props;
    const designJson = JSON.stringify(design);
    const dataJson = JSON.stringify(data);
    const optsJson = JSON.stringify({
      mode, showHidden, activeTabs, dragging,
    });
    const key = designJson + '\n' + dataJson + '\n' + optsJson;
    if (key === this.lastKey) {
      return;
    }
    this.lastKey = key;
    let errors = {};
    try {
      errors = JSON.parse(preview.render(designJson, dataJson, optsJson,
        (action, paramsJson, nodeId) => this.props.onAct(action,
          JSON.parse(paramsJson), nodeId)));
    }
    catch (err) {
      errors = { root: ['Preview crashed: ' + err.message] };
    }
    this.props.onErrors(errors);
    this.refreshRects();
  }

  refreshRects() {
    window.requestAnimationFrame(() => {
      const preview = this.preview();
      if (!preview) {
        return;
      }
      try {
        this.setState({ rects: JSON.parse(preview.rects()) });
      }
      catch (err) {
        this.setState({ rects: {} });
      }
    });
  }

  /** The drop target under a page point, or null outside the frame. */
  dropAt(px, py, type, movingId) {
    const frame = this.frameRef.current;
    if (!frame || !frame.contentDocument) {
      return null;
    }
    const r = frame.getBoundingClientRect();
    if (px < r.left || px > r.right || py < r.top || py > r.bottom) {
      return null;
    }
    const zoom = this.props.zoom;
    return dropTarget(frame.contentDocument, this.props.design, type,
      movingId, (px - r.left) / zoom, (py - r.top) / zoom);
  }

  startResize(e) {
    e.preventDefault();
    const { design, zoom, onResize } = this.props;
    const startX = e.clientX;
    const startY = e.clientY;
    const w = design.width;
    const h = design.height;
    const move = ev => {
      onResize(
        Math.max(150, Math.round(w + (ev.clientX - startX) / zoom)),
        Math.max(100, Math.round(h + (ev.clientY - startY) / zoom)),
        true);
    };
    const up = () => {
      window.removeEventListener('mousemove', move);
      window.removeEventListener('mouseup', up);
      onResize(null, null, false);
    };
    window.addEventListener('mousemove', move);
    window.addEventListener('mouseup', up);
  }

  renderMarks() {
    const { design, selectedId, hoverId, dropTarget: target } = this.props;
    const { rects } = this.state;
    const marks = [];
    const box = (r, cls, key, label) => (
      <div
        key={key}
        className={'mark ' + cls}
        style={{
          left: r.x + 'px',
          top: r.y + 'px',
          width: r.w + 'px',
          height: r.h + 'px',
        }}>
        {label && <span className="mark__label">{label}</span>}
      </div>
    );
    if (hoverId && hoverId !== selectedId && rects[hoverId]) {
      rects[hoverId].forEach((r, i) => marks.push(
        box(r, 'mark--hover', 'h' + i)));
    }
    if (selectedId && rects[selectedId]) {
      const found = findNode(design, selectedId);
      const label = found ? labelOf(found.node.type) : '';
      rects[selectedId].forEach((r, i) => marks.push(
        box(r, i === 0 ? 'mark--selected' : 'mark--selected-copy',
          's' + i, i === 0 ? label : null)));
    }
    if (target && target.line) {
      const l = target.line;
      marks.push(box({
        x: l.x - (l.w ? 0 : 1),
        y: l.y - (l.h ? 0 : 1),
        w: l.w || 3,
        h: l.h || 3,
      }, 'mark--line', 'line'));
    }
    if (target && target.box) {
      marks.push(box(target.box, 'mark--into', 'into'));
    }
    return marks;
  }

  render() {
    const { design, zoom, mode } = this.props;
    const w = design.width;
    const h = design.height;
    return (
      <div className="canvas">
        <div className="canvas__scroll">
          <div
            className="canvas__frame"
            style={{
              width: (w * zoom) + 'px',
              height: (h * zoom) + 'px',
            }}>
            <div
              className="canvas__scaler"
              style={{
                width: w + 'px',
                height: h + 'px',
                transform: 'scale(' + zoom + ')',
              }}>
              <iframe
                ref={this.frameRef}
                className="canvas__iframe"
                title="Window preview"
                src="/preview.html"
                width={w}
                height={h} />
              <div className="canvas__marks">
                {mode === 'design' && this.renderMarks()}
              </div>
            </div>
            <div
              className="canvas__resize"
              title="Drag to resize the window"
              onMouseDown={e => this.startResize(e)} />
            <div className="canvas__size">
              {w} × {h}
            </div>
          </div>
        </div>
      </div>
    );
  }
}
