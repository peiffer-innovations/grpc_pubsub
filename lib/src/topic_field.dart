class TopicField {
  const TopicField._(this.value);

  static const TopicField name = TopicField._('name');
  static const TopicField labels = TopicField._('labels');
  static const TopicField message_storage_policy = TopicField._(
    'message_storage_policy',
  );
  static const TopicField kms_key_name = TopicField._('kms_key_name');
  static const TopicField schema_settings = TopicField._('schema_settings');
  static const TopicField satisfies_pzs = TopicField._('satisfies_pzs');
  static const TopicField message_retention_duration = TopicField._(
    'message_retention_duration',
  );

  static const _all = [
    name,
    labels,
    message_storage_policy,
    kms_key_name,
    schema_settings,
    satisfies_pzs,
  ];

  final String value;

  static TopicField lookup(String name) =>
      _all.firstWhere((e) => e.value == name);

  static List<String> toStrings(Iterable<TopicField> fields) =>
      fields.map((e) => e.value).toList();
}
