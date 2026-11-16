import hashlib

from django.core.exceptions import ValidationError as DjangoValidationError
from drf_spectacular.utils import extend_schema
from rest_framework import generics, status
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response
from rest_framework.throttling import ScopedRateThrottle, SimpleRateThrottle
from rest_framework.views import APIView
from rest_framework_simplejwt.views import TokenObtainPairView

from .serializers import (
    DetailSerializer,
    PasswordResetConfirmSerializer,
    PasswordResetRequestSerializer,
    RegisterSerializer,
    UserSerializer,
)
from .services import InvalidResetLink, request_password_reset, reset_password


class FieldThrottle(SimpleRateThrottle):
    """Attempts per value of one request field (hashed), falling back to the
    address: a whole class can reach the server through one address (Docker
    Desktop, NAT), but one account or one mailbox is still protected."""

    field = ""

    def get_cache_key(self, request, view):
        data = request.data if hasattr(request.data, "get") else {}
        value = str(data.get(self.field, "")).strip().lower()
        ident = hashlib.sha256(value.encode()).hexdigest() if value else None
        return self.cache_format % {"scope": self.scope, "ident": ident or self.get_ident(request)}


class LoginThrottle(FieldThrottle):
    """Slows down guessing one student's password."""

    scope = "login"
    field = "username"


class PasswordResetThrottle(FieldThrottle):
    """Nobody can flood someone else's mailbox with reset links."""

    scope = "password_reset"
    field = "email"


class RegisterView(generics.CreateAPIView):
    serializer_class = RegisterSerializer
    permission_classes = [AllowAny]
    # Generous per address: a class signing up together shares one address.
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = "register"


class LoginView(TokenObtainPairView):
    throttle_classes = [LoginThrottle]


class MeView(generics.RetrieveAPIView):
    serializer_class = UserSerializer
    permission_classes = [IsAuthenticated]

    def get_object(self):
        return self.request.user


RESET_REQUESTED = (
    "Si existe una cuenta con ese correo, te enviamos un enlace para cambiar la contraseña."
)
RESET_INVALID = "El enlace no es válido o ya venció. Pide uno nuevo."


class PasswordResetRequestView(APIView):
    """Same answer whether or not the address is registered."""

    permission_classes = [AllowAny]
    authentication_classes = []  # a stale token in the header must not get in the way
    throttle_classes = [PasswordResetThrottle]

    @extend_schema(request=PasswordResetRequestSerializer, responses={202: DetailSerializer})
    def post(self, request):
        serializer = PasswordResetRequestSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        request_password_reset(email=serializer.validated_data["email"])
        return Response({"detail": RESET_REQUESTED}, status=status.HTTP_202_ACCEPTED)


class PasswordResetConfirmView(APIView):
    permission_classes = [AllowAny]
    authentication_classes = []
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = "password_reset_confirm"

    @extend_schema(request=PasswordResetConfirmSerializer, responses={200: DetailSerializer})
    def post(self, request):
        serializer = PasswordResetConfirmSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        try:
            reset_password(uid=data["uid"], token=data["token"], password=data["new_password"])
        except InvalidResetLink:
            return Response({"token": [RESET_INVALID]}, status=status.HTTP_400_BAD_REQUEST)
        except DjangoValidationError as exc:
            return Response(
                {"new_password": list(exc.messages)}, status=status.HTTP_400_BAD_REQUEST
            )
        return Response({"detail": "Contraseña cambiada. Ya puedes ingresar con la nueva."})
