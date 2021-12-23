import 'dart:async';

import 'package:grpc/grpc.dart';
import 'package:grpc/grpc_or_grpcweb.dart';
import 'package:grpc_googleapis/google/protobuf.dart' as pb;
import 'package:grpc_googleapis/google/pubsub_v1.dart';
import 'package:grpc_protobuf_convert/grpc_protobuf_convert.dart';
import 'package:grpc_pubsub/grpc_pubsub.dart';
import 'package:logging/logging.dart';
import 'package:protobuf/protobuf.dart' as pb1;

class PubsubClient {
  PubsubClient({
    Logger? logger,
    String host = 'pubsub.googleapis.com',
    int port = 443,
    List<String> scopes = const [
      'https://www.googleapis.com/auth/cloud-platform',
      SCOPE,
    ],
    required String serviceAccountJson,
  })  : _host = host,
        _logger = logger ?? Logger('PubSub'),
        _port = port,
        _scopes = List.from(scopes),
        _serviceAccountJson = serviceAccountJson;

  static const SCOPE = 'https://www.googleapis.com/auth/pubsub';

  final Logger _logger;
  final String _host;
  final int _port;
  final List<String> _scopes;
  final String _serviceAccountJson;
  final List<StreamSubscription> _subscriptions = [];

  late GrpcOrGrpcWebClientChannel _channel;
  bool _initialized = false;
  late String _projectId;
  late PublisherClient _publisherClient;
  late SubscriberClient _subscriberClient;

  PublisherClient get publisherClient => _publisherClient;
  SubscriberClient get subscriberClient => _subscriberClient;

  /// Initializes the client and prepares it for for use.  A client must be
  /// initialized before any of the other attributes or functions may be called.
  ///
  /// Once a client has been initialized, future calls to this will be an
  /// effective no-op until / unless this is disposed.
  Future<void> initialize() async {
    if (!_initialized) {
      _logger.info('[initialize]: start');

      await _reconnect(closePrevious: false);

      _initialized = true;
      _logger.info('[initialize]: complete');
    }
  }

  /// Disposes the client.  A disposed client cannot have other functions called
  /// unless it is re-initialized via the [initialize] function.
  Future<void> dispose() async {
    if (_initialized) {
      _logger.info('[dispose]: start');

      await _channel.shutdown();

      _subscriptions.forEach((sub) => sub.cancel());
      _subscriptions.clear();

      _initialized = false;

      _logger.info('[dispose]: complete');
    }
  }

  /// Acknowledges the messages associated with the [ackIds]. The Pub/Sub system
  /// can remove the relevant messages from the subscription.  Acknowledging a
  /// message whose ack deadline has expired may succeed, but such a message may
  /// be redelivered later. Acknowledging a message more than once will not
  /// result in an error.
  ///
  /// The [subscription] name can be just the simple name or it can be the fully
  /// quantified name in the format:
  /// `projects/{project}/subscriptions/{subscription}`.
  Future<void> acknowledge({
    required Iterable<String> ackIds,
    int retries = 5,
    required String subscription,
  }) async {
    assert(_initialized);
    assert(ackIds.isNotEmpty);
    _logger.fine('[acknowledge]: start -- [$subscription]');

    await _execute(
      executor: () async => await _subscriberClient.acknowledge(
        AcknowledgeRequest(
          ackIds: ackIds,
          subscription: subscription.startsWith('projects/')
              ? subscription
              : 'projects/$_projectId/subscriptions/$subscription',
        ),
      ),
      retries: retries,
    );
    _logger.fine('[acknowledge]: complete -- [$subscription]');
  }

  /// Creates a snapshot from the requested subscription. Snapshots are used in
  /// Seek operations, which allow you to manage message acknowledgments in
  /// bulk.  That is, you can set the acknowledgment state of messages in an
  /// existing subscription to the state captured by a snapshot.  If the
  /// snapshot already exists, returns ALREADY_EXISTS.  If the requested
  /// subscription doesn't exist, returns NOT_FOUND.  If the backlog in the
  /// subscription is too old -- and the resulting snapshot would expire in less
  /// than 1 hour -- then FAILED_PRECONDITION is returned.  See also the
  /// `Snapshot.expire_time` field. If the name is not provided in the request,
  /// the server will assign a random name for this snapshot on the same project
  /// as the subscription, conforming to the resource name format.  The
  /// generated name is populated in the returned Snapshot object. Note that for
  /// REST API requests, you must specify a name in the request.
  ///
  /// The [snapshot] name can be just the simple name or it can be the fully
  /// quantified name in the format: `projects/{project}/snapshots/{snap}`.
  ///
  /// The [subscription] name can be just the simple name or it can be the fully
  /// quantified name in the format:
  /// `projects/{project}/subscriptions/{subscription}`.
  Future<Snapshot> createSnapshot({
    required Map<String, String> labels,
    int retries = 5,
    required String snapshot,
    required String subscription,
  }) async {
    assert(_initialized);
    _logger.fine('[createSnapshot]: start -- [$subscription]');

    try {
      return await _execute(
        executor: () async {
          var result = await _subscriberClient.createSnapshot(
            CreateSnapshotRequest(
              labels: labels,
              name: snapshot.startsWith('projects/')
                  ? snapshot
                  : 'projects/$_projectId/snapshots/$snapshot',
              subscription: subscription.startsWith('projects/')
                  ? subscription
                  : 'projects/$_projectId/subscriptions/$subscription',
            ),
          );

          return result;
        },
        retries: retries,
      );
    } finally {
      _logger.fine('[createSnapshot]: complete -- [$subscription]');
    }
  }

