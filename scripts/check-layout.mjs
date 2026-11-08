#!/usr/bin/env node
// Checks that a page's layout holds still while it's used: text that changes (a button's label,
// a count, a status line) and controls that move (sliders, buttons) must not resize or move
// anything else. Opens the page in headless Chrome, then moves every slider through its range
// and presses every button, letting each settle, and compares every visible element's place
// and size before and after. Anything meant to move carries `data-moves` (it and its children
// are left out).
//
// Pressing every button must never act on anything real. Every request that would write
// (anything but GET, HEAD and OPTIONS) is held back before it leaves the browser and named;
// forms never submit; links are never followed. A button marked `data-no-press` is never
// pressed. Still meant for mockups and pages on test data: a WebSocket message or a write to
// the page's own storage isn't stopped.
//
//   node check-layout.mjs [--sizes 1280x900,390x844] [--settle 1500] <page.html or URL>...
//
// Exits 1 and names each shift (what moved, by how much, after which step), 2 when Chrome
// can't be found or started, else 0. CHROME=/path/to/chrome picks the browser.

import { spawn } from "node:child_process";
import { existsSync, mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";

const args = process.argv.slice(2);
let sizes = "1280x900,390x844";
let settle = 1500;
const pages = [];
for (let i = 0; i < args.length; i++) {
  if (args[i] === "--sizes") sizes = args[++i];
  else if (args[i] === "--settle") settle = Number(args[++i]);
  else pages.push(args[i]);
}
if (!pages.length) {
  console.error("usage: check-layout.mjs [--sizes 1280x900,390x844] [--settle 1500] <page.html or URL>...");
  process.exit(2);
}

function findChrome() {
  const known = [
    process.env.CHROME,
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    "/Applications/Chromium.app/Contents/MacOS/Chromium",
    "/usr/bin/google-chrome",
    "/usr/bin/google-chrome-stable",
    "/usr/bin/chromium",
    "/usr/bin/chromium-browser",
  ];
  return known.find((p) => p && existsSync(p));
}

const chrome = findChrome();
if (!chrome) {
  console.error("check-layout: no Chrome found (set CHROME=/path/to/chrome)");
  process.exit(2);
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// Starts Chrome with a throwaway profile and returns its DevTools port.
async function launch(profile) {
  const proc = spawn(chrome, [
    "--headless=new", "--no-sandbox", "--disable-gpu-sandbox", "--use-angle=swiftshader", "--enable-unsafe-swiftshader",
    "--hide-scrollbars", "--mute-audio", "--no-first-run", "--no-default-browser-check",
    "--remote-debugging-port=0", `--user-data-dir=${profile}`, "about:blank",
  ], { stdio: "ignore" });
  const file = join(profile, "DevToolsActivePort");
  for (let i = 0; i < 100; i++) {
    if (existsSync(file)) {
      const port = readFileSync(file, "utf8").split("\n")[0].trim();
      if (port) return { proc, port };
    }
    await sleep(100);
  }
  proc.kill();
  throw new Error("Chrome didn't start");
}

// One page over the DevTools protocol: send a method, wait for its answer.
async function openPage(port) {
  const res = await fetch(`http://127.0.0.1:${port}/json/new?about:blank`, { method: "PUT" });
  const { webSocketDebuggerUrl } = await res.json();
  const ws = new WebSocket(webSocketDebuggerUrl);
  await new Promise((ok, bad) => { ws.onopen = ok; ws.onerror = bad; });
  let next = 0;
  const waiting = new Map();
  const events = [];
  const held = [];
  const send = (method, params = {}) => new Promise((ok, bad) => {
    const id = ++next;
    waiting.set(id, { ok, bad });
    ws.send(JSON.stringify({ id, method, params }));
  });
  ws.onmessage = (m) => {
    const msg = JSON.parse(m.data);
    if (msg.id && waiting.has(msg.id)) {
      const { ok, bad } = waiting.get(msg.id);
      waiting.delete(msg.id);
      msg.error ? bad(new Error(msg.error.message)) : ok(msg.result);
    } else if (msg.method === "Fetch.requestPaused") {
      // Pressing every button must never change anything anywhere: a request that would
      // write is held back before it leaves, and named. Reads go on, so pages still draw.
      const { requestId, request } = msg.params;
      if (READS.has(request.method)) send("Fetch.continueRequest", { requestId }).catch(() => {});
      else {
        held.push(`${request.method} ${request.url}`);
        send("Fetch.failRequest", { requestId, errorReason: "BlockedByClient" }).catch(() => {});
      }
    } else if (msg.method) events.push(msg);
  };
  return { send, events, held, close: () => ws.close() };
}

const READS = new Set(["GET", "HEAD", "OPTIONS"]);

// Runs in the page: snapshots every visible element, drives each control, reports shifts.
const DRIVER = `(async (settle) => {
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  document.addEventListener("submit", (e) => e.preventDefault(), true);
  const keyOf = (el) => {
    const parts = [];
    for (let n = el; n && n !== document.body; n = n.parentElement) {
      const same = n.parentElement ? [...n.parentElement.children].filter((c) => c.tagName === n.tagName) : [n];
      parts.unshift(n.tagName.toLowerCase() + (n.id ? "#" + n.id : same.length > 1 ? ":nth-of-type(" + (same.indexOf(n) + 1) + ")" : ""));
    }
    return parts.join(" > ");
  };
  const words = (el) => (el.getAttribute("aria-label") || el.textContent || "").replace(/\\s+/g, " ").trim().slice(0, 40);
  const snap = () => {
    const seen = new Map();
    for (const el of document.body.querySelectorAll("*")) {
      if (el.closest("[data-moves]") || ["SCRIPT", "STYLE", "TEMPLATE"].includes(el.tagName)) continue;
      const r = el.getBoundingClientRect();
      if (!r.width && !r.height) continue;
      seen.set(keyOf(el), { x: r.left + scrollX, y: r.top + scrollY, w: r.width, h: r.height, words: words(el) });
    }
    return seen;
  };
  const shifts = [];
  const compare = (before, after, step) => {
    for (const [key, a] of before) {
      const b = after.get(key);
      if (!b) continue;
      const moved = Math.abs(a.x - b.x) > 0.5 || Math.abs(a.y - b.y) > 0.5;
      const resized = Math.abs(a.w - b.w) > 0.5 || Math.abs(a.h - b.h) > 0.5;
      if (moved || resized) {
        shifts.push({ step, key, words: a.words === b.words ? a.words : a.words + " → " + b.words,
          from: [a.x, a.y, a.w, a.h].map(Math.round), to: [b.x, b.y, b.w, b.h].map(Math.round) });
      }
    }
  };
  // Watches a step for its whole settle time, so a shift that comes and goes is caught too.
  const watch = async (step, act) => {
    const before = snap();
    act();
    for (let t = 0; t < settle; t += 100) {
      await sleep(100);
      compare(before, snap(), step);
    }
  };
  const controls = () => [...document.querySelectorAll("button, input[type=button], [role=button], input[type=range]")]
    .filter((el) => !el.closest("[data-moves], [data-no-press]"));
  await sleep(300);
  for (const el of controls()) {
    if (el.matches("input[type=range]")) {
      const min = +el.min || 0, max = el.max === "" ? 100 : +el.max;
      for (const f of [0.25, 0.5, 0.75, 1, 0]) {
        const v = min + (max - min) * f;
        await watch("slider " + (words(el) || keyOf(el)) + " to " + v, () => {
          el.value = v;
          el.dispatchEvent(new Event("input", { bubbles: true }));
          el.dispatchEvent(new Event("change", { bubbles: true }));
        });
      }
    } else if (!el.disabled) {
      await watch("press " + (words(el) || keyOf(el)), () => el.click());
    }
  }
  // Each step's shifts once, the first time each element moved in it.
  const once = new Set();
  return shifts.filter((s) => { const k = s.step + "|" + s.key; if (once.has(k)) return false; once.add(k); return true; });
})`;

async function check(page, port, width, height) {
  const tab = await openPage(port);
  try {
    await tab.send("Emulation.setDeviceMetricsOverride", { width, height, deviceScaleFactor: 1, mobile: width < 600 });
    await tab.send("Fetch.enable", { patterns: [{ urlPattern: "*" }] });
    await tab.send("Page.enable");
    const url = /^[a-z]+:\/\//.test(page) ? page : pathToFileURL(resolve(page)).href;
    await tab.send("Page.navigate", { url });
    for (let i = 0; i < 100 && !tab.events.some((e) => e.method === "Page.loadEventFired"); i++) await sleep(100);
    const res = await tab.send("Runtime.evaluate", { expression: `${DRIVER}(${settle})`, awaitPromise: true, returnByValue: true });
    if (res.exceptionDetails) throw new Error(res.exceptionDetails.exception?.description ?? res.exceptionDetails.text);
    return { shifts: res.result.value, held: [...new Set(tab.held)] };
  } finally {
    tab.close();
  }
}

const profile = mkdtempSync(join(tmpdir(), "check-layout-"));
let browser;
let failed = false;
try {
  browser = await launch(profile);
  for (const page of pages) {
    for (const size of sizes.split(",")) {
      const [w, h] = size.split("x").map(Number);
      const { shifts, held } = await check(page, browser.port, w, h);
      for (const r of held) console.log(`held back (never sent): ${r}`);
      if (!shifts.length) {
        console.log(`ok: ${page} at ${size}`);
        continue;
      }
      failed = true;
      console.log(`SHIFTS: ${page} at ${size}`);
      for (const s of shifts.slice(0, 20)) {
        console.log(`  after "${s.step}": ${s.key}${s.words ? ` ("${s.words}")` : ""} went from x,y,w,h ${s.from.join(",")} to ${s.to.join(",")}`);
      }
      if (shifts.length > 20) console.log(`  ...and ${shifts.length - 20} more`);
    }
  }
} catch (e) {
  console.error(`check-layout: ${e.message}`);
  process.exitCode = 2;
} finally {
  // Chrome writes to its profile while it closes: wait for it, then remove the profile.
  if (browser) {
    const gone = new Promise((r) => browser.proc.once("exit", r));
    browser.proc.kill();
    await Promise.race([gone, sleep(5000)]);
  }
  try {
    rmSync(profile, { recursive: true, force: true, maxRetries: 5, retryDelay: 200 });
  } catch {
    // A leftover temporary profile is harmless; the result above stands.
  }
}
if (failed && !process.exitCode) process.exitCode = 1;
