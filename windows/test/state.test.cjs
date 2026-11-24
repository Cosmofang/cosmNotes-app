'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { randomUUID } = require('node:crypto');
const { validDay, sectionFor, orderedWork } = require('../src/model.js');
const { Store } = require('../src/store.cjs');
const { windowsUpdate } = require('../src/updates.cjs');

function fixture(test) {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'cosmnotes-test-'));
  test.after(() => fs.rmSync(directory, { recursive: true, force: true }));
  return { store: new Store(directory), directory };
}

test('calendar-day deadline survives time zones and stays current through its due day', () => {
  assert.equal(validDay('2028-02-29'), true);
  assert.equal(validDay('2027-02-29'), false);
  assert.equal(validDay('2027-04-31'), false);
  const item = { dueDate: '2028-02-29' };
  assert.equal(sectionFor(item, '2028-02-28'), 'upcoming');
  assert.equal(sectionFor(item, '2028-02-29'), 'today');
  assert.equal(sectionFor(item, '2028-03-01'), 'overdue');
  assert.equal(sectionFor({ ...item, pinned: true }, '2028-03-01'), 'pinned');
  assert.equal(sectionFor({ ...item, pinned: true, completedAt: 5 }, '2028-03-01'), 'completed');
});

test('project and timeline changes persist with manual work order', context => {
  const { store, directory } = fixture(context);
  store.dispatch({ type: 'project-save', color: 'teal', name: 'Demo' });
  const projectID = store.projects[0].id;
  for (const title of ['First', 'Second']) {
    store.dispatch({ type: 'work-save', dueDate: '2099-01-01', notes: 'Summary', title, projectID });
  }
  const [first, second] = store.work;
  store.dispatch({ type: 'work-order', id: second.id, target: first.id, after: false });
  store.dispatch({ type: 'title', title: 'My work' });
  const reopened = new Store(directory);
  assert.equal(reopened.prefs.title, 'My work');
  assert.equal(reopened.projects[0].id, projectID);
  assert.deepEqual(orderedWork(reopened.work, 'upcoming').map(item => item.title), ['Second', 'First']);
  assert.throws(() => store.dispatch({ type: 'project-save', name: 'demo', color: 'blue' }), /已存在/);
});

test('an inbox request is idempotent and leaves the local work schema intact', context => {
  const { store, directory } = fixture(context);
  const requestDir = path.join(directory, 'work-requests');
  fs.mkdirSync(requestDir);
  const id = randomUUID();
  const request = path.join(requestDir, id + '.json');
  const payload = { title: '本地工作', dueDate: '2028-02-29', notes: '概要' };
  for (let attempt = 0; attempt < 2; attempt++) {
    fs.writeFileSync(request, JSON.stringify(payload));
    assert.equal(store.drainInbox(), true);
    assert.equal(fs.existsSync(request), false);
  }
  const work = new Store(directory).work;
  assert.equal(work.length, 1);
  assert.deepEqual({ title: work[0].title, dueDate: work[0].dueDate, notes: work[0].notes }, payload);
  assert.equal(work[0].id, id);
});

test('a malformed work file is preserved and cannot be overwritten by a save', context => {
  const { directory } = fixture(context);
  fs.writeFileSync(path.join(directory, 'work-items.json'), '{"unfinished":');
  const store = new Store(directory);
  assert.throws(() => store.dispatch({ type: 'work-save', title: 'A', notes: '', dueDate: '2028-10-01' }),
    /原文件已保留/);
  assert.equal(fs.readFileSync(path.join(directory, 'work-items.json'), 'utf8'), '{"unfinished":');
});

test('Windows release checks accept newer stable Windows installers only', () => {
  const asset = name => ({ name, state: 'uploaded' });
  const release = {
    tag_name: 'v0.10.1',
    draft: false,
    prerelease: false,
    assets: [asset('cosmNotes-v0.10.1-macOS.zip'), asset('cosmNotes-v0.10.1-Windows-x64-Setup.exe')]
  };
  assert.deepEqual(windowsUpdate(release, '0.6.0'), {
    version: 'v0.10.1',
    url: 'https://github.com/Cosmofang/cosmNotes-app/releases/download/v0.10.1/cosmNotes-v0.10.1-Windows-x64-Setup.exe'
  });
  assert.equal(windowsUpdate(release, '0.10.1'), null);
  assert.equal(windowsUpdate({ ...release, assets: release.assets.slice(0, 1) }, '0.6.0'), null);
  assert.equal(windowsUpdate({ ...release, prerelease: true }, '0.6.0'), null);
});
