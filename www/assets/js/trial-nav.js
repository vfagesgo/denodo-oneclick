/* Try Denodo trial sidebar (added for the Try Denodo guided tours).
   Fills <aside data-trial-nav="home|mcp|docs"> with the same sidebar on welcome.html, mcp-api.html and documentation.html:
   the trial homepage link, the Denodo tools, and a "Login credentials" dropdown.
   Tool links open on the server that serves the page. Sign-in details come from trial-logins.js. */
(function () {
  'use strict';
  var IC = {
    home: '<circle cx="12" cy="12" r="9"/><path d="M15 9l-2 5-5 2 2-5 5-2z"/>',
    back: '<path d="M19 12H5M11 6l-6 6 6 6"/>',
    ds: '<path d="M12 2l9 5v10l-9 5-9-5V7l9-5zM3 7l9 5 9-5M12 12v10"/>',
    dm: '<rect x="3" y="3" width="7" height="7" rx="1.5"/><rect x="14" y="3" width="7" height="7" rx="1.5"/><rect x="3" y="14" width="7" height="7" rx="1.5"/><rect x="14" y="14" width="7" height="7" rx="1.5"/>',
    chat: '<path d="M12 2l2 6.2L20 10l-6 1.8L12 18l-2-6.2L4 10l6-1.8L12 2z"/>',
    mcp: '<path d="M10 14a4 4 0 0 0 5.6 0l3-3a4 4 0 1 0-5.6-5.6L11.8 6.6M14 10a4 4 0 0 0-5.6 0l-3 3A4 4 0 0 0 11 18.6l1.2-1.2"/>',
    docs: '<path d="M4 4h6a3 3 0 0 1 3 3v13a2.5 2.5 0 0 0-2.5-2.5H4V4zM20 4h-6a3 3 0 0 0-3 3v13a2.5 2.5 0 0 1 2.5-2.5H20V4z"/>',
    key: '<circle cx="8" cy="15" r="4"/><path d="M11 12l9-9M17 6l3 3M15 8l2 2"/>'
  };
  function svg(k, w) {
    return '<svg width="' + (w || 18) + '" height="' + (w || 18) + '" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' + IC[k] + '</svg>';
  }
  function esc(t) { return String(t).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/"/g, '&quot;'); }
  function item(href, k, label, on, extra) {
    return '<a class="td-i' + (on ? ' on' : '') + '" href="' + href + '"' + (on ? ' aria-current="page"' : '') + (extra || '') + '>' + svg(k) + esc(label) + '</a>';
  }

  /* Login credentials dropdown. Used by the sidebar and by guided-personas.html. */
  function credentialsHTML(only) {
    var L = window.TRY_DENODO_LOGINS || { users: [], password: '' };
    var users = only ? L.users.filter(function (u) { return u.user === only; }) : L.users;
    var rows = users.map(function (u) {
      return '<div class="td-c-row"><span class="td-c-k">' + esc(only ? 'User' : u.tour + (u.signin ? ' · ' + u.signin : '')) + '</span>' +
        '<span class="td-c-v"><code>' + esc(u.user) + '</code><button type="button" data-copy="' + esc(u.user) + '">Copy</button></span></div>';
    }).join('');
    if (L.password) {
      rows += '<div class="td-c-row"><span class="td-c-k">Password' + (only ? '' : ' (all users)') + '</span>' +
        '<span class="td-c-v"><code>' + esc(L.password) + '</code><button type="button" data-copy="' + esc(L.password) + '">Copy</button></span></div>';
    }
    var note = only ? esc((users[0] && users[0].note) || 'For this tour: sign in with this user.')
                    : 'Each user signs in to the tool named with its tour.';
    return '<details class="td-cred"><summary>' + svg('key', 16) + 'Login credentials<span class="chev" aria-hidden="true">▾</span></summary>' +
      '<div class="td-c-b">' + rows + '<p class="td-c-note">' + note + '</p></div></details>';
  }
  function wireCopy(root) {
    root.addEventListener('click', function (e) {
      var b = e.target.closest ? e.target.closest('button[data-copy]') : null;
      if (!b) return;
      var t = b.getAttribute('data-copy'), done = function () { b.textContent = 'Copied'; setTimeout(function () { b.textContent = 'Copy'; }, 1400); };
      var nav = (root.ownerDocument || document).defaultView.navigator;
      if (nav.clipboard && nav.clipboard.writeText) nav.clipboard.writeText(t).then(done, function () { fallback(t); done(); });
      else { fallback(t); done(); }
      function fallback(x) {
        var d = root.ownerDocument || document, ta = d.createElement('textarea');
        ta.value = x; ta.setAttribute('readonly', ''); ta.style.position = 'fixed'; ta.style.opacity = '0';
        d.body.appendChild(ta); ta.select(); try { d.execCommand('copy'); } catch (err) { } ta.remove();
      }
    });
  }
  window.TryDenodoCredentials = { html: credentialsHTML, wire: wireCopy };

  function build(nav) {
    var page = nav.getAttribute('data-trial-nav');
    var home = page === 'home';
    nav.classList.add('td-nav');
    nav.setAttribute('aria-label', 'Trial');
    nav.innerHTML =
      '<div class="td-brand"><a href="welcome.html" aria-label="Trial homepage"><img src="../assets/images/denodo_logo_black.png" alt="Denodo"></a></div>' +
      '<p class="td-sec">Trial</p>' +
      (home ? item('welcome.html', 'home', 'Get started', true)
            : item('welcome.html', 'back', 'Return to trial homepage', false)) +
      '<p class="td-sec">Tools</p>' +
      item('/denodo-design-studio/', 'ds', 'Design Studio', false, ' data-app="ds"') +
      item('/denodo-data-catalog/#/', 'dm', 'Data Marketplace', false, ' data-app="dm"') +
      item('/chatbot/', 'chat', 'Ask a Question', false, ' data-app="chat"') +
      item('mcp-api.html', 'mcp', 'MCP and API', page === 'mcp') +
      item('documentation.html', 'docs', 'Documentation', page === 'docs') +
      credentialsHTML();
    wireCopy(nav);
  }
  function init() {
    var navs = document.querySelectorAll('aside[data-trial-nav]');
    for (var i = 0; i < navs.length; i++) build(navs[i]);
  }
  init();
})();
