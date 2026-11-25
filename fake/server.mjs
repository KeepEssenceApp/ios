#!/usr/bin/env node
// A small fake of the core, for tests of the iPhone app only. It answers the operations of
// contract/openapi.yaml that the app uses, from memory, with invented content. It is not the core:
// no models, no expiry, one user. The sign-in code is always 123456.
//
//   node fake/server.mjs            listens on 127.0.0.1:8795
//   PORT=9000 node fake/server.mjs
//   POST /__reset                   back to the seed
//   GET  /__state                   what was saved, for tests to look at
import http from "node:http";
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const PORT = Number(process.env.PORT || 8795);
const here = path.dirname(fileURLToPath(import.meta.url));
// The same file the app bundles, generated from contract/openapi.yaml.
const META = JSON.parse(fs.readFileSync(path.join(here, "../KeepCore/Sources/KeepCore/Resources/shared-rules.json"), "utf8"));
const MSG = META.shared_rules.save_messages;

const iso = (msAgo = 0) => new Date(Date.now() - msAgo).toISOString();
const MIN = 60_000, HOUR = 3_600_000, DAY = 86_400_000;
const pad = (n) => String(n).padStart(2, "0");
const dayOf = (d) => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
const today = () => dayOf(new Date());
const daysAgo = (n) => dayOf(new Date(Date.now() - n * DAY));

let S;

