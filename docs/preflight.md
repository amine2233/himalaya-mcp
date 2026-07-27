# Preflight Probes (2026-07-26)

## Environment

- himalaya v2.0.0 (+gmail +jmap +imap +smtp +rustls-ring +msgraph +m2dir)
- mml v1.1.1 (+cli +compiler +interpreter)
- macOS aarch64

## Family Detection

Both singular and plural aliases coexist in v2:

```
$ himalaya messages --help  → OK (V2 plural)
$ himalaya message --help   → OK (V1 alias still works in v2)
```

The `--help` structural probe is the source of truth (not version number).

## Send Subcommand

v2 uses `message send` (or `messages send`, alias). Input: positional file path,
inline raw string, or stdin. The `--save <MAILBOX>` option appends a copy.

## mml compile: accepts headers

**The structural unknown is resolved:** `mml compile` accepts a full template
(headers + blank line + MML body) on stdin and outputs a complete RFC 5322
message. No header/body splitting is needed.

```
$ printf 'From: a@b.com\nTo: c@d.com\nSubject: test\n\n<#part type=text/html><b>hello</b><#/part>\n' | mml compile
MIME-Version: 1.0
From: <a@b.com>
To: <c@d.com>
Subject: test
Content-Type: text/html; charset="utf-8"
Content-Transfer-Encoding: 7bit

<b>hello</b>
```

Multipart also works — produces `multipart/mixed` with proper boundaries.

## Conclusion

- HIMA-6 (header/body split) is NOT needed
- Send path: `mml compile` (stdin) | `himalaya message send` (stdin)
- Single branch point: `message send` (v2) vs `template send` (v1)
