from django.db import transaction
from django.db.models import Count, Prefetch
from django.shortcuts import get_object_or_404
from drf_spectacular.utils import OpenApiParameter, extend_schema
from rest_framework import mixins, status, viewsets
from rest_framework.decorators import action
from rest_framework.parsers import FormParser, JSONParser, MultiPartParser
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.accounts.serializers import DetailSerializer
from apps.coaching.concordance import concordance
from apps.coaching.models import Course, PracticeRating, SessionNote
from apps.coaching.selectors import students_of
from apps.routines.models import Routine, RoutineReference
from apps.training.models import DanceSession
from common.permissions import IsInstructorOrAdmin

from .progress import course_routines, recent_practices, step_map
from .quality import quality_report
from .serializers import (
    ChoreographySerializer,
    CoursePracticesSerializer,
    DifficultyMapSerializer,
    MapQuerySerializer,
    PublishSerializer,
    QualityReportSerializer,
    RatingSerializer,
    StudioCourseDetailSerializer,
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
    save_choreography,
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

    @extend_schema(
        request=ChoreographySerializer,
        responses={200: StudioRoutineSerializer, 409: DetailSerializer},
        description="Save the tempo and steps; students get them when it is published.",
    )
    @action(detail=True, methods=["put"])
    def choreography(self, request, pk=None):
        routine = self.get_object()
        data = ChoreographySerializer(data=request.data)
        data.is_valid(raise_exception=True)
        try:
            save_choreography(routine=routine, draft=data.validated_data)
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


class StudioCourseViewSet(
    mixins.ListModelMixin, mixins.RetrieveModelMixin, viewsets.GenericViewSet
):
    """The instructor's courses: where routines are published and how the
    students are doing (difficulty map, recent practices, ratings)."""

    permission_classes = [IsInstructorOrAdmin]
    serializer_class = StudioCourseSerializer
    pagination_class = None

    def get_serializer_class(self):
        if self.action == "retrieve":
            return StudioCourseDetailSerializer
        return StudioCourseSerializer

    @extend_schema(
        parameters=[MapQuerySerializer],
        responses={200: DifficultyMapSerializer, 404: DetailSerializer},
        description="Per step of the routine: each student's latest result and the group's.",
    )
    @action(detail=True, methods=["get"], url_path="map")
    def difficulty_map(self, request, pk=None):
        course = self.get_object()
        query = MapQuerySerializer(data=request.query_params)
        query.is_valid(raise_exception=True)
        routine = get_object_or_404(course_routines(course), pk=query.validated_data["routine"])
        data = step_map(
            course=course,
            routine=routine,
            follow_mode=query.validated_data["follow_mode"],
            speed=float(query.validated_data["speed"]),
        )
        return Response(DifficultyMapSerializer(data).data)

    @extend_schema(responses=CoursePracticesSerializer)
    @action(detail=True, methods=["get"])
    def practices(self, request, pk=None):
        course = self.get_object()
        data = {
            "concordance": concordance(PracticeRating.objects.filter(instructor=request.user)),
            "practices": recent_practices(course=course, instructor=request.user),
        }
        return Response(CoursePracticesSerializer(data).data)

    def get_queryset(self):
        if getattr(self, "swagger_fake_view", False):  # schema generation
            return Course.objects.none()
        return (
            Course.objects.filter(instructor=self.request.user)
            .annotate(students=Count("enrollments"))
            .order_by("name", "pk")
        )


class PracticeRatingView(APIView):
    """The instructor rates one practice of their students from 1 to 5."""

    permission_classes = [IsInstructorOrAdmin]

    def _practice(self, request, pk):
        return get_object_or_404(
            DanceSession.objects.filter(student__in=students_of(user=request.user)), pk=pk
        )

    @extend_schema(
        request=RatingSerializer,
        responses={200: RatingSerializer},
        parameters=[OpenApiParameter("id", str, OpenApiParameter.PATH)],
    )
    def put(self, request, pk):
        practice = self._practice(request, pk)
        data = RatingSerializer(data=request.data)
        data.is_valid(raise_exception=True)
        comment = data.validated_data["comment"].strip()
        with transaction.atomic():
            PracticeRating.objects.update_or_create(
                session=practice,
                instructor=request.user,
                defaults={"rating": data.validated_data["rating"]},
            )
            if comment:
                SessionNote.objects.create(session=practice, author=request.user, text=comment)
        return Response({"rating": data.validated_data["rating"], "comment": comment})

    @extend_schema(
        responses={204: None},
        parameters=[OpenApiParameter("id", str, OpenApiParameter.PATH)],
    )
    def delete(self, request, pk):
        practice = self._practice(request, pk)
        PracticeRating.objects.filter(session=practice, instructor=request.user).delete()
        return Response(status=status.HTTP_204_NO_CONTENT)
