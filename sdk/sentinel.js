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

    const req = http.request({
      hostname: '127.0.0.1',
      port: SENTINEL_PORT,
      path: '/ask',
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(postData)
      },
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
