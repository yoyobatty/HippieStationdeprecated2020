
/*****************************************
*
* FUNCTION AND VAR DECLARATIONS
*
******************************************/

//DEBUG STUFF
var escaper = encodeURIComponent || escape;
var decoder = decodeURIComponent || unescape;
window.onerror = function(msg, url, line, col, error) {
	if (document.location.href.indexOf("proc=debug") <= 0) {
		var extra = !col ? '' : ' | column: ' + col;
		extra += !error ? '' : ' | error: ' + error;
		extra += !navigator.userAgent ? '' : ' | user agent: ' + navigator.userAgent;
		var debugLine = 'Error: ' + msg + ' | url: ' + url + ' | line: ' + line + extra;
		runByond('?_src_=chat&proc=debug&param[error]='+escaper(debugLine));
	}
	return true;
};

//Globals
window.status = 'Output';
var $messages, $scroller, $last_message;
var opts = {
	//General
	'messageCount': 0, //A count...of messages...
	'messageLimit': 2053, //A limit...for the messages...
	'scrollSnapTolerance': 10, //If within x pixels of bottom
	'clickTolerance': 10, //Keep focus if outside x pixels of mousedown position on mouseup
	'imageRetryDelay': 50, //how long between attempts to reload images (in ms)
	'imageRetryLimit': 50, //how many attempts should we make?
	'wasd': false, //Is the user in wasd mode?
	'priorChatHeight': 0, //Thing for height-resizing detection
	'restarting': false, //Is the round restarting?
	'darkmode':true, //Are we using darkmode? If not WHY ARE YOU LIVING IN 2009???

	//Options
	'highlightTerms': [],
	'highlightLimit': 5,
	'highlightColor': '#FFFF00', //The color of the highlighted message
	'pingDisabled': false, //Has the user disabled the ping counter
	'timestamps': false,

	//Ping display
	'lastPang': 0, //Timestamp of the last response from the server.
	'pangLimit': 35000,
	'pingTime': 0, //Timestamp of when ping sent
	'pongTime': 0, //Timestamp of when ping received
	'noResponse': false, //Tracks the state of the previous ping request
	'noResponseCount': 0, //How many failed pings?

	//Clicks
	'mouseDownX': null,
	'mouseDownY': null,
	'preventFocus': false, //Prevents switching focus to the game window

	//Client Connection Data
	'clientDataLimit': 5,
	'clientData': [],

	//Admin music volume update
	'volumeUpdateDelay': 5000, //Time from when the volume updates to data being sent to the server
	'volumeUpdating': false, //True if volume update function set to fire
	'updatedVolume': 0, //The volume level that is sent to the server
	'musicStartAt': 0, //The position the music starts playing
	'musicEndAt': 0, //The position the music... stops playing... if null, doesn't apply (so the music runs through)

	'defaultMusicVolume': 25,

	'messageCombining': true,
};
var replaceRegexes = {};

/*****************************************
*
* TABS: what kind of message each is, by the classes it already carries
*
******************************************/