function seed() {
  const sig = { id: "a_builtin", name: "内置助手" };
  const analysis = (o) => ({ unavailable: false, assistant: sig, created_at: iso(o.min * MIN), related_hint: null, ...o.a });
  S = {
    seq: 100,
    credentials: new Map(),
    idem: new Map(),
    saved: [],
    assets: new Map(),
    user: { id: "u1", timezone: "Asia/Shanghai", lang: "zh" },
    devices: [
      { id: "d_ext", name: "Chrome 扩展", category: "client", client: "extension", tier: "save", created_at: iso(9 * DAY), last_used_at: iso(2 * HOUR), notifications: false },
      { id: "d_web", name: "办公室的浏览器", category: "client", client: "web", tier: "manage", created_at: iso(20 * DAY), last_used_at: iso(26 * HOUR), notifications: true },
      { id: "a_chat", name: "阿深", category: "assistant", steps: ["deep_dive"], created_at: iso(6 * DAY), last_used_at: iso(3 * DAY) },
    ],
    codes: new Map([["K7M-2QX", { device_name: "Edge 扩展", client: "extension", requested_tier: "read", expires_at: iso(-9 * MIN) }]]),
    assistants: [
      { id: "a_builtin", name: "内置助手", kind: "scheduled", steps: ["analysis", "digest"], built_in: true, connected_at: null, last_seen_at: iso(4 * MIN), runs_at: null },
      { id: "a_chat", name: "阿深", kind: "chat", steps: ["deep_dive"], built_in: false, connected_at: iso(6 * DAY), last_seen_at: iso(3 * DAY), runs_at: "chat.example.com" },
      { id: "a_sched", name: "阿读", kind: "scheduled", steps: ["analysis", "digest", "deep_read", "deep_dive"], built_in: false, connected_at: iso(5 * DAY), last_seen_at: iso(50 * MIN), runs_at: "agent.example.net" },
    ],
    settings: {
      rules: "讲数据库和分布式的交给阿读，保留 90 天。其余的交给内置助手。",
      preference: null, expiry_options: [7, 30, 90, 365], notify: true, timezone: "Asia/Shanghai", lang: "zh",
      roles: { analysis: "a_builtin", digest: "a_builtin", deep_read: "a_sched", deep_dive: "a_chat" },
      calendar_image: { enabled: false, url: null },
    },
    items: [
      { id: "i1", kind: "link", title: "把定时任务做成幂等的七种写法", site: "blog.example.dev", url: "https://blog.example.dev/idempotent-jobs", created_at: iso(35 * MIN), stage: "analysed",
        analysis: analysis({ min: 12, a: { summary: "从「同一份活交两遍会怎样」出发，列出七种让定时任务不出乱子的写法。", key_fact: "作者 林未 · 约 8 分钟读完", points: ["给每份活一个由内容算出来的标识，交回时按标识去重。", "租约要比最慢的一次执行长，过期后才允许别人接手。", "外部副作用放在最后一步，并且能重放。"], verdict: "worth_deep_dive", related_hint: "和 11 月 19 日每日摘要里讲租约的那条有关。" } }) },
      { id: "i2", kind: "link", title: "SQLite 在高并发写入下的 WAL 行为实测", site: "db.example.org", url: "https://db.example.org/wal-under-load", created_at: iso(80 * MIN), stage: "analysed",
        analysis: analysis({ min: 30, a: { summary: "8 个写线程压三种同步级别：WAL 本身不慢，慢在检查点。", key_fact: "作者 周序 · 约 12 分钟读完", points: ["有长读事务时检查点推不动，WAL 文件一直涨。", "把读事务切短，或在空闲时主动做截断式检查点。"], verdict: "good_to_know" } }) },
      { id: "i3", kind: "text", title: "一段摘抄：关于「少即是多」", site: null, url: null, created_at: iso(3 * HOUR), stage: "analysed",
        analysis: analysis({ min: 100, a: { summary: "一段讲删减比添加更难的摘抄，没有新的论据。", key_fact: "文字 · 212 字", points: ["观点常见，例子是旧的。"], verdict: "skippable" } }) },
      { id: "i4", kind: "link", title: "example.net 上的一篇文章", site: "example.net", url: "https://example.net/gone", created_at: iso(4 * HOUR), stage: "analysed", content_unavailable: true,
        analysis: analysis({ min: 200, a: { unavailable: true, summary: "没取到内容" } }) },
      { id: "i5", kind: "link", title: "Streamable HTTP 传输说明（草案）", site: "spec.example.io", url: "https://spec.example.io/streamable-http", created_at: iso(9 * MIN), stage: "triaged", dispatch_to: { id: "a_sched", name: "阿读" } },
      { id: "i6", kind: "image", title: "截屏 11-24 20.58", site: null, url: null, created_at: iso(2 * MIN), stage: "saved" },
      // already in a digest
      { id: "g1", kind: "link", title: "「能安全重放」怎么定义？", site: "notes.example.com", url: "https://notes.example.com/replay", created_at: iso(30 * HOUR), stage: "analysed", digest: true,
        analysis: analysis({ min: 1700, a: { summary: "把「重放安全」拆成三个可以检验的条件。", key_fact: "作者 许衡 · 约 6 分钟读完", points: ["结果只取决于输入。"], verdict: "worth_deep_dive" } }) },
      { id: "g2", kind: "link", title: "一次认领过期引发的重复交回", site: "ops.example.dev", url: "https://ops.example.dev/claim-expiry", created_at: iso(31 * HOUR), stage: "analysed", digest: true,
        analysis: analysis({ min: 1750, a: { summary: "认领 30 分钟过期后，两只助手都交回了同一份活。", key_fact: "事故复盘 · 约 5 分钟读完", points: ["后一次交回替换前一次，没有产生第二份。"], verdict: "worth_deep_dive" } }) },
      { id: "g3", kind: "link", title: "周末读物清单", site: "list.example.org", url: "https://list.example.org/weekend", created_at: iso(33 * HOUR), stage: "analysed", digest: true, signal: "seen",
        analysis: analysis({ min: 1800, a: { summary: "十条链接的清单。", key_fact: "清单 · 10 条", points: [], verdict: "skippable" } }) },
      { id: "g4", kind: "link", title: "新版命令行工具的更新说明", site: "tool.example.io", url: "https://tool.example.io/changelog", created_at: iso(34 * HOUR), stage: "analysed", digest: true,
        analysis: analysis({ min: 1810, a: { summary: "修了三个问题，没有新功能。", key_fact: "更新说明 · 约 2 分钟读完", points: [], verdict: "good_to_know" } }) },
      { id: "q1", kind: "link", title: "租约和心跳：两种判活的办法", site: "dist.example.org", url: "https://dist.example.org/lease-heartbeat", created_at: iso(50 * HOUR), stage: "analysed", digest: true,
        analysis: analysis({ min: 2900, a: { summary: "比较租约和心跳在判活上的取舍。", key_fact: "作者 沈括之 · 约 15 分钟读完", points: ["租约靠时钟，心跳靠网络。"], verdict: "worth_deep_dive" } }) },
    ],
    queue: [
      { item_id: "q1", added_at: iso(20 * HOUR), deep_read: "ready", went_at: iso(3 * HOUR), fetched_at: iso(3 * HOUR), entry: null,
        report: { read: "文章先定义「活着」：能在期限内完成一次确认。租约把判断交给持有者自己的时钟，心跳把判断交给观察者。作者的结论是两者要一起用：租约定上限，心跳定下限。", found: "另外查到两篇讲时钟漂移的实测，漂移在容器里比物理机大一个数量级。", questions: ["租约的长度该怎么随负载调整？", "心跳丢了几次才算死？"], assistant: { id: "a_sched", name: "阿读" } } },
    ],
    digests: [
      { day: daysAgo(1), read: false, summary: "昨天存入了 5 条，多数围绕「同一份活做两遍」这件事：怎么定义能安全重放，认领过期之后会发生什么。另有一份读物清单和一则更新说明。", worth: [{ item_id: "g1", line: "把「重放安全」拆成三个可以检验的条件，可以直接拿来对照自己的任务。" }, { item_id: "g2", line: "一次真实的重复交回：后一次替换前一次，所以没有出乱子。" }], rest: ["g3", "g4", "q1"], question: "你手上哪一个任务，跑两遍会出事？", assistant: { id: "a_builtin", name: "内置助手" }, saved: 5 },
      { day: daysAgo(2), read: true, summary: "前天存入了 2 条，都是讲判活的。", worth: [], rest: ["q1"], question: "「活着」对你的系统来说是什么意思？", assistant: { id: "a_builtin", name: "内置助手" }, saved: 2 },
    ],
    notes: [
      { id: "n1", title: "判活：租约定上限，心跳定下限", body: "## 结论\n\n租约和心跳不是二选一。**租约**回答「最晚什么时候可以接手」，**心跳**回答「最早什么时候可以怀疑」。\n\n- 租约的长度取最慢一次执行的两倍。\n- 心跳连续丢三次才开始怀疑，不直接判死。\n\n## 出处\n\n见下面的来源。", created_at: iso(26 * HOUR), assistant: { id: "a_chat", name: "阿深" }, origin: { item_id: "q1", item_title: "租约和心跳：两种判活的办法", item_url: "https://dist.example.org/lease-heartbeat", digest_day: daysAgo(2) }, sources: [{ title: "租约和心跳：两种判活的办法", url: "https://dist.example.org/lease-heartbeat" }], asset_ids: [] },
      { id: "n2", title: "检查点卡住时该怎么办", body: "把读事务切短；空闲时主动做截断式检查点。", created_at: iso(5 * DAY), assistant: { id: "a_chat", name: "阿深", submitted_by_user: true }, origin: null, sources: [], asset_ids: [] },
    ],
  };
}
seed();

