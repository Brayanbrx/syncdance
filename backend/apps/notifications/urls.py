from django.urls import path

from .views import DeviceRemoveView, DeviceView, MarkReadView, NotificationListView

urlpatterns = [
    path("", NotificationListView.as_view(), name="notification-list"),
    path("read/", MarkReadView.as_view(), name="notification-read"),
    path("devices/", DeviceView.as_view(), name="notification-device"),
    path("devices/remove/", DeviceRemoveView.as_view(), name="notification-device-remove"),
]
