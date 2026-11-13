// The stat panel: tg's statbrowser.js (tgstation master ceb0ca2410d4b2bbade05f61a661ebdd684c0e79), on Hippie's 516 bridge.
// Hippie: a small Byond shim instead of tgui's window bridge; spell and ability tabs, the text tabs some gear adds (SpiderOS,
// Crynet Nanosuit), a verb search, Status as label/value rows, the theme from the skin, tabs reported to the server in one message.
// Hippie, making the game easier to get around (the user's rulings, 2026-11-07): small tabs folded together (admin odds and ends
// into Admin and Debug as sections, anyone's tab of three verbs or fewer into Other), the tab you picked kept across rounds, the
// open tickets counted on Tickets and a dot on a tab that gets new verbs, the search's Enter running the top verb (arrows pick
// another, the ones you used lately first), and a Menu button (the game menu, as Esc with the chat bar empty).

// The bridge ----------------------------------------------------------------
var Byond = (function () {
  var subscriptions = {};
  function post(uri) {
    if (window.chrome && window.chrome.webview) {
      window.chrome.webview.postMessage(uri);
    } else {
      window.location.href = uri;
    }
  }
  function params(obj) {
    var out = [];
    for (var key in obj) {
      out.push(encodeURIComponent(key) + '=' + encodeURIComponent(obj[key]));
    }
    return out.join('&');
  }
  return {
    windowId: 'statbrowser',
    subscribeTo: function (type, fn) {
      subscriptions[type] = fn;
    },
    receive: function (type, payload) {
      var fn = subscriptions[type];
      if (fn) {
        fn(payload);
      }
    },
    sendMessage: function (type, payload) {
      var uri = 'byond://?_src_=statpanel&type=' + encodeURIComponent(type);
      if (payload !== undefined) {
        uri += '&payload=' + encodeURIComponent(JSON.stringify(payload));
      }
      post(uri);
    },
    command: function (command) {
      post('byond://winset?command=' + encodeURIComponent(command));
    },
    winset: function (id, settings) {
      var list = {};
      for (var key in settings) {
        list[(id ? id + '.' : '') + key] = settings[key];
      }
      post('byond://winset?' + params(list));
    },
    topic: function (query) {
      post('byond://?' + query);
    },
  };
})();

// The server's messages: output(url_encode(url_encode(json)), "statbrowser:byondMessage"), twice so UTF-8 comes through.
function byondMessage(raw) {
  var message;
  try {
    message = JSON.parse(decodeURIComponent(raw.replace(/\+/g, '%20')));
  } catch (e) {
    return;
  }
  Byond.receive(message.type, message.payload);
}

// Polyfills and compatibility ------------------------------------------------
var decoder = decodeURIComponent || unescape;

// Status panel implementation ------------------------------------------------
var current_tab = null;
var mc_data = null; // hippie: the MC tab's numbers (statpanels.dm generate_mc_data()), see draw_mc()
var mc_loc = '';
var href_token = null;
var verb_tabs = [];
var verbs = [['', '']]; // list with a list inside
var tickets = [];
var sdql2 = [];
var permanent_tabs = []; // tabs that won't be cleared by wipes
var turfcontents = []; // hippie: rows of name, ref, picture key, how many alike
var turfmore = 0; // hippie: things past the last row
var turficons = {}; // hippie: picture key -> data URI, each sent once
var turfname = '';
var spells = []; // hippie: [panel, charge text, name, ref]
var spell_tabs = [];
var extra_tabs = {}; // hippie: tab name -> lines, drawn like Status
var search_text = '';
var tab_before_search = null;
var menu = document.getElementById('menu');
var statcontentdiv = document.getElementById('statcontent');
var split_admin_tabs = false;
//The 'default' tab that everyone should have, that we swap to if the tab you're on is deleted or anything similar.
var defaultTab = 'Status';
var SEARCH_TAB = '__search';
// hippie: folding. Tabs never folded; admin odds and ends folded into a parent as sections; the rest fold into Other at this size.
var CORE_TABS = ['IC', 'OOC', 'Object', 'Preferences', 'Admin', 'Debug', 'Ghost', 'Mentor'];
var FOLD_INTO = {
  'Fun': 'Admin',
  'Special Verbs': 'Admin',
  'Server': 'Admin',
  'Prefs - Admin': 'Admin',
  'Event': 'Admin',
  'Mapping': 'Debug',
  'Profile': 'Debug',
};
var FOLD_SMALL = 3;
var OTHER_TAB = 'Other';
// hippie: the tab the server says was picked last round, until it exists or the player picks one
var wanted_tab = null;
// hippie: the search's results, the one Enter runs, and the verbs used lately (newest first)
var search_found = [];
var search_index = 0;
var recent_verbs = [];
try {
  recent_verbs = JSON.parse(window.localStorage.getItem('recent_verbs') || '[]') || [];
} catch (e) {
  recent_verbs = [];
}

// Any BYOND commands that could result in the client's focus changing go through this
// to ensure that when we relinquish our focus, we don't do it after the result of
// a command has already taken focus for itself.
function run_after_focus(callback) {
  setTimeout(callback, 0);
}

function tabButtonId(name) {
  return 'tab-' + name;
}

function createStatusTab(name) {
  if (name.indexOf('.') != -1) {
    var splitName = name.split('.');
    if (split_admin_tabs && splitName[0] === 'Admin') name = splitName[1];
    else name = splitName[0];
  }
  if (document.getElementById(tabButtonId(name)) || name.trim() == '') {
    return;
  }
  if (!verb_tabs.includes(name) && !permanent_tabs.includes(name)) {
    return;
  }
  var button = document.createElement('DIV');
  button.onclick = function () {
    clearSearch(true);
    wanted_tab = null;
    tab_change(name, true);
    this.blur();
    statcontentdiv.focus();
  };
  button.id = tabButtonId(name);
  button.setAttribute('data-tab', name);
  button.textContent = name;
  button.className = name == current_tab ? 'button active' : 'button';
  button.title = name == OTHER_TAB ? 'Tabs with only a few verbs' : '';
  //ORDERING ALPHABETICALLY
  button.style.order = { Status: 1, MC: 2, Tickets: 3 }[name] || name.charCodeAt(0);
  //END ORDERING
  if (name == OTHER_TAB) button.style.order = 900;
  menu.insertBefore(button, document.getElementById('verbsearch'));
  if (wanted_tab == name) {
    wanted_tab = null;
    tab_change(name);
  }
}

// hippie: a count on a tab (Tickets), red when someone is waiting
function setTabBadge(name, count, hot) {
  var button = document.getElementById(tabButtonId(name));
  if (!button) return;
  var badge = button.querySelector('.tab-badge');
  if (!count) {
    if (badge) button.removeChild(badge);
    return;
  }
  if (!badge) {
    badge = document.createElement('span');
    button.appendChild(badge);
  }
  badge.className = 'tab-badge' + (hot ? ' hot' : '');
  badge.textContent = count;
}

// hippie: a dot on a tab that got something new while another was open
function markTab(name) {
  var button = document.getElementById(tabButtonId(name));
  if (button && name != current_tab) button.classList.add('changed');
}

// hippie: which tab a verb goes in. Folding is worked out from every verb the player has (part[2] is its own category).
function refold() {
  var counts = {};
  for (var i = 0; i < verbs.length; i++) {
    var raw = verbs[i][2] || verbs[i][0];
    if (!raw) continue;
    var base = raw.split('.')[0];
    counts[base] = (counts[base] || 0) + 1;
  }
  var tabs = [];
  for (var v = 0; v < verbs.length; v++) {
    var part = verbs[v];
    if (!part[1]) continue;
    if (!part[2]) part[2] = part[0];
    var own = part[2].split('.')[0];
    var into = FOLD_INTO[own];
    if (!into && !CORE_TABS.includes(own) && counts[own] <= FOLD_SMALL) into = OTHER_TAB;
    part[0] = into ? into + '.' + own : part[2];
    var tab = part[0].split('.')[0];
    if (!tabs.includes(tab)) tabs.push(tab);
  }
  tabs.sort();
  for (var t = verb_tabs.length - 1; t >= 0; t--) {
    if (!tabs.includes(verb_tabs[t])) removeStatusTab(verb_tabs[t]);
  }
  verb_tabs = tabs;
  for (var c = 0; c < verb_tabs.length; c++) createStatusTab(verb_tabs[c]);
  if (current_tab && verb_tabs.indexOf(current_tab) == -1 && !permanent_tabs.includes(current_tab)
    && !spell_tabs.includes(current_tab) && !extra_tabs[current_tab] && current_tab != SEARCH_TAB
    && current_tab != turfname) {
    tab_change(defaultTab);
  }
}

