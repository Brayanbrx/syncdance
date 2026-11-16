from django.conf import settings
from django.conf.urls.static import static
from django.contrib import admin
from django.urls import include, path
from drf_spectacular.views import SpectacularAPIView, SpectacularSwaggerView
from rest_framework.routers import DefaultRouter

from apps.backoffice.urls import app_urlpatterns, panel_urlpatterns
from apps.coaching.views import CourseViewSet, SessionNoteViewSet
from apps.performances.views import PerformanceViewSet
from apps.routines.views import RoutineViewSet
from apps.training.views import DanceSessionViewSet
from common.views import health_check

router = DefaultRouter()
router.register("routines", RoutineViewSet, basename="routine")
router.register("performances", PerformanceViewSet, basename="performance")
router.register("training/sessions", DanceSessionViewSet, basename="session")
router.register("coaching/courses", CourseViewSet, basename="course")
router.register("coaching/notes", SessionNoteViewSet, basename="session-note")


urlpatterns = [
    path("admin/", admin.site.urls),
    path("api/schema/", SpectacularAPIView.as_view(), name="schema"),
    path("api/docs/", SpectacularSwaggerView.as_view(url_name="schema"), name="swagger-ui"),
    path("api/health/", health_check, name="health-check"),
    path("api/auth/", include("apps.accounts.urls")),
    path("api/app/", include(app_urlpatterns)),
    path("api/panel/", include(panel_urlpatterns)),
    path("api/studio/", include("apps.studio.urls")),
    path("api/", include(router.urls)),
    path("api/performances/", include("apps.analysis.urls")),
]

if settings.DEBUG:
    urlpatterns += static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)
