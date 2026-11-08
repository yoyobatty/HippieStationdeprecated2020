import { atom } from 'jotai';
import {
  MESSAGE_TYPE_ADMINCHAT,
  MESSAGE_TYPE_ADMINLOG,
  MESSAGE_TYPE_ADMINPM,
  MESSAGE_TYPE_ATTACKLOG,
  MESSAGE_TYPE_COMBAT,
  MESSAGE_TYPE_DEADCHAT,
  MESSAGE_TYPE_DEBUG,
  MESSAGE_TYPE_LOCALCHAT,
  MESSAGE_TYPE_MODCHAT,
  MESSAGE_TYPE_OOC,
  MESSAGE_TYPE_PRAYER,
  MESSAGE_TYPE_RADIO,
  MESSAGE_TYPE_SYSTEM,
  MESSAGE_TYPES,
} from './constants';
import { createMainPage, createPage } from './model';
import type { Page } from './types';

// hippie -- the tabs the old chat had: All, Local, Radio, OOC, Combat (and
// Admin for admins, added by hippie/admin). Saved tabs replace these.
export const mainPage = { ...createMainPage(), name: 'All' };

function hippiePage(id: string, name: string, types: string[]): Page {
  const acceptedTypes = {};
  for (const typeDef of MESSAGE_TYPES) {
    acceptedTypes[typeDef.type] =
      types.includes(typeDef.type) || typeDef.type === MESSAGE_TYPE_SYSTEM;
  }
  return createPage({ id, name, acceptedTypes });
}

const defaultPages = [
  mainPage,
  hippiePage('hippie-local', 'Local', [
    MESSAGE_TYPE_LOCALCHAT,
    MESSAGE_TYPE_DEADCHAT,
  ]),
  hippiePage('hippie-radio', 'Radio', [MESSAGE_TYPE_RADIO]),
  hippiePage('hippie-ooc', 'OOC', [MESSAGE_TYPE_OOC, MESSAGE_TYPE_ADMINPM]),
  hippiePage('hippie-combat', 'Combat', [MESSAGE_TYPE_COMBAT]),
];

export const HIPPIE_ADMIN_PAGE_ID = 'hippie-admin';

export function createHippieAdminPage(): Page {
  return hippiePage(HIPPIE_ADMIN_PAGE_ID, 'Admin', [
    MESSAGE_TYPE_ADMINCHAT,
    MESSAGE_TYPE_MODCHAT,
    MESSAGE_TYPE_ADMINPM,
    MESSAGE_TYPE_ADMINLOG,
    MESSAGE_TYPE_ATTACKLOG,
    MESSAGE_TYPE_PRAYER,
    MESSAGE_TYPE_DEBUG,
  ]);
}

export const versionAtom = atom(5);
export const scrollTrackingAtom = atom(true);
export const chatPagesAtom = atom(defaultPages.map((page) => page.id));
export const currentPageIdAtom = atom(mainPage.id);
export const chatPagesRecordAtom = atom(
  Object.fromEntries(defaultPages.map((page) => [page.id, page])) as Record<
    string,
    Page
  >,
);

/** Chat has been initialized from storage */
export const chatLoadedAtom = atom(false);

export const allChatAtom = atom((get) => ({
  version: get(versionAtom),
  currentPageId: get(currentPageIdAtom),
  scrollTracking: get(scrollTrackingAtom),
  pages: get(chatPagesAtom),
  pageById: get(chatPagesRecordAtom),
}));

export const currentPageAtom = atom((get) => {
  const pageId = get(currentPageIdAtom);
  const pagesById = get(chatPagesRecordAtom);
  return pagesById[pageId];
});
