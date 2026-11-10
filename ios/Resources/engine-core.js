/*
 * yuedu-lite 核心：极简 DOM / CSS 选择器 / Legado 规则求值
 * 纯 ES5，可在 iOS 9 的 JavaScriptCore 与 Node 中运行。
 */
var YLcore = (function () {
    "use strict";

    var env = {
        ajax: function () { return ""; },
        base64Encode: function (s) { return String(s); },
        base64Decode: function (s) { return String(s); },
        md5Encode: function (s) { return String(s); }
    };

    function setEnv(next) {
        if (!next) { return; }
        for (var key in next) {
            if (Object.prototype.hasOwnProperty.call(next, key)) {
                env[key] = next[key];
            }
        }
    }

    function has(obj, key) {
        return Object.prototype.hasOwnProperty.call(obj, key);
    }

    function trim(text) {
        return String(text === null || text === undefined ? "" : text)
            .replace(/^\s+|\s+$/g, "");
    }

    function normalizeSpace(text) {
        return trim(String(text === null || text === undefined ? "" : text)
            .replace(/[\s\u00a0]+/g, " "));
    }

    // -------------------------------------------------------------- entities --
    var ENTITIES = {
        amp: "&", lt: "<", gt: ">", quot: "\"", apos: "'", nbsp: "\u00a0",
        copy: "\u00a9", reg: "\u00ae", hellip: "\u2026", mdash: "\u2014",
        ndash: "\u2013", ldquo: "\u201c", rdquo: "\u201d", lsquo: "\u2018",
        rsquo: "\u2019", middot: "\u00b7", times: "\u00d7", divide: "\u00f7"
    };

    function decodeEntities(text) {
        return String(text || "").replace(/&(#x?[0-9a-fA-F]+|[a-zA-Z]+);/g, function (all, body) {
            if (body.charAt(0) === "#") {
                var code;
                if (body.charAt(1) === "x" || body.charAt(1) === "X") {
                    code = parseInt(body.slice(2), 16);
                } else {
                    code = parseInt(body.slice(1), 10);
                }
                if (!isNaN(code) && code > 0 && code < 0x110000) {
                    try { return String.fromCharCode(code); } catch (e) { return all; }
                }
                return all;
            }
            var value = ENTITIES[body.toLowerCase()];
            return value === undefined ? all : value;
        });
    }

    function escapeHtml(text) {
        return String(text || "")
            .replace(/&/g, "&amp;")
            .replace(/</g, "&lt;")
            .replace(/>/g, "&gt;");
    }

    function escapeAttr(text) {
        return String(text || "")
            .replace(/&/g, "&amp;")
            .replace(/"/g, "&quot;")
            .replace(/</g, "&lt;");
    }

    // ------------------------------------------------------------------ node --
    var VOID_TAGS = {
        area: 1, base: 1, br: 1, col: 1, embed: 1, hr: 1, img: 1, input: 1,
        link: 1, meta: 1, param: 1, source: 1, track: 1, wbr: 1
    };

    var BLOCK_TAGS = {
        address: 1, article: 1, aside: 1, blockquote: 1, dd: 1, div: 1, dl: 1,
        dt: 1, fieldset: 1, figcaption: 1, figure: 1, footer: 1, form: 1,
        h1: 1, h2: 1, h3: 1, h4: 1, h5: 1, h6: 1, header: 1, hr: 1, li: 1,
        main: 1, nav: 1, ol: 1, p: 1, pre: 1, section: 1, table: 1, tbody: 1,
        td: 1, tfoot: 1, th: 1, thead: 1, tr: 1, ul: 1, br: 1
    };

    function Node(tag, attrs, parent) {
        this.tag = tag;
        this.attrs = attrs || {};
        this.children = [];
        this.parent = parent || null;
    }

    Node.prototype.get = function (name) {
        var value = this.attrs[name];
        return value === undefined || value === null ? "" : value;
    };

    Node.prototype.hasAttr = function (name) {
        return has(this.attrs, name);
    };

    Node.prototype.classes = function () {
        return String(this.attrs["class"] || "").split(/\s+/);
    };

    Node.prototype.descendants = function () {
        var out = [];
        (function walk(node) {
            for (var i = 0; i < node.children.length; i += 1) {
                var child = node.children[i];
                if (child instanceof Node) {
                    out.push(child);
                    walk(child);
                }
            }
        })(this);
        return out;
    };

    Node.prototype.textContent = function () {
        var out = [];
        (function walk(node) {
            for (var i = 0; i < node.children.length; i += 1) {
                var child = node.children[i];
                if (typeof child === "string") {
                    out.push(child);
                } else if (child.tag !== "script" && child.tag !== "style" && child.tag !== "noscript") {
                    walk(child);
                }
            }
        })(this);
        return out.join("");
    };

    Node.prototype.ownText = function () {
        var out = [];
        for (var i = 0; i < this.children.length; i += 1) {
            if (typeof this.children[i] === "string") {
                out.push(this.children[i]);
            }
        }
        return out.join("");
    };

    Node.prototype.innerHTML = function () {
        var out = [];
        for (var i = 0; i < this.children.length; i += 1) {
            var child = this.children[i];
            out.push(typeof child === "string" ? escapeHtml(child) : child.outerHTML());
        }
        return out.join("");
    };

    Node.prototype.outerHTML = function () {
        if (this.tag.indexOf("#") === 0) {
            return this.innerHTML();
        }
        var attrs = "";
        for (var key in this.attrs) {
            if (has(this.attrs, key)) {
                attrs += " " + key + "=\"" + escapeAttr(this.attrs[key]) + "\"";
            }
        }
        if (VOID_TAGS[this.tag]) {
            return "<" + this.tag + attrs + ">";
        }
        return "<" + this.tag + attrs + ">" + this.innerHTML() + "</" + this.tag + ">";
    };

    // ---------------------------------------------------------------- parser --
    function parseAttrs(text) {
        var attrs = {};
        var re = /([\w:-]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+)))?/g;
        var match;
        while ((match = re.exec(text))) {
            var value = "";
            if (match[2] !== undefined) {
                value = match[2];
            } else if (match[3] !== undefined) {
                value = match[3];
            } else if (match[4] !== undefined) {
                value = match[4];
            }
            attrs[match[1].toLowerCase()] = decodeEntities(value);
        }
        return attrs;
    }

    function appendText(node, text) {
        if (text) {
            node.children.push(decodeEntities(text));
        }
    }

    function parseHTML(html) {
        var root = new Node("#document");
        var stack = [root];
        html = String(html === null || html === undefined ? "" : html);
        var i = 0;
        var length = html.length;

        while (i < length) {
            var lt = html.indexOf("<", i);
            if (lt < 0) {
                appendText(stack[stack.length - 1], html.slice(i));
                break;
            }
            if (lt > i) {
                appendText(stack[stack.length - 1], html.slice(i, lt));
            }
            if (html.substr(lt, 4) === "<!--") {
                var commentEnd = html.indexOf("-->", lt + 4);
                i = commentEnd < 0 ? length : commentEnd + 3;
                continue;
            }
            if (html.charAt(lt + 1) === "!" || html.charAt(lt + 1) === "?") {
                var declEnd = html.indexOf(">", lt + 1);
                i = declEnd < 0 ? length : declEnd + 1;
                continue;
            }
            var gt = html.indexOf(">", lt + 1);
            if (gt < 0) {
                appendText(stack[stack.length - 1], html.slice(lt));
                break;
            }
            var raw = html.slice(lt + 1, gt);
            i = gt + 1;

            if (raw.charAt(0) === "/") {
                var closeName = trim(raw.slice(1)).toLowerCase();
                for (var k = stack.length - 1; k > 0; k -= 1) {
                    if (stack[k].tag === closeName) {
                        stack.length = k;
                        break;
                    }
                }
                continue;
            }

            var selfClosing = /\/\s*$/.test(raw);
            if (selfClosing) {
                raw = raw.replace(/\/\s*$/, "");
            }
            var nameMatch = /^([\w:-]+)/.exec(raw);
            if (!nameMatch) {
                continue;
            }
            var tag = nameMatch[1].toLowerCase();
            var node = new Node(tag, parseAttrs(raw.slice(nameMatch[1].length)),
                stack[stack.length - 1]);
            stack[stack.length - 1].children.push(node);
            if (!selfClosing && !VOID_TAGS[tag]) {
                stack.push(node);
            }
        }
        return root;
    }

    // -------------------------------------------------------------- selector --
    function splitGroups(selector) {
        var groups = [];
        var depth = 0;
        var start = 0;
        for (var i = 0; i < selector.length; i += 1) {
            var ch = selector.charAt(i);
            if (ch === "(") {
                depth += 1;
            } else if (ch === ")") {
                depth = Math.max(0, depth - 1);
            } else if (ch === "," && depth === 0) {
                groups.push(selector.slice(start, i));
                start = i + 1;
            }
        }
        groups.push(selector.slice(start));
        var out = [];
        for (var j = 0; j < groups.length; j += 1) {
            var group = trim(groups[j]);
            if (group) {
                out.push(group);
            }
        }
        return out;
    }

    function tokenizeSelector(selector) {
        var tokens = [];
        var buf = [];
        var comb = " ";
        for (var i = 0; i < selector.length; i += 1) {
            var ch = selector.charAt(i);
            if (ch === ">" || ch === "+") {
                if (buf.length) {
                    tokens.push([comb, trim(buf.join(""))]);
                    buf = [];
                }
                comb = ">";
                continue;
            }
            if (/\s/.test(ch)) {
                if (buf.length) {
                    tokens.push([comb, trim(buf.join(""))]);
                    buf = [];
                    comb = " ";
                }
                continue;
            }
            buf.push(ch);
        }
        if (buf.length) {
            tokens.push([comb, trim(buf.join(""))]);
        }
        var out = [];
        for (var j = 0; j < tokens.length; j += 1) {
            if (tokens[j][1]) {
                out.push(tokens[j]);
            }
        }
        return out;
    }

    function parseCompound(text) {
        var tag = null;
        var ids = [];
        var classes = [];
        var attrs = [];
        var pos = 0;
        if (text && ".#[".indexOf(text.charAt(0)) < 0) {
            var tagMatch = /^[\w*-]+/.exec(text);
            if (tagMatch) {
                tag = tagMatch[0].toLowerCase();
                pos = tagMatch[0].length;
            }
        }
        while (pos < text.length) {
            var ch = text.charAt(pos);
            if (ch === ".") {
                var classMatch = /^\.([\w-]+)/.exec(text.slice(pos));
                if (!classMatch) { pos += 1; continue; }
                classes.push(classMatch[1]);
                pos += classMatch[0].length;
            } else if (ch === "#") {
                var idMatch = /^#([\w-]+)/.exec(text.slice(pos));
                if (!idMatch) { pos += 1; continue; }
                ids.push(idMatch[1]);
                pos += idMatch[0].length;
            } else if (ch === "[") {
                var end = text.indexOf("]", pos);
                if (end < 0) { break; }
                var body = trim(text.slice(pos + 1, end));
                var attrMatch = /^([\w:-]+)\s*(?:([~^$*|]?=)\s*([\s\S]*))?$/.exec(body);
                if (attrMatch) {
                    var attrValue = trim(attrMatch[3] || "").replace(/^["']|["']$/g, "");
                    attrs.push([attrMatch[1].toLowerCase(), attrMatch[2] || null, attrValue]);
                }
                pos = end + 1;
            } else if (ch === ":") {
                var pseudo = /^:[\w-]+(?:\([^)]*\))?/.exec(text.slice(pos));
                pos += pseudo ? pseudo[0].length : 1;
            } else {
                pos += 1;
            }
        }
        return [tag, ids, classes, attrs];
    }

    function matchCompound(node, compound) {
        if (!(node instanceof Node) || node.tag.charAt(0) === "#") {
            return false;
        }
        var tag = compound[0], ids = compound[1], classes = compound[2], attrs = compound[3];
        if (tag && tag !== "*" && node.tag !== tag) {
            return false;
        }
        var nodeClasses = node.classes();
        for (var i = 0; i < classes.length; i += 1) {
            if (nodeClasses.indexOf(classes[i]) < 0) {
                return false;
            }
        }
        for (var j = 0; j < ids.length; j += 1) {
            if (node.get("id") !== ids[j]) {
                return false;
            }
        }
        for (var k = 0; k < attrs.length; k += 1) {
            var name = attrs[k][0], op = attrs[k][1], value = attrs[k][2];
            if (!node.hasAttr(name)) {
                return false;
            }
            var actual = node.get(name);
            if (op === null) { continue; }
            var ok;
            if (op === "=") { ok = actual === value; }
            else if (op === "~=") { ok = (" " + actual + " ").indexOf(" " + value + " ") >= 0; }
            else if (op === "^=") { ok = actual.indexOf(value) === 0; }
            else if (op === "$=") { ok = actual.slice(-value.length) === value; }
            else if (op === "*=") { ok = actual.indexOf(value) >= 0; }
            else if (op === "|=") { ok = actual === value || actual.indexOf(value + "-") === 0; }
            else { ok = true; }
            if (!ok) { return false; }
        }
        return true;
    }

    function select(root, selector) {
        var result = [];
        var groups = splitGroups(selector);
        for (var g = 0; g < groups.length; g += 1) {
            var current = [root];
            var tokens = tokenizeSelector(groups[g]);
            for (var t = 0; t < tokens.length; t += 1) {
                var comb = tokens[t][0];
                var compound = parseCompound(tokens[t][1]);
                var next = [];
                for (var c = 0; c < current.length; c += 1) {
                    var base = current[c];
                    var pool;
                    if (comb === ">") {
                        pool = [];
                        for (var p = 0; p < base.children.length; p += 1) {
                            if (base.children[p] instanceof Node) {
                                pool.push(base.children[p]);
                            }
                        }
                    } else if (comb === "+") {
                        pool = [];
                    } else {
                        pool = base.descendants();
                    }
                    for (var q = 0; q < pool.length; q += 1) {
                        if (matchCompound(pool[q], compound)) {
                            next.push(pool[q]);
                        }
                    }
                }
                var seen = [];
                current = [];
                for (var n = 0; n < next.length; n += 1) {
                    if (seen.indexOf(next[n]) < 0) {
                        seen.push(next[n]);
                        current.push(next[n]);
                    }
                }
            }
            result = result.concat(current);
        }
        var uniq = [], out = [];
        for (var r = 0; r < result.length; r += 1) {
            if (uniq.indexOf(result[r]) < 0) {
                uniq.push(result[r]);
                out.push(result[r]);
            }
        }
        return out;
    }

    // ---------------------------------------------------------------- text ----
    function htmlToText(html) {
        var root = parseHTML(html);
        var lines = [];
        var buf = [];

        function flush() {
            var text = normalizeSpace(buf.join(""));
            buf = [];
            if (text) {
                lines.push(text);
            }
        }

        function walk(node) {
            for (var i = 0; i < node.children.length; i += 1) {
                var child = node.children[i];
                if (typeof child === "string") {
                    buf.push(child);
                    continue;
                }
                if (child.tag === "script" || child.tag === "style" ||
                    child.tag === "noscript" || child.tag === "head" ||
                    child.tag === "title") {
                    continue;
                }
                var block = BLOCK_TAGS[child.tag] === 1;
                if (block) { flush(); }
                walk(child);
                if (block) { flush(); }
            }
        }

        walk(root);
        flush();
        return lines.join("\n");
    }

    // ---------------------------------------------------------- rule helpers --
    var EXTRACT_OPS = { text: 1, textNodes: 1, ownText: 1, html: 1, all: 1, content: 1 };

    function splitTop(text, sep) {
        var parts = [];
        var depth = 0;
        var start = 0;
        var i = 0;
        while (i < text.length) {
            if (text.substr(i, 2) === "{{") {
                depth += 1;
                i += 2;
                continue;
            }
            if (text.substr(i, 2) === "}}" && depth > 0) {
                depth -= 1;
                i += 2;
                continue;
            }
            if (depth === 0 && text.substr(i, sep.length) === sep) {
                parts.push(text.slice(start, i));
                i += sep.length;
                start = i;
                continue;
            }
            i += 1;
        }
        parts.push(text.slice(start));
        return parts;
    }

    function splitRegex(rule) {
        var idx = -1;
        var depth = 0;
        var i = 0;
        while (i < rule.length) {
            if (rule.substr(i, 2) === "{{") {
                depth += 1;
                i += 2;
                continue;
            }
            if (rule.substr(i, 2) === "}}" && depth > 0) {
                depth -= 1;
                i += 2;
                continue;
            }
            if (depth === 0 && rule.substr(i, 2) === "##") {
                idx = i;
                break;
            }
            i += 1;
        }
        if (idx < 0) {
            return [rule, null, null];
        }
        var expr = rule.slice(0, idx);
        var rest = rule.slice(idx + 2);
        var split = rest.indexOf("##");
        if (split >= 0) {
            return [expr, rest.slice(0, split), rest.slice(split + 2)];
        }
        return [expr, rest, null];
    }

    function asText(value) {
        if (value === null || value === undefined) { return ""; }
        if (value instanceof Node) { return normalizeSpace(value.textContent()); }
        if (typeof value === "string") { return value; }
        if (typeof value === "object") {
            try { return JSON.stringify(value); } catch (e) { return String(value); }
        }
        return String(value);
    }

    function asNode(value) {
        if (value instanceof Node) { return value; }
        if (typeof value === "string") { return parseHTML(value); }
        return null;
    }

    function joinValues(items) {
        var out = [];
        for (var i = 0; i < items.length; i += 1) {
            var text = asText(items[i]);
            if (text) { out.push(text); }
        }
        return out.join("\n");
    }

    function jsonPath(value, path) {
        path = trim(path || "");
        if (!path || path === "$") { return [value]; }
        if (path.slice(0, 2) === "$.") { path = path.slice(2); }
        var tokens = [];
        var re = /[^.\[\]]+|\[[^\]]*\]/g;
        var match;
        while ((match = re.exec(path))) { tokens.push(match[0]); }
        var current = [value];
        for (var i = 0; i < tokens.length; i += 1) {
            var token = tokens[i];
            var bracket = token.charAt(0) === "[";
            var key = bracket ? trim(token.slice(1, -1)).replace(/^["']|["']$/g, "") : token;
            var index = /^-?\d+$/.test(key) ? parseInt(key, 10) : null;
            var next = [];
            for (var j = 0; j < current.length; j += 1) {
                var item = current[j];
                if (item === null || item === undefined) { continue; }
                if (key === "*") {
                    if (Array.isArray(item)) {
                        for (var w = 0; w < item.length; w += 1) { next.push(item[w]); }
                    } else if (typeof item === "object") {
                        for (var wk in item) {
                            if (Object.prototype.hasOwnProperty.call(item, wk)) {
                                next.push(item[wk]);
                            }
                        }
                    }
                    continue;
                }
                if (Array.isArray(item)) {
                    if (index !== null) {
                        if (index >= -item.length && index < item.length) { next.push(item[index]); }
                    } else if (bracket) {
                        for (var m = 0; m < item.length; m += 1) {
                            if (item[m] && typeof item[m] === "object" && key in item[m]) {
                                next.push(item[m][key]);
                            }
                        }
                    } else {
                        for (var m2 = 0; m2 < item.length; m2 += 1) {
                            if (item[m2] && typeof item[m2] === "object" && key in item[m2]) {
                                next.push(item[m2][key]);
                            }
                        }
                    }
                } else if (typeof item === "object") {
                    if (key in item) { next.push(item[key]); }
                }
            }
            current = next;
            if (!current.length) { break; }
        }
        return current;
    }

    function jsonList(items) {
        if (items.length === 1 && typeof items[0] === "object" &&
            items[0] && typeof items[0].length === "number" &&
            typeof items[0] !== "string") {
            return items[0];
        }
        return items;
    }

    function legacySelector(token) {
        token = trim(token || "");
        if (token.slice(0, 6) === "class.") { return "." + token.slice(6); }
        if (token.slice(0, 3) === "id.") { return "#" + token.slice(3); }
        if (token.slice(0, 4) === "tag.") { return token.slice(4); }
        return token;
    }

    function splitIndex(token) {
        var match = /^(.*?)(?:\[(-?\d+)\]|\.(-?\d+))$/.exec(trim(token || ""));
        if (match && (match[2] !== undefined || match[3] !== undefined)) {
            var raw = match[2] !== undefined ? match[2] : match[3];
            return [match[1], parseInt(raw, 10)];
        }
        return [trim(token || ""), null];
    }

    function applySelectorToken(token, nodes) {
        token = trim(token || "");
        if (!token) { return nodes; }
        if (token === "children") {
            var kids = [];
            for (var c = 0; c < nodes.length; c += 1) {
                for (var i = 0; i < nodes[c].children.length; i += 1) {
                    if (nodes[c].children[i] instanceof Node) {
                        kids.push(nodes[c].children[i]);
                    }
                }
            }
            return kids;
        }
        if (/^-?\d+$/.test(token)) {
            var index = parseInt(token, 10);
            return index >= -nodes.length && index < nodes.length ? [nodes[index]] : [];
        }
        if (token.charAt(0) === "!" && /^\d+$/.test(token.slice(1))) {
            var rev = nodes.slice().reverse();
            var ri = parseInt(token.slice(1), 10);
            return ri < rev.length ? [rev[ri]] : [];
        }

        var parts = splitIndex(token);
        var selector = legacySelector(parts[0]);
        var out = [];
        for (var n = 0; n < nodes.length; n += 1) {
            if (selector) {
                out = out.concat(select(nodes[n], selector));
            } else {
                out.push(nodes[n]);
            }
        }
        if (parts[1] !== null) {
            var idx = parts[1];
            return idx >= -out.length && idx < out.length ? [out[idx]] : [];
        }
        return out;
    }

    function selectLegacy(rule, value) {
        var node = asNode(value);
        if (!node) { return []; }
        var nodes = [node];
        var tokens = rule.split("@");
        for (var i = 0; i < tokens.length; i += 1) {
            nodes = applySelectorToken(tokens[i], nodes);
        }
        return nodes;
    }

    function coerceList(value) {
        if (typeof value === "object" && value && typeof value.length === "number" &&
            typeof value !== "string") {
            return value;
        }
        var text = asText(value);
        if (!text) { return []; }
        var stripped = trim(text);
        if (stripped.charAt(0) === "{" || stripped.charAt(0) === "[") {
            try {
                var parsed = JSON.parse(stripped);
                if (typeof parsed === "object" && parsed && typeof parsed.length === "number") {
                    return parsed;
                }
                return [parsed];
            } catch (e) { /* ignore */ }
        }
        if (stripped.indexOf("<") >= 0) {
            return select(parseHTML(stripped), "*");
        }
        return [];
    }

    function selectExpr(rule, value, ctx) {
        rule = trim(rule || "");
        if (!rule) { return []; }
        if (rule.slice(0, 5) === "@css:") {
            var root = asNode(value);
            return root ? select(root, trim(rule.slice(5))) : [];
        }
        if (rule.slice(0, 6) === "@json:") {
            return jsonList(jsonPath(value, trim(rule.slice(6))));
        }
        if (rule.charAt(0) === "$") {
            return jsonList(jsonPath(value, rule));
        }
        if (rule.charAt(0) === "@") {
            rule = rule.slice(1);
        }
        if (rule.slice(0, 2) === "{{" && rule.slice(-2) === "}}" &&
            rule.indexOf("{{") === rule.lastIndexOf("{{")) {
            return coerceList(jsEval(rule.slice(2, -2), value, ctx));
        }
        return selectLegacy(rule, value);
    }

    function selectNodes(rule, value, ctx) {
        rule = trim(rule || "");
        if (!rule) { return []; }
        var alternatives = splitTop(rule, "||");
        for (var i = 0; i < alternatives.length; i += 1) {
            var nodes = selectExpr(trim(alternatives[i]), value, ctx);
            if (nodes.length) { return nodes; }
        }
        return [];
    }

    function extractOp(op, value) {
        if (value instanceof Node) {
            if (op === "text" || op === "textNodes" || op === "content") {
                return normalizeSpace(value.textContent());
            }
            if (op === "ownText") {
                return normalizeSpace(value.ownText());
            }
            if (op === "html" || op === "all") {
                return value.innerHTML();
            }
            if (value.hasAttr(op)) {
                return value.get(op);
            }
            return "";
        }
        if (value && typeof value === "object" && !(typeof value.length === "number") &&
            Object.prototype.hasOwnProperty.call(value, op)) {
            return asText(value[op]);
        }
        return asText(value);
    }

    var TAG_NAMES = {
        a: 1, abbr: 1, article: 1, aside: 1, b: 1, blockquote: 1, body: 1,
        br: 1, button: 1, dd: 1, div: 1, dl: 1, dt: 1, em: 1, footer: 1,
        form: 1, h1: 1, h2: 1, h3: 1, h4: 1, h5: 1, h6: 1, header: 1, hr: 1,
        html: 1, i: 1, img: 1, input: 1, label: 1, li: 1, main: 1, nav: 1,
        ol: 1, option: 1, p: 1, pre: 1, section: 1, select: 1, small: 1,
        span: 1, strong: 1, table: 1, tbody: 1, td: 1, textarea: 1, tfoot: 1,
        th: 1, thead: 1, tr: 1, u: 1, ul: 1
    };

    function looksLikeAttr(token, value) {
        if (!/^[\w:-]+$/.test(token || "")) { return false; }
        return value instanceof Node && value.hasAttr(token);
    }

    function evalRule(rule, value, ctx) {
        rule = trim(rule || "");
        if (!rule) { return ""; }
        var alternatives = splitTop(rule, "||");
        if (alternatives.length > 1) {
            for (var i = 0; i < alternatives.length; i += 1) {
                var got = evalRule(alternatives[i], value, ctx);
                if (got) { return got; }
            }
            return "";
        }
        var parts = splitRegex(rule);
        var text = evalExpr(parts[0], value, ctx);
        if (parts[1] !== null) {
            text = regexApply(text, parts[1], parts[2]);
        }
        return text;
    }

    function evalExpr(rule, value, ctx) {
        rule = trim(rule || "");
        if (!rule) { return ""; }
        if (rule.indexOf("{{") >= 0) {
            return evalTemplate(rule, value, ctx);
        }
        if (EXTRACT_OPS[rule]) {
            return extractOp(rule, value);
        }
        if (rule.slice(0, 6) === "@json:") {
            return joinValues(jsonPath(value, trim(rule.slice(6))));
        }
        if (rule.charAt(0) === "$") {
            return joinValues(jsonPath(value, rule));
        }
        if (rule.slice(0, 5) === "@css:") {
            var root = asNode(value);
            if (!root) { return ""; }
            var nodes = select(root, trim(rule.slice(5)));
            var texts = [];
            for (var i = 0; i < nodes.length; i += 1) {
                texts.push(normalizeSpace(nodes[i].textContent()));
            }
            return texts.join("\n");
        }
        if (/^@xpath:/i.test(rule)) {
            return "";
        }
        if (rule.charAt(0) === "@") {
            rule = rule.slice(1);
            if (!rule) { return ""; }
        }
        if (looksLikeAttr(rule, value)) {
            return value.get(rule);
        }
        return evalLegacy(rule, value);
    }

    function evalLegacy(rule, value) {
        var tokens = rule.split("@");
        var op = null;
        if (tokens.length > 1) {
            var last = trim(tokens[tokens.length - 1]);
            if (EXTRACT_OPS[last]) {
                op = tokens.pop();
            } else if (/^[\w:-]+$/.test(last) && !TAG_NAMES[last.toLowerCase()]) {
                op = tokens.pop();
            }
        }
        var node = asNode(value);
        if (!node) { return ""; }
        var nodes = [node];
        for (var i = 0; i < tokens.length; i += 1) {
            nodes = applySelectorToken(tokens[i], nodes);
        }
        if (!nodes.length) { return ""; }
        var out = [];
        for (var j = 0; j < nodes.length; j += 1) {
            out.push(op ? extractOp(op, nodes[j]) : normalizeSpace(nodes[j].textContent()));
        }
        return out.join("\n");
    }

    function dotAllPattern(pattern) {
        var out = "";
        var inClass = false;
        for (var i = 0; i < pattern.length; i += 1) {
            var ch = pattern.charAt(i);
            if (ch === "\\") {
                out += ch;
                if (i + 1 < pattern.length) {
                    out += pattern.charAt(i + 1);
                    i += 1;
                }
                continue;
            }
            if (ch === "[") { inClass = true; out += ch; continue; }
            if (ch === "]") { inClass = false; out += ch; continue; }
            if (ch === "." && !inClass) { out += "[\\s\\S]"; continue; }
            out += ch;
        }
        return out;
    }

    /* Java 常用内联标志：(?s) 让 . 匹配换行，(?i) 忽略大小写，(?m) 多行 */
    function compilePattern(pattern) {
        var flags = "g";
        var dotAll = false;
        pattern = String(pattern || "").replace(/\(\?([ism]+)\)/g, function (all, letters) {
            if (letters.indexOf("i") >= 0 && flags.indexOf("i") < 0) { flags += "i"; }
            if (letters.indexOf("m") >= 0 && flags.indexOf("m") < 0) { flags += "m"; }
            if (letters.indexOf("s") >= 0) { dotAll = true; }
            return "";
        });
        if (dotAll) { pattern = dotAllPattern(pattern); }
        return { pattern: pattern, flags: flags };
    }

    function regexApply(text, pattern, replacement) {
        try {
            var compiled = compilePattern(pattern);
            var re = new RegExp(compiled.pattern, compiled.flags);
            if (replacement === null) {
                return String(text).replace(re, "");
            }
            return String(text).replace(re, replacement);
        } catch (e) {
            return text;
        }
    }

    function evalTemplate(template, value, ctx) {
        ctx = ctx || {};
        var out = [];
        var i = 0;
        while (true) {
            var start = template.indexOf("{{", i);
            if (start < 0) {
                out.push(template.slice(i));
                break;
            }
            out.push(template.slice(i, start));
            var end = template.indexOf("}}", start + 2);
            if (end < 0) {
                out.push(template.slice(start));
                break;
            }
            var code = trim(template.slice(start + 2, end));
            if (code === "key") {
                out.push(String(ctx.key === undefined ? "" : ctx.key));
            } else if (code === "page") {
                out.push(String(ctx.page === undefined ? 1 : ctx.page));
            } else if (code === "baseUrl" || code === "base_url") {
                out.push(String(ctx.baseUrl || ""));
            } else if (code === "sourceUrl") {
                out.push(String(ctx.sourceUrl || ""));
            } else {
                out.push(asText(jsEval(code, value, ctx)));
            }
            i = end + 2;
        }
        return out.join("");
    }

    function javaObject(ctx) {
        return {
            ajax: function (url) {
                try { return env.ajax(String(url)); } catch (e) { return ""; }
            },
            get: function (url) { return this.ajax(url); },
            post: function (url, body, headers) {
                try {
                    if (!env.post) { return ""; }
                    return env.post(String(url),
                        body === null || body === undefined ? "" : String(body),
                        headers || {});
                } catch (e) {
                    return "";
                }
            },
            base64Encode: function (s) { return env.base64Encode(String(s)); },
            base64Decode: function (s) { return env.base64Decode(String(s)); },
            md5Encode: function (s) { return env.md5Encode(String(s)); },
            md5Encode16: function (s) { return env.md5Encode(String(s)).slice(8, 24); },
            hexEncode: function (s) {
                var text = String(s), out = "";
                for (var i = 0; i < text.length; i += 1) {
                    var hex = text.charCodeAt(i).toString(16);
                    out += hex.length < 2 ? "0" + hex : hex;
                }
                return out;
            },
            log: function () {},
            toast: function () {}
        };
    }

    function jsEval(code, value, ctx) {
        code = trim(code || "");
        if (!code) { return ""; }
        ctx = ctx || {};
        var result;
        if (value instanceof Node) {
            result = normalizeSpace(value.textContent());
        } else if (value === null || value === undefined) {
            result = "";
        } else {
            result = value;
        }
        var names = ["result", "baseUrl", "key", "page", "sourceUrl", "java",
            "JSON", "Math", "Date", "String", "Number", "Boolean", "Array",
            "Object", "RegExp", "parseInt", "parseFloat", "encodeURIComponent",
            "decodeURIComponent", "console"];
        var args = [result, ctx.baseUrl || "", ctx.key || "",
            ctx.page === undefined ? 1 : ctx.page, ctx.sourceUrl || "",
            javaObject(ctx), JSON, Math, Date, String, Number, Boolean, Array,
            Object, RegExp, parseInt, parseFloat, encodeURIComponent,
            decodeURIComponent, { log: function () {} }];
        try {
            var fn = Function.apply(null, names.concat(["return (" + code + ");"]));
            var out = fn.apply(null, args);
            return out === null || out === undefined ? "" : String(out);
        } catch (e) {
            try {
                var fn2 = Function.apply(null, names.concat([code]));
                var out2 = fn2.apply(null, args);
                return out2 === null || out2 === undefined ? "" : String(out2);
            } catch (e2) {
                return "";
            }
        }
    }

    // ------------------------------------------------------------------ url ----
    function normalizePath(path) {
        var parts = path.split("/");
        var out = [];
        for (var i = 0; i < parts.length; i += 1) {
            var seg = parts[i];
            if (seg === "" || seg === ".") {
                if (i === 0) { out.push(""); }
                continue;
            }
            if (seg === "..") {
                if (out.length > 1) { out.pop(); }
                continue;
            }
            out.push(seg);
        }
        return out.join("/") || "/";
    }

    function absUrl(url, base) {
        url = trim(url);
        if (!url) { return ""; }
        if (url.slice(0, 2) === "//") { return "https:" + url; }
        if (/^[a-z][a-z0-9+.-]*:/i.test(url)) { return url; }
        if (!base) { return url; }
        var match = /^([a-z][a-z0-9+.-]*:)\/\/([^\/?#]*)([^?#]*)/i.exec(base);
        if (!match) { return url; }
        var scheme = match[1], host = match[2], path = match[3] || "/";
        var directory = path.replace(/[^\/]*$/, "");
        if (url.charAt(0) === "/") {
            path = url;
        } else if (url.charAt(0) === "?" || url.charAt(0) === "#") {
            path = path + url;
        } else {
            path = directory + url;
        }
        if (path.charAt(0) !== "/") { path = "/" + path; }
        return scheme + "//" + host + normalizePath(path);
    }

    return {
        Node: Node,
        parseHTML: parseHTML,
        select: select,
        htmlToText: htmlToText,
        normalizeSpace: normalizeSpace,
        trim: trim,
        decodeEntities: decodeEntities,
        evalRule: evalRule,
        evalTemplate: evalTemplate,
        selectNodes: selectNodes,
        absUrl: absUrl,
        splitTop: splitTop,
        jsonPath: jsonPath,
        jsEval: jsEval,
        replaceText: regexApply,
        setEnv: setEnv
    };
})();

if (typeof module !== "undefined" && module.exports) {
    module.exports = YLcore;
}
