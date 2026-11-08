/**
 * hippie -- messages only this server sends the chat
 * (hippiestation/code/modules/tgui_panel/tgui_panel.dm).
 */

import {
  chatPagesAtom,
  chatPagesRecordAtom,
  createHippieAdminPage,
  HIPPIE_ADMIN_PAGE_ID,
} from '../chat/atom';
import { acceptChatMessage } from '../chat/handlers';
import { chatRenderer } from '../chat/renderer';
import { store } from '../events/store';
import { hippieAdminAtom } from './atoms';

type Sequenced = { sequence: number; content: Record<string, unknown> };

/** A tick's messages for this player in one output, oldest first */
export function hippieMessages(batch: Sequenced[]): void {
  if (!Array.isArray(batch)) {
    return;
  }
  for (const message of batch) {
    if (message && typeof message.sequence === 'number') {
      acceptChatMessage(message);
    }
  }
}

/**
 * This round's last messages for a page that just loaded (a reconnect, Fix
 * Chat): the browser forgets everything between launches on 516, the server
 * doesn't. They go above anything already shown, under a marker.
 */
export function hippieHistory(payload: { messages: string[] }): void {
  const messages = payload?.messages;
  if (!Array.isArray(messages) || !messages.length) {
    return;
  }
  const batch = messages.map((html) => ({
    html,
    avoidHighlighting: true,
    hippieHistory: true,
  }));
  batch.push({
    html: '<div class="Hippie__historyMark">Earlier this round</div>',
    avoidHighlighting: true,
    hippieHistory: true,
  });
  chatRenderer.processBatch(batch, {
    prepend: true,
    suppressHighlightSound: true,
    notifyListeners: false,
  });
}

/** Whether this player is an admin: an admin gets an Admin tab, once */
export function hippieAdmin(payload: { admin: boolean }): void {
  const admin = !!payload?.admin;
  store.set(hippieAdminAtom, admin);
  if (!admin) {
    return;
  }
  const pages = store.get(chatPagesAtom);
  if (pages.includes(HIPPIE_ADMIN_PAGE_ID)) {
    return;
  }
  const page = createHippieAdminPage();
  store.set(chatPagesAtom, [...pages, page.id]);
  store.set(chatPagesRecordAtom, {
    ...store.get(chatPagesRecordAtom),
    [page.id]: page,
  });
}