// ---- helpers

const lang = (req) => ((req.headers["accept-language"] || "en").toLowerCase().startsWith("zh") ? "zh" : "en");
const ERR = {
  unauthorized: { zh: "这台设备没有登录，或已被撤销。", en: "This device is not signed in, or was revoked." },
  not_found: { zh: "没有这样东西。", en: "No such thing." },
  bad_request: { zh: "请求不对。", en: "The request is malformed." },
  gone: { zh: "这个短码已经用过或过期了。", en: "This code was used or has expired." },
  last_manager: { zh: "最后一台管理档的设备不能撤销或降档。", en: "The last device with the manage tier cannot be lowered or revoked." },
  idempotency_key_required: { zh: "缺少 Idempotency-Key。", en: "The Idempotency-Key header is missing." },
  conflict: { zh: "没有可以去深挖的助手。", en: "No assistant is set for deep dives." },
  forbidden: { zh: "这台设备的权限不够。", en: "This device's tier does not allow this." },
  bad_code: { zh: "验证码不对。", en: "That code is not right." },
};
function send(res, status, body, headers = {}) {
  const data = body === undefined ? "" : typeof body === "string" ? body : JSON.stringify(body);
  res.writeHead(status, { "content-type": typeof body === "string" ? "text/markdown; charset=utf-8" : "application/json", ...headers });
  res.end(data);
}
function fail(req, res, status, code, messageKey = code) {
  send(res, status, { error: { code, message: (ERR[messageKey] || ERR.bad_request)[lang(req)] } });
}
function readBody(req) {
  return new Promise((resolve) => {
    const chunks = [];
    req.on("data", (c) => chunks.push(c));
    req.on("end", () => resolve(Buffer.concat(chunks)));
  });
}
const publicItem = (i, detail = false) => {
  const out = {
    id: i.id, kind: i.kind, title: i.title, site: i.site ?? null, url: i.url ?? null, created_at: i.created_at, stage: i.stage,
    content_unavailable: !!i.content_unavailable, dispatch_to: i.dispatch_to ?? (i.stage === "saved" ? null : { id: "a_builtin", name: "内置助手" }),
    days_left: i.pinned ? null : Math.max(0, (i.expiry_days ?? 30) - Math.floor((Date.now() - Date.parse(i.expires_from ?? i.created_at)) / DAY)),
    pinned: !!i.pinned, signal: i.signal ?? null, in_queue: S.queue.some((q) => q.item_id === i.id), analysis: i.analysis ?? null,
  };
  if (detail) {
    Object.assign(out, {
      body: i.body ?? (i.kind === "text" ? "删减比添加更难。添加只需要一个理由，删减需要对整体有把握。" : i.content_unavailable ? null : "（原文的正文）" + i.title),
      asset_id: i.asset_id ?? null,
      // A kept item has no end date: no expiry tag, no expiry moment.
      tags: [`assistant:${out.dispatch_to?.name ?? "内置助手"}`, ...(i.pinned ? [] : [`expiry:${i.expiry_days ?? 30}`]), "source:phone/share"],
      expiry_days: i.pinned ? null : i.expiry_days ?? 30,
      expires_at: i.pinned ? null : new Date(Date.parse(i.expires_from ?? i.created_at) + (i.expiry_days ?? 30) * DAY).toISOString(),
    });
  }
  return out;
};
const item = (id) => S.items.find((i) => i.id === id);
function publicDigest(d) {
  const idx = S.digests.indexOf(d);
  const handled = (i) => i && (i.signal || S.queue.some((q) => q.item_id === i.id));
  const worth = d.worth.filter((w) => !handled(item(w.item_id)));
  const moved = d.worth.filter((w) => handled(item(w.item_id))).map((w) => w.item_id);
  const rest = [...moved, ...d.rest].map((id) => {
    const i = item(id);
    const inQueue = S.queue.some((q) => q.item_id === id);
    return { item_id: id, title: i?.title ?? "（已删除）", signal: i?.signal ?? null, in_queue: inQueue, available: !!i, can_restore: !!i && (!!i.signal || (inQueue && moved.includes(id))) };
  });
  return {
    day: d.day, read: d.read, counts: { saved: d.saved, worth: worth.length }, summary: d.summary,
    worth: worth.map((w) => ({ item_id: w.item_id, title: item(w.item_id)?.title, line: w.line, verdict: "worth_deep_dive", available: !!item(w.item_id), in_queue: false })),
    rest, question: d.question, assistant: d.assistant,
    previous_day: S.digests[idx + 1]?.day ?? null, next_day: S.digests[idx - 1]?.day ?? null,
  };
}
function calendar(month) {
  const now = new Date();
  const [y, m] = (month || `${now.getFullYear()}-${pad(now.getMonth() + 1)}`).split("-").map(Number);
  const count = new Date(y, m, 0).getDate();
  const t = today();
  const noteDays = new Set(S.notes.map((n) => dayOf(new Date(n.created_at))));
  const days = [];
  const counts = { saved: 0, digests: 0, read: 0, notes: 0 };
  for (let d = 1; d <= count; d++) {
    const day = `${y}-${pad(m)}-${pad(d)}`;
    const digest = S.digests.find((x) => x.day === day);
    let mark = "empty";
    if (day > t) mark = "future";
    else if (noteDays.has(day)) mark = "note";
    else if (digest) mark = digest.read ? "digest_read" : "digest_unread";
    else if (day === t || d % 3 === 0) mark = day === t ? "saved" : d % 6 === 0 ? "digest_read" : "saved";
    if (mark !== "empty" && mark !== "future") counts.saved += mark === "saved" ? 2 : 4;
    if (mark === "digest_read" || mark === "digest_unread" || mark === "note") counts.digests += 1;
    if (mark === "digest_read" || mark === "note") counts.read += 1;
    if (mark === "note") counts.notes += 1;
    days.push({ day, mark, has_digest: !!digest });
  }
  const prev = new Date(y, m - 2, 1), next = new Date(y, m, 1);
  const thisMonth = `${now.getFullYear()}-${pad(now.getMonth() + 1)}`;
  const key = `${y}-${pad(m)}`;
  return { month: key, today: t, days, counts, previous_month: `${prev.getFullYear()}-${pad(prev.getMonth() + 1)}`, next_month: key < thisMonth ? `${next.getFullYear()}-${pad(next.getMonth() + 1)}` : null };
}
function status() {
  const waiting = S.items.filter((i) => !i.analysis && !i.digest);
  return {
    assistants: S.assistants.map((a) => ({ id: a.id, name: a.name, state: !a.last_seen_at ? "never" : Date.now() - Date.parse(a.last_seen_at) < DAY ? "recent" : "quiet", last_seen_at: a.last_seen_at })),
    saved_today: S.items.filter((i) => !i.digest).length, waiting: waiting.length,
    oldest_waiting_deleted_on: waiting.length ? dayOf(new Date(Date.now() + 29 * DAY)) : null,
    no_digest_reason: "not_yet_time",
  };
}
const queueEntry = (q) => ({ ...q, title: item(q.item_id)?.title ?? "" });

