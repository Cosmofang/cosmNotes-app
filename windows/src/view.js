'use strict';

const api = window.cosmNotes;
const { sections, projectColors, noteColors, dayKey, sectionFor, orderedWork } = window.cosmModel;
const query = new URLSearchParams(location.search);
const noteID = query.get('note');
const noProject = 'unassigned';
const all = 'all';
const groupTitles = { pinned: '已置顶', overdue: '已逾期', today: '今天', upcoming: '即将到期', completed: '已完成' };
const colorTitles = {
  blue: '蓝色', teal: '青色', green: '绿色', orange: '橙色', red: '红色', pink: '粉色', purple: '紫色', gray: '灰色',
  lemon: '柠檬黄', peach: '蜜桃粉', mint: '薄荷绿', sky: '天空蓝', lilac: '丁香紫'
};
const projectOpen = new Set();
const detailOpen = new Set();
let state;
let release;
let screen = query.get('section') || 'work';
let filter = all;
let month = new Date();
let selectedDay = '';
let compact = false;
let drag;
let placeholder;
let toastTimer;
let expandedSection;

const byID = id => document.getElementById(id);
const toolbar = byID('toolbar');
const tabs = byID('tabs');
const content = byID('content');
const footer = byID('footer');
const dialog = byID('dialog');
const editor = byID('editor');
const fields = byID('fields');
const formError = byID('form-error');

function element(tag, className, ...children) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  node.append(...children);
  return node;
}

function button(text, action, { title, kind, pressed } = {}) {
  const control = element('button', kind, text);
  control.type = 'button';
  if (title) {
    control.title = title;
    control.setAttribute('aria-label', title);
  }
  if (pressed !== undefined) control.setAttribute('aria-pressed', String(pressed));
  control.addEventListener('click', action);
  return control;
}

function icon(text, title, action, pressed, kind = '') {
  return button(text, action, { title, pressed, kind: 'icon ' + kind });
}

function textInput(name, value = '', type = 'text') {
  const input = element(type === 'area' ? 'textarea' : 'input');
  input.name = name;
  if (input.tagName === 'INPUT') input.type = type;
  input.value = value;
  if (type === 'date') input.addEventListener('click', () => input.showPicker?.());
  return input;
}

function dropdown(name, values, current) {
  const select = element('select');
  select.name = name;
  for (const [value, label] of values) {
    const option = element('option', '', label);
    option.value = value;
    select.append(option);
  }
  select.value = current;
  return select;
}

function labeled(title, control) {
  return element('label', '', title, control);
}

function toast(text) {
  const node = byID('toast');
  node.textContent = text;
  node.classList.add('visible');
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => node.classList.remove('visible'), 3300);
}

async function send(command, onSuccess) {
  try {
    const response = await api.change(command);
    if (response.error) throw new Error(response.error);
    state = response.state;
    onSuccess?.(response.result);
    render();
    return true;
  } catch (error) {
    if (dialog.open) formError.textContent = error.message;
    else toast(error.message);
    return false;
  }
}

function edit(title, inputs, buildCommand, onSuccess, danger) {
  byID('dialog-title').textContent = title;
  formError.textContent = '';
  fields.replaceChildren(...inputs);
  editor.querySelector('.danger')?.remove();
  if (danger) {
    const remove = button(danger.label, async () => {
      if (await send(danger.command)) dialog.close();
    }, { kind: 'danger' });
    editor.querySelector('.form-actions').prepend(remove);
  }
  editor.onsubmit = async event => {
    event.preventDefault();
    const save = editor.querySelector('button[type="submit"]');
    save.disabled = true;
    try {
      if (await send(buildCommand(Object.fromEntries(new FormData(editor))), onSuccess)) dialog.close();
    } finally {
      save.disabled = false;
    }
  };
  if (!dialog.open) dialog.showModal();
  fields.querySelector('input,select,textarea')?.focus();
}

for (const id of ['cancel', 'dialog-close']) byID(id).onclick = () => dialog.close();

