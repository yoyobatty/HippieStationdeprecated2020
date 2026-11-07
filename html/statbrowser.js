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
//status_tab_parts expects a list to be returned, to which we'll send a list within a list
//with just "loading" to not appear broken.
var status_tab_parts = [['Loading...']];
var current_tab = null;
//mc_tab_parts expects a list to be returned, to which we'll send a list within a list
//with just "loading" to not appear broken.
var mc_tab_parts = [['Loading...']];
var href_token = null;
var verb_tabs = [];
var verbs = [['', '']]; // list with a list inside
var tickets = [];
var sdql2 = [];
var permanent_tabs = []; // tabs that won't be cleared by wipes
var turfcontents = [];
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
    draw_lines(extra_tabs[tab]);
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

// hippie: "Label: value" lines become two columns; anything else spans both
function addStatusLine(table, text) {
  var tr = document.createElement('tr');
  var split = text.indexOf(': ');
  if (split > 0 && split < 40) {
    var label = document.createElement('td');
    label.className = 'status-label';
    label.textContent = text.substring(0, split);
    var value = document.createElement('td');
    value.className = 'status-value';
    value.textContent = text.substring(split + 2);
    tr.appendChild(label);
    tr.appendChild(value);
  } else {
    var td = document.createElement('td');
    td.colSpan = 2;
    td.className = 'status-value';
    td.textContent = text;
    tr.appendChild(td);
  }
  table.appendChild(tr);
  return tr;
}

function draw_lines(lines) {
  statcontentdiv.textContent = '';
  var table = document.createElement('table');
  table.className = 'status-table';
  var lastrow;
  for (var i = 0; i < lines.length; i++) {
    var part = lines[i];
    if (!Array.isArray(part)) {
      if (String(part).trim() === '') {
        var gap = document.createElement('tr');
        gap.className = 'status-gap';
        gap.appendChild(document.createElement('td'));
        table.appendChild(gap);
      } else {
        lastrow = addStatusLine(table, String(part));
      }
      continue;
    }
    var base = String(part[0]).trim();
    if (base === 'same_line' && lastrow) {
      var cell = lastrow.lastChild;
      var a = document.createElement('a');
      a.href = '#';
      a.onclick = make_topic_onclick(part[2]);
      a.textContent = part[1];
      cell.appendChild(a);
    } else if (base === '') {
      var gap2 = document.createElement('tr');
      gap2.className = 'status-gap';
      gap2.appendChild(document.createElement('td'));
      table.appendChild(gap2);
    } else {
      lastrow = addStatusLine(table, base);
      if (part[2]) {
        var link = document.createElement('a');
        link.href = '#';
        link.onclick = make_topic_onclick(part[2]);
        link.textContent = part[1];
        lastrow.lastChild.appendChild(link);
      }
    }
  }
  statcontentdiv.appendChild(table);
}

function make_topic_onclick(query) {
  return (e) => {
    e.preventDefault();
    Byond.topic(query);
  };
}

function draw_status() {
  if (!document.getElementById(tabButtonId('Status'))) {
    createStatusTab('Status');
    current_tab = 'Status';
  }
  draw_lines(status_tab_parts);
  if (verb_tabs.length == 0 || !verbs) {
    Byond.command('Fix-Stat-Panel');
  }
}

function draw_mc() {
  statcontentdiv.textContent = '';
  statcontentdiv.className = 'mcstatcontent';
  var table = document.createElement('table');
  for (var i = 0; i < mc_tab_parts.length; i++) {
    var part = mc_tab_parts[i];
    var tr = document.createElement('tr');
    var td0 = document.createElement('td');
    td0.className = 'monospace';
    td0.textContent = part[0];
    var td1 = document.createElement('td');
    td1.textContent = part[1];
    var td2 = document.createElement('td');
    if (part[3]) {
      var a = document.createElement('a');
      a.href = '#';
      a.onclick = make_topic_onclick('_src_=vars;admin_token=' + href_token + ';Vars=' + part[3]);
      a.textContent = part[2];
      td2.appendChild(a);
    } else {
      td2.textContent = part[2];
    }
    tr.appendChild(td0);
    tr.appendChild(td1);
    tr.appendChild(td2);
    table.appendChild(tr);
  }
  statcontentdiv.appendChild(table);
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
    if (part[2]) {
      var img = document.createElement('img');
      img.src = part[2];
      row.appendChild(img);
    } else {
      var blank = document.createElement('span');
      blank.className = 'turf-noicon';
      row.appendChild(blank);
    }
    var name = document.createElement('span');
    name.textContent = part[0];
    row.appendChild(name);
    list.appendChild(row);
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

Byond.subscribeTo('update_stat', (payload) => {
  status_tab_parts = [];

  var parsed = payload.global_data;

  for (var i = 0; i < parsed.length; i++)
    if (parsed[i] != null) status_tab_parts.push(parsed[i]);

  parsed = payload.other_str || [];

  for (var j = 0; j < parsed.length; j++)
    if (parsed[j] != null) status_tab_parts.push(parsed[j]);

  if (current_tab == 'Status') {
    draw_status();
  }
});

Byond.subscribeTo('update_mc', (payload) => {
  mc_tab_parts = payload.mc_data;
  mc_tab_parts.splice(0, 0, ['', 'Location:', payload.coord_entry]);
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

Byond.subscribeTo('update_listedturf', (TC) => {
  turfcontents = TC;
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