  /// Creates a subscription to a given topic. See the resource name rules.  If
  /// the subscription already exists, returns `ALREADY_EXISTS`.  If the
  /// corresponding topic doesn't exist, returns `NOT_FOUND`.
  ///
  /// If the name is not provided in the request, the server will assign a
  /// random name for this subscription on the same project as the topic,
  /// conforming to the resource name format.  The generated name is populated
  /// in the returned [Subscription] object.  Note that for REST API requests,
  /// you must specify a name in the request.
  ///
  /// If provided, the [subscription] name can be just the simple name or it can
  /// be the fully quantified name in the format:
  /// `projects/{project}/subscriptions/{subscription}`.
  ///
  /// The [topic] can be just the simple name or it can be the fully quantified
  /// name in the format: `projects/{project}/topics/{topic}`.
  ///
  /// If push delivery is used with this subscription, the [pushConfig] is used
  /// to configure it.  An empty pushConfig signifies that the subscriber will
  /// pull and ack messages using API methods.
  ///
  /// For more information on the options, see the official documentation here:
  /// https://cloud.google.com/pubsub/docs/reference/rpc/google.pubsub.v1#google.pubsub.v1.Subscription
  Future<Subscription> createSubscription({
    int? ackDeadlineSeconds,
    DeadLetterPolicy? deadLetterPolicy,
    bool? enableMessageOrdering,
    ExpirationPolicy? expirationPolicy,
    String? filter,
    Map<String, String>? labels,
    Duration? messageRetentionDuration,
    PushConfig? pushConfig,
    bool? retainAckedMessages,
    int retries = 5,
    RetryPolicy? retryPolicy,
    String? subscription,
    required String topic,
    Duration? topicMessageRetentionDuration,
  }) async {
    assert(_initialized);
    _logger.fine('[createSubscription]: start -- [$subscription]');

    try {
      return await _execute(
        executor: () async {
          var result = await _subscriberClient.createSubscription(
            Subscription(
              ackDeadlineSeconds: ackDeadlineSeconds,
              deadLetterPolicy: deadLetterPolicy,
              enableMessageOrdering: enableMessageOrdering,
              expirationPolicy: expirationPolicy,
              filter: filter,
              labels: labels,
              messageRetentionDuration: messageRetentionDuration == null
                  ? null
                  : GrpcProtobufConvert.toDuration(messageRetentionDuration),
              name: subscription == null
                  ? null
                  : subscription.startsWith('projects/')
                      ? subscription
                      : 'projects/$_projectId/subscriptions/$subscription',
              pushConfig: pushConfig,
              retainAckedMessages: retainAckedMessages,
              retryPolicy: retryPolicy,
              topic: topic.startsWith('projects/')
                  ? topic
                  : 'projects/$_projectId/topics/$topic',
              topicMessageRetentionDuration:
                  topicMessageRetentionDuration == null
                      ? null
                      : GrpcProtobufConvert.toDuration(
                          topicMessageRetentionDuration),
            ),
          );

          return result;
        },
        retries: retries,
      );
    } finally {
      _logger.fine('[createSubscription]: complete -- [$subscription]');
    }
  }

