import 'package:uuid/uuid.dart';
import 'package:parishrecord/models/user.dart';
import 'constants.dart';

class SeedData {
  static final _uuid = const Uuid();

  static List<AppUser> users = [
    AppUser(
      id: _uuid.v4(),
      email: 'admin@parish.com',
      displayName: 'Admin User',
      role: AppRoles.admin,
      emailVerified: true,
    ),
    AppUser(
      id: _uuid.v4(),
      email: 'staff@parish.com',
      displayName: 'Staff Member',
      role: AppRoles.staff,
      emailVerified: true,
    ),
  ];
}
