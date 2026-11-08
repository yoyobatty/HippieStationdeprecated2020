/**
 * hippie -- this server's additions to tg's chat renderer: search, time
 * stamps, the "N new" count while scrolled up, and the menu on a speaker's
 * name. The renderer calls these at the points marked "hippie" in it.
 */

import { atom } from 'jotai';
import { store } from '../events/store';

/** Messages that came in while scrolled up (the new-messages pill) */
export const hippieNewCountAtom = atom(0);

let searchText = '';

function pad2(n: number): string {
  return (n < 10 ? '0' : '') + n;
}

/** A time stamp at the start of a new message; shown only with the setting */
export function addTimestamp(node: HTMLElement, createdAt: number): void {
  const when = new Date(createdAt || Date.now());
  const stamp = document.createElement('span');
  stamp.className = 'Hippie__time';
  stamp.textContent = `[${pad2(when.getHours())}:${pad2(when.getMinutes())}] `;
  node.insertBefore(stamp, node.firstChild);
}

export function setTimestampsShown(root: HTMLElement | null, shown: boolean) {
  root?.classList.toggle('Hippie--times', shown);
}

/** Hides a message node that doesn't match the search */
export function applySearch(node: HTMLElement): void {
  if (!searchText) {
    node.classList.remove('Hippie--filtered');
    return;
  }
  const text = (node.textContent || '').toLowerCase();
  node.classList.toggle('Hippie--filtered', !text.includes(searchText));
}

export function setSearch(text: string, messages: Array<{ node: any }>) {
  searchText = text.trim().toLowerCase();
  for (const message of messages) {
    if (message.node && message.node !== 'pruned') {
      applySearch(message.node);
    }
  }
}

export function getSearch(): string {
  return searchText;
}

export function countNew(added: number): void {
  if (added > 0) {
    store.set(hippieNewCountAtom, store.get(hippieNewCountAtom) + added);
  }
}

export function resetNew(): void {
  if (store.get(hippieNewCountAtom)) {
    store.set(hippieNewCountAtom, 0);
  }
}

// The name menu. The server says what's on it (hippie/nameMenu), so the page
// never decides who may do what.

const ACTION_LABELS: Record<string, string> = {
  examine: 'Examine',
  follow: 'Follow',
  pm: 'PM',
  player_panel: 'Player panel',
};

let menuNode: HTMLDivElement | null = null;
let menuAt = { x: 0, y: 0 };

export function closeNameMenu(): void {
  menuNode?.remove();
  menuNode = null;
}

/** A click in the chat: on a marked name, ask the server for its menu */
export function handleChatClick(event: MouseEvent): void {
  const target = event.target as HTMLElement | null;
  const name = target?.closest?.('.name[data-ref]') as HTMLElement | null;
  closeNameMenu();
  if (!name) {
    return;
  }
  event.preventDefault();
  event.stopPropagation();
  menuAt = { x: event.clientX, y: event.clientY };
  Byond.sendMessage('hippie/name', { ref: name.getAttribute('data-ref') });
}

type MenuPayload = { ref: string; name: string; actions: string[] };

export function openNameMenu(payload: MenuPayload): void {
  closeNameMenu();
  if (!payload?.actions?.length) {
    return;
  }
  const menu = document.createElement('div');
  menu.className = 'Hippie__nameMenu';
  const title = document.createElement('div');
  title.className = 'Hippie__nameMenuTitle';
  title.textContent = payload.name;
  menu.appendChild(title);
  for (const action of payload.actions) {
    const item = document.createElement('div');
    item.className = 'Hippie__nameMenuItem';
    item.textContent = ACTION_LABELS[action] || action;
    item.addEventListener('click', (e) => {
      e.stopPropagation();
      Byond.sendMessage('hippie/nameAct', { ref: payload.ref, action });
      closeNameMenu();
    });
    menu.appendChild(item);
  }
  document.body.appendChild(menu);
  // Keep it on screen
  const width = menu.offsetWidth;
  const height = menu.offsetHeight;
  const x = Math.min(menuAt.x, window.innerWidth - width - 4);
  const y = Math.min(menuAt.y, window.innerHeight - height - 4);
  menu.style.left = `${Math.max(0, x)}px`;
  menu.style.top = `${Math.max(0, y)}px`;
  menuNode = menu;
}

document.addEventListener('click', (e) => {
  if (menuNode && !menuNode.contains(e.target as Node)) {
    closeNameMenu();
  }
});
document.addEventListener('keydown', (e) => {
  if (e.key === 'Escape') {
    closeNameMenu();
  }
});
