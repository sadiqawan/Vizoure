#!/usr/bin/env python3
"""Vizoure NMS updater: the ONLY component that performs upgrades.

Runs as root from systemd (vizoure-updater.service / vizoure-updater-check.service).
The web UI (www-data) never runs this, never runs shell commands and never touches the
network: it only drops a small JSON *request* file into the spool directory. Everything in
a request is treated as hostile and re-validated here. See md/09-update-system.md.

Usage:
    vizoure-updater.py --process     handle pending requests (path unit)
    vizoure-updater.py --check       refresh the GitHub release list (timer)
    vizoure-updater.py --reconcile   mark runs that were killed midway as interrupted
"""

import fcntl
import hashlib
import json
import os
import pwd
import re
import shutil
import stat
import subprocess
import sys
import tarfile
import tempfile
import threading
import time
import urllib.error
import urllib.parse
import urllib.request

# Fixed on purpose: not configurable from the UI or the config file (no SSRF / source swap).
OWNER = 'sadiqawan'
REPO = 'Vizoure'
SIGN_NAMESPACE = 'vizoure-release'
SIGN_PRINCIPAL = 'vizoure-release'
WEB_USER = 'www-data'

# Unit tests point everything at a scratch tree. The service environment is fixed by systemd and
# cannot be influenced by the web user.
P = os.environ.get('VIZOURE_UPDATER_PREFIX', '')
STATE_DIR = P + '/var/lib/vizoure-updater'
SPOOL_DIR = P + '/var/spool/vizoure-updater'
REQ_DIR = SPOOL_DIR + '/requests'
UPLOAD_DIR = SPOOL_DIR + '/uploads'
CONF_FILE = P + '/etc/vizoure/updater.conf'
VERSION_FILE = P + '/etc/vizoure/version'
SIGNERS_FILE = P + '/etc/vizoure/allowed_signers'
LOCK_FILE = P + '/run/vizoure-updater.lock'
STATE_FILE = STATE_DIR + '/state.json'
HISTORY_FILE = STATE_DIR + '/history.jsonl'
SEEN_FILE = STATE_DIR + '/seen-requests.json'
RUN_DIR = STATE_DIR + '/run'
CACHE_DIR = STATE_DIR + '/releases'
WORK_DIR = STATE_DIR + '/work'

TAG_RE = re.compile(r'^v(\d+)\.(\d+)\.(\d+)-vz(\d+)$')
ZBX_RE = re.compile(r'^\d+\.\d+\.\d+$')
ID_RE = re.compile(r'^[0-9a-f]{32}$')
TARBALL_RE = re.compile(r'^vizoure-nms-(v\d+\.\d+\.\d+-vz\d+)-install\.tar\.gz$')
PROXY_RE = re.compile(r'^https?://[A-Za-z0-9.\-]+(:\d{1,5})?$')
CHANNELS = ('stable', 'test')
RUNNING_STATES = ('queued', 'validating', 'downloading', 'verifying', 'extracting', 'upgrading')

MAX_REQUEST = 4096
MAX_TARBALL = 50 * 1024 * 1024
MAX_SUMS = 64 * 1024
MAX_SIG = 4 * 1024
MAX_EXTRACT_TOTAL = 200 * 1024 * 1024
MAX_EXTRACT_MEMBERS = 2000
MAX_NOTES = 20000
REQUEST_MAX_AGE = 600
MANUAL_CHECK_MIN_INTERVAL = 60
UPGRADE_TIMEOUT = 2 * 3600
HEARTBEAT_EVERY = 5
KEEP_CACHED_RELEASES = 3

ALLOWED_DOWNLOAD_HOSTS = ('github.com', 'objects.githubusercontent.com', 'release-assets.githubusercontent.com')
REDACT_RE = re.compile(r'pass(word|wd)?|secret|token', re.I)

# Customer-visible log wording. Real technical names (packages, executables, paths, repository hosts) are replaced by
# NEUTRAL descriptions - never by a lookalike such as "vizoure-server", which would be a command/package that does not
# exist. The unfiltered output stays root-only in run/<id>/log.raw.txt.
_PKG_WORDS = (
    ('server-mysql', 'core server package'), ('server-pgsql', 'core server package'), ('server', 'core server package'),
    ('frontend-php', 'core web package'), ('apache-conf', 'core web configuration package'),
    ('nginx-conf', 'core web configuration package'), ('sql-scripts', 'core database scripts package'),
    ('agent2', 'core agent package'), ('agent', 'core agent package'), ('release', 'core repository package'),
    ('proxy-mysql', 'core proxy package'), ('web-service', 'core web service package'),
)
_UPSTREAM_RULES = [
    (re.compile(r'https?://[^\s]*zabbix[^\s]*', re.I), 'the package repository'),
    (re.compile(r'(?:/[\w.+-]+)*/zabbix[\w./+-]*', re.I), 'core files'),
    (re.compile(r'\bzabbix_[a-z0-9_]+\b', re.I), 'core component'),   # executables: zabbix_server, zabbix_agentd ...
    (re.compile(r'\bzabbix-([a-z0-9]+(?:-[a-z0-9]+)*)\b', re.I), None),   # packages: handled by _pkg_repl
    (re.compile(r'\bzabbix\b', re.I), 'Vizoure NMS core'),
]


