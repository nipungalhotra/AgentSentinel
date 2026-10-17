# 📱 Apple Shortcuts Integration for loggdin

loggdin integrates natively with **Apple Shortcuts** on macOS, iOS, iPadOS, and watchOS.

Because loggdin enforces a **zero-trust, loopback-only architecture** (`127.0.0.1`), it never opens unauthenticated network ports to local Wi-Fi or the internet. Instead, it leverages Apple's encrypted iCloud and SSH ecosystems so you can review and approve permissions from your Mac, iPhone, or Apple Watch with total security.

---

## ⚡ Quick Actions Supported

| Action | URL Scheme | CLI Command |
|---|---|---|
| **Allow Once** | `open "loggdin://allow?scope=once"` | `loggdin allow once` |
| **Allow 10 Minutes** | `open "loggdin://allow?scope=10m"` | `loggdin allow 10m` |
| **Always Allow** | `open "loggdin://allow?scope=always"` | `loggdin allow always` |
| **Deny** | `open "loggdin://deny"` | `loggdin deny` |
| **Check Pending** | N/A | `loggdin pending` |
| **Set Sound** | `open "loggdin://sound?name=Glass"` | `loggdin sound Glass` |

---

## 💻 1. Creating Shortcuts on macOS

You can create shortcuts in the macOS **Shortcuts.app** (`/Applications/Shortcuts.app`):

### Shortcut A: "Approve 10 Minutes"
1. Open **Shortcuts** on your Mac.
2. Click **+** (New Shortcut).
3. Name it **"Approve 10m"** (or whatever you prefer).
4. Add the action **"Run Shell Script"**:
   ```bash
   /Applications/Loggdin.app/Contents/MacOS/loggdin allow 10m
   ```
   *(Or alternatively, add **"Open URLs"** with URL: `loggdin://allow?scope=10m`)*.
5. In the Shortcut settings (right sidebar):
   - Check **"Use as Quick Action"** (adds it to Finder & Services menu).
   - Check **"Pin in Menu Bar"** (gives you a 1-click button in your Mac's menu bar!).

### Shortcut B: "Deny Action"
1. In **Shortcuts**, click **+**.
2. Name it **"Deny loggdin"**.
3. Add action **"Run Shell Script"**:
   ```bash
   /Applications/Loggdin.app/Contents/MacOS/loggdin deny
   ```
   *(Or add **"Open URLs"** with URL: `loggdin://deny`)*.

---

## 📱 2. Syncing & Controlling from iPhone / iPad / Apple Watch

Because macOS Shortcuts automatically syncs via **iCloud**, your Mac shortcuts are visible on your iOS devices. To approve actions from your iPhone or Apple Watch without exposing insecure HTTP ports:

### Secure Remote Approval via Native Apple SSH:
Apple Shortcuts has a built-in **"Run Script Over SSH"** action that uses standard encrypted SSH (port 22).

1. On your Mac: Enable **Remote Login**:
   - Go to **System Settings > General > Sharing > Remote Login** and toggle it **ON**.
2. On your iPhone:
   - Open **Shortcuts** app.
   - Create a shortcut called **"Approve loggdin (iPhone)"**.
   - Add the action **"Run Script Over SSH"**:
     - **Host**: Your Mac's local hostname (e.g. `your-macbook.local` or private Tailscale/VPN IP)
     - **Port**: `22`
     - **User**: Your Mac username (e.g. `nipun`)
     - **Authentication**: Password or SSH Key
     - **Script**:
       ```bash
       PATH="$PATH:/usr/local/bin:$HOME/.local/bin" loggdin allow 10m
       ```
3. Add the Shortcut to your **iPhone Home Screen**, **Lock Screen Widget**, or **Action Button** (iPhone 15 Pro / 16).
4. You can now also say:
   - *"Hey Siri, Approve loggdin"*
   - *"Hey Siri, Deny loggdin"*
   and Siri will execute it directly on your Mac!

---

## 🔒 Security Advantage

Unlike web servers that listen on all network interfaces (`0.0.0.0`) and can be discovered by LAN sniffers or malicious Wi-Fi users:
1. **Loopback Only (`127.0.0.1`)**: loggdin's HTTP listener rejects all incoming connections from external network interfaces at the OS kernel level.
2. **Apple Ecosystem Encryption**: Remote actions from iPhone or Apple Watch pass strictly through Apple's ed25519-encrypted SSH or iCloud synchronization.
