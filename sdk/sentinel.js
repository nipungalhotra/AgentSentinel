/**
 * Agent Sentinel Node.js SDK
 * Universal Liquid Glass Permission Gate for AI Agents (ChatGPT, Codex, LangChain, Custom Agents)
 */

const http = require('http');
const { exec } = require('child_process');

const fs = require('fs');
const path = require('path');
const os = require('os');

function stateDir() {
  // Per-OS loggdin state dir (matches bin/loggdin.py and the Mac app).
  if (process.env.LOGGDIN_HOME) return process.env.LOGGDIN_HOME;
  const home = os.homedir();
  if (process.platform === 'darwin') return path.join(home, 'Library', 'Application Support', 'AgentSentinel');
  if (process.platform === 'win32') return path.join(process.env.APPDATA || path.join(home, 'AppData', 'Roaming'), 'Loggdin');
  return path.join(process.env.XDG_CONFIG_HOME || path.join(home, '.config'), 'loggdin');
}

function readStateFile(name) {
  const files = process.env.LOGGDIN_HOME ? [] : [path.join(os.homedir(), '.loggdin', name)];
  files.push(path.join(stateDir(), name));
  for (const f of files) {
    try { if (fs.existsSync(f)) return fs.readFileSync(f, 'utf8').trim(); } catch {}
  }
  return '';
}

function verifyDaemon(port, token) {
  // Resolves 'ok' when the server on `port` proves it knows `token` (HMAC challenge on /status),
  // 'down' when nothing answers, 'mismatch' otherwise. The token is only sent after 'ok', so
  // another local user squatting the port cannot collect it.
  const crypto = require('crypto');
  const challenge = crypto.randomBytes(16).toString('hex');
  return new Promise((resolve) => {
    const req = http.get({ hostname: '127.0.0.1', port, path: `/status?challenge=${challenge}`, timeout: 2000 }, (res) => {
      let d = '';
      res.on('data', (c) => { d += c; });
      res.on('end', () => {
        try {
          const proof = String(JSON.parse(d).proof || '');
          const expected = crypto.createHmac('sha256', token).update('loggdin-status:' + challenge).digest('hex');
          const a = Buffer.from(proof), b = Buffer.from(expected);
          resolve(a.length === b.length && crypto.timingSafeEqual(a, b) ? 'ok' : 'mismatch');
        } catch { resolve('mismatch'); }
      });
    });
    req.on('timeout', () => { req.destroy(); resolve('down'); });
    req.on('error', () => resolve('down'));
  });
}

function launchDaemon() {
  // Start loggdin if it is not running: Loggdin.app on macOS, loggdin.py elsewhere.
  const { spawn } = require('child_process');
  try {
    if (process.platform === 'darwin' && fs.existsSync('/Applications/Loggdin.app')) {
      spawn('open', ['-g', '-j', '/Applications/Loggdin.app'], { detached: true, stdio: 'ignore' }).unref();
      return;
    }
    const script = path.join(stateDir(), 'loggdin.py');
    if (fs.existsSync(script)) {
      const py = process.platform === 'win32' ? 'pythonw' : 'python3';
      spawn(py, [script, 'daemon'], { detached: true, stdio: 'ignore', windowsHide: true }).unref();
    }
  } catch {}
}

function getSentinelPort() {
  if (process.env.LOGGDIN_PORT) return parseInt(process.env.LOGGDIN_PORT, 10);
  if (process.env.SENTINEL_PORT) return parseInt(process.env.SENTINEL_PORT, 10);
  const v = parseInt(readStateFile('port'), 10);
  return Number.isFinite(v) && v > 0 ? v : 9191;
}

function askPermission({
  command,
  title,
  subtitle,
  risk = 'medium',
  requestedBy = 'Antigravity App',
  directory = process.cwd(),
  modifiesFiles = 'Unknown',
  tool = 'Antigravity',
  symbol = 'sparkles',
  forcePrompt = true
}) {
  return new Promise((resolve) => {
    const postData = JSON.stringify({
      command,
      title,
      subtitle: subtitle || `${requestedBy} • ${tool}`,
      risk,
      requestedBy,
      directory,
      modifiesFiles,
      tool,
      symbol,
      forcePrompt
    });

    const token = readStateFile('token');
    const send = () => {

    const headers = {
      'Content-Type': 'application/json',
      'Content-Length': Buffer.byteLength(postData)
    };
    if (token) headers['X-Loggdin-Token'] = token;

    const req = http.request({
      hostname: '127.0.0.1',
      port: getSentinelPort(),
      path: '/ask',
      method: 'POST',
      headers: headers,
      timeout: 60000
    }, (res) => {
      let data = '';
      res.on('data', chunk => { data += chunk; });
      res.on('end', () => {
        try {
          const json = JSON.parse(data);
          resolve(!!json.allowed);
        } catch {
          resolve(false);
        }
      });
    });

    req.on('error', () => resolve(false));
    req.write(postData);
    req.end();
    };
    if (!token) return send();
    verifyDaemon(getSentinelPort(), token).then((state) => (state === 'ok' ? send() : resolve(false)));
  });
}

function guard(command, options = {}) {
  const {
    requestedBy = 'Agent',
    directory = process.cwd(),
    ...rest
  } = options;

  const cmdStr = Array.isArray(command) ? command.join(' ') : command;

  return askPermission({
    command: cmdStr,
    requestedBy,
    directory,
    ...rest
  }).then((allowed) => {
    if (!allowed) {
      throw new Error(`Sentinel: Permission denied by user for command '${cmdStr}'`);
    }
    return new Promise((resolve, reject) => {
      const { execFile } = require('child_process');
      if (Array.isArray(command)) {
        const [file, ...args] = command;
        execFile(file, args, { cwd: directory }, (error, stdout, stderr) => {
          if (error) {
            reject(Object.assign(error, { stdout, stderr }));
          } else {
            resolve({ stdout, stderr });
          }
        });
      } else {
        exec(command, { cwd: directory }, (error, stdout, stderr) => {
          if (error) {
            reject(Object.assign(error, { stdout, stderr }));
          } else {
            resolve({ stdout, stderr });
          }
        });
      }
    });
  });
}

function isDaemonRunning() {
  return new Promise((resolve) => {
    const req = http.request({
      hostname: '127.0.0.1',
      port: getSentinelPort(),
      path: '/status',
      method: 'GET',
      timeout: 1500
    }, (res) => {
      resolve(res.statusCode === 200);
    });
    req.on('error', () => resolve(false));
    req.on('timeout', () => { req.destroy(); resolve(false); });
    req.end();
  });
}

function getDaemonStatus() {
  return new Promise((resolve) => {
    const req = http.request({
      hostname: '127.0.0.1',
      port: getSentinelPort(),
      path: '/status',
      method: 'GET',
      timeout: 2000
    }, (res) => {
      let data = '';
      res.on('data', chunk => { data += chunk; });
      res.on('end', () => {
        try {
          resolve(JSON.parse(data));
        } catch {
          resolve({ status: 'offline', raw: data });
        }
      });
    });
    req.on('error', (err) => resolve({ status: 'offline', error: err.message }));
    req.on('timeout', () => { req.destroy(); resolve({ status: 'offline', error: 'timeout' }); });
    req.end();
  });
}

module.exports = { askPermission, guard, getSentinelPort, isDaemonRunning, getDaemonStatus };
