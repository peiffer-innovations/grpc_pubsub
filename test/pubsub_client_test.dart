import 'dart:io';

import 'package:grpc_pubsub/grpc_pubsub.dart';
import 'package:logging/logging.dart';
import 'package:test/test.dart';

Future<void> main() async {
  var file = File('secrets/service_account.json');

  String? serviceAccount;
  if (file.existsSync()) {
    serviceAccount = file.readAsStringSync();
  } else {
    serviceAccount = Platform.environment['SERVICE_ACCOUNT'];
  }

  test('no-op', () {});

  if (serviceAccount != null && serviceAccount.isNotEmpty) {
    Logger.root.onRecord.listen((record) {
      // ignore: avoid_print
      print('${record.level.name}: ${record.time}: ${record.message}');
      if (record.error != null) {
        // ignore: avoid_print
        print('${record.error}');
      }
      if (record.stackTrace != null) {
        // ignore: avoid_print
        print('${record.stackTrace}');
      }
    });
    Logger.root.level = Level.FINEST;

    var client = PubsubClient(serviceAccountJson: serviceAccount);
    await client.initialize();

    setUp(() async {
      var topics = (await client.listTopics()).topics;
      for (var i = 0; i < topics.length; i++) {
        await client.deleteTopic(topic: topics[i].name);
      }
    });

    test('topics', () async {
      var topic = await client.createTopic(topic: 'unit-test');

      expect(
        topic.name,
        'projects/automatedtestingframework/topics/unit-test',
      );

      topic = await client.createTopic(topic: 'unit-test2');
      expect(
        topic.name,
        'projects/automatedtestingframework/topics/unit-test2',
      );

      var topics = (await client.listTopics()).topics;
      expect(topics.length, 2);
      expect(
        topics[0]
            .name
            .startsWith('projects/automatedtestingframework/topics/unit-test'),
        true,
      );
      expect(
        topics[1]
            .name
            .startsWith('projects/automatedtestingframework/topics/unit-test'),
        true,
      );

      for (var i = 0; i < topics.length; i++) {
        await client.deleteTopic(topic: topics[i].name);
      }

      topics = (await client.listTopics()).topics;
      expect(topics.length, 0);
    });

    test('publish', () async {
      var topic = await client.createTopic(topic: 'unit-test-publish');

      expect(
        topic.name,
        'projects/automatedtestingframework/topics/unit-test-publish',
      );

      var topics = (await client.listTopics()).topics;
      for (var i = 0; i < topics.length; i++) {
        await client.deleteTopic(topic: topics[i].name);
      }

      topics = (await client.listTopics()).topics;
      expect(topics.length, 0);
    });

    tearDown(() async {
      var topics = (await client.listTopics()).topics;
      for (var i = 0; i < topics.length; i++) {
        await client.deleteTopic(topic: topics[i].name);
      }
    });
  }
}
