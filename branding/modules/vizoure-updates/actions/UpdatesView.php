<?php declare(strict_types = 0);

namespace Modules\VizoureUpdates\Actions;

use CCsrfTokenHelper,
	CControllerResponseData;

class UpdatesView extends UpdatesBase {

	/** Read-only page opened by a plain GET link: no CSRF token is sent. All POST actions keep CSRF on. */
	protected function init(): void {
		$this->disableCsrfValidation();
	}

	protected function checkInput(): bool {
		return $this->validateInput([]);
	}

	protected function doAction(): void {
		$state = $this->state();
		$installed = $state['installed'] ?? null;

		if ($installed === null) {
			// no status report yet (fresh install): read the one place the version is recorded
			$v = trim((string) @file_get_contents('/etc/vizoure/version', false, null, 0, 64));
			$installed = preg_match('/^v\d+\.\d+\.\d+-vz\d+$/', $v) ? $v : null;
		}
		$channel = $state['channel'] ?? 'stable';

		// Releases newer than installed that are visible on the chosen channel, newest first.
		$current = $this->versionTuple($installed) ?? [0, 0, 0, 0];
		$available = [];

		foreach ($state['releases'] ?? [] as $rel) {
			$tuple = $this->versionTuple($rel['tag'] ?? null);

			if ($tuple !== null && $tuple > $current && ($channel === 'test' || empty($rel['prerelease']))) {
				$available[] = [
					'tag' => $rel['tag'],
					'prerelease' => !empty($rel['prerelease']),
					'published_at' => (string) ($rel['published_at'] ?? ''),
					'notes' => (string) ($rel['notes'] ?? '')
				];
			}
		}

		usort($available, function ($a, $b) {
			return $this->versionTuple($b['tag']) <=> $this->versionTuple($a['tag']);
		});

		$latest = $this->latestRun();
		$active = ($latest !== null && in_array($latest['state'] ?? '', ['queued', 'validating', 'downloading',
			'verifying', 'extracting', 'upgrading'], true)) ? $latest : null;

		// The progress panel only exists for a running upgrade. A failed/interrupted LAST run is shown as a
		// compact warning with its recovery steps instead (and every run is in the history table).
		$last_failed = null;

		if ($latest !== null && ($latest['state'] ?? '') === 'failed' && (time() - (int) ($latest['ended'] ?? 0)) < 14 * 86400) {
			$last_failed = $latest;
			$last_failed['log'] = $this->logTail((string) $latest['id'], 200);
		}

		// Module actions are CSRF-checked against the full action name.
		$tokens = [];

		foreach (['check', 'upgrade', 'upload', 'config', 'status'] as $a) {
			$tokens[$a] = CCsrfTokenHelper::get('vizoure.updates.'.$a);
		}

		$response = new CControllerResponseData([
			'title' => _('Vizoure updates'),
			'state' => $state,
			'installed' => $installed,
			'channel' => $channel,
			'available' => $available,
			'history' => $this->history(),
			'run' => $active,
			'last_failed' => $last_failed,
			'run_active' => $active !== null,
			'tokens' => $tokens,
			'max_upload' => self::MAX_UPLOAD,
			'user' => ['debug_mode' => $this->getDebugMode()]
		]);
		$response->setTitle(_('Vizoure updates'));
		$this->setResponse($response);
	}
}
