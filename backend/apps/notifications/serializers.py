from rest_framework import serializers

from .models import Notification, PushDevice


class NotificationSerializer(serializers.ModelSerializer):
    read = serializers.SerializerMethodField()

    class Meta:
        model = Notification
        fields = ("id", "kind", "title", "body", "route", "created_at", "read")

    def get_read(self, notification) -> bool:
        return notification.read_at is not None


class DeviceSerializer(serializers.Serializer):
    token = serializers.CharField(max_length=512)
    platform = serializers.ChoiceField(
        choices=PushDevice.Platform.choices, default=PushDevice.Platform.ANDROID
    )
    app_version = serializers.CharField(max_length=32, required=False, allow_blank=True)


class TokenSerializer(serializers.Serializer):
    token = serializers.CharField(max_length=512)


class ReadSerializer(serializers.Serializer):
    # Absent: every unread notification.
    ids = serializers.ListField(child=serializers.IntegerField(), required=False, max_length=200)
