import 'features/auth/auth_controller.dart';
import 'features/profile/profile_controller.dart';

void main() {
  final auth = AuthController();
  final profile = ProfileController();
  auth.restoreSession();
  profile.loadCurrentUser();
}
