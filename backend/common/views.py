from django.conf import settings
from drf_spectacular.utils import extend_schema, inline_serializer
from rest_framework import serializers
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import AllowAny
from rest_framework.response import Response


@extend_schema(
    responses=inline_serializer(
        name="HealthResponse",
        fields={
            "status": serializers.CharField(),
            "service": serializers.CharField(),
            "environment": serializers.ChoiceField(choices=["development", "production"]),
        },
    )
)
@api_view(["GET"])
@permission_classes([AllowAny])
def health_check(request):
    # The web shows the development seed (admin / admin) only in development.
    environment = "development" if settings.DEBUG else "production"
    return Response({"status": "ok", "service": "syncdance-backend", "environment": environment})
