import json
import logging

from common.logging import JsonFormatter


def _record(**extra):
    record = logging.LogRecord("apps.demo", logging.INFO, __file__, 1, "hola %s", ("mundo",), None)
    for key, value in extra.items():
        setattr(record, key, value)
    return record


def test_one_json_object_with_the_extra_ids():
    line = JsonFormatter().format(_record(reference_id=7, task_id="abc"))
    entry = json.loads(line)
    assert entry["level"] == "INFO"
    assert entry["logger"] == "apps.demo"
    assert entry["message"] == "hola mundo"
    assert entry["reference_id"] == 7
    assert entry["task_id"] == "abc"
    assert entry["time"].endswith("+00:00")
    # Standard LogRecord attributes are not repeated as fields.
    assert "args" not in entry and "pathname" not in entry
    assert "\n" not in line


def test_exceptions_and_unserializable_values_still_give_json():
    try:
        raise ValueError("boom")
    except ValueError:
        record = _record(request=object())
        record.exc_info = __import__("sys").exc_info()
    entry = json.loads(JsonFormatter().format(record))
    assert "ValueError: boom" in entry["exception"]
    assert entry["request"].startswith("<object")
