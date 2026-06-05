import 'profile_model.dart';
import 'user_api.dart';

class ProfileController {
  final UserApi api = UserApi();
  Future<ProfileModel> loadCurrentUser() { return api.fetchProfile('me'); }
}
