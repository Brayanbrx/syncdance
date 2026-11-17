"""Singing analysis (`ai_engine.voice`).

The first part builds pitch tracks by hand and needs only numpy. The second
runs pyin and FFmpeg on synthetic voices and is skipped where they are not
installed. The cases include the ones the old singing-service got wrong.
"""

import gzip
import json
import math
import wave

import pytest

np = pytest.importorskip("numpy")

from ai_engine.voice import VoiceError  # noqa: E402
from ai_engine.voice.evaluate import compare, evaluate_solo  # noqa: E402
from ai_engine.voice.notes import (  # noqa: E402
    Note,
    note_name,
    parse_note,
    segment_notes,
    track_from_notes,
    tuning_offset,
)
from ai_engine.voice.pitch import HOP_MS, PitchTrack  # noqa: E402
from ai_engine.voice.reference import decode, exercise_reference, voice_quality  # noqa: E402

SCALE = [60, 62, 64, 65, 67, 69, 71, 72]  # C4 .. C5
NOTE_MS = 512  # 16 frames


def melody(pitches, *, start_ms=0, note_ms=NOTE_MS):
    return [
        Note(start_ms + i * note_ms, start_ms + (i + 1) * note_ms, float(p))
        for i, p in enumerate(pitches)
    ]


def sung(pitches, **kwargs):
    return track_from_notes(melody(pitches, **kwargs))


def reference():
    notes = melody(SCALE)
    return track_from_notes(notes), notes


def with_level(track, level=0.2):
    rms = np.where(track.voiced, level, 0.0)
    return PitchTrack(midi=track.midi, confidence=track.confidence, rms=rms, hop_ms=track.hop_ms)


# --- notes ---------------------------------------------------------------


def test_note_names_go_both_ways():
    assert note_name(60) == "C4"
    assert note_name(69.49) == "A4"
    assert note_name(69.51) == "A#4"
    assert note_name(54.0) == "F#3"
    assert parse_note("A4") == 69
    assert parse_note("Bb3") == 58
    assert parse_note(" c#5 ") == 73
    for bad in ("H4", "A", "A#", "C10", ""):
        with pytest.raises(ValueError):
            parse_note(bad)


def test_the_tuning_offset_is_a_circular_mean():
    assert tuning_offset([60.3, 62.3, 64.3]) == pytest.approx(0.3)
    assert tuning_offset([60.8, 63.8]) == pytest.approx(-0.2)
    assert tuning_offset([np.nan]) == 0.0
    # Half sharp, half flat by 45 cents: both sit near the half semitone.
    assert abs(tuning_offset([60.45, 61.55])) == pytest.approx(0.5)


def voice_frames(pitches, *, frames=16, vibrato=0.0, rate=5.5, flat=0.0, slide=2):
    """Frame values of a sung line: vibrato, global flatness, slides between notes."""
    parts = []
    for i, p in enumerate(pitches):
        t = np.arange(frames) * HOP_MS / 1000 + i * 0.37
        note = p - flat + vibrato * np.sin(2 * np.pi * rate * t)
        if i and slide:
            note[:slide] = np.linspace(pitches[i - 1], p, slide + 2)[1:-1] - flat
        parts.append(note)
    return np.concatenate(parts)


@pytest.mark.parametrize("vibrato", [0.0, 0.4, 0.6])
@pytest.mark.parametrize("rate", [4.5, 5.5, 7.0])
def test_a_real_looking_voice_still_gives_one_note_per_note(vibrato, rate):
    """Vibrato up to ±60 cents, 20 cents flat, slides and a consonant gap."""
    midi = voice_frames(SCALE, vibrato=vibrato, rate=rate, flat=0.2)
    midi[40:42] = np.nan  # a consonant inside E4
    track = PitchTrack(midi=midi, confidence=np.isfinite(midi).astype(float))

    found = segment_notes(track)

    assert [note.name for note in found] == ["C4", "D4", "E4", "F4", "G4", "A4", "B4", "C5"]
    for note, p in zip(found, SCALE, strict=True):
        assert note.midi == pytest.approx(p - 0.2, abs=0.15)
    assert all(a.end_ms <= b.start_ms for a, b in zip(found, found[1:], strict=False))


def test_fast_notes_and_leaps_are_kept_and_slides_add_none():
    fast = voice_frames(SCALE, frames=4, slide=1)  # 128 ms each
    track = PitchTrack(midi=fast, confidence=np.ones(fast.size))
    assert [note.name for note in segment_notes(track)] == [note_name(p) for p in SCALE]

    leaps = [60, 67, 60, 72, 65, 64]
    line = voice_frames(leaps, frames=12, vibrato=0.3, slide=3)
    track = PitchTrack(midi=line, confidence=np.ones(line.size))
    assert [note.name for note in segment_notes(track)] == [note_name(p) for p in leaps]


