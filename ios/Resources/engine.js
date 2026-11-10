/*
 * yuedu-lite 设备端引擎
 *
 * 运行在 iOS 9 的 JavaScriptCore 中，所有抓取、解析、存储、WebDAV 同步都在手机内完成。
 * 依赖：
 *   - engine-core.js 提供 YLcore（DOM / CSS / 规则求值）
 *   - 原生桥 YLNative 提供网络、文件、编码、ZIP
 *
 * 对外只有一个函数：YL.handle(action, paramsJSON) -> JSON string
 */
var YL = (function () {
    "use strict";

    var core = YLcore;
    var nat = YLNative;

    var UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 " +
        "(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36";

    core.setEnv({
        ajax: function (url) {
            try { return http(url, {}).text || ""; } catch (e) { return ""; }
        },
        post: function (url, body, headers) {
            try {
                return http(url, {
                    method: "POST",
                    body: body === null || body === undefined ? "" : String(body),
                    headers: headers || {}
                }).text || "";
            } catch (e) {
                return "";
            }
        },
        base64Encode: function (text) { return nat.base64Encode(String(text)); },
        base64Decode: function (text) { return nat.base64Decode(String(text)); },
        md5Encode: function (text) { return nat.md5(String(text)); }
    });

    var PROPFIND_BODY =
        "<?xml version=\"1.0\" encoding=\"utf-8\"?>" +
        "<d:propfind xmlns:d=\"DAV:\"><d:prop>" +
        "<d:displayname/><d:resourcetype/><d:getcontentlength/>" +
        "<d:getlastmodified/></d:prop></d:propfind>";

    var loaded = false;
    var state = null;
    var textCache = {};
    var textCacheKeys = [];
    var lastAutoPush = 0;
    var autoPushScheduled = false;
    var autoPushFailAt = 0;
    var autoPushRetryDelay = 60;
    var pendingPush = {};

    // iPhone 4S 内存有限：大于 12 MB 的 TXT/EPUB 直接拒绝，避免解码时被系统杀掉
    var MAX_BOOK_BYTES = 12 * 1024 * 1024;

    // ---------------------------------------------------------------- utils --

    function trim(text) {
        return core.trim(text);
    }

    function isArray(value) {
        return Object.prototype.toString.call(value) === "[object Array]";
    }

    function isObject(value) {
        return value !== null && typeof value === "object" && !isArray(value);
    }

    function has(obj, key) {
        return Object.prototype.hasOwnProperty.call(obj, key);
    }

    function copy(obj) {
        var out = {};
        if (!obj) { return out; }
        for (var key in obj) {
            if (has(obj, key)) { out[key] = obj[key]; }
        }
        return out;
    }

    function merge(base, extra) {
        var out = copy(base);
        if (extra) {
            for (var key in extra) {
                if (has(extra, key)) { out[key] = extra[key]; }
            }
        }
        return out;
    }

    function now() {
        return nat.now ? nat.now() : new Date().getTime();
    }

    function parseJSON(text, def) {
        if (text === null || text === undefined) { return def; }
        try {
            var value = JSON.parse(String(text));
            return value === null || value === undefined ? def : value;
        } catch (e) {
            return def;
        }
    }

    function errorText(error) {
        if (!error) { return "未知错误"; }
        return error.message || String(error);
    }

    function intValue(value, def) {
        var n = parseInt(value, 10);
        return isNaN(n) ? def : n;
    }

    function md5(text) {
        return nat.md5(String(text));
    }

    function simpleHash(text) {
        var hash = 5381;
        text = String(text);
        for (var i = 0; i < text.length; i += 1) {
            hash = ((hash << 5) + hash) + text.charCodeAt(i);
            hash = hash & 0x7fffffff;
        }
        return hash.toString(16);
    }

    function digest(text) {
        var value = nat.md5 ? md5(text) : simpleHash(text);
        return value || simpleHash(text);
    }

    // ------------------------------------------------------------------ root --

    function root() {
        var docs = nat.docsDir ? nat.docsDir() : "";
        return String(docs).replace(/\/+$/, "") + "/yuedu";
    }

    // 书籍、字体、收件箱可以放到用户自定义目录；config/shelf/progress 等状态
    // 仍然固定在 Documents/yuedu，避免换目录时把同步状态弄丢。
    function nativeDir(name, fallback) {
        try {
            if (nat[name]) {
                var value = String(nat[name]() || "").replace(/\/+$/, "");
                if (value) { return value; }
            }
        } catch (e) { /* 老版本原生层没有这个接口 */ }
        return root() + "/" + fallback;
    }

    function booksDir() {
        return nativeDir("booksDir", "books");
    }

    function fontsDir() {
        return nativeDir("fontsDir", "fonts");
    }

    function inboxDir() {
        return nativeDir("inboxDir", "inbox");
    }

    function coversDir() {
        return nativeDir("coversDir", "covers");
    }

    function storeRoot() {
        return nat.storeRoot ? String(nat.storeRoot() || "") : root();
    }

    function pathOf(name) {
        return root() + "/" + name;
    }

    function ensureDirs() {
        var base = root();
        nat.mkdir(base);
        nat.mkdir(booksDir());
        nat.mkdir(fontsDir());
        nat.mkdir(inboxDir());
        nat.mkdir(coversDir());
        nat.mkdir(base + "/cache");
    }

    function readText(path) {
        try {
            return nat.readText(path) || "";
        } catch (e) {
            return "";
        }
    }

    function writeText(path, text) {
        if (!nat.writeText(path, String(text))) {
            throw new Error("写入失败: " + path);
        }
    }

    function readJSON(path, def) {
        var raw = readText(path);
        if (!raw) { return def; }
        return parseJSON(raw, def);
    }

    function writeJSON(path, value) {
        writeText(path, JSON.stringify(value, null, 2));
    }

    function defaultConfig() {
        return {
            autoPush: true,
            fontSize: 18,
            webdav: { url: "", username: "", password: "", dir: "legado" }
        };
    }

    function normalizeState() {
        if (!isObject(state.config)) { state.config = defaultConfig(); }
        if (!isObject(state.config.webdav)) { state.config.webdav = defaultConfig().webdav; }
        // 安卓版“阅读”默认同步目录是 legado，旧版本这里默认根目录，
        // 升级后统一迁移过去，bookProgress/ 才能对上。
        if (typeof state.config.webdav.dir !== "string" ||
            !trim(state.config.webdav.dir)) {
            state.config.webdav.dir = "legado";
        }
        if (!isArray(state.sources)) { state.sources = []; }
        if (!isObject(state.shelf) || !isObject(state.shelf.books)) {
            state.shelf = { books: {} };
        }
        if (!isObject(state.progress) || !isObject(state.progress.books)) {
            state.progress = { books: {} };
        }
        if (!isObject(state.local)) { state.local = {}; }
        // 书签按书存放：{ 书key: [{index, pos, title, snippet, time}] }
        if (!isObject(state.bookmarks)) { state.bookmarks = {}; }
        // 记录上次拉取时每个进度文件的“修改时间|大小”，没变就不再下载，
        // 这样 iPhone 4S 上每次同步通常只剩一次 PROPFIND。
        if (!isObject(state.config.progressCache)) {
            state.config.progressCache = {};
        }
        // 阅读时长统计：本机累计 + 其他设备（readStats.json 按设备分桶）
        if (!intValue(state.config.readSeconds, 0)) {
            state.config.readSeconds = 0;
        }
        if (!isObject(state.config.readStatsDevices)) {
            state.config.readStatsDevices = {};
        }
        if (typeof state.config.deviceId !== "string" || !state.config.deviceId) {
            state.config.deviceId = "dev-" + digest(String(now()) + "\n" +
                String(Math.random ? Math.random() : now())).slice(0, 12);
        }
        migrateReadStats();
    }

    function loadState() {
        if (loaded) { return state; }
        ensureDirs();
        state = {
            config: readJSON(pathOf("config.json"), defaultConfig()),
            sources: readJSON(pathOf("sources.json"), []),
            shelf: readJSON(pathOf("shelf.json"), { books: {} }),
            progress: readJSON(pathOf("progress.json"), { books: {} }),
            bookmarks: readJSON(pathOf("bookmarks.json"), {}),
            local: readJSON(pathOf("local.json"), {})
        };
        normalizeState();
        loaded = true;
        repairLocalPaths();
        repairLocalCovers();
        repairLocalIntros();
        pruneCacheIfNeeded();
        return state;
    }

    function saveConfig() {
        writeJSON(pathOf("config.json"), state.config);
    }

    function saveShelf() {
        writeJSON(pathOf("shelf.json"), state.shelf);
    }

    function saveProgress() {
        writeJSON(pathOf("progress.json"), state.progress);
    }

    function saveSources() {
        writeJSON(pathOf("sources.json"), state.sources);
    }

    function saveLocal() {
        writeJSON(pathOf("local.json"), state.local);
    }

    function saveBookmarks() {
        writeJSON(pathOf("bookmarks.json"), state.bookmarks || {});
    }

    // ---------------------------------------------------------------- bookmarks --

    function bookmarkList(key) {
        var list = (state.bookmarks || {})[key];
        if (!isArray(list)) { return []; }
        var out = [];
        for (var i = 0; i < list.length; i += 1) { out.push(copy(list[i])); }
        return out;
    }

    function bookmarkAdd(params) {
        var key = trim(params.key || "");
        if (!key) { throw new Error("缺少 key"); }
        var list = bookmarkList(key);
        var item = {
            index: intValue(params.index, 0),
            pos: intValue(params.pos, 0),
            title: trim(params.title || ""),
            snippet: trim(params.snippet || "").slice(0, 60),
            time: intValue(params.time, now())
        };
        // 同一位置（±30 字）已有书签就替换，避免连点产生重复
        for (var i = list.length - 1; i >= 0; i -= 1) {
            if (list[i].index === item.index &&
                Math.abs(intValue(list[i].pos, 0) - item.pos) < 30) {
                list.splice(i, 1);
            }
        }
        list.push(item);
        list.sort(function (a, b) {
            if (a.index !== b.index) { return a.index - b.index; }
            return a.pos - b.pos;
        });
        state.bookmarks[key] = list;
        saveBookmarks();
        return copy(item);
    }

    function bookmarkRemove(params) {
        var key = trim(params.key || "");
        var time = intValue(params.time, 0);
        var list = bookmarkList(key);
        var next = [];
        for (var i = 0; i < list.length; i += 1) {
            if (intValue(list[i].time, 0) !== time) { next.push(list[i]); }
        }
        state.bookmarks[key] = next;
        saveBookmarks();
        return { ok: true, count: next.length };
    }

    function bookmarkClear(params) {
        var key = trim(params.key || "");
        if (key) {
            delete state.bookmarks[key];
        } else {
            state.bookmarks = {};
        }
        saveBookmarks();
        return { ok: true };
    }

    // 用户改过保存目录、或旧版本把书放在 Documents/yuedu/books 时，
    // local.json 里的绝对路径可能已经失效。按文件名到新目录里找一次。
    function repairLocalPaths() {
        if (!nat.exists) { return; }
        var dir = booksDir().replace(/\/+$/, "");
        var coverDir = coversDir().replace(/\/+$/, "");
        var changed = false;
        for (var key in (state.local || {})) {
            if (!has(state.local, key)) { continue; }
            var meta = state.local[key];
            if (!meta) { continue; }
            if (meta.path && !nat.exists(meta.path)) {
                var candidate = dir + "/" + localName(meta.path);
                if (nat.exists(candidate)) {
                    meta.path = candidate;
                    changed = true;
                }
            }
            if (meta.coverPath && !nat.exists(meta.coverPath)) {
                var cover = coverDir + "/" + localName(meta.coverPath);
                if (nat.exists(cover)) {
                    meta.coverPath = cover;
                    changed = true;
                }
            }
        }
        if (changed) { saveLocal(); }
    }

    function remapLocalPaths(oldBooks, newBooks) {
        oldBooks = String(oldBooks || "").replace(/\/+$/, "");
        newBooks = String(newBooks || "").replace(/\/+$/, "");
        if (!oldBooks || !newBooks || oldBooks === newBooks) { return; }
        var prefix = oldBooks + "/";
        var oldRoot = oldBooks.replace(/\/[^\/]*$/, "");
        var newRoot = newBooks.replace(/\/[^\/]*$/, "");
        var coverPrefix = oldRoot + "/covers/";
        var coverDir = coversDir().replace(/\/+$/, "");
        var changed = false;
        for (var key in (state.local || {})) {
            if (!has(state.local, key)) { continue; }
            var meta = state.local[key];
            if (!meta) { continue; }
            if (meta.path) {
                if (meta.path.indexOf(prefix) === 0) {
                    meta.path = newBooks + "/" + meta.path.slice(prefix.length);
                    changed = true;
                } else if (nat.exists && !nat.exists(meta.path)) {
                    var candidate = newBooks + "/" + localName(meta.path);
                    if (nat.exists(candidate)) {
                        meta.path = candidate;
                        changed = true;
                    }
                }
            }
            if (meta.coverPath) {
                if (meta.coverPath.indexOf(coverPrefix) === 0) {
                    meta.coverPath = coverDir + "/" +
                        meta.coverPath.slice(coverPrefix.length);
                    changed = true;
                } else if (nat.exists && !nat.exists(meta.coverPath)) {
                    var cover = coverDir + "/" + localName(meta.coverPath);
                    if (nat.exists(cover)) {
                        meta.coverPath = cover;
                        changed = true;
                    }
                }
            }
        }
        if (changed) { saveLocal(); }
    }

    // --------------------------------------------------------------- network --

    function http(url, options) {
        options = options || {};
        var headers = {};
        var source = options.headers || {};
        for (var key in source) {
            if (has(source, key)) { headers[key] = String(source[key]); }
        }
        var body = options.body;
        if (body !== null && body !== undefined && typeof body === "object") {
            body = JSON.stringify(body);
        }
        var request = {
            method: String(options.method || "GET").toUpperCase(),
            headers: headers,
            body: body === undefined || body === null ? null : String(body),
            binary: !!options.binary,
            timeout: options.timeout || 30
        };
        var raw = nat.fetch(String(url), JSON.stringify(request));
        var res = parseJSON(raw, null);
        if (!res) {
            throw new Error("网络返回无法解析");
        }
        if (res.ok !== true) {
            throw new Error(res.error || "网络请求失败");
        }
        return res;
    }

    function absolute(url, base) {
        return core.absUrl(url, base);
    }

    // ----------------------------------------------------------- source rules --

    function sourceHeaders(data) {
        var raw = data.header;
        if (raw === undefined || raw === null) { raw = data.headers; }
        var value = raw;
        if (typeof raw === "string") {
            value = parseJSON(raw, {});
        }
        var out = {};
        if (!isObject(value)) { return out; }
        for (var key in value) {
            if (has(value, key)) { out[String(key)] = String(value[key]); }
        }
        return out;
    }

    function Source(data) {
        this.data = data || {};
        this.url = trim(this.data.bookSourceUrl || "").replace(/\/+$/, "");
        this.name = this.data.bookSourceName || this.url || "未命名书源";
    }

    Source.prototype.ctx = function (key, page) {
        return {
            baseUrl: this.url,
            sourceUrl: this.url,
            key: key === undefined ? "" : key,
            page: page === undefined ? 1 : page
        };
    };

    Source.prototype.fetch = function (url, options) {
        options = options || {};
        var headers = {
            "User-Agent": UA,
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.6"
        };
        headers = merge(headers, sourceHeaders(this.data));
        headers = merge(headers, options.headers);
        var res = http(url, {
            method: options.method || "GET",
            headers: headers,
            body: options.body,
            timeout: options.timeout || 30
        });
        return res.text === undefined || res.text === null ? "" : res.text;
    };

    function toValue(text) {
        var stripped = trim(text);
        if (!stripped) { return core.parseHTML(""); }
        var first = stripped.charAt(0);
        if (first === "{" || first === "[") {
            var parsed = parseJSON(stripped, undefined);
            if (parsed !== undefined) { return parsed; }
        }
        return core.parseHTML(text);
    }

    function splitUrlOptions(template) {
        var opts = {};
        template = trim(template);
        var match = /,\s*(\{[\s\S]*\})\s*$/.exec(template);
        if (match) {
            var parsed = parseJSON(match[1], null);
            if (isObject(parsed)) {
                opts = parsed;
                template = trim(template.slice(0, match.index));
            }
        }
        return { template: template, opts: opts };
    }

    function buildUrl(source, raw, key, page) {
        var parts = splitUrlOptions(raw);
        var template = parts.template;
        if (!template) { return { url: "", opts: parts.opts }; }
        var url = template.replace(/\{\{key\}\}/g, encodeURIComponent(key === undefined ? "" : key))
            .replace(/\{\{page\}\}/g, String(page === undefined ? 1 : page));
        if (url.indexOf("{{") >= 0) {
            url = core.evalTemplate(url, null, source.ctx(key, page));
        }
        return { url: absolute(url, source.url + "/"), opts: parts.opts };
    }

    Source.prototype.search = function (key, page) {
        page = page || 1;
        var rule = this.data.ruleSearch || {};
        var ctx = this.ctx(key, page);
        var built = buildUrl(this, this.data.searchUrl, key, page);
        if (!built.url) { throw new Error("书源未配置搜索地址"); }
        var options = merge({}, built.opts);
        if (typeof options.body === "string") {
            options.body = options.body
                .replace(/\{\{key\}\}/g, encodeURIComponent(key === undefined ? "" : key))
                .replace(/\{\{page\}\}/g, String(page === undefined ? 1 : page));
            options.body = core.evalTemplate(options.body, null, ctx);
        }
        var value = toValue(this.fetch(built.url, options));
        var items = core.selectNodes(rule.bookList || "", value, ctx);
        var books = [];
        for (var i = 0; i < items.length; i += 1) {
            var item = items[i];
            var name = core.evalRule(rule.name || "text", item, ctx);
            if (!name) { continue; }
            var bookUrl = absolute(core.evalRule(rule.bookUrl || "href", item, ctx), built.url);
            if (!bookUrl) { continue; }
            var book = {
                name: name,
                author: core.evalRule(rule.author || "", item, ctx),
                bookUrl: bookUrl,
                coverUrl: absolute(core.evalRule(rule.coverUrl || "", item, ctx), built.url),
                intro: core.evalRule(rule.intro || "", item, ctx),
                kind: core.evalRule(rule.kind || "", item, ctx),
                lastChapter: core.evalRule(rule.lastChapter || "", item, ctx),
                sourceUrl: this.url,
                sourceName: this.name
            };
            book.key = bookKey(book.sourceUrl, book.bookUrl);
            books.push(book);
        }
        return books;
    };

    Source.prototype.bookInfo = function (bookUrl) {
        var rule = this.data.ruleBookInfo || {};
        var ctx = this.ctx();
        var value = toValue(this.fetch(bookUrl));
        var info = {
            bookUrl: bookUrl,
            sourceUrl: this.url,
            sourceName: this.name
        };
        var fields = ["name", "author", "coverUrl", "intro", "kind", "lastChapter"];
        for (var i = 0; i < fields.length; i += 1) {
            info[fields[i]] = core.evalRule(rule[fields[i]] || "", value, ctx);
        }
        info.coverUrl = absolute(info.coverUrl || "", bookUrl);
        var tocUrl = rule.tocUrl ? core.evalRule(rule.tocUrl, value, ctx) : "";
        info.tocUrl = absolute(tocUrl || bookUrl, bookUrl);
        info.key = bookKey(this.url, bookUrl);
        return info;
    };

    Source.prototype.toc = function (bookUrl, tocUrl) {
        var rule = this.data.ruleToc || {};
        var ctx = this.ctx();
        var url = tocUrl || bookUrl;
        var value = toValue(this.fetch(url));
        var items = core.selectNodes(rule.chapterList || "", value, ctx);
        var chapters = [];
        for (var i = 0; i < items.length; i += 1) {
            var item = items[i];
            var title = core.evalRule(rule.chapterName || "text", item, ctx);
            var href = core.evalRule(rule.chapterUrl || "href", item, ctx);
            if (!title) { continue; }
            chapters.push({
                index: chapters.length,
                title: title,
                url: absolute(href, url)
            });
        }
        return chapters;
    };

    Source.prototype.content = function (chapterUrl) {
        var rule = this.data.ruleContent || {};
        var ctx = this.ctx();
        var value = toValue(this.fetch(chapterUrl));
        var raw = core.evalRule(rule.content || "text", value, ctx);
        var text;
        if (raw.indexOf("<") >= 0) {
            text = core.htmlToText(raw);
        } else {
            text = trim(raw);
        }
        text = applyReplaceRegex(text, rule.replaceRegex);
        return { url: chapterUrl, text: readable(text), html: raw };
    };

    function applyReplaceRegex(text, rule) {
        rule = trim(rule || "");
        if (!rule) { return text; }
        if (rule.slice(0, 2) === "##") { rule = rule.slice(2); }
        var index = rule.indexOf("##");
        var pattern = index >= 0 ? rule.slice(0, index) : rule;
        var replacement = index >= 0 ? rule.slice(index + 2) : "";
        if (!pattern) { return text; }
        return core.replaceText(text, pattern, replacement);
    }

    function readable(text) {
        text = trim(text || "");
        if (!text) { return ""; }
        if (text.indexOf("\n") >= 0) { return text; }
        if (text.length > 200) {
            return text.replace(/([。！？!?])/g, "$1\n");
        }
        return text;
    }

    function findSource(url) {
        url = trim(url || "").replace(/\/+$/, "");
        var sources = state.sources || [];
        for (var i = 0; i < sources.length; i += 1) {
            var candidate = trim(sources[i].bookSourceUrl || "").replace(/\/+$/, "");
            if (candidate === url) { return sources[i]; }
        }
        return null;
    }

    function requireSource(url) {
        var data = findSource(url);
        if (!data) {
            throw new Error("找不到书源: " + (url || "(空)"));
        }
        return new Source(data);
    }

    // ------------------------------------------------------------------ cache --

    function cachePath(key, kind, url) {
        return root() + "/cache/" + key + "/" + digest(kind + url) + ".json";
    }

    function cacheGet(key, kind, url, ttl) {
        var raw = readText(cachePath(key, kind, url));
        if (!raw) { return null; }
        var payload = parseJSON(raw, null);
        if (!payload || !has(payload, "t")) { return null; }
        if (now() - intValue(payload.t, 0) > ttl) { return null; }
        return has(payload, "v") ? payload.v : null;
    }

    function cacheSet(key, kind, url, value) {
        try {
            writeJSON(cachePath(key, kind, url), { t: now(), v: value });
        } catch (e) { /* 缓存失败不影响主流程 */ }
    }

    function clearCache() {
        var base = root() + "/cache";
        var names = nat.listDir ? parseJSON(nat.listDir(base), []) : [];
        for (var i = 0; i < names.length; i += 1) {
            nat.remove(base + "/" + names[i]);
        }
        textCache = {};
        textCacheKeys = [];
    }

    // 每周启动时清一次章节缓存，防止 4S 上的缓存无限增长
    var CACHE_PRUNE_INTERVAL = 7 * 24 * 3600 * 1000;

    function pruneCacheIfNeeded() {
        var last = intValue(state.config.lastCachePrune, 0);
        if (last && now() - last < CACHE_PRUNE_INTERVAL) { return; }
        clearCache();
        state.config.lastCachePrune = now();
        saveConfig();
    }

    // ------------------------------------------------------------------ books --

    function bookKey(sourceUrl, bookUrl) {
        return digest(String(sourceUrl || "") + "\n" + String(bookUrl || "")).slice(0, 16);
    }

    function progressMap() {
        return state.progress.books || {};
    }

    function shelfList() {
        var books = state.shelf.books || {};
        var out = [];
        for (var key in books) {
            if (!has(books, key)) { continue; }
            var item = copy(books[key]);
            item.key = key;
            // 老书架条目没有简介时，从本地书籍元数据补齐
            if (!trim(item.intro || "") && state.local[key]) {
                var meta = state.local[key];
                if (trim(meta.intro || "")) { item.intro = meta.intro; }
                if (!trim(item.coverPath || "") && meta.coverPath) {
                    item.coverPath = meta.coverPath;
                }
            }
            item.progress = progressForBook(key, item.name, item.author);
            if (!trim(item.author) && item.progress &&
                trim(item.progress.author)) {
                item.author = item.progress.author;
            }
            out.push(item);
        }
        out.sort(function (a, b) {
            return intValue(b.updatedAt, 0) - intValue(a.updatedAt, 0);
        });
        return out;
    }

    function progressForBook(key, name, author) {
        var direct = progressMap()[key];
        if (direct) { return direct; }
        var keys = matchBookKeys(name, author);
        for (var i = 0; i < keys.length; i += 1) {
            if (progressMap()[keys[i]]) { return progressMap()[keys[i]]; }
        }
        var wantedName = lower(normalizeText(name));
        for (var pendingKey in progressMap()) {
            if (!has(progressMap(), pendingKey)) { continue; }
            if (pendingKey.indexOf("legado-") !== 0) { continue; }
            var pending = progressMap()[pendingKey];
            if (lower(normalizeText(pending.name)) !== wantedName) { continue; }
            return pending;
        }
        return null;
    }

    function shelfAdd(book) {
        if (!isObject(book) || !book.bookUrl) {
            throw new Error("缺少 bookUrl");
        }
        var sourceUrl = book.sourceUrl || "";
        var key = book.key || bookKey(sourceUrl, book.bookUrl);
        var existing = (state.shelf.books || {})[key] || {};
        var item = copy(book);
        item.key = key;
        item.sourceUrl = sourceUrl;
        item.bookUrl = book.bookUrl;
        item.addedAt = existing.addedAt || intValue(book.addedAt, now());
        item.updatedAt = now();
        state.shelf.books[key] = item;
        saveShelf();
        return item;
    }

    function shelfRemove(key) {
        key = trim(key || "");
        if (!key || !state.shelf.books || !state.shelf.books[key]) {
            return false;
        }
        delete state.shelf.books[key];
        saveShelf();
        return true;
    }

    function progressKey(params) {
        if (params.key) { return params.key; }
        if (params.bookUrl) { return bookKey(params.sourceUrl, params.bookUrl); }
        return "";
    }

    function saveProgressEntry(params) {
        var key = progressKey(params);
        if (!key) { throw new Error("缺少 key 或 bookUrl"); }
        var entry = copy(params);
        entry.key = key;
        entry.chapterIndex = intValue(entry.chapterIndex, 0);
        entry.pos = intValue(entry.pos, 0);
        entry.ratio = typeof entry.ratio === "number" ? entry.ratio : parseFloat(entry.ratio || 0) || 0;
        entry.updatedAt = intValue(entry.updatedAt, now());

        // 本地书的作者通常为空；如果云端进度里有作者，沿用下去，
        // 这样上传的文件名才能和安卓的“书名_作者.json”对上。
        if (!normalizeText(entry.author) && normalizeText(entry.name)) {
            var wantedName = lower(normalizeText(entry.name));
            for (var sourceKey in progressMap()) {
                if (!has(progressMap(), sourceKey) || sourceKey === key) {
                    continue;
                }
                var known = progressMap()[sourceKey] || {};
                if (lower(normalizeText(known.name)) !== wantedName) {
                    continue;
                }
                if (normalizeText(known.author)) {
                    entry.author = known.author;
                    break;
                }
            }
        }

        state.progress.books[key] = entry;

        // 把总章节数同步回书架条目。iOS 端主页 / 书架据此计算“全书进度”，
        // 老进度或云端同步过来的进度本身可能没有 chapterCount。
        var shelfItem = isObject(state.shelf.books) ? state.shelf.books[key] : null;
        if (shelfItem && intValue(entry.chapterCount, 0) > 0 &&
            intValue(shelfItem.chapterCount, 0) !== intValue(entry.chapterCount, 0)) {
            shelfItem.chapterCount = intValue(entry.chapterCount, 0);
            saveShelf();
        }

        // 这本书真实存在于书架上后，删掉之前同步过来、还没匹配上的临时进度
        var entryName = lower(normalizeText(entry.name));
        var entryAuthor = lower(normalizeText(entry.author));
        for (var pendingKey in progressMap()) {
            if (!has(progressMap(), pendingKey)) { continue; }
            if (pendingKey === key || pendingKey.indexOf("legado-") !== 0) {
                continue;
            }
            var pending = progressMap()[pendingKey] || {};
            if (lower(normalizeText(pending.name)) !== entryName) { continue; }
            var pendingAuthor = lower(normalizeText(pending.author));
            if (pendingAuthor && entryAuthor &&
                pendingAuthor !== entryAuthor) {
                continue;
            }
            delete progressMap()[pendingKey];
            delete pendingPush[pendingKey];
        }

        saveProgress();
        pendingPush[key] = true;
        scheduleAutoPush();
        return entry;
    }

    function deferAutoPush(seconds) {
        if (state.config.autoPush === false) { return; }
        if (!nat.defer) { return; }
        autoPushScheduled = true;
        nat.defer(seconds, autoPushNow);
    }

    function autoPushNow() {
        autoPushScheduled = false;
        if (state.config.autoPush === false) { return; }
        if (!davFromConfig().configured()) { return; }

        // 距上次上传不足 30 秒时不能直接返回，否则最后一次翻页的进度
        // 会被永久丢掉；这里按剩余冷却时间再排一次。
        var wait = 30000 - (now() - lastAutoPush);
        if (wait > 0) {
            deferAutoPush(Math.ceil(wait / 1000) + 1);
            return;
        }

        var keys = [];
        for (var key in pendingPush) {
            if (has(pendingPush, key)) { keys.push(key); }
        }
        if (!keys.length) { return; }
        lastAutoPush = now();
        try {
            var dav = davFromConfig();
            dav.timeout = 15;
            var result = pushProgress(dav, {
                keys: keys,
                checkRemote: true
            });
            for (var i = 0; i < result.done.length; i += 1) {
                delete pendingPush[result.done[i]];
            }
            autoPushFailAt = 0;
            autoPushRetryDelay = 60;
        } catch (e) {
            // 失败不清 pendingPush：等网络恢复后自动补传。
            autoPushFailAt = now();
            var delay = autoPushRetryDelay || 60;
            if (delay > 600) { delay = 600; }
            autoPushRetryDelay = delay * 2;
            deferAutoPush(delay);
        }
    }

    function scheduleAutoPush() {
        if (state.config.autoPush === false) { return; }
        if (!davFromConfig().configured()) { return; }
        if (autoPushScheduled) { return; }

        // 冷却中也要再排一次，否则节流窗口内的最后一次保存会一直留在
        // pendingPush 里，直到下一次翻页才上传（熄屏就可能丢）。
        var wait = 30000 - (now() - lastAutoPush);
        if (wait > 0) {
            deferAutoPush(Math.ceil(wait / 1000) + 1);
            return;
        }
        if (now() - autoPushFailAt < 60 * 1000) {
            deferAutoPush(60);
            return;
        }

        autoPushScheduled = true;
        // 原生层提供延迟执行；测试环境没有，就只靠手动/后台同步
        if (nat.defer) {
            nat.defer(3, autoPushNow);
        } else {
            autoPushScheduled = false;
        }
    }

    // ------------------------------------------------------------- local books --

    function localName(name) {
        var text = String(name || "").replace(/\\/g, "/");
        return text.slice(text.lastIndexOf("/") + 1);
    }

    function lower(text) {
        return String(text || "").toLowerCase();
    }

    function extOf(name) {
        var base = localName(name);
        var index = base.lastIndexOf(".");
        return index < 0 ? "" : lower(base.slice(index));
    }

    // 和安卓版“阅读”(legado) 一致的 TXT 分章规则。
    // 注意：iOS 9 的 JavaScriptCore 不支持正则后行断言(?<=)，所以只取不需要
    // lookbehind 的规则；顺序和 legado 默认规则表保持一致，按命中数量打分。
    var TOC_RULES = [
        // 1 目录
        "^[ \\u3000\\t]{0,4}(?:序章|楔子|正文(?!完|结)|终章|后记|尾声|番外|第\\s{0,4}[\\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]+?\\s{0,4}(?:章|节(?!课)|卷|集(?![合和])|部(?![分赛游])|篇(?!张))).{0,30}$",
        // 2/3 目录（含简介，古典 / 轻小说备用）
        "^[ \\u3000\\t]{0,4}(?:(?:内容|文章)?简介|文案|前言|序章|楔子|正文(?!完|结)|终章|后记|尾声|番外|第\\s{0,4}[\\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]+?\\s{0,4}(?:章|节(?!课)|卷|集(?![合和])|部(?![分赛游])|回(?![合来事去])|场(?![和合比电是])|话|篇(?!张))).{0,30}$",
        // 7/8/9 数字 / 大写数字 分隔符 标题名称
        "^[ \\u3000\\t]{0,4}(?:序章|楔子|正文(?!完|结)|终章|后记|尾声|番外|[零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]{1,8}章?[ 、_—\\-]|\\d{1,5}章?[:：,.， 、_—\\-]).{0,30}$",
        // 10 正文 标题/序号
        "^[ \\u3000\\t]{0,4}正文[ \\u3000]{1,4}.{0,20}$",
        // 11 Chapter/Section/Part/Episode 序号 标题
        "^[ \\u3000\\t]{0,4}(?:[Cc]hapter|[Ss]ection|[Pp]art|ＰＡＲＴ|[Nn][oO][.、]|[Ee]pisode|(?:内容|文章)?简介|文案|前言|序章|楔子|正文(?!完|结)|终章|后记|尾声|番外)\\s{0,4}\\d{1,4}.{0,30}$",
        // 12 Chapter（去简介）
        "^[ \\u3000\\t]{0,4}(?:[Cc]hapter|[Ss]ection|[Pp]art|ＰＡＲＴ|[Nn][Oo]\\.|[Ee]pisode)\\s{0,4}\\d{1,4}.{0,30}$",
        // 16 章/卷 序号 标题
        "^[ \\u3000\\t]{0,4}(?:(?:内容|文章)?简介|文案|前言|序章|楔子|正文(?!完|结)|终章|后记|尾声|番外|[卷章][\\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]{1,8})[ \\u3000]{0,4}.{0,30}$",
        // 24 通用规则（legado 最后的兜底规则）
        "^.{0,6}(?:[引楔]子|正文(?!完|结)|[引序前]言|[序终]章|扉页|[上中下][部篇卷]|卷首语|后记|尾声|番外|={2,4}|第\\s{0,4}[\\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]+?\\s{0,4}(?:章|节(?!课)|卷|页[、 \\u3000]|集(?![合和])|部(?![分是门落])|篇(?!张))).{0,40}$",
        "^.{0,6}[\\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟a-zA-Z]{1,8}[、. \\u3000].{0,20}$"
    ];
    var TOC_VERSION = 3;

    function ruleMatches(source, text) {
        var re = new RegExp(source, "gm");
        var matches = [];
        var match;
        while ((match = re.exec(text)) !== null) {
            matches.push({ title: trim(match[0]), index: match.index,
                end: re.lastIndex });
            if (match[0] === "") { re.lastIndex += 1; }
        }
        return matches;
    }

    // 和 legado 的 getTocRule 相同的打分方式：太短的“章节”当成误判的卷名。
    function pickTocMatches(text) {
        var best = null;
        var maxNum = -1;
        for (var r = 0; r < TOC_RULES.length; r += 1) {
            var matches = ruleMatches(TOC_RULES[r], text);
            var csNum = 0;
            var numE = 0;
            var last = 0;
            for (var i = 0; i < matches.length; i += 1) {
                var contentLength = matches[i].index - last;
                if (last === 0 || contentLength > 1000) {
                    csNum += 1;
                    last = matches[i].end;
                } else if (contentLength < 100) {
                    numE += 1;
                }
            }
            if (csNum >= numE * 3 && csNum > maxNum + 2) {
                maxNum = csNum;
                best = matches;
                if (maxNum > 70) { break; }
            }
        }
        return best && best.length ? best : null;
    }

    function splitTxt(text) {
        var matches = pickTocMatches(text);
        var chapters = [];
        if (matches) {
            // 第一个标题之前的内容作为“前言”，和 legado 一样保留
            if (matches[0].index > 0 && trim(text.slice(0, matches[0].index))) {
                chapters.push({ title: "前言", start: 0, end: matches[0].index });
            }
            for (var i = 0; i < matches.length; i += 1) {
                chapters.push({
                    title: matches[i].title,
                    // 和 legado 一样：正文从标题行之后开始（标题单独显示）
                    start: matches[i].end,
                    end: i + 1 < matches.length
                        ? matches[i + 1].index : text.length
                });
            }
            if (chapters.length) { return chapters; }
        }

        // 没有任何规则命中时，按 10K 字符在换行处切块，行为靠近 legado 的无规则模式
        var maxLength = 10 * 1024;
        var pos = 0;
        var part = 0;
        while (pos < text.length) {
            part += 1;
            var end = Math.min(text.length, pos + maxLength);
            if (end < text.length) {
                var newline = text.indexOf("\n", end);
                if (newline > end && newline - end < 2000) { end = newline; }
            }
            chapters.push({
                title: "第" + part + "章",
                start: pos,
                end: end
            });
            pos = end;
        }
        return chapters.length ? chapters : [{ title: "全文", start: 0, end: text.length }];
    }

    function bookText(key, path) {
        for (var i = 0; i < textCacheKeys.length; i += 1) {
            if (textCacheKeys[i] === key) { return textCache[key]; }
        }
        var text = readText(path);
        textCache[key] = text;
        textCacheKeys.push(key);
        while (textCacheKeys.length > 2) {
            var old = textCacheKeys.shift();
            delete textCache[old];
        }
        return text;
    }

    function guardFileSize(path, name) {
        if (!nat.fileSize) { return; }
        var size = intValue(nat.fileSize(path), 0);
        if (size > MAX_BOOK_BYTES) {
            throw new Error((name || "文件") + " 太大（" +
                Math.round(size / 1048576) + " MB），iPhone 4S 建议不超过 " +
                Math.round(MAX_BOOK_BYTES / 1048576) + " MB");
        }
    }

    function importLocal(name, base64) {
        name = localName(name || "book.txt");
        base64 = String(base64 || "");
        var ext = extOf(name);
        if (ext !== ".txt" && ext !== ".epub") {
            throw new Error("只支持 .txt / .epub，收到: " + (ext || "(无扩展名)"));
        }
        if (base64.length > MAX_BOOK_BYTES * 4 / 3 + 1024) {
            throw new Error("文件太大，iPhone 4S 建议不超过 " +
                Math.round(MAX_BOOK_BYTES / 1048576) + " MB");
        }
        var stamp = String(name) + "\n" + base64.length + "\n" +
            base64.slice(0, 32) + base64.slice(-32);
        var key = "local-" + digest(stamp).slice(0, 10);
        var meta;
        if (ext === ".txt") {
            var text = nat.decodeText(base64);
            var path = booksDir() + "/" + key + ".txt";
            writeText(path, text);
            meta = {
                key: key,
                name: name.replace(/\.[^.]+$/, ""),
                author: "",
                ext: ext,
                path: path,
                intro: txtIntro(text),
                chapters: splitTxt(text),
                chaptersVersion: TOC_VERSION,
                size: text.length
            };
        } else {
            var zipPath = booksDir() + "/" + key + ".epub";
            if (!nat.writeBase64(zipPath, base64)) {
                throw new Error("保存 EPUB 失败");
            }
            meta = readEpub(key, zipPath, name);
        }
        state.local[key] = meta;
        textCache = {};
        textCacheKeys = [];
        saveLocal();
        return localShelfEntry(key, meta);
    }

    // 从磁盘路径导入（云端流式下载后调用）。TXT 仍然交给原生做编码探测，
    // EPUB 直接复制文件，避免几 MB 的数据在 JS 里转 base64。
    function importLocalFile(name, path) {
        name = localName(name || "book.txt");
        var ext = extOf(name);
        if (ext !== ".txt" && ext !== ".epub") {
            throw new Error("只支持 .txt / .epub，收到: " + (ext || "(无扩展名)"));
        }
        var size = nat.fileSize ? intValue(nat.fileSize(path), 0) : 0;
        if (size > MAX_BOOK_BYTES) {
            throw new Error((name || "文件") + " 太大（" +
                Math.round(size / 1048576) + " MB），iPhone 4S 建议不超过 " +
                Math.round(MAX_BOOK_BYTES / 1048576) + " MB");
        }
        if (size <= 0) {
            throw new Error("下载到的文件是空的: " + name);
        }
        var key = "local-" + digest(name + "\n" + size).slice(0, 10);
        var meta;
        if (ext === ".txt") {
            var text = nat.readTextFile
                ? nat.readTextFile(path)
                : nat.decodeText(nat.readBase64(path) || "");
            if (!text) { throw new Error("读取文本失败: " + name); }
            var textPath = booksDir() + "/" + key + ".txt";
            writeText(textPath, text);
            meta = {
                key: key,
                name: name.replace(/\.[^.]+$/, ""),
                author: "",
                ext: ext,
                path: textPath,
                intro: txtIntro(text),
                chapters: splitTxt(text),
                chaptersVersion: TOC_VERSION,
                size: text.length
            };
        } else {
            var zipPath = booksDir() + "/" + key + ".epub";
            var copied = nat.copy ? nat.copy(path, zipPath) : false;
            if (!copied) {
                if (!nat.writeBase64(zipPath, nat.readBase64(path) || "")) {
                    throw new Error("保存 EPUB 失败");
                }
            }
            meta = readEpub(key, zipPath, name);
        }
        state.local[key] = meta;
        textCache = {};
        textCacheKeys = [];
        saveLocal();
        return localShelfEntry(key, meta);
    }

    // TXT 没有元数据：取开头正文作为简介（跳过目录式短行）
    function txtIntro(text) {
        text = String(text || "");
        if (!text) { return ""; }
        var lines = text.split(/\r?\n/);
        var parts = [];
        var total = 0;
        for (var i = 0; i < lines.length && parts.length < 4; i += 1) {
            var line = trim(lines[i]).replace(/^[\u3000\s]+/, "");
            if (line.length < 12) { continue; }     // 跳过章节名/目录行
            if (/^(第[一二三四五六七八九十百千0-9]+[章节卷]|序章|楔子|前言|目录)/.test(line)) { continue; }
            parts.push(line);
            total += line.length;
            if (total > 220) { break; }
        }
        var intro = parts.join("");
        return intro.length > 300 ? intro.slice(0, 300) : intro;
    }

    // 老版本导入的书没有简介：启动时补一批（不阻塞启动）
    function repairLocalIntros() {
        if (!state.local || !nat.exists) { return; }
        var budget = 6;
        var changed = false;
        for (var key in state.local) {
            if (!has(state.local, key)) { continue; }
            var meta = state.local[key];
            if (!meta || meta.intro || budget <= 0) { continue; }
            budget -= 1;
            if (meta.ext === ".epub") {
                if (!meta.path || !nat.exists(meta.path) || !nat.zipList) { continue; }
                try {
                    var entries = zipEntries(meta.path);
                    var containerName = zipFind(entries, "META-INF/container.xml");
                    if (!containerName) { continue; }
                    var container = core.parseHTML(nat.zipReadText(meta.path, containerName) || "");
                    var rootfile = firstElement(container, "rootfile");
                    var opfPath = rootfile ? rootfile.get("full-path") : "";
                    var opfName = opfPath ? zipFind(entries, unquote(opfPath)) : "";
                    if (!opfName) { continue; }
                    var opf = core.parseHTML(nat.zipReadText(meta.path, opfName) || "");
                    var descs = elementsOf(opf, "description");
                    if (descs.length) { meta.intro = trim(descs[0].textContent() || ""); }
                } catch (e) { /* 忽略 */ }
            } else if (meta.ext === ".txt" && meta.path) {
                try {
                    var text = bookText(key, meta.path);
                    meta.intro = txtIntro(text);
                } catch (e2) { /* 忽略 */ }
            }
            state.local[key] = meta;
            changed = true;
        }
        if (changed) { saveLocal(); }
    }

    function localShelfEntry(key, meta) {
        meta = meta || state.local[key] || {};
        var wordCount = 0;
        if (meta.ext === ".txt") {
            // TXT 的 size 就是解码后的字符数，中文里字符≈字数
            wordCount = intValue(meta.size, 0);
        }
        return {
            key: key,
            name: meta.name || "未命名",
            author: meta.author || "",
            sourceUrl: "local",
            sourceName: "本地/云端",
            bookUrl: key,
            coverUrl: "",
            coverPath: meta.coverPath || "",
            intro: meta.intro || "",
            lastChapter: "",
            local: true,
            size: intValue(meta.size, 0),
            wordCount: wordCount,
            chapterCount: (meta.chapters || []).length
        };
    }

    function unquote(value) {
        try {
            return decodeURIComponent(value);
        } catch (e) {
            return value;
        }
    }

    function joinZipPath(base, href) {
        var full = base ? base + "/" + href : href;
        var parts = full.replace(/\\/g, "/").split("/");
        var out = [];
        for (var i = 0; i < parts.length; i += 1) {
            var part = parts[i];
            if (!part || part === ".") { continue; }
            if (part === "..") {
                if (out.length) { out.pop(); }
                continue;
            }
            out.push(part);
        }
        return out.join("/");
    }

    function zipEntries(path) {
        return parseJSON(nat.zipList(path), []) || [];
    }

    function zipFind(entries, wanted) {
        wanted = unquote(wanted);
        for (var i = 0; i < entries.length; i += 1) {
            var name = entries[i];
            if (name === wanted) { return name; }
        }
        for (var j = 0; j < entries.length; j += 1) {
            if (unquote(entries[j]) === wanted) { return entries[j]; }
        }
        for (var k = 0; k < entries.length; k += 1) {
            if (lower(unquote(entries[k])) === lower(wanted)) { return entries[k]; }
        }
        return "";
    }

    function elementsOf(node, name) {
        var out = [];
        var all = node.descendants ? node.descendants() : [];
        for (var i = 0; i < all.length; i += 1) {
            var tag = all[i].tag || "";
            var index = tag.lastIndexOf(":");
            var local = index >= 0 ? tag.slice(index + 1) : tag;
            if (local === name) { out.push(all[i]); }
        }
        return out;
    }

    function firstElement(node, name) {
        var list = elementsOf(node, name);
        return list.length ? list[0] : null;
    }

    // 从 EPUB 的 opf 里找封面并解压到 covers 目录。
    // 只在需要时读封面这一张图，避免把整本 EPUB 都解析一遍。
    function epubCoverPath(path, entries, opf, base, key) {
        var items = elementsOf(opf, "item");
        var coverHref = "";
        for (var c = 0; c < items.length; c += 1) {
            var props = items[c].get("properties") || "";
            if (props.indexOf("cover-image") >= 0) {
                coverHref = items[c].get("href") || "";
                break;
            }
        }
        if (!coverHref) {
            var metas = elementsOf(opf, "meta");
            for (var mi = 0; mi < metas.length; mi += 1) {
                if (lower(metas[mi].get("name")) !== "cover") { continue; }
                var coverId = metas[mi].get("content");
                for (var k = 0; k < items.length; k += 1) {
                    if (items[k].get("id") === coverId) {
                        coverHref = items[k].get("href") || "";
                        break;
                    }
                }
                if (coverHref) { break; }
            }
        }
        if (!coverHref) { return ""; }
        var coverReal = zipFind(entries, joinZipPath(base, unquote(coverHref)));
        if (!coverReal) { return ""; }
        var coverExt = extOf(coverReal) || ".jpg";
        var target = coversDir() + "/" + key + coverExt;
        var data = nat.zipReadBase64 ? nat.zipReadBase64(path, coverReal) : "";
        if (!data || !nat.writeBase64 || !nat.writeBase64(target, data)) {
            return "";
        }
        return target;
    }

    function extractEpubCover(key, path) {
        try {
            var entries = zipEntries(path);
            var containerName = zipFind(entries, "META-INF/container.xml");
            if (!containerName) { return ""; }
            var container = core.parseHTML(nat.zipReadText(path, containerName) || "");
            var rootfile = firstElement(container, "rootfile");
            var opfPath = rootfile ? rootfile.get("full-path") : "";
            var opfName = opfPath ? zipFind(entries, unquote(opfPath)) : "";
            if (!opfName) { return ""; }
            var base = opfPath.indexOf("/") >= 0
                ? opfPath.slice(0, opfPath.lastIndexOf("/")) : "";
            var opf = core.parseHTML(nat.zipReadText(path, opfName) || "");
            return epubCoverPath(path, entries, opf, base, key);
        } catch (e) {
            return "";
        }
    }

    // 旧版本导入的 EPUB 在 local.json 里没有封面；每次启动补几张，
    // 不会为了封面把整本书重新解析一遍。
    function repairLocalCovers() {
        if (!nat.exists || !nat.zipList) { return; }
        var budget = 8;
        var changed = false;
        for (var key in (state.local || {})) {
            if (!has(state.local, key)) { continue; }
            var meta = state.local[key];
            if (!meta || meta.ext !== ".epub" || meta.coverPath) { continue; }
            if (meta.coverChecked || budget <= 0) { continue; }
            budget -= 1;
            meta.coverChecked = true;
            changed = true;
            if (meta.path && nat.exists(meta.path)) {
                var cover = extractEpubCover(key, meta.path);
                if (cover) { meta.coverPath = cover; }
            }
            state.local[key] = meta;
        }
        if (changed) { saveLocal(); }
    }

    function readEpub(key, path, filename) {
        var title = localName(filename).replace(/\.[^.]+$/, "");
        var author = "";
        var coverPath = "";
        var intro = "";
        var chapters = [];
        try {
            var entries = zipEntries(path);
            var containerName = zipFind(entries, "META-INF/container.xml");
            if (containerName) {
                var container = core.parseHTML(nat.zipReadText(path, containerName) || "");
                var rootfile = firstElement(container, "rootfile");
                var opfPath = rootfile ? rootfile.get("full-path") : "";
                var opfName = opfPath ? zipFind(entries, unquote(opfPath)) : "";
                if (opfName) {
                    var base = opfPath.indexOf("/") >= 0 ? opfPath.slice(0, opfPath.lastIndexOf("/")) : "";
                    var opf = core.parseHTML(nat.zipReadText(path, opfName) || "");
                    var manifest = {};
                    var system = firstElement(opf, "package");
                    var items = system ? elementsOf(system, "item") : elementsOf(opf, "item");
                    for (var i = 0; i < items.length; i += 1) {
                        manifest[items[i].get("id")] = items[i].get("href");
                    }

                    coverPath = epubCoverPath(path, entries, opf, base, key);

                    var spine = elementsOf(opf, "itemref");
                    for (var j = 0; j < spine.length; j += 1) {
                        var href = manifest[spine[j].get("idref")];
                        if (!href) { continue; }
                        var inner = joinZipPath(base, unquote(href));
                        var real = zipFind(entries, inner);
                        if (!real) { continue; }
                        var text = "";
                        try {
                            text = core.htmlToText(nat.zipReadText(path, real) || "");
                        } catch (e) { text = ""; }
                        var heading = text ? trim(text.split("\n")[0]).slice(0, 40) : "";
                        chapters.push({
                            title: heading || ("第 " + (j + 1) + " 节"),
                            href: real
                        });
                    }
                    var titles = elementsOf(opf, "title");
                    if (titles.length && trim(titles[0].textContent())) {
                        title = trim(titles[0].textContent());
                    }
                    var creators = elementsOf(opf, "creator");
                    if (creators.length && trim(creators[0].textContent())) {
                        author = trim(creators[0].textContent());
                    }
                    // EPUB 简介（dc:description），完整保留给详情页
                    var descs = elementsOf(opf, "description");
                    for (var di = 0; di < descs.length; di += 1) {
                        var dv = trim(descs[di].textContent() || "");
                        if (dv) { intro = dv; break; }
                    }
                }
            }
        } catch (e) { /* 尽量返回已有章节 */ }
        return {
            key: key,
            name: title,
            author: author || "",
            ext: ".epub",
            path: path,
            coverPath: coverPath || "",
            intro: intro || "",
            chapters: chapters,
            size: nat.fileSize ? nat.fileSize(path) : 0
        };
    }

    function localToc(key) {
        var meta = state.local[key];
        if (!meta) { throw new Error("本地书籍不存在: " + key); }
        ensureLocalChapters(key, meta);
        var chapters = meta.chapters || [];
        var out = [];
        for (var i = 0; i < chapters.length; i += 1) {
            out.push({
                index: i,
                title: chapters[i].title || ("第 " + (i + 1) + " 章"),
                url: key
            });
        }
        return out;
    }

    function localContent(key, index) {
        var meta = state.local[key];
        if (!meta) { throw new Error("本地书籍不存在: " + key); }
        ensureLocalChapters(key, meta);
        var chapters = meta.chapters || [];
        index = intValue(index, 0);
        if (index < 0 || index >= chapters.length) {
            throw new Error("章节超出范围");
        }
        var chapter = chapters[index];
        var body = "";
        if (meta.ext === ".txt") {
            var text = bookText(key, meta.path);
            body = text.slice(intValue(chapter.start, 0), intValue(chapter.end, text.length));
            // 和 legado 的 TextFile.getContent 一样：只把章节开头连续的 ASCII
            // 空白（换行/空格/制表符）换成两个全角空格。Java 的 \s 不包含
            // 全角空格，所以已有的“　　”要原样保留，位置才能和安卓对上。
            body = body.replace(/^[\n\r\t\f\v ]+/, "　　");
        } else {
            body = core.htmlToText(nat.zipReadText(meta.path, chapter.href) || "");
        }
        return {
            url: key,
            title: chapter.title || "",
            text: body,
            html: ""
        };
    }

    // 旧版本用的是很窄的分章正则，升级后需要重新分章，否则云端书目录还是错的。
    function ensureLocalChapters(key, meta) {
        if (!meta || meta.ext !== ".txt") { return meta; }
        if (intValue(meta.chaptersVersion, 0) >= TOC_VERSION) { return meta; }
        var text = bookText(key, meta.path);
        if (!text) { return meta; }
        meta.chapters = splitTxt(text);
        meta.chaptersVersion = TOC_VERSION;
        state.local[key] = meta;
        saveLocal();
        return meta;
    }

    function localMatches(keyword) {
        var out = [];
        keyword = lower(keyword);
        for (var key in state.local) {
            if (!has(state.local, key)) { continue; }
            var meta = state.local[key];
            if (lower(meta.name || "").indexOf(keyword) >= 0) {
                out.push(localShelfEntry(key, meta));
            }
        }
        return out;
    }

    // ---------------------------------------------------------------- webdav --

    function davFromConfig() {
        var cfg = state.config.webdav || {};
        return new Dav(cfg);
    }

    function Dav(config) {
        this.url = trim(config.url || "").replace(/\/+$/, "");
        this.username = config.username || "";
        this.password = config.password || "";
        this.dir = trim(config.dir || "").replace(/^\/+|\/+$/g, "");
        this.timeout = intValue(config.timeout, 60);
    }

    Dav.prototype.configured = function () {
        return !!this.url;
    };

    // 中文 / 空格 / 括号等文件名在 iOS 9 上会让 NSURL 解析失败，逐段做百分号编码。
    // 已经带 %XX 的片段保留原编码（安卓版就是这么拼 URL 的），只补漏掉的 %，
    // 避免二次编码把 % 变成 %25。
    function encodePath(path) {
        var parts = String(path || "").split("/");
        for (var i = 0; i < parts.length; i += 1) {
            var part = parts[i];
            if (!part) { continue; }
            parts[i] = encodeURIComponent(part)
                .replace(/%25([0-9a-fA-F]{2})/g, "%$1");
        }
        return parts.join("/");
    }

    Dav.prototype.target = function (path) {
        path = trim(path || "").replace(/^\/+/, "");
        var base = this.url + (this.dir ? "/" + encodePath(this.dir) : "");
        return path ? base + "/" + encodePath(path) : base;
    };

    Dav.prototype.headers = function (extra) {
        var headers = {};
        if (this.username) {
            headers.Authorization = "Basic " +
                nat.base64Encode(this.username + ":" + this.password);
        }
        return merge(headers, extra);
    };

    Dav.prototype.request = function (method, path, body, headers, allowed, binary, timeout) {
        var res = http(this.target(path), {
            method: method,
            headers: this.headers(headers),
            body: body,
            binary: !!binary,
            timeout: timeout || this.timeout || 60
        });
        var list = allowed || [200, 201, 204, 207];
        var ok = false;
        for (var i = 0; i < list.length; i += 1) {
            if (res.status === list[i]) { ok = true; break; }
        }
        if (!ok) {
            throw new Error("WebDAV " + method + " " + (path || "/") + " -> HTTP " + res.status);
        }
        return res;
    };

    Dav.prototype.list = function (path) {
        var res = this.request("PROPFIND", path || "", PROPFIND_BODY,
            { Depth: "1", "Content-Type": "application/xml; charset=utf-8" },
            [200, 207, 404]);
        if (res.status === 404 || !res.text) { return []; }
        var xml = core.parseHTML(res.text);
        var responses = elementsOf(xml, "response");
        var entries = [];
        var basePath = this.basePath();
        for (var i = 0; i < responses.length; i += 1) {
            var item = responses[i];
            var hrefNode = firstElement(item, "href");
            var displayNode = firstElement(item, "displayname");
            var sizeNode = firstElement(item, "getcontentlength");
            var modifiedNode = firstElement(item, "getlastmodified");
            var collection = firstElement(item, "collection");
            var href = hrefNode ? trim(hrefNode.textContent()) : "";
            if (!href) { continue; }
            var decoded = this.relative(href, basePath);
            if (decoded === null) { continue; }
            if (decoded === trim(path || "").replace(/^\/+|\/+$/g, "")) { continue; }
            if (!decoded) { continue; }
            entries.push({
                name: displayNode && trim(displayNode.textContent())
                    ? trim(displayNode.textContent())
                    : decoded.slice(decoded.lastIndexOf("/") + 1),
                path: decoded,
                isDir: !!collection,
                size: sizeNode ? intValue(trim(sizeNode.textContent()), 0) : 0,
                modified: modifiedNode ? trim(modifiedNode.textContent()) : ""
            });
        }
        return entries;
    };

    Dav.prototype.basePath = function () {
        var path = "";
        var match = /^[a-z][a-z0-9+.-]*:\/\/[^\/]*(.*)$/i.exec(this.url);
        if (match) { path = match[1] || ""; }
        path = path.replace(/^\/+|\/+$/g, "");
        if (this.dir) {
            path = path ? path + "/" + this.dir : this.dir;
        }
        return path.replace(/^\/+|\/+$/g, "");
    };

    Dav.prototype.relative = function (href, basePath) {
        var path = href;
        var match = /^[a-z][a-z0-9+.-]*:\/\/[^\/]*(.*)$/i.exec(href);
        if (match) { path = match[1] || ""; }
        path = unquote(path).replace(/^\/+|\/+$/g, "");
        if (!basePath) { return path; }
        if (path === basePath) { return ""; }
        var marker = basePath + "/";
        var index = lower(path).indexOf(lower(marker));
        if (index >= 0) {
            return path.slice(index + marker.length);
        }
        // 有些服务端返回的 href 不带完整前缀，退一步按远程目录名定位
        if (this.dir) {
            var dirMarker = lower("/" + this.dir + "/");
            var dirIndex = lower("/" + path).indexOf(dirMarker);
            if (dirIndex >= 0) {
                return path.slice(dirIndex + dirMarker.length - 1);
            }
        }
        return path;
    };

    Dav.prototype.download = function (path, binary, timeout) {
        var res = this.request("GET", path, null, null, [200, 404], binary, timeout);
        if (res.status === 404) { return null; }
        return binary ? (res.base64 || "") : (res.text || "");
    };

    // 直接下载到本地文件（走原生流式下载，不经过 base64，4S 上更稳）
    Dav.prototype.downloadTo = function (path, destination) {
        var raw = nat.downloadTo(this.target(path),
            JSON.stringify({
                headers: this.headers({}),
                timeout: this.timeout || 60
            }),
            destination);
        var res = parseJSON(raw, null);
        if (!res) { throw new Error("下载返回无法解析"); }
        if (res.ok !== true) {
            throw new Error(res.error || "下载失败");
        }
        if (res.status !== 200) {
            throw new Error("WebDAV GET " + (path || "/") + " -> HTTP " + res.status);
        }
        return res;
    };

    Dav.prototype.upload = function (path, text) {
        this.request("PUT", path, text,
            { "Content-Type": "application/octet-stream" }, [200, 201, 204, 207]);
    };

    Dav.prototype.mkdir = function (path) {
        try {
            this.request("MKCOL", path || "", null, null, [200, 201, 204, 405, 301]);
        } catch (e) {
            // 有些服务端在目录已存在时返回 405/409，视作成功
            if (String(e.message || "").indexOf("405") < 0 &&
                String(e.message || "").indexOf("409") < 0) {
                throw e;
            }
        }
    };

    function mergeBooks(local, remote) {
        var merged = copy(local || {});
        for (var key in (remote || {})) {
            if (!has(remote, key)) { continue; }
            var current = merged[key];
            if (!current ||
                intValue(remote[key].updatedAt, 0) > intValue(current.updatedAt, 0)) {
                merged[key] = remote[key];
            }
        }
        return merged;
    }

    function countKeys(obj) {
        var count = 0;
        for (var key in (obj || {})) {
            if (has(obj, key)) { count += 1; }
        }
        return count;
    }

    // ---------------------------------------------------- legado progress sync --
    //
    // 安卓版“阅读”(legado) 的进度不是一个大 JSON，而是每本书一个文件：
    //   <WebDAV>/<webDavDir>/bookProgress/书名_作者.json
    // 内容：
    //   {name, author, durChapterIndex, durChapterPos, durChapterTime, durChapterTitle}
    // 文件名里 [\\/:*?"<>|] 会被替换成下划线。这里完全按同样的规则读写，
    // 两边才能互相看到进度。

    function normalizeText(text) {
        return trim(String(text || "").replace(/\s+/g, " "));
    }

    function sameText(a, b) {
        return lower(normalizeText(a)) === lower(normalizeText(b));
    }

    function progressFileName(name, author) {
        // 完全按安卓 legado 的规则：
        // "name_author".normalizeFileName() 再把保留字符转成 %XX
        var base = String(name || "") + "_" + String(author || "");
        base = base.replace(/[\\/:*?"<>|]/g, "_");
        base = base.replace(/%/g, "%25")
            .replace(/ /g, "%20")
            .replace(/"/g, "%22")
            .replace(/#/g, "%23")
            .replace(/&/g, "%26")
            .replace(/\(/g, "%28")
            .replace(/\)/g, "%29")
            .replace(/\+/g, "%2B")
            .replace(/,/g, "%2C")
            .replace(/\//g, "%2F")
            .replace(/:/g, "%3A")
            .replace(/;/g, "%3B")
            .replace(/</g, "%3C")
            .replace(/=/g, "%3D")
            .replace(/>/g, "%3E")
            .replace(/\?/g, "%3F")
            .replace(/@/g, "%40")
            .replace(/\\/g, "%5C")
            .replace(/\|/g, "%7C");
        return base + ".json";
    }

    function knownBooks() {
        var out = [];
        var seen = {};
        function add(key, name, author) {
            key = String(key || "");
            if (!key) { return; }
            var record = seen[key];
            if (!record) {
                record = { key: key, name: "", author: "" };
                seen[key] = record;
                out.push(record);
            }
            if (!record.name && normalizeText(name)) {
                record.name = normalizeText(name);
            }
            if (!record.author && normalizeText(author)) {
                record.author = normalizeText(author);
            }
        }
        for (var key in (state.shelf.books || {})) {
            if (!has(state.shelf.books, key)) { continue; }
            var shelfBook = state.shelf.books[key] || {};
            add(key, shelfBook.name, shelfBook.author);
        }
        for (var localKey in (state.local || {})) {
            if (!has(state.local, localKey)) { continue; }
            var meta = state.local[localKey] || {};
            add(localKey, meta.name, meta.author);
        }
        for (var progressKey in progressMap()) {
            if (!has(progressMap(), progressKey)) { continue; }
            var entry = progressMap()[progressKey] || {};
            add(progressKey, entry.name, entry.author);
        }
        return out;
    }

    // 优先按“书名 + 作者”精确匹配；本地书没有作者时允许只按书名匹配，
    // 这样从安卓同步过来的进度也能落到本地 TXT 上。
    function matchBookKeys(name, author) {
        var wantedName = normalizeText(name);
        var wantedAuthor = normalizeText(author);
        if (!wantedName) { return []; }
        var books = knownBooks();
        var exact = [];
        var byName = [];
        for (var i = 0; i < books.length; i += 1) {
            var book = books[i];
            if (!sameText(book.name, wantedName)) { continue; }
            byName.push(book);
            if (sameText(book.author, wantedAuthor)) {
                exact.push(book.key);
            }
        }
        if (exact.length) { return exact; }
        var emptyAuthor = [];
        for (var j = 0; j < byName.length; j += 1) {
            if (!byName[j].author) { emptyAuthor.push(byName[j].key); }
        }
        if (emptyAuthor.length) { return emptyAuthor; }
        var keys = [];
        for (var k = 0; k < byName.length; k += 1) {
            keys.push(byName[k].key);
        }
        return keys;
    }

    function remoteProgressEntry(record) {
        if (!isObject(record)) { return null; }
        var name = normalizeText(record.name || record.bookName || "");
        if (!name) { return null; }
        var author = normalizeText(record.author || "");
        var index = intValue(record.durChapterIndex,
            intValue(record.chapterIndex, 0));
        var pos = intValue(record.durChapterPos, intValue(record.pos, 0));
        var time = intValue(record.durChapterTime, intValue(record.updatedAt, 0));
        if (time <= 0) { time = now(); }
        return {
            name: name,
            author: author,
            chapterIndex: Math.max(0, index),
            pos: Math.max(0, pos),
            chapterTitle: normalizeText(record.durChapterTitle ||
                record.chapterTitle || ""),
            updatedAt: time
        };
    }

    // 和安卓一致：章节更靠后，或同一章位置更靠后，才认为云端更新。
    function progressAhead(remote, local) {
        if (!local) { return true; }
        var remoteIndex = intValue(remote.chapterIndex, 0);
        var localIndex = intValue(local.chapterIndex, 0);
        if (remoteIndex !== localIndex) { return remoteIndex > localIndex; }
        return intValue(remote.pos, 0) > intValue(local.pos, 0);
    }

    // 云端进度里的章节序号是按安卓的分章结果算的。本机如果分章规则或
    // 版本不同，序号可能对不上；用 durChapterTitle 找到同名章节再换算，
    // 可以避免“进度跳到别的章”的大误差。
    function remapRemoteChapter(key, remote) {
        var meta = state.local ? state.local[key] : null;
        var chapters = meta && isArray(meta.chapters) ? meta.chapters : null;
        if (!chapters || !chapters.length) { return remote; }
        var wanted = normalizeText(remote.chapterTitle);
        if (!wanted) { return remote; }
        var index = intValue(remote.chapterIndex, -1);
        if (index >= 0 && index < chapters.length &&
            sameText(chapters[index].title, wanted)) {
            return remote; // 序号本来就对得上
        }
        var best = -1;
        var bestDistance = 0;
        for (var i = 0; i < chapters.length; i += 1) {
            if (!sameText(chapters[i].title, wanted)) { continue; }
            var distance = Math.abs(i - index);
            if (best < 0 || distance < bestDistance) {
                best = i;
                bestDistance = distance;
            }
        }
        if (best < 0) {
            // 标题对不上且云端章节号超出本机范围：宁可落到最后一章，
            // 也不要保存一个越界的章节号（阅读页会直接跳回第一章）。
            if (index >= chapters.length) {
                var clamped = merge({}, remote);
                clamped.chapterIndex = chapters.length - 1;
                return clamped;
            }
            return remote;
        }
        var mapped = merge({}, remote);
        mapped.chapterIndex = best;
        return mapped;
    }

    // 记录“章节标题 -> 安卓章节号”的映射，上传时把本机章节号换算成安卓的，
    // 这样即使两边分章序号不同，安卓也不会跳到别的章。
    function rememberChapterIndex(key, title, androidIndex) {
        title = normalizeText(title);
        if (!key || !title) { return; }
        if (!isObject(state.config.chapterIndexMaps)) {
            state.config.chapterIndexMaps = {};
        }
        var map = state.config.chapterIndexMaps[key];
        if (!isObject(map)) { map = {}; }
        var count = 0;
        for (var t in map) { if (has(map, t)) { count += 1; } }
        if (count > 600) { map = {}; }   // 防止异常书籍无限增长
        map[lower(title)] = intValue(androidIndex, 0);
        state.config.chapterIndexMaps[key] = map;
    }

    function androidChapterIndex(key, title, fallback) {
        title = normalizeText(title);
        if (!key || !title || !isObject(state.config.chapterIndexMaps)) {
            return fallback;
        }
        var map = state.config.chapterIndexMaps[key];
        if (!isObject(map)) { return fallback; }
        var mapped = map[lower(title)];
        return mapped === undefined ? fallback : intValue(mapped, fallback);
    }

    function applyRemoteProgress(record, preferredKey) {
        var remote = remoteProgressEntry(record);
        if (!remote) { return 0; }

        var keys = [];
        if (preferredKey && progressMap()[preferredKey]) {
            keys = [preferredKey];
        } else {
            keys = matchBookKeys(remote.name, remote.author);
        }

        if (!keys.length) {
            // 书架上还没有这本书：先挂在 pending 里，等书加入后再按书名匹配
            var pendingKey = "legado-" +
                digest(remote.name + "\n" + remote.author).slice(0, 12);
            var existing = progressMap()[pendingKey];
            if (!existing || progressAhead(remote, existing)) {
                var pending = merge(existing || {}, remote);
                pending.key = pendingKey;
                pending.pending = true;
                if (typeof pending.ratio !== "number") { pending.ratio = 0; }
                progressMap()[pendingKey] = pending;
                return 1;
            }
            return 0;
        }

        var applied = 0;
        for (var i = 0; i < keys.length; i += 1) {
            var key = keys[i];
            rememberChapterIndex(key, remote.chapterTitle, remote.chapterIndex);
            var localRemote = remapRemoteChapter(key, remote);
            var current = progressMap()[key];
            if (!current) {
                var fresh = merge({}, localRemote);
                fresh.key = key;
                fresh.name = localRemote.name;
                fresh.author = localRemote.author || "";
                fresh.chapterIndex = localRemote.chapterIndex;
                fresh.pos = localRemote.pos;
                fresh.chapterTitle = localRemote.chapterTitle;
                fresh.updatedAt = localRemote.updatedAt;
                fresh.ratio = 0;
                progressMap()[key] = fresh;
                applied += 1;
                continue;
            }

            // 即使位置没变，也把安卓端的作者名补上；否则 iOS 上传时
            // 会写成“书名_.json”，安卓按“书名_作者.json”就匹配不到了。
            var metadataChanged = false;
            if (!normalizeText(current.author) && localRemote.author) {
                current.author = localRemote.author;
                metadataChanged = true;
            }
            if (!normalizeText(current.name) && localRemote.name) {
                current.name = localRemote.name;
                metadataChanged = true;
            }
            progressMap()[key] = current;

            if (!progressAhead(localRemote, current)) {
                if (metadataChanged) { applied += 1; }
                continue;
            }
            var merged = merge(current, localRemote);
            merged.key = key;
            merged.name = localRemote.name;
            merged.author = localRemote.author || merged.author || "";
            merged.chapterIndex = localRemote.chapterIndex;
            merged.pos = localRemote.pos;
            merged.chapterTitle = localRemote.chapterTitle ||
                merged.chapterTitle || "";
            merged.updatedAt = localRemote.updatedAt;
            if (typeof merged.ratio !== "number") { merged.ratio = 0; }
            progressMap()[key] = merged;
            applied += 1;
        }
        return applied;
    }

    // 只下载能和本地已知书（书名_作者）对上的进度文件；
    // 对不上的限量尝试几个，其余跳过，避免 bookProgress 里几百个
    // 文件把 iPhone 4S 拖垮。
    function progressFileMatcher() {
        var wanted = {};
        var books = knownBooks();
        for (var i = 0; i < books.length; i += 1) {
            var file = progressFileName(books[i].name || "",
                books[i].author || "");
            wanted[lower(file)] = true;
            try { wanted[lower(decodeURIComponent(file))] = true; } catch (e) { }
        }
        return function (fileName) {
            var base = lower(localName(fileName || ""));
            if (wanted[base]) { return true; }
            try { return !!wanted[lower(decodeURIComponent(base))]; } catch (e) {
                return false;
            }
        };
    }

    function pullBookProgressFiles(dav) {
        var dir = "bookProgress";
        var entries = [];
        try {
            entries = dav.list(dir);
        } catch (e) {
            entries = [];
        }
        var cache = isObject(state.config.progressCache)
            ? state.config.progressCache : {};
        var nextCache = {};
        var matches = progressFileMatcher();
        var unknownBudget = 80;
        var files = 0;
        var downloaded = 0;
        var applied = 0;
        var errors = [];
        for (var i = 0; i < entries.length; i += 1) {
            var entry = entries[i];
            if (entry.isDir || extOf(entry.name) !== ".json") { continue; }
            if (files >= 400) { break; }
            files += 1;

            var signature = String(entry.modified || "") + "|" +
                intValue(entry.size, 0);
            nextCache[entry.name] = signature;
            if (cache[entry.name] === signature && signature !== "|0") {
                continue; // 上次拉过且没变
            }
            if (!matches(entry.name)) {
                if (unknownBudget <= 0) { continue; }
                unknownBudget -= 1;
            }

            var path = entry.path || (dir + "/" + entry.name);
            var text = "";
            try {
                text = dav.download(path, false, 20);
            } catch (e) {
                errors.push(errorText(e));
                continue;
            }
            if (!text) { continue; }
            downloaded += 1;
            applied += applyRemoteProgress(parseJSON(text, null), "");
        }
        state.config.progressCache = nextCache;
        saveConfig();
        return { files: files, downloaded: downloaded,
            applied: applied, errors: errors };
    }

    function pullLegacyProgress(dav) {
        var raw = "";
        try {
            raw = dav.download("progress.json", false, 20);
        } catch (e) {
            return { found: false, applied: 0 };
        }
        if (!raw) { return { found: false, applied: 0 }; }
        var payload = parseJSON(raw, null);
        if (!payload) { return { found: true, applied: 0 }; }
        var applied = 0;
        if (isObject(payload.books)) {
            for (var key in payload.books) {
                if (!has(payload.books, key)) { continue; }
                applied += applyRemoteProgress(payload.books[key], key);
            }
        } else if (isArray(payload)) {
            for (var i = 0; i < payload.length; i += 1) {
                applied += applyRemoteProgress(payload[i], "");
            }
        }
        return { found: true, applied: applied };
    }

    function pullReadRecord(dav) {
        var raw = "";
        try {
            raw = dav.download("readRecord.json", false, 25);
        } catch (e) {
            return 0;
        }
        if (!raw) { return 0; }
        var payload = parseJSON(raw, null);
        var list = isObject(payload) && isArray(payload.records)
            ? payload.records : payload;
        if (!isArray(list)) { return 0; }
        var applied = 0;
        for (var i = 0; i < list.length; i += 1) {
            applied += applyRemoteProgress(list[i], "");
        }
        return applied;
    }

    // 把 readRecord / readRecordDetail 数组汇总为秒。
    // HapeLee/legado-with-MD3: readRecord.json = [{deviceId,bookName,bookAuthor,readTime(ms),lastRead}]
    // readTime 多为毫秒；按 (deviceId,bookName,bookAuthor) 去重取最大值，避免重复记录翻倍。
    function sumLegadoRecords(parsed, dedupe) {
        var records = parsed;
        if (isObject(parsed) && !isArray(parsed)) {
            records = parsed.readRecord || parsed.readRecordDetail ||
                parsed.records || parsed.data || parsed.list || parsed.all ||
                parsed.items || valuesOf(parsed);
            // 有些格式是按书分组的
            if (!isArray(records)) {
                var all = [];
                for (var k in parsed) {
                    if (!has(parsed, k)) { continue; }
                    var v = parsed[k];
                    if (isArray(v)) { all = all.concat(v); }
                    else if (isObject(v) && isArray(v.records)) { all = all.concat(v.records); }
                    else if (isObject(v)) { all.push(v); }
                }
                if (all.length) { records = all; }
            }
        }
        if (!isArray(records)) { return 0; }
        var seen = {};
        var sum = 0;
        for (var i = 0; i < records.length; i += 1) {
            var r = records[i];
            if (!isObject(r)) { continue; }
            var rawT = r.readTime;
            if (rawT === null || rawT === undefined) { rawT = r.totalReadTime; }
            if (rawT === null || rawT === undefined) { rawT = r.readingTime; }
            if (rawT === null || rawT === undefined) { rawT = r.time; }
            if (rawT === null || rawT === undefined) { rawT = r.sumTime; }
            if (rawT === null || rawT === undefined) { rawT = r.duration; }
            if (rawT === null || rawT === undefined) { rawT = r.readSeconds; }
            if (rawT === null || rawT === undefined) { rawT = r.read_time; }
            var t = typeof rawT === "number" ? Math.floor(rawT) : intValue(rawT, 0);
            if (t <= 0) { continue; }
            // legado 的 readTime 单位是毫秒（单日/单本都可能小于一天）。
            // 之前用 > 1天 才换算，导致日明细被当成“秒”，统计放大成几万小时。
            if (t >= 10000 && t < 86400 * 365 * 100) { 
                // 如果看起来像毫秒（小于100年毫秒数），转换为秒
                // 但也要考虑如果已经是秒且很大，可能是秒
                if (t > 86400 * 1000) { // 大于100天的毫秒数
                    t = Math.floor(t / 1000);
                } else {
                    t = Math.floor(t / 1000);
                }
            } else if (t >= 10000) {
                // 可能已经是秒
            }
            if (t <= 0) { continue; }
            // 单条超过 100 年视为脏数据（更宽松以兼容MD3）
            if (t > 86400 * 365 * 100) { continue; }
            if (dedupe !== false) {
                // readRecord：同一 (设备,书) 只保留一条，避免重复记录翻倍
                var key = trim((r.deviceId || r.device || "") + "|" +
                    (r.bookName || r.name || r.bookTitle || "") + "|" +
                    (r.bookAuthor || r.author || ""));
                if (key !== "||") {
                    if (seen[key] && seen[key] >= t) { continue; }
                    seen[key] = t;
                } else {
                    // 如果没有设备信息，也要去重同一本书的记录
                    var bookKey = trim((r.bookName || r.name || r.bookTitle || "") + "|" +
                        (r.bookAuthor || r.author || ""));
                    if (bookKey !== "|") {
                        if (seen[bookKey] && seen[bookKey] >= t) { continue; }
                        seen[bookKey] = t;
                    }
                }
            }
            sum += t;
        }
        // 容错：明细与汇总不要重复加，调用方只取较大值
        return sum;
    }

    function sumLegadoTimeFile(dav, name) {
        var raw = "";
        try { raw = dav.download(name, false, 15); } catch (e) { return 0; }
        if (!raw) { return 0; }
        return sumLegadoRecords(parseJSON(raw, null), lower(name).indexOf("detail") < 0);
    }

    // WebDAV 上 legado 只同步 bookProgress，阅读记录通常只存在于备份 zip 里。
    // 这里找最新的 backup*.zip，解出 readRecord.json 汇总（1 小时最多一次）。
    function pullLegadoReadTimeFromBackup(dav) {
        var nowMs = now();
        if (nowMs - intValue(state.config.readTimeBackupAt, 0) < 3600 * 1000) {
            return 0;
        }
        state.config.readTimeBackupAt = nowMs;
        saveConfig();

        var candidates = [];
        var dirs = ["", "backup", "备份"];
        for (var di = 0; di < dirs.length; di += 1) {
            var entries = [];
            try { entries = dav.list(dirs[di]); } catch (e) { entries = []; }
            for (var ei = 0; ei < entries.length; ei += 1) {
                var entry = entries[ei];
                if (!entry || entry.isDir) { continue; }
                var name = lower(entry.name || entry.path || "");
                if (name.slice(-4) !== ".zip") { continue; }
                if (name.indexOf("backup") < 0 && name.indexOf("备份") < 0) { continue; }
                candidates.push(entry);
            }
        }
        if (!candidates.length) { return 0; }
        candidates.sort(function (a, b) {
            var sa = intValue(a.size, 0), sb = intValue(b.size, 0);
            if (sa !== sb) { return sb - sa; }
            return String(b.modified || "").localeCompare(String(a.modified || ""));
        });

        var target = root() + "/readrecord-backup.zip";
        var total = 0;
        for (var ci = 0; ci < candidates.length && ci < 2; ci += 1) {
            if (!nat.zipList || !nat.zipReadText) { return 0; }
            try {
                dav.downloadTo(candidates[ci].path, target);
                var names = zipEntries(target);
                var pick = "";
                for (var zi = 0; zi < names.length; zi += 1) {
                    var n = lower(names[zi]);
                    if (n.slice(-15) === "readrecord.json") { pick = names[zi]; break; }
                }
                if (!pick) { continue; }
                var raw = nat.zipReadText(target, pick) || "";
                var value = sumLegadoRecords(parseJSON(raw, null));
                if (value > total) { total = value; }
            } catch (e2) { /* 备份格式不同就跳过 */ }
        }
        return total;
    }

    // 累计阅读时长（秒）：先找根目录/备份目录里的 readRecord.json，
    // 再尝试 legado 备份 zip（备份通常在 WebDAV 根目录，不在 legado/ 下）。
    function pullLegadoReadTime(dav) {
        var total = 0;
        var davs = [dav];
        try {
            var cfg = state.config.webdav || {};
            if (trim(cfg.dir || "")) {
                davs.push(new Dav({ url: cfg.url, username: cfg.username,
                                    password: cfg.password, dir: "" }));
            }
        } catch (e0) { /* 忽略 */ }
        var names = ["readRecord.json", "backup/readRecord.json",
                     "readRecord/readRecord.json", "readRecordDetail.json",
                     "readRecord/readRecordDetail.json", "ReadRecord.json",
                     "readRecord/ReadRecord.json", "backup/ReadRecord.json"];
        for (var di = 0; di < davs.length; di += 1) {
            for (var ni = 0; ni < names.length; ni += 1) {
                var raw = "";
                try { raw = davs[di].download(names[ni], false, 12); } catch (e) { raw = ""; }
                if (!raw) { continue; }
                var sum = sumLegadoRecords(parseJSON(raw, null),
                    lower(names[ni]).indexOf("detail") < 0);
                if (sum > total) { total = sum; }
            }
        }
        if (total <= 0) {
            for (var bi = 0; bi < davs.length && total <= 0; bi += 1) {
                total = pullLegadoReadTimeFromBackup(davs[bi]);
            }
        }
        // 合理上限 50 年
        if (total > 86400 * 365 * 50) { total = 0; }
        return total;
    }

    // 旧版本把毫秒当日秒处理，缓存过错误的 legado 桶；升级后清一次强制重算。
    function migrateReadStats() {
        if (intValue(state.config.readStatsVersion, 0) >= 2) { return; }
        state.config.readStatsVersion = 2;
        if (isObject(state.config.readStatsDevices)) {
            delete state.config.readStatsDevices["legado-android"];
        }
        state.config.readStatsPullAt = 0;
        state.config.readTimeBackupAt = 0;
        saveConfig();
    }

    // 阅读时长同步：readStats.json 里每个设备只写自己的桶，
    // 拉取时把所有设备（除本机）的时长加起来，避免多端互相同步时重复累计。
    function pullReadStats(dav) {
        var merged = 0;
        var myId = state.config.deviceId;
        // 60 秒内不重复访问 WebDAV（stats.get 会被首页频繁调用）
        var pullAt = intValue(state.config.readStatsPullAt, 0);
        if (now() - pullAt < 60 * 1000) {
            for (var pid in state.config.readStatsDevices) {
                if (!has(state.config.readStatsDevices, pid) || pid === myId) { continue; }
                merged += intValue(state.config.readStatsDevices[pid], 0);
            }
            return merged;
        }
        state.config.readStatsPullAt = now();
        var raw = "";
        try { raw = dav.download("readStats.json", false, 15); } catch (e) { raw = ""; }
        if (raw) {
            var payload = parseJSON(raw, null);
            if (isObject(payload) && isObject(payload.devices)) {
                state.config.readStatsDevices = copy(payload.devices);
            }
        }
        if (!isObject(state.config.readStatsDevices)) {
            state.config.readStatsDevices = {};
        }
        // 合并安卓 legado 的阅读时长（best-effort）
        var legadoSec = pullLegadoReadTime(dav);
        if (legadoSec > 0) {
            state.config.readStatsDevices["legado-android"] = legadoSec;
        }
        var maxBucket = 86400 * 365 * 20;
        for (var id in state.config.readStatsDevices) {
            if (!has(state.config.readStatsDevices, id) || id === myId) { continue; }
            var bucket = intValue(state.config.readStatsDevices[id], 0);
            if (bucket <= 0 || bucket > maxBucket) { continue; }
            merged += bucket;
        }
        saveConfig();
        return merged;
    }

    function pushReadStats(dav) {
        var devices = isObject(state.config.readStatsDevices)
            ? copy(state.config.readStatsDevices) : {};
        devices[state.config.deviceId] = intValue(state.config.readSeconds, 0);
        state.config.readStatsDevices = devices;
        saveConfig();
        dav.upload("readStats.json", JSON.stringify({
            updatedAt: now(),
            devices: devices
        }, null, 2));
    }

    // 云端其他设备累计的阅读时长（秒）
    function remoteReadSeconds() {
        var total = 0;
        var devices = isObject(state.config.readStatsDevices)
            ? state.config.readStatsDevices : {};
        var myId = state.config.deviceId;
        var maxPerDevice = 86400 * 365 * 20;   // 单设备超过 20 年视为脏数据
        for (var id in devices) {
            if (!has(devices, id) || id === myId) { continue; }
            var value = intValue(devices[id], 0);
            if (value <= 0 || value > maxPerDevice) { continue; }
            total += value;
        }
        return total;
    }

    function pullProgress(dav) {
        var applied = 0;
        var android = pullBookProgressFiles(dav);
        applied += android.applied;

        // 阅读时长：不同设备分桶，直接全部拉下来
        pullReadStats(dav);

        // 旧版 iOS 自己写的 progress.json，保留兼容；位置规则会避免回退
        var legacy = pullLegacyProgress(dav);
        applied += legacy.applied;

        // 只有完全没有安卓进度文件时，才回退到 readRecord.json，
        // 避免把很久以前的阅读统计当成当前进度。
        if (!android.files && !legacy.found) {
            applied += pullReadRecord(dav);
        }

        if (applied > 0) { saveProgress(); }
        saveConfig();   // 保存从云端学到的章节号映射
        return {
            pulled: applied,
            total: countKeys(progressMap()),
            files: android.files,
            downloaded: android.downloaded
        };
    }

    // 快速拉取单本书的进度（避免全量拉取 bookProgress/ 目录）
    function pullBookProgressSingle(dav, key) {
        var applied = 0;
        var entry = (progressMap && progressMap()[key]) || null;
        if (!entry) {
            // 尝试从书架信息构造
            try {
                var shelf = state.shelf || {};
                var books = shelf.books || {};
                entry = books[key] || null;
            } catch (e) {
                entry = null;
            }
        }
        if (!entry) { return { pulled: 0 }; }
        var name = normalizeText(entry.name);
        if (!name) { return { pulled: 0 }; }
        var author = entry.author || "";
        var file = "bookProgress/" + progressFileName(name, author);
        var raw = "";
        try {
            raw = dav.download(file, false, 10);
        } catch (e) {
            return { pulled: 0, error: errorText(e) };
        }
        if (!raw) { return { pulled: 0 }; }
        applied += applyRemoteProgress(parseJSON(raw, null), key);
        if (applied > 0) { saveProgress(); }
        saveConfig();
        return { pulled: applied };
    }

    function pushBookProgressEntry(dav, key, checkRemote) {
        var entry = progressMap()[key];
        if (!entry) { return "missing"; }
        var name = normalizeText(entry.name);
        if (!name) { return "skipped"; }
        if (String(key).indexOf("legado-") === 0) { return "skipped"; }

        var file = "bookProgress/" + progressFileName(name, entry.author || "");
        if (checkRemote) {
            var raw = "";
            try {
                raw = dav.download(file, false, 15);
            } catch (e) {
                raw = "";
            }
            var remoteRaw = remoteProgressEntry(parseJSON(raw, null));
            // 章节序号按本机分章换算（与安卓章数不一致时，直接比较序号会
            // 误判“谁更靠前”，从而把本机进度覆盖到安卓上，产生整章级偏差）。
            var remote = remoteRaw ? remapRemoteChapter(key, remoteRaw) : null;
            if (remoteRaw) {
                rememberChapterIndex(key, remoteRaw.chapterTitle, remoteRaw.chapterIndex);
            }
            if (remote && sameText(remote.name, name) &&
                progressAhead(remote, entry)) {
                applyRemoteProgress(remote, key);
                return "adopted";
            }
        }

        dav.upload(file, JSON.stringify({
            name: name,
            author: entry.author || "",
            // 换算成安卓的章节号（若之前从云端学到过映射）
            durChapterIndex: androidChapterIndex(key, entry.chapterTitle,
                intValue(entry.chapterIndex, 0)),
            durChapterPos: intValue(entry.pos, 0),
            durChapterTime: intValue(entry.updatedAt, now()),
            durChapterTitle: entry.chapterTitle || ""
        }, null, 2));
        return "pushed";
    }

    function pushProgress(dav, options) {
        options = options || {};
        dav.mkdir("bookProgress");

        var keys = options.keys;
        if (!keys) {
            keys = [];
            for (var key in progressMap()) {
                if (has(progressMap(), key)) { keys.push(key); }
            }
        }

        var pushed = 0;
        var adopted = 0;
        var skipped = 0;
        var done = [];
        var errors = [];
        for (var i = 0; i < keys.length; i += 1) {
            try {
                var result = pushBookProgressEntry(dav, keys[i],
                    options.checkRemote === true);
                if (result === "pushed") {
                    pushed += 1;
                    done.push(keys[i]);
                } else if (result === "adopted") {
                    adopted += 1;
                    done.push(keys[i]);
                } else {
                    skipped += 1;
                }
            } catch (e) {
                errors.push(errorText(e));
            }
        }
        if (adopted > 0) { saveProgress(); }

        // 阅读时长（readStats.json 很小，顺手带上）
        try { pushReadStats(dav); } catch (e) { /* 统计失败不影响进度 */ }

        // 完整上传时额外留一份旧格式备份，方便其他/老版本 iOS 恢复
        if (!options.keys) {
            try {
                dav.upload("progress.json", JSON.stringify({
                    version: 2,
                    updatedAt: now(),
                    books: progressMap()
                }, null, 2));
            } catch (e) {
                errors.push(errorText(e));
            }
        }

        if (errors.length && !pushed && !adopted) {
            throw new Error(errors[0]);
        }
        return {
            pushed: pushed,
            adopted: adopted,
            skipped: skipped,
            done: done,
            total: countKeys(progressMap())
        };
    }

    function legadoRecords(books) {
        var records = [];
        for (var key in (books || {})) {
            if (!has(books, key)) { continue; }
            var entry = books[key];
            records.push({
                bookName: entry.name || "",
                author: entry.author || "",
                durChapterIndex: intValue(entry.chapterIndex, 0),
                durChapterPos: intValue(entry.pos, 0),
                durChapterTime: intValue(entry.updatedAt, now()),
                durChapterTitle: entry.chapterTitle || "",
                readTime: 0,
                lastRead: intValue(entry.updatedAt, now())
            });
        }
        return records;
    }

    // ------------------------------------------------------------------ cloud --

    // 安卓版（阅读）习惯把备份放在 <WebDAV>/legado/backup，书籍放在别的子目录，
    // 只列一层会“只看到压缩包备份、看不到书”。这里向下递归查找 3 层。
    var CLOUD_MAX_DEPTH = 3;
    var CLOUD_MAX_BOOKS = 400;
    var CLOUD_MAX_DIRS = 60;

    function cloudSkipDir(name) {
        var text = lower(trim(name || ""));
        if (!text || text.charAt(0) === ".") { return true; }
        return text === "__macosx" || text === "$recycle.bin" ||
            text === "lost+found" || text === "node_modules";
    }

    function isCoverImage(name) {
        var ext = extOf(name);
        return ext === ".jpg" || ext === ".jpeg" || ext === ".png" ||
            ext === ".gif" || ext === ".bmp";
    }

    function baseNameOf(name) {
        return String(name || "").replace(/\.[^.]+$/, "");
    }

    function scanCloud(dav, dir, depth, ctx) {
        if (depth > CLOUD_MAX_DEPTH || ctx.dirs >= CLOUD_MAX_DIRS ||
            ctx.books.length >= CLOUD_MAX_BOOKS) {
            return;
        }
        var entries;
        try {
            entries = dav.list(dir);
        } catch (e) {
            if (depth === 0) { throw e; }
            ctx.errors.push(errorText(e));
            return;
        }
        ctx.dirs += 1;
        var subdirs = [];
        // 先收集同目录下的图片，作为 TXT 的封面（书名.jpg / cover.jpg）
        var images = {};
        for (var i = 0; i < entries.length; i += 1) {
            var entry = entries[i];
            if (entry.isDir) {
                if (!cloudSkipDir(entry.name)) { subdirs.push(entry); }
                continue;
            }
            if (isCoverImage(entry.name)) {
                var base = lower(baseNameOf(entry.name));
                images[base] = entry.path;
                if (base === "cover" || base === "folder" ||
                    base === "封面") {
                    images["\u0000dir"] = entry.path;
                }
            }
        }
        for (var k = 0; k < entries.length; k += 1) {
            var file = entries[k];
            if (file.isDir) { continue; }
            var ext = extOf(file.name);
            if (ext !== ".txt" && ext !== ".epub" && ext !== ".zip") { continue; }
            file.folder = dir || "";
            if (ext !== ".zip") {
                file.cover = images[lower(baseNameOf(file.name))] ||
                    images["\u0000dir"] || "";
            }
            ctx.books.push(file);
            if (ctx.books.length >= CLOUD_MAX_BOOKS) { return; }
        }
        for (var j = 0; j < subdirs.length; j += 1) {
            if (ctx.books.length >= CLOUD_MAX_BOOKS ||
                ctx.dirs >= CLOUD_MAX_DIRS) {
                return;
            }
            scanCloud(dav, subdirs[j].path, depth + 1, ctx);
        }
    }

    function cloudBooks(dav) {
        // 安卓版“阅读”导出的书固定在 <同步目录>/books 下，先扫这里；
        // 一本书都没有（或目录不存在）再退回同步目录根部，
        // 兼容用户自己建立的其他目录结构。
        var ctx = { books: [], dirs: 0, errors: [] };
        try {
            scanCloud(dav, "books", 0, ctx);
        } catch (e) {
            ctx.books = [];
        }
        if (!ctx.books.length) {
            ctx = { books: [], dirs: 0, errors: [] };
            scanCloud(dav, "", 0, ctx);
        }
        return ctx.books;
    }

    function sortCloudBooks(books) {
        books.sort(function (a, b) {
            var fa = String(a.folder || "");
            var fb = String(b.folder || "");
            if (fa !== fb) { return fa.localeCompare(fb); }
            return String(a.name).localeCompare(String(b.name));
        });
        return books;
    }

    function importBackup(path) {
        var entries = zipEntries(path);
        var shelfItems = zipJSON(path, entries, "bookshelf.json");
        var records = zipJSON(path, entries, "readRecord.json");
        if (!shelfItems) { shelfItems = []; }
        if (isObject(shelfItems) && !isArray(shelfItems)) {
            shelfItems = shelfItems.books || valuesOf(shelfItems);
        }
        if (!isArray(shelfItems)) { shelfItems = []; }
        if (!records) { records = []; }
        if (isObject(records) && !isArray(records)) {
            records = records.records || valuesOf(records);
        }
        if (!isArray(records)) { records = []; }

        var books = [];
        var progress = {};
        for (var i = 0; i < shelfItems.length; i += 1) {
            var item = shelfItems[i];
            if (!isObject(item)) { continue; }
            var sourceUrl = item.origin || item.sourceUrl || "";
            var bookUrl = item.bookUrl || "";
            if (!bookUrl) { continue; }
            var key = bookKey(sourceUrl, bookUrl);
            books.push({
                key: key,
                name: item.name || "",
                author: item.author || "",
                sourceUrl: sourceUrl,
                sourceName: item.originName || "",
                bookUrl: bookUrl,
                coverUrl: item.coverUrl || "",
                intro: item.intro || "",
                lastChapter: item.latestChapterTitle || "",
                addedAt: intValue(item.durChapterTime, now())
            });
            progress[key] = {
                key: key,
                name: item.name || "",
                author: item.author || "",
                chapterIndex: intValue(item.durChapterIndex, 0),
                chapterTitle: item.durChapterTitle || "",
                pos: intValue(item.durChapterPos, 0),
                updatedAt: intValue(item.durChapterTime, now())
            };
        }
        for (var j = 0; j < records.length; j += 1) {
            var record = records[j];
            if (!isObject(record)) { continue; }
            var name = record.bookName || "";
            var author = record.author || "";
            for (var b = 0; b < books.length; b += 1) {
                if (books[b].name === name && books[b].author === author) {
                    progress[books[b].key] = {
                        key: books[b].key,
                        name: name,
                        author: author,
                        chapterIndex: intValue(record.durChapterIndex, 0),
                        chapterTitle: record.durChapterTitle || "",
                        pos: intValue(record.durChapterPos, 0),
                        updatedAt: intValue(record.durChapterTime, now())
                    };
                    break;
                }
            }
        }
        return { books: books, progress: progress };
    }

    function valuesOf(obj) {
        var out = [];
        for (var key in (obj || {})) {
            if (has(obj, key) && key !== "books" && key !== "records") {
                out.push(obj[key]);
            }
        }
        return out;
    }

    function zipJSON(path, entries, suffix) {
        suffix = lower(suffix);
        for (var i = 0; i < entries.length; i += 1) {
            var name = lower(entries[i]).replace(/\\/g, "/");
            if (name.slice(-suffix.length) === suffix) {
                return parseJSON(nat.zipReadText(path, entries[i]), null);
            }
        }
        return null;
    }

    function importBackupIntoState(path) {
        var result = importBackup(path);
        for (var i = 0; i < result.books.length; i += 1) {
            var book = result.books[i];
            var key = book.key;
            var existing = (state.shelf.books || {})[key] || {};
            var item = copy(book);
            item.addedAt = existing.addedAt || book.addedAt;
            item.updatedAt = now();
            state.shelf.books[key] = item;
        }
        saveShelf();
        state.progress.books = mergeBooks(progressMap(), result.progress);
        saveProgress();
        return {
            books: result.books.length,
            progress: countKeys(result.progress)
        };
    }

    // -------------------------------------------------------------- settings --

    function storeInfo() {
        return {
            root: storeRoot(),
            booksDir: booksDir(),
            fontsDir: fontsDir(),
            inboxDir: inboxDir()
        };
    }

    function settingsView() {
        var webdav = copy(state.config.webdav || {});
        if (webdav.password) {
            webdav.password = "******";
            webdav.hasPassword = true;
        }
        return {
            autoPush: state.config.autoPush !== false,
            fontSize: intValue(state.config.fontSize, 18),
            webdav: webdav,
            store: storeInfo(),
            sources: (state.sources || []).length,
            books: countKeys(state.shelf.books),
            localBooks: countKeys(state.local)
        };
    }

    function settingsSave(params) {
        if (has(params, "autoPush")) {
            state.config.autoPush = params.autoPush ? true : false;
        }
        if (has(params, "fontSize")) {
            state.config.fontSize = Math.max(12, Math.min(32, intValue(params.fontSize, 18)));
        }
        if (isObject(params.webdav)) {
            var webdav = state.config.webdav || {};
            var keys = ["url", "username", "password", "dir"];
            for (var i = 0; i < keys.length; i += 1) {
                var key = keys[i];
                if (!has(params.webdav, key)) { continue; }
                if (key === "password" && params.webdav[key] === "******") { continue; }
                if (key === "dir") {
                    webdav.dir = trim(params.webdav[key] || "") || "legado";
                } else {
                    webdav[key] = params.webdav[key];
                }
            }
            state.config.webdav = webdav;
        }
        saveConfig();
        return { ok: true };
    }

    function setStoreRoot(params) {
        var path = trim(params.path || "");
        if (!path) { throw new Error("请输入保存路径"); }
        if (!nat.setStoreRoot) { throw new Error("当前版本不支持修改保存路径"); }
        var oldBooks = booksDir();
        var result = parseJSON(nat.setStoreRoot(path), null);
        if (!result) { throw new Error("保存路径设置失败"); }
        if (result.ok !== true) {
            throw new Error(result.error || "目录不可写");
        }
        var newBooks = String(result.booksDir || booksDir()).replace(/\/+$/, "");
        remapLocalPaths(oldBooks, newBooks);
        textCache = {};
        textCacheKeys = [];
        state.config.storeRoot = result.root || "";
        saveConfig();
        return merge({ ok: true }, storeInfo());
    }

    // ---------------------------------------------------------------- sources --

    function sourcesSave(params) {
        var incoming = params.sources;
        if (!incoming && params.text) {
            incoming = parseJSON(params.text, null);
        }
        if (isObject(incoming) && isArray(incoming.sources)) {
            incoming = incoming.sources;
        }
        if (!isArray(incoming)) {
            throw new Error("书源必须是数组");
        }
        var clean = [];
        for (var i = 0; i < incoming.length; i += 1) {
            if (isObject(incoming[i]) && trim(incoming[i].bookSourceUrl || "")) {
                clean.push(incoming[i]);
            }
        }
        if (params.mode === "append") {
            var existing = {};
            for (var j = 0; j < state.sources.length; j += 1) {
                existing[state.sources[j].bookSourceUrl] = state.sources[j];
            }
            for (var k = 0; k < clean.length; k += 1) {
                existing[clean[k].bookSourceUrl] = clean[k];
            }
            clean = valuesOf(existing);
        }
        state.sources = clean;
        saveSources();
        return { count: clean.length };
    }

    function sourcesList() {
        var out = [];
        for (var i = 0; i < state.sources.length; i += 1) {
            var item = state.sources[i];
            out.push({
                name: item.bookSourceName || item.bookSourceUrl || "未命名",
                url: item.bookSourceUrl || "",
                type: intValue(item.bookSourceType, 0),
                group: item.bookSourceGroup || ""
            });
        }
        return { sources: out, count: out.length };
    }

    // -------------------------------------------------------------- inbox ----

    function scanInbox() {
        var folders = [
            { path: inboxDir(), clean: true },
            { path: nat.docsDir ? nat.docsDir() : "", clean: false }
        ];
        var result = { books: 0, progress: 0, sources: 0, errors: [] };
        for (var f = 0; f < folders.length; f += 1) {
            var folder = folders[f];
            if (!folder.path) { continue; }
            var names = parseJSON(nat.listDir(folder.path), []) || [];
            for (var i = 0; i < names.length; i += 1) {
                var name = names[i];
                if (name === "yuedu" || name.charAt(0) === ".") { continue; }
                var path = folder.path + "/" + name;
                var ext = extOf(name);
                if (ext !== ".txt" && ext !== ".epub" && ext !== ".zip" && ext !== ".json") {
                    continue;
                }
                try {
                    if (ext === ".txt" || ext === ".epub") {
                        guardFileSize(path, name);
                        var book = importLocalFile(name, path);
                        shelfAdd(book);
                        result.books += 1;
                    } else if (ext === ".zip") {
                        var imported = importBackupIntoState(path);
                        result.books += imported.books;
                        result.progress += imported.progress;
                    } else if (ext === ".json") {
                        var text = nat.decodeText(nat.readBase64(path));
                        var saved = sourcesSave({ sources: parseJSON(text, []), mode: "append" });
                        result.sources = saved.count;
                    }
                    if (folder.clean) { nat.remove(path); }
                } catch (e) {
                    result.errors.push(name + ": " + errorText(e));
                }
            }
        }
        return result;
    }

    // ------------------------------------------------------------ dispatcher --

    function dispatch(action, params) {
        loadState();
        action = String(action || "");

        if (action === "ping") {
            return { ok: true, name: "yuedu-lite", version: "1.5", onDevice: true };
        }
        if (action === "shelf.list") {
            return { books: shelfList() };
        }
        if (action === "shelf.add") {
            return { book: shelfAdd(params.book || params) };
        }
        if (action === "shelf.remove") {
            return { removed: shelfRemove(params.key) };
        }
        if (action === "sources.list") {
            return sourcesList();
        }
        if (action === "sources.save") {
            return sourcesSave(params);
        }
        if (action === "search") {
            return searchBooks(params);
        }
        if (action === "book.info") {
            return bookInfoAction(params);
        }
        if (action === "toc") {
            return tocAction(params);
        }
        if (action === "content") {
            return contentAction(params);
        }
        if (action === "progress.get") {
            var key = trim(params.key || "");
            return { progress: key ? (progressMap()[key] || null) : progressMap() };
        }
        if (action === "progress.save") {
            return { progress: saveProgressEntry(params) };
        }
        if (action === "sync.pull") {
            var pullDav = davFromConfig();
            if (!pullDav.configured()) { throw new Error("尚未配置 WebDAV"); }
            return pullProgress(pullDav);
        }
        if (action === "sync.push") {
            var pushDav = davFromConfig();
            if (!pushDav.configured()) { throw new Error("尚未配置 WebDAV"); }
            // 不再整表下拉（那会逐本对比、在 4S 上很慢），
            // 改为上传前只检查当前这本书的云端文件；如果安卓端更靠后，
            // 就直接采纳云端进度而不是覆盖它。其它书的进度保持不动。
            var pushed = pushProgress(pushDav, { checkRemote: true });
            return {
                pulled: pushed.adopted,
                adopted: pushed.adopted,
                total: pushed.total,
                pushed: pushed.pushed,
                skipped: pushed.skipped
            };
        }
        if (action === "sync.pullBook" || action === "sync.pullBookProgress") {
            // 打开书之前调用：优先只拉取当前书的进度，避免全量同步导致阻塞
            var pullBookDav = davFromConfig();
            if (!pullBookDav.configured()) { return { pulled: 0, configured: false }; }
            pullBookDav.timeout = 12;
            try {
                var pullBookKey = trim(params.key || params.bookKey || "");
                if (pullBookKey) {
                    var single = pullBookProgressSingle(pullBookDav, pullBookKey);
                    return {
                        configured: true,
                        pulled: single.pulled || 0,
                        total: countKeys(progressMap())
                    };
                }
                // 兼容旧调用：仍然走全量拉取，但设置更短超时
                var pullBookResult = pullProgress(pullBookDav);
                return {
                    configured: true,
                    pulled: pullBookResult.pulled,
                    total: pullBookResult.total
                };
            } catch (e) {
                return { configured: true, pulled: 0, error: errorText(e) };
            }
        }
        if (action === "sync.pushBook") {
            // 退出阅读页时调用：跳过 30 秒节流，立刻把这本书的进度推上去。
            var pushBookDav = davFromConfig();
            if (!pushBookDav.configured()) { return { pushed: 0, configured: false }; }
            var pushBookKey = trim(params.key || "");
            if (!pushBookKey) { throw new Error("缺少 key"); }
            pushBookDav.timeout = 20;
            try {
                var pushBookResult = pushProgress(pushBookDav, {
                    keys: [pushBookKey],
                    checkRemote: true
                });
                delete pendingPush[pushBookKey];
                lastAutoPush = now();
                return {
                    configured: true,
                    pushed: pushBookResult.pushed,
                    adopted: pushBookResult.adopted
                };
            } catch (e) {
                return { configured: true, pushed: 0, error: errorText(e) };
            }
        }
        if (action === "store.get") {
            return storeInfo();
        }
        if (action === "store.setRoot") {
            return setStoreRoot(params);
        }
        if (action === "font.list") {
            var fonts = nat.fonts ? parseJSON(nat.fonts(), []) : [];
            return { fonts: isArray(fonts) ? fonts : [] };
        }
        if (action === "sync.test") {
            var testDav = davFromConfig();
            if (!testDav.configured()) { throw new Error("尚未配置 WebDAV"); }
            var testEntries = testDav.list("");
            return { ok: true, count: testEntries.length };
        }
        if (action === "cloud.list") {
            var webdavConfig = state.config.webdav || {};
            var listDav = new Dav(webdavConfig);
            if (!listDav.configured()) { throw new Error("尚未配置 WebDAV"); }
            var books;
            try {
                books = cloudBooks(listDav);
            } catch (e) {
                throw new Error("无法列出 " + listDav.target("") + "：" + errorText(e));
            }
            // 地址里已经带了一层目录、而“远程目录”又多填了一层时，
            // 退回 WebDAV 根目录再扫一次，保证和安卓版用同一套路径也能找到书。
            var usedRoot = false;
            if (!books.length && listDav.dir) {
                var looseDav = new Dav({
                    url: webdavConfig.url,
                    username: webdavConfig.username,
                    password: webdavConfig.password,
                    timeout: webdavConfig.timeout,
                    dir: ""
                });
                try {
                    books = cloudBooks(looseDav);
                    usedRoot = books.length > 0;
                } catch (e2) {
                    books = [];
                }
            }
            if (usedRoot) {
                for (var b = 0; b < books.length; b += 1) {
                    books[b].root = true;
                }
            }
            return { books: sortCloudBooks(books), dir: listDav.dir || "" };
        }
        if (action === "cloud.fetch") {
            return cloudFetch(params);
        }
        if (action === "cloud.import") {
            return cloudImport(params);
        }
        if (action === "settings.get") {
            return settingsView();
        }
        if (action === "webdav.config") {
            // 仅供原生更新流程使用：返回真实密码（settings.get 会打码）
            return copy(state.config.webdav || {});
        }
        if (action === "settings.save") {
            return settingsSave(params);
        }
        if (action === "export.legado") {
            return { records: legadoRecords(progressMap()) };
        }
        if (action === "local.import") {
            return { book: importLocal(params.name || "book.txt", params.base64 || "") };
        }
        if (action === "local.importPath") {
            var importPath = params.path || "";
            var name = localName(importPath || params.name || "book.txt");
            guardFileSize(importPath, name);
            return { book: importLocalFile(name, importPath) };
        }
        if (action === "backup.importPath") {
            return importBackupIntoState(params.path);
        }
        if (action === "inbox.scan") {
            return scanInbox();
        }
        if (action === "cache.clear") {
            clearCache();
            return { ok: true };
        }
        if (action === "cache.info") {
            var cacheBytes = 0;
            try {
                var names = parseJSON(nat.listDir(root() + "/cache"), []) || [];
                for (var ci = 0; ci < names.length; ci += 1) {
                    cacheBytes += intValue(nat.fileSize
                        ? nat.fileSize(root() + "/cache/" + names[ci])
                        : 0, 0);
                }
            } catch (e) { /* 大小算不出来就不显示 */ }
            return { ok: true, bytes: cacheBytes };
        }
        if (action === "stats.get") {
            // 若配置了 WebDAV，尽量刷新云端/安卓阅读时长（best-effort）
            try {
                if (davFromConfig && davFromConfig().configured()) {
                    pullReadStats(davFromConfig());
                }
            } catch (e3) {}
            // 按“书名”分组统计：同一本书可能有“有作者/无作者”两条进度，
            // 有作者时按作者去重，只有无作者记录时算 1 本，避免统计虚高。
            var byName = {};
            for (var sk in progressMap()) {
                if (!has(progressMap(), sk)) { continue; }
                var pe = progressMap()[sk];
                if (!pe) { continue; }
                var bname = lower(trim((pe.name) || ""));
                var bauth = lower(trim((pe.author) || ""));
                if (!bname && !bauth) { continue; }   // 脏数据不计入
                var groupKey = bname || ("?" + bauth);
                if (!byName[groupKey]) { byName[groupKey] = { authors: {}, anon: false }; }
                if (bauth) { byName[groupKey].authors[bauth] = true; }
                else { byName[groupKey].anon = true; }
            }
            var booksRead = 0;
            for (var gk in byName) {
                if (!has(byName, gk)) { continue; }
                var g = byName[gk];
                var authorCount = 0;
                for (var ak in g.authors) { if (has(g.authors, ak)) { authorCount += 1; } }
                booksRead += authorCount > 0 ? authorCount : 1;
            }
            var localSeconds = intValue(state.config.readSeconds, 0);
            var remoteSeconds = 0;
            try { remoteSeconds = remoteReadSeconds(); } catch (e2) { remoteSeconds = 0; }
            var totalSeconds = localSeconds + remoteSeconds;
            if (totalSeconds < 0) totalSeconds = 0;
            return {
                booksRead: booksRead,
                total: booksRead,
                localSeconds: localSeconds,
                remoteSeconds: remoteSeconds,
                totalSeconds: totalSeconds
            };
        }
        if (action === "stats.add") {
            var addSeconds = intValue(params.seconds, 0);
            if (addSeconds > 0) {
                state.config.readSeconds =
                    intValue(state.config.readSeconds, 0) + addSeconds;
                saveConfig();
            }
            return { ok: true, readSeconds: intValue(state.config.readSeconds, 0) };
        }
        if (action === "bookmark.list") {
            return { bookmarks: bookmarkList(trim(params.key || "")) };
        }
        if (action === "bookmark.add") {
            return { bookmark: bookmarkAdd(params) };
        }
        if (action === "bookmark.remove") {
            return bookmarkRemove(params);
        }
        if (action === "bookmark.clear") {
            return bookmarkClear(params);
        }
        throw new Error("未知操作: " + action);
    }

    function searchBooks(params) {
        var keyword = trim(params.q || "");
        if (!keyword) { throw new Error("缺少搜索词 q"); }
        var targets = [];
        if (params.source) {
            var urls = String(params.source).split(",");
            for (var i = 0; i < urls.length; i += 1) {
                if (trim(urls[i])) { targets.push(requireSource(urls[i])); }
            }
        } else {
            for (var j = 0; j < state.sources.length; j += 1) {
                targets.push(new Source(state.sources[j]));
            }
        }
        if (!targets.length) { throw new Error("还没有导入任何书源"); }

        var results = [];
        var errors = [];
        for (var k = 0; k < targets.length; k += 1) {
            try {
                var found = targets[k].search(keyword, 1);
                for (var m = 0; m < found.length && m < 20; m += 1) {
                    results.push(found[m]);
                }
            } catch (e) {
                errors.push({ source: targets[k].name, error: errorText(e) });
            }
        }
        var locals = localMatches(keyword);
        if (locals.length) {
            results = locals.concat(results);
        }
        return { books: results, errors: errors, count: results.length };
    }

    function bookInfoAction(params) {
        var bookUrl = trim(params.url || params.bookUrl || "");
        var sourceUrl = trim(params.source || params.sourceUrl || "");
        if (!bookUrl) { throw new Error("缺少 url"); }
        if (sourceUrl === "local") {
            return { book: localShelfEntry(bookUrl) };
        }
        var key = bookKey(sourceUrl, bookUrl);
        var cached = cacheGet(key, "info", bookUrl, 6 * 3600 * 1000);
        var info = cached;
        if (!info) {
            info = requireSource(sourceUrl).bookInfo(bookUrl);
            cacheSet(key, "info", bookUrl, info);
        }
        info = copy(info);
        info.key = key;
        if (!trim(info.name)) {
            var shelfInfo = (state.shelf.books || {})[key];
            info.name = shelfInfo && shelfInfo.name
                ? shelfInfo.name : (info.sourceName || "");
        }
        info.progress = progressForBook(key, info.name, info.author);
        return { book: info };
    }

    function tocAction(params) {
        var bookUrl = trim(params.url || params.bookUrl || "");
        var sourceUrl = trim(params.source || params.sourceUrl || "");
        if (!bookUrl) { throw new Error("缺少 url"); }
        if (sourceUrl === "local") {
            var localKey = trim(params.key || bookUrl);
            var localBook = copy((state.shelf.books || {})[localKey] ||
                localShelfEntry(localKey));
            localBook.key = localKey;
            if (!trim(localBook.intro || "")) {
                var metaEntry = localShelfEntry(localKey);
                if (trim(metaEntry.intro)) { localBook.intro = metaEntry.intro; }
                if (!trim(localBook.coverPath || "") && metaEntry.coverPath) {
                    localBook.coverPath = metaEntry.coverPath;
                }
            }
            localBook.progress = progressForBook(localKey, localBook.name, localBook.author);
            if (!trim(localBook.author) && localBook.progress &&
                trim(localBook.progress.author)) {
                localBook.author = localBook.progress.author;
            }
            return { book: localBook, chapters: localToc(localKey) };
        }
        var key = params.key || bookKey(sourceUrl, bookUrl);
        var cached = cacheGet(key, "toc", bookUrl, 6 * 3600 * 1000);
        var payload;
        if (cached) {
            payload = { book: copy(cached.book || {}), chapters: cached.chapters || [] };
        } else {
            var source = requireSource(sourceUrl);
            var info = source.bookInfo(bookUrl);
            var chapters = source.toc(bookUrl, info.tocUrl);
            payload = { book: info, chapters: chapters };
            cacheSet(key, "toc", bookUrl, payload);
        }
        payload.book.key = key;
        if (!trim(payload.book.name)) {
            var shelfBook = (state.shelf.books || {})[key];
            payload.book.name = shelfBook && shelfBook.name
                ? shelfBook.name : (payload.book.sourceName || "");
        }
        payload.book.progress = progressForBook(key, payload.book.name, payload.book.author);
        return payload;
    }

    function contentAction(params) {
        var chapterUrl = trim(params.url || params.chapterUrl || "");
        var sourceUrl = trim(params.source || params.sourceUrl || "");
        if (!chapterUrl) { throw new Error("缺少 url"); }
        if (sourceUrl === "local") {
            var localKey = trim(params.key || chapterUrl);
            var index = intValue(params.index, 0);
            var content = localContent(localKey, index);
            var meta = state.local[localKey] || {};
            var chapter = (meta.chapters || [])[index] || {};
            content.title = chapter.title || "";
            return content;
        }
        var key = params.key || bookKey(sourceUrl, chapterUrl);
        var cached = cacheGet(key, "content", chapterUrl, 24 * 3600 * 1000);
        if (cached) { return cached; }
        var result = requireSource(sourceUrl).content(chapterUrl);
        cacheSet(key, "content", chapterUrl, result);
        return result;
    }

    function cloudFetch(params) {
        var dav = davFromConfig();
        if (!dav.configured()) { throw new Error("尚未配置 WebDAV"); }
        if (params.root) { dav.dir = ""; }
        dav.timeout = 180; // 4S 上大文件走慢速网络时要留足时间
        var remote = trim(params.path || "");
        if (!remote) { throw new Error("缺少 path"); }
        var name = localName(remote);
        var ext = extOf(name);
        if (ext === ".zip") {
            return cloudImport(params);
        }
        if (ext !== ".txt" && ext !== ".epub") {
            throw new Error("云端只支持 txt / epub / zip，收到: " + (ext || "(无扩展名)"));
        }
        var temporary = root() + "/cache/cloud-" + now() + ext;
        try {
            dav.downloadTo(remote, temporary);
            var book = importLocalFile(name, temporary);
            shelfAdd(book);
            if (params.cover) {
                try { attachRemoteCover(dav, book.key, params.cover); } catch (e) { /* 封面可选 */ }
            }
            var saved = state.local[book.key];
            var coverPath = saved && saved.coverPath ? saved.coverPath : "";
            if (coverPath) {
                book.coverPath = coverPath;
                if (state.shelf.books[book.key]) {
                    state.shelf.books[book.key].coverPath = coverPath;
                    saveShelf();
                }
            }
            return { book: book };
        } finally {
            nat.remove(temporary);
        }
    }

    function attachRemoteCover(dav, key, remotePath) {
        var ext = extOf(remotePath);
        if (ext !== ".jpg" && ext !== ".jpeg" && ext !== ".png" &&
            ext !== ".gif" && ext !== ".bmp") {
            return "";
        }
        var temporary = root() + "/cache/cover-" + now() + ext;
        try {
            dav.downloadTo(remotePath, temporary);
            var size = nat.fileSize ? intValue(nat.fileSize(temporary), 0) : 0;
            if (size < 512) { return ""; }
            var target = coversDir() + "/" + key + ext;
            var copied = nat.copy ? nat.copy(temporary, target) : false;
            if (!copied) {
                var data = nat.readBase64 ? nat.readBase64(temporary) : "";
                if (!data || !nat.writeBase64 ||
                    !nat.writeBase64(target, data)) {
                    return "";
                }
            }
            var meta = state.local[key];
            if (meta) {
                meta.coverPath = target;
                state.local[key] = meta;
                saveLocal();
            }
            return target;
        } finally {
            nat.remove(temporary);
        }
    }

    function cloudImport(params) {
        var dav = davFromConfig();
        if (!dav.configured()) { throw new Error("尚未配置 WebDAV"); }
        if (params.root) { dav.dir = ""; }
        dav.timeout = 180;
        var remote = trim(params.path || "");
        if (!remote) { throw new Error("缺少 path"); }
        var temporary = root() + "/cache/import-" + now() + ".zip";
        try {
            dav.downloadTo(remote, temporary);
            var size = nat.fileSize ? intValue(nat.fileSize(temporary), 0) : 0;
            if (size <= 0) { throw new Error("下载到的备份文件是空的: " + remote); }
            return importBackupIntoState(temporary);
        } finally {
            nat.remove(temporary);
        }
    }

    // --------------------------------------------------------------- entry ----

    function handle(action, paramsJSON) {
        var params;
        try {
            params = parseJSON(paramsJSON || "{}", {});
            if (!isObject(params)) { params = {}; }
        } catch (e) {
            params = {};
        }
        try {
            var result = dispatch(action, params);
            return JSON.stringify(result === undefined ? { ok: true } : result);
        } catch (error) {
            return JSON.stringify({ error: errorText(error) });
        }
    }

    return {
        handle: handle,
        version: "1.5"
    };
})();

if (typeof module !== "undefined" && module.exports) {
    module.exports = YL;
}
