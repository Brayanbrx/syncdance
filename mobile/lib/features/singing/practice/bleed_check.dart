/// Whether the microphone hears the guide instead of the student.
///
/// Before singing together, the guide plays the first note while the student
/// stays quiet. The guide is a clean tone exactly on the note: if the
/// microphone keeps hearing that pitch, in that same octave, it would take
/// the guide for the student and score a silence as perfect.
///
/// [pitches] are the samples from the start of that note until a moment after
/// it stopped (Bluetooth arrives late); null where there was no voice.
/// Provisional: a quarter of them on the note, within 60 cents.
bool hearsGuide(Iterable<double?> pitches, double midi) {
  var total = 0, onNote = 0;
  for (final pitch in pitches) {
    total++;
    if (pitch != null && (pitch - midi).abs() <= 0.6) onNote++;
  }
  return total > 0 && onNote >= 0.25 * total;
}
