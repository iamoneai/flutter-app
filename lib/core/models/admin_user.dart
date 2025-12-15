import 'package:cloud_firestore/cloud_firestore.dart';

class AdminUser {
  final String uid;
  final String email;
  final String? displayName;
  final String? firstName;
  final String? lastName;
  final String? iin;
  final String role;
  final String status;
  final List<String> permissions;
  final DateTime createdAt;
  final DateTime? updatedAt;

  // Role constants
  static const String roleSuperAdmin = 'super_admin';
  static const String roleAdmin = 'admin';
  static const String rolePromptEditor = 'prompt_editor';
  static const String roleConfigEditor = 'config_editor';
  static const String roleViewer = 'viewer';
  static const String roleUser = 'user';

  // Permission constants
  static const String permAll = 'all';
  static const String permApiKeys = 'api_keys';
  static const String permCategories = 'categories';
  static const String permRouting = 'routing';
  static const String permPrompts = 'prompts';
  static const String permSettings = 'settings';
  static const String permUsers = 'users';
  static const String permDocs = 'docs';

  // Admin roles that can access admin panel
  static const List<String> adminRoles = [
    roleSuperAdmin,
    roleAdmin,
    rolePromptEditor,
    roleConfigEditor,
    roleViewer,
  ];

  AdminUser({
    required this.uid,
    required this.email,
    this.displayName,
    this.firstName,
    this.lastName,
    this.iin,
    required this.role,
    required this.status,
    required this.permissions,
    required this.createdAt,
    this.updatedAt,
  });

  factory AdminUser.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return AdminUser(
      uid: doc.id,
      email: data['email'] ?? '',
      displayName: data['displayName'],
      firstName: data['firstName'],
      lastName: data['lastName'],
      iin: data['iin'],
      role: data['role'] ?? roleUser,
      status: data['status'] ?? 'ACTIVE',
      permissions: _parsePermissions(data['permissions'], data['role']),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  static List<String> _parsePermissions(dynamic perms, String? role) {
    // Super admin has all permissions
    if (role == roleSuperAdmin) {
      return [permAll];
    }

    // Parse from Firestore if available
    if (perms is List) {
      return perms.map((e) => e.toString()).toList();
    }

    // Default permissions based on role
    switch (role) {
      case roleAdmin:
        return [permApiKeys, permCategories, permRouting, permPrompts, permSettings, permDocs];
      case rolePromptEditor:
        return [permPrompts, permCategories];
      case roleConfigEditor:
        return [permApiKeys, permRouting, permSettings];
      case roleViewer:
        return [permDocs];
      default:
        return [];
    }
  }

  bool get isActive => status == 'ACTIVE';

  bool get isAdmin => adminRoles.contains(role);

  bool get isSuperAdmin => role == roleSuperAdmin;

  bool hasPermission(String permission) {
    if (permissions.contains(permAll)) return true;
    return permissions.contains(permission);
  }

  Map<String, dynamic> toMap() {
    return {
      'email': email,
      'displayName': displayName,
      'firstName': firstName,
      'lastName': lastName,
      'iin': iin,
      'role': role,
      'status': status,
      'permissions': permissions,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': updatedAt != null ? Timestamp.fromDate(updatedAt!) : null,
    };
  }
}
