from rest_framework import mixins, viewsets

from .models import DanceSession
from .selectors import get_sessions_for_user
from .serializers import DanceSessionSerializer
from .services import create_session


class DanceSessionViewSet(
    mixins.CreateModelMixin,
    mixins.ListModelMixin,
    mixins.RetrieveModelMixin,
    viewsets.GenericViewSet,
):
    """Store client-calculated summaries. No video or inference request is required."""

    queryset = DanceSession.objects.none()
    serializer_class = DanceSessionSerializer

    def get_queryset(self):
        if getattr(self, "swagger_fake_view", False):
            return self.queryset
        return get_sessions_for_user(user=self.request.user)

    def perform_create(self, serializer):
        serializer.instance = create_session(student=self.request.user, **serializer.validated_data)
