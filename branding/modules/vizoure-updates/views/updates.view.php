<?php declare(strict_types = 0);
/* Vizoure NMS — "Vizoure updates" page (Super admin only). All text below is escaped by the CTag layer.
 *
 * @var CView $this
 * @var array $data
 */

$state = $data['state'];
$installed = $data['installed'];

// ----- status / settings -----
$check_note = '';

if (!$state) {
	$check_note = _('The updater service has not reported yet. It checks for releases every 6 hours, or press "Check now".');
}
elseif (($state['last_check_ok'] ?? null) === false) {
	$check_note = _s('Last check failed: %1$s. You can still upgrade offline with a release package (below).',
		$state['last_error'] ?? ''
	);
}
elseif (!empty($state['last_check_ts'])) {
	$check_note = _s('Last checked: %1$s.', date(ZBX_FULL_DATE_TIME, (int) $state['last_check_ts']));
}

$channel_select = (new CSelect('vz-channel'))
	->setId('vz-channel')
	->setValue($data['channel'])
	->addOptions(CSelect::createOptionsFromArray([
		'stable' => _('Stable (recommended)'),
		'test' => _('Test (pre-releases)')
	]));

$status_box = (new CDiv([
	(new CDiv([
		(new CSpan(_('Installed version')))->addClass('vz-upd-label'),
		(new CSpan($installed ?: _('unknown')))->addClass('vz-upd-value')->setId('vz-installed')
	]))->addClass('vz-upd-row'),
	(new CDiv([
		(new CSpan(_('Update channel')))->addClass('vz-upd-label'),
		$channel_select,
		(new CTextBox('vz-proxy', (string) ($state['proxy'] ?? ''), false, 200))
			->setId('vz-proxy')
			->setAttribute('placeholder', _('HTTP proxy (optional), e.g. http://proxy:3128'))
			->setWidth(ZBX_TEXTAREA_STANDARD_WIDTH),
		(new CButton('vz-save-config', _('Save settings')))->addClass(ZBX_STYLE_BTN_ALT)->setId('vz-save-config')
	]))->addClass('vz-upd-row'),
	(new CDiv([
		(new CButton('vz-check-now', _('Check now')))->setId('vz-check-now'),
		(new CSpan($check_note))->addClass('vz-upd-note')->setId('vz-check-note')
	]))->addClass('vz-upd-row')
]))->addClass('vz-upd-card');

// ----- run / progress panel (filled by JS) -----
$run_panel = (new CDiv([
	(new CDiv())->addClass('vz-upd-run-title')->setId('vz-run-title'),
	(new CDiv((new CDiv())->addClass('vz-upd-bar-fill')->setId('vz-run-bar')))->addClass('vz-upd-bar'),
	(new CDiv())->addClass('vz-upd-run-step')->setId('vz-run-step'),
	(new CDiv())->addClass('vz-upd-banner')->setId('vz-run-banner'),
	(new CDiv())->addClass('vz-upd-recovery')->setId('vz-run-recovery'),
	(new CTag('pre', true))->addClass('vz-upd-log')->setId('vz-run-log')
]))->addClass('vz-upd-card')->setId('vz-run-panel');

if ($data['run'] === null) {
	$run_panel->addStyle('display:none');
}

// ----- available releases -----
$available_table = (new CTableInfo())
	->setHeader([_('Version'), _('Channel'), _('Released'), _('What is new'), ''])
	->setId('vz-available');

foreach ($data['available'] as $rel) {
	$notes = trim($rel['notes'] !== '' ? $rel['notes'] : _('No release notes were published.'));
	$button = (new CButton('vz-upgrade-'.$rel['tag'], _s('Upgrade to %1$s', $rel['tag'])))
		->addClass('js-vz-upgrade')
		->setAttribute('data-version', $rel['tag'])
		->setAttribute('data-prerelease', $rel['prerelease'] ? '1' : '0');

	$available_table->addRow([
		(new CCol($rel['tag']))->addClass(ZBX_STYLE_NOWRAP),
		$rel['prerelease'] ? _('test (pre-release)') : _('stable'),
		$rel['published_at'] !== '' ? substr($rel['published_at'], 0, 10) : '-',
		(new CTag('details', true, [
			(new CTag('summary', true, _('Release notes')))->addClass(ZBX_STYLE_LINK_ACTION),
			(new CTag('pre', true, $notes))->addClass('vz-upd-notes')
		])),
		$button
	]);
}

