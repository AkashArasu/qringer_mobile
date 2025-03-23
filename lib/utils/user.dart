import 'package:stream_video/stream_video.dart';
import 'package:stream_video_flutter/stream_video_flutter.dart' as stream;


class User {
  final stream.User user;
  final String? token;  

  User({required this.user, required this.token});

  static User createUser({
    required String userId,
    required String name,
    required String role,
    required String token,
  }) {
    return User(
      user: stream.User.regular(
        userId: userId,
        name: name,
        role: role,
      ),
      token: token,
    );
  }

}