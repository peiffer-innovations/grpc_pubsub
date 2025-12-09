// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:grpc/grpc.dart';
import 'package:grpc_googleapis/google/pubsub_v1.dart';
import 'package:grpc_protobuf_convert/grpc_protobuf_convert.dart';
import 'package:grpc_pubsub/grpc_pubsub.dart';
import 'package:logging/logging.dart';
import 'package:test/test.dart';

Future<void> main() async {
  Logger.root.onRecord.listen((record) {
    print('${record.level.name}: ${record.time}: ${record.message}');
    if (record.error != null) {
      print('${record.error}');
    }
    if (record.stackTrace != null) {
      print('${record.stackTrace}');
    }
  });
  Logger.root.level = Level.FINEST;

  final client = PubsubClient.emulatorsOwner(projectId: 'unit');
  await client.initialize();

  final emulators = FirebaseEmulators();

  setUpAll(() async {
    await emulators.start();
  });

  tearDownAll(() async {
    await emulators.stop();
  });

  setUp(() async {
    final topics = (await client.listTopics()).topics;
    for (var i = 0; i < topics.length; i++) {
      await client.deleteTopic(topic: topics[i].name);
    }
  });

  tearDown(() async {
    final topics = (await client.listTopics()).topics;
    for (var i = 0; i < topics.length; i++) {
      await client.deleteTopic(topic: topics[i].name);
    }
  });

  test('topics', () async {
    var topic = await client.createTopic(topic: 'unit-test');

    expect(
      topic.name,
      'projects/unit/topics/unit-test',
    );

    topic = await client.createTopic(topic: 'unit-test2');
    expect(
      topic.name,
      'projects/unit/topics/unit-test2',
    );

    var topics = (await client.listTopics()).topics;
    expect(topics.length, 2);
    expect(
      topics[0].name.startsWith('projects/unit/topics/unit-test'),
      true,
    );
    expect(
      topics[1].name.startsWith('projects/unit/topics/unit-test'),
      true,
    );

    for (var i = 0; i < topics.length; i++) {
      await client.deleteTopic(topic: topics[i].name);
    }

    topics = (await client.listTopics()).topics;
    expect(topics.length, 0);
  });

  test('pull', () async {
    final topic = await client.createTopic(topic: 'pull');

    final subscription = await client.createSubscription(
      ackDeadlineSeconds: 10,
      expirationPolicy: ExpirationPolicy(
        ttl: GrpcProtobufConvert.toDuration(const Duration(minutes: 1)),
      ),
      topic: topic.name,
    );
    await client.publish(
      messages: [PubsubMessage(data: utf8.encode('test message'))],
      topic: topic.name,
    );

    final pull = await client.pull(
      maxMessages: 1,
      options: CallOptions(timeout: const Duration(seconds: 1)),
      subscription: subscription.name,
    );

    expect(pull.length, 1);

    await client.acknowledge(
      ackIds: [pull.first.ackId],
      subscription: subscription.name,
    );

    expect(
      await client.pull(
          maxMessages: 1,
          options: CallOptions(timeout: const Duration(seconds: 1)),
          subscription: subscription.name),
      isEmpty,
    );

    await client.deleteSubscription(subscription: subscription.name);
    await client.deleteTopic(topic: topic.name);
  });

  test('streamingPull', () async {
    final topic = await client.createTopic(topic: 'streaming-pull');

    final subscription = await client.createSubscription(
      topic: topic.name,
    );

    final stream = client.streamingPull(
      autoAcknowledge: true,
      subscription: subscription.name,
    );

    final numPublish = 10;

    final messages = <ReceivedMessage>[];
    final sub = stream.listen((message) {
      messages.add(message);
    });

    for (var i = 0; i < numPublish; i++) {
      await client.publish(
        messages: [PubsubMessage(data: utf8.encode('test message'))],
        topic: topic.name,
      );
    }

    // Break the sync loop so the message callback will happen.
    await Future.delayed(const Duration(milliseconds: 100));

    // ignore: unawaited_futures
    sub.cancel();

    expect(messages.length, numPublish);

    expect(
      await client.pull(
        maxMessages: 1,
        subscription: subscription.name,
        options: CallOptions(timeout: const Duration(seconds: 1)),
      ),
      isEmpty,
    );

    await client.deleteSubscription(subscription: subscription.name);
    await client.deleteTopic(topic: topic.name);
  });
}

class FirebaseEmulators {
  FirebaseEmulators({
    this.projectId = 'unit',
  });

  final String projectId;

  Process? _process;

  Future<PubsubClient> start({
    bool launchEmulators = true,
  }) async {
    if (_process != null) {
      throw Exception('Process already started');
    }
    if (launchEmulators) {
      final completer = Completer();
      print('Checking for firebase emulators');
      try {
        final exit = Process.runSync('firebase', ['--version']).exitCode;
        if (exit != 0) {
          print('Installing firebase emulators');
          Process.runSync('npm', ['install', '-g', 'firebase-tools']);
        }
      } catch (e) {
        print('Installing firebase emulators');
        Process.runSync('npm', ['install', '-g', 'firebase-tools']);
      }

      print('Starting emulators');
      final process = await Process.start('firebase', [
        'emulators:start',
        '--project',
        projectId,
      ]);
      _process = process;
      process.stdout.listen((event) {
        final line = utf8.decode(event).trim();
        print(line);
        if (line.contains('All emulators ready!')) {
          completer.complete();
        }
      });
      process.stderr.listen((event) {
        print(utf8.decode(event).trim());
      });

      await completer.future;
      print('emulators started');
    }

    final client = PubsubClient.emulatorsOwner(
      projectId: projectId,
    );

    return client;
  }

  Future<void> stop() async {
    final process = _process;
    if (process != null) {
      process.kill();
      await process.exitCode;
    }
  }
}
