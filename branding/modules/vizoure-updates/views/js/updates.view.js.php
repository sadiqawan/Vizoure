<?php declare(strict_types = 0);
/**
 * @var CView $this
 * @var array $data
 */

$js_data = json_encode([
	'tokens' => $data['tokens'],
	'run' => $data['run'],
	'run_active' => $data['run_active'],
	'installed' => $data['installed'],
	'max_upload' => $data['max_upload'],
	'url' => 'vizoure.php',
	'text' => [
		'confirm_title' => _('Upgrade Vizoure NMS'),
		'confirm_intro' => _('This will upgrade Vizoure NMS now. What will happen:'),
		'confirm_backup' => _('A database backup is taken first and kept in /var/backups/vizoure.'),
		'confirm_restart' => _('Services (web, monitoring server) are restarted. Expect a few minutes of downtime; this page keeps working and reconnects on its own.'),
		'confirm_test' => _('This is a TEST pre-release. Do not use it on a production system.'),
		'confirm_button' => _('Upgrade now'),
		'cancel' => _('Cancel'),
		'restarting' => _('The server is restarting. This is expected during an upgrade; reconnecting...'),
		'success' => _('Upgrade completed successfully.'),
		'failed' => _('The upgrade did not complete.'),
		'backup_kept' => _('Your database backup was kept:'),
		'recovery' => _('Recovery steps'),
		'reload' => _('Reload page'),
		'starting' => _('Request sent. Waiting for the updater service...'),
		'error_generic' => _('The request failed.'),
		'checking' => _('Check requested. The result appears in a few seconds...'),
		'saved' => _('Settings saved.'),
		'in_browser' => _('your browser time')
	]
], JSON_HEX_TAG | JSON_HEX_AMP | JSON_HEX_APOS | JSON_HEX_QUOT);
?>
<script>
(function() {
	'use strict';

	const D = <?= $js_data ?>;
	const TERMINAL = ['done', 'failed'];
	const $ = (id) => document.getElementById(id);

	function post(action, fields, formData) {
		const body = formData || new URLSearchParams();
		body.append('_csrf_token', D.tokens[action]);

		if (!formData) {
			Object.keys(fields || {}).forEach((k) => body.append(k, fields[k]));
		}

		return fetch(D.url + '?action=vizoure.updates.' + action, {
			method: 'POST', body: body, credentials: 'same-origin', cache: 'no-store'
		}).then((r) => r.json());
	}

	function el(tag, text, cls) {
		const e = document.createElement(tag);

		if (text !== undefined) {
			e.textContent = text;
		}

		if (cls) {
			e.className = cls;
		}

		return e;
	}

	/* ---------- times: server/Zabbix-user time zone is shown by PHP; add the browser's if it differs ---------- */
	document.querySelectorAll('.js-vz-time').forEach((t) => {
		const ts = parseInt(t.dataset.ts, 10);
		const zbx_offset = parseInt(t.dataset.offset, 10);
		const browser_offset = -new Date(ts * 1000).getTimezoneOffset() * 60;

		if (zbx_offset !== browser_offset) {
			const local = new Date(ts * 1000).toLocaleString(undefined, {
				year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', second: '2-digit',
				hour12: false, timeZoneName: 'short'
			});
			t.appendChild(el('span', ' (' + local + ', ' + D.text.in_browser + ')', 'vz-upd-note vz-upd-small'));
		}
	});

	/* ---------- progress panel (only exists while an upgrade runs) ---------- */
	function showPanel() {
		$('vz-run-panel').style.display = '';
	}

	function banner(kind, text) {
		const b = $('vz-run-banner');
		b.className = 'vz-upd-banner' + (kind ? ' vz-upd-' + kind : '');
		b.textContent = text || '';
		b.style.display = text ? 'block' : 'none';
	}

	function percent(run) {
		const map = {queued: 4, validating: 10, downloading: 25, verifying: 40, extracting: 50, upgrading: 55, done: 100, failed: 100};
		let p = map[run.state] || 0;
		const m = /\((\d)\/(\d)\)\s*$/.exec(run.step || '');

		if (run.state === 'upgrading' && m) {
			p = 55 + Math.round((parseInt(m[1], 10) / parseInt(m[2], 10)) * 40);
		}

		return p;
	}

	function renderRun(run, log) {
		showPanel();
		$('vz-run-title').textContent = run.to ? ('Upgrade ' + (run.from || '?') + ' → ' + run.to) : 'Upgrade';
		$('vz-run-step').textContent = run.step || '';

		const bar = $('vz-run-bar');
		bar.style.width = percent(run) + '%';
		bar.className = 'vz-upd-bar-fill' + (run.state === 'failed' ? ' vz-upd-bar-failed' : (run.state === 'done' ? ' vz-upd-bar-done' : ''));

		const pre = $('vz-run-log');
		const atEnd = pre.scrollTop + pre.clientHeight >= pre.scrollHeight - 8;
		pre.textContent = (log || []).join('\n');
		pre.style.display = (log && log.length) ? '' : 'none';

		if (atEnd) {
			pre.scrollTop = pre.scrollHeight;
		}

		const rec = $('vz-run-recovery');
		rec.textContent = '';

		if (run.state === 'done') {
			banner('ok', D.text.success + (run.backup_file ? '  Backup: ' + run.backup_file : ''));
		}
		else if (run.state === 'failed') {
			banner('err', D.text.failed + (run.error ? ' ' + run.error : '') +
				(run.backup_file ? ' ' + D.text.backup_kept + ' ' + run.backup_file : ''));

			if (run.recovery && run.recovery.length) {
				rec.appendChild(el('strong', D.text.recovery));
				const ol = el('ol');
				run.recovery.forEach((s) => ol.appendChild(el('li', s)));
				rec.appendChild(ol);
			}
		}
	}

	let polling = false;
	let outageSince = null;

	function setBusy(busy) {
		document.querySelectorAll('.js-vz-upgrade, #vz-check-now, #vz-save-config').forEach((b) => {
			b.disabled = busy;
		});
		$('vz-upload').disabled = busy || !uploadReady();
	}

	function poll(runId) {
		if (polling) {
			return;
		}

		polling = true;
		setBusy(true);

		const tick = () => {
			post('status', {id: runId || ''}).then((res) => {
				if (outageSince !== null) {
					outageSince = null;
					banner('', '');
				}

				if (!res.ok || !res.run) {
					setTimeout(tick, 2000);
					return;
				}

				runId = res.run.id;
				renderRun(res.run, res.log);

				if (TERMINAL.indexOf(res.run.state) !== -1) {
					polling = false;
					setBusy(false);

					if (res.run.state === 'done') {
						const btn = el('button', D.text.reload, 'btn-alt');
						btn.type = 'button';
						btn.onclick = () => location.reload();
						$('vz-run-recovery').appendChild(btn);
						setTimeout(() => location.reload(), 4000);
					}

					return;
				}

				setTimeout(tick, 2000);
			}).catch(() => {
				// Apache/PHP is restarting mid-upgrade: keep retrying (up to 15 minutes), then give up.
				if (outageSince === null) {
					outageSince = Date.now();
				}

				if (Date.now() - outageSince > 15 * 60 * 1000) {
					polling = false;
					setBusy(false);
					banner('err', D.text.error_generic + ' Reload the page to check the result.');
					return;
				}

				banner('warn', D.text.restarting);
				setTimeout(tick, 3000);
			});
		};

		tick();
	}

	function startRunUi(title) {
		showPanel();
		$('vz-run-title').textContent = title;
		$('vz-run-step').textContent = D.text.starting;
		$('vz-run-bar').style.width = '4%';
		$('vz-run-bar').className = 'vz-upd-bar-fill';
		$('vz-run-log').textContent = '';
		$('vz-run-log').style.display = 'none';
		$('vz-run-recovery').textContent = '';
		banner('', '');
	}

	function confirmUpgrade(version, prerelease) {
		const content = el('div', undefined, 'vz-upd-confirm');
		content.appendChild(el('p', D.text.confirm_intro));
		const ul = el('ul');
		[D.text.confirm_backup, D.text.confirm_restart].forEach((t) => ul.appendChild(el('li', t)));
		content.appendChild(ul);
		content.appendChild(el('p', (D.installed || '?') + ' → ' + version, 'vz-upd-mono'));

		if (prerelease) {
			content.appendChild(el('p', D.text.confirm_test, 'vz-upd-warn'));
		}

		overlayDialogue({
			title: D.text.confirm_title,
			class: 'modal-popup',
			content: jQuery(content),
			buttons: [
				{
					title: D.text.confirm_button,
					class: 'js-vz-confirm',
					isSubmit: true,
					action: () => {
						post('upgrade', {version: version}).then((res) => {
							startRunUi('Upgrade → ' + version);

							if (!res.ok) {
								banner('err', res.error || D.text.error_generic);
								return;
							}

							poll(res.id);
						}).catch(() => {
							startRunUi('Upgrade → ' + version);
							banner('err', D.text.error_generic);
						});
					}
				},
				{title: D.text.cancel, class: 'btn-alt js-cancel', cancel: true, action: () => {}}
			]
		}, {trigger_element: document.activeElement});
	}

	document.querySelectorAll('.js-vz-upgrade').forEach((b) => {
		b.addEventListener('click', () => confirmUpgrade(b.dataset.version, b.dataset.prerelease === '1'));
	});

	$('vz-check-now').addEventListener('click', () => {
		$('vz-check-note').textContent = D.text.checking;
		post('check').then((res) => {
			if (!res.ok) {
				$('vz-check-note').textContent = res.error || D.text.error_generic;
				return;
			}

			setTimeout(() => location.reload(), 6000);
		}).catch(() => {
			$('vz-check-note').textContent = D.text.error_generic;
		});
	});

	$('vz-save-config').addEventListener('click', () => {
		post('config', {channel: $('vz-channel').value, proxy: $('vz-proxy').value}).then((res) => {
			$('vz-check-note').textContent = res.ok ? D.text.saved : (res.error || D.text.error_generic);

			if (res.ok) {
				setTimeout(() => location.reload(), 3000);
			}
		}).catch(() => {
			$('vz-check-note').textContent = D.text.error_generic;
		});
	});

	/* ---------- offline upload: ONE multi-file picker, identified by name, validated before upload ---------- */
	const RULES = {
		package: {re: /^vizoure-nms-v\d+\.\d+\.\d+-vz\d+-install\.tar\.gz$/, expected: 'vizoure-nms-<version>-install.tar.gz'},
		sums: {re: /^SHA256SUMS$/, expected: 'SHA256SUMS'},
		sig: {re: /^SHA256SUMS\.sig$/, expected: 'SHA256SUMS.sig'}
	};
	let picked = {package: null, sums: null, sig: null};

	function uploadReady() {
		return !!(picked.package && picked.sums && picked.sig);
	}

	function explain(f) {
		const n = f.name;

		if (/^sha256sums?\.(txt|sha256|asc|sig\.txt)$/i.test(n) || /^sha256sums?$/i.test(n) || /checksum|\.sha256$/i.test(n)) {
			return '"' + n + '" is not the release checksum file. Use the file named exactly SHA256SUMS (no extension) from the Vizoure release page; a checksum list from another folder or website will not work.';
		}

		if (/\.(sig|asc|gpg|minisig)$/i.test(n)) {
			return '"' + n + '" is not the release signature. The signature must be named exactly SHA256SUMS.sig.';
		}

		if (/\.(tar\.gz|tgz|zip|tar|gz)$/i.test(n)) {
			return '"' + n + '" is not a Vizoure release package. Expected vizoure-nms-<version>-install.tar.gz from the release assets (not the "Source code" archive).';
		}

		return '"' + n + '" is not one of the 3 release files (vizoure-nms-<version>-install.tar.gz, SHA256SUMS, SHA256SUMS.sig).';
	}

	function renderPicked(problems) {
		['package', 'sums', 'sig'].forEach((k) => {
			const li = document.querySelector('#vz-upload-form li[data-kind="' + k + '"]');
			const mark = li.querySelector('[data-mark]');
			const exp = li.querySelector('[data-expected]');
			const f = picked[k];

			mark.textContent = f ? '✔' : '○';
			mark.className = 'vz-upd-mark' + (f ? ' vz-upd-mark-ok' : '');
			exp.textContent = f ? f.name + '  (' + (f.size / 1024).toFixed(f.size < 10240 ? 1 : 0) + ' KB)' : RULES[k].expected + ' – missing';
		});

		const box = $('vz-file-problems');
		box.textContent = '';
		problems.forEach((p) => box.appendChild(el('div', '✖ ' + p, 'vz-upd-problem')));
		$('vz-upload').disabled = polling || !uploadReady();
	}

	function takeFiles(fileList) {
		const problems = [];
		picked = {package: null, sums: null, sig: null};

		Array.prototype.forEach.call(fileList, (f) => {
			const kind = Object.keys(RULES).find((k) => RULES[k].re.test(f.name));

			if (!kind) {
				problems.push(explain(f));
			}
			else if (f.size > D.max_upload) {
				problems.push('"' + f.name + '" is larger than the ' + (D.max_upload / 1048576) + ' MB limit.');
			}
			else if (picked[kind]) {
				problems.push('Two files look like the ' + kind + ' file: "' + picked[kind].name + '" and "' + f.name + '". Select only one of each.');
			}
			else {
				picked[kind] = f;
			}
		});

		renderPicked(problems);
	}

	const fileInput = $('vz-files');
	fileInput.addEventListener('change', () => takeFiles(fileInput.files));

	const drop = $('vz-drop');
	['dragenter', 'dragover'].forEach((ev) => drop.addEventListener(ev, (e) => {
		e.preventDefault();
		drop.classList.add('vz-upd-drop-over');
	}));
	['dragleave', 'drop'].forEach((ev) => drop.addEventListener(ev, (e) => {
		e.preventDefault();
		drop.classList.remove('vz-upd-drop-over');
	}));
	drop.addEventListener('drop', (e) => takeFiles(e.dataTransfer.files));
	drop.addEventListener('click', (e) => {
		if (e.target !== fileInput) {
			fileInput.click();
		}
	});

	$('vz-upload').addEventListener('click', () => {
		if (!uploadReady()) {
			return;
		}

		const fd = new FormData();
		fd.append('package', picked.package, picked.package.name);
		fd.append('sums', picked.sums, picked.sums.name);
		fd.append('sig', picked.sig, picked.sig.name);
		startRunUi('Offline upgrade');

		post('upload', null, fd).then((res) => {
			if (!res.ok) {
				banner('err', res.error || D.text.error_generic);
				$('vz-run-step').textContent = '';
				return;
			}

			poll(res.id);
		}).catch(() => banner('err', D.text.error_generic));
	});

	renderPicked([]);

	if (D.run && D.run_active) {
		renderRun(D.run, []);
		poll(D.run.id);
	}
})();
</script>