function removeStatusTab(name) {
  var button = document.getElementById(tabButtonId(name));
  if (!button || permanent_tabs.includes(name)) {
    return;
  }
  for (var i = verb_tabs.length - 1; i >= 0; --i) {
    if (verb_tabs[i] == name) {
      verb_tabs.splice(i, 1);
    }
  }
  menu.removeChild(button);
}

function sortVerbs() {
  verbs.sort((a, b) => {
    var selector = a[0] == b[0] ? 1 : 0;
    if (a[selector].toUpperCase() < b[selector].toUpperCase()) {
      return 1;
    } else if (a[selector].toUpperCase() > b[selector].toUpperCase()) {
      return -1;
    }
    return 0;
  });
}

function addPermanentTab(name) {
  if (!permanent_tabs.includes(name)) {
    permanent_tabs.push(name);
  }
  createStatusTab(name);
}

function removePermanentTab(name) {
  for (var i = permanent_tabs.length - 1; i >= 0; --i) {
    if (permanent_tabs[i] == name) {
      permanent_tabs.splice(i, 1);
    }
  }
  removeStatusTab(name);
}

function checkStatusTab() {
  for (var i = menu.children.length - 1; i >= 0; i--) {
    var tab = menu.children[i].getAttribute('data-tab');
    if (!tab) {
      continue;
    }
    if (!verb_tabs.includes(tab) && !permanent_tabs.includes(tab)) {
      menu.removeChild(menu.children[i]);
    }
  }
}

function remove_verb(v) {
  var verb_to_remove = v; // to_remove = [verb:category, verb:name]
  for (var i = verbs.length - 1; i >= 0; i--) {
    var part_to_remove = verbs[i];
    if (part_to_remove[1] == verb_to_remove[1]) {
      verbs.splice(i, 1);
    }
  }
}

function findVerbindex(name, verblist) {
  for (var i = 0; i < verblist.length; i++) {
    var part = verblist[i];
    if (part[1] == name) return i;
  }
}
function wipe_verbs() {
  verbs = [['', '']];
  verb_tabs = [];
  checkStatusTab(); // remove all empty verb tabs
}

function tab_change(tab, picked) {
  if (tab == current_tab) {
    draw_tab(tab);
    return;
  }
  var last = document.getElementById(tabButtonId(current_tab));
  if (last) last.classList.remove('active'); // disable active on last button
  current_tab = tab;
  if (tab != SEARCH_TAB) {
    set_byond_tab(tab, picked);
  }
  var button = document.getElementById(tabButtonId(tab));
  if (button) {
    button.classList.add('active'); // make current button active
    button.classList.remove('changed');
  }
  draw_tab(tab);
}

function draw_tab(tab) {
  statcontentdiv.className = 'statcontent';
  if (tab == SEARCH_TAB) {
    draw_search();
  } else if (tab == 'Status') {
    draw_status();
  } else if (tab == 'MC') {
    draw_mc();
  } else if (tab == 'Tickets') {
    draw_tickets();
  } else if (tab == 'SDQL2') {
    draw_sdql2();
  } else if (tab == turfname) {
    draw_listedturf();
  } else if (extra_tabs[tab]) {
    draw_extra(tab);
  } else if (spell_tabs.includes(tab) || verb_tabs.includes(tab)) {
    statcontentdiv.textContent = '';
    if (spell_tabs.includes(tab)) draw_spells(tab);
    if (verb_tabs.includes(tab)) draw_verbs(tab, true);
  } else {
    statcontentdiv.textContent = 'Loading...';
  }
}

function set_byond_tab(tab, picked) {
  Byond.sendMessage('Set-Tab', picked ? { tab: tab, picked: 1 } : { tab: tab });
}

// hippie: Status. The round at the top: its time and the station's, the shuttle while it's coming, docked or leaving, the
// lobby's countdown; the map, round, server time, time dilation and ping under them. Then the player's ahelp or question,
// then what their mob says about itself. That can be anything (a cyborg's cell, a blob's power, the AI's cyborgs, a
// guardian's cooldowns), so each item is drawn by its shape (st_norm()): "Label: value" in two columns, a value like 12/50,
// 12/50E, 80% or 3 of 5 as a bar, "Title | Key: value | ..." as a card, other text as a note; a mob that needs more sends
// bars, cooldowns, notes, cards and foldable sections as lists (stat_panel.dm stat_bar() and the rest). Gear tabs (SpiderOS,
// the nanosuit) are drawn the same way. A wide panel puts the round and the mob side by side. The page is built once and
// changed in place, so a click isn't lost to the next update.
var status_data = null;
var status_view = null;
var extra_view = null;
var status_folded = {};
try {
  status_folded = JSON.parse(window.localStorage.getItem('status_folded') || '{}') || {};
} catch (e) {
  status_folded = {};
}
var SHUTTLE_LEVELS = { ETA: 'average', ETD: 'good', ESC: 'info', LDN: 'info', IGN: 'average', ERR: 'bad', DIS: 'bad' };
var VITAL_LABEL = /health|integrity|charge|power|cell|energy|battery/i;

function st_num(n) {
  return Number.isInteger(n) || Math.abs(n) >= 100 ? String(Math.round(n)) : n.toFixed(1);
}

function st_secs(s) {
  s = Math.max(0, Math.round(s));
  return s >= 60 ? Math.floor(s / 60) + ':' + ('0' + (s % 60)).slice(-2) : s + ' s';
}

// Any item a mob sends, as one of: gap, section, row, link, bar, cooldown, note, card
function st_norm(item) {
  if (item === null || item === undefined) return null;
  if (Array.isArray(item)) {
    // [text, link text, href]: the ahelp line, tg's statclick links
    var base = String(item[0]).trim();
    return { t: 'link', label: base == 'same_line' ? '' : base, text: String(item[1] || ''), href: item[2] };
  }
  if (typeof item == 'object') return item.t ? item : null;
  var text = String(item);
  if (!text.trim()) return { t: 'gap' };
  var parts = text.split(' | ');
  if (parts.length >= 3) {
    var fields = [];
    for (var i = 1; i < parts.length; i++) {
      var at = parts[i].indexOf(': ');
      fields.push(at > 0 ? [parts[i].substring(0, at), parts[i].substring(at + 2)] : ['', parts[i]]);
    }
    return { t: 'card', title: parts[0], fields: fields };
  }
  var split = text.indexOf(': ');
  if (split > 0 && split < 40) {
    var label = text.substring(0, split);
    var value = text.substring(split + 2).trim();
    var m = value.match(/^(-?\d+(?:\.\d+)?)\s*\/\s*(\d+(?:\.\d+)?)\s*([A-Za-z]{0,3})$/) || value.match(/^(\d+) of (\d+)()$/);
    if (m && Number(m[2]) > 0) return { t: 'bar', label: label, value: Number(m[1]), max: Number(m[2]), unit: m[3] };
    m = value.match(/^(-?\d+(?:\.\d+)?)\s*%$/);
    if (m) return { t: 'bar', label: label, value: Number(m[1]), max: 100, unit: '%' };
    return { t: 'row', label: label, value: value };
  }
  return { t: 'note', text: text };
}

function st_key(n) {
  return n.t + ':' + (n.label || n.title || n.text || '');
}

function st_level(n) {
  if (n.level) return n.level;
  if (n.t == 'bar' && VITAL_LABEL.test(n.label)) {
    var f = n.max ? n.value / n.max : 0;
    return f >= 0.5 ? 'good' : f >= 0.25 ? 'average' : 'bad';
  }
  return '';
}

function st_meter() {
  var meter = mc_el('span', 'st-meter');
  meter.fill = mc_el('span', 'st-fill');
  meter.appendChild(meter.fill);
  return meter;
}

function st_set_meter(meter, fraction, level) {
  meter.fill.style.width = Math.max(0, Math.min(100, fraction * 100)).toFixed(1) + '%';
  mc_class(meter.fill, 'st-fill' + (level ? ' ' + level : ''));
}

