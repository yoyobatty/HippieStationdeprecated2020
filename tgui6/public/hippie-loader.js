// hippie -- fetches the chat's stylesheet and script (sent beforehand with browse_rsc) and puts them in the page.
// browse() cuts a page off somewhere under 1 MB, so they can't be inlined; and on BYOND 516 a file asked for while it's
// still arriving can go unanswered for good under its name while name?r=1 comes back at once (goonchat's loader found
// this), so each is asked for again under a new name until it comes. Placed at the end of the body by tgui_panel.dm.
(function () {
  var RETRY_MS = 1500;
  var TRIES = 200;
  var started = Date.now();
  var log = (window.chatLoadLog = []);
  function note(text) {
    log.push(text + ' ' + (Date.now() - started) + 'ms');
  }
  function fetchText(name, attempt, done) {
    var xhr = new XMLHttpRequest();
    var settled = false;
    var timer = setTimeout(function () {
      if (!settled && attempt < TRIES) {
        settled = true;
        note(name + ' again');
        xhr.abort();
        fetchText(name, attempt + 1, done);
      }
    }, RETRY_MS);
    xhr.onreadystatechange = function () {
      if (xhr.readyState !== 4 || settled) {
        return;
      }
      settled = true;
      clearTimeout(timer);
      note(name + (attempt ? '?r=' + attempt : '') + ' ' + xhr.status);
      if (xhr.status < 200 || xhr.status >= 400 || !xhr.responseText) {
        if (attempt < TRIES) {
          setTimeout(function () {
            fetchText(name, attempt + 1, done);
          }, RETRY_MS);
        }
        return;
      }
      done(xhr.responseText);
    };
    xhr.open('GET', attempt ? name + '?r=' + attempt : name, true);
    xhr.send(null);
  }
  fetchText('tgui-panel.bundle.css', 0, function (css) {
    var style = document.createElement('style');
    style.textContent = css;
    document.head.appendChild(style);
    fetchText('tgui-panel.bundle.js', 0, function (js) {
      var script = document.createElement('script');
      script.text = js + '\n//# sourceURL=tgui-panel.bundle.js';
      document.body.appendChild(script);
      note('ran');
    });
  });
})();