def _pkg_repl(m):
    rest = m.group(1).lower()
    for key, words in _PKG_WORDS:
        if rest == key or rest.startswith(key):
            return words
    return 'core component'


def customer_text(line):
    """Descriptive rewrite for the page: no upstream product name, no invented technical names."""
    out = line
    for rx, repl in _UPSTREAM_RULES:
        out = rx.sub(_pkg_repl, out) if repl is None else rx.sub(repl, out)
    return out


# ----------------------------------------------------------------------------------------------
# small helpers
# ----------------------------------------------------------------------------------------------

class Rejected(ValueError):
    """The request was refused BEFORE anything on the server was changed (plain words + how to fix it)."""

    def __init__(self, reason, fix=''):
        super().__init__(reason)
        self.reason = reason
        self.fix = fix


def log(msg):
    print('vizoure-updater: ' + str(msg), flush=True)


def now():
    return int(time.time())


def parse_version(tag):
    m = TAG_RE.match(tag) if isinstance(tag, str) else None
    return tuple(int(x) for x in m.groups()) if m else None


def installed_version():
    try:
        with open(VERSION_FILE) as f:
            v = f.read().strip()
        return v if parse_version(v) else None
    except OSError:
        return None


def write_atomic(path, data, mode=0o644):
    os.makedirs(os.path.dirname(path), mode=0o755, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), prefix='.tmp-')
    try:
        with os.fdopen(fd, 'w') as f:
            f.write(data)
        os.chmod(tmp, mode)
        os.replace(tmp, path)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def read_json(path, default):
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


def redact_line(line):
    return '[line hidden: may contain a credential]' if REDACT_RE.search(line) else line


def short_error(exc):
    return re.sub(r'\s+', ' ', str(exc))[:300]


# ----------------------------------------------------------------------------------------------
# config + state
# ----------------------------------------------------------------------------------------------

def load_config():
    conf = {'channel': 'stable', 'proxy': ''}
    try:
        with open(CONF_FILE) as f:
            for raw in f:
                raw = raw.strip()
                if not raw or raw.startswith('#') or '=' not in raw:
                    continue
                k, v = raw.split('=', 1)
                k, v = k.strip(), v.strip()
                if k == 'channel' and v in CHANNELS:
                    conf['channel'] = v
                elif k == 'proxy' and (v == '' or PROXY_RE.match(v)):
                    conf['proxy'] = v
    except OSError:
        pass
    return conf


def save_config(conf):
    write_atomic(CONF_FILE, '# managed by vizoure-updater (values are validated)\nchannel=%s\nproxy=%s\n'
                 % (conf['channel'], conf['proxy']))


def load_state():
    st = read_json(STATE_FILE, {})
    st.setdefault('schema', 1)
    st.setdefault('releases', [])
    st.setdefault('last_check_ts', 0)
    st.setdefault('last_check_attempt_ts', 0)
    st.setdefault('last_check_ok', None)
    st.setdefault('last_error', '')
    st.setdefault('rate_limited_until', 0)
    st.setdefault('etag', '')
    return st


def release_visible(rel, channel):
    return channel == 'test' or not rel.get('prerelease')


def recompute(state):
    """Derive installed/channel/update_available from stored data (no network)."""
    conf = load_config()
    inst = installed_version()
    state['installed'] = inst
    state['channel'] = conf['channel']
    state['proxy'] = conf['proxy']
    cur = parse_version(inst) if inst else (0, 0, 0, 0)
    newer = [r for r in state['releases']
             if release_visible(r, conf['channel']) and parse_version(r['tag']) and parse_version(r['tag']) > cur]
    newer.sort(key=lambda r: parse_version(r['tag']), reverse=True)
    state['update_available'] = {'version': newer[0]['tag'], 'prerelease': newer[0]['prerelease'],
                                 'published_at': newer[0]['published_at']} if newer else None
    return state


