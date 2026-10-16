<?php declare(strict_types = 0);

namespace Modules\VizoureUpdates\Actions;

/** POST + CSRF: change the update channel and the proxy used by the updater (validated again as root). */
class UpdatesConfig extends UpdatesBase {

	protected function checkInput(): bool {
		$ok = $this->validateInput(['channel' => 'required|in stable,test', 'proxy' => 'string']);

		if (!$ok) {
			$this->jsonError(_('Invalid settings.'));
		}

		return $ok;
	}

	protected function doAction(): void {
		$proxy = trim((string) $this->getInput('proxy', ''));

		if ($proxy !== '' && !preg_match('#^https?://[A-Za-z0-9.\-]+(:\d{1,5})?$#', $proxy)) {
			$this->jsonError(_('Proxy must look like http://host:port (no credentials).'));
			return;
		}

		try {
			$id = $this->newId();
			$channel = (string) $this->getInput('channel');
			$this->writeRequest($id, ['action' => 'set_config', 'channel' => $channel, 'proxy' => $proxy]);
			$this->audit('config', ['request' => $id, 'channel' => $channel, 'proxy_set' => $proxy !== '']);
			$this->json(['ok' => true, 'id' => $id]);
		}
		catch (\Throwable $e) {
			$this->jsonError($e->getMessage());
		}
	}
}
