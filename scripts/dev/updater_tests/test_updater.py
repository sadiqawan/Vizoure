"""Dev-only unit tests for branding/updater/vizoure-updater.py (never shipped).

Run on a Linux host (the updater needs pwd/fcntl):
    VIZOURE_UPDATER_PREFIX is set by this file to a scratch directory.
    python3 -m unittest scripts/dev/updater_tests/test_updater.py -v
Needs ssh-keygen (signature tests generate THROWAWAY keys in a temp dir).
"""

import importlib.util
import io
import json
import os
import subprocess
import sys
import tarfile
import tempfile
import time
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
UPDATER = os.path.join(HERE, '..', '..', '..', 'branding', 'updater', 'vizoure-updater.py')
SCRATCH = tempfile.mkdtemp(prefix='vz-updater-test-')
os.environ['VIZOURE_UPDATER_PREFIX'] = SCRATCH

spec = importlib.util.spec_from_file_location('vzu', UPDATER)
vzu = importlib.util.module_from_spec(spec)
spec.loader.exec_module(vzu)


def rid():
    return os.urandom(16).hex()


def keygen(path):
    subprocess.run(['ssh-keygen', '-q', '-t', 'ed25519', '-N', '', '-f', path, '-C', 'throwaway'], check=True)
    with open(path + '.pub') as f:
        return f.read().strip()


def sign(key, path, namespace='vizoure-release'):
    subprocess.run(['ssh-keygen', '-q', '-Y', 'sign', '-f', key, '-n', namespace, path], check=True)


class Versions(unittest.TestCase):
    def test_parse(self):
        self.assertEqual(vzu.parse_version('v7.4.15-vz2'), (7, 4, 15, 2))
        for bad in ('7.4.15-vz2', 'v7.4.15', 'v7.4.15-vz', 'v7.4-vz1', 'v7.4.15-vz1; rm -rf /', None, 5, ''):
            self.assertIsNone(vzu.parse_version(bad), bad)

    def test_order(self):
        self.assertGreater(vzu.parse_version('v7.4.15-vz10'), vzu.parse_version('v7.4.15-vz9'))
        self.assertGreater(vzu.parse_version('v7.4.16-vz1'), vzu.parse_version('v7.4.15-vz99'))
        self.assertGreater(vzu.parse_version('v7.5.0-vz1'), vzu.parse_version('v7.4.99-vz9'))


class RequestValidation(unittest.TestCase):
    def base(self, **kw):
        r = {'v': 1, 'id': rid(), 'ts': int(time.time()), 'action': 'check', 'user': 'admin', 'userid': '1'}
        r.update(kw)
        return r

    def test_good(self):
        self.assertEqual(vzu.validate_request(self.base())['action'], 'check')
        self.assertEqual(vzu.validate_request(self.base(action='upgrade', version='v7.4.15-vz3'))['version'],
                         'v7.4.15-vz3')
        c = vzu.validate_request(self.base(action='upload_upgrade', orig_name='vizoure-nms-v7.4.15-vz3-install.tar.gz'))
        self.assertEqual(c['version'], 'v7.4.15-vz3')
        c = vzu.validate_request(self.base(action='set_config', channel='test', proxy='http://proxy.local:3128'))
        self.assertEqual(c['channel'], 'test')

    def test_rejects(self):
        bad = [
            self.base(v=2), self.base(action='rm'), self.base(action='upgrade'),
            self.base(action='upgrade', version='main'), self.base(action='upgrade', version='v1.0.0-vz1;id'),
            self.base(ts=int(time.time()) - 3600), self.base(id='../../etc/passwd'), self.base(user='a;b'),
            self.base(userid='x'), self.base(extra='field'),
            self.base(action='upload_upgrade', orig_name='../../x.tar.gz'),
            self.base(action='upload_upgrade', orig_name='vizoure-nms-v7.4.15-vz3-install.tar.gz.evil'),
            self.base(action='set_config', channel='nightly', proxy=''),
            self.base(action='set_config', channel='stable', proxy='http://user:pw@host'),
            self.base(action='set_config', channel='stable', proxy='file:///etc/passwd'),
            'not-a-dict', None,
        ]
        for b in bad:
            with self.assertRaises(ValueError, msg=str(b)):
                vzu.validate_request(b)