// One item's element, and how to change it in place when the next update brings the same item
function st_make(n) {
  var v = { key: st_key(n), update: function () {} };
  if (n.t == 'gap') {
    v.el = mc_el('div', 'st-gap');
  } else if (n.t == 'section') {
    v.el = mc_el('div', 'st-section', n.title);
    v.el.dataset.fold = n.title;
  } else if (n.t == 'note') {
    v.el = mc_el('div', 'st-note');
    v.update = (x) => {
      mc_set(v.el, x.text);
      mc_class(v.el, 'st-note' + (x.level ? ' ' + x.level : ''));
    };
  } else if (n.t == 'card') {
    v.el = mc_el('div', 'st-card');
    var title = mc_el('div', 'st-card-title');
    var body = mc_el('div', 'st-card-fields');
    v.el.appendChild(title);
    v.el.appendChild(body);
    v.update = (x) => {
      mc_set(title, x.title);
      var html = (x.fields || []).map((f) => [f[0], f[1]].join('\u0001')).join('\u0002');
      if (body.dataset.was !== html) {
        body.dataset.was = html;
        body.textContent = '';
        (x.fields || []).forEach((f) => {
          var field = mc_el('span', 'st-field');
          if (f[0]) field.appendChild(mc_el('span', 'st-field-key', f[0]));
          var val = mc_el('span', 'st-field-value', String(f[1]));
          if (/^[A-Z][A-Z ]{2,}$/.test(String(f[1]).trim())) val.classList.add('average'); // OFFLINE, DEPOWERED
          field.appendChild(val);
          body.appendChild(field);
        });
      }
      mc_class(v.el, 'st-card' + (x.level ? ' ' + x.level : ''));
    };
  } else {
    // row, link, bar, cooldown: a label, then the value
    v.el = mc_el('div', 'st-row');
    var lab = mc_el('span', 'st-label');
    var val2 = mc_el('span', 'st-value');
    v.el.appendChild(lab);
    v.el.appendChild(val2);
    if (n.t == 'link') {
      var text = mc_el('span');
      var a = mc_el('a');
      a.href = '#';
      val2.appendChild(text);
      val2.appendChild(a);
      v.update = (x) => {
        mc_set(lab, x.label);
        mc_set(a, x.text);
        a.dataset.href = x.href || '';
      };
    } else if (n.t == 'bar' || n.t == 'cooldown') {
      var meter = st_meter();
      var figure = mc_el('span', 'st-figure');
      val2.appendChild(meter);
      val2.appendChild(figure);
      v.update = (x) => {
        mc_set(lab, x.label);
        if (x.t == 'bar') {
          var level = st_level(x);
          st_set_meter(meter, x.max ? x.value / x.max : 0, level);
          mc_set(figure, x.unit == '%' ? st_num(x.value) + '%' : st_num(x.value) + '/' + st_num(x.max) + (x.unit || ''));
          mc_class(figure, 'st-figure' + (level ? ' ' + level : ''));
        } else {
          meter.style.display = x.total ? '' : 'none';
          if (x.total) st_set_meter(meter, x.left / x.total, x.left > 0 ? 'average' : 'good');
          mc_set(figure, x.left > 0 ? st_secs(x.left / 10) : 'Ready');
          mc_class(figure, 'st-figure ' + (x.left > 0 ? 'average' : 'good'));
        }
      };
    } else {
      v.update = (x) => {
        mc_set(lab, x.label);
        mc_set(val2, String(x.value));
      };
    }
  }
  return v;
}

// The items into a container, in place: an item that's the same kind with the same label as last time is only changed
function st_sync(container, cache, items) {
  var list = [];
  for (var i = 0; i < (items || []).length; i++) {
    var n = st_norm(items[i]);
    if (n) list.push(n);
  }
  var folded = false;
  for (var j = 0; j < list.length; j++) {
    var item = list[j];
    var v = cache[j];
    if (!v || v.key != st_key(item)) {
      var made = st_make(item);
      if (v) {
        container.replaceChild(made.el, v.el);
      } else {
        container.appendChild(made.el);
      }
      cache[j] = v = made;
    }
    v.update(item);
    if (item.t == 'section') {
      folded = !!status_folded[item.title];
      v.el.classList.toggle('folded', folded);
    } else {
      v.el.style.display = folded ? 'none' : '';
    }
  }
  while (cache.length > list.length) {
    cache.pop().el.remove();
  }
  return list.length;
}

function st_click(e) {
  var link = e.target.closest('[data-href]');
  if (link) {
    e.preventDefault();
    if (link.dataset.href) Byond.topic(link.dataset.href);
    return;
  }
  var fold = e.target.closest('[data-fold]');
  if (fold) {
    var title = fold.dataset.fold;
    if (status_folded[title]) {
      delete status_folded[title];
    } else {
      status_folded[title] = 1;
    }
    try {
      window.localStorage.setItem('status_folded', JSON.stringify(status_folded));
    } catch (err) {}
    draw_tab(current_tab);
  }
}

function st_tile(label) {
  var t = mc_el('div', 'st-tile');
  t.label = mc_el('div', 'st-tile-label', label);
  t.value = mc_el('div', 'st-tile-value');
  t.appendChild(t.label);
  t.appendChild(t.value);
  return t;
}

function st_build() {
  var v = { items: [], help: [] };
  v.root = mc_el('div', 'st');
  v.root.onclick = st_click;
  v.round = mc_el('div', 'st-round');
  v.tiles = mc_el('div', 'st-tiles');
  v.tile_time = st_tile('Round');
  v.tile_station = st_tile('Station');
  v.tile_shuttle = st_tile('Shuttle');
  v.tiles.appendChild(v.tile_time);
  v.tiles.appendChild(v.tile_station);
  v.tiles.appendChild(v.tile_shuttle);
  v.round.appendChild(v.tiles);
  v.meta = mc_el('div', 'st-meta');
  v.meta2 = mc_el('div', 'st-meta');
  v.round.appendChild(v.meta);
  v.round.appendChild(v.meta2);
  v.helpbox = mc_el('div', 'st-help');
  v.round.appendChild(v.helpbox);
  v.root.appendChild(v.round);
  v.mine = mc_el('div', 'st-mine');
  v.root.appendChild(v.mine);
  return v;
}

// "Label value" pieces for a meta line, each in its own span so one can be coloured
function st_meta(line, pieces) {
  var text = pieces.map((p) => p[0] + '\u0001' + p[1] + '\u0001' + (p[2] || '')).join('\u0002');
  if (line.dataset.was === text) return;
  line.dataset.was = text;
  line.textContent = '';
  pieces.forEach((p, i) => {
    if (i) line.appendChild(document.createTextNode(' · '));
    var span = mc_el('span', p[2] || '');
    if (p[0]) span.appendChild(mc_el('span', 'st-meta-key', p[0] + ' '));
    span.appendChild(mc_el('span', 'st-meta-value', p[1]));
    if (p[3]) span.title = p[3];
    line.appendChild(span);
  });
}

function draw_status() {
  if (!document.getElementById(tabButtonId('Status'))) {
    createStatusTab('Status');
    current_tab = 'Status';
  }
  if (verb_tabs.length == 0 || !verbs) {
    Byond.command('Fix-Stat-Panel');
  }
  if (!status_data || !status_data.round) {
    statcontentdiv.textContent = 'Loading...';
    return;
  }
  var v = status_view;
  if (!v || v.root.parentNode !== statcontentdiv) {
    statcontentdiv.textContent = '';
    v = status_view = st_build();
    statcontentdiv.appendChild(v.root);
  }
  var r = status_data.round;

  // The tiles: the round's time and the station's, or the lobby's countdown and players; the shuttle while it matters
  if (r.start !== undefined && r.start !== null) {
    mc_set(v.tile_time.label, 'Starts in');
    mc_set(v.tile_time.value, typeof r.start == 'number' ? st_secs(r.start) : r.start == 'DELAYED' ? 'Delayed' : 'Soon');
    mc_class(v.tile_time, 'st-tile' + (r.start == 'DELAYED' ? ' average' : ' info'));
    mc_set(v.tile_station.label, 'Players');
    mc_set(v.tile_station.value, r.players + (r.ready !== undefined && r.ready !== null ? ' · ' + r.ready + ' ready' : ''));
  } else {
    mc_set(v.tile_time.label, 'Round');
    mc_set(v.tile_time.value, r.round_time || '--:--:--');
    mc_class(v.tile_time, 'st-tile');
    mc_set(v.tile_station.label, 'Station');
    mc_set(v.tile_station.value, r.station_time || '');
  }
  var sh = r.shuttle;
  var shown = sh && sh[0] && sh[0] != 'RCH' && !(r.start !== undefined && r.start !== null);
  v.tile_shuttle.style.display = shown ? '' : 'none';
  if (shown) {
    mc_set(v.tile_shuttle.value, sh[0] + ' ' + sh[1]);
    mc_class(v.tile_shuttle, 'st-tile' + (SHUTTLE_LEVELS[sh[0]] ? ' ' + SHUTTLE_LEVELS[sh[0]] : ''));
  }

  // The round's facts, then the server's
  var facts = [['', r.map]];
  if (r.round_id) facts.push(['Round', r.round_id]);
  if (r.next_map) facts.push(['Next', r.next_map]);
  if (r.mode) facts.push(['Mode', r.mode]);
  st_meta(v.meta, facts);
  var tidi = r.tidi || [0, 0, 0, 0];
  var ping = r.ping || [0, 0];
  var server = String(r.server_time || '').split(' ');
  st_meta(v.meta2, [
    ['Server', server[1] || server[0], '', server[0]],
    ['TiDi', tidi[0] + '%', tidi[0] >= 20 ? 'bad' : tidi[0] >= 5 ? 'average' : '', 'avg ' + tidi.slice(1).join('% · ') + '%'],
    ['Ping', ping[0] + ' ms', ping[0] >= 300 ? 'bad' : ping[0] >= 150 ? 'average' : '', 'average ' + ping[1] + ' ms'],
  ]);

  // Their ahelp and question
  var help = status_data.help || [];
  v.helpbox.style.display = help.length ? '' : 'none';
  st_sync(v.helpbox, v.help, help);

  // Their mob
  var count = st_sync(v.mine, v.items, status_data.items);
  v.mine.style.display = count ? '' : 'none';
  mc_class(v.root, 'st' + (count ? ' st-two' : ''));
}

