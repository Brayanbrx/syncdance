from django.contrib.auth.password_validation import validate_password
from django.core.exceptions import ValidationError as DjangoValidationError
from rest_framework import serializers

from .models import User
from .services import register_user


class UserSerializer(serializers.ModelSerializer):
    # The web shows its administration panel only to platform administrators.
    is_platform_admin = serializers.BooleanField(source="manages_all_courses", read_only=True)

    class Meta:
        model = User
        fields = ("id", "username", "email", "first_name", "last_name", "role", "is_platform_admin")
        read_only_fields = ("id", "role")


class RegisterSerializer(serializers.ModelSerializer):
    password = serializers.CharField(write_only=True, min_length=8)
    # The sign-up form shows the terms and privacy policy with a checkbox.
    accept_terms = serializers.BooleanField(write_only=True)

    class Meta:
        model = User
        fields = ("id", "username", "email", "password", "first_name", "last_name", "accept_terms")
        read_only_fields = ("id",)

    def validate_accept_terms(self, value):
        if not value:
            raise serializers.ValidationError(
                "Para crear la cuenta acepta los términos y la política de privacidad."
            )
        return value

    def validate(self, attrs):
        # Same rules as the admin: not common, not only digits, not like the name.
        profile = {k: v for k, v in attrs.items() if k not in ("password", "accept_terms")}
        try:
            validate_password(attrs["password"], user=User(**profile))
        except DjangoValidationError as exc:
            raise serializers.ValidationError({"password": list(exc.messages)}) from exc
        return attrs

    def create(self, validated_data):
        validated_data.pop("accept_terms")
        return register_user(**validated_data)


class LegalSerializer(serializers.Serializer):
    controller = serializers.CharField()
    contact_email = serializers.CharField(allow_blank=True)
    terms_version = serializers.CharField()


class PasswordResetRequestSerializer(serializers.Serializer):
    email = serializers.EmailField()


class PasswordResetConfirmSerializer(serializers.Serializer):
    uid = serializers.CharField(max_length=64)
    token = serializers.CharField(max_length=128)
    new_password = serializers.CharField(write_only=True, max_length=128)


class DeleteAccountSerializer(serializers.Serializer):
    password = serializers.CharField(write_only=True, max_length=128)


class DetailSerializer(serializers.Serializer):
    detail = serializers.CharField()
