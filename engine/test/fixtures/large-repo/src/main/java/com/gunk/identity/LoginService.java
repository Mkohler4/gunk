package com.gunk.identity;
class LoginService { private final SessionTokenStore tokens; LoginService(SessionTokenStore tokens) { this.tokens = tokens; } SessionToken login(String email) { return tokens.issue(email); } }
