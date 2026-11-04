# 🧩 loggdin Agent SDKs (Python & Node.js)

Universal Liquid Glass permission sentinel SDKs for AI agent pipelines, autonomous coding loops, and developer tooling. Compatible with **Claude Code**, **Google Antigravity**, **OpenAI Codex / ChatGPT**, **LangChain**, **CrewAI**, and custom agent frameworks.

---

## 🚀 Quickstart

### Python SDK (`sdk/sentinel.py` / `sdk/loggdin.py`)

No external pip dependencies required. Built with standard Python library (`urllib`, `subprocess`, `json`):

```python
from sentinel import ask_permission, guard, is_daemon_running

# Check if loggdin is active
if not is_daemon_running():
    print("⚠️ loggdin daemon is offline. Starting application...")

# 1. Ask authorization before a critical action
approved = ask_permission(
    command="docker compose down -v && docker compose up -d",
    title="Rebuild Production Containers?",
    subtitle="Antigravity Deployer • High Risk",
    risk="high",
    requested_by="Autonomous Agent",
    tool="Docker"
)

if approved:
    print("User approved via notch card / Touch ID! Proceeding...")
else:
    print("Action denied or timed out.")

# 2. Guard execution automatically (raises PermissionError if denied)
# Note: Pass as a list to avoid shell injection vulnerabilities!
result = guard(["git", "push", "origin", "main", "--force"], requested_by="Release Agent")
print(result.stdout)
```

---

### Node.js SDK (`sdk/sentinel.js`)

Zero npm dependencies. Uses native Node.js `http` and `child_process`:

```javascript
const { askPermission, guard, isDaemonRunning } = require('./sentinel');

async function main() {
  const online = await isDaemonRunning();
  console.log(`loggdin daemon online: ${online}`);

  // 1. Interactive Permission Request
  const allowed = await askPermission({
    command: 'npm publish --access public',
    title: 'Publish Package to NPM Registry?',
    subtitle: 'Release Pipeline • CI/CD',
    risk: 'high',
    requestedBy: 'Claude Code Agent',
    tool: 'npm'
  });

  if (allowed) {
    console.log('✅ User authorized package publication.');
  }

  // 2. Safe Guarded Execution using execFile argument array
  try {
    const { stdout } = await guard(['git', 'reset', '--hard', 'HEAD~1'], {
      requestedBy: 'Codex Agent'
    });
    console.log('Output:', stdout);
  } catch (err) {
    console.error('Execution blocked:', err.message);
  }
}

main();
```

---

## 📚 API Reference

### Python API

#### `ask_permission(...) -> bool`
Presents the Liquid Glass permission card centered beneath the MacBook camera notch.

```python
def ask_permission(
    command: str,
    title: str = None,
    subtitle: str = None,
    risk: str = "medium",          # "low" | "medium" | "high" | "critical"
    requested_by: str = "Agent",   # Tool or Agent name shown on card
    directory: str = None,         # Execution working directory
    modifies_files: str = "None",  # Summary of files affected
    tool: str = "CLI",             # Underlying tool (git, docker, npm, etc.)
    symbol: str = "sparkles",      # SF Symbol icon name
    force_prompt: bool = True      # Bypass cached approvals if critical
) -> bool
```
- **Returns**: `True` if user clicked **Allow** or authenticated with **Touch ID**; `False` if denied, dismissed, or timed out (60s).

#### `guard(...) -> subprocess.CompletedProcess`
Requests authorization and executes the command only if approved.
```python
def guard(
    command: Union[str, List[str]], # String command or safe argument list
    requested_by: str = "Agent",
    directory: str = None,
    shell: bool = None,             # False (safe), True (shell), or None (auto-detect)
    **kwargs                        # Passed directly to subprocess.run
) -> subprocess.CompletedProcess
```
- **Raises**: `PermissionError` if denied or timed out.
- **Security**: When passed as a `list` or when `shell=False`, arguments are executed directly without `/bin/sh` interpolation to prevent command injection.

#### `is_daemon_running() -> bool`
Returns `True` if the local loggdin daemon is listening and healthy on `127.0.0.1`.