class Spool(unittest.TestCase):
    def setUp(self):
        os.makedirs(vzu.REQ_DIR, exist_ok=True)
        os.makedirs(vzu.STATE_DIR, exist_ok=True)
        for n in os.listdir(vzu.REQ_DIR):
            os.unlink(os.path.join(vzu.REQ_DIR, n))
        if os.path.exists(vzu.SEEN_FILE):
            os.unlink(vzu.SEEN_FILE)

    def put(self, name, content):
        with open(os.path.join(vzu.REQ_DIR, name), 'w') as f:
            f.write(content if isinstance(content, str) else json.dumps(content))

    def req(self, **kw):
        r = {'v': 1, 'id': rid(), 'ts': int(time.time()), 'action': 'check', 'user': 'admin', 'userid': '1'}
        r.update(kw)
        return r

    def test_valid_consumed_and_removed(self):
        self.put('a.json', self.req())
        got = list(vzu.consume_requests())
        self.assertEqual(len(got), 1)
        self.assertEqual(os.listdir(vzu.REQ_DIR), [])

    def test_replay_rejected(self):
        r = self.req()
        self.put('a.json', r)
        self.assertEqual(len(list(vzu.consume_requests())), 1)
        self.put('b.json', r)
        self.assertEqual(len(list(vzu.consume_requests())), 0)

    def test_symlink_rejected(self):
        target = os.path.join(SCRATCH, 'secret.json')
        with open(target, 'w') as f:
            json.dump(self.req(), f)
        os.symlink(target, os.path.join(vzu.REQ_DIR, 'link.json'))
        self.assertEqual(len(list(vzu.consume_requests())), 0)
        self.assertEqual(os.listdir(vzu.REQ_DIR), [])

    def test_oversize_and_garbage_rejected(self):
        self.put('big.json', 'x' * 9000)
        self.put('junk.json', '{not json')
        self.put('note.txt', 'ignored')
        self.assertEqual(len(list(vzu.consume_requests())), 0)
        self.assertEqual(os.listdir(vzu.REQ_DIR), [])


class Tarballs(unittest.TestCase):
    def make(self, entries):
        buf = os.path.join(SCRATCH, 't-%s.tar.gz' % rid())
        with tarfile.open(buf, 'w:gz') as tf:
            for name, kind, data in entries:
                ti = tarfile.TarInfo(name)
                if kind == 'file':
                    ti.size = len(data)
                    tf.addfile(ti, io.BytesIO(data))
                elif kind == 'dir':
                    ti.type = tarfile.DIRTYPE
                    tf.addfile(ti)
                elif kind == 'symlink':
                    ti.type = tarfile.SYMTYPE
                    ti.linkname = data
                    tf.addfile(ti)
                elif kind == 'hardlink':
                    ti.type = tarfile.LNKTYPE
                    ti.linkname = data
                    tf.addfile(ti)
        return buf

    def test_ok(self):
        t = self.make([('vizoure-nms-v1.0.0-vz1', 'dir', b''), ('vizoure-nms-v1.0.0-vz1/a.txt', 'file', b'hi')])
        out = vzu.safe_extract(t, os.path.join(SCRATCH, 'ok-' + rid()), 'vizoure-nms-v1.0.0-vz1')
        self.assertTrue(os.path.isfile(os.path.join(out, 'a.txt')))

    def test_rejected(self):
        top = 'vizoure-nms-v1.0.0-vz1'
        cases = {
            'traversal': [(top + '/../../evil', 'file', b'x')],
            'absolute': [('/etc/evil', 'file', b'x')],
            'outside top': [('other/a', 'file', b'x')],
            'symlink': [(top + '/l', 'symlink', '/etc/passwd')],
            'hardlink': [(top + '/h', 'hardlink', '/etc/passwd')],
            'backslash': [(top + '\\..\\evil', 'file', b'x')],
        }
        for label, entries in cases.items():
            t = self.make(entries)
            with self.assertRaises(ValueError, msg=label):
                vzu.safe_extract(t, os.path.join(SCRATCH, 'bad-' + rid()), top)


