# ParseLiveQuery provenance

The Swift sources in `Sources/ParseLiveQuery` are copied from
`parse-community/Parse-SDK-iOS-OSX` tag `6.1.1`, revision
`af5d63cc38dc614f7017029c6f3f586a8d737ec7`. The only source adaptation is an
unqualified `Event<T>` reference in `ObjCCompat.swift`, required because this
fork uses a unique module name to coexist with ParseObjC's unused upstream
`ParseLiveQuery` target in the SwiftPM graph.

This local product exists because ParseCore's generated umbrella module imports
`PFPurchase.h`, whose public StoreKit 1 declarations trigger three deprecation
warnings in the iOS 18+ SDK even though ParseLiveQuery does not use purchases.
The package manifest scopes `-Wno-deprecated-declarations` to this target's
Clang importer. The Xcode project passes the same Clang-importer flag to its
native targets, which also import ParseCore directly. Swift application-source
deprecation warnings remain enabled.

When upgrading ParseObjC, update these sources from the matching upstream tag,
retain `LICENSE` and `PATENTS`, and re-run clean Debug and Release builds before
changing the pinned version.
