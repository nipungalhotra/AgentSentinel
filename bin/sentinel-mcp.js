#!/usr/bin/env node

/**
 * Universal Agent Sentinel MCP (Model Context Protocol) Server
 * Compatible with Claude Code, Cowork, Antigravity IDE, Cursor, Windsurf & ChatGPT
 */

const http = require('http');
const readline = require('readline');
const { exec, execSync } = require('child_process');
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

function getSentinelToken() {
  return readStateFile('token');
}

function requestSentinel(payload) {
  const postData = JSON.stringify(payload);
  const post = (token) => new Promise((resolve) => {
    const headers = { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(postData) };
    if (token) headers['X-Loggdin-Token'] = token;
    const req = http.request({
      hostname: '127.0.0.1', port: getSentinelPort(), path: '/ask', method: 'POST', headers,
      timeout: 120000
    }, (res) => {
      let data = '';
      res.on('data', (chunk) => { data += chunk; });
      res.on('end', () => {
        try { resolve(JSON.parse(data)); } catch { resolve({ allowed: false, decision: 'error', error: data }); }
      });
    });
    req.on('timeout', () => { req.destroy(); resolve({ allowed: false, decision: 'timeout' }); });
    req.on('error', (err) => resolve({ allowed: false, error: `loggdin connection error: ${err.message}` }));
    req.write(postData);
    req.end();
  });

  const attempt = async (retry) => {
    const token = getSentinelToken();
    if (token) {
      const state = await verifyDaemon(getSentinelPort(), token);
      if (state === 'down' && retry) {
        launchDaemon();   // start loggdin, then try once more
        await new Promise((r) => setTimeout(r, 1500));
        return attempt(false);
      }
      if (state !== 'ok') {
        return { allowed: false, error: state === 'down'
          ? 'loggdin daemon is offline. Start Loggdin (macOS) or run `loggdin start`.'
          : 'The process on the loggdin port failed its identity check; refusing to send the token.' };
      }
    }
    return post(token);
  };
  return attempt(true);
}

const TOOLS = [
  {
    name: 'sentinel_request_permission',
    description: 'Requests user authorization via the macOS Liquid Glass popup anchored beneath the MacBook camera notch. Use before executing sensitive terminal commands, file modifications, or external actions. Compatible with Claude Code, Cowork, Antigravity, ChatGPT, Codex, and Cursor.',
    inputSchema: {
      type: 'object',
      properties: {
        command: {
          type: 'string',
          description: 'The shell command, file path, or action to be authorized.'
        },
        title: {
          type: 'string',
          description: 'Optional question title (e.g. "Run this command?", "Modify sensitive file?", "Delete database?")'
        },
        risk: {
          type: 'string',
          enum: ['low', 'medium', 'high'],
          description: 'Risk level. High risk actions prompt hold-to-confirm.'
        },
        requested_by: {
          type: 'string',
          description: 'Name of the calling AI agent (e.g. "Claude Code", "Cowork", "Antigravity", "ChatGPT", "Codex")'
        },
        directory: {
          type: 'string',
          description: 'Active working directory.'
        },
        modifies_files: {
          type: 'string',
          description: 'Impact description on local files (e.g. "Yes", "No", "Yes, permanently").'
        },
        tool: {
          type: 'string',
          description: 'Tool name being executed (e.g. "Bash", "FileEdit", "BrowserAction").'
        }
      },
      required: ['command']
    }
  },
  {
    name: 'sentinel_guard_command',
    description: 'Requests authorization via the Liquid Glass popup and executes the command only if approved by the user. Returns command stdout, stderr, and exit code.',
    inputSchema: {
      type: 'object',
      properties: {
        command: {
          type: 'string',
          description: 'Shell command to execute after permission.'
        },
        requested_by: {
          type: 'string',
          description: 'Calling AI agent name.'
        },
        directory: {
          type: 'string',
          description: 'Working directory for the command execution.'
        }
      },
      required: ['command']
    }
  }
];

// MCP JSON-RPC Stdio Handler
const rl = readline.createInterface({
  input: process.stdin,
  output: process.stdout,
  terminal: false
});

function sendResponse(id, result, error = null) {
  const resp = { jsonrpc: '2.0', id };
  if (error) {
    resp.error = error;
  } else {
    resp.result = result;
  }
  process.stdout.write(JSON.stringify(resp) + '\n');
}

rl.on('line', async (line) => {
  if (!line.trim()) return;
  try {
    const msg = JSON.parse(line);
    const { id, method, params } = msg;

    if (method === 'initialize') {
      sendResponse(id, {
        protocolVersion: '2024-11-05',
        capabilities: { tools: {} },
        serverInfo: {
          name: 'agent-sentinel',
          version: '1.2.1'
        }
      });
      return;
    }

    if (method === 'notifications/initialized') {
      // Client confirmed initialization
      return;
    }

    if (method === 'tools/list') {
      sendResponse(id, { tools: TOOLS });
      return;
    }

    if (method === 'tools/call') {
      const { name, arguments: args = {} } = params;

      if (name === 'sentinel_request_permission') {
        const payload = {
          command: args.command,
          title: args.title,
          risk: args.risk,
          requestedBy: args.requested_by || 'AI Agent',
          directory: args.directory || process.cwd(),
          modifiesFiles: args.modifies_files || (args.command.includes('rm') || args.command.includes('write') ? 'Yes' : 'No'),
          tool: args.tool || 'MCP Tool'
        };

        const result = await requestSentinel(payload);

        if (result.allowed) {
          sendResponse(id, {
            content: [
              {
                type: 'text',
                text: JSON.stringify({
                  allowed: true,
                  decision: result.decision,
                  scope: result.scope || 'once',
                  summary: `User approved (${result.scope || 'once'}) via Sentinel Liquid Glass popup.`
                })
              }
            ],
            isError: false
          });
        } else {
          sendResponse(id, {
            content: [
              {
                type: 'text',
                text: `❌ Permission denied by user via Sentinel popup for: "${args.command}"`
              }
            ],
            isError: true
          });
        }
        return;
      }

      if (name === 'sentinel_guard_command') {
        const payload = {
          command: args.command,
          title: 'Run this command?',
          risk: args.command.includes('rm -rf') ? 'high' : 'medium',
          requestedBy: args.requested_by || 'AI Agent',
          directory: args.directory || process.cwd(),
          modifiesFiles: 'Yes'
        };

        const result = await requestSentinel(payload);

        if (!result.allowed) {
          sendResponse(id, {
            content: [
              {
                type: 'text',
                text: `❌ Execution cancelled: Permission denied by user via Sentinel.`
              }
            ],
            isError: true
          });
          return;
        }

        // Execute command safely
        const cwd = args.directory || process.cwd();
        exec(args.command, { cwd, maxBuffer: 10 * 1024 * 1024 }, (err, stdout, stderr) => {
          sendResponse(id, {
            content: [
              {
                type: 'text',
                text: JSON.stringify({
                  status: err ? 'failed' : 'success',
                  exitCode: err ? err.code : 0,
                  stdout: stdout || '',
                  stderr: stderr || ''
                }, null, 2)
              }
            ],
            isError: !!err
          });
        });
        return;
      }

      sendResponse(id, null, { code: -32601, message: `Tool not found: ${name}` });
      return;
    }

    // Default response for unhandled ping / methods
    if (id !== undefined) {
      sendResponse(id, {});
    }
  } catch (err) {
    // Malformed JSON
  }
});
