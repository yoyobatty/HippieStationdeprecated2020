# tgui6: tg's chat on Hippie

This folder is part of tgstation's `tgui/` workspace, pinned to the commit in `TG_COMMIT`. It holds only what the chat
(tgui-panel) needs: `common`, `tgui` (without tg's windows), `tgui-panel` and `tgui-dev-server`. The game's own windows
are still on `tgui-next/`.

- Fetch it again with `python tools/tgui6_sync/fetch.py [sha]`. That **overwrites the files listed below**, so diff them
  first and put the hippie parts back. Every change is marked `hippie` in the file.
- After fetching Font Awesome again (`assets/font-awesome`), run `python tools/tgui6_sync/trim_fa.py`.
- Build: `bun install` once, then `bun run tgui:build`, which writes `public/tgui-panel.bundle.{js,css}`. Those two are
  committed, so a server needs no build step. **Recompile the DM afterwards**: they go into the .rsc.

The DM side is in `hippiestation/code/modules/tgui_panel/`.

## Changed tg files

- `rspack.config.ts`: only the tgui-panel entry is built, and fonts are inlined into the CSS.
- `packages/tgui-panel/index.tsx`:
  - imports Font Awesome and `hippie/hippie.scss`;
  - drops tg's skin winsets (our skin has no `output_selector`; the server shows `browseroutput`).
- `packages/tgui-panel/chat/handlers.ts`: `acceptChatMessage()` is split out for `hippie/messages` batches.
- `packages/tgui-panel/chat/atom.ts`: the default tabs are All, Local, Radio, OOC and Combat; Admin is added for admins.
- `packages/tgui-panel/chat/constants.ts`: this server's classes are mapped to message types (`.looc`, `.userdanger` as
  combat, `.mentornotice`, `.mentor`, `.prayer`).
- `packages/tgui-panel/chat/renderer.tsx`: hooks for the PM text rule, time stamps, search, the new-messages count and
  the name menu.
- `packages/tgui-panel/chat/model.ts`: adds the `hippieHistory` message flag.
- `packages/tgui-panel/chat/ChatPanel.tsx`: the time stamp setting, and the "N new" pill.
- `packages/tgui-panel/chat/use-chat-persistence.ts`:
  - saved messages aren't restored (the server sends this round's back);
  - a saved layout that is only Main (plus Admin) gets our tabs.
- `packages/tgui-panel/events/listeners.ts`: adds the `hippie/*` handlers.
- `packages/tgui-panel/Panel.tsx`: the search button and box.
- `packages/tgui-panel/settings/{atoms,types}.ts`, `SettingsGeneral.tsx`: dark theme by default, and the time stamp
  setting.
- `assets/font-awesome/all.min.css`: trimmed to FA6's two @font-face rules (`trim_fa.py`).

## Our own files

- `packages/tgui-panel/hippie/`
- `public/hippie-loader.js`
- `assets/font-awesome/*.ttf` (tg's, copied in)