def save_state(state):
    recompute(state)
    write_atomic(STATE_FILE, json.dumps(state, indent=1, sort_keys=True))


def append_history(entry):
    os.makedirs(STATE_DIR, mode=0o755, exist_ok=True)
    with open(HISTORY_FILE, 'a') as f:
        f.write(json.dumps(entry, sort_keys=True) + '\n')
    os.chmod(HISTORY_FILE, 0o644)


# ----------------------------------------------------------------------------------------------
# GitHub
# ----------------------------------------------------------------------------------------------

class _SafeRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        u = urllib.parse.urlparse(newurl)
        host = u.hostname or ''
        if u.scheme != 'https' or not (host in ALLOWED_DOWNLOAD_HOSTS or host.endswith('.githubusercontent.com')):
            raise urllib.error.URLError('redirect to a disallowed host refused')
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def opener(conf):
    handlers = [_SafeRedirect()]
    if conf.get('proxy'):
        handlers.append(urllib.request.ProxyHandler({'https': conf['proxy'], 'http': conf['proxy']}))
    else:
        handlers.append(urllib.request.ProxyHandler({}))
    return urllib.request.build_opener(*handlers)


def user_agent():
    return 'vizoure-updater/1 (+https://github.com/%s/%s)' % (OWNER, REPO)


def check_releases(force=False):
    """Refresh state['releases'] from the GitHub releases API. Cached, ETag + rate-limit aware."""
    state = load_state()
    conf = load_config()
    t = now()
    if t < state['rate_limited_until']:
        state['last_error'] = 'GitHub rate limit reached; next check after %s' % time.strftime(
            '%H:%M:%S', time.localtime(state['rate_limited_until']))
        save_state(state)
        return state
    if force and t - state['last_check_attempt_ts'] < MANUAL_CHECK_MIN_INTERVAL:
        return state
    state['last_check_attempt_ts'] = t
    url = 'https://api.github.com/repos/%s/%s/releases?per_page=30' % (OWNER, REPO)
    headers = {'Accept': 'application/vnd.github+json', 'User-Agent': user_agent()}
    if state['etag']:
        headers['If-None-Match'] = state['etag']
    try:
        with opener(conf).open(urllib.request.Request(url, headers=headers), timeout=20) as resp:
            body = resp.read(2 * 1024 * 1024 + 1)
            if len(body) > 2 * 1024 * 1024:
                raise ValueError('release list too large')
            data = json.loads(body.decode('utf-8'))
            state['etag'] = resp.headers.get('ETag', '')
        releases = []
        for r in data if isinstance(data, list) else []:
            tag = r.get('tag_name')
            if not parse_version(tag) or r.get('draft'):
                continue
            releases.append({'tag': tag, 'prerelease': bool(r.get('prerelease')),
                             'published_at': str(r.get('published_at') or '')[:25],
                             'name': str(r.get('name') or tag)[:120],
                             'notes': str(r.get('body') or '')[:MAX_NOTES]})
        releases.sort(key=lambda x: parse_version(x['tag']), reverse=True)
        state['releases'] = releases[:20]
        state['last_check_ok'] = True
        state['last_error'] = ''
        state['last_check_ts'] = t
    except urllib.error.HTTPError as e:
        if e.code == 304:
            state['last_check_ok'] = True
            state['last_error'] = ''
            state['last_check_ts'] = t
        elif e.code in (403, 429):
            reset = e.headers.get('X-RateLimit-Reset')
            state['rate_limited_until'] = int(reset) if reset and reset.isdigit() else t + 3600
            state['last_check_ok'] = False
            state['last_error'] = 'GitHub rate limit reached (HTTP %d)' % e.code
        else:
            state['last_check_ok'] = False
            state['last_error'] = 'GitHub returned HTTP %d' % e.code
    except (urllib.error.URLError, OSError, ValueError) as e:
        state['last_check_ok'] = False
        state['last_error'] = 'Cannot reach GitHub: ' + short_error(getattr(e, 'reason', e))
    save_state(state)
    return state


def download(url, dest, max_size, conf):
    u = urllib.parse.urlparse(url)
    if u.scheme != 'https' or u.hostname != 'github.com' or not u.path.startswith('/%s/%s/releases/download/' % (OWNER, REPO)):
        raise ValueError('refusing to download from an unexpected URL')
    req = urllib.request.Request(url, headers={'User-Agent': user_agent()})
    size = 0
    with opener(conf).open(req, timeout=60) as resp, open(dest, 'wb') as out:
        while True:
            chunk = resp.read(65536)
            if not chunk:
                break
            size += len(chunk)
            if size > max_size:
                raise ValueError('download exceeds the size limit')
            out.write(chunk)
    os.chmod(dest, 0o600)