function make_topic_onclick(query) {
  return (e) => {
    e.preventDefault();
    Byond.topic(query);
  };
}

// A gear tab (SpiderOS, the nanosuit): its lines, drawn as Status draws a mob's
function draw_extra(tab) {
  var v = extra_view;
  if (!v || v.tab != tab || v.root.parentNode !== statcontentdiv) {
    statcontentdiv.textContent = '';
    v = extra_view = { tab: tab, items: [], root: mc_el('div', 'st-mine st-extra') };
    v.root.onclick = st_click;
    statcontentdiv.appendChild(v.root);
  }
  st_sync(v.root, v.items, extra_tabs[tab]);
}

// hippie: the MC tab. CPU, map CPU and time dilation with their last two minutes, the facts and controllers under them, then
// the subsystems as a table that sorts by any column and filters by name; the ones that never fire or are off are folded away
// at the end, and any the watchdog took offline or found asleep sit at the top with its button. The page is built once and its figures
// changed in place each second, so the filter keeps its focus and a click isn't lost to a redraw; rows don't move while the
// mouse is over the table. Names open View Variables, as before.
var SVG_NS = 'http://www.w3.org/2000/svg';
var MC_HISTORY = 120; // statpanels.dm MC_HISTORY_LENGTH
var mc_view = null;
var mc_filter = '';
var mc_sort = { key: 'cost', desc: true };
var mc_show_nofire = false;
var mc_open = ''; // the subsystem (type) whose row detail is open
try {
  var saved_sort = JSON.parse(window.localStorage.getItem('mc_sort') || 'null');
  if (saved_sort && saved_sort.key) mc_sort = saved_sort;
  mc_show_nofire = window.localStorage.getItem('mc_nofire') == '1';
} catch (e) {}
// key, header, index in a subsystem's list (statpanels.dm generate_mc_data()), numbers sort high first
var MC_COLUMNS = [
  ['state', '', 1],
  ['name', 'Subsystem', 0],
  ['cost', 'ms', 2],
  ['tick', 'tick', 3],
  ['over', 'over', 4],
  ['ticks', 'ticks', 5],
  ['extra', '', 6],
];
var MC_STATES = { R: 'Running', Q: 'Queued', P: 'Paused', S: 'Sleeping' };

function mc_el(tag, cls, text) {
  var e = document.createElement(tag);
  if (cls) e.className = cls;
  if (text !== undefined) e.textContent = text;
  return e;
}

function mc_set(e, text) {
  if (e.textContent !== text) e.textContent = text;
}

function mc_class(e, cls) {
  if (e.className !== cls) e.className = cls;
}

function mc_ms(n) {
  if (!n) return '0';
  if (n < 1) return n.toFixed(2);
  if (n < 10) return n.toFixed(1);
  return String(Math.round(n));
}

function mc_pct(n) {
  if (!n) return '0';
  return n < 10 ? n.toFixed(1) : String(Math.round(n));
}

function mc_level(v, warn, bad) {
  return v >= bad ? ' bad' : v >= warn ? ' average' : '';
}

function mc_tile(label) {
  var t = { tile: mc_el('div', 'mc-tile') };
  var head = mc_el('div', 'mc-tile-head');
  head.appendChild(mc_el('span', 'mc-tile-label', label));
  t.value = mc_el('span', 'mc-tile-value');
  head.appendChild(t.value);
  var svg = document.createElementNS(SVG_NS, 'svg');
  svg.setAttribute('class', 'mc-spark');
  svg.setAttribute('viewBox', '0 0 ' + MC_HISTORY + ' 24');
  svg.setAttribute('preserveAspectRatio', 'none');
  t.area = document.createElementNS(SVG_NS, 'path');
  t.area.setAttribute('class', 'mc-spark-area');
  t.line = document.createElementNS(SVG_NS, 'path');
  t.line.setAttribute('class', 'mc-spark-line');
  svg.appendChild(t.area);
  svg.appendChild(t.line);
  t.sub = mc_el('div', 'mc-tile-sub');
  t.tile.appendChild(head);
  t.tile.appendChild(svg);
  t.tile.appendChild(t.sub);
  return t;
}

// The newest second at the right edge; the scale grows past `floor` when the line does
function mc_spark(t, series, floor) {
  series = series || [];
  var top = floor;
  for (var i = 0; i < series.length; i++) {
    if (series[i] > top) top = series[i];
  }
  if (!series.length) {
    t.line.setAttribute('d', '');
    t.area.setAttribute('d', '');
    return 0;
  }
  var x0 = MC_HISTORY - series.length;
  var d = '';
  for (var j = 0; j < series.length; j++) {
    d += (j ? 'L' : 'M') + (x0 + j) + ' ' + (23 - (series[j] / top) * 22).toFixed(1);
  }
  t.line.setAttribute('d', d);
  t.area.setAttribute('d', d + 'L' + (MC_HISTORY - 1) + ' 24L' + x0 + ' 24Z');
  return Math.max.apply(null, series);
}

function mc_chip(label, act, arg) {
  var c = mc_el('a', 'mc-chip');
  c.href = '#';
  c.dataset.act = act;
  c.dataset.arg = arg || '';
  c.appendChild(mc_el('span', 'mc-chip-label', label));
  c.val = mc_el('span', 'mc-chip-value');
  c.appendChild(c.val);
  return c;
}

function mc_action(act, arg, type) {
  if (act == 'vv') {
    if (arg) Byond.topic('_src_=vars;admin_token=' + href_token + ';Vars=' + arg);
  } else if (act == 'watchdog') {
    Byond.topic('_src_=holder;admin_token=' + href_token + ';mcwatchdog=' + arg + (type ? ';ss=' + type : ''));
  }
}

function mc_click(e) {
  var target = e.target.closest('[data-act]');
  if (!target) {
    mc_row_click(e);
    return;
  }
  e.preventDefault();
  if (target.dataset.act == 'sort') {
    var key = target.dataset.arg;
    if (mc_sort.key == key) {
      mc_sort.desc = !mc_sort.desc;
    } else {
      mc_sort = { key: key, desc: key != 'name' };
    }
    try {
      window.localStorage.setItem('mc_sort', JSON.stringify(mc_sort));
    } catch (err) {}
    draw_mc(true);
  } else if (target.dataset.act == 'nofire') {
    mc_show_nofire = !mc_show_nofire;
    try {
      window.localStorage.setItem('mc_nofire', mc_show_nofire ? '1' : '0');
    } catch (err) {}
    draw_mc(true);
  } else {
    mc_action(target.dataset.act, target.dataset.arg, target.dataset.type);
  }
}

// A click on a subsystem's row, not its name or button: its detail strip opens under it (one at a time), or closes
function mc_row_click(e) {
  if (e.target.closest('[data-act]') || e.target.closest('.mc-detail')) return;
  var tr = e.target.closest('tr[data-type]');
  if (!tr) return;
  mc_open = mc_open == tr.dataset.type ? '' : tr.dataset.type;
  if (mc_data) mc_data.detail = null;
  Byond.sendMessage('MC-Detail', { type: mc_open });
  draw_mc(true);
}

function mc_secs(ds) {
  return ds === null || ds === undefined ? '-' : (ds / 10).toFixed(1) + ' s';
}

function mc_build_detail() {
  var t = mc_tile('ms/s');
  t.tr = mc_el('tr', 'mc-detail');
  var td = mc_el('td');
  td.colSpan = MC_COLUMNS.length;
  t.tile.className = 'mc-tile mc-detail-tile';
  t.facts = mc_el('div', 'mc-detail-facts');
  t.tile.appendChild(t.facts);
  td.appendChild(t.tile);
  t.tr.appendChild(td);
  return t;
}