  /// Creates a topic with the given [topic].  The [topic] can either be the
  /// simple name of the topic or it may be the fully quantified name in the
  /// `projects/{project}/topics/{topic}` format.
  ///
  /// If set, the [kmsKeyName] represents The resource name of the Cloud KMS
  /// CryptoKey to be used to protect access to messages published on this
  /// topic.  The expected format is
  /// `projects/*/locations/*/keyRings/*/cryptoKeys/*`.
  Future<Topic> createTopic({
    Map<String, String>? labels,
    MessageStoragePolicy? messageStoragePolicy,
    String? kmsKeyName,
    int retries = 5,
    SchemaSettings? schemaSettings,
    Duration? messageRetentionDuration,
    required String topic,
  }) async {
    assert(_initialized);
    _logger.fine('[createTopic]: start -- [$topic]');
    try {
      return await _execute(
        executor: () async {
          var request = Topic(
            name: topic.startsWith('projects/')
                ? topic
                : 'projects/$_projectId/topics/$topic',
            labels: labels,
            messageStoragePolicy: messageStoragePolicy,
            kmsKeyName: kmsKeyName,
            schemaSettings: schemaSettings,
            messageRetentionDuration: messageRetentionDuration == null
                ? null
                : GrpcProtobufConvert.toDuration(
                    messageRetentionDuration,
                  ),
          );

          var result = await _publisherClient.createTopic(request);

          return result;
        },
        retries: retries,
      );
    } finally {
      _logger.fine('[createTopic]: complete -- [$topic]');
    }
  }

  /// Removes an existing snapshot.  Snapshots are used in Seek operations,
  /// which allow you to manage message acknowledgments in bulk.  That is, you
  /// can set the acknowledgment state of messages in an existing subscription
  /// to the state captured by a snapshot.  When the snapshot is deleted, all
  /// messages retained in the snapshot are immediately dropped.  After a
  /// snapshot is deleted, a new one may be created with the same name, but the
  /// new one has no association with the old snapshot or its subscription,
  /// unless the same subscription is specified.
  ///
  /// The [snapshot] name can be just the simple name or it can be the fully
  /// quantified name in the format: `projects/{project}/snapshots/{snap}`.
  Future<void> deleteSnapshot({
    int retries = 5,
    required String snapshot,
  }) async {
    assert(_initialized);
    _logger.fine('[deleteSnapshot]: start -- [$snapshot]');

    try {
      await _execute(
        executor: () async => await _subscriberClient.deleteSnapshot(
          DeleteSnapshotRequest(
            snapshot: snapshot.startsWith('projects/')
                ? snapshot
                : 'projects/$_projectId/snapshots/$snapshot',
          ),
        ),
        retries: retries,
      );
    } finally {
      _logger.fine('[deleteSnapshot]: complete -- [$snapshot]');
    }
  }

  /// Deletes an existing subscription.  All messages retained in the
  /// subscription are immediately dropped.  Calls to `Pull` after deletion will
  /// return `NOT_FOUND`.  After a subscription is deleted, a new one may be
  /// created with the same name, but the new one has no association with the
  /// old subscription or its topic unless the same topic is specified.
  ///
  /// The [subscription] name can be just the simple name or it can be the fully
  /// quantified name in the format:
  /// `projects/{project}/subscriptions/{subscription}`.
  Future<void> deleteSubscription({
    int retries = 5,
    required String subscription,
  }) async {
    assert(_initialized);
    _logger.fine('[deleteSubscription]: start -- [$subscription]');

    try {
      await _execute(
        executor: () async => await _subscriberClient.deleteSubscription(
          DeleteSubscriptionRequest(
            subscription: subscription.startsWith('projects/')
                ? subscription
                : 'projects/$_projectId/subscriptions/$subscription',
          ),
        ),
        retries: retries,
      );
    } finally {
      _logger.fine('[deleteSubscription]: complete -- [$subscription]');
    }
  }

  /// Deletes the [topic].  The [topic] can either be the simple name of the
  /// topic or it may be the fully quantified name in the
  /// `projects/{project}/topics/{topic}` format.
  ///
  /// After a topic is deleted, a new topic may be created with the same name;
  /// this is an entirely new topic with none of the old configuration or
  /// subscriptions. Existing subscriptions to this topic are not deleted, but
  /// their topic field is set to `_deleted-topic_`.
  Future<void> deleteTopic({
    int retries = 5,
    required String topic,
  }) async {
    assert(_initialized);
    _logger.fine('[deleteTopic]: start -- [$topic]');
    try {
      await _execute(
        executor: () => _publisherClient.deleteTopic(
          DeleteTopicRequest(topic: topic),
        ),
        retries: retries,
      );
    } finally {
      _logger.fine('[deleteTopic]: complete -- [$topic]');
    }
  }

  /// Detaches a [subscription] from this topic. All messages retained in the
  /// subscription are dropped. Subsequent `Pull` and `StreamingPull` requests
  /// will return `FAILED_PRECONDITION`.  If the subscription is a push
  /// subscription, pushes to the endpoint will stop.
  ///
  /// The [subscription] can be the simple name or the the fully quantified
  /// format: `projects/{project}/subscriptions/{subscription}`
  Future<DetachSubscriptionResponse> detachSubscription({
    int retries = 5,
    required String subscription,
  }) async {
    assert(_initialized);
    _logger.fine('[detachSubscription]: start -- [$subscription]');
    try {
      return await _execute(
        executor: () async {
          var result = await _publisherClient
              .detachSubscription(DetachSubscriptionRequest(
            subscription: subscription.startsWith('projects/')
                ? subscription
                : 'projects/$_projectId/subscriptions/$subscription',
          ));

          return result;
        },
        retries: retries,
      );
    } finally {
      _logger.fine('[detachSubscription]: complete -- [$subscription]');
    }
  }

