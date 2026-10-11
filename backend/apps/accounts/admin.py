from django.contrib import admin
from django.contrib.auth.admin import UserAdmin as DjangoUserAdmin

from .models import User


@admin.register(User)
class UserAdmin(DjangoUserAdmin):
    # Students sign up from the app: find them by role and last access. The
    # instructor resets a forgotten password from the user's page.
    list_display = ("username", "email", "role", "is_active", "last_login", "date_joined")
    list_filter = ("role", "is_active", "is_staff")
    ordering = ("-date_joined",)
    fieldsets = DjangoUserAdmin.fieldsets + (("SyncDance", {"fields": ("role",)}),)
    add_fieldsets = DjangoUserAdmin.add_fieldsets + (("SyncDance", {"fields": ("email", "role")}),)
