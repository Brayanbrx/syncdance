from rest_framework.routers import DefaultRouter

from .views import StudioCourseViewSet, StudioRoutineViewSet

router = DefaultRouter()
router.register("routines", StudioRoutineViewSet, basename="studio-routine")
router.register("courses", StudioCourseViewSet, basename="studio-course")

urlpatterns = router.urls