# ----------------------------------------------------------------------------------------------
# verification + safe extraction
# ----------------------------------------------------------------------------------------------

def verify_signature(sums_path, sig_path):
    """SHA256SUMS must carry a valid ssh-keygen -Y signature from an allowed signer. No override."""
    if not os.path.isfile(SIGNERS_FILE):
        raise Rejected('This server has no list of trusted release signers, so no release can be verified.',
                       'Re-run the command-line upgrade once (see the README), which installs it.')
    with open(sums_path, 'rb') as sums:
        r = subprocess.run(['ssh-keygen', '-Y', 'verify', '-f', SIGNERS_FILE, '-I', SIGN_PRINCIPAL,
                            '-n', SIGN_NAMESPACE, '-s', sig_path],
                           stdin=sums, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30)
    if r.returncode != 0:
        raise Rejected('The release signature is missing or invalid. Only releases signed by Vizoure can be installed.',
                       'Download SHA256SUMS and SHA256SUMS.sig again from the Vizoure releases page and do not edit them.')


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(1 << 20), b''):
            h.update(chunk)
    return h.hexdigest()


def check_checksum(sums_path, name, tarball_path):
    want = None
    with open(sums_path) as f:
        for line in f:
            m = re.match(r'^([0-9a-f]{64}) [ *](.+)$', line.rstrip('\n'))
            if m and m.group(2) == name:
                want = m.group(1)
    if want is None:
        raise Rejected('The checksum list does not contain %s.' % name,
                       'Use the SHA256SUMS file from the same release as the package.')
    if sha256_file(tarball_path) != want:
        raise Rejected('The package does not match its checksum: it was changed or the download is damaged.',
                       'Download the package again from the Vizoure releases page.')


def safe_extract(tarball, dest, top):
    """Extract only regular files/dirs under <top>/, no links, no traversal, bounded size."""
    total = 0
    members = []
    with tarfile.open(tarball, 'r:gz') as tf:
        for m in tf:
            if len(members) >= MAX_EXTRACT_MEMBERS:
                raise Rejected('The package is not a valid Vizoure release (too many entries).',
                           'Download vizoure-nms-<version>-install.tar.gz from the Assets list of the release (not the Source code archive).')
            name = m.name
            if name.startswith('/') or '..' in name.split('/') or '\\' in name:
                raise Rejected('The package is not a valid Vizoure release (unsafe file path).',
                           'Download vizoure-nms-<version>-install.tar.gz from the Assets list of the release (not the Source code archive).')
            if not (name == top or name.startswith(top + '/')):
                raise Rejected('The package is not a valid Vizoure release (unexpected content).',
                           'Download vizoure-nms-<version>-install.tar.gz from the Assets list of the release (not the Source code archive).')
            if not (m.isreg() or m.isdir()):
                raise Rejected('The package is not a valid Vizoure release (it contains links or special files).',
                           'Download vizoure-nms-<version>-install.tar.gz from the Assets list of the release (not the Source code archive).')
            total += max(m.size, 0)
            if total > MAX_EXTRACT_TOTAL:
                raise Rejected('The package is too large to be a Vizoure release.',
                           'Download vizoure-nms-<version>-install.tar.gz from the Assets list of the release (not the Source code archive).')
            members.append(m)
        os.makedirs(dest, mode=0o700, exist_ok=True)
        tf.extractall(dest, members=members, filter='data')
    return os.path.join(dest, top)


# ----------------------------------------------------------------------------------------------
# request intake (hostile input)
# ----------------------------------------------------------------------------------------------

def web_uid():
    try:
        return pwd.getpwnam(WEB_USER).pw_uid
    except KeyError:
        return None


def open_spool_file(path, max_size):
    """Open a file the web user created; reject symlinks, non-regular files, foreign owners, big files."""
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    try:
        st = os.fstat(fd)
        if not stat.S_ISREG(st.st_mode) or st.st_nlink != 1:
            raise ValueError('spool entry is not a plain file')
        if os.environ.get('VIZOURE_UPDATER_PREFIX') is None and st.st_uid != web_uid():
            raise ValueError('spool file has unexpected owner')
        if st.st_size > max_size:
            raise ValueError('spool file too large')
    except BaseException:
        os.close(fd)
        raise
    return os.fdopen(fd, 'rb')


