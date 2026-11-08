/**
 * @file
 * @copyright 2020 Aleksej Komarov
 * @license MIT
 */

import '../../assets/font-awesome/all.min.css'; // hippie -- inlined (fonts and all), see rspack.config.ts
import './styles/main.scss';
import './styles/themes/light.scss';
import './hippie/hippie.scss';

import { createRoot } from 'react-dom/client';
import { setupGlobalEvents } from 'tgui-core/events';
import { captureExternalLinks } from 'tgui-core/links';
import { setupHotReloading } from 'tgui-dev-server/link/client';
import { App } from './app';
import { bus } from './events/listeners';
import { setupPanelFocusHacks } from './panelFocus';
import { wsSend } from './websocket/helpers';

const root = createRoot(document.getElementById('react-root')!);

function render(component: React.ReactElement) {
  root.render(component);
}

function setupApp() {
  // Delay setup
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', setupApp);
    return;
  }

  setupGlobalEvents({
    ignoreWindowFocus: true,
  });

  setupPanelFocusHacks();
  captureExternalLinks();

  render(<App />);

  // Dispatch incoming messages as store actions
  Byond.subscribe((type, payload) => {
    bus.dispatch({ type, payload });
    wsSend({ type, payload });
  });

  // hippie -- our skin has no output_selector/output_browser: the server shows browseroutput over the old output once
  // the page says it's ready (/datum/chatOutput/proc/showChat)

  // Enable hot module reloading
  if (import.meta.webpackHot) {
    setupHotReloading();

    import.meta.webpackHot.accept(['./app'], () => {
      render(<App />);
    });
  }
}

setupApp();
