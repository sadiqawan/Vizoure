<?php declare(strict_types = 0);

namespace Modules\VizoureUpdates\Actions;

/**
 * POST + CSRF (multipart): offline upgrade from a release package. Three files are required, exactly as
 * published with the release: the package, SHA256SUMS and SHA256SUMS.sig. The root service verifies the
 * signature and checksum; this action only stages the files and writes the request.
 */
class UpdatesUpload extends UpdatesBase {

	protected function checkInput(): bool {
		return $this->validateInput([]);
	}

	protected function doAction(): void {
		$files = ['package' => '.tar.gz', 'sums' => '.SHA256SUMS', 'sig' => '.SHA256SUMS.sig'];
		$id = $this->newId();
		$dir = self::SPOOL_DIR.'/uploads';
		$staged = [];

		try {
			foreach ($files as $field => $suffix) {
				$f = $_FILES[$field] ?? null;

				if (!is_array($f) || ($f['error'] ?? UPLOAD_ERR_NO_FILE) !== UPLOAD_ERR_OK) {
					throw new \RuntimeException(_s('Missing or failed upload: %1$s (limit is %2$s MB per file).',
						$field, self::MAX_UPLOAD / 1048576));
				}

				if ($f['size'] > self::MAX_UPLOAD || !is_uploaded_file($f['tmp_name'])) {
					throw new \RuntimeException(_s('File %1$s is too large.', $field));
				}

				$dest = $dir.'/'.$id.$suffix;

				if (!move_uploaded_file($f['tmp_name'], $dest)) {
					throw new \RuntimeException(_('Cannot store the uploaded file (is the updater installed?).'));
				}

				@chmod($dest, 0600);
				$staged[] = $dest;
			}

			$name = basename((string) $_FILES['package']['name']);

			if (!preg_match('/^vizoure-nms-v\d+\.\d+\.\d+-vz\d+-install\.tar\.gz$/', $name)) {
				throw new \RuntimeException(_('The package must be named vizoure-nms-<version>-install.tar.gz.'));
			}

			$this->writeRequest($id, ['action' => 'upload_upgrade', 'orig_name' => $name]);
			$this->audit('upload', ['request' => $id, 'package' => $name]);
			$this->json(['ok' => true, 'id' => $id]);
		}
		catch (\Throwable $e) {
			foreach ($staged as $path) {
				@unlink($path);
			}

			$this->jsonError($e->getMessage());
		}
	}
}