function openWork(item, project = filter) {
  const title = textInput('title', item?.title);
  const dueDate = textInput('dueDate', item?.dueDate || selectedDay || dayKey(), 'date');
  title.required = true;
  dueDate.required = true;
  const choices = [['', '未归类'], ...state.projects.map(row => [row.id, row.name])];
  const projectID = filterProject(item ? item.projectID : project)?.id || '';
  edit(item ? '编辑工作' : '新增工作', [
    labeled('工作标题', title), labeled('截止日期', dueDate),
    labeled('项目', dropdown('projectID', choices, projectID)),
    labeled('概要', textInput('notes', item?.notes, 'area'))
  ], values => ({ type: 'work-save', id: item?.id, ...values }), () => {
    projectOpen.add(dropdownProjectID() || noProject);
  }, item ? { label: '删除工作', command: { type: 'work-delete', id: item.id } } : undefined);
}

function dropdownProjectID() {
  return fields.querySelector('[name="projectID"]')?.value;
}

function filterProject(id) {
  return state.projects.find(project => project.id === id);
}

function openProject(project) {
  const name = textInput('name', project?.name);
  name.required = true;
  const colors = Object.keys(projectColors).map(color => [color, colorTitles[color]]);
  edit(project ? '编辑项目' : '添加项目', [
    labeled('项目名称', name), labeled('配色', dropdown('color', colors, project?.color || 'blue'))
  ], values => ({ type: 'project-save', id: project?.id, ...values }));
}

function openTitle() {
  const title = textInput('title', state.prefs.title);
  title.required = true;
  edit('修改时间轴名称', [labeled('标题', title)], values => ({ type: 'title', ...values }));
}

function colored(node, color, property = '--project') {
  if (color) node.style.setProperty(property, color);
  return node;
}

function dragHandle(kind, id, heightHint) {
  const handle = element('span', 'icon grab', '☰');
  handle.title = '拖动';
  handle.draggable = true;
  handle.addEventListener('dragstart', event => {
    drag = { kind, id, size: heightHint()?.offsetHeight || 39 };
    event.dataTransfer.setData('text/plain', kind);
    event.dataTransfer.effectAllowed = 'move';
  });
  return handle;
}

function clearDrop() {
  placeholder?.remove();
  placeholder = undefined;
  document.querySelectorAll('.drop-into').forEach(node => node.classList.remove('drop-into'));
}

function dropTarget(node, canDrop, place, onDrop) {
  node.addEventListener('dragover', event => {
    if (!drag || !canDrop(drag)) return;
    event.preventDefault();
    event.stopPropagation();
    event.dataTransfer.dropEffect = 'move';
    const bounds = node.getBoundingClientRect();
    place(node, event.clientY >= bounds.top + bounds.height / 2);
  });
  node.addEventListener('drop', event => {
    if (!drag || !canDrop(drag)) return;
    event.preventDefault();
    event.stopPropagation();
    const bounds = node.getBoundingClientRect();
    const after = placeholder?.previousElementSibling === node || (!placeholder && event.clientY >= bounds.top + bounds.height / 2);
    const item = drag;
    drag = undefined;
    clearDrop();
    onDrop(item, after);
  });
}

function gap(node, after) {
  if (placeholder && (after ? placeholder.previousElementSibling === node : placeholder.nextElementSibling === node)) return;
  clearDrop();
  placeholder = element('div', 'drop-preview');
  placeholder.style.setProperty('--drop-height', Math.min(drag.size, 88) + 'px');
  placeholder.addEventListener('dragover', event => {
    event.preventDefault();
    event.stopPropagation();
    event.dataTransfer.dropEffect = 'move';
  });
  placeholder.addEventListener('drop', event => {
    if (!drag) return;
    event.preventDefault();
    event.stopPropagation();
    node.dispatchEvent(new DragEvent('drop', { bubbles: true, clientY: node.getBoundingClientRect().top + (after ? node.offsetHeight : 0) }));
  }, { capture: true });
  if (after) node.after(placeholder);
  else node.before(placeholder);
}

function into(node) {
  if (node.classList.contains('drop-into')) return;
  clearDrop();
  node.classList.add('drop-into');
}

