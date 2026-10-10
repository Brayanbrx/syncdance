"""Stick body of a generated coach, seen from the front like a phone 2-3 m away.

Coordinates in metres: +X is screen right, +Y up, +Z toward the camera. The
coach faces the learner, so the coach's anatomical LEFT is at +X. In mirror mode
the learner's right follows screen right: step sheets are written in screen
terms and the stored reference keeps the coach's anatomical labels.
"""

import math
from dataclasses import dataclass, replace

HIP_HALF = 0.10
SHOULDER_HALF = 0.19
TORSO = 0.50
NECK_TO_NOSE = 0.24
UPPER_ARM = 0.30
FOREARM = 0.27
THIGH = 0.44
SHIN = 0.43
ANKLE_HEIGHT = 0.08
STAND_HEIGHT = ANKLE_HEIGHT + THIGH + SHIN - 0.01  # knees almost straight
FOOT = 0.11  # half stance: ankles under the hips


@dataclass(frozen=True)
class Arm:
    """Frontal raise 0 (down) .. 90 (out) .. 180 (up); forward raise toward the
    camera; elbow flexion bending the forearm along `bend` (out, up, forward),
    where `out` points away from the body midline."""

    raise_deg: float = 8.0
    forward_deg: float = 0.0
    elbow_deg: float = 6.0
    bend: tuple[float, float, float] = (0.0, 1.0, 0.0)


@dataclass(frozen=True)
class Pose:
    """Pelvis and ankle positions drive the legs by inverse kinematics."""

    pelvis: tuple[float, float, float] = (0.0, STAND_HEIGHT, 0.0)
    left_foot: tuple[float, float, float] = (FOOT, ANKLE_HEIGHT, 0.0)  # screen right
    right_foot: tuple[float, float, float] = (-FOOT, ANKLE_HEIGHT, 0.0)  # screen left
    left_arm: Arm = Arm()
    right_arm: Arm = Arm()
    lean_deg: float = 0.0  # positive tilts the torso toward screen right

    def with_arms(self, left, right=None):
        return replace(self, left_arm=left, right_arm=right if right is not None else left)


def _add(a, b, k=1.0):
    return (a[0] + k * b[0], a[1] + k * b[1], a[2] + k * b[2])


def _sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def _dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def _norm(a):
    length = math.sqrt(_dot(a, a))
    return (a[0] / length, a[1] / length, a[2] / length)


def _perpendicular(vector, axis, fallback=(0.0, 0.0, 1.0)):
    """Component of `vector` orthogonal to unit `axis`, normalized."""
    rest = _add(vector, axis, -_dot(vector, axis))
    if _dot(rest, rest) < 1e-9:
        rest = _add(fallback, axis, -_dot(fallback, axis))
    return _norm(rest)


def _leg(hip, ankle, side):
    """Two-bone IK: knees bend forward and slightly outward, like a person."""
    to_ankle = _sub(ankle, hip)
    reach = THIGH + SHIN - 1e-4
    distance = min(max(math.sqrt(_dot(to_ankle, to_ankle)), 0.2), reach)
    direction = _norm(to_ankle)
    ankle = _add(hip, direction, distance)
    along = (THIGH**2 - SHIN**2 + distance**2) / (2 * distance)
    height = math.sqrt(max(THIGH**2 - along**2, 0.0))
    pole = _perpendicular((0.25 * side, 0.0, 1.0), direction)
    knee = _add(_add(hip, direction, along), pole, height)
    return knee, ankle


def _arm(shoulder, arm, side):
    raise_rad = math.radians(arm.raise_deg)
    forward_rad = math.radians(arm.forward_deg)
    frontal = (side * math.sin(raise_rad), -math.cos(raise_rad), 0.0)
    upper = _norm(_add((0.0, 0.0, math.sin(forward_rad)), frontal, math.cos(forward_rad)))
    bend = _perpendicular((side * arm.bend[0], arm.bend[1], arm.bend[2]), upper)
    elbow_rad = math.radians(arm.elbow_deg)
    forearm = _add(_add((0.0, 0.0, 0.0), upper, math.cos(elbow_rad)), bend, math.sin(elbow_rad))
    elbow = _add(shoulder, upper, UPPER_ARM)
    wrist = _add(elbow, forearm, FOREARM)
    return elbow, wrist, forearm


def skeleton(pose):
    """All 33 canonical joints (pose-v1 names) in body metres."""
    joints = {}
    pelvis = pose.pelvis
    lean = math.radians(pose.lean_deg)
    up = (math.sin(lean), math.cos(lean), 0.0)
    across = (math.cos(lean), -math.sin(lean), 0.0)
    neck = _add(pelvis, up, TORSO)
    nose = _add(_add(neck, up, NECK_TO_NOSE), (0.0, 0.0, 0.09))
    joints["nose"] = nose
    for side, name in ((1, "left"), (-1, "right")):
        hip = _add(pelvis, across, side * HIP_HALF)
        shoulder = _add(neck, across, side * SHOULDER_HALF)
        foot = pose.left_foot if side == 1 else pose.right_foot
        knee, ankle = _leg(hip, foot, side)
        elbow, wrist, forearm = _arm(shoulder, pose.left_arm if side == 1 else pose.right_arm, side)
        joints[f"{name}Hip"] = hip
        joints[f"{name}Shoulder"] = shoulder
        joints[f"{name}Knee"] = knee
        joints[f"{name}Ankle"] = ankle
        joints[f"{name}Heel"] = _add(ankle, (0.0, -0.06, -0.05))
        joints[f"{name}FootIndex"] = _add(ankle, (side * 0.03, -0.07, 0.16))
        joints[f"{name}Elbow"] = elbow
        joints[f"{name}Wrist"] = wrist
        joints[f"{name}Index"] = _add(wrist, forearm, 0.08)
        joints[f"{name}Pinky"] = _add(_add(wrist, forearm, 0.07), (side * 0.015, 0.0, 0.0))
        joints[f"{name}Thumb"] = _add(_add(wrist, forearm, 0.05), (-side * 0.02, 0.0, 0.01))
        joints[f"{name}EyeInner"] = _add(nose, (side * 0.015, 0.035, -0.02))
        joints[f"{name}Eye"] = _add(nose, (side * 0.032, 0.037, -0.025))
        joints[f"{name}EyeOuter"] = _add(nose, (side * 0.05, 0.035, -0.03))
        joints[f"{name}Ear"] = _add(nose, (side * 0.075, 0.015, -0.09))
        joints[f"{name}Mouth"] = _add(nose, (side * 0.022, -0.045, -0.005))
    return joints


@dataclass(frozen=True)
class Camera:
    """Orthographic frontal view: canvas pixels per metre, floor near the bottom."""

    width: int = 960
    height: int = 960
    pixels_per_metre: float = 380.0
    floor: float = 0.93  # fraction of the height

    def project(self, point):
        x = self.width / 2 + point[0] * self.pixels_per_metre
        y = self.height * self.floor - point[1] * self.pixels_per_metre
        return x, y

    def landmarks(self, pose):
        """pose-v1 landmarks: normalized image coordinates, full confidence."""
        result = []
        for joint, point in skeleton(pose).items():
            x, y = self.project(point)
            result.append(
                {"joint": joint, "x": x / self.width, "y": y / self.height, "confidence": 1.0}
            )
        return result
