/* Try Denodo, selected-industry context for existing index_v3.html.
 * Does not modify the existing tour engine, application routes or use-case cards.
 */
(function () {
  'use strict';
  const KEY = 'trydenodo.selectedChallenge.v1';
  const challenges = Object.freeze({
    crestbank: {
      label: 'Crestbank',
      detail: 'Banking',
      scenario: 'Crestbank wants to understand loan repayment activity among Gold and Platinum customers. Choose the role you want to play in answering this question.'
    },
    medixit: {
      label: 'Medixit',
      detail: 'Pharmaceuticals',
      scenario: 'Medixit wants to understand patient participation, study start dates and the X-ray images linked to trial patients. Choose the role you want to play in answering this question.'
    }
  });
  const fromURL = new URLSearchParams(window.location.search).get('challenge');
  let stored = null;
  try { stored = window.sessionStorage.getItem(KEY); } catch (e) { /* privacy mode */ }
  const key = Object.prototype.hasOwnProperty.call(challenges, fromURL) ? fromURL
    : Object.prototype.hasOwnProperty.call(challenges, stored) ? stored : 'crestbank';
  const selected = challenges[key];
  try { window.sessionStorage.setItem(KEY, key); } catch (e) { /* ignore */ }
  window.TryDenodoChallenge = { id:key, label:selected.label, database: key === 'medixit' ? 'pharm_ai' : 'bank_demo' };

  function updateScenarioLine() {
    const explicit = document.querySelector('[data-scenario-line], #scenario-line, .scenario-line');
    if (explicit) { explicit.textContent = selected.scenario; return true; }
    const elts = [...document.querySelectorAll('p, .hero-subtitle, .hero-description, .scenario')];
    const match = elts.find(el => /Crestbank needs to know|falling behind on their loan repayments/i.test(el.textContent || '')
      && el.textContent.length < 650);
    if (match) { match.textContent = selected.scenario; return true; }
    return false;
  }

  function insertBanner() {
    if (document.getElementById('td-challenge-banner')) return;
    const el = document.createElement('div');
    el.id = 'td-challenge-banner';
    el.className = 'td-challenge-banner';
    el.setAttribute('role', 'region');
    el.setAttribute('aria-label', 'Selected business challenge');
    el.innerHTML = '<div class="td-challenge-banner__name"></div><a class="td-challenge-banner__link" href="/index.html">Change challenge</a>';
    const name = el.querySelector('.td-challenge-banner__name');
    name.textContent = selected.label;
    const detail = document.createElement('span');
    detail.textContent = selected.detail;
    name.appendChild(detail);
    const header = document.querySelector('header, [role="banner"]');
    if (header) header.insertAdjacentElement('afterend', el);
    else document.body.insertBefore(el, document.body.firstChild);
  }

  function insertMissingScenarioHint() {
    if (document.querySelector('#td-challenge-note')) return;
    const heroTitle = [...document.querySelectorAll('h1, h2')].find(el => /welcome to your denodo trial|choose a tour and get hands on/i.test(el.textContent || ''));
    if (!heroTitle) return;
    const hint = document.createElement('p');
    hint.id = 'td-challenge-note';
    hint.className = 'td-challenge-note';
    hint.textContent = selected.scenario;
    heroTitle.insertAdjacentElement('afterend', hint);
  }

  // Only the Crestbank role tours are currently implemented. The Medixit
  // branch offers honest, role-specific starter instructions without claiming
  // that a full validated clinical trial workflow is already deployed.
  function getPersonaRole(node) {
    let el = node;
    for (let level = 0; el && el !== document.body && level < 7; el = el.parentElement, level++) {
      const text = (el.textContent || '').trim();
      if (text.length > 950) continue;
      const identifiers = [el.id, el.className, el.getAttribute?.('data-role'), el.getAttribute?.('data-tour')].filter(x => typeof x === 'string').join(' ');
      const hasTourAction = /start tour|begin tour|take tour|launch tour/i.test(text) || /persona|tour|card/i.test(identifiers);
      if (!hasTourAction) continue;
      if (/Data Engineer/i.test(text)) return 'engineer';
      if (/AI Builder/i.test(text)) return 'ai';
      if (/Business Analyst|End User/i.test(text)) return 'analyst';
    }
    return null;
  }
  function medixitRouting(event) {
    if (key !== 'medixit') return;
    const trigger = event.target.closest?.('button, a, [role="button"], [onclick]') || event.target;
    if (!trigger || trigger.closest?.('.td-challenge-banner')) return;
    const role = getPersonaRole(trigger);
    if (!role) return;
    event.preventDefault();
    event.stopImmediatePropagation();
    const url = new URL('medixit-tour-preview.html', window.location.href);
    url.searchParams.set('role', role);
    window.location.assign(url.href);
  }

  function initialise() {
    insertBanner();
    if (!updateScenarioLine()) insertMissingScenarioHint();
    if (key === 'medixit') document.addEventListener('click', medixitRouting, true);
    const nativeLink = document.querySelector('a[href="index.html"]');
    if (nativeLink && /get started/i.test(nativeLink.textContent || '')) {
      // Existing nav's "Get started" should stay on the welcome page,
      // instead of returning to the new industry selector.
      nativeLink.setAttribute('href', 'index_v3.html?challenge=' + key);
    }
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', initialise, {once:true});
  else initialise();
})();
