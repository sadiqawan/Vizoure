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
			'run' => $active ?? $latest,
			'run_active' => $active !== null,
			'tokens' => $tokens,
			'max_upload' => self::MAX_UPLOAD,
			'user' => ['debug_mode' => $this->getDebugMode()]
		]);
		$response->setTitle(_('Vizoure updates'));
		$this->setResponse($response);
	}
}
