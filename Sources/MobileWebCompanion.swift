import Foundation
import Network

@MainActor
enum MobileWebCompanion {

    /// Helper to find the Mac's primary local Wi-Fi IP address (en0 / en1)
    static func getLocalIPAddress() -> String {
        var address = "127.0.0.1"
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&ifaddr) == 0 {
            var ptr = ifaddr
            while ptr != nil {
                let interface = ptr!.pointee
                let addrFamily = interface.ifa_addr.pointee.sa_family
                if addrFamily == UInt8(AF_INET) {
                    let name = String(cString: interface.ifa_name)
                    if name == "en0" || name == "en1" {
                        var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                        getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                                    &hostname, socklen_t(hostname.count),
                                    nil, socklen_t(0), NI_NUMERICHOST)
                        address = String(cString: hostname)
                        break
                    }
                }
                ptr = interface.ifa_next
            }
            freeifaddrs(ifaddr)
        }
        return address
    }

    static var html: String {
        let ip = getLocalIPAddress()
        return """
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no, viewport-fit=cover">
  <title>loggdin • Phone Sentinel</title>
  <meta name="apple-mobile-web-app-capable" content="yes">
  <meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
  <meta name="theme-color" content="#090a0f">
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;600&family=Plus+Jakarta+Sans:wght@400;500;600;700;800&display=swap" rel="stylesheet">
  <style>
    * {
      box-sizing: border-box;
      margin: 0;
      padding: 0;
      -webkit-tap-highlight-color: transparent;
    }
    body {
      background-color: #090a0f;
      background-image: 
        radial-gradient(at 0% 0%, rgba(59, 130, 246, 0.15) 0px, transparent 50%),
        radial-gradient(at 100% 100%, rgba(139, 92, 246, 0.15) 0px, transparent 50%);
      color: #f8fafc;
      font-family: 'Plus Jakarta Sans', -apple-system, BlinkMacSystemFont, sans-serif;
      min-height: 100vh;
      display: flex;
      flex-direction: column;
      align-items: center;
      padding: env(safe-area-inset-top, 20px) 16px env(safe-area-inset-bottom, 24px) 16px;
      overflow-x: hidden;
    }
    .container {
      width: 100%;
      max-width: 440px;
      display: flex;
      flex-direction: column;
      gap: 16px;
    }
    header {
      display: flex;
      align-items: center;
      justify-content: space-between;
      padding: 12px 16px;
      background: rgba(255, 255, 255, 0.04);
      border: 1px solid rgba(255, 255, 255, 0.08);
      border-radius: 20px;
      backdrop-filter: blur(20px);
      -webkit-backdrop-filter: blur(20px);
    }
    .brand {
      display: flex;
      align-items: center;
      gap: 10px;
    }
    .brand-icon {
      width: 32px;
      height: 32px;
      border-radius: 9px;
      background: linear-gradient(135deg, #3B82F6, #8B5CF6);
      display: flex;
      align-items: center;
      justify-content: center;
      font-weight: 800;
      font-size: 15px;
      box-shadow: 0 4px 12px rgba(59, 130, 246, 0.3);
    }
    .brand-text h1 {
      font-size: 15px;
      font-weight: 700;
      letter-spacing: -0.3px;
    }
    .brand-text p {
      font-size: 10px;
      color: #94a3b8;
      font-family: 'JetBrains Mono', monospace;
    }
    .live-badge {
      display: flex;
      align-items: center;
      gap: 6px;
      padding: 4px 10px;
      border-radius: 20px;
      background: rgba(34, 197, 94, 0.12);
      border: 1px solid rgba(34, 197, 94, 0.3);
      font-size: 11px;
      font-weight: 600;
      color: #4ade80;
    }
    .pulse-dot {
      width: 6px;
      height: 6px;
      border-radius: 50%;
      background: #22c55e;
      box-shadow: 0 0 8px #22c55e;
      animation: pulse 2s infinite;
    }
    @keyframes pulse {
      0%, 100% { opacity: 1; transform: scale(1); }
      50% { opacity: 0.4; transform: scale(0.85); }
    }
    .card {
      background: rgba(255, 255, 255, 0.05);
      border: 1px solid rgba(255, 255, 255, 0.1);
      border-radius: 28px;
      padding: 24px 20px;
      backdrop-filter: blur(28px);
      -webkit-backdrop-filter: blur(28px);
      box-shadow: 0 20px 40px -15px rgba(0, 0, 0, 0.5);
      transition: all 0.3s ease;
      position: relative;
      overflow: hidden;
    }
    .card.high-risk {
      border-color: rgba(239, 68, 68, 0.4);
      background: radial-gradient(circle at top right, rgba(239, 68, 68, 0.15), transparent 70%), rgba(255, 255, 255, 0.05);
      box-shadow: 0 20px 50px -15px rgba(239, 68, 68, 0.3);
    }
    .face-wrapper {
      display: flex;
      justify-content: center;
      margin-bottom: 16px;
    }
    .squircle-face {
      width: 72px;
      height: 72px;
      border-radius: 22px;
      background: linear-gradient(135deg, #1e293b, #0f172a);
      border: 1.5px solid rgba(255, 255, 255, 0.15);
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      gap: 8px;
      box-shadow: 0 8px 24px rgba(0, 0, 0, 0.4);
      position: relative;
      transition: transform 0.2s cubic-bezier(0.34, 1.56, 0.64, 1);
    }
    .eyes {
      display: flex;
      gap: 16px;
    }
    .eye {
      width: 7px;
      height: 10px;
      background: #f8fafc;
      border-radius: 4px;
      transition: all 0.2s ease;
    }
    .mouth {
      width: 14px;
      height: 4px;
      background: #94a3b8;
      border-radius: 3px;
      transition: all 0.2s ease;
    }
    .squircle-face.worried .eye {
      height: 8px;
      transform: translateY(1px);
    }
    .squircle-face.worried .mouth {
      width: 8px;
      height: 8px;
      border-radius: 50%;
      border: 2px solid #ef4444;
      background: transparent;
    }
    .squircle-face.happy .mouth {
      height: 6px;
      border-radius: 0 0 10px 10px;
      background: #22c55e;
    }
    .squircle-face.sad .mouth {
      height: 4px;
      border-radius: 10px 10px 0 0;
      background: #ef4444;
    }
    .agent-row {
      display: flex;
      align-items: center;
      justify-content: space-between;
      margin-bottom: 12px;
    }
    .agent-pill {
      display: inline-flex;
      align-items: center;
      gap: 6px;
      padding: 5px 12px;
      border-radius: 12px;
      font-size: 12px;
      font-weight: 700;
      background: rgba(139, 92, 246, 0.2);
      color: #c4b5fd;
      border: 1px solid rgba(139, 92, 246, 0.35);
    }
    .agent-pill.claude { background: rgba(139, 92, 246, 0.2); color: #c4b5fd; border-color: rgba(139, 92, 246, 0.35); }
    .agent-pill.antigravity { background: rgba(59, 130, 246, 0.2); color: #93c5fd; border-color: rgba(59, 130, 246, 0.35); }
    .agent-pill.cursor { background: rgba(16, 185, 129, 0.2); color: #6ee7b7; border-color: rgba(16, 185, 129, 0.35); }
    .agent-pill.codex { background: rgba(6, 182, 212, 0.2); color: #67e8f9; border-color: rgba(6, 182, 212, 0.35); }
    .agent-pill.cowork { background: rgba(245, 158, 11, 0.2); color: #fcd34d; border-color: rgba(245, 158, 11, 0.35); }
    .risk-tag {
      font-size: 11px;
      font-weight: 700;
      text-transform: uppercase;
      letter-spacing: 0.5px;
      padding: 4px 8px;
      border-radius: 8px;
    }
    .risk-high { background: rgba(239, 68, 68, 0.2); color: #fca5a5; border: 1px solid rgba(239, 68, 68, 0.35); }
    .risk-med { background: rgba(245, 158, 11, 0.2); color: #fde68a; border: 1px solid rgba(245, 158, 11, 0.35); }
    .risk-low { background: rgba(59, 130, 246, 0.2); color: #bfdbfe; border: 1px solid rgba(59, 130, 246, 0.35); }

    .title {
      font-size: 18px;
      font-weight: 700;
      margin-bottom: 6px;
      line-height: 1.3;
    }
    .subtitle {
      font-size: 13px;
      color: #94a3b8;
      margin-bottom: 14px;
    }
    .command-box {
      background: #030712;
      border: 1px solid rgba(255, 255, 255, 0.1);
      border-radius: 14px;
      padding: 14px;
      font-family: 'JetBrains Mono', monospace;
      font-size: 12.5px;
      line-height: 1.45;
      color: #38bdf8;
      word-break: break-all;
      position: relative;
      margin-bottom: 14px;
    }
    .copy-btn {
      position: absolute;
      top: 8px;
      right: 8px;
      background: rgba(255, 255, 255, 0.1);
      border: none;
      color: #cbd5e1;
      padding: 4px 8px;
      border-radius: 6px;
      font-size: 10px;
      font-weight: 600;
      cursor: pointer;
    }
    .warning-box {
      background: rgba(239, 68, 68, 0.1);
      border: 1px solid rgba(239, 68, 68, 0.3);
      border-radius: 12px;
      padding: 10px 12px;
      font-size: 12px;
      color: #fca5a5;
      margin-bottom: 16px;
      display: flex;
      align-items: center;
      gap: 8px;
    }
    .meta-details {
      display: flex;
      flex-direction: column;
      gap: 6px;
      font-size: 11.5px;
      color: #94a3b8;
      margin-bottom: 20px;
      background: rgba(255, 255, 255, 0.02);
      border-radius: 10px;
      padding: 10px 12px;
    }
    .meta-row {
      display: flex;
      gap: 6px;
    }
    .meta-label {
      color: #64748b;
      font-weight: 600;
      min-width: 60px;
    }
    .meta-val {
      color: #cbd5e1;
      word-break: break-all;
    }

    /* Action Buttons */
    .actions-grid {
      display: flex;
      flex-direction: column;
      gap: 10px;
    }
    .btn {
      width: 100%;
      padding: 16px;
      border-radius: 16px;
      border: none;
      font-family: inherit;
      font-size: 15px;
      font-weight: 700;
      cursor: pointer;
      display: flex;
      align-items: center;
      justify-content: center;
      gap: 8px;
      transition: transform 0.15s ease, opacity 0.15s ease, box-shadow 0.15s ease;
    }
    .btn:active {
      transform: scale(0.97);
    }
    .btn-allow {
      background: linear-gradient(135deg, #10b981, #059669);
      color: #ffffff;
      box-shadow: 0 8px 20px -6px rgba(16, 185, 129, 0.5);
    }
    .btn-ten-min {
      background: linear-gradient(135deg, #8b5cf6, #6366f1);
      color: #ffffff;
      box-shadow: 0 8px 20px -6px rgba(139, 92, 246, 0.5);
    }
    .btn-always {
      background: rgba(255, 255, 255, 0.08);
      border: 1px solid rgba(255, 255, 255, 0.15);
      color: #e2e8f0;
    }
    .btn-deny {
      background: rgba(239, 68, 68, 0.12);
      border: 1px solid rgba(239, 68, 68, 0.25);
      color: #fca5a5;
      padding: 13px;
      font-size: 14px;
    }

    /* Idle View */
    .idle-view {
      text-align: center;
      padding: 40px 16px;
    }
    .idle-icon {
      width: 76px;
      height: 76px;
      border-radius: 24px;
      background: linear-gradient(135deg, rgba(59, 130, 246, 0.2), rgba(139, 92, 246, 0.2));
      border: 1.5px solid rgba(255, 255, 255, 0.15);
      margin: 0 auto 20px auto;
      display: flex;
      align-items: center;
      justify-content: center;
      font-size: 34px;
      box-shadow: 0 10px 30px rgba(0, 0, 0, 0.4);
    }
    .idle-title {
      font-size: 19px;
      font-weight: 700;
      margin-bottom: 8px;
    }
    .idle-desc {
      font-size: 13px;
      color: #94a3b8;
      line-height: 1.5;
      margin-bottom: 24px;
    }
    .stats-grid {
      display: grid;
      grid-template-columns: 1fr 1fr;
      gap: 12px;
      margin-bottom: 24px;
    }
    .stat-card {
      background: rgba(255, 255, 255, 0.03);
      border: 1px solid rgba(255, 255, 255, 0.06);
      border-radius: 16px;
      padding: 14px 10px;
    }
    .stat-val {
      font-size: 20px;
      font-weight: 800;
      color: #38bdf8;
    }
    .stat-lbl {
      font-size: 11px;
      color: #64748b;
      margin-top: 2px;
    }
    .btn-test {
      background: rgba(255, 255, 255, 0.06);
      border: 1px solid rgba(255, 255, 255, 0.12);
      color: #cbd5e1;
      padding: 12px 18px;
      border-radius: 12px;
      font-size: 13px;
      font-weight: 600;
      cursor: pointer;
      display: inline-flex;
      align-items: center;
      gap: 6px;
    }
    .toast {
      position: fixed;
      bottom: 24px;
      left: 50%;
      transform: translateX(-50%) translateY(100px);
      background: #0f172a;
      border: 1px solid rgba(255, 255, 255, 0.2);
      padding: 12px 20px;
      border-radius: 14px;
      font-size: 13px;
      font-weight: 600;
      color: #f8fafc;
      box-shadow: 0 10px 30px rgba(0, 0, 0, 0.6);
      transition: transform 0.3s cubic-bezier(0.34, 1.56, 0.64, 1);
      z-index: 100;
      display: flex;
      align-items: center;
      gap: 8px;
    }
    .toast.show {
      transform: translateX(-50%) translateY(0);
    }
  </style>
</head>
<body>
  <div class="container">
    <header>
      <div class="brand">
        <div class="brand-icon">🛡️</div>
        <div class="brand-text">
          <h1>loggdin</h1>
          <p>\(ip):9191</p>
        </div>
      </div>
      <div class="live-badge">
        <div class="pulse-dot"></div>
        <span>COMPANION</span>
      </div>
    </header>

    <div id="content">
      <!-- Dynamically filled by JavaScript -->
    </div>
  </div>

  <div id="toast" class="toast"></div>

  <script>
    let currentRequestId = null;
    let isSubmitting = false;

    function showToast(msg, icon = '✓') {
      const t = document.getElementById('toast');
      t.innerHTML = `<span>${icon}</span> <span>${msg}</span>`;
      t.classList.add('show');
      setTimeout(() => t.classList.remove('show'), 2600);
    }

    function copyCmd(cmd) {
      navigator.clipboard.writeText(cmd).then(() => {
        showToast('Command copied to clipboard!');
      });
    }

    async function pollPending() {
      if (isSubmitting) return;
      try {
        const res = await fetch('/pending');
        if (!res.ok) return;
        const data = await res.json();
        
        if (data.hasPending && data.request) {
          if (currentRequestId !== data.request.id) {
            currentRequestId = data.request.id;
            renderPrompt(data.request);
            if (navigator.vibrate) {
              navigator.vibrate([100, 50, 100]);
            }
          }
        } else {
          if (currentRequestId !== null || !document.getElementById('idle-screen')) {
            currentRequestId = null;
            renderIdle(data.activeGrants || 0, data.savedRules || 0);
          }
        }
      } catch (err) {
        console.error("Poll error:", err);
      }
    }

    function renderPrompt(req) {
      const riskClass = req.risk === 'high' ? 'high-risk' : '';
      const tagClass = req.risk === 'high' ? 'risk-high' : (req.risk === 'medium' ? 'risk-med' : 'risk-low');
      const agentClass = (req.requestedBy || 'agent').toLowerCase().replace(/[^a-z]/g, '');

      let warningsHtml = '';
      if (req.secretWarnings && req.secretWarnings.length > 0) {
        warningsHtml = `
          <div class="warning-box">
            <span>⚠️</span>
            <span>${req.secretWarnings.join('<br>')}</span>
          </div>
        `;
      }

      const faceMood = req.risk === 'high' ? 'worried' : '';

      document.getElementById('content').innerHTML = `
        <div class="card ${riskClass}">
          <div class="face-wrapper">
            <div class="squircle-face ${faceMood}" id="face">
              <div class="eyes">
                <div class="eye"></div>
                <div class="eye"></div>
              </div>
              <div class="mouth"></div>
            </div>
          </div>

          <div class="agent-row">
            <div class="agent-pill ${agentClass}">
              <span>⚡</span> ${escapeHtml(req.requestedBy || 'AI Agent')}
            </div>
            <div class="risk-tag ${tagClass}">
              ${escapeHtml(req.risk || 'NORMAL')} RISK
            </div>
          </div>

          <div class="title">${escapeHtml(req.title || 'Permission Request')}</div>
          <div class="subtitle">${escapeHtml(req.subtitle || 'Waiting for authorization')}</div>

          <div class="command-box">
            <button class="copy-btn" onclick="copyCmd('${escapeJs(req.command || '')}')">COPY</button>
            ${escapeHtml(req.command || 'No command specified')}
          </div>

          ${warningsHtml}

          <div class="meta-details">
            <div class="meta-row">
              <span class="meta-label">Directory:</span>
              <span class="meta-val">${escapeHtml(req.directory || '~')}</span>
            </div>
            ${req.modifiesFiles && req.modifiesFiles !== 'No' ? `
            <div class="meta-row">
              <span class="meta-label">Modifies:</span>
              <span class="meta-val">${escapeHtml(req.modifiesFiles)}</span>
            </div>` : ''}
          </div>

          <div class="actions-grid">
            <button class="btn btn-allow" onclick="sendDecision('${req.id}', 'allow', 'once')">
              <span>🟢</span> Allow Once
            </button>
            <button class="btn btn-ten-min" onclick="sendDecision('${req.id}', 'allow', 'tenMinutes')">
              <span>⏱️</span> Allow for 10 Min
            </button>
            <button class="btn btn-always" onclick="sendDecision('${req.id}', 'allow', 'always')">
              <span>⚡</span> Always Allow
            </button>
            <button class="btn btn-deny" onclick="sendDecision('${req.id}', 'deny', 'once')">
              <span>🔴</span> Deny Action
            </button>
          </div>
        </div>
      `;
    }

    function renderIdle(grants, rules) {
      document.getElementById('content').innerHTML = `
        <div class="card idle-view" id="idle-screen">
          <div class="idle-icon">🛡️</div>
          <div class="idle-title">Shield Guard Active</div>
          <div class="idle-desc">
            Waiting for requests from Claude Code, Antigravity IDE, Cursor, Codex, or your terminal.
          </div>

          <div class="stats-grid">
            <div class="stat-card">
              <div class="stat-val">${grants}</div>
              <div class="stat-lbl">Active 10m Grants</div>
            </div>
            <div class="stat-card">
              <div class="stat-val">${rules}</div>
              <div class="stat-lbl">Saved Rules</div>
            </div>
          </div>

          <button class="btn-test" onclick="triggerTestPrompt()">
            <span>🧪</span> Send Test Prompt to Phone
          </button>
        </div>
      `;
    }

    async function sendDecision(reqId, action, scope) {
      if (isSubmitting) return;
      isSubmitting = true;

      const face = document.getElementById('face');
      if (face) {
        face.className = 'squircle-face ' + (action === 'allow' ? 'happy' : 'sad');
      }

      showToast(action === 'allow' ? `Approved (${scope})!` : 'Action Denied', action === 'allow' ? '🟢' : '🔴');

      try {
        const res = await fetch('/mobile/decision', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ id: reqId, action: action, scope: scope })
        });
        const result = await res.json();
        console.log("Decision response:", result);
      } catch (err) {
        console.error("Error sending decision:", err);
      } finally {
        setTimeout(() => {
          isSubmitting = false;
          currentRequestId = null;
          pollPending();
        }, 600);
      }
    }

    async function triggerTestPrompt() {
      showToast('Firing test prompt...', '⚡');
      try {
        await fetch('/mobile/test', { method: 'POST' });
        setTimeout(pollPending, 300);
      } catch (err) {
        console.error("Test prompt error:", err);
      }
    }

    function escapeHtml(str) {
      if (!str) return '';
      return String(str)
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#039;');
    }

    function escapeJs(str) {
      if (!str) return '';
      return String(str).replace(/'/g, "\\\\'").replace(/"/g, '\\"');
    }

    // Initial render & polling interval
    renderIdle(0, 4);
    pollPending();
    setInterval(pollPending, 1200);
  </script>
</body>
</html>
"""
    }
}
