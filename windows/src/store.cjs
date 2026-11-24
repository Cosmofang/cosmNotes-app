'use strict';

const fs = require('node:fs');
const path = require('node:path');
const { randomUUID } = require('node:crypto');
const { TextEncoder } = require('node:util');
const { dayKey, validDay, sectionFor, orderedWork, moved, projectColors, noteColors } = require('./model.js');

const uuid = /^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/i;
const encoder = new TextEncoder();
const collections = {
  projects: 'work-projects.json',
  work: 'work-items.json',
  notes: 'windows-notes.json',
  prefs: 'windows-preferences.json'
};
const defaultPrefs = {
  title: '工作时间轴', theme: 'dark', pinned: false, calendar: true, calendarBelow: false,
  bounds: null, updateSeen: ''
};
const cocoatime = () => Date.now() / 1000 - 978307200;

function checkedText(value, max, message, { optional = false, trim = false } = {}) {
  if (typeof value !== 'string') throw new Error(message);
  const result = trim ? value.trim() : value;
  if ((!optional && !result.trim()) || encoder.encode(result).length > max) throw new Error(message);
  return result;
}

function locate(rows, id, message) {
  const index = rows.findIndex(row => row.id === id);
  if (index < 0) throw new Error(message);
  return index;
}

function saveJSON(directory, filename, value) {
  const target = path.join(directory, filename);
  const temp = target + '.' + randomUUID() + '.tmp';
  try {
    fs.writeFileSync(temp, JSON.stringify(value, null, 2) + '\n', { mode: 0o600, flag: 'wx' });
    fs.renameSync(temp, target);
  } finally {
    fs.rmSync(temp, { force: true });
  }
}

class Store {
  constructor(directory) {
    this.directory = directory;
    this.errors = {};
    fs.mkdirSync(directory, { recursive: true });
    this.projects = this.load('projects', [], Array.isArray);
    this.work = this.load('work', [], Array.isArray);
    this.notes = this.load('notes', [], Array.isArray);
    this.prefs = {
      ...defaultPrefs,
      ...this.load('prefs', {}, value => value !== null && typeof value === 'object' && !Array.isArray(value))
    };
  }

  load(name, fallback, valid) {
    try {
      const value = JSON.parse(fs.readFileSync(path.join(this.directory, collections[name]), 'utf8'));
      if (!valid(value)) throw new Error('文件格式不正确');
      if (Array.isArray(value)) {
        const ids = new Set();
        for (const row of value) {
          if (!row || typeof row.id !== 'string' || !uuid.test(row.id) || ids.has(row.id.toLowerCase())) {
            throw new Error('记录 ID 无效或重复');
          }
          ids.add(row.id.toLowerCase());
          if (name === 'projects' && typeof row.name !== 'string') throw new Error('项目名称无效');
          if (name === 'work' && (!validDay(row.dueDate) || typeof row.title !== 'string'
              || typeof row.notes !== 'string' || !Number.isFinite(row.createdAt))) throw new Error('工作记录无效');
          if (name === 'notes' && typeof row.text !== 'string') throw new Error('便签内容无效');
        }
      }
      return value;
    } catch (error) {
      if (error.code !== 'ENOENT') this.errors[name] = '无法读取 ' + collections[name] + '。原文件已保留。';
      return fallback;
    }
  }

  save(name, next) {
    if (this.errors[name]) throw new Error(this.errors[name]);
    saveJSON(this.directory, collections[name], next);
    this[name] = next;
  }

  snapshot() {
    return { projects: this.projects, work: this.work, notes: this.notes, prefs: this.prefs, errors: this.errors };
  }

  updatePrefs(delta) {
    this.save('prefs', { ...this.prefs, ...delta });
  }

  projectFor(item) {
    return this.projects.some(project => project.id === item.projectID) ? item.projectID : undefined;
  }

  saveProject(command) {
    const name = checkedText(command.name, 160, '请输入项目名称（最多 160 字节）。', { trim: true });
    const { color, id } = command;
    if (!Object.hasOwn(projectColors, color)) throw new Error('请选择项目颜色。');
    const key = name.normalize('NFKC').toLocaleLowerCase();
    if (this.projects.some(project => project.id !== id && project.name.normalize('NFKC').toLocaleLowerCase() === key)) {
      throw new Error('项目名称已存在。');
    }
    const projects = [...this.projects];
    if (id) {
      const index = locate(projects, id, '找不到项目。');
      projects[index] = { id, name, color };
    } else {
      projects.push({ id: randomUUID(), name, color });
    }
    this.save('projects', projects);
  }