document.addEventListener('dragend', () => { drag = undefined; clearDrop(); });
document.addEventListener('dragover', () => {
  if (drag) clearDrop();
});

function projectId(item) {
  return filterProject(item?.projectID)?.id || noProject;
}

function filterBar() {
  const bar = element('div', 'filters');
  const choices = [{ id: all, name: '全部工作' }, ...state.projects, { id: noProject, name: '未归类' }];
  for (const project of choices) {
    const selector = button(project.name, () => {
      filter = project.id;
      selectedDay = '';
      redrawContent();
    });
    const real = project.id !== all && project.id !== noProject;
    if (real) selector.prepend(colored(element('span', 'dot'), projectColors[project.color]));
    const chip = element('span', 'filter', selector);
    chip.setAttribute('aria-current', String(filter === project.id));
    if (real) chip.append(icon('✎', '编辑项目 ' + project.name, () => openProject(project)));
    if (project.id !== all) {
      dropTarget(chip, item => item.kind === 'work', into,
        item => send({ type: 'work-move', id: item.id, projectID: real ? project.id : undefined }));
    }
    bar.append(chip);
  }
  return bar;
}

function calendarPanel() {
  const year = month.getFullYear();
  const monthIndex = month.getMonth();
  const first = new Date(year, monthIndex, 1);
  const today = dayKey();
  const dates = new Map();
  for (const item of state.work) {
    if (filter !== all && projectId(item) !== filter) continue;
    const ids = dates.get(item.dueDate) || new Set();
    ids.add(projectId(item));
    dates.set(item.dueDate, ids);
  }
  const panel = element('section', 'calendar');
  const flip = delta => { month = new Date(year, monthIndex + delta, 1); redrawContent(); };
  panel.append(element('div', 'calendar-top',
    dragHandle('calendar', 'calendar', () => panel),
    icon('‹', '上个月', () => flip(-1)),
    element('strong', 'month', year + '年' + (monthIndex + 1) + '月'),
    icon('›', '下个月', () => flip(1)),
    icon(state.prefs.calendarBelow ? '↑' : '↓', '移动月历', () => send({ type: 'calendar-position' })),
    icon(state.prefs.calendar ? '⌃' : '⌄', state.prefs.calendar ? '收拢月历' : '展开月历',
      () => send({ type: 'calendar' }, () => { if (state.prefs.calendar) expandedSection = 'calendar-grid'; }))
  ));
  if (!state.prefs.calendar) return panel;
  const grid = expansion('calendar-grid', 'calendar-grid');
  for (const weekday of ['周一', '周二', '周三', '周四', '周五', '周六', '周日']) grid.append(element('span', 'weekday', weekday));
  const padding = (first.getDay() + 6) % 7;
  const last = new Date(year, monthIndex + 1, 0).getDate();
  for (let i = 0; i < padding; i++) grid.append(element('span'));
  for (let i = 1; i <= last; i++) {
    const date = dayKey(new Date(year, monthIndex, i));
    const marks = element('span', 'marks');
    const colors = [...(dates.get(date) || [])];
    const weekday = (padding + i - 1) % 7;
    for (const id of colors.slice(0, 5)) {
      const previous = dates.get(dayKey(new Date(year, monthIndex, i - 1)))?.has(id);
      const next = dates.get(dayKey(new Date(year, monthIndex, i + 1)))?.has(id);
      const mark = colored(element('span', 'mark'), projectColors[filterProject(id)?.color] || projectColors.gray);
      if (colors.length === 1 && i > 1 && weekday !== 0 && previous) mark.classList.add('before');
      if (colors.length === 1 && i < last && weekday !== 6 && next) mark.classList.add('after');
      marks.append(mark);
    }
    const cell = button(String(i), () => {
      selectedDay = selectedDay === date ? '' : date;
      redrawContent();
    }, { kind: 'day' + (date === today ? ' today' : '') + (date === selectedDay ? ' selected' : ''), title: date });
    cell.append(marks);
    grid.append(cell);
  }
  if (selectedDay) panel.append(button('全部日期', () => { selectedDay = ''; redrawContent(); }, { kind: 'add' }));
  panel.append(grid);
  return panel;
}

