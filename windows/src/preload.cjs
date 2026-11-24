'use strict';

const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('cosmNotes', {
  read: () => ipcRenderer.invoke('cosm:read'),
  change: command => ipcRenderer.invoke('cosm:change', command),
  windowAction: name => ipcRenderer.invoke('cosm:window', name),
  openNote: id => ipcRenderer.invoke('cosm:note', id),
  checkUpdate: () => ipcRenderer.invoke('cosm:update'),
  download: () => ipcRenderer.invoke('cosm:download'),
  onState: listener => ipcRenderer.on('cosm:state', (_event, state) => listener(state)),
  onUpdate: listener => ipcRenderer.on('cosm:version', (_event, state) => listener(state)),
  onNavigate: listener => ipcRenderer.on('cosm:go', (_event, section) => listener(section))
});
