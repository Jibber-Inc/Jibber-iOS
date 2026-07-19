//
//  AnalyticsManager.swift
//  Jibber
//
//  Created by Benji Dodgson on 3/5/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation
import ParseCore

@MainActor
final class AnalyticsManager {
    
    static let shared = AnalyticsManager()
    
    enum EventType: String {
        case finalizedOnboarding = "ONBOARDING_FINALIZED"
        case onboardingBeginTapped = "ONBOARDING_BEGIN_TAPPED"
        case onboardingRSVPTapped = "ONBOARDING_RSVP_TAPPED"
        case emotionSelected = "EMOTION_SELECTED"
        case expressionSelected = "EXPRESSION_SELECTED"
        case expressionMade = "EXPRESSION_MADE"
        case deliveryTypeSelected = "DELIVERY_TYPE_SELECTED"
        case messageSent = "MESSAGE_SENT"
        case replySent = "REPLY_SENT"
        case suggestionSelected = "SUGGESTION_SELECTED"
        case inviteSent = "INVITE_SENT"
        case conversationCreated = "CONVERSATION_CREATED"
        case contextCueCreated = "CONTEXT_CUE_CREATED"
        case achievementCreated = "ACHIEVEMENT_CREATED"
        case appClipShareCreated = "APP_CLIP_SHARE_CREATED"
        case appClipInvoked = "APP_CLIP_INVOKED"
        case appClipPreviewViewed = "APP_CLIP_PREVIEW_VIEWED"
        case appClipGatedActionTapped = "APP_CLIP_GATED_ACTION_TAPPED"
        case appClipOnboardingStarted = "APP_CLIP_ONBOARDING_STARTED"
        case appClipOnboardingCompleted = "APP_CLIP_ONBOARDING_COMPLETED"
        case appClipConnectionCompleted = "APP_CLIP_CONNECTION_COMPLETED"
        case appClipUpgradeOverlayPresented = "APP_CLIP_UPGRADE_OVERLAY_PRESENTED"

        var isAppClipEvent: Bool {
            return self.rawValue.hasPrefix("APP_CLIP_")
        }
    }
    
    init() {
        if isRelease {
            
        }
    }
    
    func trackEvent(type: EventType, properties: [String: Any]? = nil) {
        // The legacy analytics provider is intentionally untouched. App Clip
        // funnel events are sent to Parse with a strict non-PII allowlist.
        guard type.isAppClipEvent else { return }

        let allowedKeys = Set(["action", "allocation", "kind", "outcome", "source"])
        var dimensions = ["environment": Config.shared.environment.rawValue]
        properties?.forEach { key, value in
            guard allowedKeys.contains(key), dimensions.count < 8 else { return }
            dimensions[key] = String(describing: value)
        }
        PFAnalytics.trackEvent(
            inBackground: type.rawValue,
            dimensions: dimensions,
            block: nil
        )
    }
    
    func trackStreen(type: String, properties: [String: Any]? = nil) {
        guard isRelease else { return }
    }
}
