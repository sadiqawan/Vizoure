/* Vizoure NMS — horizontal top header interaction.
 * Operates only on #vizoure-top-header's own DOM. Does not touch, require,
 * or depend on Zabbix's class.sidebar.js / main.js sidebar code — those are
 * already guarded by Zabbix core itself to only run `if (sidebar !== null)`
 * (see js/main.js), which is false here since no .sidebar element exists.
 *
 * Features: priority+ overflow ("More"), hover/click/keyboard dropdowns (one
 * open at a time, edge-aware flyouts), icon-only user area, search that
 * expands from an icon, hamburger below 1024px.
 * Marker: VIZOURE_TOPHEADER_JS
 */
(function () {
	'use strict';

	var OPEN_DELAY = 120;
	var CLOSE_DELAY = 300;
	var MOBILE_MAX = 1023;

	document.addEventListener('DOMContentLoaded', function () {
		var header = document.getElementById('vizoure-top-header');
		if (!header) {
			return;
		}

		var nav = header.querySelector('.vz-header-nav');
		var menu = header.querySelector('.menu-main');
		var timers = new WeakMap();

		// ---------- helpers ----------

		function isMobile() {
			return window.innerWidth <= MOBILE_MAX;
		}

		function link(li) {
			return li.querySelector(':scope > a');
		}

		function clearTimer(li) {
			var t = timers.get(li);
			if (t) {
				clearTimeout(t);
				timers.delete(li);
			}
		}

		function closeItem(li) {
			clearTimer(li);
			li.classList.remove('vz-open');
			var a = link(li);
			if (a) {
				a.setAttribute('aria-expanded', 'false');
			}
			var nested = li.querySelectorAll('.vz-open');
			for (var i = 0; i < nested.length; i++) {
				nested[i].classList.remove('vz-open');
				var na = link(nested[i]);
				if (na) {
					na.setAttribute('aria-expanded', 'false');
				}
			}
		}

		// Close everything open that is not `keep` or one of its ancestors.
		function closeOthers(keep) {
			var open = header.querySelectorAll('.vz-open');
			for (var i = 0; i < open.length; i++) {
				if (!keep || (open[i] !== keep && !open[i].contains(keep))) {
					closeItem(open[i]);
				}
			}
		}

		// Keep a freshly opened menu inside the viewport: flip flyouts/right-align
		// dropdowns horizontally, shift nested menus up if they run off the bottom.
		function fit(li) {
			var sub = li.querySelector(':scope > .submenu');
			if (!sub || isMobile()) {
				return;
			}
			var nested = li.parentNode.classList.contains('submenu');
			li.classList.remove('vz-flip', 'vz-align-right');
			sub.style.top = '';

			var r = sub.getBoundingClientRect();
			if (nested) {
				// opens to the right by default; flip to the left if clipped, or if the
				// parent menu itself was flipped (keeps the cascade going one direction)
				var parentLi = li.parentNode.parentNode;
				if (r.right > window.innerWidth - 4
						|| (parentLi && parentLi.classList && parentLi.classList.contains('vz-flip'))) {
					li.classList.add('vz-flip');
				}
				r = sub.getBoundingClientRect();
				var over = r.bottom - (window.innerHeight - 4);
				if (over > 0) {
					sub.style.top = Math.max(-over - 6, -(r.top - 4) - 6) + 'px';
				}
			}
			else if (r.right > window.innerWidth - 4) {
				li.classList.add('vz-align-right');
			}
		}

		function openItem(li) {
			clearTimer(li);
			closeOthers(li);
			li.classList.add('vz-open');
			var a = link(li);
			if (a) {
				a.setAttribute('aria-expanded', 'true');
			}
			fit(li);
		}

		// ---------- dropdown wiring (delegated, so items moved into "More" keep working) ----------

		function submenuItemOf(target) {
			var el = target.closest ? target.closest('li.has-submenu, li.vz-more') : null;
			return (el && header.contains(el)) ? el : null;
		}

		header.addEventListener('mouseover', function (e) {
			if (isMobile()) {
				return;
			}
			var li = submenuItemOf(e.target);
			if (!li) {
				return;
			}
			// entering any item cancels pending closes on it and its ancestors
			for (var p = li; p && p !== header; p = p.parentNode) {
				if (p.nodeType === 1 && p.tagName === 'LI') {
					clearTimer(p);
				}
			}
			if (!li.classList.contains('vz-open')) {
				var t = setTimeout(function () { openItem(li); }, OPEN_DELAY);
				timers.set(li, t);
			}
		});

		header.addEventListener('mouseout', function (e) {
			if (isMobile()) {
				return;
			}
			var li = submenuItemOf(e.target);
			if (!li || li.contains(e.relatedTarget)) {
				return;
			}
			clearTimer(li);
			var t = setTimeout(function () { closeItem(li); }, CLOSE_DELAY);
			timers.set(li, t);
		});

		// Click toggles. Parent links already have href="#" (CMenuItem), so
		// preventing default is safe.
		header.addEventListener('click', function (e) {
			var a = e.target.closest ? e.target.closest('a') : null;
			if (!a || !header.contains(a)) {
				return;
			}
			var li = a.parentNode;
			if (li.tagName === 'LI' && (li.classList.contains('has-submenu') || li.classList.contains('vz-more'))
					&& a.parentNode.querySelector(':scope > .submenu')) {
				e.preventDefault();
				if (li.classList.contains('vz-open')) {
					closeItem(li);
				}
				else {
					openItem(li);
				}
			}
		});

		// Keyboard: Enter/Space (native click on <a> covers Enter; add Space),
		// Esc closes + restores focus, arrows move between items, Tab closes on leave.
		header.addEventListener('keydown', function (e) {
			var a = e.target.closest ? e.target.closest('a') : null;
			var li = a ? a.parentNode : null;

			if (e.key === 'Escape') {
				var open = header.querySelectorAll('.vz-open');
				if (open.length) {
					var innermost = open[open.length - 1];
					var trigger = link(innermost) || innermost.querySelector('button');
					closeOthers(null);
					closeSearch();
					if (trigger) {
						trigger.focus();
					}
				}
				return;
			}

			if (!a || !li || li.tagName !== 'LI') {
				return;
			}

			var parentIsSubmenu = li.parentNode.classList.contains('submenu');

			if (e.key === ' ' && li.querySelector(':scope > .submenu')) {
				e.preventDefault();
				a.click();
			}
			else if (e.key === 'ArrowDown') {
				e.preventDefault();
				if (parentIsSubmenu) {
					focusSibling(li, 1);
				}
				else if (li.querySelector(':scope > .submenu')) {
					openItem(li);
					focusFirst(li);
				}
			}
			else if (e.key === 'ArrowUp' && parentIsSubmenu) {
				e.preventDefault();
				focusSibling(li, -1);
			}
			else if (e.key === 'ArrowRight') {
				if (parentIsSubmenu && li.querySelector(':scope > .submenu')) {
					e.preventDefault();
					openItem(li);
					focusFirst(li);
				}
				else if (!parentIsSubmenu) {
					e.preventDefault();
					focusSibling(li, 1);
				}
			}
			else if (e.key === 'ArrowLeft') {
				if (parentIsSubmenu) {
					var parentLi = li.parentNode.parentNode;
					if (parentLi && parentLi.tagName === 'LI' && parentLi.parentNode.classList.contains('submenu')) {
						e.preventDefault();
						closeItem(parentLi);
						link(parentLi).focus();
					}
				}
				else {
					e.preventDefault();
					focusSibling(li, -1);
				}
			}
		});

		function focusFirst(li) {
			var first = li.querySelector(':scope > .submenu > li > a');
			if (first) {
				first.focus();
			}
		}

		function focusSibling(li, dir) {
			var sib = dir > 0 ? li.nextElementSibling : li.previousElementSibling;
			while (sib && (sib.hidden || !link(sib))) {
				sib = dir > 0 ? sib.nextElementSibling : sib.previousElementSibling;
			}
			if (sib) {
				link(sib).focus();
			}
		}

		document.addEventListener('click', function (e) {
			if (!header.contains(e.target)) {
				closeOthers(null);
				closeSearch();
			}
		});

		header.addEventListener('focusout', function (e) {
			if (e.relatedTarget && !header.contains(e.relatedTarget)) {
				closeOthers(null);
				closeSearch();
			}
		});

		// ---------- icon-only user area: accessible names + tooltips ----------

		var userLinks = header.querySelectorAll('.menu-user > li > a');
		for (var u = 0; u < userLinks.length; u++) {
			var name = userLinks[u].textContent.trim();
			if (name !== '') {
				userLinks[u].setAttribute('aria-label', name);
				// Zabbix sets title="<username>" on User settings; keep the
				// username visible too, but make the action name the tooltip lead.
				var existing = userLinks[u].getAttribute('title');
				userLinks[u].setAttribute('title', existing && existing !== name ? name + ' (' + existing + ')' : name);
			}
		}

		// ---------- search: icon that expands into a panel ----------

		var searchBox = header.querySelector('.vz-search');
		var searchToggle = header.querySelector('.vz-search-toggle');

		function closeSearch() {
			if (searchBox && searchBox.classList.contains('vz-open')) {
				searchBox.classList.remove('vz-open');
				searchToggle.setAttribute('aria-expanded', 'false');
			}
		}

		if (searchBox && searchToggle) {
			searchToggle.addEventListener('click', function () {
				var opening = !searchBox.classList.contains('vz-open');
				closeOthers(null);
				if (opening) {
					searchBox.classList.add('vz-open');
					searchToggle.setAttribute('aria-expanded', 'true');
					var input = searchBox.querySelector('input.search');
					if (input) {
						input.focus();
					}
				}
				else {
					closeSearch();
				}
			});
		}

		// ---------- priority+ ("More") ----------

		var more = null;
		var moreList = null;

		function buildMore() {
			more = document.createElement('li');
			more.className = 'vz-more';
			more.hidden = true;

			var a = document.createElement('a');
			a.href = '#';
			a.setAttribute('aria-haspopup', 'true');
			a.setAttribute('aria-expanded', 'false');
			a.setAttribute('title', 'More');
			var icon = document.createElement('span');
			icon.className = 'vz-more-icon';
			var label = document.createElement('span');
			label.textContent = 'More';
			a.appendChild(icon);
			a.appendChild(label);

			moreList = document.createElement('ul');
			moreList.className = 'submenu';

			more.appendChild(a);
			more.appendChild(moreList);
			menu.appendChild(more);
		}

		function layout() {
			if (!menu) {
				return;
			}
			if (!more) {
				buildMore();
			}

			// 1. everything back into the bar, in original order
			while (moreList.firstChild) {
				menu.insertBefore(moreList.firstChild, more);
			}
			more.hidden = true;
			closeItem(more);

			if (isMobile()) {
				return;
			}

			var items = [];
			for (var c = menu.firstElementChild; c; c = c.nextElementSibling) {
				if (c !== more) {
					items.push(c);
				}
			}

			var avail = nav.clientWidth;
			var total = 0;
			for (var i = 0; i < items.length; i++) {
				total += items[i].getBoundingClientRect().width;
			}
			if (total <= avail) {
				return;
			}

			// 2. need More: measure it, then move items from the end until it fits
			more.hidden = false;
			var moreW = more.getBoundingClientRect().width;
			var moved = [];
			while (items.length > 1 && total + moreW > avail) {
				var last = items.pop();
				total -= last.getBoundingClientRect().width;
				moved.unshift(last);
				// detach from flow immediately is not needed for the math above,
				// widths were measured while all items were in the bar.
			}
			for (var m = 0; m < moved.length; m++) {
				moreList.appendChild(moved[m]);
			}
			// keep the "selected" state visible on More when the active page is inside it
			more.classList.toggle('is-selected', !!moreList.querySelector('.is-selected'));
		}

		var rafId = 0;
		function scheduleLayout() {
			if (rafId) {
				cancelAnimationFrame(rafId);
			}
			rafId = requestAnimationFrame(function () {
				rafId = 0;
				layout();
			});
		}

		layout();
		window.addEventListener('resize', scheduleLayout);
		window.addEventListener('load', scheduleLayout);
		if (window.ResizeObserver) {
			new ResizeObserver(scheduleLayout).observe(nav);
		}
		if (document.fonts && document.fonts.ready) {
			document.fonts.ready.then(scheduleLayout);
		}

		// ---------- hamburger (<1024px) ----------

		var hamburger = header.querySelector('.vz-hamburger');
		if (hamburger) {
			hamburger.addEventListener('click', function () {
				var is_open = header.classList.toggle('vz-mobile-open');
				hamburger.setAttribute('aria-expanded', is_open ? 'true' : 'false');
				if (!is_open) {
					closeOthers(null);
				}
			});
			window.addEventListener('resize', function () {
				if (!isMobile() && header.classList.contains('vz-mobile-open')) {
					header.classList.remove('vz-mobile-open');
					hamburger.setAttribute('aria-expanded', 'false');
				}
			});
		}
	});
})();