// The first rule that matches decides. PMs and the mentor channel go before the admin classes they're dressed in.
var MESSAGE_RULES = [
	['admin', '.adminsay, .admin, .adminnotice, .mentor, .log_message, .prayer'],
	['ooc', '.ooc, .looc, .adminooc, .adminobserverooc'],
	['radio', '.radio, .sciradio, .comradio, .secradio, .medradio, .engradio, .suppradio, .servradio, .syndradio, .centcomradio, .aiprivradio, .redteamradio, .blueteamradio, .deptradio, .binarysay'],
	['local', '.say, .emote, .deadsay'],
	['combat', '.danger, .userdanger'],
];
var PM_TEXT = /^\s*(Admin PM|PM (from|to)-|Reply PM|Mentor PM|Mentor-PM|MENTOR:|Ticket #)/i;
// Which kinds each tab shows. System lines (connection notices) show everywhere.
var TABS = {
	'all': null,
	'local': ['local'],
	'radio': ['radio'],
	'ooc': ['ooc', 'pm'],
	'combat': ['combat'],
	'admin': ['admin', 'pm'],
};
var HISTORY_KEEP = 200;
var HISTORY_KEY = 'goonchat_history';

var chatui = {
	tab: 'all',
	unread: {local: 0, radio: 0, ooc: 0, combat: 0, admin: 0},
	search: '',
	admin: false,
	round: null,
	history: [], //what was shown, oldest first: {h: html, t: type, ts: time, n: repeats, r: round}
	historyDirty: false,
	newCount: 0,
};

function classifyMessage(entry, text) {
	if (entry.querySelector('.internal, .connectionClosed')) {
		return 'system';
	}
	if (PM_TEXT.test(text) || entry.querySelector('.adminhelp, .mentornotice')) {
		return 'pm';
	}
	for (var i = 0; i < MESSAGE_RULES.length; i++) {
		if (entry.querySelector(MESSAGE_RULES[i][1])) {
			return MESSAGE_RULES[i][0];
		}
	}
	return 'other';
}

function tabShows(tab, type) {
	var kinds = TABS[tab];
	return !kinds || type == 'system' || kinds.indexOf(type) != -1;
}

function clamp(val, min, max) {
	return Math.max(min, Math.min(val, max))
}

function pad2(n) {
	return (n < 10 ? '0' : '') + n;
}

function timeText(when) {
	var d = new Date(when);
	return pad2(d.getHours()) + ':' + pad2(d.getMinutes());
}

// Linkify the contents of a node, within its parent.
function linkify(parent, insertBefore, text) {
	var start = 0;
	var match;
	var regex = /(?:(?:https?:\/\/)|(?:www\.))(?:[^ ]*?\.[^ ]*?)+[-A-Za-z0-9+&@#\/%?=~_|$!:,.;()]+/ig;
	while ((match = regex.exec(text)) !== null) {
		// add the unmatched text
		parent.insertBefore(document.createTextNode(text.substring(start, match.index)), insertBefore);

		var href = match[0];
		if (!/^https?:\/\//i.test(match[0])) {
			href = "http://" + match[0];
		}

		// add the link
		var link = document.createElement("a");
		link.href = href;
		link.textContent = match[0];
		parent.insertBefore(link, insertBefore);

		start = regex.lastIndex;
	}
	if (start !== 0) {
		// add the remaining text and remove the original text node
		parent.insertBefore(document.createTextNode(text.substring(start)), insertBefore);
		parent.removeChild(insertBefore);
	}
}

// Recursively linkify the children of a given node.
function linkify_node(node) {
	var children = node.childNodes;
	// work backwards to avoid the risk of looping forever on our own output
	for (var i = children.length - 1; i >= 0; --i) {
		var child = children[i];
		if (child.nodeType == Node.TEXT_NODE) {
			// text is to be linkified
			linkify(node, child, child.textContent);
		} else if (child.nodeName != "A" && child.nodeName != "a") {
			// do not linkify existing links
			linkify_node(child);
		}
	}
}

function byondDecode(message) {
	// Basically we url_encode twice server side so we can manually read the encoded version and actually do UTF-8.
	// The replace for + is because FOR SOME REASON, BYOND replaces spaces with a + instead of %20, and a plus with %2b.
	// Marvelous.
	message = message.replace(/\+/g, "%20");
	try {
		// This is a workaround for the above not always working when BYOND's shitty url encoding breaks. (byond bug id:2399401)
		message = decodeURIComponent(message);
	} catch (err) {
		message = unescape(message);
	}
	return message;
}

function replaceRegex() {
	var selectedRegex = replaceRegexes[$(this).attr('replaceRegex')];
	if (selectedRegex) {
		var replacedText = $(this).html().replace(selectedRegex[0], selectedRegex[1]);
		$(this).html(replacedText);
	}
	$(this).removeAttr('replaceRegex');
}

function escapeRegex(text) {
	return text.replace(/[-\/\\^$*+?.()|[\]{}]/g, '\\$&');
}

// Get all child text nodes that match a regex pattern
function getTextNodes(elem, pattern) {
	var result = [];
	(function walk(node) {
		for (var child = node.firstChild; child; child = child.nextSibling) {
			if (child.nodeType === 3) {
				pattern.lastIndex = 0;
				if (/\S/.test(child.nodeValue) && pattern.test(child.nodeValue)) {
					result.push(child);
				}
			} else if (child.nodeType === 1 && !$(child).hasClass('ts')) {
				walk(child);
			}
		}
	})(elem);
	return result;
}

// Highlight all text terms matching the registered patterns
function highlightTerms(el) {
	var terms = [];
	for (var i = 0; i < opts.highlightTerms.length; i++) {
		terms.push(escapeRegex(opts.highlightTerms[i]));
	}
	var pattern = new RegExp("(" + terms.join('|') + ")", 'gi');
	var nodes = getTextNodes(el, pattern);
	for (var n = 0; n < nodes.length; n++) {
		var node = nodes[n];
		var parts = node.nodeValue.split(pattern);
		var frag = document.createDocumentFragment();
		for (var p = 0; p < parts.length; p++) {
			if (!parts[p]) {
				continue;
			}
			if (p % 2 == 1) { //split() with a group puts the matches at the odd places
				var span = document.createElement('span');
				span.className = 'highlight';
				span.style.backgroundColor = opts.highlightColor;
				span.style.color = '#000000';
				span.textContent = parts[p];
				frag.appendChild(span);
			} else {
				frag.appendChild(document.createTextNode(parts[p]));
			}
		}
		node.parentNode.replaceChild(frag, node);
	}
}

function iconError(E) {
	var that = this;
	setTimeout(function() {
		var attempts = $(that).data('reload_attempts');
		if (typeof attempts === 'undefined' || !attempts) {
			attempts = 1;
		}
		if (attempts > opts.imageRetryLimit)
			return;
		var src = that.src;
		that.src = null;
		that.src = src+'#'+attempts;
		$(that).data('reload_attempts', ++attempts);
	}, opts.imageRetryDelay);
}

function isAtBottom() {
	var s = $scroller[0];
	return s.scrollHeight - s.scrollTop - s.clientHeight <= opts.scrollSnapTolerance;
}

function scrollToBottom() {
	var s = $scroller[0];
	s.scrollTop = s.scrollHeight;
}

function updateNewMessages() {
	if (chatui.newCount > 0) {
		$('#newMessages .number').text(chatui.newCount);
		$('#newMessages').show();
	} else {
		$('#newMessages').hide();
	}
}

function setUnread(tab, count) {
	chatui.unread[tab] = count;
	var $badge = $('#tab-' + tab + ' .unread');
	$badge.text(count > 99 ? '99+' : count);
	$badge.toggleClass('on', count > 0);
}

function matchesSearch(entry) {
	return !chatui.search || (entry.textContent || '').toLowerCase().indexOf(chatui.search) != -1;
}

// The (repeat) badge and the time go back on after the message's html is put in again.
function decorateEntry(entry, record) {
	var ts = document.createElement('span');
	ts.className = 'ts';
	ts.textContent = record.ts ? timeText(record.ts) : '';
	entry.insertBefore(ts, entry.firstChild);
	if (record.n > 1) {
		var badge = document.createElement('span');
		badge.className = 'r';
		badge.textContent = record.n;
		entry.appendChild(badge);
	}
}

function finishEntry(entry) {
	$(entry).find('[replaceRegex]').each(replaceRegex);
	$(entry).find("img.icon").on('error', iconError);
	var to_linkify = entry.querySelectorAll('.linkify');
	for (var i = 0; i < to_linkify.length; ++i) {
		linkify_node(to_linkify[i]);
	}
	if (opts.highlightTerms && opts.highlightTerms.length > 0) {
		highlightTerms(entry);
	}
}

function dropOldest() {
	var first = $messages[0].firstChild;
	if (first) {
		$messages[0].removeChild(first);
	}
	opts.messageCount--;
}

// One message into the chat. Returns whether it can be seen in the open tab.
function addMessage(message, flag, record) {
	// Messages from the server end with a line break: the next one starts on its own line anyway, and a repeat badge belongs on this one
	message = message.replace(/(\s*<br\s*\/?>\s*)+$/i, '').trim();
	if (!message.length) {
		return false;
	}

	var entry = document.createElement('div');
	entry.innerHTML = message;
	var trimmed_message = entry.textContent || entry.innerText || "";
	var type = record ? record.t : classifyMessage(entry, trimmed_message);

	if (!record && opts.messageCombining && $last_message && $last_message == trimmed_message) {
		var last = $messages[0].lastChild;
		var lastRecord = chatui.history[chatui.history.length - 1];
		if (last && lastRecord && last === chatui.lastEntry) {
			lastRecord.n++;
			lastRecord.h = message;
			if (flag != 'recovered') {
				lastRecord.ts = Date.now();
			}
			last.innerHTML = message;
			decorateEntry(last, lastRecord);
			finishEntry(last);
			chatui.historyDirty = true;
			var $badge = $(last).children('.r').last();
			$badge.css('font-size', '0.9em');
			setTimeout(function() { $badge.css('font-size', ''); }, 150);
			return tabShows(chatui.tab, type) && matchesSearch(last);
		}
	}

	// restored: kept by this page from before it was loaded again. recovered: sent back by the server for a page that came up empty.
	var kept = flag == 'restored' || flag == 'recovered';
	if (!record) {
		record = {h: message, t: type, ts: flag == 'recovered' ? null : Date.now(), n: 1, r: chatui.round};
	}
	entry.className = 'entry t-' + type;
	if (kept) {
		entry.className += ' restored';
		if (record.r !== chatui.round || !chatui.round) {
			entry.className += ' stale';
		}
		entry.setAttribute('data-round', record.r || '');
	}
	decorateEntry(entry, record);
	finishEntry(entry);
	if (!matchesSearch(entry)) {
		entry.className += ' nomatch';
	}

	opts.messageCount++;
	if (opts.messageCount >= opts.messageLimit) {
		dropOldest();
	}
	$messages[0].appendChild(entry);
	$last_message = flag == 'restored' ? null : trimmed_message;
	chatui.lastEntry = null;

	if (type != 'system' && flag != 'restored') {
		chatui.lastEntry = entry;
		chatui.history.push(record);
		if (chatui.history.length > HISTORY_KEEP + 50) {
			chatui.history.splice(0, chatui.history.length - HISTORY_KEEP);
		}
		chatui.historyDirty = true;
		// Unread: it arrived where it can't be seen
		if (flag != 'recovered' && !tabShows(chatui.tab, type)) {
			for (var tab in chatui.unread) {
				if (tabShows(tab, type) && (tab != 'admin' || chatui.admin)) {
					setUnread(tab, chatui.unread[tab] + 1);
				}
			}
		}
	}
	return tabShows(chatui.tab, type) && matchesSearch(entry);
}

//Send a message to the client
function output(message, flag) {
	if (typeof message === 'undefined') {
		return;
	}
	if (typeof flag === 'undefined') {
		flag = '';
	}
	if (flag !== 'internal')
		opts.lastPang = Date.now();

	var atBottom = isAtBottom();
	var seen = addMessage(byondDecode(message), flag);
	afterAdding(atBottom, seen ? 1 : 0);
}

// Several messages from one tick of the server's chat queue, each its own argument.
function chatBatch() {
	opts.lastPang = Date.now();
	var atBottom = isAtBottom();
	var seen = 0;
	for (var i = 0; i < arguments.length; i++) {
		if (addMessage(byondDecode(arguments[i]), '')) {
			seen++;
		}
	}
	afterAdding(atBottom, seen);
}

// This round's last messages, from the server, for a page that came up empty (a reconnect, Fix chat). Each its own argument.
function chatRestore() {
	if (!arguments.length) {
		return;
	}
	for (var i = 0; i < arguments.length; i++) {
		addMessage(byondDecode(arguments[i]), 'recovered');
	}
	addDivider();
	$last_message = null;
	chatui.lastEntry = null;
	scrollToBottom();
}

function addDivider() {
	var divider = document.createElement('div');
	divider.className = 'entry t-system divider';
	divider.textContent = 'Reconnected';
	$messages[0].appendChild(divider);
	opts.messageCount++;
}

function afterAdding(atBottom, seen) {
	if (atBottom) {
		scrollToBottom();
		chatui.newCount = 0;
	} else if (seen) {
		chatui.newCount += seen;
	}
	updateNewMessages();
}

function internalOutput(message, flag)
{
	output(escaper(message), flag)
}

//Runs a route within byond, client or server side. Consider this "ehjax" for byond.
function runByond(uri) {
	if (window.chrome && window.chrome.webview) { //516: a direct line to the client, and no navigating (see tgui-main.html)
		window.chrome.webview.postMessage(uri.charAt(0) == '?' ? 'byond://' + uri : uri);
		return;
	}
	window.location = uri;
}

function setCookie(cname, cvalue, exdays) {
	cvalue = escaper(cvalue);
	var d = new Date();
	d.setTime(d.getTime() + (exdays*24*60*60*1000));
	var expires = 'expires='+d.toUTCString();
	document.cookie = cname + '=' + cvalue + '; ' + expires + "; path=/";
}

function getCookie(cname) {
	var name = cname + '=';
	var ca = document.cookie.split(';');
	for(var i=0; i < ca.length; i++) {
	var c = ca[i];
	while (c.charAt(0)==' ') c = c.substring(1);
		if (c.indexOf(name) === 0) {
			return decoder(c.substring(name.length,c.length));
		}
	}
	return '';
}

function rgbToHex(R,G,B) {return toHex(R)+toHex(G)+toHex(B);}
function toHex(n) {
	n = parseInt(n,10);
	if (isNaN(n)) return "00";
	n = Math.max(0,Math.min(n,255));
	return "0123456789ABCDEF".charAt((n-n%16)/16) + "0123456789ABCDEF".charAt(n%16);
}

function swap() { //Swap to darkmode
	// A new address each time: on 516 an address that once went unanswered stays that way (see the loader in browserOutput.html)
	if (opts.darkmode){
		document.getElementById("sheetofstyles").href = "browserOutput_white.css?t=" + Date.now();
		opts.darkmode = false;
		runByond('?_src_=chat&proc=swaptolightmode');
	} else {
		document.getElementById("sheetofstyles").href = "browserOutput.css?t=" + Date.now();
		opts.darkmode = true;
		runByond('?_src_=chat&proc=swaptodarkmode');
	}
	$('html').toggleClass('light', !opts.darkmode);
	$('#themeDark').toggleClass('on', opts.darkmode);
	$('#themeLight').toggleClass('on', !opts.darkmode);
	setCookie('darkmode', (opts.darkmode ? 'true' : 'false'), 365);
}

function handleClientData(ckey, ip, compid) {
	//byond sends player info to here
	var currentData = {'ckey': ckey, 'ip': ip, 'compid': compid};
	if (opts.clientData && !$.isEmptyObject(opts.clientData)) {
		runByond('?_src_=chat&proc=analyzeClientData&param[cookie]='+JSON.stringify({'connData': opts.clientData}));

		for (var i = 0; i < opts.clientData.length; i++) {
			var saved = opts.clientData[i];
			if (currentData.ckey == saved.ckey && currentData.ip == saved.ip && currentData.compid == saved.compid) {
				return; //Record already exists
			}
		}
		//Lets make sure we obey our limit (can connect from server with higher limit)
		while (opts.clientData.length >= opts.clientDataLimit) {
			opts.clientData.shift();
		}
	} else {
		runByond('?_src_=chat&proc=analyzeClientData&param[cookie]=none');
	}

	//Update the cookie with current details
	opts.clientData.push(currentData);
	setCookie('connData', JSON.stringify(opts.clientData), 365);
}

// Whether this player gets the Admin tab, and which round this is (links in messages kept from another round go nowhere).
function setChatState(admin, round) {
	chatui.admin = !!admin;
	$('#tab-admin').toggle(chatui.admin);
	if (chatui.admin && chatui.wantedTab == 'admin' && chatui.tab != 'admin') { //the tab they left open, now that it's there
		chatui.selectTab('admin');
	}
	if (!chatui.admin) {
		setUnread('admin', 0);
		if (chatui.tab == 'admin') {
			chatui.selectTab('all');
		}
	}
	if (round) {
		chatui.round = String(round);
		$messages.children('.restored').each(function() {
			$(this).toggleClass('stale', $(this).attr('data-round') !== chatui.round);
		});
	}
}

//Server calls this on ehjax response
//Or, y'know, whenever really
function ehjaxCallback(data) {
	opts.lastPang = Date.now();
	if (data == 'softPang') {
		return;
	} else if (data == 'pang') {
		opts.pingCounter = 0; //reset
		opts.pingTime = Date.now();
		runByond('?_src_=chat&proc=ping');

	} else if (data == 'pong') {
		if (opts.pingDisabled) {return;}
		opts.pongTime = Date.now();
		var pingDuration = Math.ceil((opts.pongTime - opts.pingTime) / 2);
		$('#pingMs').text(pingDuration+'ms');
		pingDuration = Math.min(pingDuration, 255);
		var red = pingDuration;
		var green = 255 - pingDuration;
		var blue = 0;
		var hex = rgbToHex(red, green, blue);
		$('#pingDot').css('color', '#'+hex);

	} else if (data == 'roundrestart') {
		opts.restarting = true;
		chatui.saveHistory(true);
		internalOutput('<div class="connectionClosed internal restarting">The server is restarting. You\'ll reconnect on your own.</div>', 'internal');
	} else if (data == 'stopMusic') {
		$('#adminMusic').prop('src', '');
	} else {
		//Oh we're actually being sent data instead of an instruction
		var dataJ;
		try {
			dataJ = $.parseJSON(data);
		} catch (e) {
			//But...incorrect :sadtrombone:
			window.onerror('JSON: '+e+'. '+data, 'browserOutput.html', 327);
			return;
		}
		data = dataJ;

		if (data.clientData) {
			if (opts.restarting) {
				opts.restarting = false;
				$('.connectionClosed.restarting:not(.restored)').addClass('restored').text('Reconnected.');
			}
			setChatState(data.clientData.admin, data.clientData.round);
			if (!data.clientData.ckey && !data.clientData.ip && !data.clientData.compid) {
				//TODO: Call shutdown perhaps
				return;
			} else {
				handleClientData(data.clientData.ckey, data.clientData.ip, data.clientData.compid);
			}
			sendVolumeUpdate();
		} else if (typeof data.chatAdmin !== 'undefined') {
			setChatState(data.chatAdmin, null);
		} else if (data.adminMusic) {
			if (typeof data.adminMusic === 'string') {
				var adminMusic = byondDecode(data.adminMusic);
				var bindLoadedData = false;
				adminMusic = adminMusic.match(/https?:\/\/\S+/) || '';
				if (data.musicRate) {
					var newRate = Number(data.musicRate);
					if(newRate) {
						$('#adminMusic').prop('defaultPlaybackRate', newRate);
					}
				} else {
					$('#adminMusic').prop('defaultPlaybackRate', 1.0);
				}
				if (data.musicSeek) {
					opts.musicStartAt = Number(data.musicSeek) || 0;
					bindLoadedData = true;
				} else {
					opts.musicStartAt = 0;
				}
				if (data.musicHalt) {
					opts.musicEndAt = Number(data.musicHalt) || null;
					bindLoadedData = true;
				}
				if (bindLoadedData) {
					$('#adminMusic').one('loadeddata', adminMusicLoadedData);
				}
				$('#adminMusic').prop('src', adminMusic);
				$('#adminMusic').trigger("play");
			}
		} else if (data.syncRegex) {
			for (var i in data.syncRegex) {

				var regexData = data.syncRegex[i];
				var regexName = regexData[0];
				var regexFlags = regexData[1];
				var regexReplaced = regexData[2];

				replaceRegexes[i] = [new RegExp(regexName, regexFlags), regexReplaced];
			}
		}
	}
}

function toggleWasd(state) {
	opts.wasd = (state == 'on' ? true : false);
}

function sendVolumeUpdate() {
	opts.volumeUpdating = false;
	if(opts.updatedVolume) {
		runByond('?_src_=chat&proc=setMusicVolume&param[volume]='+opts.updatedVolume);
	}
}

function adminMusicEndCheck(event) {
	if (opts.musicEndAt) {
		if ($('#adminMusic').prop('currentTime') >= opts.musicEndAt) {
			$('#adminMusic').off(event);
			$('#adminMusic').trigger('pause');
			$('#adminMusic').prop('src', '');
		}
	} else {
		$('#adminMusic').off(event);
	}
}

function adminMusicLoadedData(event) {
	if (opts.musicStartAt && ($('#adminMusic').prop('duration') === Infinity || (opts.musicStartAt <= $('#adminMusic').prop('duration'))) ) {
		$('#adminMusic').prop('currentTime', opts.musicStartAt);
	}
	if (opts.musicEndAt) {
		$('#adminMusic').on('timeupdate', adminMusicEndCheck);
	}
}

function focusMap() {
	runByond('byond://winset?mapwindow.map.focus=true');
}

/*****************************************
*
* THE CHAT'S OWN CONTROLS
*
******************************************/

chatui.selectTab = function(tab) {
	if (!(tab in TABS) || (tab == 'admin' && !chatui.admin)) {
		tab = 'all';
	}
	chatui.tab = tab;
	$messages.attr('data-tab', tab);
	$('#tabs .tab').removeClass('active');
	$('#tab-' + tab).addClass('active');
	if (tab in chatui.unread) {
		setUnread(tab, 0);
	}
	setCookie('chattab', tab, 365);
	chatui.newCount = 0;
	updateNewMessages();
	scrollToBottom();
};

chatui.setSearch = function(text) {
	chatui.search = (text || '').toLowerCase().trim();
	if ($('#searchInput').val() != text) {
		$('#searchInput').val(text);
	}
	var entries = $messages[0].children;
	for (var i = 0; i < entries.length; i++) {
		$(entries[i]).toggleClass('nomatch', !matchesSearch(entries[i]));
	}
	scrollToBottom();
};

chatui.openSearch = function() {
	$('body').addClass('searching');
	$('#searchInput').focus().select();
};

chatui.closeSearch = function() {
	$('body').removeClass('searching');
	chatui.setSearch('');
	focusMap();
};

chatui.setOption = function(name, on) {
	if (name == 'timestamps') {
		opts.timestamps = !!on;
		$('body').toggleClass('show-ts', opts.timestamps);
		setCookie('timestamps', opts.timestamps ? 'true' : 'false', 365);
	} else if (name == 'combine') {
		opts.messageCombining = !!on;
		setCookie('messagecombining', opts.messageCombining ? 'true' : 'false', 365);
	} else if (name == 'ping') {
		opts.pingDisabled = !on;
		$('#ping').toggleClass('off', opts.pingDisabled);
		setCookie('pingdisabled', opts.pingDisabled ? 'true' : 'false', 365);
	}
	chatui.showOptions();
};

chatui.showOptions = function() {
	$('.switch[data-option="timestamps"]').toggleClass('on', opts.timestamps);
	$('.switch[data-option="combine"]').toggleClass('on', opts.messageCombining);
	$('.switch[data-option="ping"]').toggleClass('on', !opts.pingDisabled);
	$('#themeDark').toggleClass('on', opts.darkmode);
	$('#themeLight').toggleClass('on', !opts.darkmode);
	$('#fontSizeValue').text(parseInt(chatui.fontSize, 10) + 'px');
	$('#lineHeightValue').text(parseFloat(chatui.lineHeight).toFixed(1));
	var $terms = $('.highlightTerm');
	for (var i = 0; i < $terms.length; i++) {
		if (!$terms.eq(i).is(':focus')) {
			$terms.eq(i).val(opts.highlightTerms[i] || '');
		}
	}
	$('#highlightColor').val(normalColor(opts.highlightColor));
	$('#musicVolume').val(opts.updatedVolume || opts.defaultMusicVolume);
	$('#musicVolumeValue').text(opts.updatedVolume || opts.defaultMusicVolume);
};

// <input type=color> takes only #rrggbb
function normalColor(color) {
	color = (color || '').trim();
	if (/^#[0-9a-f]{3}$/i.test(color)) {
		color = '#' + color.charAt(1) + color.charAt(1) + color.charAt(2) + color.charAt(2) + color.charAt(3) + color.charAt(3);
	}
	return /^#[0-9a-f]{6}$/i.test(color) ? color.toLowerCase() : '#ffff00';
}

chatui.openSettings = function() {
	chatui.showOptions();
	$('#settings').show();
	$('#toggleOptions').addClass('on');
};

chatui.closeSettings = function() {
	$('#settings').hide();
	$('#toggleOptions').removeClass('on');
	focusMap();
};

chatui.setFontSize = function(size) {
	chatui.fontSize = clamp(parseInt(size, 10) || 13, 6, 40) + 'px';
	$messages.css('font-size', chatui.fontSize);
	setCookie('fontsize', chatui.fontSize, 365);
	chatui.showOptions();
};

chatui.setLineHeight = function(height) {
	chatui.lineHeight = clamp(parseFloat(height) || 1.2, 0.5, 3).toFixed(1);
	$messages.css('line-height', chatui.lineHeight);
	setCookie('lineheight', chatui.lineHeight, 365);
	chatui.showOptions();
};

chatui.saveHighlights = function() {
	var terms = [];
	$('.highlightTerm').each(function() {
		var term = $(this).val();
		if (term !== null && /\S/.test(term)) {
			terms.push(term.trim().toLowerCase());
		}
	});
	opts.highlightTerms = terms.slice(0, opts.highlightLimit);
	opts.highlightColor = normalColor($('#highlightColor').val());
	setCookie('highlightterms', JSON.stringify(opts.highlightTerms), 365);
	setCookie('highlightcolor', opts.highlightColor, 365);
};

chatui.clear = function() {
	$messages.empty();
	opts.messageCount = 0;
	$last_message = null;
	chatui.history = [];
	chatui.historyDirty = true;
	chatui.saveHistory(true);
	for (var tab in chatui.unread) {
		setUnread(tab, 0);
	}
	chatui.newCount = 0;
	updateNewMessages();
};

// What can be seen right now, as text (the self-test reads it).
chatui.visibleText = function() {
	var out = [];
	var entries = $messages[0].children;
	for (var i = 0; i < entries.length; i++) {
		if (entries[i].offsetParent !== null) {
			out.push(entries[i].textContent);
		}
	}
	return out.join('\n');
};

/*****************************************
*
* HISTORY: the last messages, put back after a reconnect or a new round
*
******************************************/

function historyStore() {
	try {
		var test = '__goonchat_test';
		window.localStorage.setItem(test, test);
		window.localStorage.removeItem(test);
		return window.localStorage;
	} catch (e) {
		return null;
	}
}

chatui.saveHistory = function(force) {
	if (!chatui.historyDirty && !force) {
		return;
	}
	var store = historyStore();
	if (!store) {
		return;
	}
	chatui.historyDirty = false;
	var items = chatui.history.slice(-HISTORY_KEEP);
	try {
		store.setItem(HISTORY_KEY, JSON.stringify({v: 1, saved: Date.now(), items: items}));
	} catch (e) { //full: keep what fits
		try {
			store.setItem(HISTORY_KEY, JSON.stringify({v: 1, saved: Date.now(), items: items.slice(-50)}));
		} catch (e2) {}
	}
};

chatui.restoreHistory = function() {
	var store = historyStore();
	if (!store) {
		return 0;
	}
	var saved;
	try {
		saved = JSON.parse(store.getItem(HISTORY_KEY) || 'null');
	} catch (e) {
		saved = null;
	}
	if (!saved || saved.v !== 1 || !saved.items || !saved.items.length) {
		return 0;
	}
	for (var i = 0; i < saved.items.length; i++) {
		var item = saved.items[i];
		if (item && typeof item.h === 'string' && item.t in {'local':1, 'radio':1, 'ooc':1, 'pm':1, 'combat':1, 'admin':1, 'other':1}) {
			addMessage(item.h, 'restored', item);
			chatui.history.push(item);
		}
	}
	addDivider();
	return saved.items.length;
};

/*****************************************
*
* SAVE LOG
*
******************************************/

function saveLogFileName() {
	var date = new Date();
	return 'SS13 Chat Log ' + date.getFullYear() + '-' + pad2(date.getMonth() + 1) + '-' + pad2(date.getDate()) + ' ' +
		pad2(date.getHours()) + pad2(date.getMinutes()) + pad2(date.getSeconds()) + '.html';
}

chatui.saveLog = function() {
	$.ajax({
		type: 'GET',
		url: 'browserOutput_white.css?t=' + Date.now(),
		dataType: 'text',
		success: function(styleData) { saveLogWith(styleData); },
		error: function() { saveLogWith(''); },
	});
};

function saveLogWith(styleData) {
	var $copy = $messages.clone();
	$copy.find('.entry').removeClass('nomatch').css('display', '');
	$copy.removeAttr('data-tab');
	var html = '<!DOCTYPE html><html><head><meta charset="UTF-8"><title>Chat Log</title><style>' + styleData +
		' .ts {color: #777; font-size: 0.8em; margin-right: 5px;} .r {margin-left: 5px; padding: 1px 5px; border-radius: 8px; background: #ddd; font-size: 0.72em;} .r:before {content: "x";}' +
		'</style></head><body>' + $copy.html() + '</body></html>';
	var blob = new Blob([html], {type: 'text/html'});
	var name = saveLogFileName();
	if (window.navigator.msSaveBlob) {
		window.navigator.msSaveBlob(blob, name);
	} else if (window.showSaveFilePicker) {
		window.showSaveFilePicker({suggestedName: name, types: [{description: 'Chat log', accept: {'text/html': ['.html']}}]}).then(function(handle) {
			return handle.createWritable().then(function(writable) {
				return writable.write(blob).then(function() { return writable.close(); });
			});
		}).then(function() {
			internalOutput('<span class="internal boldnshit">Chat log saved.</span>', 'internal');
		}, function(e) {
			if (e && e.name != 'AbortError') {
				internalOutput('<span class="internal boldnshit">Couldn\'t save the log: ' + e + '</span>', 'internal');
			}
		});
	} else {
		var link = document.createElement('a');
		link.href = URL.createObjectURL(blob);
		link.download = name;
		document.body.appendChild(link);
		link.click();
		document.body.removeChild(link);
	}
}

/*****************************************
*
* DOM READY
*
******************************************/

if (typeof $ === 'undefined') {
	var div = document.getElementById('loading').childNodes[1];
	div += '<br><br>ERROR: Jquery did not load.';
}

function chatInit() {
	$messages = $('#messages');
	$scroller = $('#scroller');
	opts.lastPang = Date.now(); //not 'AFK or lagging' before the server has had a chance to answer

	//Hey look it's a controller loop!
	setInterval(function() {
		if (opts.lastPang + opts.pangLimit < Date.now() && !opts.restarting) { //Every pingLimit
				if (!opts.noResponse) { //Only actually append a message if the previous ping didn't also fail (to prevent spam)
					opts.noResponse = true;
					opts.noResponseCount++;
					internalOutput('<div class="connectionClosed internal" data-count="'+opts.noResponseCount+'">You are either AFK, experiencing lag or the connection has closed.</div>', 'internal');
				}
		} else if (opts.noResponse) { //Previous ping attempt failed ohno
				$('.connectionClosed[data-count="'+opts.noResponseCount+'"]:not(.restored)').addClass('restored').text('Connection restored.');
				opts.noResponse = false;
		}
	}, 2000); //2 seconds

	setInterval(function() { chatui.saveHistory(false); }, 1500);
	$(window).on('beforeunload', function() { chatui.saveHistory(true); });


	/*****************************************
	*
	* LOAD SAVED CONFIG
	*
	******************************************/
	var savedConfig = {
		fontsize: getCookie('fontsize'),
		lineheight: getCookie('lineheight'),
		'spingDisabled': getCookie('pingdisabled'),
		'shighlightTerms': getCookie('highlightterms'),
		'shighlightColor': getCookie('highlightcolor'),
		'smusicVolume': getCookie('musicVolume'),
		'smessagecombining': getCookie('messagecombining'),
		'sdarkmode': getCookie('darkmode'),
		'stimestamps': getCookie('timestamps'),
		'schattab': getCookie('chattab'),
	};

	chatui.fontSize = savedConfig.fontsize || '13px';
	chatui.lineHeight = savedConfig.lineheight || '1.2';
	$messages.css({'font-size': chatui.fontSize, 'line-height': chatui.lineHeight});
	if(savedConfig.sdarkmode == 'false'){ //dark from the start, the same as the skin around it
		swap();
	}
	if (savedConfig.spingDisabled == 'true') {
		opts.pingDisabled = true;
		$('#ping').addClass('off');
	}
	if (savedConfig.shighlightTerms) {
		try {
			opts.highlightTerms = $.parseJSON(savedConfig.shighlightTerms).filter(function (entry) {
				return entry !== null && /\S/.test(entry);
			}).slice(0, opts.highlightLimit);
		} catch (e) {
			opts.highlightTerms = [];
		}
	}
	if (savedConfig.shighlightColor) {
		opts.highlightColor = savedConfig.shighlightColor;
	}
	if (savedConfig.smusicVolume) {
		var newVolume = clamp(savedConfig.smusicVolume, 0, 100);
		$('#adminMusic').prop('volume', newVolume / 100);
		opts.updatedVolume = newVolume;
		sendVolumeUpdate();
	}
	else{
		$('#adminMusic').prop('volume', opts.defaultMusicVolume / 100);
	}
	if (savedConfig.smessagecombining == 'false') {
		opts.messageCombining = false;
	}
	if (savedConfig.stimestamps == 'true') {
		opts.timestamps = true;
		$('body').addClass('show-ts');
	}
	(function() {
		var dataCookie = getCookie('connData');
		if (dataCookie) {
			var dataJ;
			try {
				dataJ = $.parseJSON(dataCookie);
			} catch (e) {
				window.onerror('JSON '+e+'. '+dataCookie, 'browserOutput.html', 434);
				return;
			}
			opts.clientData = dataJ;
		}
	})();


	/*****************************************
	*
	* BASE CHAT OUTPUT EVENTS
	*
	******************************************/

	$('body').on('click', 'a', function(e) {
		e.preventDefault();
	});

	$('body').on('mousedown', function(e) {
		var $target = $(e.target);
		if ($target.closest('a, input, textarea, #bar, #settings').length) {
			opts.preventFocus = true;
		} else {
			opts.preventFocus = false;
			opts.mouseDownX = e.pageX;
			opts.mouseDownY = e.pageY;
		}
	});

	$('body').on('mouseup', function(e) {
		if (!opts.preventFocus &&
			(e.pageX >= opts.mouseDownX - opts.clickTolerance && e.pageX <= opts.mouseDownX + opts.clickTolerance) &&
			(e.pageY >= opts.mouseDownY - opts.clickTolerance && e.pageY <= opts.mouseDownY + opts.clickTolerance)
		) {
			opts.mouseDownX = null;
			opts.mouseDownY = null;
			if ($('#settings').is(':visible')) {
				chatui.closeSettings();
			} else {
				focusMap();
			}
		}
	});

	$messages.on('click', 'a', function(e) {
		var href = $(this).attr('href');
		if (!href) {
			return;
		}
		$(this).addClass('visited');
		if (href[0] == '?' || (href.length >= 8 && href.substring(0,8) == 'byond://')) {
			if ($(this).closest('.entry').hasClass('stale')) { //from another round: it points at nothing, or at something else now
				return;
			}
			runByond(href);
		} else {
			href = escaper(href);
			runByond('?action=openLink&link='+href);
		}
	});

	//Fuck everything about this event. Will look into alternatives.
	$('body').on('keydown', function(e) {
		if (e.target.nodeName == 'INPUT' || e.target.nodeName == 'TEXTAREA') {
			if (e.target.id == 'searchInput' && e.which == 27) { //Esc
				chatui.closeSearch();
			}
			return;
		}

		if (e.ctrlKey && (e.key == 'f' || e.key == 'F')) {
			e.preventDefault();
			chatui.openSearch();
			return false;
		}

		if (e.ctrlKey || e.altKey || e.shiftKey) { //Band-aid "fix" for allowing ctrl+c copy paste etc. Needs a proper fix.
			return;
		}

		e.preventDefault()

		var k = e.which;
		// Hardcoded because else there would be no feedback message.
		if (k == 113) { // F2
			runByond('byond://winset?screenshot=auto');
			internalOutput('<span class="internal boldnshit">Screenshot taken</span>', 'internal');
		}
		if (k == 27 && $('#settings').is(':visible')) { // Esc
			chatui.closeSettings();
			return false;
		}

		// The keyboard goes back to the game, and the key that was pressed with it: the game will get its release from the map.
		var name = gameKeyName(e);
		runByond('byond://winset?mapwindow.map.focus=true' + (name ? ';command=' + encodeURIComponent('KeyDown ' + name) : ''));
		return false;
	});

	// What the game's macros call this key, for the ones anybody would be holding down as they click out of the chat.
	function gameKeyName(e) {
		var names = {ArrowUp: 'North', ArrowDown: 'South', ArrowLeft: 'West', ArrowRight: 'East', ' ': 'Space'};
		if (names[e.key]) {
			return names[e.key];
		}
		return /^[a-zA-Z0-9]$/.test(e.key) ? e.key.toUpperCase() : null;
	}

	//Mildly hacky fix for scroll issues on mob change (interface gets resized sometimes, messing up snap-scroll)
	$(window).on('resize', function(e) {
		if ($(this).height() !== opts.priorChatHeight) {
			scrollToBottom();
			opts.priorChatHeight = $(this).height();
		}
	});

	$scroller.on('scroll', function() {
		if (chatui.newCount && isAtBottom()) {
			chatui.newCount = 0;
			updateNewMessages();
		}
	});


	/*****************************************
	*
	* OPTIONS INTERFACE EVENTS
	*
	******************************************/

	$('#newMessages').on('click', function(e) {
		scrollToBottom();
		chatui.newCount = 0;
		updateNewMessages();
		focusMap();
	});

	$('#tabs').on('click', '.tab', function(e) {
		chatui.wantedTab = $(this).attr('data-tab');
		chatui.selectTab(chatui.wantedTab);
		focusMap();
	});

	$('#searchOpen').on('click', function() { chatui.openSearch(); });
	$('#searchClose').on('click', function() { chatui.closeSearch(); });
	$('#searchInput').on('input', function() { chatui.setSearch($(this).val()); });

	$('#toggleOptions').on('click', function(e) {
		if ($('#settings').is(':visible')) {
			chatui.closeSettings();
		} else {
			chatui.openSettings();
		}
	});
	$('#settingsClose').on('click', function() { chatui.closeSettings(); });

	$('#decreaseFont').on('click', function() { chatui.setFontSize(parseInt(chatui.fontSize, 10) - 1); });
	$('#increaseFont').on('click', function() { chatui.setFontSize(parseInt(chatui.fontSize, 10) + 1); });
	$('#decreaseLineHeight').on('click', function() { chatui.setLineHeight(parseFloat(chatui.lineHeight) - 0.1); });
	$('#increaseLineHeight').on('click', function() { chatui.setLineHeight(parseFloat(chatui.lineHeight) + 0.1); });

	$('#settings').on('click', '.switch', function() {
		var option = $(this).attr('data-option');
		chatui.setOption(option, !$(this).hasClass('on'));
	});
	$('#themeDark').on('click', function() { if (!opts.darkmode) { swap(); } });
	$('#themeLight').on('click', function() { if (opts.darkmode) { swap(); } });

	$('.highlightTerm').on('change', function() { chatui.saveHighlights(); });
	$('#highlightColor').on('input change', function() { chatui.saveHighlights(); });

	$('#saveLog').on('click', function() { chatui.saveLog(); });
	$('#clearMessages').on('click', function() { chatui.clear(); });

	$('#musicVolume').on('input change', function() {
		var newVolume = clamp($('#musicVolume').val(), 0, 100);
		$('#musicVolumeValue').text(newVolume);
		$('#adminMusic').prop('volume', newVolume / 100);
		setCookie('musicVolume', newVolume, 365);
		opts.updatedVolume = newVolume;
		if(!opts.volumeUpdating) {
			setTimeout(sendVolumeUpdate, opts.volumeUpdateDelay);
			opts.volumeUpdating = true;
		}
	});

	$('img.icon').on('error', iconError);


	/*****************************************
	*
	* KICK EVERYTHING OFF
	*
	******************************************/

	var restored = chatui.restoreHistory();
	chatui.wantedTab = savedConfig.schattab || 'all';
	chatui.selectTab(chatui.wantedTab);
	chatui.showOptions();
	runByond('?_src_=chat&proc=doneLoading&param[fresh]=' + (restored ? 0 : 1)); //an empty page gets the round's last messages from the server
	if ($('#loading').is(':visible')) {
		$('#loading').remove();
	}
	$('body').addClass('ready');
	opts.priorChatHeight = $(window).height();
	scrollToBottom();
}

// Not $(function () {...}): the loader in browserOutput.html runs this after the page is parsed, and jQuery, loaded that late, waits
// for the window's load event instead, which a file that went unanswered (see the loader) held back for 30 s.
if (document.readyState === 'loading') {
	document.addEventListener('DOMContentLoaded', chatInit);
} else {
	chatInit();
}
