import pytest
from django.core.cache import cache


@pytest.fixture(autouse=True)
def fresh_throttle():
    # Login throttle counters live in the cache and would leak between tests.
    cache.clear()
    yield
    cache.clear()
