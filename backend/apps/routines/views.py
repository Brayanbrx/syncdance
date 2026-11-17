import mimetypes

from django.http import FileResponse
from drf_spectacular.types import OpenApiTypes
from drf_spectacular.utils import OpenApiParameter, extend_schema, extend_schema_view
from rest_framework import permissions, viewsets
from rest_framework.decorators import action
from rest_framework.exceptions import NotFound
from rest_framework.response import Response

from common.permissions import IsInstructorOrAdmin

from .models import Routine, RoutineReference
from .reference_services import queue_reference
from .selectors import get_routines_for_user
from .serializers import RoutineReferenceSerializer, RoutineSerializer
from .services import create_routine, update_routine

# Singing routines play AAC audio; some systems lack this mapping.
mimetypes.add_type("audio/mp4", ".m4a")


@extend_schema_view(
    list=extend_schema(
        parameters=[
            OpenApiParameter(
                "kind",
                str,
                enum=Routine.Kind.values,
                required=False,
                description="Solo rutinas de baile (DANCE) o de canto (SING).",
            )
        ]
    )
)
class RoutineViewSet(viewsets.ModelViewSet):
    queryset = Routine.objects.all()
    serializer_class = RoutineSerializer

    def get_queryset(self):
        routines = get_routines_for_user(user=self.request.user)
        # The app lists dance and singing in separate sections.
        kind = self.request.query_params.get("kind")
        if self.action == "list" and kind in Routine.Kind.values:
            routines = routines.filter(kind=kind)
        return routines

    def get_permissions(self):
        if self.action in {
            "list",
            "retrieve",
            "reference",
            "reference_status",
            "reference_download",
            "reference_video",
            "reference_poster",
        }:
            return [permissions.IsAuthenticated()]
        return [IsInstructorOrAdmin()]

    @extend_schema(responses=RoutineReferenceSerializer)
    @action(detail=True, methods=["get"])
    def reference(self, request, pk=None):
        routine = self.get_object()
        reference = (
            routine.references.filter(
                status=RoutineReference.Status.READY, source_video=routine.master_video.name
            )
            .exclude(reference_asset="")
            .first()
        )
        if reference is None:
            raise NotFound("La rutina todavía no tiene una referencia lista.")
        return Response(RoutineReferenceSerializer(reference, context={"request": request}).data)

    @extend_schema(request=None, responses={202: RoutineReferenceSerializer})
    @action(detail=True, methods=["post"], url_path="generate-reference")
    def generate_reference(self, request, pk=None):
        reference = queue_reference(routine_id=self.get_object().pk)
        reference.refresh_from_db()
        return Response(
            RoutineReferenceSerializer(reference, context={"request": request}).data, status=202
        )

    @extend_schema(responses=RoutineReferenceSerializer)
    @action(detail=True, methods=["get"], url_path="reference-status")
    def reference_status(self, request, pk=None):
        routine = self.get_object()
        reference = routine.references.filter(source_video=routine.master_video.name).first()
        if reference is None:
            raise NotFound("No hay procesamiento para el video actual.")
        return Response(RoutineReferenceSerializer(reference, context={"request": request}).data)

    @extend_schema(responses={(200, "application/gzip"): OpenApiTypes.BINARY})
    @action(
        detail=True,
        methods=["get"],
        url_path=r"references/(?P<version>[0-9]+)/download",
        url_name="reference-download",
    )
    def reference_download(self, request, pk=None, version=None):
        reference = self.get_object().references.filter(version=version, status="READY").first()
        if reference is None or not reference.reference_asset:
            raise NotFound("Referencia no disponible.")
        try:
            source = reference.reference_asset.open("rb")
        except FileNotFoundError as exc:
            raise NotFound("El archivo de referencia no está disponible.") from exc
        response = FileResponse(
            source,
            content_type="application/gzip",
            as_attachment=True,
            filename=f"reference-v{reference.version}.json.gz",
        )
        response["ETag"] = f'"{reference.checksum_sha256}"'
        response["Cache-Control"] = "private, no-cache"
        return response

    def perform_create(self, serializer):
        serializer.instance = create_routine(
            instructor=self.request.user,
            **serializer.validated_data,
        )

    @extend_schema(responses={(200, "application/octet-stream"): OpenApiTypes.BINARY})
    @action(
        detail=True,
        methods=["get"],
        url_path=r"references/(?P<version>[0-9]+)/video",
        url_name="reference-video",
    )
    def reference_video(self, request, pk=None, version=None):
        # Serve the video pinned to this version, even after the master changes:
        # the light version the reference was computed from, when it exists.
        reference = self.get_object().references.filter(version=version, status="READY").first()
        if reference is None or not reference.video or not reference.source_sha256:
            raise NotFound("Video de referencia no disponible.")
        try:
            source = reference.video.open("rb")
        except FileNotFoundError as exc:
            raise NotFound("El video de referencia no está disponible.") from exc
        response = FileResponse(
            source,
            content_type=mimetypes.guess_type(reference.video.name)[0]
            or "application/octet-stream",
        )
        response["ETag"] = f'"{reference.source_sha256}"'
        response["Cache-Control"] = "private, no-cache"
        return response

    @extend_schema(responses={(200, "image/jpeg"): OpenApiTypes.BINARY})
    @action(
        detail=True,
        methods=["get"],
        url_path=r"references/(?P<version>[0-9]+)/poster",
        url_name="reference-poster",
    )
    def reference_poster(self, request, pk=None, version=None):
        reference = self.get_object().references.filter(version=version, status="READY").first()
        if reference is None or not reference.poster:
            raise NotFound("Miniatura no disponible.")
        try:
            source = reference.poster.open("rb")
        except FileNotFoundError as exc:
            raise NotFound("Miniatura no disponible.") from exc
        response = FileResponse(source, content_type="image/jpeg")
        # A version never changes its poster.
        response["Cache-Control"] = "private, max-age=86400"
        return response

    def perform_update(self, serializer):
        serializer.instance = update_routine(
            routine=serializer.instance,
            **serializer.validated_data,
        )
