import 'core-js/es';
import 'core-js/web/immediate';
import 'core-js/web/queue-microtask';
import 'core-js/web/timers';
import 'regenerator-runtime/runtime';
import './polyfills';

import { loadCSS } from 'fg-loadcss';
import { render } from 'inferno';
import { setupHotReloading } from 'tgui-dev-server/link/client';
import { backendUpdate } from './backend';
import { callByond, tridentVersion, winget } from './byond';
import { setupDrag } from './drag';
import { releaseHeldKeys } from './hotkeys';
import { createLogger } from './logging';
import { getRoute } from './routes';
import { createStore } from './store';

const logger = createLogger();
const store = createStore();
const reactRoot = document.getElementById('react-root');

let initialRender = true;
let handedOverToOldTgui = false;
// hippie -- a pooled window between UIs: nothing to draw
let released = !!window.__pool__;

const renderLayout = () => {
  // Short-circuit the renderer
  if (handedOverToOldTgui || released) {
    return;
  }
  // Mark the beginning of the render
  let startedAt;
  if (process.env.NODE_ENV !== 'production') {
    startedAt = Date.now();
  }
  try {
    const state = store.getState();
    // Initial render setup
    if (initialRender) {
      logger.log('initial render', state);

      // ----- Old TGUI chain-loader: begin -----
      const route = getRoute(state);
      // Route was not found, load old TGUI
      if (!route) {
        logger.info('loading old tgui');
        // Short-circuit the renderer
        handedOverToOldTgui = true;
        // Unsubscribe from updates
        window.update = window.initialize = () => {};
        // IE8: Use a redirection method
        // (tridentVersion is null on non-Trident engines, e.g. WebView2;
        // `null <= 4` is true in JS, so check must be explicit)
        if (tridentVersion !== null && tridentVersion <= 4) {
          setTimeout(() => {
            location.href = 'tgui-fallback.html?ref=' + window.__ref__;
          }, 10);
          return;
        }
        // Inject current state into the data holder
        const holder = document.getElementById('data');
        holder.textContent = JSON.stringify(state);
        // hippie -- old tgui takes the page for good, so a pooled window
        // is thrown away when it closes; it's shown here, as old tgui
        // won't
        if (window.__pool__) {
          holder.setAttribute('data-ref', state.config.ref);
          callByond('', { tgui_pool: window.__pool__, spent: 1 });
          showPooledWindow(state.config.window);
        }
        // Load old TGUI by injecting new scripts
        loadCSS('v4shim.css');
        loadCSS('tgui.css');
        const head = document.getElementsByTagName('head')[0];
        const script = document.createElement('script');
        script.type = 'text/javascript';
        script.src = 'tgui.js';
        head.appendChild(script);
        // Bail
        return;
      }
      // ----- Old TGUI chain-loader: end -----

      // Setup dragging
      setupDrag(state);
    }
    // Start rendering
    const { Layout } = require('./layout');
    const element = <Layout state={state} dispatch={store.dispatch} />;
    render(element, reactRoot);
  }
  catch (err) {
    logger.error('rendering error', err);
  }
  // Report rendering time
  if (process.env.NODE_ENV !== 'production') {
    const finishedAt = Date.now();
    const diff = finishedAt - startedAt;
    const diffFrames = (diff / 16.6667).toFixed(2);
    logger.debug(`rendered in ${diff}ms (${diffFrames} frames)`);
    if (initialRender) {
      const diff = finishedAt - window.__inception__;
      const diffFrames = (diff / 16.6667).toFixed(2);
      logger.log(`fully loaded in ${diff}ms (${diffFrames} frames)`);
    }
  }
  if (initialRender) {
    initialRender = false;
  }
};

// Parse JSON and report all abnormal JSON strings coming from BYOND
const parseStateJson = json => {
  let reviver = (key, value) => {
    if (typeof value === 'object' && value !== null) {
      if (value.__number__) {
        return parseFloat(value.__number__);
      }
    }
    return value;
  };
  // IE8: No reviver for you!
  // See: https://stackoverflow.com/questions/1288962
  // (tridentVersion is null on non-Trident engines, e.g. WebView2;
  // `null <= 4` is true in JS, so check must be explicit, else every
  // BYOND-encoded number silently fails to parse and rendering throws)
  if (tridentVersion !== null && tridentVersion <= 4) {
    reviver = undefined;
  }
  try {
    return JSON.parse(json, reviver);
  }
  catch (err) {
    logger.log(err);
    logger.log('What we got:', json);
    const msg = err && err.message;
    throw new Error('JSON parsing error: ' + msg);
  }
};

