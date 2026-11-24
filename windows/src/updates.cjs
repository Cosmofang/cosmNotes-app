'use strict';

const { createHash, createPublicKey, verify } = require('node:crypto');
const { createReadStream } = require('node:fs');
const publicKeyPrefix = Buffer.from('302a300506032b6570032100', 'hex');

function installerName(version) {
  if (typeof version !== 'string' || !/^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/.test(version)) {
    throw new Error('无法识别更新版本。');
  }
  return 'cosmNotes-v' + version + '-Windows-x64-Setup.exe';
}

function manifestBytes({ version, path, sha512, size }) {
  return Buffer.from(JSON.stringify(['cosmNotes-Windows-x64-v1', version, path, sha512, size]));
}

function base64OfLength(value, length) {
  if (typeof value !== 'string') return null;
  const decoded = Buffer.from(value, 'base64');
  return decoded.length === length && decoded.toString('base64') === value ? decoded : null;
}

function verifyManifest(info, rawPublicKey) {
  const name = installerName(info?.version);
  const file = info.files?.[0];
  const signature = base64OfLength(info.signature, 64);
  const publicKey = base64OfLength(rawPublicKey, 32);
  if (!publicKey || !signature || !Array.isArray(info.files) || info.files.length !== 1
      || file?.url !== name || info.path !== name || file.sha512 !== info.sha512
      || !base64OfLength(file.sha512, 64) || !Number.isSafeInteger(file.size) || file.size <= 0
      || info.packages != null) {
    throw new Error('Windows 更新信息无效。');
  }
  const manifest = { version: info.version, path: name, sha512: file.sha512, size: file.size };
  const key = createPublicKey({ format: 'der', type: 'spki', key: Buffer.concat([publicKeyPrefix, publicKey]) });
  if (!verify(null, manifestBytes(manifest), key, signature)) throw new Error('Windows 更新签名校验失败。');
  return manifest;
}

async function sha512File(file) {
  const hash = createHash('sha512');
  for await (const chunk of createReadStream(file)) hash.update(chunk);
  return hash.digest('base64');
}

module.exports = { installerName, manifestBytes, verifyManifest, sha512File };
