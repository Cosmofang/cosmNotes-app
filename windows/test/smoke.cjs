'use strict';

const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const assert = require('node:assert/strict');
const { spawnSync } = require('node:child_process');
const { _electron } = require('playwright-core');

const installed = process.env.COSMNOTES_TEST_EXE;
const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'cosmnotes-smoke-'));
const options = {
  executablePath: installed || require('electron'),
  args: installed ? ['--disable-gpu'] : [path.join(__dirname, '..'), '--disable-gpu'],
  env: { ...process.env, COSMNOTES_DATA_DIR: directory },
  timeout: 30_000
};

const visible = locator => locator.waitFor({ state: 'visible', timeout: 6_000 });

async function submit(page) {
  const dialog = page.getByRole('dialog');
  await dialog.getByRole('button', { name: '保存', exact: true }).click();
  await dialog.waitFor({ state: 'hidden', timeout: 4_000 });
}

async function checkWindowsMCP(page) {
  if (process.platform !== 'win32' || !installed) return;
  const server = path.join(path.dirname(installed), 'resources', 'mcp', 'cosmnotes_mcp.py');
  const message = {
    jsonrpc: '2.0', id: 1, method: 'tools/call',
    params: { name: 'create_work', arguments: { title: 'Codex 烟雾测试', notes: 'MCP 写盘', due_date: '2099-06-01' } }
  };
  const tool = spawnSync('python', [server], {
    env: { ...process.env, COSMNOTES_DATA_DIR: directory, COSMNOTES_APP_PATH: installed },
    input: JSON.stringify(message) + '\n', encoding: 'utf8', timeout: 20_000
  });
  assert.equal(tool.status, 0, tool.error?.message || tool.stderr);
  const result = JSON.parse(tool.stdout.trim()).result;
  assert.equal(result?.isError, false, tool.stdout);
  const data = JSON.parse(fs.readFileSync(path.join(directory, 'work-items.json'), 'utf8'));
  assert.equal(data.filter(row => row.title === 'Codex 烟雾测试').length, 1);
  await page.locator('.project').filter({ has: page.getByRole('button', { name: /未归类/ }) })
    .getByRole('button', { name: /未归类/ }).click();
  await visible(page.getByRole('button', { name: 'Codex 烟雾测试', exact: true }));
}

async function run() {
  let app;
  try {
    app = await _electron.launch(options);
    const page = await app.firstWindow();
    page.on('pageerror', error => console.error('Renderer:', error.message));
    if (installed) {
      assert.equal(await app.evaluate(({ app: desktop }) => desktop.getVersion()),
        require('../package.json').version);
      assert.equal(await app.evaluate(() => process.arch), 'x64');
    }

    await visible(page.getByRole('heading', { name: '工作时间轴' }));
    await page.getByRole('button', { name: /添加项目/ }).click();
    await page.getByLabel('项目名称').fill('Platform QA');
    await page.getByLabel('配色').selectOption('teal');
    await submit(page);
    await page.locator('.project-heading').filter({ hasText: 'Platform QA' }).click();
    await page.getByRole('button', { name: /添加工作/ }).click();
    await page.getByLabel('工作标题').fill('Verify delivery');
    await page.getByLabel('截止日期').fill('2099-05-01');
    await page.getByLabel('概要').fill('Review with the team');
    await submit(page);
    await page.getByRole('button', { name: 'Verify delivery', exact: true }).click();
    await visible(page.getByText('Review with the team'));
    await page.getByRole('button', { name: '置顶工作' }).click();
    await visible(page.locator('.group h3').getByText('已置顶'));
    await page.getByRole('button', { name: '窗口置顶' }).click();
    await visible(page.getByRole('button', { name: '取消窗口置顶' }));
    assert.equal(await app.evaluate(({ BrowserWindow }) => BrowserWindow.getAllWindows()[0].isAlwaysOnTop()), true);
    await page.getByRole('button', { name: '收拢月历' }).click();
    await visible(page.getByRole('button', { name: '展开月历' }));
    if (process.env.COSMNOTES_SMOKE_SCREENSHOT) await page.screenshot({ path: process.env.COSMNOTES_SMOKE_SCREENSHOT });

    await page.getByRole('button', { name: '便签', exact: true }).click();
    await page.getByRole('button', { name: '新增便签', exact: true }).click();
    await page.getByLabel('类型').selectOption('todo');
    await page.getByLabel('内容').fill('Verify checklist');
    await submit(page);
    await page.getByRole('button', { name: /Verify checklist/ }).click();
    await visible(page.getByRole('button', { name: /Verify checklist/, pressed: true }));
    const floating = app.waitForEvent('window');
    await page.getByRole('button', { name: '打开桌面浮窗' }).click();
    const note = await floating;
    await visible(note.getByRole('heading', { name: '桌面便签' }));
    await note.getByRole('button', { name: '关闭浮窗' }).click();
    await page.getByRole('button', { name: '工作', exact: true }).click();
    await checkWindowsMCP(page);

    await app.close();
    app = await _electron.launch(options);
    const reopened = await app.firstWindow();
    await visible(reopened.getByRole('heading', { name: '工作时间轴' }));
    await reopened.locator('.project-heading').filter({ hasText: 'Platform QA' }).click();
    await visible(reopened.getByRole('button', { name: 'Verify delivery', exact: true }));
    assert.equal(await app.evaluate(({ BrowserWindow }) => BrowserWindow.getAllWindows()[0].isAlwaysOnTop()), true);
    const work = JSON.parse(fs.readFileSync(path.join(directory, 'work-items.json'), 'utf8'));
    assert.equal(work.find(item => item.title === 'Verify delivery')?.dueDate, '2099-05-01');
    console.log('Verified desktop launch, timeline, floating notes and data after restart.');
  } finally {
    if (app) await app.close();
    fs.rmSync(directory, { recursive: true, force: true, maxRetries: 5, retryDelay: 300 });
  }
}

run().catch(error => { console.error(error); process.exitCode = 1; });
