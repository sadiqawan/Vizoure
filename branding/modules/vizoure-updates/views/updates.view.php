<?php declare(strict_types = 0);
/* Vizoure NMS — "Vizoure updates" page (Super admin only). All text below is escaped by the CTag layer.
 * Colours come from the active Zabbix theme (no hard-coded light/dark values), see vizoure-updates.css.
 *
 * @var CView $this
 * @var array $data
 */

$state = $data['state'];
$installed = $data['installed'];
$releases_url = 'https://github.com/sadiqawan/Vizoure/releases';

/** A time rendered in the user's Zabbix time zone, with the zone shown; the JS adds the browser's local time if it differs. */
$time = function (int $ts): CTag {
	$tz = new DateTimeZone(date_default_timezone_get());
	$abbr = (new DateTime('@'.$ts))->setTimezone($tz)->format('T');

	return (new CTag('time', true, zbx_date2str(DATE_TIME_FORMAT_SECONDS, $ts).' '.$abbr))
		->addClass('js-vz-time')
		->setAttribute('datetime', gmdate('c', $ts))
		->setAttribute('data-ts', (string) $ts)
		->setAttribute('data-offset', (string) $tz->getOffset(new DateTime('@'.$ts)));
};

// ----- status / settings -----
$check_note = [];

if (!$state) {
	$check_note[] = _('The updater service has not reported yet. It checks for releases every 6 hours, or press "Check now".');
}
elseif (($state['last_check_ok'] ?? null) === false) {
	$check_note[] = _s('Last check failed: %1$s. You can still upgrade offline with a release package (below).',
		$state['last_error'] ?? ''
	);
}
elseif (!empty($state['last_check_ts'])) {
	$check_note = [_('Last checked:').' ', $time((int) $state['last_check_ts'])];
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
		(new CSpan($installed ?: _('unknown')))->addClass('vz-upd-version')->setId('vz-installed')
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

// ----- last upgrade failed/interrupted (shown instead of an empty progress panel) -----
$failed_box = null;

if ($data['last_failed'] !== null) {
	$f = $data['last_failed'];
	$steps = new CTag('ol', true);

	foreach ((array) ($f['recovery'] ?? []) as $s) {
		$steps->addItem(new CTag('li', true, (string) $s));
	}

	$failed_box = (new CDiv([
		(new CDiv([
			(new CTag('strong', true, _s('The last upgrade (%1$s to %2$s) did not complete.', (string) ($f['from'] ?? '?'),
				(string) ($f['to'] ?? '?')
			))),
			' ', (string) ($f['error'] ?? '')
		]))->addClass('vz-upd-banner vz-upd-err')->addStyle('display:block'),
		(new CTag('details', true, [
			(new CTag('summary', true, _('Recovery steps')))->addClass(ZBX_STYLE_LINK_ACTION),
			$steps
		]))->addClass('vz-upd-recovery')->setAttribute('open', 'open'),
		$f['log'] ? (new CTag('details', true, [
			(new CTag('summary', true, _('Upgrade log')))->addClass(ZBX_STYLE_LINK_ACTION),
			(new CTag('pre', true, implode("\n", $f['log'])))->addClass('vz-upd-log')
		]))->addClass('vz-upd-recovery')->setAttribute('open', 'open') : null
	]))->addClass('vz-upd-card');
}

// ----- run / progress panel: hidden until an upgrade is running (filled by JS) -----
$run_panel = (new CDiv([
	(new CDiv())->addClass('vz-upd-run-title')->setId('vz-run-title'),
	(new CDiv((new CDiv())->addClass('vz-upd-bar-fill')->setId('vz-run-bar')))->addClass('vz-upd-bar'),
	(new CDiv())->addClass('vz-upd-run-step')->setId('vz-run-step'),
	(new CDiv())->addClass('vz-upd-banner')->setId('vz-run-banner'),
	(new CDiv())->addClass('vz-upd-recovery')->setId('vz-run-recovery'),
	(new CTag('pre', true))->addClass('vz-upd-log')->setId('vz-run-log')
]))->addClass('vz-upd-card')->setId('vz-run-panel')->addStyle('display:none');

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
	$released = $rel['published_at'] !== '' ? strtotime($rel['published_at']) : false;

	$available_table->addRow([
		(new CCol($rel['tag']))->addClass(ZBX_STYLE_NOWRAP),
		$rel['prerelease'] ? _('test (pre-release)') : _('stable'),
		$released ? zbx_date2str(DATE_FORMAT, $released) : '-',
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

// ----- offline upload: ONE multi-file picker + checklist -----
$file_rows = [
	['package', _('Release package'), 'vizoure-nms-<version>-install.tar.gz'],
	['sums', _('Checksums'), 'SHA256SUMS'],
	['sig', _('Signature'), 'SHA256SUMS.sig']
];
$checklist = new CTag('ul', true);

foreach ($file_rows as [$kind, $label, $expected]) {
	$checklist->addItem(
		(new CTag('li', true, [
			(new CSpan("\u{25CB}"))->addClass('vz-upd-mark')->setAttribute('data-mark', $kind),
			(new CSpan($label))->addClass('vz-upd-file-label'),
			' ',
			(new CSpan($expected))->addClass('vz-upd-mono vz-upd-note')->setAttribute('data-expected', $kind)
		]))->setAttribute('data-kind', $kind)
	);
}

$upload_form = (new CForm('post', null, 'multipart/form-data'))
	->setId('vz-upload-form')
	->setAttribute('onsubmit', 'return false;')
	->addItem([
		(new CDiv([
			_('Offline upgrade: download the 3 files of a release from the '),
			(new CLink(_('Vizoure releases page'), $releases_url))->setTarget('_blank')
				->setAttribute('rel', 'noopener noreferrer'),
			_(' on a machine with internet access, then select all 3 here. The package must be signed by Vizoure; unsigned or modified packages are rejected.')
		]))->addClass('vz-upd-note'),
		(new CDiv([
			(new CDiv([
				(new CTag('strong', true, _('Select the 3 release files'))),
				(new CTag('div', true, _('Drop them here, or click to choose (hold Ctrl/Shift to select several).')))
					->addClass('vz-upd-note'),
				(new CInput('file', 'vz-files'))->setId('vz-files')->setAttribute('multiple', 'multiple')
					->setAttribute('accept', '.gz,.sig,.txt,application/gzip,application/octet-stream,text/plain')
			]))->addClass('vz-upd-drop')->setId('vz-drop'),
			(new CDiv([
				$checklist,
				(new CDiv())->addClass('vz-upd-problems')->setId('vz-file-problems')
			]))->addClass('vz-upd-checks')
		]))->addClass('vz-upd-row vz-upd-upload-row'),
		(new CDiv([
			(new CButton('vz-upload', _('Upload and upgrade')))->setId('vz-upload')->setAttribute('disabled', 'disabled'),
			(new CSpan(_s('Each file may be up to %1$s MB. If SHA256SUMS is greyed out in the file dialog, switch the dialog filter to "All files".', $data['max_upload'] / 1048576)))->addClass('vz-upd-note')
		]))->addClass('vz-upd-row')
	]);

// ----- history -----
$history_table = (new CTableInfo())
	->setHeader([_('When'), _('User'), _('From'), _('To'), _('Source'), _('Mode'), _('Result'), _('Backup')])
	->setNoDataMessage(_('No upgrades yet'));

$result_labels = ['success' => _('success'), 'failed' => _('failed'), 'interrupted' => _('interrupted'),
	'rejected' => _('rejected (nothing changed)')];

foreach ($data['history'] as $h) {
	$result = $result_labels[$h['result'] ?? ''] ?? (string) ($h['result'] ?? '');
	$result_class = ['success' => ZBX_STYLE_GREEN, 'rejected' => ZBX_STYLE_ORANGE][$h['result'] ?? ''] ?? ZBX_STYLE_RED;
	$result_cell = [(new CSpan($result))->addClass($result_class)];

	if (!empty($h['error'])) {
		$result_cell[] = (new CDiv(trim((string) $h['error'].' '.(string) ($h['fix'] ?? ''))))
			->addClass('vz-upd-note vz-upd-small');
	}

	$history_table->addRow([
		isset($h['started']) ? $time((int) $h['started']) : '-',
		(string) ($h['user'] ?? '-'),
		(string) ($h['from'] ?? '-'),
		(string) ($h['to'] ?? '-'),
		(string) ($h['source'] ?? '-'),
		(string) ($h['mode'] ?? '-'),
		$result_cell,
		(new CSpan((string) ($h['backup_file'] ?? '-')))->addClass('vz-upd-mono')
	]);
}

(new CHtmlPage())
	->setTitle(_('Vizoure updates'))
	->addItem([
		$status_box,
		$failed_box,
		$run_panel,
		(new CTag('h4', true, _('Available updates')))->addClass('vz-upd-h'),
		$available_block,
		(new CTag('h4', true, _('Upgrade offline (release package)')))->addClass('vz-upd-h'),
		(new CDiv($upload_form))->addClass('vz-upd-card'),
		(new CTag('h4', true, _('Upgrade history')))->addClass('vz-upd-h'),
		$history_table
	])
	->show();

$this->includeJsFile('updates.view.js.php', [
	'tokens' => $data['tokens'],
	'run' => $data['run'],
	'run_active' => $data['run_active'],
	'installed' => $installed,
	'channel' => $data['channel'],
	'max_upload' => $data['max_upload']
]);
