// import 'dart:io';

// import 'package:logging/logging.dart';

// Future<void> main() async {
//   Logger.root.onRecord.listen((record) {
//     // ignore: avoid_print
//     print('${record.level.name}: ${record.time}: ${record.message}');
//     if (record.error != null) {
//       // ignore: avoid_print
//       print('${record.error}');
//     }
//     if (record.stackTrace != null) {
//       // ignore: avoid_print
//       print('${record.stackTrace}');
//     }
//   });
//   final _logger = Logger('main');

//   final serviceAccountFile = File('secrets/service_account.json');
//   if (!serviceAccountFile.existsSync()) {
//     _logger.info(
//       'File secrets/service_account.json not found. Please follow the '
//       'steps in README.md to create it.',
//     );
//     exit(1);
//   }

//   final scopes = [
//     'https://www.googleapis.com/auth/cloud-platform',
//     'https://www.googleapis.com/auth/pubsub',
//   ];

//   final authenticator = ServiceAccountAuthenticator(
//       serviceAccountFile.readAsStringSync(), scopes);
//   final projectId = authenticator.projectId;
// }
