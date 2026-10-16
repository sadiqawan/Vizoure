<?php declare(strict_types = 0);

namespace Modules\VizoureUpdates\Actions;

/** POST poll: returns updater state, the run status and the log tail. Read-only. */
class UpdatesStatus extends UpdatesBase {

	protected function checkInput(): bool {
		return $this->validateInput(['id' => 'string']);
	}

	protected function doAction(): void {
		$id = (string) $this->getInput('id', '');
		$run = $id !== '' ? $this->runStatus($id) : $this->latestRun();
		$state = $this->state();

		$this->json([
			'ok' => true,
			'server_time' => time(),
			'installed' => $state['installed'] ?? null,
			'channel' => $state['channel'] ?? 'stable',
			'last_check_ts' => $state['last_check_ts'] ?? 0,
			'last_check_ok' => $state['last_check_ok'] ?? null,
			'last_error' => $state['last_error'] ?? '',
			'update_available' => $state['update_available'] ?? null,
			'run' => $run,
			'log' => $run ? $this->logTail((string) $run['id']) : []
		]);
	}
}