function mc_fill_detail(t, info) {
  if (!info || info[0] != mc_open) {
    mc_set(t.value, '');
    mc_spark(t, [], 1);
    mc_set(t.sub, 'Loading...');
    mc_set(t.facts, '');
    return;
  }
  // Averaged over the subsystem's own wait: one firing every 2 s would draw 0, 15, 0, 15 a second
  var raw = info[1] || [];
  var span = Math.min(30, Math.max(1, Math.ceil(info[2] / 10)));
  var hist = [];
  for (var j = span - 1; j < raw.length; j++) {
    var part = 0;
    for (var s = j - span + 1; s <= j; s++) part += raw[s];
    hist.push(part / span);
  }
  var peak = mc_spark(t, hist, 1);
  var sum = 0;
  for (var i = 0; i < hist.length; i++) sum += hist[i];
  mc_set(t.value, hist.length ? mc_ms(hist[hist.length - 1]) : '-');
  mc_set(t.sub, hist.length ? 'peak ' + mc_ms(peak) + ' · avg ' + mc_ms(sum / hist.length) + ' · ' + hist.length + ' s' : 'no fires');
  var facts = [
    'wait ' + mc_secs(info[2]),
    'priority ' + info[3],
    'fires ' + Number(info[4]).toLocaleString(),
    'last ' + mc_secs(info[6]) + ' ago',
    'next ' + mc_secs(info[5]),
    'init order ' + info[7],
  ];
  if (info[8]) facts.push(info[8]);
  mc_set(t.facts, facts.join(' · '));
}

function mc_build() {
  var v = { rows: {}, order: '' };
  v.root = mc_el('div', 'mc');
  v.root.onclick = mc_click;
  var tiles = mc_el('div', 'mc-tiles');
  v.cpu = mc_tile('CPU');
  v.map = mc_tile('Map CPU');
  v.tidi = mc_tile('TiDi');
  tiles.appendChild(v.cpu.tile);
  tiles.appendChild(v.map.tile);
  tiles.appendChild(v.tidi.tile);
  v.root.appendChild(tiles);
  v.facts = mc_el('div', 'mc-facts');
  v.root.appendChild(v.facts);
  var chips = mc_el('div', 'mc-chips');
  v.chip_mc = mc_chip('MC', 'vv');
  v.chip_failsafe = mc_chip('Failsafe', 'vv');
  v.chip_watchdog = mc_chip('Watchdog', 'vv');
  v.chip_profile = mc_chip('Profile 30 s', 'watchdog', 'profile');
  v.chip_profile.classList.add('mc-chip-button');
  v.chip_globals = mc_chip('Globals', 'vv');
  v.chip_config = mc_chip('Config', 'vv');
  v.chip_cameras = mc_chip('Cameras', 'vv');
  [v.chip_mc, v.chip_failsafe, v.chip_watchdog, v.chip_profile, v.chip_globals, v.chip_config, v.chip_cameras].forEach((c) =>
    chips.appendChild(c)
  );
  v.root.appendChild(chips);
  var bar = mc_el('div', 'mc-toolbar');
  v.filter = mc_el('input', 'mc-filter');
  v.filter.type = 'text';
  v.filter.placeholder = 'Filter';
  v.filter.spellcheck = false;
  v.filter.value = mc_filter;
  v.filter.oninput = () => {
    mc_filter = v.filter.value;
    draw_mc(true);
  };
  bar.appendChild(v.filter);
  v.count = mc_el('span', 'mc-count');
  bar.appendChild(v.count);
  v.root.appendChild(bar);
  v.table = mc_el('table', 'mc-table');
  var colgroup = mc_el('colgroup');
  var thead = mc_el('thead');
  var headrow = mc_el('tr');
  v.heads = {};
  MC_COLUMNS.forEach((col) => {
    colgroup.appendChild(mc_el('col', 'mc-col-' + col[0]));
    var th = mc_el('th', 'mc-' + col[0]);
    if (col[1]) {
      th.dataset.act = 'sort';
      th.dataset.arg = col[0];
      th.textContent = col[1];
    }
    v.heads[col[0]] = th;
    headrow.appendChild(th);
  });
  thead.appendChild(headrow);
  v.table.appendChild(colgroup);
  v.table.appendChild(thead);
  v.body = mc_el('tbody');
  v.table.appendChild(v.body);
  v.detail = mc_build_detail();
  v.nofire_body = mc_el('tbody', 'mc-nofire');
  v.nofire_head = mc_el('tr', 'mc-group');
  var group = mc_el('td');
  group.colSpan = MC_COLUMNS.length;
  group.dataset.act = 'nofire';
  v.nofire_label = mc_el('span');
  group.appendChild(v.nofire_label);
  v.nofire_head.appendChild(group);
  v.nofire_body.appendChild(v.nofire_head);
  v.table.appendChild(v.nofire_body);
  v.root.appendChild(v.table);
  return v;
}

function mc_make_row(ss) {
  var r = { tr: mc_el('tr'), cells: [] };
  MC_COLUMNS.forEach((col) => {
    var td = mc_el('td', 'mc-' + col[0]);
    r.cells.push(td);
    r.tr.appendChild(td);
  });
  r.name = mc_el('a');
  r.name.href = '#';
  r.name.dataset.act = 'vv';
  r.cells[1].appendChild(r.name);
  r.bar = mc_el('span', 'mc-bar');
  r.cost = mc_el('span');
  r.cells[2].appendChild(r.bar);
  r.cells[2].appendChild(r.cost);
  r.badge = mc_el('span', 'mc-badge');
  r.fix = mc_el('a', 'mc-fix');
  r.fix.href = '#';
  r.fix.dataset.act = 'watchdog';
  r.extra = mc_el('span', 'mc-extra-text');
  r.cells[6].appendChild(r.badge);
  r.cells[6].appendChild(r.fix);
  r.cells[6].appendChild(r.extra);
  return r;
}

// Turned off, taken offline by the watchdog, or asleep: [badge, button, watchdog action]
function mc_trouble(status) {
  if (typeof status == 'number') {
    if (!status) return ['OFF', 'Turn on', 'enable'];
    return ['OFF ' + Math.floor(status / 60) + ':' + ('0' + (status % 60)).slice(-2), 'Turn on', 'enable'];
  }
  if (status === 'asleep') return ['ASLEEP', 'Start now', 'wake'];
  return null;
}

// Never fires, or turned off (Assets and Icon Smoothing turn themselves off once their start-up work is done): folded away
function mc_resting(status) {
  return status === 'nofire' || status === 'off';
}

function mc_update_row(r, ss, top) {
  var trouble = mc_trouble(ss[8]);
  var firing = !mc_resting(ss[8]);
  mc_class(r.tr, (!firing ? 'mc-row-nofire' : trouble ? 'mc-row-trouble' : '') + (ss[9] == mc_open ? ' open' : ''));
  r.tr.dataset.type = ss[9];
  mc_set(r.cells[0], ss[1]);
  r.cells[0].className = 'mc-state mc-state-' + (ss[1] || 'I');
  r.cells[0].title = MC_STATES[ss[1]] || '';
  mc_set(r.name, ss[0]);
  r.name.dataset.arg = ss[7];
  r.name.title = ss[9];
  mc_set(r.cost, firing ? mc_ms(ss[2]) : '');
  r.bar.style.width = firing && top > 0 ? Math.min(100, (ss[2] / top) * 100).toFixed(1) + '%' : '0';
  mc_set(r.cells[3], firing ? mc_pct(ss[3]) : '');
  mc_set(r.cells[4], firing ? mc_pct(ss[4]) : '');
  mc_class(r.cells[4], 'mc-over' + (ss[4] > 0 ? ' hot' : ''));
  mc_set(r.cells[5], firing ? String(ss[5]) : '');
  mc_class(r.cells[5], 'mc-ticks' + (ss[5] > 1 ? ' hot' : ''));
  mc_set(r.badge, trouble ? trouble[0] : ss[8] === 'off' ? 'OFF' : '');
  mc_class(r.badge, 'mc-badge' + (trouble ? '' : ' quiet'));
  mc_set(r.fix, trouble ? trouble[1] : '');
  r.fix.dataset.arg = trouble ? trouble[2] : '';
  r.fix.dataset.type = ss[9];
  mc_set(r.extra, ss[6]);
  r.cells[6].title = ss[6];
}

function mc_sorter(list) {
  var index = 0;
  MC_COLUMNS.forEach((col) => {
    if (col[0] == mc_sort.key) index = col[2];
  });
  return (a, b) => {
    var ta = mc_trouble(a[8]) ? 0 : 1;
    var tb = mc_trouble(b[8]) ? 0 : 1;
    if (ta != tb) return ta - tb; // trouble first, whatever the sort
    var x = a[index];
    var y = b[index];
    var r = typeof x == 'number' && typeof y == 'number' ? x - y : String(x).localeCompare(String(y));
    if (mc_sort.desc) r = -r;
    return r || list.indexOf(a) - list.indexOf(b);
  };
}

