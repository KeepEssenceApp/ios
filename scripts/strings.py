#!/usr/bin/env python3
"""The interface strings, zh and en, and the String Catalog generated from them.

    python3 scripts/strings.py           write KeepCore/Sources/KeepCore/Resources/Localizable.xcstrings
    python3 scripts/strings.py --check   fail when the catalog is out of date, a key used in the code
                                         is missing, or a word the glossary bans appears

The words come from the spec's design/terms.md. Sentences that the table there does not have are
built from those words in plain wording. The sentences of saving (saved, duplicate, queued, failed,
the question about passwords) are not here: they come from the core (GET /v1/meta).
"""
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "KeepCore/Sources/KeepCore/Resources/Localizable.xcstrings"

# key, zh, en
S = [
    # the four entries
    ("tab.today", "今天", "Today"),
    ("tab.digest", "每日摘要", "Daily digest"),
    ("tab.notes", "笔记", "Notes"),
    ("tab.assistants", "助手设置", "Assistants"),
    # terms
    ("term.analysis", "解读", "Analysis"),
    ("term.assistant", "助手", "Assistant"),
    ("term.deep_dive", "深挖", "Deep dive"),
    ("term.deep_read", "精读", "Deep read"),
    ("term.original", "原文", "Original"),
    ("term.queue", "深挖队列", "Deep-dive queue"),
    ("term.unavailable", "没取到内容", "Content could not be fetched"),
    ("calendar", "月历", "Calendar"),
    ("field.summary", "内容概述", "Summary"),
    ("field.key_fact", "关键事实", "Key fact"),
    ("field.points", "要点", "Key points"),
    ("field.verdict", "判定", "Verdict"),
    ("field.related", "关联提示", "Related"),
    ("verdict.worth", "值得深挖", "Worth a deep dive"),
    ("verdict.good", "知道就行", "Good to know"),
    ("verdict.skip", "可以略过", "Skippable"),
    # actions
    ("action.save", "存入", "Save"),
    ("action.queue", "加入深挖队列", "Add to the deep-dive queue"),
    ("action.start_deep_dive", "开始深挖", "Start a deep dive"),
    ("action.not_interested", "不感兴趣", "Not interested"),
    ("action.seen", "看过了", "Seen"),
    ("action.restore", "挽回", "Restore"),
    ("action.delete", "删除", "Delete"),
    ("action.download", "下载", "Download"),
    ("action.share", "分享", "Share"),
    ("action.allow", "允许", "Allow"),
    ("action.refuse", "拒绝", "Refuse"),
    ("action.revoke", "撤销", "Revoke"),
    ("action.rename", "改名", "Rename"),
    ("action.copy", "复制", "Copy"),
    ("action.open", "打开", "Open"),
    ("action.paste", "粘贴", "Paste"),
    ("action.dismiss", "知道了", "OK"),
    # one sentence after an action
    ("said.queued", "已加入深挖队列", "Added to the deep-dive queue"),
    ("said.not_interested", "已标为不感兴趣", "Marked as not interested"),
    ("said.seen", "已标为看过了", "Marked as seen"),
    ("said.saved", "已存入", "Saved"),
    ("said.copied", "已复制", "Copied"),
    ("error.unreachable", "连不上服务器。", "The server cannot be reached."),
    # sign-in
    ("signin.email.prompt", "用受邀的邮箱登录。", "Sign in with your invited email address."),
    ("signin.email", "邮箱", "Email"),
    ("signin.send_code", "发验证码", "Send the code"),
    ("signin.code.prompt", "如果 %@ 在受邀名单里，6 位验证码已经发过去了。", "If %@ is invited, a 6-digit code is on its way."),
    ("signin.code", "6 位验证码", "6-digit code"),
    ("signin.other_email", "换一个邮箱", "Use another email"),
    ("signin.resend", "再发一次", "Send again"),
    ("signin.server", "服务器：%@", "Server: %@"),
    ("signin.server.bad", "服务器地址不对。", "That server address is not valid."),
    ("saveonly.sentence", "这台设备只能存入，看不到内容。在别的应用里点分享就能存入。",
     "This device can only save and cannot see any content. Share from another app to save."),
    # status bar
    ("status.working", "%lld 个助手在干活", "Assistants at work: %lld"),
    ("status.none_working", "没有助手在干活", "No assistant is at work"),
    ("status.last_seen", "%1$@ %2$@来过", "%1$@ came %2$@"),
    ("status.counts", "今天存入了 %1$lld 条，%2$lld 条在等", "Saved today: %1$lld · waiting: %2$lld"),
    ("status.oldest_deleted", "在等的条目里最早的一条 %@ 删除。", "The oldest waiting item is deleted on %@."),
    ("status.state.working", "在干活", "At work"),
    ("status.state.never", "还没来过", "Has not come yet"),
    ("status.state.came", "%@来过", "Came %@"),
    ("status.no_digest.not_yet_time", "今天的每日摘要还没到时间。", "Today's daily digest is not due yet."),
    ("status.no_digest.nothing_analysed", "今天还没有解读，所以没有每日摘要。", "Nothing was analysed today, so there is no daily digest."),
    ("status.no_digest.no_assistant", "没有助手出每日摘要。", "No assistant writes the daily digest."),
    ("status.no_digest.waiting", "每日摘要在等助手来。", "The daily digest is waiting for an assistant."),
    # today
    ("today.all_handled", "今天的都处理完了。", "Everything for today is handled."),
    ("today.queued", "%lld 条排着队，联网后自动存入。", "Queued: %lld. They will be saved when you are back online."),
    ("today.rest", "其余的 · %lld", "The rest · %lld"),
    ("today.waiting", "还没有解读的条目 · %lld", "Items without an analysis yet · %lld"),
    # item
    ("item.analysed_by", "交给哪个助手", "Given to"),
    ("item.kept_for", "保留多久", "Kept for"),
    ("item.days_left", "还剩 %lld 天", "%lld days left"),
    ("item.days", "%lld 天", "%lld days"),
    # One control for how long an item is kept: the options, then "Never delete" last. 收藏 extends
    # an item's life to never expire; it is not a save button, so it is never a bare "Keep".
    ("item.never_delete", "收藏（不过期）", "Never delete"),
    ("item.end_date", "改回有期限", "Give it an end date"),
    ("item.never_deleted", "收藏了，不过期", "Never deleted"),
    ("item.not_assigned", "还没分派", "Not assigned yet"),
    # QA #32: how long an item is kept is decided when it is sorted
    ("item.decided_when_sorted", "初筛时定", "Decided when it is sorted"),
    ("item.undecided_hint", "你不选的话，保留多久在初筛时定：%lld 天，或者按你的规则。", "Unless you choose, how long this is kept is decided when the item is sorted: %lld days, or what your rules say."),
    ("item.set_by_sorting", "初筛时定的。另选一个就改。", "Set when the item was sorted. Choose another to change it."),
    ("item.said.days", "保留 %1$lld 天，到 %2$@ 删除。", "Kept for %1$lld days, until %2$@."),
    ("item.said.never", "收藏了，不过期。", "Never deleted."),
    ("item.said.changed", "已保存。", "Changes saved."),
    ("item.delete.confirm", "删除后立刻消失，不能恢复。", "It disappears at once and cannot be restored."),
    # digest
    ("digest.counts", "存入了 %1$lld 条，%2$lld 条值得深挖", "%1$lld saved, %2$lld worth a deep dive"),
    ("digest.summary", "总结", "Summary"),
    ("digest.worth", "值得深挖的", "Worth a deep dive"),
    ("digest.rest", "其余的 · %lld", "The rest · %lld"),
    ("digest.question", "睡前一问", "A question to sleep on"),
    ("digest.read", "读了，晚安", "Read. Good night"),
    ("digest.read_done", "读了", "Read"),
    ("digest.unread", "还没读", "Not read yet"),
    # No daily digest: when it comes, what it needs, where today's analyses are meanwhile.
    ("digest.none", "还没有每日摘要。每天一份，当天至少有一条解读好的条目时，在 21:00（%@）之后出；漏掉的一天并进下一份。",
     "No daily digest yet. There is one a day, written after 21:00 (%@) when the day has at least one analysed item; a missed day is folded into the next one."),
    ("digest.none.not_yet_time", "今天的每日摘要在 21:00（%@）之后出。它需要今天至少有一条解读好的条目。在那之前，今天的解读都在「今天」里。",
     "Today's daily digest is written after 21:00 (%@). It needs at least one analysed item from today. Until then, today's analyses are in Today."),
    ("digest.none.nothing_analysed", "今天还没有每日摘要：它需要至少一条解读好的条目，而今天的条目都还没解读。有了解读，每日摘要在 21:00（%@）之后出。",
     "No daily digest today yet: it needs at least one analysed item, and none of today's items is analysed. Once one is, the digest is written after 21:00 (%@)."),
    ("digest.none.no_assistant", "没有指定出每日摘要的助手，所以不会有每日摘要。今天的解读都在「今天」里。",
     "No assistant is set to write the daily digest, so none is written. Today's analyses are in Today."),
    ("digest.none.waiting", "今天的每日摘要该出了：助手下次来时就出。在那之前，今天的解读都在「今天」里。",
     "Today's daily digest is due: it is written when the assistant next comes. Until then, today's analyses are in Today."),
    # notes and the queue
    ("notes.find", "快速查找", "Quick find"),
    ("notes.none", "还没有笔记。深挖之后存回来的笔记在这里。", "No notes yet. Notes saved from a deep dive appear here."),
    ("notes.find.none", "没有找到笔记。", "No note matches."),
    ("note.origin", "出处", "From"),
    ("note.sources", "来源", "Sources"),
    ("note.pasted", "由用户交回", "Pasted back by you"),
    ("paste.title", "标题", "Title"),
    ("queue.waiting", "等精读", "Waiting for a deep read"),
    ("queue.reading", "精读中", "Being read"),
    ("queue.ready", "精读好了", "Deep read ready"),
    ("queue.no_assistant", "没有精读助手", "No assistant does deep reads"),
    ("queue.see_deep_read", "看精读", "See the deep read"),
    ("queue.paste_back", "把结果贴回来", "Paste the result back"),
    ("queue.remove", "移出队列", "Remove from the queue"),
    ("queue.went", "%@去过", "You went %@"),
    ("deepdive.note", "开场话不带内容，助手自己来取。", "The opening line carries no content. The assistant fetches it."),
    ("deepread.read", "读出来的", "What it says"),
    ("deepread.found", "另外查到的", "What else was found"),
    ("deepread.questions", "可以接着问的", "What to ask next"),
    ("calendar.counts", "存入 %1$lld 条 · 每日摘要 %2$lld 份 · 读了 %3$lld 份 · 笔记 %4$lld 篇",
     "%1$lld saved · %2$lld digests · %3$lld read · %4$lld notes"),
    # assistants
    ("assistants.connect", "接入一个助手", "Connect an assistant"),
    ("assistants.rules", "规则", "Rules"),
    ("assistants.devices", "设备", "Devices"),
    ("assistants.my_calendar", "我的月历", "My calendar"),
    ("assistants.notifications", "通知", "Notifications"),
    ("assistants.account", "账户", "Account"),
    ("assistants.none", "还没有助手。", "No assistants yet."),
    ("assistant.built_in", "内置助手", "Built-in assistant"),
    ("assistant.scheduled", "定时型", "Scheduled"),
    ("assistant.chat", "对话型", "Chat"),
    ("assistant.steps", "它能做的步骤", "Steps it may do"),
    ("assistant.runs_at", "内容会被送到：%@", "Content is sent to: %@"),
    ("assistant.revoke.confirm", "撤销 %@？立即生效，它认领中的活会放回。", "Revoke %@? It takes effect at once and its claimed work is released."),
    ("roles.title", "谁做哪一步", "Who does which step"),
    ("roles.analysis", "缺省解读助手", "Default for analysis"),
    ("roles.digest", "汇总助手", "Writes the daily digest"),
    ("roles.deep_read", "精读助手", "Does deep reads"),
    ("roles.deep_dive", "缺省深挖助手", "Default for deep dives"),
    ("roles.nobody", "无", "Nobody"),
    ("step.triage", "初筛", "Triage"),
    # connect
    ("connect.intro", "把接入地址填进助手那边，它会打开 KeepEssence 的允许页，你点「允许」。",
     "Enter the connect address in the assistant. It opens the KeepEssence allow page, and you press Allow."),
    ("connect.address", "接入地址", "Connect address"),
    ("connect.not_credential", "这个地址不是凭据，可以复制。", "This address is not a credential. It can be copied."),
    ("connect.content_goes", "接入之后，内容会被送到这个助手运行的地方。", "Once connected, your content is sent to where that assistant runs."),
    ("connect.pick", "选一个产品", "Pick a product"),
    ("connect.own", "自己部署的 agent", "Your own agent"),
    ("connect.unverified_list", "待验证：%@。", "Not verified yet: %@."),
    ("connect.claude.kind", "对话型：只做深挖", "Chat: deep dives only"),
    ("connect.claude.1", "打开 Claude 的 Connectors，点 Add → Add custom connector。", "Open Connectors in Claude and choose Add → Add custom connector."),
    ("connect.claude.2", "名字填 KeepEssence，地址粘贴接入地址，点 Continue。", "Name it KeepEssence, paste the connect address, and choose Continue."),
    ("connect.claude.3", "认证保持它自动检测到的选项，点 Add，再点 Connect。", "Keep the authentication it detects, choose Add, then Connect."),
    ("connect.claude.4", "浏览器打开 KeepEssence 的允许页，点「允许」。", "The browser opens the KeepEssence allow page. Press Allow."),
    ("connect.claude.note", "各套餐都能接；免费套餐只能有一个自定义连接器。Claude 第一次存回笔记时会问你是否允许。",
     "Every plan can connect; the free plan allows one custom connector. Claude asks you the first time it saves a note."),
    ("connect.chatgpt.kind", "对话型：只做深挖", "Chat: deep dives only"),
    ("connect.chatgpt.1", "在电脑上打开 chatgpt.com/plugins，点 + → Add custom MCP server。", "On a computer, open chatgpt.com/plugins and choose + → Add custom MCP server."),
    ("connect.chatgpt.2", "名字填 KeepEssence，Server URL 粘贴接入地址，认证选 OAuth。", "Name it KeepEssence, paste the connect address as the Server URL, and choose OAuth."),
    ("connect.chatgpt.3", "看过风险提示后确认，点 Create as a plugin，再安装它。", "Read the risk notice and confirm, choose Create as a plugin, then install it."),
    ("connect.chatgpt.4", "浏览器打开 KeepEssence 的允许页，点「允许」。", "The browser opens the KeepEssence allow page. Press Allow."),
    ("connect.chatgpt.note", "只能在网页上接和用，手机上不行。个人套餐只能读：聊完后回到深挖队列，点「把结果贴回来」。",
     "It connects and works on the web only, not on a phone. Personal plans can only read: afterwards, come back to the deep-dive queue and paste the result back."),
    ("connect.gemini.kind", "对话型：只做深挖", "Chat: deep dives only"),
    ("connect.gemini.1", "在电脑上打开 gemini.google.com，在它的菜单里进 Connected Apps。", "On a computer, open gemini.google.com and go to Connected Apps in its menu."),
    ("connect.gemini.2", "在 Custom apps 下点 Add a custom app，粘贴接入地址，点 Next。", "Under Custom apps choose Add a custom app, paste the connect address, and choose Next."),
    ("connect.gemini.3", "浏览器打开 KeepEssence 的允许页，点「允许」。", "The browser opens the KeepEssence allow page. Press Allow."),
    ("connect.gemini.4", "之后手机和网页都能用：对话里输入 @ 选 KeepEssence。", "After that it works on the phone and the web: type @ in a conversation and pick KeepEssence."),
    ("connect.gemini.note", "目前只限美国、18 岁以上、个人 Google 账号、英文，并且要开着 History。存回笔记时 Gemini 每次都会让你确认。",
     "For now: United States only, 18 or older, a personal Google account, English, with History on. Gemini asks you every time it saves a note."),
    ("connect.own.kind", "定时型：解读、汇总、深挖", "Scheduled: analysis, daily digest, deep dives"),
    ("connect.own.1", "在它的 MCP 配置里加一个远程服务器，地址填接入地址，传输选 Streamable HTTP，认证选 OAuth。",
     "Add a remote server to its MCP configuration: the connect address, Streamable HTTP transport, OAuth authentication."),
    ("connect.own.2", "它打开 KeepEssence 的允许页，点「允许」。", "It opens the KeepEssence allow page. Press Allow."),
    ("connect.own.3", "给它设一个定时任务：每次来先问有什么活，认领，做完交回。", "Give it a timetable: each time it asks what work there is, claims it, and hands it back when done."),
    ("connect.own.note", "它要支持 MCP 和 OAuth。", "It needs to support MCP and OAuth."),
    # rules
    ("rules.intro", "写给分派助手的话：什么样的条目交给谁、保留多久。", "What you tell the dispatch assistant: which items go to whom, and how long they are kept."),
    ("rules.expiry", "保留多久的档位（天）", "Options for how long items are kept (days)"),
    ("rules.expiry.intro", "最多 6 个，每个 1 到 365 天。", "Up to 6, each from 1 to 365 days."),
    ("rules.expiry.bad", "档位要 1 到 6 个，每个 1 到 365 天。", "Give 1 to 6 options, each from 1 to 365 days."),
    # devices
    ("devices.approve", "允许新设备接入", "Allow a new device"),
    ("devices.approve.intro", "输入新设备上显示的短码。", "Type the short code the new device shows."),
    ("devices.check", "核对", "Check"),
    ("devices.asks", "%@ 想接入", "%@ asks to connect"),
    ("devices.compare", "核对这个短码和那台设备上显示的一样，再点允许。", "Check that this code is the one shown on that device before you allow it."),
    ("devices.tier", "权限", "Tier"),
    ("devices.this", "这台设备", "This device"),
    ("devices.last_used", "%@用过", "Used %@"),
    ("devices.never_used", "还没用过", "Not used yet"),
    ("devices.revoke.confirm", "撤销 %@？立即生效。", "Revoke %@? It takes effect at once."),
    ("tier.save", "只存入", "Save only"),
    ("tier.read", "读", "Read"),
    ("tier.manage", "管理", "Manage"),
    ("tier.save.note", "只能存入，看不到任何内容。", "Can save. Sees no content."),
    ("tier.read.note", "能读，能对解读和每日摘要做动作。", "Can read and act on analyses and daily digests."),
    ("tier.manage.note", "还能管理助手、规则和设备。", "Can also manage assistants, rules and devices."),
    # my calendar
    ("mycalendar.intro", "给月历开一个公开的图片地址，可以贴到个人主页或文档里。图里只有圆点和数字，没有任何内容和身份信息。",
     "Give your calendar a public image address to put on a profile page or in a document. The image has only dots and numbers: no content and nothing that identifies you."),
    ("mycalendar.public", "公开的图片地址", "Public image address"),
    ("mycalendar.rotate", "换一个地址", "Replace the address"),
    ("mycalendar.rotate.confirm", "旧地址会立刻失效。", "The old address stops working at once."),
    # notifications
    ("notify.what", "只有一种通知：解读好了，或精读好了。", "There is one kind of notification: an analysis is ready, or a deep read is ready."),
    ("notify.me", "通知我", "Notify me"),
    ("notify.not_here", "这个版本的 iPhone App 还收不到系统通知。上面的开关对你的其他设备生效。",
     "This version of the iPhone app cannot receive system notifications. The switch above applies to your other devices."),
    # account
    ("account.language", "语言", "Language"),
    ("account.language.system", "跟随系统", "Follows the system"),
    ("account.timezone", "时区", "Time zone"),
    ("account.timezone.use", "改用这台设备的时区：%@", "Use this device's time zone: %@"),
    ("account.server", "服务器：%@", "Server: %@"),
    ("account.sign_out", "退出", "Sign out"),
    ("account.sign_out.confirm", "退出会撤销这台设备。", "Signing out revokes this device."),
    # share extension
    ("share.sign_in_first", "先打开 KeepEssence 登录。", "Open KeepEssence and sign in first."),
    ("share.dont_save", "不存入", "Don't save"),
    ("share.nothing", "没有能存入的内容", "there was nothing to save"),
    # What the share sheet says about a picture (QA #87). A static line, not part of the sentence of a save;
    # and the sentences of the pictures that were not saved as shared. The number is the limit the code uses, in MiB
    # (3,145,728 bytes is 3 MiB; not written MB).
    ("share.image_note", "图片会先在手机上处理再存入，原图不上传。", "Images are processed on your phone before saving; the original isn't uploaded."),
    ("share.image_only_link", "图片没能存入，只存入了链接。", "The image couldn't be saved; only the link was."),
    ("share.image_only_text", "图片没能存入，只存入了文字。", "The image couldn't be saved; only the text was."),
    # The same two, for a save that is still waiting in the queue. Said only as far as the phone knows: the picture
    # will not be saved, and what is in the queue is the link or the text. Whether the core saves it later is the
    # core's answer to give then, so it is not promised here (Project 7213889512, Marketing 7213864126).
    ("share.image_only_link_queued", "图片不会存入，排队的只有链接。", "The image won't be saved; only the link is queued."),
    ("share.image_only_text_queued", "图片不会存入，排队的只有文字。", "The image won't be saved; only the text is queued."),
    ("share.image_too_large", "图片太大，压缩后仍超过 %lld MiB，没有存入。", "This image is too large even after compression (over %lld MiB), so it wasn't saved."),
    ("share.image_unreadable", "这张图片读不出来，没有存入。", "This image couldn't be read, so it wasn't saved."),
    ("share.image_failed", "这张图片没能存入。", "This image couldn't be saved."),
    ("share.gif_one_frame", "动图只保留了一帧。", "Only one frame of the animation was kept."),
]

