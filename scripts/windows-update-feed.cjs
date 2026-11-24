'use strict';

const { createPrivateKey, sign } = require('node:crypto');
const { readFileSync, statSync, writeFileSync } = require('node:fs');
const { basename, join } = require('node:path');
const { installerName, manifestBytes, sha512File, verifyManifest } = require('../windows/src/updates.cjs');

async function run(file, version, output, rawPublicKey, rawSeed) {
  const name = installerName(version);
  if (basename(file) !== name) throw new Error('The installer filename must match its version.');
  const seed = Buffer.from(rawSeed || '', 'base64');
  if (seed.length !== 32) throw new Error('The release signing key is missing or invalid.');
  const prefix = Buffer.from('302e020100300506032b657004220420', 'hex');
  const key = createPrivateKey({ format: 'der', type: 'pkcs8', key: Buffer.concat([prefix, seed]) });
  const sha512 = await sha512File(file);
  const size = statSync(file).size;
  const manifest = { version, path: name, sha512, size };
  const info = {
    version, files: [{ url: name, sha512, size }], path: name, sha512,
    signature: sign(null, manifestBytes(manifest), key).toString('base64')
  };
  verifyManifest(info, rawPublicKey);
  // JSON is valid YAML; electron-updater loads this file as the stable Windows channel.
  writeFileSync(output, JSON.stringify(info, null, 2) + '\n');
}

if (require.main === module) {
  const [file, version, output, keyPath = join(__dirname, '..', 'Resources', 'UpdatePublicKey')] = process.argv.slice(2);
  run(file, version, output, readFileSync(keyPath, 'utf8').trim(), process.env.COSMNOTES_UPDATE_SIGNING_KEY)
    .catch(error => { console.error(error.message); process.exitCode = 1; });
}

module.exports = run;
