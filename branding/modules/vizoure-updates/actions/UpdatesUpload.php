<?php declare(strict_types = 0);

namespace Modules\VizoureUpdates\Actions;

/**
 * POST + CSRF (multipart): offline upgrade from a release package. Three files are required, exactly as
 * published with the release: the package, SHA256SUMS and SHA256SUMS.sig. The root service verifies the
 * signature and checksum; this action only stages the files, checks their names and writes the request.
 */
class UpdatesUpload extends UpdatesBase {

	protected function checkInput(): bool {
		return $this->validateInput([]);
	}

	protected function doAction(): void {
		$id = $this->newId();
		$dir = self::SPOOL_DIR.'/uploads';
		$staged = [];

		// field => [staged suffix, human label, expected file name (regex or exact), how to say it]
		$files = [
			'package' => ['.tar.gz', _('release package'),
				'/^vizoure-nms-v\d+\.\d+\.\d+-vz\d+-install\.tar\.gz$/', 'vizoure-nms-<version>-install.tar.gz'],
			'sums' => ['.SHA256SUMS', _('checksum file'), '/^SHA256SUMS$/', 'SHA256SUMS'],
			'sig' => ['.SHA256SUMS.sig', _('signature file'), '/^SHA256SUMS\.sig$/', 'SHA256SUMS.sig']
		];
		$limit_mb = self::MAX_UPLOAD / 1048576;

		try {
			// 0) GitHub's automatic "Source code" archive is the most common wrong pick: say so exactly.
			$picked_name = basename((string) ($_FILES['package']['name'] ?? ''));

			if (preg_match('/^Vizoure-(\d+\.\d+\.\d+-vz\d+)\.(zip|tar\.gz)$/i', $picked_name, $m)) {
				$this->jsonRejected(
					_s('"%1$s" is the "Source code" archive that GitHub adds to every release automatically. It is not the release package.', $picked_name),
					_s('Download vizoure-nms-v%1$s-install.tar.gz (plus SHA256SUMS and SHA256SUMS.sig) from the Assets list of the release.', $m[1])
				);

				return;
			}

			// 1) Check every file first and report ALL problems at once, naming the file and the expected name.
			$problems = [];

			foreach ($files as $field => [$suffix, $label, $regex, $expected]) {
				$f = $_FILES[$field] ?? null;
				$err = is_array($f) ? (int) ($f['error'] ?? UPLOAD_ERR_NO_FILE) : UPLOAD_ERR_NO_FILE;
				$name = is_array($f) ? basename((string) ($f['name'] ?? '')) : '';

				if ($err === UPLOAD_ERR_NO_FILE) {
					$problems[] = _s('The %1$s is missing. Select the file named %2$s.', $label, $expected);
				}
				elseif ($err === UPLOAD_ERR_INI_SIZE || $err === UPLOAD_ERR_FORM_SIZE
						|| ($err === UPLOAD_ERR_OK && $f['size'] > self::MAX_UPLOAD)) {
					$problems[] = _s('%1$s is larger than the %2$s MB limit.', $name, $limit_mb);
				}
				elseif ($err !== UPLOAD_ERR_OK) {
					$problems[] = _s('%1$s could not be uploaded (upload error %2$s). Try again.', $name, $err);
				}
				elseif (!preg_match($regex, $name)) {
					$problems[] = _s('"%1$s" is not the %2$s. Expected a file named %3$s from the Vizoure release page.',
						$name, $label, $expected
					);
				}
			}

			if ($problems) {
				throw new \RuntimeException(implode(' ', $problems));
			}

			// 1b) Early, friendly rejection (nothing is queued): wrong channel or not newer than what is installed.
			$state = $this->state();
			$channel = $state['channel'] ?? 'stable';
			$installed = $state['installed'] ?? null;
			$meta = $this->readPackageMeta($_FILES['package']['tmp_name']);

			if (is_array($meta)) {
				if (($meta['channel'] ?? '') === 'test' && $channel !== 'test') {
					$this->jsonRejected(_('This is a test release.'), _('To install it, set Update channel to Test and save.'));

					return;
				}

				$new = $this->versionTuple((string) ($meta['version'] ?? ''));
				$cur = $this->versionTuple($installed);

				if ($new !== null && $cur !== null && $new <= $cur) {
					$this->jsonRejected(_s('This release (%1$s) is not newer than the version installed (%2$s).',
						$meta['version'], $installed), _('Choose a newer release.')
					);

					return;
				}
			}

			// 2) Stage them (private to the updater) and hand the request over.
			foreach ($files as $field => [$suffix]) {
				$f = $_FILES[$field];
				$dest = $dir.'/'.$id.$suffix;

				if (!is_uploaded_file($f['tmp_name']) || !move_uploaded_file($f['tmp_name'], $dest)) {
					throw new \RuntimeException(
						_('Cannot store the uploaded file. Is the Vizoure updater service installed and running?')
					);
				}

				@chmod($dest, 0600);
				$staged[] = $dest;
			}

			$name = basename((string) $_FILES['package']['name']);
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