function workRow(item, kind, today) {
  const completed = item.completedAt != null;
  const open = detailOpen.has(item.id);
  const card = element('article', completed ? 'work-row done' : 'work-row');
  const label = button(item.title, () => {
    if (open) detailOpen.delete(item.id);
    else { detailOpen.add(item.id); expandedSection = 'work-' + item.id; }
    redrawContent();
  }, { kind: 'work-label' });
  label.setAttribute('aria-expanded', String(open));
  const date = element('time', '', item.dueDate.slice(5));
  date.dateTime = item.dueDate;
  date.title = item.dueDate;
  const actions = element('div', 'row-actions',
    icon('◆', item.pinned ? '取消置顶工作' : '置顶工作', () => send({ type: 'work-pin', id: item.id }), Boolean(item.pinned)),
    icon('✎', '编辑工作 ' + item.title, () => openWork(item)),
    dragHandle('work', item.id, () => card)
  );
  card.append(element('div', 'work-top',
    icon(completed ? '✓' : '○', completed ? '恢复待完成' : '标为完成',
      () => send({ type: 'work-complete', id: item.id })),
    label, date, actions
  ));
  if (open) {
    const detail = expansion('work-detail', 'work-' + item.id);
    detail.append(item.notes || button('添加概要', () => openWork(item)));
    card.append(detail);
  }
  dropTarget(card, source => {
    const other = state.work.find(work => work.id === source.id);
    return source.kind === 'work' && other && source.id !== item.id
      && projectId(other) === projectId(item) && sectionFor(other, today) === kind;
  }, gap, (source, after) => send({ type: 'work-order', id: source.id, target: item.id, after }));
  return card;
}

function projectPanel(project, expanded, showHeader) {
  const id = project.id;
  const panel = element('section', 'project');
  if (showHeader) {
    const heading = button(project.name, () => {
      if (expanded) projectOpen.delete(id);
      else { projectOpen.add(id); expandedSection = 'project-' + id; }
      redrawContent();
    }, { kind: 'project-heading' });
    heading.setAttribute('aria-expanded', String(expanded));
    heading.prepend(element('span', '', expanded ? '⌄' : '›'), colored(element('span', 'dot'), projectColors[project.color]));
    const top = element('div', 'project-top', heading);
    if (id !== noProject) {
      top.append(icon('✎', '编辑项目 ' + project.name, () => openProject(project)), dragHandle('project', id, () => panel));
    }
    dropTarget(top, item => item.kind === 'work' && projectId(state.work.find(work => work.id === item.id)) !== id,
      into, item => send({ type: 'work-move', id: item.id, projectID: id === noProject ? undefined : id }));
    if (id !== noProject) {
      dropTarget(panel, item => item.kind === 'project' && item.id !== id, gap,
        (item, after) => send({ type: 'project-order', id: item.id, target: id, after }));
    }
    panel.append(top);
  }
  const today = dayKey();
  const items = state.work.filter(item => projectId(item) === id && (!selectedDay || item.dueDate === selectedDay));
  if (expanded) {
    const body = expansion('project-body', 'project-' + id);
    for (const kind of sections) {
      const list = orderedWork(items.filter(item => sectionFor(item, today) === kind), kind);
      if (list.length === 0) continue;
      body.append(element('div', 'group', element('h3', '', groupTitles[kind]),
        ...list.map(item => workRow(item, kind, today))));
    }
    body.append(button(id === noProject ? '＋ 新增工作' : '＋ 添加工作', () => openWork(undefined, id), { kind: 'add' }));
    panel.append(body);
  }
  return panel;
}

function workScreen() {
  const list = element('div');
  const unassigned = { id: noProject, name: '未归类', color: 'gray' };
  if (filter === all) {
    for (const project of [...state.projects, unassigned]) {
      list.append(projectPanel(project, projectOpen.has(project.id), true));
    }
    list.append(button('＋ 添加项目', () => openProject(), { kind: 'add' }));
  } else {
    list.append(projectPanel(filterProject(filter) || unassigned, true, false));
  }
  const calendar = calendarPanel();
  dropTarget(list, item => item.kind === 'calendar', into, () => send({ type: 'calendar-position' }));
  return state.prefs.calendarBelow ? [filterBar(), list, calendar] : [filterBar(), calendar, list];
}

