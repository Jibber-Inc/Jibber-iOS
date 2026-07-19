//
//  AppClipTests.swift
//  AppClipTests
//
//  Created by Benji Dodgson on 12/24/21.
//  Copyright © 2021 Benjamin Dodgson. All rights reserved.
//

import XCTest
@testable import AppClip

class AppClipTests: XCTestCase {

    func testParsesParameterizedInviteRegardlessOfQueryOrder() throws {
        let url = try XCTUnwrap(
            URL(
                string: "https://appclip.apple.com/id?reservationId=reservation-1&kind=invite&p=com.Jibber-Inc.iOS.Clip"
            )
        )

        XCTAssertEqual(
            AppClipInvocation(url: url),
            .invite(reservationID: "reservation-1")
        )
    }

    func testParsesParameterizedMomentRegardlessOfQueryOrder() throws {
        let url = try XCTUnwrap(
            URL(
                string: "https://appclip.apple.com/id?momentId=moment-1&p=com.Jibber-Inc.iOS.Clip&kind=moment"
            )
        )

        XCTAssertEqual(
            AppClipInvocation(url: url),
            .moment(momentID: "moment-1")
        )
    }

    func testParsesWebsiteFallbackRoutesByQueryName() throws {
        let invite = try XCTUnwrap(
            URL(string: "https://jibber.wtf/reservation?source=qr&reservationId=reservation-2")
        )
        let moment = try XCTUnwrap(
            URL(string: "https://jibber.wtf/moment?source=messages&momentId=moment-2")
        )

        XCTAssertEqual(
            AppClipInvocation(url: invite),
            .invite(reservationID: "reservation-2")
        )
        XCTAssertEqual(
            AppClipInvocation(url: moment),
            .moment(momentID: "moment-2")
        )
    }

    func testBuildsEnvironmentSpecificDefaultLinks() {
        XCTAssertEqual(
            AppClipInvocation.invite(reservationID: "r1").url(for: .production).absoluteString,
            "https://appclip.apple.com/id?p=com.Jibber-Inc.iOS.Clip&kind=invite&reservationId=r1"
        )
        XCTAssertEqual(
            AppClipInvocation.moment(momentID: "m1").url(for: .staging).absoluteString,
            "https://appclip.apple.com/id?p=com.Jibber-Inc.iOS-staging.Clip&kind=moment&momentId=m1"
        )
    }

    func testMapsInvocationsToEquivalentInviteAndMomentDestinations() {
        switch AppClipInvocation.invite(reservationID: "r1").launchActivity {
        case .reservation(let reservationID):
            XCTAssertEqual(reservationID, "r1")
        default:
            XCTFail("Invite invocation did not map to the Reservation flow")
        }

        switch AppClipInvocation.moment(momentID: "m1").launchActivity {
        case .deepLink(let deepLink):
            XCTAssertEqual(deepLink.deepLinkTarget?.rawValue, DeepLinkTarget.moment.rawValue)
            XCTAssertEqual(deepLink.momentId, "m1")
        default:
            XCTFail("Moment invocation did not map to the Moment flow")
        }
    }

    func testRejectsMalformedInvocations() throws {
        let missingID = try XCTUnwrap(
            URL(string: "https://appclip.apple.com/id?p=com.Jibber-Inc.iOS.Clip&kind=moment")
        )
        let unknownKind = try XCTUnwrap(
            URL(string: "https://appclip.apple.com/id?p=com.Jibber-Inc.iOS.Clip&kind=other&id=1")
        )
        let externalHost = try XCTUnwrap(
            URL(string: "https://example.com/?kind=invite&reservationId=reservation-1")
        )
        let wrongApplePath = try XCTUnwrap(
            URL(string: "https://appclip.apple.com/not-id?kind=moment&momentId=moment-1")
        )

        XCTAssertNil(AppClipInvocation(url: missingID))
        XCTAssertNil(AppClipInvocation(url: unknownKind))
        XCTAssertNil(AppClipInvocation(url: externalHost))
        XCTAssertNil(AppClipInvocation(url: wrongApplePath))
    }
}
