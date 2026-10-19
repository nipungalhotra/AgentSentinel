/**
 * Agent Sentinel Node.js SDK
 * Universal Liquid Glass Permission Gate for AI Agents (ChatGPT, Codex, LangChain, Custom Agents)
 */

const http = require('http');
const { exec } = require('child_process');

const SENTINEL_PORT = process.env.SENTINEL_PORT || 9191;

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
      port: SENTINEL_PORT,
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

module.exports = { askPermission };
