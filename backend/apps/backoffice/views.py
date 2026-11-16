from django.http import FileResponse, Http404
from drf_spectacular.types import OpenApiTypes
from drf_spectacular.utils import OpenApiParameter, OpenApiResponse, extend_schema
from rest_framework import mixins, status, viewsets
from rest_framework.decorators import action
from rest_framework.parsers import FormParser, JSONParser, MultiPartParser
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.views import APIView

from common.permissions import IsPlatformAdmin

from .models import AppRelease
from .selectors import latest_release, panel_courses, panel_routines, panel_users, platform_summary
from .serializers import (
    PanelCourseSerializer,
    PanelReleaseSerializer,
    PanelReleaseUpdateSerializer,
    PanelRoutineSerializer,
    PanelUserCreateSerializer,
    PanelUserSerializer,
    PasswordSerializer,
    PlatformSummarySerializer,
    PublicReleaseSerializer,
)
from .services import (
    create_release,
    create_user,
    delete_release,
    set_password,
    update_release,
    update_user,
)

NO_RELEASE = "Todavía no hay una versión publicada de la app."


class LatestReleaseView(APIView):
    """Public: what the landing page offers to download."""

    permission_classes = [AllowAny]
    authentication_classes = []

    @extend_schema(
        responses={200: PublicReleaseSerializer, 404: OpenApiResponse(description=NO_RELEASE)}
    )
    def get(self, request):
        release = latest_release()
        if release is None:
            return Response({"detail": NO_RELEASE}, status=status.HTTP_404_NOT_FOUND)
        return Response(PublicReleaseSerializer(release).data)


class DownloadLatestView(APIView):
    """Public: the newest published APK, as a file to install."""

    permission_classes = [AllowAny]
    authentication_classes = []

    @extend_schema(
        responses={
            (200, "application/vnd.android.package-archive"): OpenApiTypes.BINARY,
            404: OpenApiResponse(description=NO_RELEASE),
        }
    )
    def get(self, request):
        release = latest_release()
        if release is None or not release.apk:
            raise Http404(NO_RELEASE)
        try:
            handle = release.apk.open("rb")
        except FileNotFoundError as exc:
            raise Http404(NO_RELEASE) from exc
        response = FileResponse(
            handle,
            as_attachment=True,
            filename=release.download_name,
            content_type="application/vnd.android.package-archive",
        )
        response["ETag"] = f'"{release.sha256}"'
        return response


class PlatformSummaryView(APIView):
    permission_classes = [IsPlatformAdmin]

    @extend_schema(responses=PlatformSummarySerializer)
    def get(self, request):
        return Response(PlatformSummarySerializer(platform_summary()).data)


@extend_schema(
    parameters=[
        OpenApiParameter("role", str, enum=["STUDENT", "INSTRUCTOR", "ADMIN"]),
        OpenApiParameter("active", bool),
        OpenApiParameter("search", str),
    ]
)
class PanelUserViewSet(
    mixins.ListModelMixin,
    mixins.RetrieveModelMixin,
    mixins.CreateModelMixin,
    mixins.UpdateModelMixin,
    viewsets.GenericViewSet,
):
    permission_classes = [IsPlatformAdmin]
    serializer_class = PanelUserSerializer
    http_method_names = ["get", "post", "patch"]

    def get_queryset(self):
        params = self.request.query_params
        active = params.get("active")
        return panel_users(
            role=params.get("role") or None,
            active=None if active in (None, "") else active.lower() == "true",
            search=(params.get("search") or "").strip() or None,
        )

    def get_serializer_class(self):
        return PanelUserCreateSerializer if self.action == "create" else PanelUserSerializer

    @extend_schema(request=PanelUserCreateSerializer, responses={201: PanelUserSerializer})
    def create(self, request, *args, **kwargs):
        serializer = PanelUserCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        user = create_user(actor=request.user, **serializer.validated_data)
        return Response(PanelUserSerializer(user).data, status=status.HTTP_201_CREATED)

    def perform_update(self, serializer):
        serializer.instance = update_user(
            actor=self.request.user, user=serializer.instance, **serializer.validated_data
        )

    @extend_schema(request=PasswordSerializer, responses={204: None})
    @action(detail=True, methods=["post"], url_path="set-password")
    def set_password(self, request, pk=None):
        serializer = PasswordSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        set_password(
            actor=request.user,
            user=self.get_object(),
            password=serializer.validated_data["password"],
        )
        return Response(status=status.HTTP_204_NO_CONTENT)


class PanelRoutineViewSet(mixins.ListModelMixin, mixins.UpdateModelMixin, viewsets.GenericViewSet):
    """Catalog overview; only publishing (is_active) changes here. Videos and
    references are managed in the Django Admin."""

    permission_classes = [IsPlatformAdmin]
    serializer_class = PanelRoutineSerializer
    http_method_names = ["get", "patch"]

    def get_queryset(self):
        return panel_routines()


class PanelCourseViewSet(mixins.ListModelMixin, viewsets.GenericViewSet):
    permission_classes = [IsPlatformAdmin]
    serializer_class = PanelCourseSerializer

    def get_queryset(self):
        return panel_courses()


class PanelReleaseViewSet(
    mixins.ListModelMixin,
    mixins.CreateModelMixin,
    mixins.UpdateModelMixin,
    mixins.DestroyModelMixin,
    viewsets.GenericViewSet,
):
    permission_classes = [IsPlatformAdmin]
    parser_classes = [MultiPartParser, FormParser, JSONParser]
    queryset = AppRelease.objects.select_related("uploaded_by")
    http_method_names = ["get", "post", "patch", "delete"]

    def get_serializer_class(self):
        if self.action == "partial_update":
            return PanelReleaseUpdateSerializer
        return PanelReleaseSerializer

    @extend_schema(request=PanelReleaseSerializer, responses={201: PanelReleaseSerializer})
    def create(self, request, *args, **kwargs):
        serializer = PanelReleaseSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        release = create_release(actor=request.user, **serializer.validated_data)
        return Response(PanelReleaseSerializer(release).data, status=status.HTTP_201_CREATED)

    @extend_schema(request=PanelReleaseUpdateSerializer, responses=PanelReleaseSerializer)
    def partial_update(self, request, *args, **kwargs):
        release = self.get_object()
        serializer = PanelReleaseUpdateSerializer(release, data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        release = update_release(release=release, **serializer.validated_data)
        return Response(PanelReleaseSerializer(release).data)

    def perform_destroy(self, instance):
        delete_release(release=instance)
