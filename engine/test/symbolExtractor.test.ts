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

  it("extracts Dart classes, methods, and functions", () => {
    const symbols = extractor.extract({
      path: "lib/auth_controller.dart",
      contents: `import 'auth_repository.dart';

class AuthController {
  final AuthRepository repository = AuthRepository();
  Future<AuthState> signInWithEmail(String email, String password) async {
    return repository.signInWithEmail(email, password);
  }
}

String compactDate(DateTime value) {
  return value.toIso8601String();
}`,
    });

    expect(symbols.language).toBe("dart");
    expect(symbols.viaFallback).toBe(false);
    expect(symbols.imports).toContainEqual({
      moduleSpecifier: "auth_repository.dart",
      resolvedTarget: null,
      line: 1,
    });
    expect(symbols.symbols).toContainEqual({ name: "AuthController", kind: "class", line: 3 });
    expect(symbols.symbols).toContainEqual({
      name: "signInWithEmail",
      kind: "method",
      line: 5,
    });
    expect(symbols.symbols).toContainEqual({ name: "compactDate", kind: "function", line: 10 });
  });

  it("extracts Kotlin classes/functions", () => {
    const symbols = extractor.extract({
      path: "app/src/main/java/com/gunk/fixture/features/payments/PaymentsRepository.kt",
      contents: `package com.gunk.fixture.features.payments

import com.android.billingclient.api.BillingClient

class PaymentsRepository {
  fun createCheckout(planId: String): CheckoutSession {
    return CheckoutSession(planId, "billing-client-token")
  }
}

object PaymentsModule {
  fun provide() = PaymentsRepository()
}

private class InternalOnly
fun topLevelFactory() = PaymentsRepository()`,
    });

    expect(symbols.language).toBe("kotlin");
    expect(symbols.viaFallback).toBe(false);
    expect(symbols.imports).toContainEqual({
      moduleSpecifier: "com.android.billingclient.api.BillingClient",
      resolvedTarget: null,
      line: 3,
    });
    expect(symbols.symbols).toContainEqual({ name: "PaymentsRepository", kind: "class", line: 5 });
    expect(symbols.symbols).toContainEqual({ name: "createCheckout", kind: "function", line: 6 });
    expect(symbols.symbols).toContainEqual({ name: "PaymentsModule", kind: "class", line: 11 });
    expect(symbols.symbols).toContainEqual({ name: "provide", kind: "function", line: 12 });
    expect(symbols.symbols).toContainEqual({ name: "InternalOnly", kind: "class", line: 15 });
    expect(symbols.symbols).toContainEqual({ name: "topLevelFactory", kind: "function", line: 16 });
    expect(symbols.exports).toContainEqual({ name: "PaymentsRepository", kind: "class", line: 5 });
    expect(symbols.exports).toContainEqual({ name: "createCheckout", kind: "function", line: 6 });
    expect(symbols.exports).toContainEqual({ name: "topLevelFactory", kind: "function", line: 16 });
    expect(symbols.exports).not.toContainEqual({ name: "InternalOnly", kind: "class", line: 15 });
  });

  it("extracts Java classes/methods", () => {
    const symbols = extractor.extract({
      path: "src/main/java/com/gunk/orders/OrderService.java",
      contents: `package com.gunk.orders;
import com.gunk.shared.Page;

class OrderService {
  private final OrderRepository repository;
  OrderService(OrderRepository repository) { this.repository = repository; }
  OrderReceipt createOrder(OrderRequest request) { return repository.save(request); }
  private void audit() {}
}

public record OrderRequest(String sku, int quantity) {}`,
    });

    expect(symbols.language).toBe("java");
    expect(symbols.viaFallback).toBe(false);
    expect(symbols.imports).toContainEqual({
      moduleSpecifier: "com.gunk.shared.Page",
      resolvedTarget: null,
      line: 2,
    });
    expect(symbols.symbols).toContainEqual({ name: "OrderService", kind: "class", line: 4 });
    expect(symbols.symbols).toContainEqual({ name: "OrderService", kind: "method", line: 6 });
    expect(symbols.symbols).toContainEqual({ name: "createOrder", kind: "method", line: 7 });
    expect(symbols.symbols).toContainEqual({ name: "audit", kind: "method", line: 8 });
    expect(symbols.symbols).toContainEqual({ name: "OrderRequest", kind: "type", line: 11 });
    expect(symbols.exports).toContainEqual({ name: "OrderService", kind: "class", line: 4 });
    expect(symbols.exports).toContainEqual({ name: "createOrder", kind: "method", line: 7 });
    expect(symbols.exports).toContainEqual({ name: "OrderRequest", kind: "type", line: 11 });
    expect(symbols.exports).not.toContainEqual({ name: "audit", kind: "method", line: 8 });
  });

  it("captures Dart import specifiers", () => {
    const symbols = extractor.extract({
      path: "lib/main.dart",
      contents: `import 'dart:async';
import 'package:gunk_flutter_fixture/types.dart';
import 'package:firebase_auth/firebase_auth.dart';
import './features/auth/auth_controller.dart';
import 'features/profile/profile_controller.dart';

void main() {}`,
    });

    expect(symbols.imports).toContainEqual({
      moduleSpecifier: "dart:async",
      resolvedTarget: null,
      line: 1,
    });
    expect(symbols.imports).toContainEqual({
      moduleSpecifier: "package:gunk_flutter_fixture/types.dart",
      resolvedTarget: null,
      line: 2,
    });
    expect(symbols.imports).toContainEqual({
      moduleSpecifier: "package:firebase_auth/firebase_auth.dart",
      resolvedTarget: null,
      line: 3,
    });
    expect(symbols.imports).toContainEqual({
      moduleSpecifier: "./features/auth/auth_controller.dart",
      resolvedTarget: "./features/auth/auth_controller.dart",
      line: 4,
    });
    expect(symbols.imports).toContainEqual({
      moduleSpecifier: "features/profile/profile_controller.dart",
      resolvedTarget: null,
      line: 5,
    });
  });

  it("treats public top-level decls as exports", () => {
    const symbols = extractor.extract({
      path: "lib/types.dart",
      contents: `class ApiEnvelope {
  final Map<String, Object?> data;
  const ApiEnvelope(this.data);
}

enum AuthState { signedOut, signedIn }
typedef AuthBuilder = ApiEnvelope Function();
const defaultTimeoutMs = 5000;
final currentVersion = '1.0.0';
String compactDate(DateTime value) => value.toIso8601String();`,
    });

    expect(symbols.exports).toContainEqual({ name: "ApiEnvelope", kind: "class", line: 1 });
    expect(symbols.exports).toContainEqual({ name: "AuthState", kind: "enum", line: 6 });
    expect(symbols.exports).toContainEqual({ name: "AuthBuilder", kind: "type", line: 7 });
    expect(symbols.exports).toContainEqual({
      name: "defaultTimeoutMs",
      kind: "variable",
      line: 8,
    });
    expect(symbols.exports).toContainEqual({
      name: "currentVersion",
      kind: "variable",
      line: 9,
    });
    expect(symbols.exports).toContainEqual({ name: "compactDate", kind: "function", line: 10 });
  });

  it("underscore-prefixed members are not exported", () => {
    const symbols = extractor.extract({
      path: "lib/private_bits.dart",
      contents: `class PublicController {
  void restoreSession() {}
  void _dropSession() {}
}

class _PrivateController {}
void publicTopLevel() {}
void _hiddenTopLevel() {}
const publicValue = 1;
const _privateValue = 2;`,
    });

    expect(symbols.symbols).toContainEqual({ name: "_dropSession", kind: "method", line: 3 });
    expect(symbols.symbols).toContainEqual({
      name: "_PrivateController",
      kind: "class",
      line: 6,
    });
    expect(symbols.symbols).toContainEqual({ name: "_hiddenTopLevel", kind: "function", line: 8 });
    expect(symbols.symbols).toContainEqual({ name: "_privateValue", kind: "variable", line: 10 });
    expect(symbols.exports).toContainEqual({ name: "PublicController", kind: "class", line: 1 });
    expect(symbols.exports).toContainEqual({
      name: "publicTopLevel",
      kind: "function",
      line: 7,
    });
    expect(symbols.exports).toContainEqual({ name: "publicValue", kind: "variable", line: 9 });
    expect(symbols.exports).not.toContainEqual({ name: "_dropSession", kind: "method", line: 3 });
    expect(symbols.exports).not.toContainEqual({
      name: "_PrivateController",
      kind: "class",
      line: 6,
    });
    expect(symbols.exports).not.toContainEqual({
      name: "_hiddenTopLevel",
      kind: "function",
      line: 8,
    });
    expect(symbols.exports).not.toContainEqual({
      name: "_privateValue",
      kind: "variable",
      line: 10,
    });
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