  /// Gets the configuration details of a snapshot.  Snapshots are used in
  /// [seek] operations, which allow you to manage message acknowledgments in
  /// bulk.  That is, you can set the acknowledgment state of messages in an
  /// existing subscription to the state captured by a snapshot.
  ///
  /// The [snapshot] name can be just the simple name or it can be the fully
  /// quantified name in the format: `projects/{project}/snapshots/{snap}`.
  Future<Snapshot> getSnapshot({
    int retries = 5,
    required String snapshot,
  }) async {
    assert(_initialized);
    _logger.fine('[getSnapshot]: start -- [$snapshot]');

    try {
      return await _execute(
        executor: () async {
          var result = await _subscriberClient.getSnapshot(
            GetSnapshotRequest(
              snapshot: snapshot.startsWith('projects/')
                  ? snapshot
                  : 'projects/$_projectId/snapshots/$snapshot',
            ),
          );

          return result;
        },
        retries: retries,
      );
    } finally {
      _logger.fine('[getSnapshot]: complete -- [$snapshot]');
    }
  }

  /// Gets the configuration details of a subscription.
  ///
  /// The [subscription] name can be just the simple name or it can be the fully
  /// quantified name in the format:
  /// `projects/{project}/subscriptions/{subscription}`.
  Future<Subscription> getSubscription({
    int retries = 5,
    required String subscription,
  }) async {
    assert(_initialized);
    _logger.fine('[getSubscription]: start -- [$subscription]');

    try {
      return await _execute(
        executor: () async {
          var result = await _subscriberClient.getSubscription(
            GetSubscriptionRequest(
              subscription: subscription.startsWith('projects/')
                  ? subscription
                  : 'projects/$_projectId/subscriptions/$subscription',
            ),
          );

          return result;
        },
        retries: retries,
      );
    } finally {
      _logger.fine('[getSubscription]: complete -- [$subscription]');
    }
  }

  /// Gets the configuration of a [topic].  The name of the topic can be the
  /// simple name or it can be the fully quantified format:
  /// `projects/{project}/topics/{topic}`.
  Future<Topic> getTopic({
    int retries = 5,
    required String topic,
  }) async {
    assert(_initialized);
    _logger.fine('[getTopic]: start -- [$topic]');
    try {
      return await _execute(
        executor: () async {
          var result = await _publisherClient.getTopic(
            GetTopicRequest(
              topic: topic.startsWith('projects/')
                  ? topic
                  : 'projects/$_projectId/topics/$topic',
            ),
          );

          return result;
        },
        retries: retries,
      );
    } finally {
      _logger.fine('[getTopic]: complete -- [$topic]');
    }
  }

  /// Lists the existing snapshots.  Snapshots are used in
  /// [Seek]( https://cloud.google.com/pubsub/docs/replay-overview) operations,
  /// which allow you to manage message acknowledgments in bulk.  That is, you
  /// can set the acknowledgment state of messages in an existing subscription
  /// to the state captured by a snapshot.
  ///
  /// If set, the [project] can be either just the project id or it can be the
  /// fully quantified format: `projects/{project}`.  If not set, the project
  /// from the service account will be used.
  Future<ListSnapshotsResponse> listSnapshots({
    int? pageSize,
    String? pageToken,
    String? project,
    int retries = 5,
  }) async {
    assert(_initialized);
    var projectId = project ?? _projectId;
    _logger.fine('[listSnapshots]: start -- [$projectId]');

    try {
      return await _execute(
        executor: () async {
          var result = await _subscriberClient.listSnapshots(
            ListSnapshotsRequest(
              pageSize: pageSize,
              pageToken: pageToken,
              project: projectId.startsWith('projects/')
                  ? projectId
                  : 'projects/$projectId',
            ),
          );

          return result;
        },
        retries: retries,
      );
    } finally {
      _logger.fine('[listSnapshots]: complete -- [$projectId]');
    }
  }

