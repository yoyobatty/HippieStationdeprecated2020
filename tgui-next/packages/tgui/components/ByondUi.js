import { shallowDiffers } from 'common/react';
import { Component, createRef } from 'inferno';
import { callByond } from '../byond';
import { createLogger } from '../logging';
import { computeBoxProps } from './Box';

// hippie -- a BYOND skin control (a map) laid over part of the page, kept in
// place as the window moves and resizes. Ported from tgstation's tgui ByondUi
// (2020). The control is a child of this tgui window: params are its winset
// properties, with `parent` the window's id (config.window).

const logger = createLogger('ByondUi');

// The controls this page has made, to take them all away when it unloads
const byondUiStack = [];

const winsetMany = (id, params) => callByond('winset', { ...params, id });

const createByondUiElement = elementId => {
  const index = byondUiStack.length;
  byondUiStack.push(null);
  const id = elementId || 'byondui_' + index;
  logger.log(`allocated '${id}'`);
  return {
    render: params => {
      byondUiStack[index] = id;
      winsetMany(id, params);
    },
    unmount: () => {
      logger.log(`unmounting '${id}'`);
      byondUiStack[index] = null;
      winsetMany(id, { parent: '' });
    },
  };
};

window.addEventListener('beforeunload', () => {
  for (let index = 0; index < byondUiStack.length; index++) {
    const id = byondUiStack[index];
    if (typeof id === 'string') {
      byondUiStack[index] = null;
      winsetMany(id, { parent: '' });
    }
  }
});

const getBoundingBox = element => {
  const pixelRatio = window.devicePixelRatio || 1;
  const rect = element.getBoundingClientRect();
  return {
    pos: [
      Math.round(rect.left * pixelRatio),
      Math.round(rect.top * pixelRatio),
    ],
    size: [
      Math.round((rect.right - rect.left) * pixelRatio),
      Math.round((rect.bottom - rect.top) * pixelRatio),
    ],
  };
};

export class ByondUi extends Component {
  constructor(props) {
    super(props);
    this.containerRef = createRef();
    this.byondUiElement = createByondUiElement(
      props.params && props.params.id);
    this.resizeTimer = null;
    this.handleResize = () => {
      clearTimeout(this.resizeTimer);
      this.resizeTimer = setTimeout(() => this.forceUpdate(), 100);
    };
  }

  shouldComponentUpdate(nextProps) {
    const { params: prevParams = {}, ...prevRest } = this.props;
    const { params: nextParams = {}, ...nextRest } = nextProps;
    return shallowDiffers(prevParams, nextParams)
      || shallowDiffers(prevRest, nextRest);
  }

  componentDidMount() {
    window.addEventListener('resize', this.handleResize);
    this.componentDidUpdate();
    this.handleResize();
  }

  componentDidUpdate() {
    const { params = {} } = this.props;
    const box = getBoundingBox(this.containerRef.current);
    this.byondUiElement.render({
      ...params,
      pos: box.pos[0] + ',' + box.pos[1],
      size: box.size[0] + 'x' + box.size[1],
    });
  }

  componentWillUnmount() {
    window.removeEventListener('resize', this.handleResize);
    clearTimeout(this.resizeTimer);
    this.byondUiElement.unmount();
  }

  render() {
    const { params, ...rest } = this.props;
    const boxProps = computeBoxProps(rest);
    return (
      <div ref={this.containerRef} {...boxProps}>
        <div style={{ 'min-height': '22px' }} />
      </div>
    );
  }
}
