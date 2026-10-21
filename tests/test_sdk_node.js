/**
 * Unit tests for loggdin / Agent Sentinel Node.js SDK (sdk/sentinel.js)
 */

const assert = require('assert');
const http = require('http');
const fs = require('fs');
const path = require('path');
const os = require('os');

const { askPermission, guard, getSentinelPort } = require('../sdk/sentinel');

async function runTests() {
  console.log('Running Node.js SDK Tests...\n');

  let lastPayload = null;
  let responseAllowed = true;

  // Start mock HTTP server on ephemeral port
  const server = http.createServer((req, res) => {
    let body = '';
    req.on('data', chunk => { body += chunk; });
    req.on('end', () => {
      if (body) {
        lastPayload = JSON.parse(body);
      }
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ allowed: responseAllowed }));
    });
  });

  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const testPort = server.address().port;

  try {
    // 1. Port Discovery Test
    process.env.LOGGDIN_PORT = testPort.toString();
    assert.strictEqual(getSentinelPort(), testPort, 'getSentinelPort should match LOGGDIN_PORT');
    delete process.env.LOGGDIN_PORT;

    process.env.SENTINEL_PORT = testPort.toString();
    assert.strictEqual(getSentinelPort(), testPort, 'getSentinelPort should match SENTINEL_PORT');
    console.log('✓ test_port_discovery passed');

    // 2. Ask Permission Approved
    responseAllowed = true;
    const allowed = await askPermission({
      command: 'npm test',
      title: 'Run test suite',
      risk: 'low',
      requestedBy: 'Node Test Runner'
    });
    assert.strictEqual(allowed, true, 'askPermission should resolve to true');
    assert.strictEqual(lastPayload.command, 'npm test');
    assert.strictEqual(lastPayload.requestedBy, 'Node Test Runner');
    assert.strictEqual(lastPayload.risk, 'low');
    console.log('✓ test_ask_permission_approved passed');

    // 3. Ask Permission Denied
    responseAllowed = false;
    const denied = await askPermission({
      command: 'rm -rf node_modules',
      risk: 'high'
    });
    assert.strictEqual(denied, false, 'askPermission should resolve to false');
    assert.strictEqual(lastPayload.command, 'rm -rf node_modules');
    console.log('✓ test_ask_permission_denied passed');

    // 4. Guard Approved Execution
    responseAllowed = true;
    const proc = await guard("node -e 'console.log(\"node-sdk-ok\")'", { requestedBy: 'Tester' });
    assert.ok(proc.stdout.includes('node-sdk-ok'), 'guard stdout should include output');
    console.log('✓ test_guard_execution_success passed');

    // 5. Guard Denied Rejection
    responseAllowed = false;
    let threw = false;
    try {
      await guard('echo "should not run"', { requestedBy: 'Tester' });
    } catch (err) {
      threw = true;
      assert.ok(err.message.includes('Permission denied'), 'Error should indicate permission denied');
    }
    assert.strictEqual(threw, true, 'guard should reject with error when denied');
    console.log('✓ test_guard_execution_denied passed');

    // 6. Guard Approved Array Execution (execFile)
    responseAllowed = true;
    const arrayProc = await guard(['node', '-e', 'console.log("node-array-exec-ok")'], { requestedBy: 'Tester' });
    assert.ok(arrayProc.stdout.includes('node-array-exec-ok'), 'array command should execute with execFile');
    console.log('✓ test_guard_execution_array_args passed');

    console.log('\nAll 6 Node.js SDK tests passed successfully!');
  } finally {
    delete process.env.SENTINEL_PORT;
    server.close();
  }
}

runTests().catch(err => {
  console.error('\n❌ Node.js SDK Tests Failed:', err);
  process.exit(1);
});