  /// Lists matching subscriptions.
  ///
  /// If set, the [project] can be either just the project id or it can be the
  /// fully quantified format: `projects/{project}`.  If not set, the project
  /// from the service account will be used.
  Future<ListSubscriptionsResponse> listSubscriptions({
    int? pageSize,
    String? pageToken,
    String? project,
    int retries = 5,
  }) async {
    assert(_initialized);
    var projectId = project ?? _projectId;
    _logger.fine('[listSubscriptions]: start -- [$projectId]');

    try {
      return await _execute(
        executor: () async {
          var result = await _subscriberClient.listSubscriptions(
            ListSubscriptionsRequest(
              pageSize: pageSize,
              pageToken: pageToken,
              project: projectId.startsWith('projects/')
                  ? projectId
                  : 'projects/$projectId',
            ),
          );

          return result;
        },
        retries: retries,
      );
    } finally {
      _logger.fine('[listSubscriptions]: complete -- [$projectId]');
    }
  }

  /// Lists the names of the snapshots on this topic. Snapshots are used in Seek
  /// operations, which allow you to manage message acknowledgments in bulk.
  /// That is, you can set the acknowledgment state of messages in an existing
  /// subscription to the state captured by a snapshot.
  ///
  /// The [topic] can be just the simple name or it can be the fully quantified
  /// name in the format: `projects/{project}/topics/{topic}`.
  Future<ListTopicSnapshotsResponse> listTopicSnapshots({
    int? pageSize,
    String? pageToken,
    int retries = 5,
    required String topic,
  }) async {
    assert(_initialized);
    _logger.fine('[listTopicSnapshots]: start -- [$topic]');
    try {
      return await _execute(
        executor: () async {
          var result = await _publisherClient.listTopicSnapshots(
            ListTopicSnapshotsRequest(
              pageSize: pageSize,
              pageToken: pageToken,
              topic: topic.startsWith('projects/')
                  ? topic
                  : 'projects/$_projectId/topics/$topic',
            ),
          );

          return result;
        },
        retries: retries,
      );
    } finally {
      _logger.fine('[listTopicSnapshots]: complete -- [$topic]');
    }
  }

  /// Lists the names of the attached subscriptions on this topic.
  ///
  /// The [topic] can be just the simple name or it can be the fully quantified
  /// name in the format: `projects/{project}/topics/{topic}`.
  Future<ListTopicSubscriptionsResponse> listTopicSubscriptions({
    int? pageSize,
    String? pageToken,
    int retries = 5,
    required String topic,
  }) async {
    assert(_initialized);
    _logger.fine('[listTopicSubscriptions]: start -- [$topic]');
    try {
      return await _execute(
        executor: () async {
          var result = await _publisherClient.listTopicSubscriptions(
            ListTopicSubscriptionsRequest(
              pageSize: pageSize,
              pageToken: pageToken,
              topic: topic.startsWith('projects/')
                  ? topic
                  : 'projects/$_projectId/topics/$topic',
            ),
          );

          return result;
        },
        retries: retries,
      );
    } finally {
      _logger.fine('[listTopicSubscriptions]: complete -- [$topic]');
    }
  }

  /// Lists matching topics.  If set, the [project] can be either just the
  /// project id or it can be the fully quantified format: `projects/{project}`.
  ///
  /// If not set, the project from the service account will be used.
  Future<ListTopicsResponse> listTopics({
    int? pageSize,
    String? pageToken,
    String? project,
    int retries = 5,
  }) async {
    assert(_initialized);
    var projectId = project ?? _projectId;
    _logger.fine('[listTopics]: start -- [$projectId]');

    try {
      return await _execute(
        executor: () async {
          var result = await _publisherClient.listTopics(
            ListTopicsRequest(
              pageSize: pageSize,
              pageToken: pageToken,
              project: projectId.startsWith('projects/')
                  ? projectId
                  : 'projects/$projectId',
            ),
          );

          return result;
        },
        retries: retries,
      );
    } finally {
      _logger.fine('[listTopics]: complete -- [$projectId]');
    }
  }

  /// Modifies the ack deadline for a specific message.  This method is useful
  /// to indicate that more time is needed to process a message by the
  /// subscriber, or to make the message available for redelivery if the
  /// processing was interrupted.  Note that this does not modify the
  /// subscription-level [ackDeadlineSeconds] used for subsequent messages.
  ///
  /// The [subscription] name can be just the simple name or it can be the fully
  /// quantified name in the format:
  /// `projects/{project}/subscriptions/{subscription}`.
  Future<void> modifyAckDeadline({
    required int ackDeadlineSeconds,
    required Iterable<String> ackIds,
    int retries = 5,
    required String subscription,
  }) async {
    assert(_initialized);
    _logger.fine('[modifyAckDeadline]: start -- [$subscription]');

    try {
      await _execute<pb.Empty>(
        executor: () async {
          return await _subscriberClient.modifyAckDeadline(
            ModifyAckDeadlineRequest(
              ackDeadlineSeconds: ackDeadlineSeconds,
              ackIds: ackIds,
              subscription: subscription.startsWith('projects/')
                  ? subscription
                  : 'projects/$_projectId/subscriptions/$subscription',
            ),
          );
        },
        retries: retries,
      );
    } finally {
      _logger.fine('[modifyAckDeadline]: complete -- [$subscription]');
    }
  }

