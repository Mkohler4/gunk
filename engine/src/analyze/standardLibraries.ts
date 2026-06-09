// Standard-library / runtime-builtin import allowlists.
//
// Self-containment treats any external import that is not declared in a
// dependency manifest (requirements.txt, package.json, pom.xml, ...) as a
// "missing dependency". But every language ships a standard library that is
// never declared because it is part of the runtime. Without this allowlist a
// Python module that merely imports `os`/`typing`, or a Java module importing
// `java.util.*`, would always fail self-containment. These imports are part of
// the runtime contract, so they count as covered.

import type { LanguageKind } from "../models.js";

// Python 3 standard-library top-level module names. Submodule imports
// (e.g. `os.path`, `concurrent.futures`) are matched by their root package.
const PYTHON_STDLIB = new Set<string>([
  "__future__", "_thread", "abc", "aifc", "argparse", "array", "ast", "asyncio",
  "atexit", "base64", "bdb", "binascii", "bisect", "builtins", "bz2", "cProfile",
  "calendar", "cgi", "cgitb", "chunk", "cmath", "cmd", "code", "codecs",
  "codeop", "collections", "colorsys", "compileall", "concurrent", "configparser",
  "contextlib", "contextvars", "copy", "copyreg", "crypt", "csv", "ctypes",
  "curses", "dataclasses", "datetime", "dbm", "decimal", "difflib", "dis",
  "distutils", "doctest", "email", "encodings", "ensurepip", "enum", "errno",
  "faulthandler", "fcntl", "filecmp", "fileinput", "fnmatch", "fractions",
  "ftplib", "functools", "gc", "getopt", "getpass", "gettext", "glob", "graphlib",
  "grp", "gzip", "hashlib", "heapq", "hmac", "html", "http", "idlelib", "imaplib",
  "imghdr", "imp", "importlib", "inspect", "io", "ipaddress", "itertools", "json",
  "keyword", "lib2to3", "linecache", "locale", "logging", "lzma", "mailbox",
  "mailcap", "marshal", "math", "mimetypes", "mmap", "modulefinder", "msilib",
  "msvcrt", "multiprocessing", "netrc", "nntplib", "numbers", "operator", "optparse",
  "os", "ossaudiodev", "pathlib", "pdb", "pickle", "pickletools", "pipes", "pkgutil",
  "platform", "plistlib", "poplib", "posix", "posixpath", "pprint", "profile",
  "pstats", "pty", "pwd", "py_compile", "pyclbr", "pydoc", "queue", "quopri",
  "random", "re", "readline", "reprlib", "resource", "rlcompleter", "runpy",
  "sched", "secrets", "select", "selectors", "shelve", "shlex", "shutil", "signal",
  "site", "smtplib", "sndhdr", "socket", "socketserver", "spwd", "sqlite3", "ssl",
  "stat", "statistics", "string", "stringprep", "struct", "subprocess", "sunau",
  "symtable", "sys", "sysconfig", "syslog", "tabnanny", "tarfile", "telnetlib",
  "tempfile", "termios", "textwrap", "threading", "time", "timeit", "tkinter",
  "token", "tokenize", "tomllib", "trace", "traceback", "tracemalloc", "tty",
  "turtle", "turtledemo", "types", "typing", "unicodedata", "unittest", "urllib",
  "uu", "uuid", "venv", "warnings", "wave", "weakref", "webbrowser", "winreg",
  "winsound", "wsgiref", "xdrlib", "xml", "xmlrpc", "zipapp", "zipfile",
  "zipimport", "zlib", "zoneinfo",
]);

// Node.js builtin modules (with or without the `node:` scheme).
const NODE_BUILTINS = new Set<string>([
  "assert", "async_hooks", "buffer", "child_process", "cluster", "console",
  "constants", "crypto", "dgram", "diagnostics_channel", "dns", "domain",
  "events", "fs", "http", "http2", "https", "inspector", "module", "net", "os",
  "path", "perf_hooks", "process", "punycode", "querystring", "readline", "repl",
  "stream", "string_decoder", "sys", "timers", "tls", "trace_events", "tty",
  "url", "util", "v8", "vm", "wasi", "worker_threads", "zlib",
]);

function rootPackage(specifier: string, separator: string): string {
  const head = specifier.split(separator)[0] ?? specifier;
  return head.trim();
}

/**
 * Returns true when `specifier` refers to a language standard-library / runtime
 * builtin and therefore should not be treated as a missing external dependency.
 */
export function isStandardLibraryImport(specifier: string, language: LanguageKind): boolean {
  const trimmed = specifier.trim();
  if (trimmed.length === 0) return false;

  switch (language) {
    case "python":
      return PYTHON_STDLIB.has(rootPackage(trimmed, "."));
    case "javaScript":
    case "typeScript": {
      const bare = trimmed.startsWith("node:") ? trimmed.slice("node:".length) : trimmed;
      return trimmed.startsWith("node:") || NODE_BUILTINS.has(rootPackage(bare, "/"));
    }
    case "java":
    case "kotlin": {
      const normalized = trimmed.startsWith("import ") ? trimmed.slice("import ".length).trim() : trimmed;
      return (
        normalized.startsWith("java.") ||
        normalized.startsWith("javax.") ||
        normalized.startsWith("kotlin.") ||
        normalized.startsWith("kotlinx.")
      );
    }
    case "dart":
      return trimmed.startsWith("dart:");
    case "swift":
    case "go":
    case "unknown":
      return false;
  }
}
