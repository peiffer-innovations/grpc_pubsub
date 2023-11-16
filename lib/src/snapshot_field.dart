// ignore_for_file: constant_identifier_names

class SnapshotField {
  const SnapshotField._(this.value);

  static const SnapshotField expire_time = SnapshotField._('expire_time');
  static const SnapshotField labels = SnapshotField._('labels');
  static const SnapshotField name = SnapshotField._('name');
  static const SnapshotField topic = SnapshotField._('topic');

  static const _all = [
    expire_time,
    labels,
    name,
    topic,
  ];

  final String value;

  static SnapshotField lookup(String name) =>
      _all.firstWhere((e) => e.value == name);

  static List<String> toStrings(Iterable<SnapshotField> fields) =>
      fields.map((e) => e.value).toList();
}