/**
 * hippie -- the window pool (hippiestation/code/modules/tgui/tgui_pool.dm).
 * A pooled window is a hidden window with this page already loaded. The
 * server hands it a UI with hippieMount (one message: no page load and no
 * tgui:initialize round trip), takes it back with hippieRelease and hides
 * it, and hands it the next UI later.
 */
const injectedHead = {};

// Centred on the game window, as a new popup would be, then shown
const showPooledWindow = async win => {
  try {
    const [pos, size, own] = await Promise.all([
      winget('mainwindow', 'pos'),
      winget('mainwindow', 'size'),
      winget(win, 'size'),
    ]);
    const x = Math.round(pos.x + (size.x - own.x) / 2);
    const y = Math.round(pos.y + (size.y - own.y) / 2);
    callByond('winset', {
      [`${win}.pos`]: `${Math.max(x, 0)},${Math.max(y, 0)}`,
    });
  }
  catch (err) {
    logger.log('could not centre the window', err);
  }
  callByond('winset', {
    [`${win}.is-visible`]: true,
    [`${win}.focus`]: true,
  });
  requestAnimationFrame(() => {
    window.__hippiePaintedAt__ = performance.timeOrigin + performance.now();
  });
};

window.hippieMount = json => {
  if (handedOverToOldTgui) {
    return;
  }
  const { head, state } = parseStateJson(json);
  window.__hippiePaintedAt__ = 0;
  window.__ref__ = state.config.ref;
  document.getElementById('data').setAttribute('data-ref', state.config.ref);
  // A window's own style sheets (sprite sheets): kept for the next UI
  if (head && !injectedHead[head]) {
    injectedHead[head] = true;
    document.head.insertAdjacentHTML('beforeend', head);
  }
  // The last UI's tree goes, and its state with it (store.js)
  render(null, reactRoot);
  released = false;
  initialRender = true;
  store.dispatch({ type: 'hippieMount', payload: state });
  window.__hippieMounts__ = (window.__hippieMounts__ || 0) + 1;
  if (!handedOverToOldTgui) {
    showPooledWindow(state.config.window);
  }
  // The server reopens the UI the old way if this never comes
  callByond('', { tgui_pool: window.__pool__, mounted: 1 });
};

window.hippieRelease = () => {
  if (handedOverToOldTgui) {
    return;
  }
  releaseHeldKeys();
  released = true;
  render(null, reactRoot);
  window.__ref__ = null;
  // Ready again. A window shut by its title bar's X has lost its page
  // (about:blank), so this never comes and the server throws it away
  callByond('', { tgui_pool: window.__pool__, ready: 1 });
};

const setupApp = () => {
  // Subscribe for redux state updates
  store.subscribe(() => {
    renderLayout();
  });

  // Subscribe for bankend updates
  window.update = window.initialize = stateJson => {
    // hippie -- a pooled window between UIs takes no updates
    if (released) {
      return;
    }
    const state = parseStateJson(stateJson);
    // Backend update dispatches a store action
    store.dispatch(backendUpdate(state));
  };

  // Enable hot module reloading
  if (module.hot) {
    setupHotReloading();
    module.hot.accept(['./layout', './routes'], () => {
      renderLayout();
    });
  }

  // Process the early update queue
  while (true) {
    let stateJson = window.__updateQueue__.shift();
    if (!stateJson) {
      break;
    }
    window.update(stateJson);
  }

  // Dynamically load font-awesome from browser's cache
  loadCSS('font-awesome.css');

  // hippie -- a pooled window tells the server it's ready for a UI
  if (window.__pool__) {
    callByond('', { tgui_pool: window.__pool__, ready: 1 });
  }
};

// IE8: Wait for DOM to properly load
const isOldTrident = tridentVersion !== null && tridentVersion <= 4;
if (isOldTrident && document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', setupApp);
}
else {
  setupApp();
}
