/* Live refresh for the delegate ledger. Host-specific by design, so it lives
 * here and not in startr-swap.js. It never swaps anything itself: when /status
 * says the ledger changed, it submits the results block's own Refresh form and
 * lets startr.swap do the swap. (A link to the current address would be
 * declined by startr.swap and become a full reload; a GET form is not.)
 * Off when the checkbox is off; the choice is remembered. */
(function () {
  // A swap that lands on the address we are already at is not a navigation:
  // a Refresh, or a star POST that redirected back here. Keep history clean.
  document.addEventListener('swap:navigate', function (e) {
    if (e.detail && e.detail.url === location.href) e.preventDefault();
  });
  // A failed swap must not strand the reader on a POST address: reload here.
  document.addEventListener('swap:error', function (e) {
    e.preventDefault();
    location.assign(location.href);
  });
  // Keep keyboard focus on the same row's star after a swap replaces the rows.
  var focusRow = null;
  document.addEventListener('swap:before', function () {
    var a = document.activeElement;
    var row = a && a.closest && a.closest('article');
    focusRow = row ? row.id : null;
  });
  document.addEventListener('swap:after', function () {
    if (!focusRow) return;
    var b = document.querySelector('#' + CSS.escape(focusRow) + ' .star');
    if (b) b.focus();
    focusRow = null;
  });

  var box = document.getElementById('live');
  if (!box) return;
  var every = (parseInt(box.dataset.interval, 10) || 0) * 1000;
  var note = document.getElementById('live-note');
  try { if (localStorage.getItem('ledger-live') === 'off') box.checked = false; } catch (e) {}
  if (every <= 0) { box.disabled = true; return; }
  var last = null;
  function busy() {
    var a = document.activeElement;
    if (!a || a === document.body || a.id === 'live') return false;
    // Typing, or reading a row with the keyboard: leave the page alone.
    return a.matches('input, textarea, select') || !!a.closest('#results');
  }
  function tick() {
    if (!box.checked || document.hidden || busy()) return;
    fetch('/status', { credentials: 'same-origin' })
      .then(function (r) { return r.json(); })
      .then(function (s) {
        var key = s.rows + ':' + s.newest;
        if (last !== null && key !== last) {
          var f = document.getElementById('refresh');
          if (f && f.requestSubmit) f.requestSubmit();
        }
        last = key;
        if (note) note.textContent = ' ' + s.rows;
      })
      .catch(function () {});
  }
  box.addEventListener('change', function () {
    try { localStorage.setItem('ledger-live', box.checked ? 'on' : 'off'); } catch (e) {}
    if (box.checked) tick();
  });
  setInterval(tick, every);
  tick();
})();