# Words the glossary and design/terms.md ban from the interface, and 标签 / tag(s): the user is not
# told that tags exist (rule A6, Cheney 2026-11-26).
BANNED_ZH = ["书签", "知识库", "存档", "搜索", "分类", "文件夹", "主题", "喜欢", "首页", "设置", "钥匙", "暂存", "攒存", "标签"]
BANNED_EN = ["bookmark", "knowledge base", "archive", "search", "category", "folder", "topic", "like", "home", "settings", "token", "api key", "tag", "tags"]
ALLOWED_ZH = {"tab.assistants": ["设置"]}   # 「助手设置」 is the entry's own name in the glossary


def catalog():
    strings = {}
    for key, zh, en in S:
        strings[key] = {
            "extractionState": "manual",
            "localizations": {
                "en": {"stringUnit": {"state": "translated", "value": en}},
                "zh-Hans": {"stringUnit": {"state": "translated", "value": zh}},
            },
        }
    return json.dumps({"sourceLanguage": "en", "strings": dict(sorted(strings.items())), "version": "1.0"},
                      ensure_ascii=False, indent=2) + "\n"


def problems():
    out = []
    keys = [k for k, _, _ in S]
    if len(keys) != len(set(keys)):
        out.append("duplicate keys: %s" % sorted({k for k in keys if keys.count(k) > 1}))
    used = set()
    for folder in ("App", "ShareExtension", "KeepCore/Sources"):
        for f in (ROOT / folder).rglob("*.swift"):
            text = f.read_text()
            used |= set(re.findall(r'\bL\("([^"]+)"', text))
            # A key chosen in code and passed to L() later is a plain string literal there.
            used |= set(re.findall(r'"([a-z0-9_.]+)"', text)) & set(keys)
    for k in sorted(used):
        if "\\(" in k:      # built at run time: connect.<product>.<n>
            continue
        if k not in keys:
            out.append("used in the code but not in the table: %s" % k)
    for k in sorted(set(keys) - used):
        if not k.startswith("connect."):
            out.append("in the table but not used: %s" % k)
    for key, zh, en in S:
        for w in BANNED_ZH:
            if w in zh and w not in ALLOWED_ZH.get(key, []):
                out.append("banned word %s in %s (zh)" % (w, key))
        for w in BANNED_EN:
            if re.search(r"\b%s\b" % re.escape(w), en.lower()):
                out.append("banned word %s in %s (en)" % (w, key))
        if re.findall(r"%(?:\d\$)?(?:lld|@)", zh).__len__() != re.findall(r"%(?:\d\$)?(?:lld|@)", en).__len__():
            out.append("placeholders differ in %s" % key)
    return out


if __name__ == "__main__":
    text = catalog()
    if "--check" in sys.argv:
        bad = problems()
        if not OUT.exists() or OUT.read_text() != text:
            bad.append("Localizable.xcstrings is out of date: run python3 scripts/strings.py")
        if bad:
            print("\n".join(bad))
            sys.exit(1)
        print("strings: %d keys, zh and en, catalog up to date" % len(S))
    else:
        OUT.write_text(text)
        print("wrote %s (%d keys)" % (OUT, len(S)))
