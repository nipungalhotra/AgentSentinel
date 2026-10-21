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

function getSentinelToken() {
  try {
    const p1 = path.join(os.homedir(), '.loggdin', 'token');
    if (fs.existsSync(p1)) return fs.readFileSync(p1, 'utf8').trim();
    const p2 = path.join(os.homedir(), 'Library', 'Application Support', 'AgentSentinel', 'token');
    if (fs.existsSync(p2)) return fs.readFileSync(p2, 'utf8').trim();
  } catch {}
  return '';
}

function requestSentinel(payload) {
  return new Promise((resolve, reject) => {
    const postData = JSON.stringify(payload);
    const token = getSentinelToken();
    const headers = {
      'Content-Type': 'application/json',
      'Content-Length': Buffer.byteLength(postData)
    };
    if (token) {
      headers['X-Loggdin-Token'] = token;
    }
    const options = {
      hostname: '127.0.0.1',
      port: getSentinelPort(),
      path: '/ask',
      method: 'POST',
      headers: headers,
      timeout: 60000 // 60s timeout matching popup max duration
    };

    const req = http.request(options, (res) => {
      let data = '';
      res.on('data', (chunk) => { data += chunk; });
      res.on('end', () => {
        try {
          const parsed = JSON.parse(data);
          resolve(parsed);
        } catch (e) {
          resolve({ allowed: false, decision: 'error', error: data });
        }
      });
    });

    req.on('error', (err) => {
      // If Sentinel is not running, attempt to launch it
      if (err.code === 'ECONNREFUSED') {
        try {
          execSync('open -g -j /Applications/Loggdin.app 2>/dev/null || open -g -j /Applications/AgentSentinel.app 2>/dev/null || open /Applications/Loggdin.app 2>/dev/null || true');
          // Wait 1.5s and retry once
          setTimeout(() => {
            const retryReq = http.request(options, (res2) => {
              let d = '';
              res2.on('data', (c) => { d += c; });
              res2.on('end', () => {
                try { resolve(JSON.parse(d)); } catch { resolve({ allowed: false, decision: 'deny' }); }
              });
            });
            retryReq.on('error', () => resolve({ allowed: false, error: 'AgentSentinel daemon is offline. Launch Agent Sentinel.' }));
            retryReq.write(postData);
            retryReq.end();
          }, 1500);
          return;
        } catch {
          // ignore
        }
      }
      resolve({ allowed: false, error: `Sentinel connection error: ${err.message}` });
    });

    req.write(postData);
    req.end();
  });
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
          version: '1.2.0'
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
