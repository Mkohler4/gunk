import 'token_store.dart';
class AuthController { final TokenStore tokens = TokenStore(); Future<void> signInWithToken(String token) => tokens.save(token); }