  /// Modifies the [PushConfig] for a specified subscription.
  ///
  /// This may be used to change a push subscription to a pull one (signified by
  /// an empty PushConfig) or vice versa, or change the endpoint URL and other
  /// attributes of a push subscription.  Messages will accumulate for delivery
  /// continuously through the call regardless of changes to the [PushConfig].
  ///
  /// The [subscription] name can be just the simple name or it can be the fully
  /// quantified name in the format:
  /// `projects/{project}/subscriptions/{subscription}`.
  Future<pb.Empty> modifyPushConfig({
    required PushConfig pushConfig,
    int retries = 5,
    required String subscription,
  }) async {
    assert(_initialized);
    _logger.fine('[modifyPushConfig]: start -- [$subscription]');

    try {
      return await _execute<pb.Empty>(
        executor: () async {
          return await _subscriberClient.modifyPushConfig(
            ModifyPushConfigRequest(
              pushConfig: pushConfig,
              subscription: subscription.startsWith('projects/')
                  ? subscription
                  : 'projects/$_projectId/subscriptions/$subscription',
            ),
          );
        },
        retries: retries,
      );
    } finally {
      _logger.fine('[modifyPushConfig]: complete -- [$subscription]');
    }
  }

  /// Adds one or more messages to the [topic].  Returns `NOT_FOUND` if the topic
  /// does not exist.
  ///
  /// The [topic] can be just the simple name or it can be the fully quantified
  /// name in the format: `projects/{project}/topics/{topic}`.
  Future<PublishResponse> publish({
    required Iterable<PubsubMessage> messages,
    int retries = 5,
    required String topic,
  }) async {
    assert(_initialized);
    try {
      _logger.fine('[publish]: start -- [$topic]');
    } catch (e) {
      // no-op; in the event that log events are sent via PubSub, this can
      // trigger errors trying to log this information out.  So... ignore that
      // error as log errors should never be allowed to create issues.
    }
    try {
      return await _execute(
        executor: () async {
          var result = await _publisherClient.publish(
            PublishRequest(
              messages: messages,
              topic: topic.startsWith('projects/')
                  ? topic
                  : 'projects/$_projectId/topics/$topic',
            ),
          );
          _logger.finest('[publish]: result -- [${result.messageIds}]');

          return result;
        },
        retries: retries,
      );
    } finally {
      try {
        _logger.fine('[publish]: complete -- [$topic]');
      } catch (e) {
        // no-op; in the event that log events are sent via PubSub, this can
        // trigger errors trying to log this information out.  So... ignore that
        // error as log errors should never be allowed to create issues.
      }
    }
  }

  /// Pulls messages from the server. The server may return `UNAVAILABLE` if
  /// there are too many concurrent pull requests pending for the given
  /// subscription.
  ///
  /// The [subscription] name can be just the simple name or it can be the fully
  /// quantified name in the format:
  /// `projects/{project}/subscriptions/{subscription}`.
  Future<List<ReceivedMessage>> pull({
    required int maxMessages,
    int retries = 5,
    required String subscription,
  }) async {
    assert(_initialized);
    _logger.fine('[pull]: start -- [$subscription]');
    try {
      return (await _execute(
        executor: () async {
          var result = await _subscriberClient.pull(
            PullRequest(
              maxMessages: maxMessages,
              subscription: subscription.startsWith('projects/')
                  ? subscription
                  : 'projects/$_projectId/subscriptions/$subscription',
            ),
          );

          return result;
        },
        retries: retries,
      ))
          .receivedMessages;
    } finally {
      _logger.fine('[pull]: complete -- [$subscription]');
    }
  }

  /// Seeks an existing subscription to a point in time or to a given snapshot,
  /// whichever is provided in the request.  Snapshots are used in `Seek`
  /// operations, which allow you to manage message acknowledgments in bulk.
  /// That is, you can set the acknowledgment state of messages in an existing
  /// subscription to the state captured by a snapshot.  Note that both the
  /// subscription and the snapshot must be on the same topic.
  ///
  /// The [subscription] name can be just the simple name or it can be the fully
  /// quantified name in the format:
  /// `projects/{project}/subscriptions/{subscription}`.
  Future<SeekResponse> seek({
    required int maxMessages,
    int retries = 5,
    required String subscription,
  }) async {
    assert(_initialized);
    _logger.fine('[seek]: start -- [$subscription]');
    try {
      return await _execute(
        executor: () async {
          var result = await _subscriberClient.seek(
            SeekRequest(
              subscription: subscription.startsWith('projects/')
                  ? subscription
                  : 'projects/$_projectId/subscriptions/$subscription',
            ),
          );

          return result;
        },
        retries: retries,
      );
    } finally {
      _logger.fine('[seek]: complete -- [$subscription]');
    }
  }

