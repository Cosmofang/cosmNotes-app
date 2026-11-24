'use strict';

const repository = 'Cosmofang/cosmNotes-app';
const latestURL = 'https://api.github.com/repos/' + repository + '/releases/latest';

function version(value) {
  if (typeof value !== 'string' || !/^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/.test(value)) return null;
  const components = value.split('.').map(Number);
  return components.every(Number.isSafeInteger) ? components : null;
}

function windowsUpdate(release, installed) {
  if (release.draft || release.prerelease) return null;
  const tag = release.tag_name;
  const remote = typeof tag === 'string' && tag.startsWith('v') ? version(tag.slice(1)) : null;
  const current = version(installed);
  if (!remote || !current) throw new Error('无法识别版本号。');

  const difference = remote.map((part, index) => part - current[index]).find(part => part !== 0) || 0;
  if (difference <= 0) return null;

  const name = 'cosmNotes-' + tag + '-Windows-x64-Setup.exe';
  if (!release.assets?.some(asset => asset.name === name && asset.state === 'uploaded')) return null;
  return {
    version: tag,
    url: 'https://github.com/' + repository + '/releases/download/' + tag + '/' + name
  };
}

module.exports = { latestURL, windowsUpdate };
