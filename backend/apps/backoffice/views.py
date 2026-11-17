from django.http import FileResponse, Http404
from drf_spectacular.types import OpenApiTypes
from drf_spectacular.utils import OpenApiParameter, OpenApiResponse, extend_schema
from rest_framework import mixins, status, viewsets
from rest_framework.decorators import action
from rest_framework.parsers import FormParser, JSONParser, MultiPartParser
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.throttling import ScopedRateThrottle
from rest_framework.views import APIView

from common.permissions import IsPlatformAdmin

from .models import AppRelease
from .selectors import (
    catalog_proposals,
    latest_release,
    panel_courses,
    panel_routines,
    panel_users,
    pilot_metrics,
    platform_summary,
)
from .serializers import (
    AppErrorSerializer,
    CatalogProposalSerializer,
    PanelCourseSerializer,
    PanelReleaseSerializer,
    PanelReleaseUpdateSerializer,
    PanelRoutineSerializer,
    PanelUserCreateSerializer,
    PanelUserSerializer,
    PasswordSerializer,
    PilotMetricsSerializer,
    PlatformSummarySerializer,
    PublicReleaseSerializer,
    ReviewNoteSerializer,
)
from .services import (
    approve_for_catalog,
    create_release,
    create_user,
    delete_release,
    reject_for_catalog,
    report_app_error,
    set_password,
    update_release,
    update_user,
)

NO_RELEASE = "Todavía no hay una versión publicada de la app."


class AppErrorView(APIView):
    """Public: the Android app reports an error it hit (no account needed:
    it may crash before signing in). Throttled per address."""

    permission_classes = [AllowAny]
    authentication_classes = []
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = "app_errors"

    @extend_schema(request=AppErrorSerializer, responses={204: None})
    def post(self, request):
        data = AppErrorSerializer(data=request.data)
        data.is_valid(raise_exception=True)
        report_app_error(**data.validated_data)
        return Response(status=status.HTTP_204_NO_CONTENT)


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
class PilotMetricsView(APIView):
    """The pilot's gate figures (E5): activity, retention, routines per
    instructor, app-instructor concordance and calibration."""

    permission_classes = [IsPlatformAdmin]

    @extend_schema(responses=PilotMetricsSerializer)
    def get(self, request):
        return Response(PilotMetricsSerializer(pilot_metrics()).data)


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


class PanelCatalogProposalViewSet(mixins.ListModelMixin, viewsets.GenericViewSet):
    """Routines instructors proposed for the free catalog: approve or reject."""

    permission_classes = [IsPlatformAdmin]
    serializer_class = CatalogProposalSerializer
    pagination_class = None  # a review queue: short by nature

    def get_queryset(self):
        return catalog_proposals()

    @extend_schema(
        request=None,
        responses={204: None, 409: OpenApiResponse(description="Ya no está pendiente")},
    )
    @action(detail=True, methods=["post"])
    def approve(self, request, pk=None):
        approve_for_catalog(actor=request.user, routine=self.get_object())
        return Response(status=status.HTTP_204_NO_CONTENT)

    @extend_schema(
        request=ReviewNoteSerializer,
        responses={204: None, 409: OpenApiResponse(description="Ya no está pendiente")},
    )
    @action(detail=True, methods=["post"])
    def reject(self, request, pk=None):
        data = ReviewNoteSerializer(data=request.data)
        data.is_valid(raise_exception=True)
        reject_for_catalog(
            actor=request.user, routine=self.get_object(), note=data.validated_data.get("note")
        )
        return Response(status=status.HTTP_204_NO_CONTENT)


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