// ---- routes

const routes = [];
const route = (method, pattern, handler, open = false) => {
  const keys = [];
  const re = new RegExp("^" + pattern.replace(/:[a-z_]+/g, (k) => (keys.push(k.slice(1)), "([^/]+)")) + "$");
  routes.push({ method, re, keys, handler, open });
};

route("GET", "/v1/meta", (c) => c.json(200, META), true);
route("POST", "/v1/auth/email-codes", (c) => c.empty(202), true);
route("POST", "/v1/auth/sessions", (c) => {
  if (c.body.code !== "123456") return c.fail(401, "unauthorized", "bad_code");
  const credential = "fake-credential-" + crypto.randomBytes(8).toString("hex");
  const device = { id: "d_" + ++S.seq, name: c.body.device_name || "iPhone", category: "client", client: c.body.client || "phone", tier: "manage", created_at: iso(), last_used_at: iso(), notifications: false };
  S.devices.unshift(device);
  S.credentials.set(credential, device.id);
  c.json(201, { credential, device: { ...device, this_device: true }, user: S.user });
}, true);

route("GET", "/v1/devices/me", (c) => c.json(200, { device: { ...c.device, this_device: true }, user: S.user }));
route("DELETE", "/v1/devices/me", (c) => {
  S.devices = S.devices.filter((d) => d !== c.device);
  c.empty(204);
});
route("GET", "/v1/devices", (c) => c.json(200, { devices: S.devices.map((d) => ({ ...d, this_device: d === c.device })) }));
route("PATCH", "/v1/devices/:id", (c) => {
  const d = S.devices.find((x) => x.id === c.p.id);
  if (!d) return c.fail(404, "not_found");
  if (c.body.tier && d.tier === "manage" && c.body.tier !== "manage" && S.devices.filter((x) => x.tier === "manage").length === 1) return c.fail(409, "last_manager");
  if (c.body.name) d.name = c.body.name;
  if (c.body.tier) d.tier = c.body.tier;
  c.json(200, { ...d, this_device: d === c.device });
});
route("DELETE", "/v1/devices/:id", (c) => {
  const d = S.devices.find((x) => x.id === c.p.id);
  if (!d) return c.fail(404, "not_found");
  if (d.tier === "manage" && S.devices.filter((x) => x.tier === "manage").length === 1) return c.fail(409, "last_manager");
  S.devices = S.devices.filter((x) => x !== d);
  S.assistants = S.assistants.filter((a) => a.id !== d.id);
  c.empty(204);
});
route("GET", "/v1/device-codes/:code/request", (c) => {
  const r = S.codes.get(c.p.code);
  return r ? c.json(200, r) : c.fail(404, "not_found");
});
route("POST", "/v1/device-codes/:code/approve", (c) => {
  const r = S.codes.get(c.p.code);
  if (!r) return c.fail(410, "gone");
  const rank = { save: 0, read: 1, manage: 2 };
  const tier = c.body.tier || r.requested_tier;
  if (rank[tier] > rank[r.requested_tier]) return c.fail(400, "bad_request");
  S.codes.delete(c.p.code);
  const d = { id: "d_" + ++S.seq, name: c.body.device_name || r.device_name, category: "client", client: r.client, tier, created_at: iso(), last_used_at: null, notifications: false };
  S.devices.push(d);
  c.json(200, d);
});
route("POST", "/v1/device-codes/:code/deny", (c) => (S.codes.delete(c.p.code) ? c.empty(204) : c.fail(410, "gone")));

