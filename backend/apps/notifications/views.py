from drf_spectacular.utils import extend_schema
from rest_framework import status
from rest_framework.generics import ListAPIView
from rest_framework.response import Response
from rest_framework.views import APIView

from . import services
from .models import Notification
from .serializers import DeviceSerializer, NotificationSerializer, ReadSerializer, TokenSerializer


class NotificationListView(ListAPIView):
    """The signed-in person's inbox, newest first, with the unread count."""

    serializer_class = NotificationSerializer

    def get_queryset(self):
        return Notification.objects.filter(user=self.request.user)

    def list(self, request, *args, **kwargs):
        response = super().list(request, *args, **kwargs)
        response.data["unread"] = Notification.objects.filter(
            user=request.user, read_at__isnull=True
        ).count()
        return response


class MarkReadView(APIView):
    @extend_schema(request=ReadSerializer, responses={200: dict})
    def post(self, request):
        serializer = ReadSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        updated = services.mark_read(user=request.user, ids=serializer.validated_data.get("ids"))
        return Response({"updated": updated})


class DeviceView(APIView):
    """Register this phone's FCM token (after sign-in and when it rotates)."""

    @extend_schema(request=DeviceSerializer, responses={204: None})
    def post(self, request):
        serializer = DeviceSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        services.register_device(user=request.user, **serializer.validated_data)
        return Response(status=status.HTTP_204_NO_CONTENT)


class DeviceRemoveView(APIView):
    """Sign-out: this phone stops receiving this account's messages."""

    @extend_schema(request=TokenSerializer, responses={204: None})
    def post(self, request):
        serializer = TokenSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        services.unregister_device(user=request.user, token=serializer.validated_data["token"])
        return Response(status=status.HTTP_204_NO_CONTENT)