class Signatures(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.dir = tempfile.mkdtemp(prefix='sig-', dir=SCRATCH)
        cls.good = os.path.join(cls.dir, 'good')
        cls.other = os.path.join(cls.dir, 'other')
        pub = keygen(cls.good)
        keygen(cls.other)
        os.makedirs(os.path.dirname(vzu.SIGNERS_FILE), exist_ok=True)
        with open(vzu.SIGNERS_FILE, 'w') as f:
            f.write('vizoure-release namespaces="vizoure-release" %s\n' % pub)

    def sums(self, content='abc  file\n'):
        p = os.path.join(self.dir, 'SHA256SUMS-' + rid())
        with open(p, 'w') as f:
            f.write(content)
        return p

    def test_valid_signature_accepted(self):
        s = self.sums()
        sign(self.good, s)
        vzu.verify_signature(s, s + '.sig')

    def test_wrong_key_rejected(self):
        s = self.sums()
        sign(self.other, s)
        with self.assertRaises(ValueError):
            vzu.verify_signature(s, s + '.sig')

    def test_tampered_sums_rejected(self):
        s = self.sums()
        sign(self.good, s)
        with open(s, 'a') as f:
            f.write('deadbeef  evil\n')
        with self.assertRaises(ValueError):
            vzu.verify_signature(s, s + '.sig')

    def test_wrong_namespace_rejected(self):
        s = self.sums()
        sign(self.good, s, namespace='something-else')
        with self.assertRaises(ValueError):
            vzu.verify_signature(s, s + '.sig')

    def test_missing_or_garbage_sig_rejected(self):
        s = self.sums()
        with self.assertRaises(Exception):
            vzu.verify_signature(s, s + '.sig')
        with open(s + '.sig', 'w') as f:
            f.write('garbage')
        with self.assertRaises(ValueError):
            vzu.verify_signature(s, s + '.sig')

    def test_checksum(self):
        tb = os.path.join(self.dir, 'pkg.tar.gz')
        with open(tb, 'wb') as f:
            f.write(b'payload')
        good = vzu.sha256_file(tb)
        s = self.sums('%s  vizoure-nms-v1.0.0-vz1-install.tar.gz\n' % good)
        vzu.check_checksum(s, 'vizoure-nms-v1.0.0-vz1-install.tar.gz', tb)
        with open(tb, 'wb') as f:
            f.write(b'tampered')
        with self.assertRaises(ValueError):
            vzu.check_checksum(s, 'vizoure-nms-v1.0.0-vz1-install.tar.gz', tb)
        with self.assertRaises(ValueError):
            vzu.check_checksum(s, 'not-listed.tar.gz', tb)


class StateLogic(unittest.TestCase):
    def setUp(self):
        os.makedirs(os.path.dirname(vzu.VERSION_FILE), exist_ok=True)
        with open(vzu.VERSION_FILE, 'w') as f:
            f.write('v7.4.15-vz2\n')
        vzu.save_config({'channel': 'stable', 'proxy': ''})

    def releases(self):
        return [{'tag': 'v7.4.15-vz3', 'prerelease': True, 'published_at': 'x', 'name': 'n', 'notes': ''},
                {'tag': 'v7.4.15-vz2', 'prerelease': False, 'published_at': 'x', 'name': 'n', 'notes': ''},
                {'tag': 'v7.4.15-vz1', 'prerelease': False, 'published_at': 'x', 'name': 'n', 'notes': ''}]

    def test_stable_hides_prerelease(self):
        st = vzu.recompute({'releases': self.releases()})
        self.assertIsNone(st['update_available'])

    def test_test_channel_shows_prerelease(self):
        vzu.save_config({'channel': 'test', 'proxy': ''})
        st = vzu.recompute({'releases': self.releases()})
        self.assertEqual(st['update_available']['version'], 'v7.4.15-vz3')

    def test_config_validation_on_load(self):
        with open(vzu.CONF_FILE, 'w') as f:
            f.write('channel=nightly\nproxy=http://u:p@h\n')
        c = vzu.load_config()
        self.assertEqual(c, {'channel': 'stable', 'proxy': ''})


class Redaction(unittest.TestCase):
    def test_redact(self):
        self.assertIn('hidden', vzu.redact_line('Password: hunter2'))
        self.assertIn('hidden', vzu.redact_line('mysqldump -p"x" token=abc'))
        self.assertEqual(vzu.redact_line('[3/6] Stopping services...'), '[3/6] Stopping services...')


class Rejections(unittest.TestCase):
    """Refusals before anything changes must carry a plain-words reason and a fix (shown to the admin)."""

    def test_signature_rejection_has_fix(self):
        d = tempfile.mkdtemp(prefix='rej-', dir=SCRATCH)
        sums = os.path.join(d, 'SHA256SUMS')
        open(sums, 'w').write('abc  file\n')
        open(sums + '.sig', 'w').write('garbage')
        with self.assertRaises(vzu.Rejected) as cm:
            vzu.verify_signature(sums, sums + '.sig')
        self.assertTrue(cm.exception.reason and cm.exception.fix)
        self.assertNotIn('zabbix', (cm.exception.reason + cm.exception.fix).lower())

    def test_checksum_rejection_has_fix(self):
        d = tempfile.mkdtemp(prefix='rej-', dir=SCRATCH)
        tb = os.path.join(d, 'p.tar.gz')
        open(tb, 'wb').write(b'x')
        sums = os.path.join(d, 'S')
        open(sums, 'w').write('%s  vizoure-nms-v1.0.0-vz1-install.tar.gz\n' % ('0' * 64))
        with self.assertRaises(vzu.Rejected) as cm:
            vzu.check_checksum(sums, 'vizoure-nms-v1.0.0-vz1-install.tar.gz', tb)
        self.assertIn('Download the package again', cm.exception.fix)

    def test_recovery_text_uses_vizoure_cli_and_no_upstream_name(self):
        text = ' '.join(vzu.recovery_steps({'backup_file': '/var/backups/vizoure/x.sql.gz'}))
        self.assertIn('sudo vizoure start', text)
        self.assertNotIn('zabbix', text.lower())

    def test_customer_log_hides_upstream_name(self):
        os.makedirs(vzu.STATE_DIR, exist_ok=True)
        run = vzu.Run({'id': rid(), 'user': 'admin', 'userid': '1', 'version': 'v9.9.9-vz1'}, 'upload')
        run.say('Setting up zabbix-server-mysql (1:7.4.15) ...')
        run.logf.close()
        run.rawf.close()
        shown = open(os.path.join(run.dir, 'log.txt')).read()
        raw = open(os.path.join(run.dir, 'log.raw.txt')).read()
        self.assertNotIn('zabbix', shown.lower())
        self.assertIn('zabbix', raw)


if __name__ == '__main__':
    unittest.main(verbosity=2)