def validate_request(req):
    """Return a clean dict or raise ValueError. Unknown keys are rejected."""
    if not isinstance(req, dict) or req.get('v') != 1:
        raise ValueError('bad request format')
    allowed = {'v', 'id', 'ts', 'action', 'user', 'userid', 'version', 'channel', 'proxy', 'orig_name'}
    if set(req) - allowed:
        raise ValueError('unexpected fields in request')
    if not isinstance(req.get('id'), str) or not ID_RE.match(req['id']):
        raise ValueError('bad request id')
    if not isinstance(req.get('ts'), int) or abs(now() - req['ts']) > REQUEST_MAX_AGE:
        raise ValueError('request expired')
    action = req.get('action')
    if action not in ('check', 'upgrade', 'upload_upgrade', 'set_config'):
        raise ValueError('unknown action')
    user = req.get('user')
    if not isinstance(user, str) or not re.match(r'^[\w.@\- ]{1,64}$', user):
        raise ValueError('bad user')
    if not isinstance(req.get('userid'), str) or not re.match(r'^\d{1,20}$', req['userid']):
        raise ValueError('bad userid')
    clean = {'id': req['id'], 'action': action, 'user': user, 'userid': req['userid']}
    if action == 'upgrade':
        if not parse_version(req.get('version')):
            raise ValueError('target is not a release tag (vX.Y.Z-vzN)')
        clean['version'] = req['version']
    elif action == 'upload_upgrade':
        m = TARBALL_RE.match(req.get('orig_name') or '')
        if not m:
            raise ValueError('package file name must be vizoure-nms-<version>-install.tar.gz')
        clean['orig_name'] = req['orig_name']
        clean['version'] = m.group(1)
    elif action == 'set_config':
        if req.get('channel') not in CHANNELS:
            raise ValueError('bad channel')
        proxy = req.get('proxy', '')
        if not isinstance(proxy, str) or not (proxy == '' or PROXY_RE.match(proxy)):
            raise ValueError('bad proxy URL (use http(s)://host[:port], no credentials)')
        clean['channel'] = req['channel']
        clean['proxy'] = proxy
    return clean


def consume_requests():
    """Yield validated requests; every spool file is removed whether or not it was valid."""
    try:
        names = sorted(os.listdir(REQ_DIR), key=lambda n: os.lstat(os.path.join(REQ_DIR, n)).st_mtime)
    except OSError:
        return
    seen = read_json(SEEN_FILE, [])
    for n in names:
        path = os.path.join(REQ_DIR, n)
        if not n.endswith('.json'):
            _unlink(path)
            continue
        try:
            with open_spool_file(path, MAX_REQUEST) as f:
                raw = f.read(MAX_REQUEST + 1)
            _unlink(path)
            req = validate_request(json.loads(raw.decode('utf-8')))
            if req['id'] in seen:
                raise ValueError('replayed request id')
            seen = (seen + [req['id']])[-200:]
            write_atomic(SEEN_FILE, json.dumps(seen), 0o600)
            yield req
        except (OSError, ValueError) as e:
            _unlink(path)
            log('rejected request %s: %s' % (n, short_error(e)))
            append_history({'ts': now(), 'result': 'rejected', 'error': short_error(e), 'request_file': n[:64]})


def _unlink(path):
    try:
        os.unlink(path)
    except OSError:
        pass


# ----------------------------------------------------------------------------------------------
# upgrade run
# ----------------------------------------------------------------------------------------------

