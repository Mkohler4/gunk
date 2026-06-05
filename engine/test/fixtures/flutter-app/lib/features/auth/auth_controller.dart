import 'auth_repository.dart';
import 'auth_state.dart';

class AuthController {
  final AuthRepository repository = AuthRepository();
  Future<AuthState> signInWithEmail(String email, String password) { return repository.signInWithEmail(email, password); }
  Future<AuthState?> restoreSession() { return repository.restoreSession(); }
}
