import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:grpc_pubsub/grpc_pubsub.dart';
import 'package:logging/logging.dart';
import 'package:test/test.dart';

Future<void> main() async {
  final file = File('secrets/service_account.json');

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

    final client = PubsubClient(serviceAccountJson: serviceAccount);
    await client.initialize();

    setUp(() async {
      final topics = (await client.listTopics()).topics;
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
      final topic = await client.createTopic(topic: 'unit-test-publish');

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
      final topics = (await client.listTopics()).topics;
      for (var i = 0; i < topics.length; i++) {
        await client.deleteTopic(topic: topics[i].name);
      }
    });
  }
}

// ignore_for_file: avoid_print

class FirebaseEmulators {
  FirebaseEmulators({
    this.pubsubUrl = 'http://localhost:5097/',
  });

  final String projectId;
  final String pubsubUrl;

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
      final exit = Process.runSync('firebase', ['--version']).exitCode;
      if (exit != 0) {
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
