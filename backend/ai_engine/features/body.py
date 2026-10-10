"""2D geometry matching mobile body-features-v1, without Django dependencies."""

import math

JOINTS = (
    "nose",
    "leftEyeInner",
    "leftEye",
    "leftEyeOuter",
    "rightEyeInner",
    "rightEye",
    "rightEyeOuter",
    "leftEar",
    "rightEar",
    "leftMouth",
    "rightMouth",
    "leftShoulder",
    "rightShoulder",
    "leftElbow",
    "rightElbow",
    "leftWrist",
    "rightWrist",
    "leftPinky",
    "rightPinky",
    "leftIndex",
    "rightIndex",
    "leftThumb",
    "rightThumb",
    "leftHip",
    "rightHip",
    "leftKnee",
    "rightKnee",
    "leftAnkle",
    "rightAnkle",
    "leftHeel",
    "rightHeel",
    "leftFootIndex",
    "rightFootIndex",
)
TRIPLETS = {
    "leftElbow": ("leftShoulder", "leftElbow", "leftWrist"),
    "rightElbow": ("rightShoulder", "rightElbow", "rightWrist"),
    "leftShoulder": ("leftElbow", "leftShoulder", "leftHip"),
    "rightShoulder": ("rightElbow", "rightShoulder", "rightHip"),
    "leftKnee": ("leftHip", "leftKnee", "leftAnkle"),
    "rightKnee": ("rightHip", "rightKnee", "rightAnkle"),
}


def extract_features(landmarks, aspect_ratio):
    if not math.isfinite(aspect_ratio) or aspect_ratio <= 0:
        raise ValueError("Invalid image aspect ratio")
    points = {}
    for point in landmarks:
        x, y, confidence = (point[key] for key in ("x", "y", "confidence"))
        if not all(math.isfinite(v) for v in (x, y, confidence)):
            continue
        if 0 <= x <= 1 and 0 <= y <= 1 and 0.5 <= confidence <= 1:
            points[point["joint"]] = (x * aspect_ratio, y)
    anchors = ("leftHip", "rightHip", "leftShoulder", "rightShoulder")
    if any(key not in points for key in anchors):
        return {}, {}
    lh, rh, ls, rs = (points[key] for key in anchors)
    origin = ((lh[0] + rh[0]) / 2, (lh[1] + rh[1]) / 2)
    torso = ((ls[0] + rs[0]) / 2 - origin[0], (ls[1] + rs[1]) / 2 - origin[1])
    scale = math.hypot(*torso)
    if not math.isfinite(scale) or scale <= 1e-6:
        return {}, {}
    normalized = {
        key: [(p[0] - origin[0]) / scale, (p[1] - origin[1]) / scale] for key, p in points.items()
    }
    angles = {}
    for name, (a, v, b) in TRIPLETS.items():
        if any(key not in normalized for key in (a, v, b)):
            continue
        a, v, b = (normalized[key] for key in (a, v, b))
        ax, ay, bx, by = a[0] - v[0], a[1] - v[1], b[0] - v[0], b[1] - v[1]
        if math.hypot(ax, ay) <= 1e-6 or math.hypot(bx, by) <= 1e-6:
            continue
        angles[name] = math.degrees(math.atan2(abs(ax * by - ay * bx), ax * bx + ay * by))
    return normalized, angles
