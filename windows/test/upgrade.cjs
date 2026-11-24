'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const http = require('node:http');
const { generateKeyPairSync, randomUUID } = require('node:crypto');
const { spawnSync } = require('node:child_process');
const { _electron } = require('playwright-core');
const asar = require('@electron/asar');
const writeFeed = require('../../scripts/windows-update-feed.cjs');

const installed = process.env.COSMNOTES_TEST_EXE;
const setup = process.argv[2];
const version = require('../package.json').version;
const expected = '0.6.99';

function installedProcesses() {
  const powershell = spawnSync('pwsh', ['-NoProfile', '-Command',
    'Get-CimInstance Win32_Process -Filter "Name = \'cosmNotes.exe\'" | Where-Object { $_.ExecutablePath -eq $env:COSMNOTES_TEST_EXE } | Select-Object -ExpandProperty ProcessId'
  ], { encoding: 'utf8', timeout: 8000 });
  assert.equal(powershell.status, 0, powershell.stderr);
  return powershell.stdout.split(/\s+/).filter(Boolean).map(value => Number(value));
}

async function waitFor(check, seconds) {
  const deadline = Date.now() + seconds * 1000;
  while (Date.now() < deadline) {
    if (await check()) return;
    await new Promise(resolve => setTimeout(resolve, 500));
  }
  throw new Error('The installer did not complete and relaunch cosmNotes.');
}

async function run() {
  assert.equal(process.platform, 'win32');
  assert.ok(installed?.endsWith('cosmNotes.exe') && fs.existsSync(installed));
  assert.ok(setup && fs.existsSync(setup));
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'cosmnotes-upgrade-'));
  const data = path.join(root, 'profile');
  const resources = path.join(path.dirname(installed), 'resources');
  const bundle = path.join(resources, 'app.asar');
  const manifest = path.join(root, 'latest.yml');
  const options = {
    executablePath: installed,
    args: ['--disable-gpu'],
    env: { ...process.env, COSMNOTES_DATA_DIR: data },
    timeout: 30_000
  };
  const requests = new Map();
  const server = http.createServer((req, res) => {
    const file = new URL(req.url, 'http://localhost').pathname;
    const entry = file === '/latest.yml' ? manifest : file === '/' + path.basename(setup) ? setup : null;
    if (!entry) { res.writeHead(404).end(); return; }
    requests.set(file, (requests.get(file) || 0) + 1);
    res.writeHead(200, { 'Content-Length': fs.statSync(entry).size });
    fs.createReadStream(entry).pipe(res);
  });

  let application;
  try {
    const raw = (key, type) => key.export({ format: 'der', type }).subarray(-32).toString('base64');
    const keys = generateKeyPairSync('ed25519');
    const publicKey = raw(keys.publicKey, 'spki');
    await writeFeed(setup, version, manifest, publicKey, raw(keys.privateKey, 'pkcs8'));
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    fs.writeFileSync(path.join(resources, 'app-update.yml'), JSON.stringify({
      provider: 'generic', url: 'http://127.0.0.1:' + server.address().port + '/',
      updaterCacheDirName: 'cosmnotes-test-' + randomUUID()
    }));
    fs.writeFileSync(path.join(resources, 'UpdatePublicKey'), publicKey);

    // Give the installed fixture an older version while keeping the packaged updater.
    const staging = path.join(root, 'app');
    asar.extractAll(bundle, staging);
    const packageJSON = path.join(staging, 'package.json');
    const info = JSON.parse(fs.readFileSync(packageJSON, 'utf8'));
    assert.equal(info.version, version);
    fs.writeFileSync(packageJSON, JSON.stringify({ ...info, version: expected }));
    const olderPackage = path.join(root, 'older.asar');
    await asar.createPackage(staging, olderPackage);
    asar.uncache(bundle);
    fs.copyFileSync(olderPackage, bundle);

    fs.mkdirSync(data);
    const workFile = path.join(data, 'work-items.json');
    const seed = Buffer.from(JSON.stringify([{
      id: randomUUID(), title: '验证工作保留', dueDate: '2099-08-07', notes: '合成测试数据', createdAt: 22
    }]));
    fs.writeFileSync(workFile, seed);
    application = await _electron.launch(options);
    const page = await application.firstWindow();
    assert.equal(await application.evaluate(({ app }) => app.getVersion()), expected);
    const install = page.getByRole('button', { name: '重启并更新' });
    await install.waitFor({ timeout: 65_000 });
    const status = page.locator('#footer').getByText('cosmNotes v' + version + ' 更新已就绪');
    assert.equal(await status.isVisible(), true);
    assert.ok(requests.get('/' + path.basename(setup)) > 0);
    const before = new Set(installedProcesses());
    await install.click();
    await waitFor(() => {
      asar.uncache(bundle);
      try {
        const current = JSON.parse(asar.extractFile(bundle, 'package.json'));
        return current.version === version && installedProcesses().some(pid => !before.has(pid));
      } catch {
        return false;
      }
    }, 60);
    assert.deepEqual(fs.readFileSync(workFile), seed);
    console.log('Verified signed Windows update, in-app installation, relaunch and byte-identical work data.');
  } finally {
    if (application && application.process().exitCode === null) await application.close().catch(() => {});
    for (const pid of installedProcesses()) {
      try { process.kill(pid); } catch {}
    }
    server.close();
    fs.rmSync(root, { recursive: true, force: true, maxRetries: 5, retryDelay: 400 });
  }
}

run().catch(error => { console.error(error); process.exitCode = 1; });
