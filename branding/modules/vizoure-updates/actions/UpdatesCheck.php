<?php declare(strict_types = 0);

namespace Modules\VizoureUpdates\Actions;

/** POST + CSRF: asks the root service to refresh the GitHub release list ("Check now"). */
class UpdatesCheck extends UpdatesBase {

	protected function checkInput(): bool {
		return $this->validateInput([]);
	}

	protected function doAction(): void {
		try {
			$id = $this->newId();
			$this->writeRequest($id, ['action' => 'check']);
			$this->audit('check', ['request' => $id]);
			$this->json(['ok' => true, 'id' => $id]);
		}
		catch (\Throwable $e) {
			$this->jsonError($e->getMessage());
		}
	}
}
