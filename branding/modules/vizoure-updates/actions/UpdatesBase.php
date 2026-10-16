<?php declare(strict_types = 0);
/* Vizoure NMS — shared helpers for the updates actions.
 *
 * SECURITY MODEL: this code runs as www-data. It never executes commands and never touches the
 * network. It only (a) reads status files written by the root updater service and (b) writes a small
 * JSON *request* (or an uploaded package) into the spool directory. The root service re-validates
 * every request. See md/09-update-system.md.
 */

namespace Modules\VizoureUpdates\Actions;

use CAudit,
	CController,
	CControllerResponseData,
	CWebUser;

abstract class UpdatesBase extends CController {

	protected const STATE_DIR = '/var/lib/vizoure-updater';
	protected const SPOOL_DIR = '/var/spool/vizoure-updater';
	protected const MAX_UPLOAD = 2097152;

	protected function checkPermissions(): bool {
		return $this->getUserType() == USER_TYPE_SUPER_ADMIN;
	}

	/* ---------- reads (files written by root) ---------- */

	protected function readJson(string $path, $default) {
		$raw = @file_get_contents($path, false, null, 0, 2 * 1024 * 1024);

		if ($raw === false) {
			return $default;
		}

		$data = json_decode($raw, true);

		return is_array($data) ? $data : $default;
	}

	/** [major, minor, patch, vz] for vX.Y.Z-vzN, or null. Mirrors the updater's comparison. */
	protected function versionTuple(?string $tag): ?array {
		if ($tag !== null && preg_match('/^v(\d+)\.(\d+)\.(\d+)-vz(\d+)$/', $tag, $m)) {
			return [(int) $m[1], (int) $m[2], (int) $m[3], (int) $m[4]];
		}

		return null;
	}

	protected function state(): array {
		return $this->readJson(self::STATE_DIR.'/state.json', []);
	}

	protected function history(int $limit = 25): array {
		$raw = @file_get_contents(self::STATE_DIR.'/history.jsonl', false, null, 0, 1024 * 1024);
		$rows = [];

		if ($raw !== false) {
			foreach (array_reverse(explode("\n", trim($raw))) as $line) {
				$row = json_decode($line, true);

				if (is_array($row) && ($row['result'] ?? '') !== 'rejected' && ($row['result'] ?? '') !== 'config') {
					$rows[] = $row;
				}

				if (count($rows) >= $limit) {
					break;
				}
			}
		}

		return $rows;
	}

	protected function runStatus(string $id): ?array {
		if (!preg_match('/^[0-9a-f]{32}$/', $id)) {
			return null;
		}

		$status = $this->readJson(self::STATE_DIR.'/run/'.$id.'/status.json', []);

		return $status ?: null;
	}

	protected function latestRun(): ?array {
		$best = null;

		foreach ((array) @glob(self::STATE_DIR.'/run/*/status.json') as $file) {
			$status = $this->readJson($file, []);

			if ($status && ($best === null || ($status['started'] ?? 0) > ($best['started'] ?? 0))) {
				$best = $status;
			}
		}

		return $best;
	}

	protected function logTail(string $id, int $lines = 300): array {
		if (!preg_match('/^[0-9a-f]{32}$/', $id)) {
			return [];
		}

		$raw = @file_get_contents(self::STATE_DIR.'/run/'.$id.'/log.txt', false, null, 0, 1024 * 1024);

		if ($raw === false || $raw === '') {
			return [];
		}

		return array_slice(explode("\n", rtrim($raw)), -$lines);
	}

	/* ---------- writes (request spool) ---------- */

	protected function newId(): string {
		return bin2hex(random_bytes(16));
	}

	/** Write one request file; the root service validates it again from scratch. */
	protected function writeRequest(string $id, array $fields): void {
		$request = array_merge([
			'v' => 1,
			'id' => $id,
			'ts' => time(),
			'user' => (string) CWebUser::$data['username'],
			'userid' => (string) CWebUser::$data['userid']
		], $fields);

		$dir = self::SPOOL_DIR.'/requests';
		$tmp = $dir.'/.'.$id.'.part';
		$fh = @fopen($tmp, 'x');

		if ($fh === false) {
			throw new \RuntimeException(_('Cannot write to the updater spool directory. Is the Vizoure updater installed?'));
		}

		fwrite($fh, json_encode($request));
		fclose($fh);
		@chmod($tmp, 0600);

		// The path unit only fires on *.json, so the rename is what hands the request over.
		if (!@rename($tmp, $dir.'/'.$id.'.json')) {
			@unlink($tmp);

			throw new \RuntimeException(_('Cannot hand the request to the updater service.'));
		}
	}

	/** Audit log entry (Administration → Audit log) for every action taken on this page. */
	protected function audit(string $event, array $details): void {
		try {
			$module = \API::getApiService('module')->get([
				'output' => ['moduleid', 'id', 'relative_path', 'status', 'config'],
				'filter' => ['id' => 'vizoure.updates']
			]);

			if (!$module) {
				return;
			}

			$db = $module[0];
			$new = $db;
			$new['config'] = json_encode(['last_event' => $event, 'details' => $details, 'at' => time()]);

			CAudit::log(CWebUser::$data['userid'], CWebUser::getIp(), CWebUser::$data['username'],
				CAudit::ACTION_UPDATE, CAudit::RESOURCE_MODULE, [$db['moduleid'] => $new], [$db['moduleid'] => $db]
			);
		}
		catch (\Throwable $e) {
			// Auditing must never break the action itself; the root updater keeps its own history.
		}
	}

	/* ---------- responses ---------- */

	protected function json(array $data): void {
		$this->setResponse(new CControllerResponseData(['main_block' => json_encode($data)]));
	}

	protected function jsonError(string $message): void {
		$this->json(['ok' => false, 'error' => $message]);
	}

	protected function checkInput(): bool {
		return true;
	}
}
