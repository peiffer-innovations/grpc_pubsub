class SubscriptionField {
  const SubscriptionField._(this.value);

  static const SubscriptionField ack_deadline_seconds = SubscriptionField._(
    'ack_deadline_seconds',
  );
  static const SubscriptionField dead_letter_policy = SubscriptionField._(
    'dead_letter_policy',
  );
  static const SubscriptionField enable_message_ordering = SubscriptionField._(
    'enable_message_ordering',
  );
  static const SubscriptionField expiration_policy = SubscriptionField._(
    'expiration_policy',
  );
  static const SubscriptionField filter = SubscriptionField._('filter');
  static const SubscriptionField labels = SubscriptionField._('labels');
  static const SubscriptionField message_retention_duration =
      SubscriptionField._('message_retention_duration');
  static const SubscriptionField name = SubscriptionField._('name');
  static const SubscriptionField push_config = SubscriptionField._(
    'push_config',
  );
  static const SubscriptionField retain_acked_messages = SubscriptionField._(
    'retain_acked_messages',
  );
  static const SubscriptionField retry_policy = SubscriptionField._(
    'retry_policy',
  );
  static const SubscriptionField topic = SubscriptionField._('topic');
  static const SubscriptionField topic_message_retention_duration =
      SubscriptionField._(
    'topic_message_retention_duration',
  );

  static const _all = [
    ack_deadline_seconds,
    dead_letter_policy,
    enable_message_ordering,
    expiration_policy,
    expiration_policy,
    filter,
    labels,
    message_retention_duration,
    name,
    push_config,
    retain_acked_messages,
    retry_policy,
    topic,
    topic_message_retention_duration,
  ];

  final String value;

  static SubscriptionField lookup(String name) =>
      _all.firstWhere((e) => e.value == name);

  static List<String> toStrings(Iterable<SubscriptionField> fields) =>
      fields.map((e) => e.value).toList();
}
