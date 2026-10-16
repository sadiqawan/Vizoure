<?php declare(strict_types = 0);

namespace Modules\VizoureUpdates\Actions;

/** POST + CSRF: request an upgrade to a published release. The root service re-validates everything. */
class UpdatesUpgrade extends UpdatesBase {

	protected function checkInput(): bool {
		$ok = $this->validateInput(['version' => 'required|string']);

		if (!$ok) {
			$this->jsonError(_('Invalid request.'));
		}

		return $ok;
	}

	protected function doAction(): void {
		$version = (string) $this->getInput('version');

		if (!preg_match('/^v\d+\.\d+\.\d+-vz\d+$/', $version)) {
			$this->jsonError(_('Not a valid release version.'));
			return;
		}

		// UX pre-check only (the updater enforces the same rules): the release must be listed and eligible.
		$state = $this->state();
		$channel = $state['channel'] ?? 'stable';
		$eligible = [];

		foreach ($state['releases'] ?? [] as $r) {
			if ($channel === 'test' || empty($r['prerelease'])) {
				$eligible[] = $r['tag'] ?? '';
			}
		}

		if (!in_array($version, $eligible, true)) {
			$this->jsonError(_('This release is not available on your update channel.'));
			return;
		}

		try {
			$id = $this->newId();
			$this->writeRequest($id, ['action' => 'upgrade', 'version' => $version]);
			$this->audit('upgrade', ['request' => $id, 'to' => $version, 'from' => $state['installed'] ?? null]);
			$this->json(['ok' => true, 'id' => $id]);
		}
		catch (\Throwable $e) {
			$this->jsonError($e->getMessage());
		}
	}
}
