'use strict';

const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { fileURLToPath } = require('node:url');
const { app, BrowserWindow, ipcMain, Menu, screen, Tray } = require('electron');
const { NsisUpdater } = require('electron-updater');
const { Store } = require('./store.cjs');
const { verifyManifest, sha512File } = require('./updates.cjs');

const localPath = process.env.LOCALAPPDATA || path.join(os.homedir(), 'AppData', 'Local');
const dataPath = path.resolve(process.env.COSMNOTES_DATA_DIR
  || (process.platform === 'win32' ? path.join(localPath, 'cosmNotes') : path.join(app.getPath('appData'), 'cosmNotes Desktop')));
app.setPath('userData', dataPath);
app.setAppUserModelId('com.cosmofang.cosmnotes');
app.setName('cosmNotes');

const icon = path.join(__dirname, '..', 'resources', 'icon.png');
const view = path.join(__dirname, 'index.html');
const independentNotes = new Map();
let store;
let timeline;
let tray;
let quitting = false;
let saveBoundsTimer;
let priorHeight;
let refreshUpdate;
let manualCheckRequested = false;
let updater;
let preparedUpdate;
let installing = false;
let updateState = { status: 'idle' };

function publish(channel, value, except) {
  for (const window of BrowserWindow.getAllWindows()) {
    if (!window.isDestroyed() && window.webContents !== except) window.webContents.send(channel, value);
  }
}

function publishState(except) {
  for (const [id, window] of independentNotes) {
    const note = store.notes.find(item => item.id === id && !item.archivedAt);
    if (!note) window.close();
    else window.setAlwaysOnTop(Boolean(note.pinned));
  }
  if (timeline && !timeline.isDestroyed()) timeline.setAlwaysOnTop(Boolean(store.prefs.pinned));
  publish('cosm:state', store.snapshot(), except);
}

function setUpdateState(status, details = {}) {
  updateState = { status, installed: app.getVersion(), ...details };
  publish('cosm:version', updateState);
  configureTray();
}

function configureUpdater() {
  if (!app.isPackaged || process.platform !== 'win32') return;
  updater = new NsisUpdater();
  updater.autoDownload = false;
  updater.autoInstallOnAppQuit = false;
  updater.disableDifferentialDownload = true;
  updater.disableWebInstaller = true;
  updater.allowPrerelease = false;
  updater.on('download-progress', progress => {
    if (updateState.status === 'preparing') {
      setUpdateState('preparing', { version: updateState.version, percent: Math.floor(progress.percent) });
    }
  });
  updater.on('error', error => {
    console.warn('App update:', error.message);
    if (installing) {
      installing = false;
      setUpdateState('failed');
    }
  });
}

async function checkUpdate(manual = false) {
  if (!updater || preparedUpdate || installing) return;
  manualCheckRequested ||= manual;
  if (refreshUpdate) return refreshUpdate;
  if (manual) setUpdateState('checking');

  refreshUpdate = (async () => {
    try {
      const result = await updater.checkForUpdates();
      if (!result) return;
      const key = fs.readFileSync(path.join(process.resourcesPath, 'UpdatePublicKey'), 'utf8').trim();
      const manifest = verifyManifest(result.updateInfo, key);
      if (!result.isUpdateAvailable) {
        setUpdateState(manualCheckRequested ? 'current' : 'idle');
        return;
      }
      const version = 'v' + manifest.version;
      setUpdateState('preparing', { version });
      const [file] = await updater.downloadUpdate(result.cancellationToken);
      if (!file || await sha512File(file) !== manifest.sha512) throw new Error('更新包校验失败。');
      preparedUpdate = { file, version, sha512: manifest.sha512 };
      const notify = store.prefs.updateSeen !== version;
      if (notify) {
        try { store.updatePrefs({ updateSeen: version }); }
        catch (error) { console.warn(error.message); }
      }
      setUpdateState('ready', { version, notify });
    } catch (error) {
      if (manualCheckRequested || updateState.status === 'preparing') setUpdateState('failed');
      console.warn('Update check:', error.message);
    }
  })();
  try { await refreshUpdate; }
  finally {
    refreshUpdate = undefined;
    manualCheckRequested = false;
  }
}

async function installUpdate() {
  if (!preparedUpdate || installing) return;
  const { file, version, sha512 } = preparedUpdate;
  installing = true;
  setUpdateState('installing', { version });
  try {
    if (await sha512File(file) !== sha512) {
      preparedUpdate = undefined;
      throw new Error('更新包校验失败，请重新检查更新。');
    }
    updater.quitAndInstall(true, true);
  } catch (error) {
    installing = false;
    preparedUpdate = undefined;
    setUpdateState('failed');
    throw error;
  }
}

function securedWindow(options = {}) {
  const windowsBuild = Number(os.release().split('.')[2]);
  const acrylic = process.platform === 'win32' && windowsBuild >= 22621;
  const window = new BrowserWindow({
    icon, frame: false, show: false, thickFrame: true, backgroundColor: acrylic ? '#00000000' : '#17202c',
    backgroundMaterial: acrylic ? 'acrylic' : 'none',
    webPreferences: { preload: path.join(__dirname, 'preload.cjs'), sandbox: true, contextIsolation: true, nodeIntegration: false },
    ...options
  });
  window.webContents.setWindowOpenHandler(() => ({ action: 'deny' }));
  window.webContents.on('will-navigate', event => event.preventDefault());
  window.once('ready-to-show', () => window.show());
  return window;
}

function rememberBounds() {
  if (!timeline || timeline.isDestroyed() || timeline.isMinimized() || timeline.isMaximized() || priorHeight) return;
  try { store.updatePrefs({ bounds: timeline.getBounds() }); }
  catch (error) { console.warn(error.message); }
}

