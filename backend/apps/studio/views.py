from django.db.models import Count, Prefetch
from drf_spectacular.utils import extend_schema
from rest_framework import mixins, status, viewsets
from rest_framework.decorators import action
from rest_framework.parsers import FormParser, JSONParser, MultiPartParser
from rest_framework.response import Response

from apps.accounts.serializers import DetailSerializer
from apps.coaching.models import Course
from apps.routines.models import Routine, RoutineReference
from common.permissions import IsInstructorOrAdmin

from .quality import quality_report
from .serializers import (
    PublishSerializer,
    QualityReportSerializer,
    StudioCourseSerializer,
    StudioRoutineSerializer,
    StudioRoutineWriteSerializer,
)
from .services import (
    StudioError,
    create_studio_routine,
    current_reference,
    delete_routine,
    propose_for_catalog,
    publish,
    unpublish,
    update_studio_routine,
    withdraw_from_catalog,
)


def refused(error: StudioError) -> Response:
    if error.conflict:
        return Response({"detail": str(error)}, status=status.HTTP_409_CONFLICT)
    return Response({error.field or "detail": [str(error)]}, status=status.HTTP_400_BAD_REQUEST)


class StudioRoutineViewSet(
    mixins.ListModelMixin,
    mixins.RetrieveModelMixin,
    viewsets.GenericViewSet,
):
    """The instructor's own routines: upload, review, publish in their courses."""

    permission_classes = [IsInstructorOrAdmin]
    serializer_class = StudioRoutineSerializer
    pagination_class = None  # one instructor's routines: a short list
    parser_classes = [JSONParser, MultiPartParser, FormParser]

    def get_queryset(self):
        if getattr(self, "swagger_fake_view", False):  # schema generation
            return Routine.objects.none()
        return (
            Routine.objects.filter(instructor=self.request.user)
            .prefetch_related(
                Prefetch("references", queryset=RoutineReference.objects.order_by("-version")),
                "published_in_courses",
            )
            .order_by("-created_at", "-pk")
        )

    def _answer(self, routine, code=status.HTTP_200_OK):
        routine = self.get_queryset().get(pk=routine.pk)
        return Response(self.get_serializer(routine).data, status=code)

    @extend_schema(request=StudioRoutineWriteSerializer, responses={201: StudioRoutineSerializer})
    def create(self, request):
        data = StudioRoutineWriteSerializer(data=request.data)
        data.is_valid(raise_exception=True)
        fields = dict(data.validated_data)
        video = fields.pop("master_video", None)
        if video is None:
            return Response(
                {"master_video": ["Sube el video de la rutina."]},
                status=status.HTTP_400_BAD_REQUEST,
            )
        try:
            routine = create_studio_routine(instructor=request.user, master_video=video, **fields)
        except StudioError as error:
            return refused(error)
        return self._answer(routine, status.HTTP_201_CREATED)

    @extend_schema(request=StudioRoutineWriteSerializer, responses=StudioRoutineSerializer)
    def partial_update(self, request, pk=None):
        routine = self.get_object()
        data = StudioRoutineWriteSerializer(routine, data=request.data, partial=True)
        data.is_valid(raise_exception=True)
        try:
            update_studio_routine(routine=routine, **data.validated_data)
        except StudioError as error:
            return refused(error)
        return self._answer(routine)

    @extend_schema(responses={204: None, 409: DetailSerializer})
    def destroy(self, request, pk=None):
        try:
            delete_routine(routine=self.get_object())
        except StudioError as error:
            return refused(error)
        return Response(status=status.HTTP_204_NO_CONTENT)

    @extend_schema(request=PublishSerializer, responses=StudioRoutineSerializer)
    @action(detail=True, methods=["post"])
    def publish(self, request, pk=None):
        routine = self.get_object()
        data = PublishSerializer(data=request.data)
        data.is_valid(raise_exception=True)
        try:
            publish(
                routine=routine,
                user=request.user,
                course_ids=data.validated_data["courses"],
                music_rights=data.validated_data.get("music_rights") or None,
            )
        except StudioError as error:
            return refused(error)
        return self._answer(routine)

    @extend_schema(request=None, responses=StudioRoutineSerializer)
    @action(detail=True, methods=["post"])
    def unpublish(self, request, pk=None):
        return self._answer(unpublish(routine=self.get_object()))

    @extend_schema(
        methods=["POST"],
        request=None,
        responses={200: StudioRoutineSerializer, 409: DetailSerializer},
        description="Propose the published routine for the SyncDance catalog.",
    )
    @extend_schema(
        methods=["DELETE"],
        request=None,
        responses={200: StudioRoutineSerializer, 409: DetailSerializer},
        description="Withdraw the proposal, or take the routine out of the catalog.",
    )
    @action(detail=True, methods=["post", "delete"])
    def catalog(self, request, pk=None):
        action = propose_for_catalog if request.method == "POST" else withdraw_from_catalog
        try:
            routine = action(routine=self.get_object())
        except StudioError as error:
            return refused(error)
        return self._answer(routine)

    @extend_schema(responses={200: QualityReportSerializer, 404: DetailSerializer})
    @action(detail=True, methods=["get"])
    def quality(self, request, pk=None):
        report = quality_report(current_reference(self.get_object()))
        if report is None:
            return Response(
                {"detail": "Todavía no hay una referencia lista."},
                status=status.HTTP_404_NOT_FOUND,
            )
        return Response(report)


class StudioCourseViewSet(mixins.ListModelMixin, viewsets.GenericViewSet):
    """The instructor's courses, to choose where a routine is published."""

    permission_classes = [IsInstructorOrAdmin]
    serializer_class = StudioCourseSerializer
    pagination_class = None

    def get_queryset(self):
        if getattr(self, "swagger_fake_view", False):  # schema generation
            return Course.objects.none()
        return (
            Course.objects.filter(instructor=self.request.user)
            .annotate(students=Count("enrollments"))
            .order_by("name", "pk")
        )