route("POST", "/v1/items", (c) => {
  const key = c.req.headers["idempotency-key"];
  if (!key) return c.fail(400, "idempotency_key_required");
  if (S.idem.has(key)) return c.json(...S.idem.get(key));
  const allowed = ["kind", "url", "title", "text", "asset_id", "entry"];
  const b = c.body;
  if (Object.keys(b).some((k) => !allowed.includes(k)) || !["link", "text", "image", "file"].includes(b.kind) ||
      (b.kind === "link" && !b.url) || (b.kind === "text" && !b.text) || ((b.kind === "image" || b.kind === "file") && !b.asset_id)) return c.fail(400, "bad_request");
  let answer;
  const dup = b.kind === "link" && S.items.find((i) => i.url === b.url);
  if (dup) {
    answer = [200, { status: "duplicate", item_id: dup.id, message_key: "duplicate", message: MSG.duplicate[c.lang] }];
  } else {
    const id = "i" + ++S.seq;
    let site = null;
    try { site = b.url ? new URL(b.url).host : null; } catch {}
    S.items.push({ id, kind: b.kind, title: b.title || (b.text || "").split("\n")[0].slice(0, 60) || site || "图片", site, url: b.url ?? null, body: b.text ?? null, asset_id: b.asset_id ?? null, created_at: iso(), stage: "saved" });
    S.saved.push({ id, key, ...b });
    answer = [201, { status: "saved", item_id: id, message_key: "saved", message: MSG.saved[c.lang], image_stored: b.asset_id ? true : undefined }];
  }
  S.idem.set(key, answer);
  c.json(...answer);
});
route("GET", "/v1/items", (c) => {
  const state = c.q.get("state");
  const list = S.items.filter((i) => (state === "today" ? !i.digest : state === "digested" ? i.digest : i.pinned));
  c.json(200, { items: list.map((i) => publicItem(i)), next_cursor: null });
});
route("GET", "/v1/items/:id", (c) => (item(c.p.id) ? c.json(200, publicItem(item(c.p.id), true)) : c.fail(404, "not_found")));
route("PATCH", "/v1/items/:id", (c) => {
  const i = item(c.p.id);
  if (!i) return c.fail(404, "not_found");
  if (c.body.expiry_days) {
    i.expiry_days = c.body.expiry_days;
    // Days on a kept item give it an end date again, counted from now.
    if (i.pinned) { i.pinned = false; i.expires_from = new Date().toISOString(); }
  }
  if (c.body.dispatch_to) {
    const a = S.assistants.find((x) => x.id === c.body.dispatch_to);
    if (!a) return c.fail(400, "bad_request");
    i.dispatch_to = { id: a.id, name: a.name };
  }
  c.json(200, publicItem(i, true));
});
route("DELETE", "/v1/items/:id", (c) => {
  S.items = S.items.filter((i) => i.id !== c.p.id);
  S.queue = S.queue.filter((q) => q.item_id !== c.p.id);
  c.empty(204);
});
route("PUT", "/v1/items/:id/pin", (c) => (item(c.p.id) ? ((item(c.p.id).pinned = true), c.empty(204)) : c.fail(404, "not_found")));
route("DELETE", "/v1/items/:id/pin", (c) => {
  const i = item(c.p.id);
  if (!i) return c.fail(404, "not_found");
  if (i.pinned) { i.pinned = false; i.expires_from = new Date().toISOString(); }
  c.empty(204);
});
route("PUT", "/v1/items/:id/signal", (c) => {
  const i = item(c.p.id);
  if (!i) return c.fail(404, "not_found");
  if (!["not_interested", "seen"].includes(c.body.signal)) return c.fail(400, "bad_request");
  i.signal = c.body.signal;
  c.empty(204);
});
route("DELETE", "/v1/items/:id/signal", (c) => (item(c.p.id) ? ((item(c.p.id).signal = null), c.empty(204)) : c.fail(404, "not_found")));