function openNote(note) {
  const noteKinds = [['text', '文字便签'], ['todo', '待办事项']];
  const themes = Object.keys(noteColors).map(color => [color, colorTitles[color]]);
  edit(note ? '编辑便签' : '新增便签', [
    labeled('类型', dropdown('kind', noteKinds, note?.kind || 'text')),
    labeled('颜色', dropdown('theme', themes, note?.theme || 'lemon')),
    labeled('内容', textInput('text', note?.text, 'area'))
  ], values => ({ type: 'note-save', id: note?.id, ...values }));
}

function toggleNoteLine(note, index, done) {
  const lines = note.text.split('\n');
  lines[index] = lines[index].replace(/^(?:-\s*)?\[[ xX]\]\s*/, '').trim();
  lines[index] = (done ? '- [ ] ' : '- [x] ') + lines[index];
  send({ type: 'note-save', id: note.id, kind: note.kind, theme: note.theme, text: lines.join('\n') });
}

function styledText(text) {
  const line = element('p');
  for (const part of text.split(/(\*\*[^*]+\*\*|\x60[^\x60]+\x60)/)) {
    if (part.startsWith('**') && part.endsWith('**')) line.append(element('strong', '', part.slice(2, -2)));
    else if (part.startsWith('\x60') && part.endsWith('\x60')) line.append(element('code', '', part.slice(1, -1)));
    else line.append(part);
  }
  return line;
}

