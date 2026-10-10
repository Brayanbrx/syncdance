"""Coach video and rhythm track for generated choreographies (worker only).

numpy, OpenCV and FFmpeg are imported lazily: CI and Django never need them.
All content is synthesized here, so the result carries no third-party license.
"""

import math
import os
import unicodedata
import wave

from .body import Camera, skeleton

AUDIO_RATE = 44_100
COACH = (255, 196, 61)  # one colour: the learner mirrors the coach, sides stay theirs
OUTLINE = (110, 60, 10)
TEXT = (255, 255, 255)
SHADOW_TEXT = (30, 20, 50)
ACCENT = (255, 120, 180)


def synth_audio(timeline, path, rate=AUDIO_RATE):
    """Kick on every beat, claps on 2/4/6/8, off-beat hats, bass and chords;
    wood-block clicks during the lead-in. Deterministic (seeded noise)."""
    import numpy as np

    total = int(round(timeline.duration_s * rate))
    out = np.zeros(total, dtype=np.float64)
    beat_s = timeline.seconds_per_beat

    def place(signal, at, gain):
        start = int(at * rate)
        if start >= total:
            return
        end = min(total, start + len(signal))
        out[start:end] += gain * signal[: end - start]

    def envelope(seconds, decay):
        t = np.arange(int(seconds * rate)) / rate
        return t, np.exp(-t * decay)

    t, decay = envelope(0.35, 11)
    kick = np.sin(2 * np.pi * (50 * t + 70 * (1 - np.exp(-30 * t)) / 30)) * decay
    rng = np.random.default_rng(7)
    _, decay = envelope(0.18, 24)
    clap = np.diff(rng.standard_normal(len(decay)) * decay, prepend=0.0)
    _, decay = envelope(0.05, 90)
    hat = np.diff(rng.standard_normal(len(decay)) * decay, prepend=0.0)
    t, decay = envelope(0.12, 40)
    wood = np.sin(2 * np.pi * 1250 * t) * decay
    roots = (65.41, 49.00, 55.00, 43.65)  # C2 G1 A1 F1
    chords = (
        (261.63, 329.63, 392.00),
        (196.00, 246.94, 293.66),
        (220.00, 261.63, 329.63),
        (174.61, 220.00, 261.63),
    )
    t_beat, decay_beat = envelope(beat_s, 3.5)
    t_bar = np.arange(int(4 * beat_s * rate)) / rate
    swell = np.minimum(1.0, t_bar / 0.08) * np.exp(-t_bar * 0.6)

    danced = 0
    for beat in range(timeline.total_beats):
        at = beat * beat_s
        if not timeline.evaluated_at(at + 1e-6):
            place(wood, at, 0.55)
            continue
        bar = (danced // 4) % 4
        place(kick, at, 0.9)
        if danced % 2 == 1:
            place(clap, at, 0.35)
        place(hat, at + beat_s / 2, 0.18)
        root = roots[bar]
        bass = np.sin(2 * np.pi * root * t_beat) + 0.4 * np.sin(4 * np.pi * root * t_beat)
        place(bass * decay_beat, at, 0.32)
        if danced % 4 == 0:
            pad = sum(np.sin(2 * np.pi * f * t_bar) for f in chords[bar]) * swell
            place(pad, at, 0.06)
        danced += 1

    peak = float(np.max(np.abs(out))) or 1.0
    pcm = (out / peak * 0.89 * 32767).astype(np.int16)
    with wave.open(str(path), "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(rate)
        wav.writeframes(pcm.tobytes())


FONT_CANDIDATES = (
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",  # fonts-dejavu-core
    "C:/Windows/Fonts/arialbd.ttf",  # local previews on Windows
)


def font_path():
    candidates = [os.environ.get("SYNCDANCE_FONT"), *FONT_CANDIDATES]
    try:
        import matplotlib

        candidates.append(
            os.path.join(
                os.path.dirname(matplotlib.__file__),
                "mpl-data",
                "fonts",
                "ttf",
                "DejaVuSans-Bold.ttf",
            )
        )
    except ImportError:
        pass
    return next((path for path in candidates if path and os.path.isfile(path)), None)


def ascii_caption(text):
    """Hershey fonts only draw ASCII: drop accents and inverted marks."""
    plain = unicodedata.normalize("NFKD", text).encode("ascii", "ignore").decode()
    return plain.strip()


class Captions:
    """Spanish captions (accents, ¡) via Pillow and a TTF font; ASCII fallback."""

    def __init__(self, path=None):
        self.path = path if path is not None else font_path()
        self._fonts = {}
        self.items = []

    def add(self, text, center, size, color=TEXT):
        self.items.append((text, center, size, color))

    def _font(self, size):
        from PIL import ImageFont

        if size not in self._fonts:
            self._fonts[size] = ImageFont.truetype(self.path, size)
        return self._fonts[size]

    def render(self, cv2, np, frame):
        items, self.items = self.items, []
        if not items:
            return frame
        if not self.path:
            for text, center, size, color in items:
                _hershey(cv2, frame, ascii_caption(text), center, size, color)
            return frame
        from PIL import Image, ImageDraw

        image = Image.fromarray(frame)
        draw = ImageDraw.Draw(image)
        for text, center, size, color in items:
            draw.text(
                center,
                text,
                font=self._font(size),
                fill=color,
                anchor="mm",
                stroke_width=max(2, size // 12),
                stroke_fill=SHADOW_TEXT,
            )
        return np.asarray(image).copy()


def _hershey(cv2, frame, text, center, size, color):
    font = cv2.FONT_HERSHEY_DUPLEX
    scale = size / 32
    thickness = max(1, size // 20)
    (w, h), _ = cv2.getTextSize(text, font, scale, thickness)
    origin = (int(center[0] - w / 2), int(center[1] + h / 2))
    cv2.putText(frame, text, origin, font, scale, SHADOW_TEXT, thickness + 6, cv2.LINE_AA)
    cv2.putText(frame, text, origin, font, scale, color, thickness, cv2.LINE_AA)


LIMBS = (
    ("leftHip", "leftKnee", 0.090),
    ("leftKnee", "leftAnkle", 0.075),
    ("leftAnkle", "leftFootIndex", 0.055),
    ("rightHip", "rightKnee", 0.090),
    ("rightKnee", "rightAnkle", 0.075),
    ("rightAnkle", "rightFootIndex", 0.055),
    ("leftShoulder", "leftElbow", 0.070),
    ("leftElbow", "leftWrist", 0.060),
    ("rightShoulder", "rightElbow", 0.070),
    ("rightElbow", "rightWrist", 0.060),
)


def draw_frame(cv2, np, background, timeline, seconds, camera, captions=None):
    captions = captions or Captions()
    frame = background.copy()
    pose = timeline.pose_at(seconds)
    joints = skeleton(pose)
    ppm = camera.pixels_per_metre

    def px(name):
        x, y = camera.project(joints[name])
        return int(round(x)), int(round(y))

    floor_y = int(camera.height * camera.floor)
    shadow = frame.copy()
    cv2.ellipse(
        shadow,
        (int(camera.width / 2 + pose.pelvis[0] * ppm), floor_y + 6),
        (int(0.42 * ppm), int(0.05 * ppm)),
        0,
        0,
        360,
        (10, 5, 20),
        -1,
        cv2.LINE_AA,
    )
    cv2.addWeighted(shadow, 0.55, frame, 0.45, 0, frame)

    torso = np.array(
        [px("leftShoulder"), px("rightShoulder"), px("rightHip"), px("leftHip")], np.int32
    )
    # Back to front: segments further from the camera first.
    segments = sorted(LIMBS, key=lambda limb: (joints[limb[0]][2] + joints[limb[1]][2]) / 2)
    behind = [s for s in segments if (joints[s[0]][2] + joints[s[1]][2]) / 2 < 0.02]
    front = [s for s in segments if s not in behind]

    def limb(a, b, width):
        thickness = max(2, int(width * ppm))
        cv2.line(frame, px(a), px(b), OUTLINE, thickness + 8, cv2.LINE_AA)
        cv2.line(frame, px(a), px(b), COACH, thickness, cv2.LINE_AA)

    for a, b, width in behind:
        limb(a, b, width)
    cv2.fillConvexPoly(frame, torso, OUTLINE, cv2.LINE_AA)
    inner = (torso - torso.mean(axis=0)) * 0.86 + torso.mean(axis=0)
    cv2.fillConvexPoly(frame, inner.astype(np.int32), COACH, cv2.LINE_AA)
    for a, b, width in front:
        limb(a, b, width)
    for wrist in ("leftWrist", "rightWrist"):
        cv2.circle(frame, px(wrist), int(0.045 * ppm), OUTLINE, -1, cv2.LINE_AA)
        cv2.circle(frame, px(wrist), int(0.035 * ppm), COACH, -1, cv2.LINE_AA)
    neck = px("leftShoulder")[0] / 2 + px("rightShoulder")[0] / 2
    head_x, head_y = px("nose")
    head = (int((head_x + neck) / 2), head_y - int(0.03 * ppm))
    cv2.circle(frame, head, int(0.125 * ppm), OUTLINE, -1, cv2.LINE_AA)
    cv2.circle(frame, head, int(0.11 * ppm), COACH, -1, cv2.LINE_AA)

    cue = timeline.cue_at(seconds)
    captions.add(cue.caption, (camera.width / 2, 52), 42)
    if not cue.evaluated:
        # Beside the coach, never over the body.
        captions.add(str(cue.count), (camera.width * 0.82, camera.height * 0.45), 170, ACCENT)
    else:
        beat = timeline.beat_at(seconds)
        here = timeline.pose_at(seconds).pelvis[0]
        ahead = timeline.pose_at((math.floor(beat) + 1) * timeline.seconds_per_beat).pelvis[0]
        if abs(ahead - here) > 0.05:
            direction = 1 if ahead > here else -1
            y = int(camera.height * 0.30)
            x0 = int(camera.width / 2 + direction * 230)
            cv2.arrowedLine(
                frame, (x0, y), (x0 + direction * 110, y), ACCENT, 14, cv2.LINE_AA, tipLength=0.45
            )
    dots_y = camera.height - 34
    for count in range(1, 9):
        x = int(camera.width / 2 + (count - 4.5) * 46)
        active = count == cue.count
        color = ACCENT if active else (90, 80, 120)
        cv2.circle(frame, (x, dots_y), 15 if active else 9, color, -1, cv2.LINE_AA)
    if cue.evaluated:
        captions.add(str(cue.count), (camera.width - 70, 60), 60, ACCENT)
    if cue.next_caption:
        captions.add(f"SIGUE: {cue.next_caption}", (camera.width / 2, 104), 28)
    return captions.render(cv2, np, frame)


def render_video(timeline, path, *, audio_path=None, camera=None, fps=30):
    """H.264 + AAC MP4 (yuv420p, faststart) playable on Android."""
    import cv2
    import imageio_ffmpeg
    import numpy as np

    camera = camera or Camera()
    top = np.array([46, 22, 84], np.float32)
    bottom = np.array([12, 18, 44], np.float32)
    ramp = np.linspace(0, 1, camera.height, dtype=np.float32)[:, None, None]
    background = (top * (1 - ramp) + bottom * ramp).repeat(camera.width, axis=1)
    background = np.ascontiguousarray(background.astype(np.uint8))
    writer = imageio_ffmpeg.write_frames(
        str(path),
        (camera.width, camera.height),
        fps=fps,
        codec="libx264",
        quality=None,
        macro_block_size=16,
        output_params=["-preset", "veryfast", "-crf", "23", "-movflags", "+faststart"],
        audio_path=str(audio_path) if audio_path else None,
        audio_codec="aac" if audio_path else None,
    )
    captions = Captions()
    writer.send(None)
    try:
        for index in range(round(timeline.duration_s * fps)):
            frame = draw_frame(cv2, np, background, timeline, index / fps, camera, captions)
            writer.send(np.ascontiguousarray(frame))
    finally:
        writer.close()
