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
		'saved' => _('Settings saved.')
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

	function banner(kind, text) {
		const b = $('vz-run-banner');
		b.className = 'vz-upd-banner' + (kind ? ' vz-upd-' + kind : '');
		b.textContent = text || '';
		b.style.display = text ? '' : 'none';
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
		$('vz-run-panel').style.display = '';
		$('vz-run-title').textContent = run.to ? ('Upgrade ' + (run.from || '?') + ' → ' + run.to) : 'Upgrade';
		$('vz-run-step').textContent = run.step || '';

		const bar = $('vz-run-bar');
		bar.style.width = percent(run) + '%';
		bar.className = 'vz-upd-bar-fill' + (run.state === 'failed' ? ' vz-upd-bar-failed' : (run.state === 'done' ? ' vz-upd-bar-done' : ''));

		const pre = $('vz-run-log');
		const atEnd = pre.scrollTop + pre.clientHeight >= pre.scrollHeight - 8;
		pre.textContent = (log || []).join('\n');

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
		document.querySelectorAll('.js-vz-upgrade, #vz-upload, #vz-check-now, #vz-save-config').forEach((b) => {
			b.disabled = busy;
		});
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
							if (!res.ok) {
								$('vz-run-panel').style.display = '';
								banner('err', res.error || D.text.error_generic);
								return;
							}

							$('vz-run-panel').style.display = '';
							$('vz-run-title').textContent = 'Upgrade → ' + version;
							$('vz-run-step').textContent = D.text.starting;
							$('vz-run-log').textContent = '';
							$('vz-run-recovery').textContent = '';
							banner('', '');
							poll(res.id);
						}).catch(() => banner('err', D.text.error_generic));
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

	$('vz-upload').addEventListener('click', () => {
		const fd = new FormData($('vz-upload-form'));
		$('vz-run-panel').style.display = '';
		banner('', '');

		post('upload', null, fd).then((res) => {
			if (!res.ok) {
				banner('err', res.error || D.text.error_generic);
				return;
			}

			$('vz-run-title').textContent = 'Offline upgrade';
			$('vz-run-step').textContent = D.text.starting;
			$('vz-run-log').textContent = '';
			$('vz-run-recovery').textContent = '';
			poll(res.id);
		}).catch(() => banner('err', D.text.error_generic));
	});

	if (D.run) {
		renderRun(D.run, []);

		if (D.run_active) {
			poll(D.run.id);
		}
	}
})();
</script>