  /// Establishes a stream with the server, which sends messages down to the
  /// client.  The client streams acknowledgements and ack deadline
  /// modifications back to the server.  The server will close the stream and
  /// return the status on any error.  The server may close the stream with
  /// status `UNAVAILABLE` to reassign server-side resources, in which case, the
  /// client should re-establish the stream.  Flow control can be achieved by
  /// configuring the underlying RPC channel.
  ///
  /// The [connectionTtl] is the maximum amount of time to allow a single
  /// connection to remain open.  As connections may close without any notice,
  /// this value ensures that the stream can be re-established before messages
  /// may have expired and ensure they are consistently received.  While it is
  /// not recommended to disable the periodic reconnect, you may do so by
  /// setting the value to [Duration.zero].
  ///
  /// For more information on the request, see:
  /// https://cloud.google.com/pubsub/docs/reference/rpc/google.pubsub.v1#google.pubsub.v1.StreamingPullRequest
  Future<Stream<StreamingPullResponse>> streamingPull({
    Duration connectionTtl = const Duration(minutes: 5),
    void Function()? onClosed,
    int retries = 5,
    required Stream<StreamingPullRequest> stream,
    required StreamingPullRequest subscribeRequest,
  }) async {
    assert(_initialized);
    _logger.fine('[streamingPull]: start');

    return runZonedGuarded(() async {
      try {
        var innerController = StreamController<StreamingPullRequest>();
        var outerController = StreamController<StreamingPullResponse>();
        var listener = stream.listen((event) => innerController.add(event));

        ResponseStream<StreamingPullResponse>? result;
        StreamSubscription<StreamingPullResponse>? resultListener;

        late Future<void> Function() onCancel;
        Timer? reconnectTimer;

        outerController.onCancel = () {
          reconnectTimer?.cancel();
          resultListener?.cancel();
          result?.cancel();
          innerController.close();
          outerController.close();
          listener.cancel();

          if (onClosed != null) {
            onClosed();
          }
        };

        var connect = () async {
          await _executeStream<ResponseStream<StreamingPullResponse>>(
            executor: () async {
              innerController.onCancel = null;

              // ignore: unawaited_futures
              innerController.close();

              innerController = StreamController<StreamingPullRequest>();
              innerController.onCancel = onCancel;

              var reset =
                  await _subscriberClient.streamingPull(innerController.stream);
              result = reset;
              resultListener = reset.listen((event) {
                outerController.add(event);
              });
              _subscriptions.add(resultListener!);
              innerController.add(subscribeRequest);

              return reset;
            },
            retries: retries,
          );
        };

        innerController.add(subscribeRequest);
        onCancel = () async {
          if (!innerController.isClosed) {
            _logger.finer('[streamingPull]: connection closed; retrying');

            try {
              await connect();
              _logger.finer('[streamingPull]: reconnected');
            } catch (e, stack) {
              _logger.severe(
                '[streamingPull]: Error trying to connect',
                e,
                stack,
              );
            }
          }
        };

        await connect();

        if (connectionTtl.inMilliseconds > 0) {
          reconnectTimer = Timer.periodic(connectionTtl, (timer) async {
            _logger.finer('[streamingPull]: TTL exceeded, reconnecting');

            try {
              await connect();
              _logger.finer('[streamingPull]: reconnected');
            } catch (e, stack) {
              _logger.severe(
                '[streamingPull]: Error trying to connect',
                e,
                stack,
              );
            }
          });
        }

        return outerController.stream;
      } finally {
        _logger.fine('[streamingPull]: complete');
      }
    }, (e, stack) {
      _logger.severe('[streamingPull]: uncaught error encountered', e, stack);
    })!;
  }

  /// Updates an existing snapshot.  Snapshots are used in `Seek` operations,
  /// which allow you to manage message acknowledgments in bulk.  That is, you
  /// can set the acknowledgment state of messages in an existing subscription
  /// to the state captured by a snapshot.
  ///
  /// The [snapshot] name can be just the simple name or it can be the fully
  /// quantified name in the format: `projects/{project}/snapshots/{snap}`.
  Future<Snapshot> updateSnapshot({
    int retries = 5,
    required Snapshot snapshot,
    required List<SnapshotField> updateMask,
  }) async {
    assert(_initialized);
    assert(updateMask.isNotEmpty);

    _logger.fine('[updateSnapshot]: start');
    try {
      return await _execute(
        executor: () async {
          var result = await _subscriberClient.updateSnapshot(
            UpdateSnapshotRequest(
              snapshot: snapshot,
              updateMask: pb.FieldMask(
                paths: SnapshotField.toStrings(updateMask),
              ),
            ),
          );

          return result;
        },
        retries: retries,
      );
    } finally {
      _logger.fine('[updateSnapshot]: complete');
    }
  }

