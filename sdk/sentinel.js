/**
 * Agent Sentinel Node.js SDK
 * Universal Liquid Glass Permission Gate for AI Agents (ChatGPT, Codex, LangChain, Custom Agents)
 */

const http = require('http');
const { exec } = require('child_process');

const fs = require('fs');
const path = require('path');
const os = require('os');

function getSentinelPort() {
  if (process.env.LOGGDIN_PORT) return parseInt(process.env.LOGGDIN_PORT, 10);
  if (process.env.SENTINEL_PORT) return parseInt(process.env.SENTINEL_PORT, 10);
  try {
    const p1 = path.join(os.homedir(), '.loggdin', 'port');
    if (fs.existsSync(p1)) return parseInt(fs.readFileSync(p1, 'utf8').trim(), 10);
    const p2 = path.join(os.homedir(), 'Library', 'Application Support', 'AgentSentinel', 'port');
    if (fs.existsSync(p2)) return parseInt(fs.readFileSync(p2, 'utf8').trim(), 10);
  } catch {}
  return 9191;
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

    const fs = require('fs');
    const path = require('path');
    const os = require('os');
    let token = '';
    try {
      const p1 = path.join(os.homedir(), '.loggdin', 'token');
      const p2 = path.join(os.homedir(), 'Library', 'Application Support', 'AgentSentinel', 'token');
      if (fs.existsSync(p1)) token = fs.readFileSync(p1, 'utf8').trim();
      else if (fs.existsSync(p2)) token = fs.readFileSync(p2, 'utf8').trim();
    } catch {}

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