route("GET", "/v1/digests", (c) => c.json(200, { digests: S.digests.map((d) => ({ day: d.day, read: d.read })), next_cursor: null }));
route("GET", "/v1/digests/:day", (c) => {
  const d = c.p.day === "latest" ? S.digests[0] : S.digests.find((x) => x.day === c.p.day);
  return d ? c.json(200, publicDigest(d)) : c.fail(404, "not_found");
});
route("POST", "/v1/digests/:day/read", (c) => {
  const d = S.digests.find((x) => x.day === c.p.day);
  if (!d) return c.fail(404, "not_found");
  d.read = true;
  c.empty(204);
});

route("GET", "/v1/deep-read-queue", (c) => c.json(200, { entries: S.queue.map(queueEntry) }));
route("PUT", "/v1/deep-read-queue/:id", (c) => {
  if (!item(c.p.id)) return c.fail(404, "not_found");
  let q = S.queue.find((x) => x.item_id === c.p.id);
  if (!q) S.queue.unshift((q = { item_id: c.p.id, added_at: iso(), deep_read: "waiting", report: null, went_at: null, fetched_at: null, entry: null }));
  c.json(200, queueEntry(q));
});
route("DELETE", "/v1/deep-read-queue/:id", (c) => {
  S.queue = S.queue.filter((q) => q.item_id !== c.p.id);
  c.empty(204);
});
route("POST", "/v1/deep-dive-requests", (c) => {
  const i = item(c.body.item_id);
  if (!i) return c.fail(404, "not_found");
  const a = S.assistants.find((x) => x.id === (c.body.assistant_id || S.settings.roles.deep_dive));
  if (!a) return c.fail(409, "conflict");
  const q = S.queue.find((x) => x.item_id === i.id);
  if (q) q.went_at = iso();
  const line = META.shared_rules.opening_line[c.lang].replace("{first_line}", i.title);
  c.json(201, { assistant: { id: a.id, name: a.name }, opening_line: line, open_url: a.kind === "chat" ? "https://chat.example.com/new?q=" + encodeURIComponent(line) : null, entry: a.kind === "chat" ? null : "在 agent.example.net 的对话里发出开场话" });
});

