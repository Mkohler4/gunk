import 'package:dio/dio.dart';
import 'profile_model.dart';

class UserApi {
  final Dio dio = Dio(BaseOptions(baseUrl: 'https://api.example.test'));
  Future<ProfileModel> fetchProfile(String userId) async {
    final response = await dio.get('/users/$userId');
    return ProfileModel(response.data['id'] as String, response.data['displayName'] as String);
  }
}
