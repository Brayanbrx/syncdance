import logging
import uuid

from drf_spectacular.utils import OpenApiResponse, extend_schema
from rest_framework import mixins, status, viewsets
from rest_framework.response import Response

from .models import DanceSession
from .selectors import get_sessions_for_user
from .serializers import DanceSessionSerializer
from .services import SessionAlreadyExists, create_session, find_synced_session

logger = logging.getLogger(__name__)


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

    @extend_schema(
        responses={
            201: DanceSessionSerializer,
            200: OpenApiResponse(
                DanceSessionSerializer,
                description="La sesión ya estaba sincronizada; se devuelve la copia guardada.",
            ),
            409: OpenApiResponse(description="El identificador pertenece a otra cuenta."),
        }
    )
    def create(self, request, *args, **kwargs):
        # Idempotent per client UUID: checked before validation so a retry still
        # succeeds after its routine or reference stopped accepting new sessions.
        session_id = _client_session_id(request.data)
        session = find_synced_session(student=request.user, session_id=session_id)
        created = False
        if session is None:
            if session_id and DanceSession.objects.filter(pk=session_id).exists():
                logger.warning(
                    "session id owned by another account",
                    extra={"session_id": str(session_id), "user_id": request.user.pk},
                )
                raise SessionAlreadyExists()
            serializer = self.get_serializer(data=request.data)
            serializer.is_valid(raise_exception=True)
            session, created = create_session(student=request.user, **serializer.validated_data)
        session = self.get_queryset().get(pk=session.pk)
        logger.info(
            "session stored" if created else "session retry answered with stored copy",
            extra={
                "session_id": str(session.pk),
                "user_id": request.user.pk,
                "routine_id": session.routine_id,
                "game": hasattr(session, "game"),
            },
        )
        return Response(
            self.get_serializer(session).data,
            status=status.HTTP_201_CREATED if created else status.HTTP_200_OK,
        )


def _client_session_id(data):
    try:
        return uuid.UUID(str(data["id"]))
    except (KeyError, TypeError, ValueError):
        return None  # Missing ids get a server UUID; invalid ones fail validation.