function noteCard(note) {
  const title = note.text.split('\n').find(line => line.trim())?.replace(/^#+\s+/, '')
    || (note.kind === 'todo' ? '待办事项' : '文字便签');
  const card = colored(element('article', 'note'), noteColors[note.theme], '--note');
  const header = element('div', 'note-top', element('strong', '', title));
  if (note.archivedAt) {
    header.append(button('恢复便签', () => send({ type: 'note-restore', id: note.id }, () => { screen = 'notes'; })));
  } else {
    header.append(icon(note.collapsed ? '⌄' : '⌃', note.collapsed ? '展开便签' : '折叠便签',
      () => send({ type: 'note-collapse', id: note.id })));
    if (!noteID) header.append(icon('↗', '打开桌面浮窗', () => api.openNote(note.id)));
    header.append(
      icon('◆', note.pinned ? '取消置顶便签' : '置顶便签', () => send({ type: 'note-pin', id: note.id }), Boolean(note.pinned)),
      icon('✎', '编辑便签', () => openNote(note)),
      icon('×', '归档便签', () => send({ type: 'note-close', id: note.id }))
    );
  }
  card.append(header);
  if (note.collapsed && !note.archivedAt) return card;
  const body = element('div', 'note-text');
  if (note.archivedAt) body.append(element('p', '', new Date(note.archivedAt).toLocaleDateString('zh-CN')));
  note.text.split('\n').forEach((line, index) => {
    const task = line.match(/^(?:-\s*)?\[([ xX])\]\s*(.*)$/);
    if ((task || note.kind === 'todo') && line.trim() && !note.archivedAt) {
      const done = task?.[1].toLowerCase() === 'x';
      body.append(element('div', '', button((done ? '✓ ' : '○ ') + (task ? task[2] : line),
        () => toggleNoteLine(note, index, done), { kind: 'note-check', pressed: done })));
    } else if (/^#+\s/.test(line)) {
      body.append(element('h3', '', line.replace(/^#+\s+/, '')));
    } else {
      body.append(styledText(line));
    }
  });
  card.append(body);
  return card;
}

function notesScreen() {
  if (noteID) {
    const note = state.notes.find(item => item.id === noteID && !item.archivedAt);
    return note ? [noteCard(note)] : [];
  }
  const archive = screen === 'history';
  const cards = state.notes.filter(note => Boolean(note.archivedAt) === archive);
  if (archive) cards.sort((a, b) => b.archivedAt.localeCompare(a.archivedAt));
  const nodes = cards.map(noteCard);
  if (archive && !cards.length) nodes.push(element('p', 'empty', '暂无历史便签'));
  if (!archive) nodes.push(button('＋ 新增便签', () => openNote(), { kind: 'add' }));
  return nodes;
}

function expansion(className, key) {
  if (expandedSection !== key) return element('div', className);
  expandedSection = undefined;
  return element('div', className + ' expanding');
}

function redrawContent() {
  if (!state) return;
  const top = content.scrollTop;
  const errors = Object.values(state.errors).map(message => element('p', 'error', message));
  content.replaceChildren(...errors, ...(screen === 'work' && !noteID ? workScreen() : notesScreen()));
  content.scrollTop = top;
}

function renderToolbar() {
  const title = element('h1', '', noteID ? '桌面便签' : state.prefs.title);
  title.title = noteID ? '桌面便签' : '双击修改标题';
  if (!noteID) title.addEventListener('dblclick', openTitle);
  const actions = element('div', 'toolbar-actions');
  if (!noteID && !compact && screen !== 'history') {
    actions.append(icon('＋', screen === 'work' ? '新增工作' : '新增便签',
      () => screen === 'work' ? openWork() : openNote()));
  }
  if (!noteID) {
    actions.append(
      icon(state.prefs.theme === 'dark' ? '☀' : '☾', '切换深浅外观', () => send({ type: 'theme' })),
      icon('◆', state.prefs.pinned ? '取消窗口置顶' : '窗口置顶', () => send({ type: 'pin-window' }), state.prefs.pinned),
      icon(compact ? '⌄' : '⌃', compact ? '展开时间轴' : '收拢时间轴', async () => {
        compact = await api.windowAction('compact');
        render();
      })
    );
  }
  actions.append(icon('−', '最小化', () => api.windowAction('minimize')),
    icon('×', noteID ? '关闭浮窗' : '收进系统托盘', () => api.windowAction('close'), undefined, 'close'));
  toolbar.replaceChildren(title, element('div', 'drag-space'), actions);
}

function renderFooter() {
  const current = release?.status;
  const messages = {
    checking: '正在检查更新…', current: '已是最新版本', failed: '暂时无法完成更新',
    preparing: '正在准备更新' + (release?.percent == null ? '…' : ' ' + release.percent + '%'),
    ready: 'cosmNotes ' + release?.version + ' 更新已就绪', installing: '正在重启并更新…'
  };
  const version = element('span', '', messages[current] || ('cosmNotes v' + (release?.installed || '')));
  const actions = element('div', 'row-actions');
  if (current === 'ready') {
    actions.append(button('重启并更新', async () => {
      try { await api.installUpdate(); } catch (error) { toast(error.message); }
    }, { kind: 'primary' }));
  } else if (current !== 'installing' && current !== 'preparing') {
    const check = button('检查更新…', async () => {
      try { await api.checkUpdate(); } catch (error) { toast(error.message); }
    });
    check.disabled = current === 'checking';
    actions.append(check);
  }
  footer.replaceChildren(version, actions);
}

function render() {
  if (!state) return;
  document.documentElement.dataset.theme = state.prefs.theme;
  document.body.classList.toggle('compact', compact);
  document.body.classList.toggle('floating', Boolean(noteID));
  renderToolbar();
  tabs.replaceChildren(...[['work', '工作'], ['notes', '便签'], ['history', '历史']].map(([value, label]) =>
    button(label, () => { screen = value; render(); }, { pressed: screen === value })));
  redrawContent();
  renderFooter();
}

api.onState(next => { state = next; render(); });
api.onUpdate(next => {
  release = next;
  renderFooter();
  if (next.notify && !noteID) toast('cosmNotes ' + next.version + ' 更新已就绪');
});
api.onNavigate(section => { compact = false; screen = section; render(); });
api.read().then(data => {
  state = data;
  release ||= data.update;
  render();
  if (release.notify && !noteID) toast('cosmNotes ' + release.version + ' 更新已就绪');
}).catch(error => toast(error.message));
