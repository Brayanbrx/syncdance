import json
import logging
from datetime import UTC, datetime

# Attributes every LogRecord has; anything else came from `extra=`.
_STANDARD = set(vars(logging.makeLogRecord({}))) | {"message", "asctime", "taskName"}


class JsonFormatter(logging.Formatter):
    """One JSON object per line for Docker logs: time, level, logger, message
    and the `extra=` fields (ids such as reference_id or task_id). Never log
    frames, passwords or tokens: only identifiers and outcomes."""

    def format(self, record):
        entry = {
            "time": datetime.fromtimestamp(record.created, UTC).isoformat(timespec="milliseconds"),
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
        }
        for key, value in vars(record).items():
            if key not in _STANDARD and not key.startswith("_"):
                entry[key] = value
        if record.exc_info:
            entry["exception"] = self.formatException(record.exc_info)
        return json.dumps(entry, ensure_ascii=False, default=str)
