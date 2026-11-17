from django.urls import include, path
from rest_framework.routers import DefaultRouter

from .views import (
    AppErrorView,
    DownloadLatestView,
    LatestReleaseView,
    PanelCatalogProposalViewSet,
    PanelCourseViewSet,
    PanelReleaseViewSet,
    PanelRoutineViewSet,
    PanelUserViewSet,
    PilotMetricsView,
    PlatformSummaryView,
)

panel = DefaultRouter()
panel.include_root_view = False
panel.register("users", PanelUserViewSet, basename="panel-user")
panel.register("routines", PanelRoutineViewSet, basename="panel-routine")
panel.register("courses", PanelCourseViewSet, basename="panel-course")
panel.register("proposals", PanelCatalogProposalViewSet, basename="panel-proposal")
panel.register("releases", PanelReleaseViewSet, basename="panel-release")

app_urlpatterns = [
    path("latest/", LatestReleaseView.as_view(), name="app-latest"),
    path("download/", DownloadLatestView.as_view(), name="app-download"),
    path("errors/", AppErrorView.as_view(), name="app-errors"),
]

panel_urlpatterns = [
    path("summary/", PlatformSummaryView.as_view(), name="panel-summary"),
    path("pilot/", PilotMetricsView.as_view(), name="panel-pilot"),
    path("", include(panel.urls)),
]
