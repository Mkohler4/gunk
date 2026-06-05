package com.gunk.identity;
class LoginController { private final LoginService service = new LoginService(new SessionTokenStore()); SessionToken login(String email) { return service.login(email); } }
