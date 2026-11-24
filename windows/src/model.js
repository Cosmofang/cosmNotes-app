(function () {
  'use strict';

  const sections = ['pinned', 'overdue', 'today', 'upcoming', 'completed'];
  const projectColors = {
    blue: '#5a8dec', teal: '#3ca8aa', green: '#5aa670', orange: '#dc8c50',
    red: '#e06a6d', pink: '#d26da7', purple: '#9c7ad7', gray: '#8594a7'
  };
  const noteColors = {
    lemon: '#d6ae57', peach: '#d8917a', mint: '#6eaf95', sky: '#729edf', lilac: '#a587d5'
  };

  function dayKey(date = new Date()) {
    return [date.getFullYear(), String(date.getMonth() + 1).padStart(2, '0'),
      String(date.getDate()).padStart(2, '0')].join('-');
  }

  function validDay(value) {
    if (typeof value !== 'string' || !/^[0-9]{4}-[0-9]{2}-[0-9]{2}$/.test(value) || value.startsWith('0000')) return false;
    const date = new Date(value + 'T00:00:00Z');
    return !Number.isNaN(date.getTime()) && date.toISOString().slice(0, 10) === value;
  }

  function sectionFor(item, today) {
    if (item.completedAt != null) return 'completed';
    if (item.pinned) return 'pinned';
    if (item.dueDate < today) return 'overdue';
    return item.dueDate === today ? 'today' : 'upcoming';
  }

  function orderedWork(items, section) {
    const priority = [...items].sort((a, b) => {
      if (section === 'completed' && a.completedAt !== b.completedAt) return b.completedAt - a.completedAt;
      return a.dueDate.localeCompare(b.dueDate) || a.createdAt - b.createdAt || a.id.localeCompare(b.id);
    });
    const manual = priority.filter(item => item.manualOrder?.section === section)
      .sort((a, b) => a.manualOrder.position - b.manualOrder.position);
    let index = 0;
    return priority.map(item => item.manualOrder?.section === section ? manual[index++] : item);
  }

  function moved(items, id, target, after) {
    const source = items.find(item => item.id === id);
    if (!source || id === target) return items;
    const next = items.filter(item => item.id !== id);
    const destination = next.findIndex(item => item.id === target);
    if (destination === -1) return items;
    next.splice(destination + (after ? 1 : 0), 0, source);
    return next;
  }

  const model = { sections, projectColors, noteColors, dayKey, validDay, sectionFor, orderedWork, moved };
  if (typeof module === 'object') module.exports = model;
  else globalThis.cosmModel = model;
})();
