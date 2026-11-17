from django.urls import path
from rest_framework.routers import DefaultRouter

from .views import PracticeRatingView, StudioCourseViewSet, StudioRoutineViewSet

router = DefaultRouter()
router.register("routines", StudioRoutineViewSet, basename="studio-routine")
router.register("courses", StudioCourseViewSet, basename="studio-course")

urlpatterns = [
    *router.urls,
    path(
        "practices/<uuid:pk>/rating/", PracticeRatingView.as_view(), name="studio-practice-rating"
    ),
]