def test_a_one_frame_octave_jump_does_not_split_a_note():
    midi = np.full(30, 69.0)
    midi[12] = 81.0  # pyin doubling the pitch for one frame
    found = segment_notes(PitchTrack(midi=midi, confidence=np.ones(30)))
    assert [(note.start_ms, note.end_ms, note.name) for note in found] == [(0, 960, "A4")]


def test_silence_has_no_notes():
    empty = PitchTrack(midi=np.full(50, np.nan), confidence=np.zeros(50))
    assert segment_notes(empty) == []


def test_bad_notes_and_tracks_are_refused():
    for args in ((100, 100, 60.0), (-1, 10, 60.0), (0, 10, float("nan")), (0, 10, 200.0)):
        with pytest.raises(ValueError):
            Note(*args)
    with pytest.raises(ValueError):
        PitchTrack(midi=np.zeros(3), confidence=np.zeros(2))


# --- against a reference ------------------------------------------------------


def test_the_same_melody_scores_full_marks():
    track, notes = reference()
    result = compare(with_level(track), track, notes)
    assert result.scores.to_dict() == {
        "overall": 100,
        "tuning": 100,
        "timing": 100,
        "stability": 100,
        "volume": 100,
        "coverage": 100,
    }
    assert result.offset_ms == 0
    assert result.findings() == []


def test_a_wrong_note_cannot_hide_behind_its_neighbors():
    """F4 sung as F#4: the old time warp reported 100 % tuning."""
    track, notes = reference()
    wrong = [66 if p == 65 else p for p in SCALE]
    result = compare(sung(wrong), track, notes)
    assert result.scores.tuning == 88  # 7 of 8 notes
    [finding] = result.findings()
    assert finding == {
        "code": "OUT_OF_TUNE",
        "start_ms": 3 * NOTE_MS,
        "expected": "F4",
        "sung": "F#4",
        "cents": 100.0,
    }


def test_singing_an_octave_lower_is_not_an_error():
    track, notes = reference()
    result = compare(sung([p - 12 for p in SCALE]), track, notes)
    assert result.octave_shift == -1
    assert result.scores.tuning == 100
    assert result.findings() == [{"code": "OCTAVE_SHIFT", "octaves": -1}]
    # Unless the octave is required.
    strict = compare(sung([p - 12 for p in SCALE]), track, notes, allow_octave=False)
    assert strict.octave_shift == 0
    assert strict.scores.tuning == 0


def test_one_note_held_over_a_melody_scores_low_and_keeps_its_octave():
    track, notes = reference()
    result = compare(with_level(sung([60] * len(SCALE))), track, notes)
    assert result.octave_shift == 0
    assert result.scores.tuning <= 13
    # Steady and on time, yet wrong: nothing adds to the tuning.
    assert result.scores.overall <= result.scores.tuning


def test_a_transposition_counts_only_when_chosen():
    track, notes = reference()
    higher = sung([p + 2 for p in SCALE])
    assert compare(higher, track, notes, transpose_semitones=2).scores.tuning == 100
    guessed = compare(higher, track, notes)
    assert guessed.scores.tuning == 0
    assert guessed.notes[0].cents == pytest.approx(200)


def test_a_late_start_keeps_the_notes_and_loses_the_timing():
    track, notes = reference()
    result = compare(sung(SCALE, start_ms=416), track, notes)
    assert result.scores.tuning == 100
    assert result.offset_ms == 416
    assert result.scores.timing == 0
    assert result.scores.overall == 77  # 100, less 40 % x (1 - 3/7 of the rest)
    assert result.timing_bias_ms == 416
    assert {"code": "LATE", "ms": 416} in result.findings()
    # Within the tolerance, a small delay is still on time.
    assert compare(sung(SCALE, start_ms=96), track, notes).scores.timing == 100


def test_notes_not_sung_lower_the_coverage_never_the_tuning():
    track, notes = reference()
    half = track_from_notes(melody(SCALE)[:4], duration_ms=track.duration_ms)
    result = compare(half, track, notes)
    assert result.scores.coverage == 50
    assert result.scores.tuning == 100
    assert result.scores.overall == 50
    assert [note.sung_midi for note in result.notes[4:]] == [None] * 4
    assert {"code": "MISSED_NOTES", "count": 4} in result.findings()


def test_without_any_voice_there_is_no_score_but_the_coverage():
    track, notes = reference()
    silent = PitchTrack(midi=np.full(len(track), np.nan), confidence=np.zeros(len(track)))
    scores = compare(silent, track, notes).scores
    assert scores.to_dict() == {
        "overall": None,
        "tuning": None,
        "timing": None,
        "stability": None,
        "volume": None,
        "coverage": 0,
    }