  /// Updates an existing subscription.  Note that certain properties of a
  /// subscription, such as its topic, are not modifiable.
  ///
  /// The [subscription] name can be just the simple name or it can be the fully
  /// quantified name in the format:
  /// `projects/{project}/subscriptions/{subscription}`.
  Future<Subscription> updateSubscription({
    int retries = 5,
    required Subscription subscription,
    required Iterable<SubscriptionField> updateMask,
  }) async {
    assert(_initialized);
    assert(updateMask.isNotEmpty);

    _logger.fine('[updateSubscription]: start');
    try {
      return await _execute(
        executor: () async {
          var result = await _subscriberClient.updateSubscription(
            UpdateSubscriptionRequest(
              subscription: subscription,
              updateMask: pb.FieldMask(
                paths: SubscriptionField.toStrings(updateMask),
              ),
            ),
          );

          return result;
        },
        retries: retries,
      );
    } finally {
      _logger.fine('[updateSubscription]: complete');
    }
  }

  /// Updates an existing [topic]. Note that certain properties of a topic are
  /// not modifiable.
  ///
  /// Set the list of fields to update via the [updateMask].
  Future<Topic> updateTopic({
    int retries = 5,
    required Topic topic,
    required Iterable<TopicField> updateMask,
  }) async {
    assert(_initialized);
    assert(updateMask.isNotEmpty);

    _logger.fine('[updateTopic]: start -- [$topic]');
    try {
      return await _execute(
        executor: () async {
          var result = await _publisherClient.updateTopic(
            UpdateTopicRequest(
              topic: topic,
              updateMask: pb.FieldMask(paths: TopicField.toStrings(updateMask)),
            ),
          );

          return result;
        },
        retries: retries,
      );
    } finally {
      _logger.fine('[updateTopic]: complete -- [$topic]');
    }
  }

  Future<T> _execute<T extends pb1.GeneratedMessage>({
    required Future<T> Function() executor,
    required int retries,
  }) async {
    T? result;

    var delay = Duration(milliseconds: 500);
    var attempts = 1;
    while (result == null) {
      var completer = Completer<T>();
      Completer<T>? innerCompleter = completer;
      try {
        // ignore: unawaited_futures
        runZonedGuarded(() async {
          innerCompleter?.complete(await executor());
          innerCompleter = null;
        }, (e, stack) {
          innerCompleter?.completeError(e, stack);
          innerCompleter = null;
        });

        result = await completer.future;
        break;
      } catch (e) {
        await _reconnect();
        attempts++;
        if (attempts < retries) {
          await Future.delayed(delay);

          delay = Duration(milliseconds: delay.inMilliseconds * 2);
          _logger.fine(
            '[execute]: Error attempting to execute function, attempt [$attempts / $retries].',
          );
        } else {
          rethrow;
        }
      }
    }

    return result;
  }

  Future<T> _executeStream<T extends ResponseStream>({
    required Future<T> Function() executor,
    required int retries,
  }) async {
    T? result;

    var delay = Duration(milliseconds: 500);
    var attempts = 1;
    while (result == null) {
      var completer = Completer<T>();
      Completer<T>? innerCompleter = completer;
      try {
        // ignore: unawaited_futures
        runZonedGuarded(() async {
          innerCompleter?.complete(await executor());
          innerCompleter = null;
        }, (e, stack) {
          innerCompleter?.completeError(e, stack);
          innerCompleter = null;
        });

        result = await completer.future;
        break;
      } catch (e) {
        await _reconnect();
        attempts++;
        if (attempts < retries) {
          await Future.delayed(delay);

          delay = Duration(milliseconds: delay.inMilliseconds * 2);
          _logger.fine(
            '[execute]: Error attempting to execute function, attempt [$attempts / $retries].',
          );
        } else {
          rethrow;
        }
      }
    }

    return result;
  }

  Future<void> _reconnect({
    bool closePrevious = true,
  }) async {
    if (closePrevious) {
      await _channel.shutdown();
    }

    _subscriptions.forEach((sub) => sub.cancel());
    _subscriptions.clear();

    var authenticator = ServiceAccountAuthenticator(
      _serviceAccountJson,
      _scopes,
    );
    _projectId = authenticator.projectId!;

    _channel = GrpcOrGrpcWebClientChannel.grpc(
      _host,
      port: _port,
    );

    _publisherClient = PublisherClient(
      _channel,
      options: authenticator.toCallOptions,
    );

    _subscriberClient = SubscriberClient(
      _channel,
      options: authenticator.toCallOptions,
    );
  }
}
