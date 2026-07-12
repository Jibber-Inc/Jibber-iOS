# Messaging package

`MessagingContracts` is Foundation-only and safe for the app and extension
targets. `MessagingPersistence` is app-only and contains ParseSwift, GRDB,
LiveQuery, attachment upload, repository, cache, and outbox implementations.

## App integration

1. Add this local package to the Xcode workspace. Link `MessagingPersistence`
   to the main app only; link `MessagingContracts` to extensions that need
   notification/deep-link models.
2. Initialize ParseSwift 4.14.2 once with the same application ID, client key,
   server URL, and LiveQuery URL as the Objective-C SDK. Do not ship a master
   key. Leave Objective-C keychain migration disabled when using the explicit
   session bridge below.
3. Implement `MessagingSessionProviding` with the current `PFUser.objectId` and
   `PFUser.sessionToken`, then call
   `MessagingAuthenticationCoordinator(...).synchronizeSession()` after login
   and whenever the legacy session changes.
4. Construct the durable stack after session activation:

   ```swift
   let databaseURL = try GRDBMessagingStore.defaultDatabaseURL()
   let store = try GRDBMessagingStore(databaseURL: databaseURL)
   let repository = ParseMessagingRepository(
       authenticatedUserID: userID,
       uploadCache: store)
   let realtime = try ParseMessagingLiveQueryClient(
       authenticatedUserID: userID)
   let reconciler = MessagingRealtimeReconciler(store: store)
   let outboxWorker = MessagingOutboxWorker(
       store: store,
       remote: repository,
       errorClassifier: ParseMessagingErrorClassifier())
   ```

5. For a send, call `store.stageSend(draft:authorID:)` before updating the UI,
   then run `outboxWorker.drainOnce()`. Trigger drains after enqueue, app launch,
   foregrounding, and network recovery. The persisted client message ID and
   attachment upload cache make retries idempotent across process termination.
6. Subscribe with the currently loaded conversation IDs. Pass each aggregate
   event to `MessagingRealtimeReconciler.apply`. On
   `conversationSetInvalidated`, refresh all conversation pages, call
   `store.removeConversation(id:)` for server-confirmed departures, cancel the
   old subscription, and subscribe again with the refreshed ID set. An empty
   initial ID set still subscribes to the authenticated user's memberships and
   discovers their first/new conversation.
7. On logout, cancel LiveQuery, stop outbox scheduling, and call
   `store.removeAllMessagingData()` before activating another user.

The backend must deploy the matching schemas, indexes, CLPs, validation
triggers, Cloud functions, S3 file adapter, and authenticated LiveQuery classes
before enabling writes in the client.