function draw_mc(force) {
  if (!mc_data) {
    statcontentdiv.textContent = 'Loading...';
    return;
  }
  var v = mc_view;
  if (!v || v.root.parentNode !== statcontentdiv) {
    statcontentdiv.textContent = '';
    v = mc_view = mc_build();
    statcontentdiv.appendChild(v.root);
    force = true;
  }
  statcontentdiv.className = 'statcontent mc-content';
  var d = mc_data;
  var hist = d.history || [[], [], []];

  // The vitals
  var peak = mc_spark(v.cpu, hist[0], 100);
  mc_set(v.cpu.value, mc_pct(d.cpu) + '%');
  mc_class(v.cpu.tile, 'mc-tile' + mc_level(d.cpu, 75, 100));
  mc_set(v.cpu.sub, 'peak ' + mc_pct(peak) + '%');
  peak = mc_spark(v.map, hist[1], 50);
  mc_set(v.map.value, mc_pct(d.map_cpu) + '%');
  mc_class(v.map.tile, 'mc-tile' + mc_level(d.map_cpu, 30, 50));
  mc_set(v.map.sub, 'peak ' + mc_pct(peak) + '%');
  mc_spark(v.tidi, hist[2], 20);
  mc_set(v.tidi.value, mc_pct(d.tidi) + '%');
  mc_class(v.tidi.tile, 'mc-tile' + mc_level(d.tidi, 5, 20));
  var avg = d.tidi_avg || [0, 0, 0];
  mc_set(v.tidi.sub, 'avg ' + avg.map(mc_pct).join(' · '));

  mc_set(
    v.facts,
    'Tick ' +
      Number(d.tick).toLocaleString() +
      ' · Time ' +
      Number(d.time).toLocaleString() +
      ' · FPS ' +
      d.fps +
      ' · Drift ' +
      d.drift +
      ' (' +
      d.drift_pct +
      '%) · Instances ' +
      Number(d.instances).toLocaleString() +
      (mc_loc ? ' · ' + mc_loc : '')
  );

  // The controllers
  var mc = d.mc;
  v.chip_mc.dataset.arg = mc ? mc[3] : '';
  mc_set(v.chip_mc.val, mc ? (mc[0] ? '#' + mc[1] + ' · limit ' + mc[2] + '%' : 'stopped') : 'none');
  mc_class(v.chip_mc, 'mc-chip' + (mc && mc[0] ? '' : ' bad'));
  var fs = d.failsafe;
  v.chip_failsafe.dataset.arg = fs ? fs[3] : '';
  mc_set(v.chip_failsafe.val, fs ? 'Defcon ' + fs[0] : 'none');
  mc_class(v.chip_failsafe, 'mc-chip' + (!fs ? ' bad' : fs[0] <= 2 ? ' bad' : fs[0] < 5 ? ' average' : ''));
  var wd = d.watchdog;
  v.chip_watchdog.dataset.arg = wd ? wd[5] : '';
  mc_set(v.chip_watchdog.val, wd ? 'Freezes ' + wd[0] + ' · Lag ' + wd[1] : 'not running');
  v.chip_watchdog.title = wd && wd[0] ? 'Last freeze ' + wd[2] + ' s, ' + wd[3] + ' min ago' : '';
  mc_class(v.chip_watchdog, 'mc-chip' + (!wd ? ' bad' : wd[0] || wd[1] ? ' average' : ''));
  mc_set(v.chip_profile.firstChild, wd && wd[4] ? 'Profiling' : 'Profile 30 s');
  mc_class(v.chip_profile, 'mc-chip mc-chip-button' + (wd ? '' : ' disabled'));
  v.chip_globals.dataset.arg = d.globals;
  v.chip_config.dataset.arg = d.config;
  var cams = d.cameras || [0, 0, ''];
  v.chip_cameras.dataset.arg = cams[2];
  mc_set(v.chip_cameras.val, cams[0] + ' · ' + cams[1] + ' chunks');

  // The subsystems
  var list = d.subsystems || [];
  var top = 0;
  for (var i = 0; i < list.length; i++) {
    if (!mc_resting(list[i][8]) && list[i][2] > top) top = list[i][2];
  }
  var filter = mc_filter.trim().toLowerCase();
  var seen = {};
  var firing = [];
  var idle = [];
  var shown = 0;
  for (var j = 0; j < list.length; j++) {
    var ss = list[j];
    var ref = ss[7];
    seen[ref] = true;
    var r = v.rows[ref];
    if (!r) r = v.rows[ref] = mc_make_row(ss);
    mc_update_row(r, ss, top);
    var match = !filter || ss[0].toLowerCase().indexOf(filter) != -1 || ss[9].toLowerCase().indexOf(filter) != -1;
    r.tr.style.display = match ? '' : 'none';
    if (mc_resting(ss[8])) {
      idle.push(ss);
    } else {
      firing.push(ss);
      if (match) shown++;
    }
  }
  for (var old in v.rows) {
    if (!seen[old]) {
      v.rows[old].tr.remove();
      delete v.rows[old];
    }
  }
  firing.sort(mc_sorter(list));
  idle.sort((a, b) => a[0].localeCompare(b[0]));
  var order = firing.map((s) => s[7]).join(',') + '|' + idle.map((s) => s[7]).join(',');
  if (order != v.order && (force || !v.table.matches(':hover'))) {
    v.order = order;
    firing.forEach((s) => v.body.appendChild(v.rows[s[7]].tr));
    idle.forEach((s) => v.nofire_body.appendChild(v.rows[s[7]].tr));
  }
  // The open row's detail strip, under it wherever the sort put it
  var open_row = null;
  for (var k = 0; k < list.length; k++) {
    if (list[k][9] == mc_open) open_row = v.rows[list[k][7]];
  }
  if (open_row && open_row.tr.style.display != 'none') {
    if (open_row.tr.nextSibling !== v.detail.tr) open_row.tr.after(v.detail.tr);
    v.detail.tr.style.display = '';
    mc_fill_detail(v.detail, d.detail);
  } else {
    v.detail.tr.style.display = 'none';
  }
  v.nofire_body.className = 'mc-nofire' + (mc_show_nofire ? ' open' : '');
  mc_set(v.nofire_label, 'Not firing (' + idle.length + ')');
  mc_set(v.count, filter ? shown + ' of ' + firing.length : firing.length + ' firing');
  for (var key in v.heads) {
    var th = v.heads[key];
    th.classList.toggle('sorted', key == mc_sort.key);
    th.classList.toggle('desc', key == mc_sort.key && mc_sort.desc);
  }
}

function remove_tickets() {
  if (tickets) {
    tickets = [];
    removePermanentTab('Tickets');
    if (current_tab == 'Tickets') tab_change(defaultTab);
  }
  checkStatusTab();
}

function remove_sdql2() {
  if (sdql2) {
    sdql2 = [];
    removePermanentTab('SDQL2');
    if (current_tab == 'SDQL2') tab_change(defaultTab);
  }
  checkStatusTab();
}

// Clicking something the panel lists: the server checks it listed it to this player, then it's a click on it
function make_item_onmousedown(ref) {
  return (e) => {
    e.preventDefault();
    var query = 'src=' + ref;
    switch (e.button) {
      case 1:
        query += ';statpanel_item_click=middle';
        break;
      case 2:
        query += ';statpanel_item_click=right';
        break;
      default:
        query += ';statpanel_item_click=left';
    }
    if (e.shiftKey) {
      query += ';statpanel_item_shiftclick=1';
    }
    if (e.ctrlKey) {
      query += ';statpanel_item_ctrlclick=1';
    }
    if (e.altKey) {
      query += ';statpanel_item_altclick=1';
    }
    Byond.topic(query);
  };
}

function draw_listedturf() {
  statcontentdiv.textContent = '';
  var list = document.createElement('div');
  list.className = 'turf-list';
  for (var i = 0; i < turfcontents.length; i++) {
    var part = turfcontents[i];
    var row = document.createElement('div');
    row.className = 'turf-item';
    row.onmousedown = make_item_onmousedown(part[1]);
    row.oncontextmenu = (e) => e.preventDefault();
    var picture = turficons[part[2]];
    if (picture) {
      var img = document.createElement('img');
      img.src = picture;
      row.appendChild(img);
    } else {
      var blank = document.createElement('span');
      blank.className = 'turf-noicon';
      row.appendChild(blank);
    }
    var name = document.createElement('span');
    name.textContent = part[0];
    row.appendChild(name);
    // Hippie: alike things are one row
    if (part[3] > 1) {
      var count = document.createElement('span');
      count.className = 'turf-count';
      count.textContent = '×' + part[3];
      row.appendChild(count);
    }
    list.appendChild(row);
  }
  if (turfmore > 0) {
    var more = document.createElement('div');
    more.className = 'turf-more';
    more.textContent = '+' + turfmore + ' more';
    list.appendChild(more);
  }
  statcontentdiv.appendChild(list);
}

