/* loggdin site: live notch-card demo + waitlist form. No dependencies. */
(() => {
  "use strict";

  /* ---------------- Waitlist ----------------
     Set data-endpoint on the form (or WAITLIST_ENDPOINT below) to a form backend that accepts
     a POST with an "email" field, e.g. Buttondown, Formspree, ConvertKit or Tally. */
  const WAITLIST_ENDPOINT = "";

  const form = document.getElementById("waitlist");
  const email = document.getElementById("email");
  const status = document.getElementById("waitlist-status");
  const defaultNote = status ? status.textContent : "";

  function setStatus(text, state, html) {
    if (!status) return;
    status.dataset.state = state || "";
    if (html) status.innerHTML = html; else status.textContent = text;
  }

  if (form) {
    form.addEventListener("submit", async (event) => {
      event.preventDefault();
      const value = (email.value || "").trim();
      const valid = /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value);
      email.setAttribute("aria-invalid", valid ? "false" : "true");
      if (!valid) {
        setStatus("Enter an email address like you@example.com.", "error");
        email.focus();
        return;
      }
      const endpoint = form.dataset.endpoint || WAITLIST_ENDPOINT;
      if (!endpoint) {
        setStatus("", "", 'Sign-ups open very soon. Meanwhile, <a href="https://github.com/nipungalhotra/AgentSentinel">watch the GitHub repo</a> to hear about the release first.');
        return;
      }
      const button = form.querySelector("button[type=submit]");
      button.disabled = true;
      setStatus("Adding you…", "");
      try {
        const body = new FormData();
        body.append("email", value);
        const res = await fetch(endpoint, { method: "POST", body, headers: { Accept: "application/json" } });
        if (!res.ok) throw new Error(String(res.status));
        form.reset();
        setStatus("You're on the list. We'll email you when the signed Mac app is ready.", "ok");
      } catch (err) {
        setStatus("That didn't go through. Check your connection and try again.", "error");
      } finally {
        button.disabled = false;
      }
    });
    email.addEventListener("input", () => {
      if (email.getAttribute("aria-invalid") === "true") { email.setAttribute("aria-invalid", "false"); setStatus(defaultNote, ""); }
    });
  }

  document.querySelectorAll("[data-focus-email]").forEach((link) => {
    link.addEventListener("click", (event) => {
      event.preventDefault();
      document.getElementById("top").scrollIntoView({ behavior: matchMedia("(prefers-reduced-motion: reduce)").matches ? "auto" : "smooth" });
      setTimeout(() => email && email.focus({ preventScroll: true }), 450);
    });
  });

  const year = document.getElementById("year");
  if (year) year.textContent = String(new Date().getFullYear());

  /* ---------------- Notch card demo ---------------- */
  const card = document.getElementById("card");
  if (!card) return;

  const REQUESTS = [
    { agent: "Claude Code", dir: "~/code/shop-api", risk: "medium", q: "Run this command?", cmd: "npm install stripe@latest", act: "installing the Stripe SDK" },
    { agent: "Codex", dir: "~/code/shop-api", risk: "high", q: "Run this command?", cmd: "git push --force origin main", act: "pushing the rebased branch" },
    { agent: "Cursor", dir: "~/code/site", risk: "low", q: "Run this command?", cmd: "cd web && npm test | head -40", act: "running the web tests" },
    { agent: "Claude Code", dir: "~/code/shop-api", risk: "medium", q: "Edit this file?", cmd: "write src/checkout/handler.ts  (+42 −17)", act: "updating the checkout handler" },
    { agent: "Antigravity", dir: "~/code/infra", risk: "high", q: "Run this command?", cmd: "terraform apply -auto-approve", act: "applying the staging plan" },
    { agent: "Copilot CLI", dir: "~/code/site", risk: "low", q: "Connect to this host?", cmd: "GET api.github.com/repos/acme/site/pulls", act: "checking open pull requests" },
  ];
  const AUTO_SCOPES = ["once", "10m", "always", "once", "all", "once"];
  const SCOPE_TEXT = {
    once: { button: "Allow once", done: "Allowed once." },
    "10m": { button: "Allow 10 min", done: "Allowed for 10 minutes in this folder." },
    all: { button: "Allow 10 min, all", done: "Allowed for 10 minutes in every folder." },
    always: { button: "Always allow", done: "Saved as a rule for this folder." },
  };
  const MOUTH = { happy: "M13.5 25c3.6 3.6 9.4 3.6 13 0", flat: "M14 26.5h12", sad: "M13.5 28.5c3.6-3.6 9.4-3.6 13 0" };
  const RISK_LABEL = { low: "Low risk", medium: "Medium risk", high: "High risk" };
  const CIRC = 182.2;

  const $ = (id) => document.getElementById(id);
  const el = { q: $("card-q"), agent: $("card-agent"), dir: $("card-dir"), risk: $("card-risk"), cmd: $("card-cmd"),
               ring: $("ring"), mouth: $("mouth"), resolved: $("resolved"), allow: $("allow"), allowLabel: $("allow-label"),
               deny: $("deny"), log: $("agent-log"), pause: $("demo-pause") };
  const scopeButtons = Array.from(card.querySelectorAll(".scope"));

  const reducedMotion = matchMedia("(prefers-reduced-motion: reduce)").matches;
  let autoplay = !reducedMotion;
  let index = 0;
  let scope = "once";
  let current = REQUESTS[0];
  let busy = false;
  let timer = null;
  let rafId = null;
  let deadline = 0;
  let total = 0;

  function setScope(next, fromUser) {
    const btn = scopeButtons.find((b) => b.dataset.scope === next);
    if (!btn || btn.getAttribute("aria-disabled") === "true") return;
    scope = next;
    scopeButtons.forEach((b) => b.setAttribute("aria-checked", b === btn ? "true" : "false"));
    el.allowLabel.textContent = SCOPE_TEXT[next].button;
    if (fromUser) engage();
  }

  function logLine(prefix, text, cls) {
    const li = document.createElement("li");
    const p = document.createElement("span");
    p.className = cls || "dim";
    p.textContent = prefix + " ";
    li.append(p, document.createTextNode(text));
    el.log.append(li);
    while (el.log.children.length > 9) el.log.firstElementChild.remove();
  }

  function stopClock() { clearTimeout(timer); cancelAnimationFrame(rafId); }

  function tick() {
    const left = Math.max(0, deadline - performance.now());
    el.ring.style.strokeDashoffset = String(CIRC * (1 - left / total));
    el.ring.style.stroke = left < 3000 ? "#f0a35a" : "#5aa8f0";
    if (left > 0) { rafId = requestAnimationFrame(tick); return; }
    if (autoplay) {
      const auto = current.risk === "high" ? null : AUTO_SCOPES[index % AUTO_SCOPES.length];
      if (auto) { setScope(auto); press(el.allow, () => decide("allow")); }
      else press(el.deny, () => decide("deny"));
    } else {
      decide("timeout");
    }
  }

  function startClock(ms) {
    stopClock();
    total = ms; deadline = performance.now() + ms;
    if (reducedMotion) { el.ring.style.strokeDashoffset = "0"; if (!autoplay) timer = setTimeout(() => decide("timeout"), ms); return; }
    rafId = requestAnimationFrame(tick);
  }

  function press(button, then) {
    button.classList.add("is-pressed");
    setTimeout(() => { button.classList.remove("is-pressed"); then(); }, 140);
  }

  function show(i) {
    current = REQUESTS[i % REQUESTS.length];
    el.q.textContent = current.q;
    el.agent.textContent = current.agent;
    el.dir.textContent = current.dir;
    el.cmd.textContent = current.cmd;
    el.risk.dataset.risk = current.risk;
    el.risk.textContent = RISK_LABEL[current.risk];
    el.resolved.textContent = "";
    el.ring.style.strokeDashoffset = "0";
    el.ring.style.stroke = "#5aa8f0";
    el.mouth.setAttribute("d", current.risk === "high" ? MOUTH.flat : MOUTH.happy);
    const allBtn = scopeButtons.find((b) => b.dataset.scope === "all");
    const high = current.risk === "high";
    allBtn.setAttribute("aria-disabled", high ? "true" : "false");
    allBtn.title = high ? "Not offered for high-risk actions" : "10 minutes in every folder";
    setScope("once");
    card.classList.remove("is-deny");
    card.classList.remove("is-stowed");
    logLine(current.agent.split(" ")[0].toLowerCase() + " ›", current.act + "… waiting for you", "dim");
    busy = false;
    startClock(autoplay ? 5200 : 30000);
  }

  function decide(kind) {
    if (busy) return;
    busy = true;
    stopClock();
    const who = current.agent.split(" ")[0].toLowerCase() + " ›";
    if (kind === "allow") {
      el.mouth.setAttribute("d", MOUTH.happy);
      el.resolved.textContent = SCOPE_TEXT[scope].done;
      logLine(who, "allowed: " + current.cmd, "ok");
    } else {
      el.mouth.setAttribute("d", MOUTH.sad);
      card.classList.add("is-deny");
      el.resolved.textContent = kind === "timeout" ? "No answer, so it was denied." : "Denied. The agent carries on without it.";
      logLine(who, "denied: " + current.cmd, "no");
    }
    setTimeout(() => {
      card.classList.add("is-stowed");
      setTimeout(() => { index += 1; show(index); }, reducedMotion ? 200 : 650);
    }, reducedMotion ? 1400 : 1100);
  }

  function engage() {
    if (!autoplay) return;
    autoplay = false;
    el.pause.setAttribute("aria-pressed", "true");
    el.pause.textContent = "Play demo";
    if (!busy) startClock(30000);
  }

  scopeButtons.forEach((b) => b.addEventListener("click", () => setScope(b.dataset.scope, true)));
  card.querySelector(".scopes").addEventListener("keydown", (event) => {
    if (event.key !== "ArrowRight" && event.key !== "ArrowLeft") return;
    event.preventDefault();
    const enabled = scopeButtons.filter((b) => b.getAttribute("aria-disabled") !== "true");
    let i = enabled.findIndex((b) => b.dataset.scope === scope);
    i = (i + (event.key === "ArrowRight" ? 1 : -1) + enabled.length) % enabled.length;
    setScope(enabled[i].dataset.scope, true);
    enabled[i].focus();
  });
  el.allow.addEventListener("click", () => { engage(); decide("allow"); });
  el.deny.addEventListener("click", () => { engage(); decide("deny"); });

  // Return / esc work like the real card, but never while typing in a field elsewhere.
  document.addEventListener("keydown", (event) => {
    const t = event.target;
    const typing = t && (t.tagName === "INPUT" || t.tagName === "TEXTAREA" || t.isContentEditable);
    const inCard = t && card.contains(t);
    if (typing || (!inCard && t !== document.body)) return;
    if (event.key === "Enter" && !(inCard && t.classList.contains("scope"))) { event.preventDefault(); engage(); press(el.allow, () => decide("allow")); }
    if (event.key === "Escape") { event.preventDefault(); engage(); press(el.deny, () => decide("deny")); }
  });

  el.pause.addEventListener("click", () => {
    autoplay = !autoplay;
    el.pause.setAttribute("aria-pressed", autoplay ? "false" : "true");
    el.pause.textContent = autoplay ? "Pause demo" : "Play demo";
    if (!busy) startClock(autoplay ? 5200 : 30000);
  });
  if (!autoplay) { el.pause.textContent = "Play demo"; el.pause.setAttribute("aria-pressed", "true"); }

  // Pause the clock while the demo is off screen or the tab is hidden.
  let visible = true;
  const io = new IntersectionObserver((entries) => {
    visible = entries[0].isIntersecting;
    if (!visible) stopClock(); else if (!busy) startClock(autoplay ? 5200 : 30000);
  }, { threshold: 0.25 });
  io.observe(card);
  document.addEventListener("visibilitychange", () => { if (document.hidden) stopClock(); else if (visible && !busy) startClock(autoplay ? 5200 : 30000); });

  show(0);
})();
