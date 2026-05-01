import { createHash } from 'node:crypto';
import { createReadStream, closeSync, openSync, readSync, writeSync } from 'node:fs';
import { readFile, stat, writeFile } from 'node:fs/promises';
import { spawn } from 'node:child_process';

const dmgPath = 'Habits.dmg';
const statePath = '.habits-release.json';
const workerPath = 'worker.js';
const indexPath = 'index.html';
const bucketName = 'habits-downloads';

function sha256File(path) {
  return new Promise((resolve, reject) => {
    const hash = createHash('sha256');
    const stream = createReadStream(path);
    stream.on('error', reject);
    stream.on('data', (chunk) => hash.update(chunk));
    stream.on('end', () => resolve(hash.digest('hex')));
  });
}

async function readJson(path) {
  try {
    return JSON.parse(await readFile(path, 'utf8'));
  } catch (error) {
    if (error.code === 'ENOENT') return {};
    throw error;
  }
}

function extractCurrentVersion(workerSource) {
  return workerSource.match(/const DOWNLOAD_VERSION = '([^']+)';/)?.[1]
    ?? workerSource.match(/const DOWNLOAD_KEY = 'Habits-([^']+)\.dmg';/)?.[1]
    ?? '';
}

function validateVersion(version) {
  if (!/^[0-9A-Za-z][0-9A-Za-z._-]*$/.test(version)) {
    throw new Error('Version must start with a letter or number and only contain letters, numbers, dots, underscores, or hyphens.');
  }
}

async function promptVersion(defaultVersion) {
  let fd;
  try {
    fd = openSync('/dev/tty', 'r+');
    writeSync(fd, `Habits version [${defaultVersion}]: `);

    const chunks = [];
    const buffer = Buffer.alloc(1);
    while (readSync(fd, buffer, 0, 1) === 1) {
      if (buffer[0] === 10 || buffer[0] === 13) break;
      chunks.push(buffer[0]);
    }

    const answer = Buffer.from(chunks).toString('utf8').trim();
    return answer || defaultVersion;
  } catch {
    return defaultVersion;
  } finally {
    if (fd !== undefined) closeSync(fd);
  }
}

function replaceOrThrow(source, pattern, replacement, file) {
  if (!pattern.test(source)) throw new Error(`Could not find expected release value in ${file}.`);
  return source.replace(pattern, replacement);
}

async function run(command, args) {
  await new Promise((resolve, reject) => {
    const child = spawn(command, args, { stdio: 'inherit' });
    child.on('error', reject);
    child.on('exit', (code, signal) => {
      if (code === 0) resolve();
      else reject(new Error(`${command} ${args.join(' ')} failed${signal ? ` with signal ${signal}` : ` with exit code ${code}`}.`));
    });
  });
}

async function runWrangler(args) {
  try {
    await run('wrangler', args);
  } catch (error) {
    if (error.code !== 'ENOENT') throw error;
    await run('npx', ['wrangler', ...args]);
  }
}

async function main() {
  const [workerSource, indexSource, state] = await Promise.all([
    readFile(workerPath, 'utf8'),
    readFile(indexPath, 'utf8'),
    readJson(statePath),
    stat(dmgPath),
  ]);

  const defaultVersion = state.version || extractCurrentVersion(workerSource);
  if (!defaultVersion) throw new Error('No previous Habits version found.');

  const version = await promptVersion(defaultVersion);
  validateVersion(version);

  const key = `Habits-${version}.dmg`;
  const sha256 = await sha256File(dmgPath);

  const nextWorker = replaceOrThrow(
    replaceOrThrow(
      workerSource,
      /const DOWNLOAD_VERSION = '[^']+';/,
      `const DOWNLOAD_VERSION = '${version}';`,
      workerPath,
    ),
    /const DOWNLOAD_SHA256 = '[0-9a-f]{64}';/,
    `const DOWNLOAD_SHA256 = '${sha256}';`,
    workerPath,
  );

  const nextIndex = replaceOrThrow(
    indexSource,
    /<span class="btn-sub">Version [^<]+<\/span>/,
    `<span class="btn-sub">Version ${version}</span>`,
    indexPath,
  );

  await Promise.all([
    writeFile(workerPath, nextWorker),
    writeFile(indexPath, nextIndex),
    writeFile(statePath, `${JSON.stringify({ version }, null, 2)}\n`),
  ]);

  console.log(`Uploading ${dmgPath} as ${bucketName}/${key}`);
  console.log(`SHA-256 ${sha256}`);

  await runWrangler([
    'r2',
    'object',
    'put',
    `${bucketName}/${key}`,
    '--file',
    dmgPath,
    '--remote',
    '--content-type',
    'application/x-apple-diskimage',
    '--cache-control',
    'public, max-age=31536000, immutable',
  ]);
}

main().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