route("GET", "/v1/notes", (c) => {
  const q = (c.q.get("q") || "").trim();
  const list = S.notes.filter((n) => !q || n.title.includes(q) || n.body.includes(q));
  c.json(200, { notes: list.map((n) => ({ id: n.id, title: n.title, excerpt: n.body.replace(/[#*\n-]+/g, " ").trim().slice(0, 80), created_at: n.created_at })), next_cursor: null });
});
route("POST", "/v1/notes", (c) => {
  const key = c.req.headers["idempotency-key"];
  if (!key) return c.fail(400, "idempotency_key_required");
  if (S.idem.has(key)) return c.json(...S.idem.get(key));
  if (!c.body.title || !c.body.body) return c.fail(400, "bad_request");
  const i = c.body.item_id ? item(c.body.item_id) : null;
  const n = { id: "n" + ++S.seq, title: c.body.title, body: c.body.body, created_at: iso(), assistant: { id: "a_chat", name: "阿深", submitted_by_user: true }, origin: i ? { item_id: i.id, item_title: i.title, item_url: i.url, digest_day: null } : null, sources: [], asset_ids: [] };
  S.notes.unshift(n);
  if (i) S.queue = S.queue.filter((q) => q.item_id !== i.id);
  S.idem.set(key, [201, n]);
  c.json(201, n);
});
route("GET", "/v1/notes/:id", (c) => {
  const n = S.notes.find((x) => x.id === c.p.id);
  if (!n) return c.fail(404, "not_found");
  if ((c.req.headers.accept || "").includes("text/markdown")) {
    const src = (n.sources || []).map((s) => `- [${s.title}](${s.url})`).join("\n");
    return c.text(200, `# ${n.title}\n\n${n.body}\n${src ? "\n" + src + "\n" : ""}`);
  }
  c.json(200, n);
});

route("POST", "/v1/assets", (c) => {
  const { sha256, bytes, content_type } = c.body;
  if (!/^[0-9a-f]{64}$/.test(sha256 || "") || !(bytes > 0)) return c.fail(400, "bad_request");
  if (bytes > 3145728) return c.fail(413, "bad_request");
  const existing = [...S.assets.values()].find((a) => a.sha256 === sha256 && a.stored);
  if (existing) return c.json(200, { asset_id: existing.id, status: "stored" });
  const id = "as" + ++S.seq;
  S.assets.set(id, { id, sha256, bytes, content_type, stored: false, data: null });
  c.json(200, { asset_id: id, status: "upload", upload_url: `http://127.0.0.1:${PORT}/__upload/${id}?sig=fake`, expires_at: iso(-10 * MIN) });
});
route("PUT", "/__upload/:id", (c) => {
  const a = S.assets.get(c.p.id);
  if (!a) return c.fail(404, "not_found");
  a.data = c.raw;
  a.uploaded_type = c.req.headers["content-type"];
  c.empty(204);
}, true);
route("GET", "/__asset/:id", (c) => {
  const a = S.assets.get(c.p.id);
  if (!a?.data) return c.fail(404, "not_found");
  c.res.writeHead(200, { "content-type": a.content_type });
  c.res.end(a.data);
}, true);
route("POST", "/v1/assets/:id/complete", (c) => {
  const a = S.assets.get(c.p.id);
  if (!a?.data) return c.fail(409, "bad_request");
  const sha = crypto.createHash("sha256").update(a.data).digest("hex");
  if (sha !== a.sha256 || a.data.length !== a.bytes || a.uploaded_type !== a.content_type) return c.fail(415, "bad_request");
  a.stored = true;
  c.empty(204);
});
route("GET", "/v1/assets/:id", (c) => {
  const a = S.assets.get(c.p.id);
  if (!a?.stored) return c.fail(404, "not_found");
  c.json(200, { download_url: `http://127.0.0.1:${PORT}/__asset/${a.id}`, expires_at: iso(-5 * MIN), content_type: a.content_type, bytes: a.bytes });
});

route("GET", "/v1/status", (c) => c.json(200, status()));
route("GET", "/v1/calendar", (c) => c.json(200, calendar(c.q.get("month"))));
const settings = (c) => (c.device.tier === "manage" ? S.settings : { ...S.settings, calendar_image: { enabled: S.settings.calendar_image.enabled, url: null } });
route("GET", "/v1/settings", (c) => c.json(200, settings(c)));
route("PATCH", "/v1/settings", (c) => {
  const b = c.body;
  const allowed = ["rules", "expiry_options", "notify", "timezone", "lang", "roles", "calendar_image_enabled"];
  if (Object.keys(b).some((k) => !allowed.includes(k))) return c.fail(400, "bad_request");
  for (const k of ["rules", "expiry_options", "notify", "timezone", "lang"]) if (k in b) S.settings[k] = b[k];
  if (b.roles) Object.assign(S.settings.roles, b.roles);
  if ("calendar_image_enabled" in b) {
    S.settings.calendar_image.enabled = b.calendar_image_enabled;
    S.settings.calendar_image.url = b.calendar_image_enabled ? S.settings.calendar_image.url || `http://127.0.0.1:${PORT}/c/${crypto.randomBytes(12).toString("hex")}.svg` : null;
  }
  c.json(200, settings(c));
});
route("POST", "/v1/settings/calendar-image/rotate", (c) => {
  S.settings.calendar_image.url = `http://127.0.0.1:${PORT}/c/${crypto.randomBytes(12).toString("hex")}.svg`;
  c.json(200, settings(c));
});
route("GET", "/v1/assistants", (c) => c.json(200, { assistants: S.assistants, connect_url: "https://keepessence.app/mcp" }));
route("PATCH", "/v1/assistants/:id", (c) => {
  const a = S.assistants.find((x) => x.id === c.p.id);
  if (!a) return c.fail(404, "not_found");
  if (c.body.name) a.name = c.body.name;
  if (c.body.steps) a.steps = c.body.steps;
  c.json(200, a);
});
route("DELETE", "/v1/assistants/:id", (c) => {
  S.assistants = S.assistants.filter((a) => a.id !== c.p.id);
  S.devices = S.devices.filter((d) => d.id !== c.p.id);
  for (const k of Object.keys(S.settings.roles)) if (S.settings.roles[k] === c.p.id) S.settings.roles[k] = null;
  c.empty(204);
});

route("GET", "/__page/:n", (c) => {
  c.res.writeHead(200, { "content-type": "text/html; charset=utf-8" });
  c.res.end(`<!doctype html><meta name="viewport" content="width=device-width"><title>Share test ${c.p.n}</title><h1>A page made for the share test</h1><p>Invented content, page ${c.p.n}.</p>`);
}, true);
route("POST", "/__reset", (c) => (seed(), c.empty(204)), true);
route("GET", "/__state", (c) => c.json(200, { saved: S.saved, assets: [...S.assets.values()].map(({ data, ...a }) => ({ ...a, received: data?.length ?? 0 })), notes: S.notes.length, digests: S.digests.map((d) => ({ day: d.day, read: d.read })), queue: S.queue.map((q) => q.item_id), signals: S.items.filter((i) => i.signal).map((i) => [i.id, i.signal]) }), true);

const SAVE_TIER_OK = [/^\/v1\/devices\/me$/, /^\/v1\/items$/, /^\/v1\/assets/];

http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://127.0.0.1:${PORT}`);
  const raw = await readBody(req);
  for (const r of routes) {
    const m = req.method === r.method && url.pathname.match(r.re);
    if (!m) continue;
    const c = {
      req, res, raw, q: url.searchParams, lang: lang(req), p: Object.fromEntries(r.keys.map((k, i) => [k, decodeURIComponent(m[i + 1])])),
      json: (s, b) => send(res, s, b), text: (s, t) => send(res, s, t), empty: (s) => send(res, s), fail: (s, code, key) => fail(req, res, s, code, key),
    };
    try { c.body = raw.length && (req.headers["content-type"] || "").includes("json") ? JSON.parse(raw.toString("utf8")) : {}; } catch { return fail(req, res, 400, "bad_request"); }
    if (!r.open) {
      const cred = (req.headers.authorization || "").replace(/^Bearer /, "");
      c.device = S.devices.find((d) => d.id === S.credentials.get(cred));
      if (!c.device) return fail(req, res, 401, "unauthorized");
      c.device.last_used_at = iso();
      if (c.device.tier === "save" && !(SAVE_TIER_OK.some((x) => x.test(url.pathname)) && (req.method !== "GET" || url.pathname === "/v1/devices/me"))) return fail(req, res, 403, "forbidden");
    }
    console.log(req.method, url.pathname + url.search);
    return r.handler(c);
  }
  fail(req, res, 404, "not_found");
}).listen(PORT, "127.0.0.1", () => console.log(`fake core on http://127.0.0.1:${PORT}`));
