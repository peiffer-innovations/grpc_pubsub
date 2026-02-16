[I'm done](https://github.com/peiffer-innovations/peiffer-innovations.github.com)


<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->
**Table of Contents**

- [grpc_pubsub](#grpc_pubsub)
  - [Using the library](#using-the-library)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

# grpc_pubsub

Library to work with the the gRPC based APIs for [Cloud Pub/Sub](https://cloud.google.com/pubsub/docs/reference/rpc).

All the requests support retries with a progressive backoff by default.  The streaming pull is designed to be fault tolerant with automated reconnects to ensure that once subscribed, the messages are properly received with minimal effort from the client.

## Using the library

Add the repo to your Flutter `pubspec.yaml` file.

```
dependencies:
  grpc_pubsub: <<version>> 
```

Then run...
```
flutter packages get
```
