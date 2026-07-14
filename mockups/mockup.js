/* awiwi mockups — shared demo behaviors.
   Mockup-only vanilla JS; the real SPA drives all of this from Svelte state.
   Behavior specs live in handovers/server-rewrite/T22-mockups.md. */
(function () {
  'use strict';
  var root = document.documentElement;

  /* --- theme: apply persisted choice ASAP (script is loaded in <head>,
     non-deferred, so this runs before first paint — no theme flash).
     Pages marked data-theme-fixed (the *-light.html static snapshots)
     keep their hardcoded initial theme but can still be toggled live. --- */
  try {
    var stored = localStorage.getItem('awiwi-theme');
    if (stored && !root.hasAttribute('data-theme-fixed')) {
      root.setAttribute('data-theme', stored);
    }
  } catch (e) { /* file:// or private mode may deny storage — fine */ }

  function currentTheme() {
    return root.getAttribute('data-theme') || 'dark';
  }

  function syncToggle() {
    document.querySelectorAll('.theme-toggle [data-set-theme]').forEach(function (b) {
      b.classList.toggle('is-active', b.getAttribute('data-set-theme') === currentTheme());
    });
  }

  function setTheme(next) {
    root.classList.add('theme-transition');
    root.setAttribute('data-theme', next);
    try { localStorage.setItem('awiwi-theme', next); } catch (e) { /* ignore */ }
    syncToggle();
    window.setTimeout(function () { root.classList.remove('theme-transition'); }, 350);
  }

  /* --- table serializers for the copy-menu --- */
  function tableRows(table) {
    return Array.prototype.map.call(table.querySelectorAll('tr'), function (tr) {
      return Array.prototype.map.call(tr.querySelectorAll('th,td'), function (c) {
        return c.textContent.trim();
      });
    });
  }
  function toMarkdown(rows) {
    if (!rows.length) return '';
    var out = ['| ' + rows[0].join(' | ') + ' |',
               '| ' + rows[0].map(function () { return '---'; }).join(' | ') + ' |'];
    rows.slice(1).forEach(function (r) { out.push('| ' + r.join(' | ') + ' |'); });
    return out.join('\n');
  }
  function toCsv(rows) {
    return rows.map(function (r) {
      return r.map(function (c) {
        return /[",\n]/.test(c) ? '"' + c.replace(/"/g, '""') + '"' : c;
      }).join(',');
    }).join('\n');
  }
  function toHtml(rows) {
    var head = '<tr>' + rows[0].map(function (c) { return '<th>' + c + '</th>'; }).join('') + '</tr>';
    var body = rows.slice(1).map(function (r) {
      return '<tr>' + r.map(function (c) { return '<td>' + c + '</td>'; }).join('') + '</tr>';
    }).join('\n');
    return '<table>\n<thead>' + head + '</thead>\n<tbody>\n' + body + '\n</tbody>\n</table>';
  }
  var serializers = { markdown: toMarkdown, csv: toCsv, html: toHtml };

  function writeClipboard(text) {
    if (navigator.clipboard && navigator.clipboard.writeText) {
      return navigator.clipboard.writeText(text).catch(function () { /* file:// may deny */ });
    }
    return Promise.resolve();
  }

  function flashCopied(btn, label) {
    var original = btn.dataset.originalLabel || btn.textContent;
    btn.dataset.originalLabel = original;
    btn.textContent = label || 'Copied ✓';
    btn.classList.add('is-copied');
    window.setTimeout(function () {
      btn.textContent = original;
      btn.classList.remove('is-copied');
    }, 1400);
  }

  document.addEventListener('DOMContentLoaded', function () {
    /* --- theme toggle --- */
    syncToggle();
    document.querySelectorAll('.theme-toggle [data-set-theme]').forEach(function (b) {
      b.addEventListener('click', function () { setTheme(b.getAttribute('data-set-theme')); });
    });

    /* --- plain copy buttons (code blocks, full files) --- */
    document.querySelectorAll('.copy-btn:not([aria-haspopup])').forEach(function (btn) {
      btn.addEventListener('click', function () {
        var block = btn.closest('.code-block');
        var pre = block && block.querySelector('pre');
        writeClipboard(pre ? pre.textContent : '').then(function () { flashCopied(btn); });
        if (!pre) flashCopied(btn);
      });
    });

    /* --- table copy-menu: open/close + copy-and-close on format pick --- */
    document.querySelectorAll('.copy-menu').forEach(function (menu) {
      var trigger = menu.querySelector('.copy-btn[aria-haspopup]');
      var list = menu.querySelector('.copy-menu-list');
      if (!trigger || !list) return;

      function close() {
        list.classList.add('u-hidden');
        trigger.setAttribute('aria-expanded', 'false');
      }
      trigger.addEventListener('click', function () {
        var open = list.classList.toggle('u-hidden') === false;
        trigger.setAttribute('aria-expanded', String(open));
      });
      /* choosing a format copies the data AND closes the menu */
      list.querySelectorAll('button').forEach(function (item) {
        item.addEventListener('click', function () {
          var container = menu.closest('.spread') || menu;
          var scope = container.parentElement || document;
          var table = scope.querySelector('table');
          var fmt = (item.textContent.match(/markdown|csv|html/i) || ['markdown'])[0].toLowerCase();
          var text = table ? serializers[fmt](tableRows(table)) : '';
          writeClipboard(text);
          close();
          flashCopied(trigger, 'Copied ✓');
        });
      });
      /* click-outside closes without copying */
      document.addEventListener('click', function (e) {
        if (!menu.contains(e.target)) close();
      });
    });

    /* --- redacted spans: click (or Enter/Space) toggles reveal.
       Server embeds the real value in the DOM when not in remote mode;
       the frontend only toggles visibility. --- */
    document.querySelectorAll('.redacted').forEach(function (el) {
      el.setAttribute('role', 'button');
      el.setAttribute('tabindex', '0');
      el.setAttribute('aria-pressed', 'false');
      el.setAttribute('title', 'Click to reveal');
      function toggle() {
        var on = el.classList.toggle('is-revealed');
        el.setAttribute('aria-pressed', String(on));
        el.setAttribute('title', on ? 'Click to redact' : 'Click to reveal');
      }
      el.addEventListener('click', toggle);
      el.addEventListener('keydown', function (e) {
        if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); toggle(); }
      });
    });
  });
})();