  saveWork(command, requestID) {
    const title = checkedText(command.title, 512, '请输入工作标题（最多 512 字节）。', { trim: true });
    const notes = checkedText(command.notes, 8192, '概要最多 8192 字节。', { optional: true });
    const { dueDate, id } = command;
    if (!validDay(dueDate)) throw new Error('请选择有效的截止日期。');
    const projectID = command.projectID || undefined;
    if (projectID) locate(this.projects, projectID, '找不到项目。');
    const work = [...this.work];
    if (id) {
      const index = locate(work, id, '找不到这条工作。');
      const previous = work[index];
      const manualOrder = previous.projectID === projectID ? previous.manualOrder : undefined;
      work[index] = { ...previous, title, notes, dueDate, projectID, manualOrder };
    } else {
      const existing = requestID && work.find(row => row.id.toLowerCase() === requestID.toLowerCase());
      if (existing) {
        if (existing.title === title && existing.dueDate === dueDate && existing.notes === notes) return;
        throw new Error('工作 ID 已存在。');
      }
      work.push({ id: requestID || randomUUID(), title, notes, dueDate, projectID, createdAt: cocoatime() });
    }
    this.save('work', work);
  }

  changeWork(command) {
    const work = [...this.work];
    const index = locate(work, command.id, '找不到这条工作。');
    const item = { ...work[index] };
    switch (command.type) {
      case 'work-pin':
        item.pinned = !item.pinned;
        break;
      case 'work-complete':
        item.completedAt = item.completedAt == null ? cocoatime() : undefined;
        break;
      case 'work-move':
        if (command.projectID) locate(this.projects, command.projectID, '找不到项目。');
        item.projectID = command.projectID || undefined;
        item.manualOrder = undefined;
        break;
      case 'work-delete':
        work.splice(index, 1);
        this.save('work', work);
        return;
    }
    work[index] = item;
    this.save('work', work);
  }

  reorderWork(command) {
    const source = this.work[locate(this.work, command.id, '找不到这条工作。')];
    const today = dayKey();
    const section = sectionFor(source, today);
    const projectID = this.projectFor(source);
    const siblings = this.work.filter(item => this.projectFor(item) === projectID && sectionFor(item, today) === section);
    const ordered = orderedWork(siblings, section);
    const next = moved(ordered, command.id, command.target, command.after);
    if (next === ordered) return;
    const positions = new Map(next.map((item, index) => [item.id, index]));
    this.save('work', this.work.map(item => positions.has(item.id)
      ? { ...item, manualOrder: { section, position: positions.get(item.id) } }
      : item));
  }

  changeNote(command) {
    const notes = [...this.notes];
    const id = command.id || randomUUID();
    const index = command.id ? locate(notes, id, '找不到便签。') : notes.length;
    const note = { ...notes[index], id };
    switch (command.type) {
      case 'note-save': {
        note.text = checkedText(command.text, 128 * 1024, '便签内容最多 128 KB。', { optional: true });
        if (!Object.hasOwn(noteColors, command.theme)) throw new Error('请选择便签颜色。');
        note.theme = command.theme;
        note.kind = command.kind === 'todo' ? 'todo' : 'text';
        break;
      }
      case 'note-close': {
        if (!note.text.trim()) {
          notes.splice(index, 1);
          this.save('notes', notes);
          return id;
        }
        note.archivedAt = new Date().toISOString();
        break;
      }
      case 'note-restore':
        delete note.archivedAt;
        break;
      case 'note-pin':
        note.pinned = !note.pinned;
        break;
      case 'note-collapse':
        note.collapsed = !note.collapsed;
        break;
    }
    notes[index] = note;
    this.save('notes', notes);
    return id;
  }

  dispatch(command) {
    switch (command?.type) {
      case 'project-save': return this.saveProject(command);
      case 'project-order': return this.save('projects', moved(this.projects, command.id, command.target, command.after));
      case 'work-save': return this.saveWork(command);
      case 'work-order': return this.reorderWork(command);
      case 'work-move':
      case 'work-complete':
      case 'work-delete':
      case 'work-pin': return this.changeWork(command);
      case 'note-save':
      case 'note-close':
      case 'note-restore':
      case 'note-pin':
      case 'note-collapse': return this.changeNote(command);
      case 'title': return this.updatePrefs({ title: checkedText(command.title, 160, '请输入窗口标题。', { trim: true }) });
      case 'theme': return this.updatePrefs({ theme: this.prefs.theme === 'dark' ? 'light' : 'dark' });
      case 'pin-window': return this.updatePrefs({ pinned: !this.prefs.pinned });
      case 'calendar': return this.updatePrefs({ calendar: !this.prefs.calendar });
      case 'calendar-position': return this.updatePrefs({ calendarBelow: !this.prefs.calendarBelow });
      default: throw new Error('无法执行这项操作。');
    }
  }

  drainInbox() {
    const directory = path.join(this.directory, 'work-requests');
    if (!fs.existsSync(directory)) return false;
    let changed = false;
    for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
      const id = entry.name.slice(0, -5);
      if (!entry.isFile() || !entry.name.endsWith('.json') || !uuid.test(id)) continue;
      const request = path.join(directory, entry.name);
      try {
        if (fs.statSync(request).size > 65536) continue;
        const { title, dueDate, notes } = JSON.parse(fs.readFileSync(request, 'utf8'));
        this.saveWork({ title, dueDate, notes }, id);
        changed = true;
        fs.rmSync(request, { force: true });
      } catch (error) {
        if (error.code !== 'ENOENT') console.warn('Could not read work request', id, error.message);
      }
    }
    return changed;
  }
}

module.exports = { Store };
