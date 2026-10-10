import hashlib

from rest_framework import generics
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.throttling import ScopedRateThrottle, SimpleRateThrottle
from rest_framework_simplejwt.views import TokenObtainPairView

from .serializers import RegisterSerializer, UserSerializer


class LoginThrottle(SimpleRateThrottle):
    """Attempts per account name, not per address: a whole class can reach the
    server through one address (Docker Desktop, NAT), but guessing one
    student's password is still slowed down."""

    scope = "login"

    def get_cache_key(self, request, view):
        data = request.data if hasattr(request.data, "get") else {}
        username = str(data.get("username", "")).strip().lower()
        ident = hashlib.sha256(username.encode()).hexdigest() if username else None
        return self.cache_format % {"scope": self.scope, "ident": ident or self.get_ident(request)}


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
