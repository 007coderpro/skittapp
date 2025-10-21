/// Viritysvaihtoehdot (esim. standardiviritys, drop D, jne.)
class TuningPreset {
  final String name;
  final List<String> notes;
  final String description;

  const TuningPreset({
    required this.name,
    required this.notes,
    required this.description,
  });
}

/// Valmiit viritysvaihtoehdot
class TuningPresets {
  static const standard = TuningPreset(
    name: 'Standard',
    notes: ['E2', 'A2', 'D3', 'G3', 'B3', 'E4'],
    description: 'Standardiviritys (E-A-D-G-B-E)',
  );

  static const dropD = TuningPreset(
    name: 'Drop D',
    notes: ['D2', 'A2', 'D3', 'G3', 'B3', 'E4'],
    description: 'Drop D -viritys (D-A-D-G-B-E)',
  );

  static const halfStepDown = TuningPreset(
    name: 'Half Step Down',
    notes: ['Eb2', 'Ab2', 'Db3', 'Gb3', 'Bb3', 'Eb4'],
    description: 'Puolisävel alemmas',
  );

  static const List<TuningPreset> all = [
    standard,
    dropD,
    halfStepDown,
  ];
}