$available_block = $data['available']
	? $available_table
	: (new CDiv($installed ? _s('You are up to date (%1$s).', $installed) : _('No newer release is available.')))
		->addClass('vz-upd-note')->setId('vz-uptodate');

// ----- offline upload -----
$upload_form = (new CForm('post', null, 'multipart/form-data'))
	->setId('vz-upload-form')
	->addItem([
		(new CDiv(_('Offline upgrade: choose the three files published with a release. The package must be signed by Vizoure; unsigned or modified packages are rejected.')))->addClass('vz-upd-note'),
		(new CDiv([
			(new CLabel(_('Package (vizoure-nms-<version>-install.tar.gz)'), 'vz-up-package')),
			(new CInput('file', 'package'))->setId('vz-up-package')->setAttribute('accept', '.gz')
		]))->addClass('vz-upd-row'),
		(new CDiv([
			(new CLabel(_('SHA256SUMS'), 'vz-up-sums')),
			(new CInput('file', 'sums'))->setId('vz-up-sums')
		]))->addClass('vz-upd-row'),
		(new CDiv([
			(new CLabel(_('SHA256SUMS.sig'), 'vz-up-sig')),
			(new CInput('file', 'sig'))->setId('vz-up-sig')
		]))->addClass('vz-upd-row'),
		(new CDiv([
			(new CButton('vz-upload', _('Upload and upgrade')))->setId('vz-upload'),
			(new CSpan(_s('Each file may be up to %1$s MB.', $data['max_upload'] / 1048576)))->addClass('vz-upd-note')
		]))->addClass('vz-upd-row')
	]);

// ----- history -----
$history_table = (new CTableInfo())
	->setHeader([_('When'), _('User'), _('From'), _('To'), _('Source'), _('Mode'), _('Result'), _('Backup')]);

$result_labels = ['success' => _('success'), 'failed' => _('failed'), 'interrupted' => _('interrupted')];

foreach ($data['history'] as $h) {
	$result = $result_labels[$h['result'] ?? ''] ?? (string) ($h['result'] ?? '');
	$history_table->addRow([
		isset($h['started']) ? date(ZBX_FULL_DATE_TIME, (int) $h['started']) : '-',
		(string) ($h['user'] ?? '-'),
		(string) ($h['from'] ?? '-'),
		(string) ($h['to'] ?? '-'),
		(string) ($h['source'] ?? '-'),
		(string) ($h['mode'] ?? '-'),
		(new CSpan($result))->addClass(($h['result'] ?? '') === 'success' ? ZBX_STYLE_GREEN : ZBX_STYLE_RED)
			->setTitle((string) ($h['error'] ?? '')),
		(new CSpan((string) ($h['backup_file'] ?? '-')))->addClass('vz-upd-mono')
	]);
}

(new CHtmlPage())
	->setTitle(_('Vizoure updates'))
	->addItem([
		$status_box,
		$run_panel,
		(new CTag('h4', true, _('Available updates')))->addClass('vz-upd-h'),
		$available_block,
		(new CTag('h4', true, _('Upload release package (offline)')))->addClass('vz-upd-h'),
		(new CDiv($upload_form))->addClass('vz-upd-card'),
		(new CTag('h4', true, _('Upgrade history')))->addClass('vz-upd-h'),
		$history_table
	])
	->show();

$this->includeJsFile('updates.view.js.php', [
	'tokens' => $data['tokens'],
	'run' => $data['run'],
	'run_active' => $data['run_active'],
	'installed' => $installed
]);