class Run:
    def __init__(self, req, source):
        self.req = req
        self.id = req['id']
        self.dir = os.path.join(RUN_DIR, self.id)
        os.makedirs(self.dir, mode=0o755, exist_ok=True)
        self.logf = open(os.path.join(self.dir, 'log.txt'), 'a')
        os.chmod(os.path.join(self.dir, 'log.txt'), 0o644)
        # the unfiltered output (package names etc.) stays root-only for administrators
        fd = os.open(os.path.join(self.dir, 'log.raw.txt'), os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
        self.rawf = os.fdopen(fd, 'a')
        self.status = {'id': self.id, 'state': 'queued', 'step': 'Queued', 'source': source,
                       'user': req['user'], 'userid': req['userid'], 'to': req.get('version'),
                       'from': installed_version(), 'started': now(), 'ended': None, 'heartbeat': now(),
                       'mode': None, 'backup_file': None, 'error': None, 'fix': None, 'recovery': None}
        self._stop = threading.Event()
        self.save()

    def save(self):
        self.status['heartbeat'] = now()
        write_atomic(os.path.join(self.dir, 'status.json'), json.dumps(self.status, indent=1))

    def say(self, line):
        line = line.rstrip('\n')
        self.rawf.write(line + '\n')
        self.rawf.flush()
        # customer-visible log: no upstream product names, no credential-looking lines
        self.logf.write(customer_text(redact_line(line)) + '\n')
        self.logf.flush()

    def set(self, state, step):
        self.status['state'] = state
        self.status['step'] = step
        self.say('== %s' % step)
        self.save()

    def heartbeat_loop(self):
        while not self._stop.wait(HEARTBEAT_EVERY):
            self.save()

    def reject(self, reason, fix):
        """Refused before anything was changed: not a failure, no recovery steps."""
        self._stop.set()
        self.status['state'] = 'rejected'
        self.status['step'] = 'Upload rejected - nothing was changed on the server' \
            if self.status['source'] == 'upload' else 'Upgrade not started - nothing was changed on the server'
        self.status['ended'] = now()
        self.status['error'] = reason
        self.status['fix'] = fix
        self.status['recovery'] = None
        self.say('REJECTED: %s %s' % (reason, fix))
        self.save()
        self.logf.close()
        self.rawf.close()
        entry = {k: self.status.get(k) for k in ('id', 'user', 'userid', 'from', 'to', 'mode', 'source', 'started',
                                                'ended')}
        entry.update({'result': 'rejected', 'error': reason, 'fix': fix, 'backup_file': None})
        append_history(entry)
        save_state(load_state())

    def finish(self, ok, error=None):
        self._stop.set()
        self.status['state'] = 'done' if ok else 'failed'
        self.status['step'] = 'Upgrade completed' if ok else 'Upgrade failed'
        self.status['ended'] = now()
        self.status['error'] = error
        if not ok:
            self.status['recovery'] = recovery_steps(self.status)
        self.say(('SUCCESS' if ok else 'FAILED: %s' % error))
        self.save()
        self.logf.close()
        self.rawf.close()
        entry = {k: self.status.get(k) for k in ('id', 'user', 'userid', 'from', 'to', 'mode', 'source', 'backup_file',
                                                'started', 'ended')}
        entry['result'] = 'success' if ok else 'failed'
        entry['error'] = error
        append_history(entry)
        st = load_state()
        save_state(st)


def recovery_steps(status):
    steps = ['Check the log on this page to see where the upgrade stopped.']
    if status.get('backup_file'):
        steps.append('Your database backup was kept: %s' % status['backup_file'])
        steps.append('To restore it: sudo vizoure stop server && zcat %s | sudo mysql vizoure && '
                     'sudo vizoure start server' % status['backup_file'])
    steps.append('If anything is stopped, start it again: sudo vizoure start   (check with: sudo vizoure status)')
    steps.append('The upgrade can be re-run from this page once the cause is fixed (it is safe to repeat).')
    steps.append('To go back to the previous release, install its package with scripts/upgrade.sh from the previous '
                 'release tarball (see README, Recovery).')
    return steps


def installed_core_version():
    r = subprocess.run(['dpkg-query', '-W', '-f=${Version}', 'zabbix-server-mysql'], stdout=subprocess.PIPE,
                       stderr=subprocess.DEVNULL, timeout=15)
    m = re.search(r'(\d+\.\d+\.\d+)', r.stdout.decode() if r.returncode == 0 else '')
    return m.group(1) if m else None


def run_upgrade(req, source):
    run = Run(req, source)
    hb = threading.Thread(target=run.heartbeat_loop, daemon=True)
    hb.start()
    work = os.path.join(WORK_DIR, run.id)
    changed = False  # becomes True only when upgrade.sh is started
    try:
        run.set('validating', 'Validating request')
        inst = installed_version()
        if not inst:
            raise Rejected('The installed version is unknown (/etc/vizoure/version is missing).',
                           'Re-run the command-line upgrade once (see the README).')
        target = req['version']
        if parse_version(target) <= parse_version(inst):
            raise Rejected('This release (%s) is not newer than the version installed (%s).' % (target, inst),
                           'Choose a newer release.')
        conf = load_config()
        os.makedirs(work, mode=0o700, exist_ok=True)
        tarball = os.path.join(work, 'package.tar.gz')
        sums = os.path.join(work, 'SHA256SUMS')
        sig = os.path.join(work, 'SHA256SUMS.sig')
        tar_name = 'vizoure-nms-%s-install.tar.gz' % target

        if source == 'github':
            state = load_state()
            rel = next((r for r in state['releases'] if r['tag'] == target), None)
            if rel is None or not release_visible(rel, conf['channel']):
                state = check_releases(force=False)
                rel = next((r for r in state['releases'] if r['tag'] == target), None)
            if rel is None:
                raise Rejected('%s is not a published release.' % target, 'Press "Check now" and choose a listed release.')
            if not release_visible(rel, conf['channel']):
                raise Rejected('This is a test release.', 'To install it, set Update channel to Test and save.')
            run.set('downloading', 'Downloading release %s' % target)
            base = 'https://github.com/%s/%s/releases/download/%s/' % (OWNER, REPO, target)
            try:
                download(base + tar_name, tarball, MAX_TARBALL, conf)
            except Exception:
                raise Rejected('The release could not be downloaded from GitHub.',
                               'Check the server\'s internet connection (or the proxy setting), or upgrade offline '
                               'with the 3 release files.')
            download(base + 'SHA256SUMS', sums, MAX_SUMS, conf)
            download(base + 'SHA256SUMS.sig', sig, MAX_SIG, conf)
        else:
            run.set('validating', 'Reading uploaded package')
            for suffix, dest, limit in (('.tar.gz', tarball, MAX_TARBALL), ('.SHA256SUMS', sums, MAX_SUMS),
                                        ('.SHA256SUMS.sig', sig, MAX_SIG)):
                src = os.path.join(UPLOAD_DIR, run.id + suffix)
                with open_spool_file(src, limit) as fin, open(dest, 'wb') as fout:
                    shutil.copyfileobj(fin, fout)
                os.chmod(dest, 0o600)
                _unlink(src)

        run.set('verifying', 'Verifying signature and checksum')
        verify_signature(sums, sig)
        check_checksum(sums, tar_name, tarball)

        run.set('extracting', 'Unpacking release')
        top = 'vizoure-nms-%s' % target
        src_dir = safe_extract(tarball, os.path.join(work, 'src'), top)
        for needed in ('scripts/upgrade.sh', 'release.json', 'branding/VERSION', 'branding/apply-branding.sh'):
            if not os.path.isfile(os.path.join(src_dir, needed)):
                raise Rejected('The package is not a valid Vizoure release (it is missing %s).' % needed,
                               'Download vizoure-nms-<version>-install.tar.gz from the Assets list of the release (not the Source code archive).')
        meta = read_json(os.path.join(src_dir, 'release.json'), None)
        with open(os.path.join(src_dir, 'branding/VERSION')) as f:
            pkg_version = f.read().strip()
        if (not isinstance(meta, dict) or meta.get('version') != target or pkg_version != target
                or meta.get('type') not in ('full', 'branding-only') or not ZBX_RE.match(str(meta.get('core_version')))):
            raise Rejected('The package contents do not match the release it claims to be.',
                           'Download the package again from the Vizoure releases page.')
        if meta.get('channel') == 'test' and conf['channel'] != 'test':
            raise Rejected('This is a test release.', 'To install it, set Update channel to Test and save.')

        # The updater (not the UI) decides the mode: branding-only only if declared AND Zabbix is unchanged.
        mode = 'full'
        if meta['type'] == 'branding-only' and meta['core_version'] == installed_core_version():
            mode = 'branding-only'
        run.status['mode'] = mode
        # keep a verified copy for recovery / re-run
        cdir = os.path.join(CACHE_DIR, target)
        os.makedirs(cdir, mode=0o755, exist_ok=True)
        shutil.copy(tarball, os.path.join(cdir, tar_name))
        shutil.copy(sums, os.path.join(cdir, 'SHA256SUMS'))
        shutil.copy(sig, os.path.join(cdir, 'SHA256SUMS.sig'))
        prune_cache()

        run.set('upgrading', 'Running upgrade (%s)' % mode)
        changed = True
        cmd = ['/bin/bash', os.path.join(src_dir, 'scripts/upgrade.sh'), meta['core_version']]
        if mode == 'branding-only':
            cmd.append('--branding-only')
        env = {'PATH': '/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin', 'LANG': 'C.UTF-8',
               'DEBIAN_FRONTEND': 'noninteractive', 'VIZOURE_REF': target, 'VIZOURE_FROM_UPDATER': '1',
               'HOME': '/root'}
        proc = subprocess.Popen(cmd, cwd=src_dir, env=env, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, text=True, errors='replace')
        deadline = time.time() + UPGRADE_TIMEOUT
        for line in proc.stdout:
            m = re.match(r'^VIZOURE_BACKUP_FILE=(/var/backups/vizoure/[\w.\-]+\.sql\.gz)$', line.strip())
            if m:
                run.status['backup_file'] = m.group(1)
            step = re.match(r'^\[(\d)/(\d)\] (.+)$', line.strip())
            if step:
                run.status['step'] = 'Upgrading: %s (%s/%s)' % (step.group(3)[:80], step.group(1), step.group(2))
                run.save()
            run.say(line)
            if time.time() > deadline:
                proc.kill()
                raise ValueError('upgrade timed out')
        rc = proc.wait()
        if rc == 75:
            # upgrade.sh refused to start (not enough disk space for the backup / backup failed): nothing was changed
            changed = False
            raise Rejected('The upgrade was not started because the database backup could not be made '
                           '(usually not enough free disk space).',
                           'Free up disk space on the server and try again; nothing was changed.')
        if rc != 0:
            raise ValueError('the upgrade script exited with status %d' % rc)
        run.finish(True)
    except Rejected as e:
        if changed:
            run.finish(False, short_error(e))
        else:
            run.reject(e.reason, e.fix)
    except Exception as e:  # noqa: BLE001 - every failure must end in a clean failed state
        if changed:
            run.finish(False, short_error(e))
        else:
            run.reject('The release could not be prepared: %s' % short_error(e),
                       'Check the server\'s internet connection (or the proxy setting), or upgrade offline with the '
                       '3 release files.')
    finally:
        shutil.rmtree(work, ignore_errors=True)
        for suffix in ('.tar.gz', '.SHA256SUMS', '.SHA256SUMS.sig'):
            _unlink(os.path.join(UPLOAD_DIR, run.id + suffix))


def prune_cache():
    try:
        tags = sorted((d for d in os.listdir(CACHE_DIR) if parse_version(d)), key=parse_version, reverse=True)
    except OSError:
        return
    for old in tags[KEEP_CACHED_RELEASES:]:
        shutil.rmtree(os.path.join(CACHE_DIR, old), ignore_errors=True)


def reconcile():
    """Runs left in an active state while no updater process holds the lock were killed midway."""
    try:
        runs = os.listdir(RUN_DIR)
    except OSError:
        return
    for rid in runs:
        sp = os.path.join(RUN_DIR, rid, 'status.json')
        st = read_json(sp, None)
        if not isinstance(st, dict) or st.get('state') not in RUNNING_STATES:
            continue
        st['state'] = 'failed'
        st['step'] = 'Upgrade interrupted'
        st['ended'] = now()
        st['error'] = 'The upgrade was interrupted (updater stopped or machine rebooted) before it finished.'
        st['recovery'] = recovery_steps(st)
        write_atomic(sp, json.dumps(st, indent=1))
        append_history({k: st.get(k) for k in ('id', 'user', 'userid', 'from', 'to', 'mode', 'source', 'backup_file',
                                               'started', 'ended')} | {'result': 'interrupted', 'error': st['error']})
        shutil.rmtree(os.path.join(WORK_DIR, rid), ignore_errors=True)
    save_state(load_state())


# ----------------------------------------------------------------------------------------------
# entry points
# ----------------------------------------------------------------------------------------------

def locked():
    os.makedirs(os.path.dirname(LOCK_FILE), exist_ok=True)
    fd = os.open(LOCK_FILE, os.O_RDWR | os.O_CREAT, 0o600)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        os.close(fd)
        return None
    return fd


def handle(req):
    a = req['action']
    log('handling %s from %s' % (a, req['user']))
    if a == 'check':
        check_releases(force=True)
    elif a == 'set_config':
        save_config({'channel': req['channel'], 'proxy': req['proxy']})
        save_state(load_state())
        append_history({'ts': now(), 'user': req['user'], 'userid': req['userid'], 'result': 'config',
                        'error': None, 'channel': req['channel']})
        check_releases(force=False)
    elif a in ('upgrade', 'upload_upgrade'):
        run_upgrade(req, 'github' if a == 'upgrade' else 'upload')


def main(argv):
    if len(argv) != 2 or argv[1] not in ('--process', '--check', '--reconcile'):
        print(__doc__)
        return 2
    if os.geteuid() != 0 and os.environ.get('VIZOURE_UPDATER_PREFIX') is None:
        print('must run as root', file=sys.stderr)
        return 2
    for d in (STATE_DIR, RUN_DIR, WORK_DIR, CACHE_DIR):
        os.makedirs(d, mode=0o755, exist_ok=True)
    fd = locked()
    if fd is None:
        log('another updater run is active; exiting')
        return 0
    try:
        if argv[1] == '--reconcile':
            reconcile()
        elif argv[1] == '--check':
            reconcile()
            check_releases(force=False)
        else:
            reconcile()
            while True:
                reqs = list(consume_requests())
                if not reqs:
                    break
                for r in reqs:
                    handle(r)
    finally:
        os.close(fd)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