#### `get_daemon_status() -> dict`
Returns server diagnostics:
```python
{
    "status": "running",
    "port": 9191,
    "socket": "/Users/.../sentinel.sock",
    "version": "1.2.0"
}
```

---

### Node.js API

#### `askPermission(options) -> Promise<boolean>`
Options:
- `command` *(string, required)*: The command or action to evaluate.
- `title` *(string)*: Primary headline on the permission card.
- `subtitle` *(string)*: Secondary context subtitle.
- `risk` *(string)*: `'low'` | `'medium'` | `'high'` | `'critical'`.
- `requestedBy` *(string)*: Calling agent name.
- `directory` *(string)*: Working directory (defaults to `process.cwd()`).
- `modifiesFiles` *(string)*: File impact summary.
- `tool` *(string)*: Tool category (`git`, `docker`, `npm`, etc.).
- `symbol` *(string)*: SF Symbol icon identifier.
- `forcePrompt` *(boolean)*: Set `true` to require prompt regardless of cached grants.

#### `guard(command, options) -> Promise<{ stdout: string, stderr: string }>`
Evaluates authorization and executes the command.
- If `command` is an `Array` (`['git', 'push', 'origin', 'main']`), it executes safely using `child_process.execFile`.
- If `command` is a `string`, it executes via `child_process.exec`.
- Rejects with `Error("Sentinel: Permission denied by user...")` if denied.

#### `isDaemonRunning() -> Promise<boolean>`
Resolves to `true` if the daemon is online.

#### `getDaemonStatus() -> Promise<Object>`
Resolves to daemon status JSON.

---

## 💡 Common Real-World Use Cases

### 1. LangChain / CrewAI Custom Tool Protection
Wrap high-impact agent tools with loggdin authorization:

```python
from langchain.tools import tool
from sentinel import ask_permission, guard

@tool
def drop_database_collection(collection_name: str) -> str:
    """Drops a database collection after securing operator authorization."""
    approved = ask_permission(
        command=f"db.{collection_name}.drop()",
        title=f"Drop Database Collection: {collection_name}?",
        subtitle="LangChain Agent • Production Database",
        risk="critical",
        requested_by="Database Cleanup Agent"
    )
    if not approved:
        return f"Action cancelled: Operator denied deletion of {collection_name}."
    
    # Proceed with actual database call
    return f"Collection {collection_name} dropped successfully."
```

### 2. Workspace Boundary / Jail Enforcement
Prevent autonomous agents from modifying files outside the project root:

```python
import os
from sentinel import ask_permission

WORKSPACE_DIR = os.path.abspath("./my_project")

def safe_write_file(target_path: str, content: str):
    abs_path = os.path.abspath(target_path)
    
    # Check if target is outside workspace
    if not abs_path.startswith(WORKSPACE_DIR):
        approved = ask_permission(
            command=f"write outside workspace: {abs_path}",
            title="Suspicious Out-of-Workspace File Write",
            subtitle=f"Attempting to write to {abs_path}",
            risk="high",
            requested_by="Code Generator Agent",
            modifies_files=abs_path
        )
        if not approved:
            raise PermissionError(f"Access denied to path: {abs_path}")
            
    with open(abs_path, "w") as f:
        f.write(content)
```

### 3. Safe Argument Array Execution (Injection Defense)
```python
from sentinel import guard

# ❌ Risky: shell string interpolation
user_branch = "main; rm -rf /"
# guard(f"git checkout {user_branch}") # UNSAFE!

# ✅ Safe: List-based arguments execute with shell=False
guard(["git", "checkout", user_branch], requested_by="Git Assistant")
```

---

## ⚙️ Environment Variables & Overrides

| Variable | Default | Description |
| :--- | :--- | :--- |
| `LOGGDIN_PORT` | `9191` | Custom local IPC HTTP port override. |
| `SENTINEL_PORT` | `9191` | Secondary port override alias. |
| `SENTINEL_URL` | `http://127.0.0.1:9191/ask` | Full target endpoint URL override. |
| `~/.loggdin/token` | Generated at startup | Bearer token verified in `X-Loggdin-Token` header. |
| `~/.loggdin/port` | Dynamically published | Auto-discovery file inspected by SDKs. |
