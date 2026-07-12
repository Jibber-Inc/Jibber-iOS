# Parse messaging cutover notes

## Status

The iOS messaging runtime is Parse-native. The app, notification extensions,
intent handlers, conversation screens, threads, replies, pins, reactions,
typing, reads, and moment comments no longer use the GetStream SDK or chat
tokens.

This is a fresh-start cutover: existing GetStream conversations and messages
are intentionally not migrated. A mandatory app-version/schema gate prevents
old clients from writing against the new contract during rollout.

## Runtime architecture

- `MessagingContracts` owns vendor-neutral models, pagination, capabilities,
  and repository protocols.
- `MessagingPersistence` owns ParseSwift models and queries, LiveQuery
  reconciliation, the user-scoped GRDB cache, attachment checkpoints, and the
  durable send outbox.
- `ParseMessagingManager` verifies the authenticated Parse identity, opens the
  correct user-scoped database, checks backend capabilities, reconciles cached
  reads with LiveQuery, and drains queued writes in conversation order.
- The compatibility controllers adapt the repository to the existing Jibber
  presentation protocols. Collection-view IDs remain stable client IDs and are
  resolved to canonical Parse object IDs before server mutations.
- Parse Cloud Code validates membership, immutable/server-managed fields,
  idempotency keys, ACLs, reply aggregates, and push behavior for direct client
  writes.

## Supported behavior

- Direct, group, and moment conversations
- Cached conversation/message/reply/member/pin reads with keyset pagination
- Offline optimistic sends and replies with durable retry and idempotency
- Edit, tombstone delete, hide, pin, reaction, expression, read/unread, title,
  membership, and typing mutations
- Read receipts, delivery state, unread counts, reply summaries, and thread
  participants
- Parse LiveQuery updates with cache reconciliation
- Parse-native notification rendering, quick reply, and mark-read actions
- Idempotent moment-conversation creation with `moment:<objectId>` context keys

## Intentional boundaries

- There is no GetStream history migration or dual-write period.
- Media must have a local file URL or a remote URL before it can enter the
  attachment/outbox pipeline.
- Generic audio, contact, location, and arbitrary metadata replacement remain
  unsupported because Jibber has no current product behavior for those kinds.
- Direct Parse writes require an authenticated user and the required app/schema
  headers; server hooks remain authoritative for authorization and derived
  fields.

## Release gates

Before production rollout, verify the backend unit and real Parse/Mongo suites,
the messaging package tests, a full staging app build, production Mongo indexes,
LiveQuery and push configuration, and the minimum-version/schema capability
response. Keep the mandatory-update gate enabled for the cutover release.
