enum EqualizerPreset {
  flat('Flat', 'No EQ shaping'),
  fullSound('Full sound', 'Gentle bass and treble lift'),
  bassBoost('Bass boost', 'Stronger low end'),
  clarity('Clarity', 'Brighter highs');

  const EqualizerPreset(this.label, this.description);

  final String label;
  final String description;

  static EqualizerPreset fromStorage(String? raw) {
    if (raw == null || raw.isEmpty) return EqualizerPreset.fullSound;
    for (final preset in EqualizerPreset.values) {
      if (preset.name == raw) return preset;
    }
    return EqualizerPreset.fullSound;
  }
}

/// Device EQ band count varies; shape gains along bass → treble.
List<double> equalizerGainsForPreset(EqualizerPreset preset, int bandCount) {
  if (bandCount <= 0) return const [];
  if (preset == EqualizerPreset.flat) {
    return List<double>.filled(bandCount, 0);
  }

  return List<double>.generate(bandCount, (index) {
    final t = bandCount <= 1 ? 0.0 : index / (bandCount - 1);
    return switch (preset) {
      EqualizerPreset.flat => 0.0,
      EqualizerPreset.bassBoost => (1 - t) * 4.5 + 0.5,
      EqualizerPreset.clarity => t * 3.5 + 0.5,
      EqualizerPreset.fullSound =>
        (t < 0.33 ? 3.0 : 0.0) + (t > 0.66 ? 2.0 : 0.0),
    };
  });
}
