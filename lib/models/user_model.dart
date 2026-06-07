class UserModel {
  final String uid;
  final String name;
  final String email;
  final List<String> espDevices;

  UserModel({
    required this.uid,
    required this.name,
    required this.email,
    required this.espDevices,
  });

  factory UserModel.fromMap(Map<dynamic, dynamic> map, String uid) {
    return UserModel(
      uid: uid,
      name: map['name'] ?? '',
      email: map['email'] ?? '',
      espDevices: List<String>.from(map['espDevices'] ?? []),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'email': email,
      'espDevices': espDevices,
    };
  }
}
