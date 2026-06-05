import { beforeAll, describe, expect, it } from "vitest";

import type { SymbolExtractor } from "../src/analyze/symbolExtractor.js";
import { createTreeSitterSymbolExtractor } from "../src/analyze/symbolExtractor.js";

let extractor: SymbolExtractor;

beforeAll(async () => {
  extractor = await createTreeSitterSymbolExtractor();
});

describe("SymbolExtractor", () => {
  it("extracts TypeScript exports and imports", () => {
    const symbols = extractor.extract({
      path: "src/auth.ts",
      contents: `import express from "express";
import { OAuth2Client } from "google-auth-library";
import type { User } from "./types";

export interface AuthSession {
  email: string;
}

export function googleOAuthCallback(user: User): AuthSession {
  return { email: user.email };
}`,
    });

    expect(symbols.language).toBe("typeScript");
    expect(symbols.imports).toContainEqual({
      moduleSpecifier: "express",
      resolvedTarget: null,
      line: 1,
    });
    expect(symbols.imports).toContainEqual({
      moduleSpecifier: "google-auth-library",
      resolvedTarget: null,
      line: 2,
    });
    expect(symbols.imports).toContainEqual({
      moduleSpecifier: "./types",
      resolvedTarget: "./types",
      line: 3,
    });
    expect(symbols.symbols).toContainEqual({ name: "AuthSession", kind: "interface", line: 5 });
    expect(symbols.symbols).toContainEqual({
      name: "googleOAuthCallback",
      kind: "function",
      line: 9,
    });
    expect(symbols.exports).toContainEqual({ name: "AuthSession", kind: "interface", line: 5 });
    expect(symbols.exports).toContainEqual({
      name: "googleOAuthCallback",
      kind: "function",
      line: 9,
    });
  });

  it("extracts Python imports and declarations", () => {
    const symbols = extractor.extract({
      path: "worker/task.py",
      contents: `import os, sys
from flask import Blueprint

class InviteSender:
    pass

def send_invite(email):
    return email`,
    });

    expect(symbols.language).toBe("python");
    expect(symbols.imports).toContainEqual({ moduleSpecifier: "os", resolvedTarget: null, line: 1 });
    expect(symbols.imports).toContainEqual({
      moduleSpecifier: "sys",
      resolvedTarget: null,
      line: 1,
    });
    expect(symbols.imports).toContainEqual({
      moduleSpecifier: "flask",
      resolvedTarget: null,
      line: 2,
    });
    expect(symbols.symbols).toContainEqual({ name: "InviteSender", kind: "class", line: 4 });
    expect(symbols.symbols).toContainEqual({ name: "send_invite", kind: "function", line: 7 });
  });

  it("extracts Swift imports and declarations", () => {
    const symbols = extractor.extract({
      path: "Sources/Auth.swift",
      contents: `import Foundation

public struct OAuthClient {
  public func signIn() {}
}

enum AuthError: Error {
  case missingToken
}`,
    });

    expect(symbols.language).toBe("swift");
    expect(symbols.imports).toContainEqual({
      moduleSpecifier: "Foundation",
      resolvedTarget: null,
      line: 1,
    });
    expect(symbols.symbols).toContainEqual({ name: "OAuthClient", kind: "struct", line: 3 });
    expect(symbols.symbols).toContainEqual({ name: "signIn", kind: "function", line: 4 });
    expect(symbols.symbols).toContainEqual({ name: "AuthError", kind: "enum", line: 7 });
    expect(symbols.exports).toContainEqual({ name: "OAuthClient", kind: "struct", line: 3 });
  });

  it("extracts Go imports and exports", () => {
    const symbols = extractor.extract({
      path: "auth/oauth.go",
      contents: `package auth

import (
  "context"
  "github.com/acme/app/session"
)

type OAuthClient struct {
}

func NewOAuthClient() *OAuthClient {
  return &OAuthClient{}
}

func (c *OAuthClient) SignIn(ctx context.Context) {
}`,
    });

    expect(symbols.language).toBe("go");
    expect(symbols.imports).toContainEqual({
      moduleSpecifier: "context",
      resolvedTarget: null,
      line: 4,
    });
    expect(symbols.imports).toContainEqual({
      moduleSpecifier: "github.com/acme/app/session",
      resolvedTarget: null,
      line: 5,
    });
    expect(symbols.symbols).toContainEqual({ name: "OAuthClient", kind: "type", line: 8 });
    expect(symbols.symbols).toContainEqual({ name: "NewOAuthClient", kind: "function", line: 11 });
    expect(symbols.symbols).toContainEqual({ name: "SignIn", kind: "method", line: 15 });
    expect(symbols.exports).toContainEqual({ name: "OAuthClient", kind: "type", line: 8 });
    expect(symbols.exports).toContainEqual({ name: "NewOAuthClient", kind: "function", line: 11 });
    expect(symbols.exports).toContainEqual({ name: "SignIn", kind: "method", line: 15 });
  });

  it("falls back to regex for unknown languages", () => {
    const symbols = extractor.extract({
      path: "scripts/auth.custom",
      contents: `import auth from "./auth";
const stripe = require("stripe");
function login() {}
class SessionStore {}`,
    });

    expect(symbols.language).toBe("unknown");
    expect(symbols.imports).toContainEqual({
      moduleSpecifier: "./auth",
      resolvedTarget: "./auth",
      line: 1,
    });
    expect(symbols.imports).toContainEqual({
      moduleSpecifier: "stripe",
      resolvedTarget: null,
      line: 2,
    });
    expect(symbols.symbols).toContainEqual({ name: "login", kind: "function", line: 3 });
    expect(symbols.symbols).toContainEqual({ name: "SessionStore", kind: "class", line: 4 });
  });
});
