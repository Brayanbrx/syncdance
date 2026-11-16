from rest_framework.permissions import BasePermission


class IsInstructorOrAdmin(BasePermission):
    def has_permission(self, request, view):
        return bool(
            request.user.is_authenticated
            and request.user.role in {request.user.Role.INSTRUCTOR, request.user.Role.ADMIN}
        )


class IsPlatformAdmin(BasePermission):
    """Superusers and the Administrator role: the web panel of the platform."""

    def has_permission(self, request, view):
        user = request.user
        return bool(user.is_authenticated and user.is_active and user.manages_all_courses)
