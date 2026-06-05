import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'auth_state.dart';

class AuthRepository {
  final FirebaseAuth firebaseAuth = FirebaseAuth.instance;
  final FlutterSecureStorage storage = const FlutterSecureStorage();
  Future<AuthState> signInWithEmail(String email, String password) async {
    final credential = await firebaseAuth.signInWithEmailAndPassword(email: email, password: password);
    await storage.write(key: 'session_user', value: credential.user?.uid ?? '');
    return AuthState(credential.user?.uid ?? '', email);
  }
  Future<AuthState?> restoreSession() async {
    final userId = await storage.read(key: 'session_user');
    return userId == null ? null : AuthState(userId, 'cached@example.test');
  }
}