function remove_listedturf() {
  removePermanentTab(turfname);
  checkStatusTab();
  if (current_tab == turfname) {
    tab_change(defaultTab);
  }
}

function remove_mc() {
  removePermanentTab('MC');
  if (current_tab == 'MC') {
    tab_change(defaultTab);
  }
}

function draw_sdql2() {
  statcontentdiv.textContent = '';
  var table = document.createElement('table');
  for (var i = 0; i < sdql2.length; i++) {
    var part = sdql2[i];
    var tr = document.createElement('tr');
    var td1 = document.createElement('td');
    td1.textContent = part[0];
    var td2 = document.createElement('td');
    if (part[2]) {
      var a = document.createElement('a');
      a.href = '#';
      a.onclick = make_topic_onclick('src=' + part[2] + ';statpanel_item_click=left');
      a.textContent = part[1];
      td2.appendChild(a);
    } else {
      td2.textContent = part[1];
    }
    tr.appendChild(td1);
    tr.appendChild(td2);
    table.appendChild(tr);
  }
  statcontentdiv.appendChild(table);
}

function draw_tickets() {
  statcontentdiv.textContent = '';
  var table = document.createElement('table');
  if (!tickets) {
    return;
  }
  for (var i = 0; i < tickets.length; i++) {
    var part = tickets[i];
    var tr = document.createElement('tr');
    var td1 = document.createElement('td');
    td1.textContent = part[0];
    var td2 = document.createElement('td');
    if (part[2]) {
      var a = document.createElement('a');
      a.href = '#';
      a.onclick = make_topic_onclick('_src_=holder;admin_token=' + href_token + ';ahelp=' + part[2] + ';ahelp_action=ticket');
      a.textContent = part[1];
      td2.appendChild(a);
    } else if (part[3]) {
      var a2 = document.createElement('a');
      a2.href = '#';
      a2.onclick = make_topic_onclick(part[3]);
      a2.textContent = part[1];
      td2.appendChild(a2);
    } else {
      td2.textContent = part[1];
    }
    tr.appendChild(td1);
    tr.appendChild(td2);
    table.appendChild(tr);
  }
  statcontentdiv.appendChild(table);
}

function make_verb_onclick(command, name) {
  return (e) => {
    e.preventDefault();
    if (name) used_verb(name);
    run_after_focus(() => {
      Byond.command(command);
    });
  };
}

// hippie: the verbs used lately, newest first, for the search
function used_verb(name) {
  var at = recent_verbs.indexOf(name);
  if (at != -1) recent_verbs.splice(at, 1);
  recent_verbs.unshift(name);
  if (recent_verbs.length > 20) recent_verbs.length = 20;
  try {
    window.localStorage.setItem('recent_verbs', JSON.stringify(recent_verbs));
  } catch (e) {
    // no storage here: kept until the panel reloads
  }
}

function run_verb(name) {
  used_verb(name);
  clearSearch(false);
  run_after_focus(() => {
    Byond.command(name.replace(/\s/g, '-'));
  });
}

function verbButton(command, note) {
  var a = document.createElement('a');
  a.href = '#';
  a.onclick = make_verb_onclick(command.replace(/\s/g, '-'), command);
  a.className = 'grid-item';
  var t = document.createElement('span');
  t.textContent = command;
  t.className = 'grid-item-text';
  if (note) {
    var small = document.createElement('span');
    small.className = 'grid-item-note';
    small.textContent = note;
    t.appendChild(small);
  }
  a.appendChild(t);
  return a;
}

function draw_verbs(cat, keep) {
  if (!keep) statcontentdiv.textContent = '';
  var table = document.createElement('div');
  var additions = {}; // additional sub-categories to be rendered
  table.className = 'grid-container';
  sortVerbs();
  if (split_admin_tabs && cat.lastIndexOf('.') != -1) {
    var splitName = cat.split('.');
    if (splitName[0] === 'Admin') cat = splitName[1];
  }
  verbs.reverse(); // sort verbs backwards before we draw
  for (var i = 0; i < verbs.length; ++i) {
    var part = verbs[i];
    var name = part[0];
    if (split_admin_tabs && name.lastIndexOf('.') != -1) {
      var splitName2 = name.split('.');
      if (splitName2[0] === 'Admin') name = splitName2[1];
    }
    var command = part[1];

    if (
      command &&
      name.lastIndexOf(cat, 0) != -1 &&
      (name.length == cat.length || name.charAt(cat.length) == '.')
    ) {
      var subCat = name.lastIndexOf('.') != -1 ? name.split('.')[1] : null;
      if (subCat && !additions[subCat]) {
        var newTable = document.createElement('div');
        newTable.className = 'grid-container';
        additions[subCat] = newTable;
      }
      (subCat ? additions[subCat] : table).appendChild(verbButton(command));
    }
  }

  // Append base table to view
  statcontentdiv.appendChild(table);

  // Append additional sub-categories if relevant
  for (var sub in additions) {
    if (Object.prototype.hasOwnProperty.call(additions, sub)) {
      var header = document.createElement('h3');
      header.textContent = sub;
      statcontentdiv.appendChild(header);
      statcontentdiv.appendChild(additions[sub]);
    }
  }
}

// hippie: spells and abilities, with their charge, as buttons (a click casts, as in the old panel)
function draw_spells(panel) {
  var table = document.createElement('div');
  table.className = 'grid-container spells';
  for (var i = 0; i < spells.length; i++) {
    var part = spells[i];
    if (part[0] != panel) continue;
    var a = document.createElement('a');
    a.href = '#';
    a.className = 'grid-item spell';
    a.onmousedown = make_item_onmousedown(part[3]);
    a.onclick = (e) => e.preventDefault();
    var t = document.createElement('span');
    t.className = 'grid-item-text';
    t.textContent = part[2];
    if (part[1]) {
      var charge = document.createElement('span');
      charge.className = 'grid-item-note';
      charge.textContent = part[1];
      t.appendChild(charge);
    }
    a.appendChild(t);
    table.appendChild(a);
  }
  statcontentdiv.appendChild(table);
}

// hippie: every verb whose name has the words in it, from every tab
function draw_search() {
  statcontentdiv.textContent = '';
  var words = search_text.toLowerCase().split(/\s+/).filter((w) => w);
  var found = [];
  for (var i = 0; i < verbs.length; i++) {
    var part = verbs[i];
    if (!part[1]) continue;
    var name = part[1].toLowerCase();
    var ok = true;
    for (var w = 0; w < words.length; w++) {
      if (name.indexOf(words[w]) == -1) {
        ok = false;
        break;
      }
    }
    if (ok) found.push(part);
  }
  found.sort((a, b) => {
    var ra = recent_verbs.indexOf(a[1]);
    var rb = recent_verbs.indexOf(b[1]);
    if (ra != rb) {
      if (ra == -1) return 1;
      if (rb == -1) return -1;
      return ra - rb;
    }
    return a[1].toUpperCase() < b[1].toUpperCase() ? -1 : 1;
  });
  search_found = found;
  if (search_index >= found.length) search_index = 0;
  if (!found.length) {
    var none = document.createElement('div');
    none.className = 'search-none';
    none.textContent = 'No verbs';
    statcontentdiv.appendChild(none);
    return;
  }
  var table = document.createElement('div');
  table.className = 'grid-container';
  for (var f = 0; f < found.length; f++) {
    var b = verbButton(found[f][1], found[f][0].split('.')[0]);
    if (f == search_index) b.classList.add('picked');
    table.appendChild(b);
  }
  statcontentdiv.appendChild(table);
}

function setSearch(text) {
  search_text = text;
  search_index = 0;
  if (text.trim()) {
    if (current_tab != SEARCH_TAB) {
      tab_before_search = current_tab;
      tab_change(SEARCH_TAB);
    } else {
      draw_search();
    }
  } else {
    clearSearch(false);
  }
}

function clearSearch(keepTab) {
  var box = document.getElementById('verbsearch-input');
  if (box && box.value) box.value = '';
  search_text = '';
  if (current_tab == SEARCH_TAB && !keepTab) {
    tab_change(tab_before_search || defaultTab);
  } else if (current_tab == SEARCH_TAB) {
    current_tab = null;
  }
}

function set_theme(which) {
  if (which == 'light') {
    document.body.className = '';
    document.documentElement.className = 'light';
  } else if (which == 'dark') {
    document.body.className = 'dark';
    document.documentElement.className = 'dark';
  }
}

function restoreFocus(e) {
  if (e && e.target && e.target.id == 'verbsearch-input') {
    return; // typing a search
  }
  run_after_focus(() => {
    Byond.winset('mapwindow.map', {
      focus: true,
    });
  });
}