def test_a_repeated_note_is_not_timed():
    notes = melody([60, 60, 64])
    track = track_from_notes(notes)
    result = compare(track, track, notes)
    assert [note.onset_error_ms for note in result.notes] == [0, None, 0]


def test_a_slow_wobble_and_an_uneven_level_lower_stability_and_volume():
    notes = melody([60, 64, 67, 72], note_ms=1024)
    track = track_from_notes(notes)
    frames = np.arange(len(track))
    # ±30 cents at 2 Hz: too slow to be vibrato, but centered on the note.
    wobble = track.midi + 0.3 * np.sin(2 * np.pi * 2 * frames * HOP_MS / 1000)
    level = 0.2 * (1 + 0.5 * np.sin(frames))
    shaky = PitchTrack(midi=wobble, confidence=track.confidence, rms=level)

    scores = compare(shaky, track, notes).scores

    assert scores.tuning == 100
    assert scores.stability < 80
    assert scores.volume < 80
    steady = compare(with_level(track), track, notes).scores
    assert (steady.stability, steady.volume) == (100, 100)


def test_tracks_must_share_the_frame_rate():
    track, notes = reference()
    other = PitchTrack(midi=track.midi, confidence=track.confidence, hop_ms=10)
    with pytest.raises(ValueError):
        compare(other, track, notes)


# --- a voice alone --------------------------------------------------------------


def test_a_scale_sung_alone_in_tune_scores_high_even_if_flat_overall():
    """The old absolute mode gave a perfect scale 24/100."""
    result = evaluate_solo(sung([p - 0.3 for p in SCALE]))
    assert result.scores.tuning == 100
    assert result.tuning_offset_cents == -30
    assert [note.expected.name for note in result.notes] == [
        "C4",
        "D4",
        "E4",
        "F4",
        "G4",
        "A4",
        "B4",
        "C5",
    ]


def test_a_note_between_semitones_is_out_of_tune_alone():
    off = [p + 0.4 if p == 67 else p for p in SCALE]
    result = evaluate_solo(sung(off))
    assert result.scores.tuning == 88
    [finding] = result.findings()
    assert finding["code"] == "OUT_OF_TUNE"
    # 40 cents, less the little the global tuning moved toward it.
    assert 35 < finding["cents"] <= 40


def test_silence_alone_has_no_score():
    result = evaluate_solo(PitchTrack(midi=np.full(30, np.nan), confidence=np.zeros(30)))
    assert result.notes == ()
    assert result.scores.overall is None
    assert result.tuning_offset_cents is None


# --- the stored reference -------------------------------------------------------


def test_an_exercise_reference_is_deterministic_and_reads_back():
    notes = melody(SCALE)
    first = exercise_reference(notes)
    second = exercise_reference(list(reversed(notes)))
    assert first.payload == second.payload
    assert first.sha256 == second.sha256
    assert first.metadata["schema_version"] == "pitch-reference-v1"
    assert first.metadata["notes"][3] == {
        "start_ms": 3 * NOTE_MS,
        "end_ms": 4 * NOTE_MS,
        "midi": 65.0,
        "name": "F4",
    }
    again = decode(first.payload)
    assert list(again.notes) == notes
    assert np.array_equal(again.track.midi, first.track.midi, equal_nan=True)
    text = gzip.decompress(first.payload)
    assert b"NaN" not in text
    assert len(json.loads(text)["frames"]["midi"]) == 8 * NOTE_MS // HOP_MS


def _tampered(edit):
    artifact = json.loads(gzip.decompress(exercise_reference(melody(SCALE)).payload))
    edit(artifact)
    return gzip.compress(json.dumps(artifact).encode())


@pytest.mark.parametrize(
    "edit",
    [
        lambda a: a.update(schema_version="pitch-reference-v0"),
        lambda a: a.update(hop_ms=0),
        lambda a: a.update(duration_ms=a["duration_ms"] + 32),
        lambda a: a["frames"]["midi"].__setitem__(0, 500),
        lambda a: a["frames"]["confidence"].__setitem__(0, 2),
        lambda a: a["notes"][1].update(start_ms=0),
        lambda a: a.update(source_sha256=""),
        lambda a: a.pop("frames"),
    ],
)
def test_a_damaged_reference_is_refused(edit):
    with pytest.raises(VoiceError):
        decode(_tampered(edit))


def test_garbage_and_overlapping_exercises_are_refused():
    for payload in (b"", b"not gzip", gzip.compress(b"[1, 2]"), "text"):
        with pytest.raises(VoiceError):
            decode(payload)
    with pytest.raises(VoiceError):
        exercise_reference([Note(0, 500, 60.0), Note(400, 900, 62.0)])
    with pytest.raises(VoiceError):
        exercise_reference([])


