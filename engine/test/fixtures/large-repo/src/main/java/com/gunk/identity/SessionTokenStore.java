package com.gunk.identity;
class SessionTokenStore { SessionToken issue(String email) { return new SessionToken(email, "session-token"); } }
record SessionToken(String email, String token) {}