function restoredBounds() {
  const bounds = store.prefs.bounds;
  if (!bounds || !['x', 'y', 'width', 'height'].every(key => Number.isInteger(bounds[key]))
      || bounds.width < 400 || bounds.height < 350) return {};
  const area = screen.getDisplayMatching(bounds).workArea;
  const width = Math.min(bounds.width, area.width);
  const height = Math.min(bounds.height, area.height);
  return {
    width, height,
    x: Math.max(area.x, Math.min(bounds.x, area.x + area.width - width)),
    y: Math.max(area.y, Math.min(bounds.y, area.y + area.height - height))
  };
}

function showTimeline(section) {
  if (!timeline) {
    timeline = securedWindow({
      width: 510, height: 730, minWidth: 400, minHeight: 54, title: 'cosmNotes',
      alwaysOnTop: Boolean(store.prefs.pinned), ...restoredBounds()
    });
    timeline.loadFile(view, section ? { query: { section } } : {});
    timeline.on('close', event => {
      if (!quitting && tray) {
        event.preventDefault();
        rememberBounds();
        timeline.hide();
      }
    });
    timeline.on('closed', () => { timeline = undefined; });
    for (const event of ['move', 'resize']) {
      timeline.on(event, () => {
        clearTimeout(saveBoundsTimer);
        saveBoundsTimer = setTimeout(rememberBounds, 275);
      });
    }
    return;
  }
  if (timeline.isMinimized()) timeline.restore();
  if (section) {
    if (priorHeight) toggleCompact();
    timeline.webContents.send('cosm:go', section);
  }
  timeline.show();
  timeline.focus();
}

function toggleCompact() {
  if (timeline.isMaximized()) timeline.unmaximize();
  const bounds = timeline.getBounds();
  if (priorHeight) {
    timeline.setResizable(true);
    timeline.setBounds({ ...bounds, height: priorHeight });
    priorHeight = undefined;
  } else {
    rememberBounds();
    priorHeight = bounds.height;
    timeline.setBounds({ ...bounds, height: 58 });
    timeline.setResizable(false);
  }
  return Boolean(priorHeight);
}

function showNote(id) {
  const note = store.notes.find(item => item.id === id && !item.archivedAt);
  if (!note) return;
  if (independentNotes.has(id)) {
    independentNotes.get(id).show();
    return;
  }
  const window = securedWindow({
    width: 360, height: 352, minWidth: 310, minHeight: 230,
    title: 'cosmNotes · 便签', alwaysOnTop: Boolean(note.pinned)
  });
  independentNotes.set(id, window);
  window.on('closed', () => independentNotes.delete(id));
  window.loadFile(view, { query: { note: id } });
}

function configureTray() {
  if (!tray) return;
  tray.setToolTip(updateState.status === 'ready' ? 'cosmNotes · ' + updateState.version + ' 更新已就绪' : 'cosmNotes');
  const menu = [
    { label: '工作时间轴', click: () => showTimeline('work') },
    { label: '桌面便签', click: () => showTimeline('notes') },
    { label: '检查更新…', click: () => { showTimeline(); checkUpdate(true); } }
  ];
  if (updateState.status === 'ready') {
    menu.push({ label: '重启并更新', click: () => installUpdate().catch(error => console.warn(error.message)) });
  }
  menu.push({ type: 'separator' }, { label: '退出 cosmNotes', click: () => app.quit() });
  tray.setContextMenu(Menu.buildFromTemplate(menu));
}

function registerIPC() {
  const trusted = (channel, handler) => ipcMain.handle(channel, (event, payload) => {
    const sender = event.senderFrame;
    if (!sender || sender.parent || !sender.url.startsWith('file:') || fileURLToPath(sender.url) !== view) {
      throw new Error('无法执行这项操作。');
    }
    return handler(event, payload);
  });

  trusted('cosm:read', () => ({ ...store.snapshot(), update: { ...updateState, installed: app.getVersion() } }));
  trusted('cosm:change', (event, command) => {
    try {
      const result = store.dispatch(command);
      publishState(event.sender);
      return { result, state: store.snapshot() };
    } catch (error) {
      return { error: error.message };
    }
  });
  trusted('cosm:window', (event, name) => {
    const window = BrowserWindow.fromWebContents(event.sender);
    if (!window) return;
    if (name === 'close') window.close();
    if (name === 'minimize') window.minimize();
    if (name === 'compact' && window === timeline) return toggleCompact();
  });
  trusted('cosm:note', (_event, id) => showNote(id));
  trusted('cosm:update', () => checkUpdate(true));
  trusted('cosm:install-update', () => installUpdate());
}

if (!app.requestSingleInstanceLock()) {
  app.quit();
} else {
  app.on('second-instance', (_event, argv) => {
    if (store && !argv.includes('--background-work')) showTimeline();
  });
  app.on('before-quit', () => {
    quitting = true;
    clearTimeout(saveBoundsTimer);
    if (store) rememberBounds();
  });
  app.on('window-all-closed', () => {});
  app.whenReady().then(() => {
    store = new Store(dataPath);
    Menu.setApplicationMenu(null);
    tray = new Tray(icon);
    tray.on('click', () => showTimeline());
    tray.on('double-click', () => showTimeline());
    configureTray();
    registerIPC();
    configureUpdater();
    if (!process.argv.includes('--background-work')) showTimeline();
    const consumeWork = () => {
      try { if (store.drainInbox()) publishState(); }
      catch (error) { console.warn('Work inbox:', error.message); }
    };
    consumeWork();
    setInterval(consumeWork, 700);
    setTimeout(() => checkUpdate(), 1400);
    setInterval(checkUpdate, 4 * 60 * 60 * 1000);
    app.on('activate', () => showTimeline());
  });
}