// hippie: verbs keep their own category in part[2]; refold() puts each in its tab (folded or not)
function add_verb_list(payload, initial) {
  var to_add = payload; // list of a list with category and verb inside it
  to_add.sort(); // sort what we're adding
  var added = [];
  for (var i = 0; i < to_add.length; i++) {
    var part = to_add[i];
    if (!part[0]) continue;
    if (findVerbindex(part[1], verbs)) continue;
    verbs.push([part[0], part[1], part[0]]);
    added.push(part[1]);
  }
  if (initial) return;
  refold();
  for (var a = 0; a < added.length; a++) {
    var at = findVerbindex(added[a], verbs);
    if (at !== undefined) markTab(verbs[at][0].split('.')[0]);
  }
  if (verb_tabs.includes(current_tab)) draw_tab(current_tab);
}

// The search box sits at the end of the tab row
(function () {
  var box = document.createElement('div');
  box.id = 'verbsearch';
  var input = document.createElement('input');
  input.id = 'verbsearch-input';
  input.type = 'text';
  input.placeholder = 'Verbs';
  input.title = 'Type part of a verb: Enter runs the top one, arrows pick another';
  input.spellcheck = false;
  input.autocomplete = 'off';
  input.oninput = () => setSearch(input.value);
  input.onkeydown = (e) => {
    if (e.key == 'Escape') {
      clearSearch(false);
      restoreFocus();
    } else if (e.key == 'Enter' && search_found[search_index]) {
      e.preventDefault();
      input.value = '';
      run_verb(search_found[search_index][1]);
    } else if ((e.key == 'ArrowDown' || e.key == 'ArrowRight') && search_found.length) {
      e.preventDefault();
      search_index = Math.min(search_index + 1, search_found.length - 1);
      draw_search();
    } else if ((e.key == 'ArrowUp' || e.key == 'ArrowLeft') && search_found.length) {
      e.preventDefault();
      search_index = Math.max(search_index - 1, 0);
      draw_search();
    }
  };
  box.appendChild(input);
  menu.appendChild(box);
  // hippie: the game menu (game_menu.dm), as Esc with the chat bar empty
  var menuButton = document.createElement('div');
  menuButton.id = 'menubutton';
  menuButton.className = 'button';
  menuButton.textContent = 'Menu';
  menuButton.title = 'Character Setup, Keybindings, Preferences, help, rules... (Esc)';
  menuButton.onclick = () => Byond.command('Game-Menu');
  menu.appendChild(menuButton);
})();

document.addEventListener('mouseup', restoreFocus);
document.addEventListener('keyup', restoreFocus);

if (!current_tab) {
  addPermanentTab(defaultTab);
  tab_change(defaultTab);
}

window.onload = () => {
  Byond.sendMessage('ready');
};

Byond.subscribeTo('remove_verb_list', (v) => {
  var to_remove = v;
  for (var i = 0; i < to_remove.length; i++) {
    remove_verb(to_remove[i]);
  }
  refold(); // hippie: a tab left small folds into Other, an empty one goes
  sortVerbs();
  if (verb_tabs.includes(current_tab)) draw_tab(current_tab);
});

// hippie: the tab picked last round
Byond.subscribeTo('restore_tab', (tab) => {
  if (!tab || tab == current_tab) return;
  if (document.getElementById(tabButtonId(tab))) tab_change(tab);
  else wanted_tab = tab;
});

function verbs_cat_check(cat) {
  for (var v = 0; v < verbs.length; v++) {
    var verbcat = verbs[v][0].split('.')[0];
    if (verbcat == cat) return;
  }
  removeStatusTab(cat);
  if (current_tab == cat) tab_change(defaultTab);
}

// passes a 2D list of (verbcategory, verbname) creates tabs and adds verbs to respective list
// example (IC, Say)
Byond.subscribeTo('init_verbs', (payload) => {
  var had = verbs.length > 1 ? verbs.map((p) => p[1]) : null; // hippie: to mark tabs with new verbs
  wipe_verbs(); // remove all verb categories so we can replace them
  checkStatusTab(); // remove all status tabs
  verb_tabs = payload.panel_tabs;
  verb_tabs.sort(); // sort it
  if (payload.verblist) {
    add_verb_list(payload.verblist, true);
    sortVerbs(); // sort them
  }
  refold(); // hippie: makes the tabs, folded
  if (had) {
    for (var n = 0; n < verbs.length; n++) {
      if (verbs[n][1] && had.indexOf(verbs[n][1]) == -1) markTab(verbs[n][0].split('.')[0]);
    }
  }
  if (current_tab == SEARCH_TAB) {
    draw_search();
  } else if (current_tab && !document.getElementById(tabButtonId(current_tab))) {
    tab_change(defaultTab);
  } else if (verb_tabs.includes(current_tab)) {
    draw_tab(current_tab);
  }
});

// hippie: {round, help, items} (statpanels.dm set_status_tab())
Byond.subscribeTo('update_stat', (payload) => {
  status_data = payload || null;
  if (current_tab == 'Status') {
    draw_status();
  }
});

Byond.subscribeTo('update_mc', (payload) => {
  mc_data = payload.mc;
  mc_data.detail = payload.detail; // the open row's, if any
  mc_loc = payload.loc;
  addPermanentTab('MC');
  if (current_tab == 'MC') {
    draw_mc();
  }
});

Byond.subscribeTo('create_listedturf', (TN) => {
  remove_listedturf(); // remove the last one if we had one
  turfname = TN;
  addPermanentTab(turfname);
  clearSearch(true);
  tab_change(turfname);
});

Byond.subscribeTo('remove_admin_tabs', () => {
  href_token = null;
  remove_mc();
  remove_tickets();
  remove_sdql2();
});

// Hippie: {rows, more, icons}: only pictures the page hasn't had ("reset" first when the server starts them afresh)
Byond.subscribeTo('update_listedturf', (TC) => {
  if (TC.icons.reset) turficons = {};
  for (var key in TC.icons) {
    if (key != 'reset') turficons[key] = TC.icons[key];
  }
  turfcontents = TC.rows;
  turfmore = TC.more;
  if (current_tab == turfname) {
    draw_listedturf();
  }
});

Byond.subscribeTo('add_admin_tabs', (ht) => {
  href_token = ht;
  addPermanentTab('MC');
  addPermanentTab('Tickets');
});

Byond.subscribeTo('update_sdql2', (S) => {
  sdql2 = S;
  if (sdql2.length > 0) {
    addPermanentTab('SDQL2');
  }
  if (current_tab == 'SDQL2') {
    draw_sdql2();
  }
});

Byond.subscribeTo('update_tickets', (T) => {
  var before = JSON.stringify(tickets);
  tickets = T;
  addPermanentTab('Tickets');
  // hippie: the open tickets on the tab, red when someone is waiting for an answer
  var open = 0;
  var waiting = false;
  for (var i = 0; i < T.length; i++) {
    var label = String(T[i][0]);
    if (label == 'Active Tickets:') open = Number(T[i][1]) || 0; // the disconnected ones too
    if (label == 'Admin hub:' && String(T[i][1]).indexOf('waiting') != -1) waiting = true;
  }
  setTabBadge('Tickets', open, waiting);
  if (before != JSON.stringify(T) && before != '[]') markTab('Tickets');
  if (current_tab == 'Tickets') {
    draw_tickets();
  }
});

// hippie: every spell and ability, each time something about them changes
Byond.subscribeTo('update_spells', (S) => {
  spells = S || [];
  var panels = [];
  for (var i = 0; i < spells.length; i++) {
    if (!panels.includes(spells[i][0])) panels.push(spells[i][0]);
  }
  for (var o = 0; o < spell_tabs.length; o++) {
    if (!panels.includes(spell_tabs[o])) {
      removePermanentTab(spell_tabs[o]);
      if (current_tab == spell_tabs[o]) tab_change(defaultTab);
    }
  }
  spell_tabs = panels;
  for (var p = 0; p < panels.length; p++) {
    addPermanentTab(panels[p]);
  }
  if (spell_tabs.includes(current_tab)) draw_tab(current_tab);
});

// hippie: text tabs from gear (SpiderOS, Crynet Nanosuit), each time they change
Byond.subscribeTo('update_extra', (E) => {
  E = E || {};
  for (var old in extra_tabs) {
    if (!E[old]) {
      removePermanentTab(old);
      if (current_tab == old) tab_change(defaultTab);
    }
  }
  extra_tabs = E;
  for (var tab in extra_tabs) {
    addPermanentTab(tab);
  }
  if (extra_tabs[current_tab]) draw_tab(current_tab);
});

Byond.subscribeTo('set_theme', set_theme);

Byond.subscribeTo('remove_listedturf', remove_listedturf);

Byond.subscribeTo('remove_sdql2', remove_sdql2);

Byond.subscribeTo('remove_mc', remove_mc);

Byond.subscribeTo('add_verb_list', add_verb_list);
