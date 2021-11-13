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
