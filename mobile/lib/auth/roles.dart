/// RBAC definitions — mirrors shared/contracts/auth-rbac.json.
/// Keep the two in sync: that contract is what the NestJS backend and
/// Firebase security rules enforce server-side; this file is the
/// client-side mirror used for UI gating.
library;

enum UserRole {
  appUser('app_user'),
  admin('admin');

  const UserRole(this.claim);

  /// Value carried in the Firebase custom claim `role`.
  final String claim;

  static UserRole fromClaim(String? value) => switch (value) {
        'admin' => UserRole.admin,
        _ => UserRole.appUser,
      };
}

enum Permission {
  // App User (mobile surface)
  viewOwnPatients,
  viewLiveReadout,
  viewOwnHistory,
  acknowledgeOwnAlerts,
  manageOwnProfile,
  pairDevice,
  submitComplaint,
  viewOwnComplaints,
  receivePush,
  // Admin (web panel surface)
  viewFleet,
  viewAllPatientsLive,
  manageUsers,
  manageAssignments,
  overseeAlerts,
  resolveComplaints,
  manageAdminSettings,
}

const Map<UserRole, Set<Permission>> rolePermissions = {
  UserRole.appUser: {
    Permission.viewOwnPatients,
    Permission.viewLiveReadout,
    Permission.viewOwnHistory,
    Permission.acknowledgeOwnAlerts,
    Permission.manageOwnProfile,
    Permission.pairDevice,
    Permission.submitComplaint,
    Permission.viewOwnComplaints,
    Permission.receivePush,
  },
  UserRole.admin: {
    Permission.viewFleet,
    Permission.viewAllPatientsLive,
    Permission.manageUsers,
    Permission.manageAssignments,
    Permission.overseeAlerts,
    Permission.resolveComplaints,
    Permission.manageAdminSettings,
  },
};

extension RoleChecks on UserRole {
  bool can(Permission permission) =>
      rolePermissions[this]?.contains(permission) ?? false;

  /// The mobile app is the App User surface — admins use the web panel.
  bool get mayUseMobileApp => can(Permission.viewOwnPatients);
}
