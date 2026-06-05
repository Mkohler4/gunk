import XCTest
@testable import GunkApp

final class SymbolExtractorTests: XCTestCase {
  private let extractor = TreeSitterSymbolExtractor()

  func testTypeScriptExportsAndImports() throws {
    let file = SymbolFile(
      path: "src/auth.ts",
      contents: """
      import express from "express";
      import { OAuth2Client } from "google-auth-library";
      import type { User } from "./types";

      export interface AuthSession {
        email: string;
      }

      export function googleOAuthCallback(user: User): AuthSession {
        return { email: user.email };
      }
      """
    )

    let symbols = try extractor.extract(file: file)

    XCTAssertEqual(symbols.language, .typeScript)
    XCTAssertTrue(symbols.imports.contains(ImportRef(moduleSpecifier: "express", resolvedTarget: nil, line: 1)))
    XCTAssertTrue(symbols.imports.contains(ImportRef(moduleSpecifier: "google-auth-library", resolvedTarget: nil, line: 2)))
    XCTAssertTrue(symbols.imports.contains(ImportRef(moduleSpecifier: "./types", resolvedTarget: "./types", line: 3)))
    XCTAssertTrue(symbols.symbols.contains(Symbol(name: "AuthSession", kind: .interface, line: 5)))
    XCTAssertTrue(symbols.symbols.contains(Symbol(name: "googleOAuthCallback", kind: .function, line: 9)))
    XCTAssertTrue(symbols.exports.contains(ExportRef(name: "AuthSession", kind: .interface, line: 5)))
    XCTAssertTrue(symbols.exports.contains(ExportRef(name: "googleOAuthCallback", kind: .function, line: 9)))
  }

  func testPythonImports() throws {
    let file = SymbolFile(
      path: "worker/task.py",
      contents: """
      import os, sys
      from flask import Blueprint

      class InviteSender:
          pass

      def send_invite(email):
          return email
      """
    )

    let symbols = try extractor.extract(file: file)

    XCTAssertEqual(symbols.language, .python)
    XCTAssertTrue(symbols.imports.contains(ImportRef(moduleSpecifier: "os", resolvedTarget: nil, line: 1)))
    XCTAssertTrue(symbols.imports.contains(ImportRef(moduleSpecifier: "sys", resolvedTarget: nil, line: 1)))
    XCTAssertTrue(symbols.imports.contains(ImportRef(moduleSpecifier: "flask", resolvedTarget: nil, line: 2)))
    XCTAssertTrue(symbols.symbols.contains(Symbol(name: "InviteSender", kind: .class, line: 4)))
    XCTAssertTrue(symbols.symbols.contains(Symbol(name: "send_invite", kind: .function, line: 7)))
  }

  func testSwiftImportsAndDecls() throws {
    let file = SymbolFile(
      path: "Sources/Auth.swift",
      contents: """
      import Foundation

      public struct OAuthClient {
        public func signIn() {}
      }

      enum AuthError: Error {
        case missingToken
      }
      """
    )

    let symbols = try extractor.extract(file: file)

    XCTAssertEqual(symbols.language, .swift)
    XCTAssertTrue(symbols.imports.contains(ImportRef(moduleSpecifier: "Foundation", resolvedTarget: nil, line: 1)))
    XCTAssertTrue(symbols.symbols.contains(Symbol(name: "OAuthClient", kind: .struct, line: 3)))
    XCTAssertTrue(symbols.symbols.contains(Symbol(name: "signIn", kind: .function, line: 4)))
    XCTAssertTrue(symbols.symbols.contains(Symbol(name: "AuthError", kind: .enum, line: 7)))
    XCTAssertTrue(symbols.exports.contains(ExportRef(name: "OAuthClient", kind: .struct, line: 3)))
  }

  func testGoImportsAndExports() throws {
    let file = SymbolFile(
      path: "auth/oauth.go",
      contents: """
      package auth

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
      }
      """
    )

    let symbols = try extractor.extract(file: file)

    XCTAssertEqual(symbols.language, .go)
    XCTAssertTrue(symbols.imports.contains(ImportRef(moduleSpecifier: "context", resolvedTarget: nil, line: 4)))
    XCTAssertTrue(symbols.imports.contains(ImportRef(moduleSpecifier: "github.com/acme/app/session", resolvedTarget: nil, line: 5)))
    XCTAssertTrue(symbols.symbols.contains(Symbol(name: "OAuthClient", kind: .type, line: 8)))
    XCTAssertTrue(symbols.symbols.contains(Symbol(name: "NewOAuthClient", kind: .function, line: 11)))
    XCTAssertTrue(symbols.symbols.contains(Symbol(name: "SignIn", kind: .method, line: 15)))
    XCTAssertTrue(symbols.exports.contains(ExportRef(name: "OAuthClient", kind: .type, line: 8)))
    XCTAssertTrue(symbols.exports.contains(ExportRef(name: "NewOAuthClient", kind: .function, line: 11)))
    XCTAssertTrue(symbols.exports.contains(ExportRef(name: "SignIn", kind: .method, line: 15)))
  }

  func testUnknownLanguageFallsBackToRegex() throws {
    let file = SymbolFile(
      path: "scripts/auth.custom",
      contents: """
      import auth from "./auth";
      const stripe = require("stripe");
      function login() {}
      class SessionStore {}
      """
    )

    let symbols = try extractor.extract(file: file)

    XCTAssertEqual(symbols.language, .unknown)
    XCTAssertTrue(symbols.imports.contains(ImportRef(moduleSpecifier: "./auth", resolvedTarget: "./auth", line: 1)))
    XCTAssertTrue(symbols.imports.contains(ImportRef(moduleSpecifier: "stripe", resolvedTarget: nil, line: 2)))
    XCTAssertTrue(symbols.symbols.contains(Symbol(name: "login", kind: .function, line: 3)))
    XCTAssertTrue(symbols.symbols.contains(Symbol(name: "SessionStore", kind: .class, line: 4)))
  }
}
