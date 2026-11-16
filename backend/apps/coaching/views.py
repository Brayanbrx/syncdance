from django.utils import timezone
from drf_spectacular.utils import OpenApiResponse, extend_schema
from rest_framework import mixins, status, viewsets
from rest_framework.decorators import action
from rest_framework.response import Response
from rest_framework.throttling import ScopedRateThrottle

from .models import Assignment, Course, SessionNote
from .selectors import courses_for_student, notes_for_student, routine_evidence
from .serializers import JoinCourseSerializer, SessionNoteSerializer, StudentCourseSerializer
from .services import InvalidJoinCode, join_course, leave_course


class CourseViewSet(mixins.ListModelMixin, viewsets.GenericViewSet):
    """The student's courses with their assignments and progress. Instructors
    manage courses in the Django Admin."""

    queryset = Course.objects.none()
    serializer_class = StudentCourseSerializer
    throttle_scope = "join"

    def get_queryset(self):
        if getattr(self, "swagger_fake_view", False):
            return self.queryset
        return courses_for_student(user=self.request.user)

    def get_throttles(self):
        # Guessing codes is slowed down; reading progress is not.
        return [ScopedRateThrottle()] if self.action == "join" else super().get_throttles()

    def get_serializer_context(self):
        context = super().get_serializer_context()
        if getattr(self, "swagger_fake_view", False):
            return context
        user = self.request.user
        routine_ids = Assignment.objects.filter(course__enrollments__student=user).values_list(
            "routine_id", flat=True
        )
        evidence = routine_evidence(student_ids=[user.pk], routine_ids=list(routine_ids))
        context["evidence"] = {routine_id: value for (_, routine_id), value in evidence.items()}
        context["today"] = timezone.localdate()
        return context

    @extend_schema(
        request=JoinCourseSerializer,
        responses={
            201: StudentCourseSerializer,
            200: OpenApiResponse(
                StudentCourseSerializer, description="Ya pertenecías al curso; nada cambia."
            ),
            404: OpenApiResponse(description="Código no válido o curso cerrado."),
        },
    )
    @action(detail=False, methods=["post"])
    def join(self, request):
        serializer = JoinCourseSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        try:
            course, created = join_course(
                student=request.user, raw_code=serializer.validated_data["code"]
            )
        except InvalidJoinCode:
            return Response(
                {"detail": "Código no válido o el curso ya no acepta alumnos."},
                status=status.HTTP_404_NOT_FOUND,
            )
        course = self.get_queryset().get(pk=course.pk)
        return Response(
            self.get_serializer(course).data,
            status=status.HTTP_201_CREATED if created else status.HTTP_200_OK,
        )

    @extend_schema(request=None, responses={204: OpenApiResponse(description="Saliste del curso.")})
    @action(detail=True, methods=["post"])
    def leave(self, request, pk=None):
        leave_course(student=request.user, course=self.get_object())
        return Response(status=status.HTTP_204_NO_CONTENT)


class SessionNoteViewSet(mixins.ListModelMixin, viewsets.GenericViewSet):
    """Instructor observations on the requesting student's synced practices."""

    queryset = SessionNote.objects.none()
    serializer_class = SessionNoteSerializer

    def get_queryset(self):
        if getattr(self, "swagger_fake_view", False):
            return self.queryset
        return notes_for_student(user=self.request.user)