# --- real signal: pyin and FFmpeg ------------------------------------------------

SR = 16000


def _tone(freq, seconds, *, vibrato=0.004):
    t = np.arange(int(seconds * SR)) / SR
    phase = 2 * np.pi * np.cumsum(freq * (1 + vibrato * np.sin(2 * np.pi * 5.5 * t))) / SR
    wave_ = sum(a * np.sin(k * phase) for k, a in ((1, 1.0), (2, 0.5), (3, 0.25), (4, 0.12)))
    fade = np.minimum(1, np.minimum(t, t[::-1]) / 0.02)
    return (0.25 * wave_ * fade).astype(np.float32)


def _voice(pitches, *, delay=0.0):
    hz = [440.0 * 2 ** ((p - 69) / 12) for p in pitches]
    parts = [np.zeros(int(delay * SR), dtype=np.float32)] + [_tone(f, 0.5) for f in hz]
    return np.concatenate(parts)


@pytest.fixture(scope="module")
def pyin():
    pytest.importorskip("librosa")
    from ai_engine.voice.pitch import track_from_samples

    return track_from_samples


def test_pyin_hears_the_scale_and_the_wrong_note(pyin):
    teacher = pyin(_voice(SCALE))
    notes = segment_notes(teacher)
    assert [note.name for note in notes] == ["C4", "D4", "E4", "F4", "G4", "A4", "B4", "C5"]

    wrong = compare(pyin(_voice([66 if p == 65 else p for p in SCALE])), teacher, notes)
    assert 85 <= wrong.scores.tuning <= 90  # 7 of 8 notes, weighted by length
    assert [f["expected"] for f in wrong.findings() if f["code"] == "OUT_OF_TUNE"] == ["F4"]

    lower = compare(pyin(_voice([p - 12 for p in SCALE])), teacher, notes)
    assert (lower.octave_shift, lower.scores.tuning) == (-1, 100)

    late = compare(pyin(_voice(SCALE, delay=0.4)), teacher, notes)
    assert late.scores.tuning == 100
    assert 350 <= late.timing_bias_ms <= 450

    alone = evaluate_solo(pyin(_voice(SCALE)))
    assert alone.scores.tuning == 100
    assert alone.scores.overall >= 90


def test_music_behind_the_voice_is_flagged(pyin):
    voice = _voice(SCALE)
    assert voice_quality(pyin(voice))["warnings"] == []
    chords = sum(
        _tone(440.0 * 2 ** ((p - 69) / 12), len(voice) / SR, vibrato=0) for p in (48, 52, 55)
    )
    assert voice_quality(pyin(voice + chords))["warnings"] == ["NOT_VOICE_ONLY"]


def _wav(path, samples):
    pcm = (np.clip(samples, -1, 1) * 32767).astype("<i2")
    with wave.open(str(path), "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(SR)
        out.writeframes(pcm.tobytes())
    return path


@pytest.fixture
def ffmpeg():
    pytest.importorskip("imageio_ffmpeg")


def test_any_file_decodes_to_mono_16k_and_playlists_are_refused(ffmpeg, tmp_path):
    from ai_engine.voice.audio import decode as decode_audio

    samples = decode_audio(_wav(tmp_path / "voz.wav", _voice([69, 71])))
    assert samples.dtype == np.float32
    assert math.isclose(samples.size, SR, rel_tol=0.01)

    with pytest.raises(VoiceError):
        decode_audio(_wav(tmp_path / "larga.wav", _voice([69] * 6)), max_seconds=2)

    trap = tmp_path / "trampa.m4a"
    trap.write_text(
        "#EXTM3U\n#EXT-X-TARGETDURATION:5\n#EXTINF:5.0,\nhttp://127.0.0.1:9/x.wav\n#EXT-X-ENDLIST\n"
    )
    with pytest.raises(VoiceError):
        decode_audio(trap)


def test_the_reference_of_a_voice_file_is_deterministic(ffmpeg, pyin, tmp_path):
    from ai_engine.voice.reference import build_pitch_reference

    path = _wav(tmp_path / "profe.wav", _voice(SCALE))
    first = build_pitch_reference(path)
    second = build_pitch_reference(path)
    assert first.payload == second.payload
    assert [note.name for note in first.notes][0] == "C4"
    assert len(first.notes) == 8
    assert first.metadata["engine"] == "librosa-pyin"
    assert first.metadata["quality"]["warnings"] == []

    silent = _wav(tmp_path / "silencio.wav", np.zeros(SR * 2, dtype=np.float32))
    with pytest.raises(VoiceError):
        build_pitch_reference(silent)
