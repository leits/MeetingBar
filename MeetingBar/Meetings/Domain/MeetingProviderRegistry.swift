//
//  MeetingProviderRegistry.swift
//  MeetingBar
//
//  Static registry of all built-in meeting provider descriptors.
//  No AppKit or Defaults imports — pure domain data.
//
//  Phase 3 goal: every per-provider switch in `MeetingServices.swift` and
//  `MeetingLinkDetection.swift` is gradually replaced by a registry lookup.
//  For PR 1, this is additive — existing switch statements remain unchanged.
//

/// Static registry of all built-in `MeetingProviderDescriptor` values.
///
/// Use `descriptor(for:)` to look up a provider by ID or `MeetingServices` case.
/// The `regexPatterns` bridge exposes the full pattern map for use in the
/// existing detection layer until Phase 3 PR 2 migrates it to the registry.
enum MeetingProviderRegistry {
    /// All built-in provider descriptors.
    static let all: [MeetingProviderDescriptor] = builtIn

    /// Descriptors keyed by stable string ID for O(1) lookup.
    private static let byID: [String: MeetingProviderDescriptor] = {
        Dictionary(builtIn.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }()

    /// Look up a descriptor by its stable string `id`.
    static func descriptor(for id: String) -> MeetingProviderDescriptor? {
        byID[id]
    }

    /// Convenience lookup directly from a `MeetingServices` case.
    static func descriptor(for service: MeetingServices) -> MeetingProviderDescriptor? {
        descriptor(for: service.rawValue)
    }

    /// Bridge to the existing `meetingLinkRegexPatterns` format.
    /// Computed from descriptors so detection behaviour is identical.
    /// The `meetingLinkRegexPatterns` constant in MeetingLinkDetection.swift is
    /// deprecated and delegates here; remove it in Phase 3 PR 7 cleanup.
    static var regexPatterns: [MeetingServices: String] {
        var result: [MeetingServices: String] = [:]
        for descriptor in builtIn {
            guard let pattern = descriptor.regexPattern,
                let service = MeetingServices(rawValue: descriptor.id)
            else { continue }
            result[service] = pattern
        }
        return result
    }
}

// MARK: - Built-in descriptors

extension MeetingProviderRegistry {
    // swiftlint:disable function_body_length
    fileprivate static let builtIn: [MeetingProviderDescriptor] = {
        // Helper — most icons are 16×16; non-default heights are explicit.
        func desc(
            _ service: MeetingServices,
            icon: String,
            height: Double = 16,
            pattern: String? = nil,
            nativeAppBrowserName: String? = nil
        ) -> MeetingProviderDescriptor {
            MeetingProviderDescriptor(
                id: service.rawValue,
                displayName: service.rawValue,
                iconName: icon,
                iconWidth: 16,
                iconHeight: height,
                regexPattern: pattern,
                nativeAppBrowserName: nativeAppBrowserName
            )
        }

        return [
            // Phone — no URL pattern, opened via tel://
            desc(
                .phone,
                icon: "NSTouchBarCommunicationAudioTemplate"),

            // Google Meet
            desc(
                .meet,
                icon: "google_meet_icon",
                height: 13.2,
                pattern: #"https?://meet.google.com/(_meet/)?[a-z-]+"#,
                nativeAppBrowserName: "MeetInOne"),

            // Google Meet Stream
            desc(
                .meetStream,
                icon: "google_meet_icon",
                height: 13.2,
                pattern: #"https?://stream\.meet\.google\.com/stream/[a-z0-9-]+"#),

            // Google Hangouts (deprecated)
            desc(
                .hangouts,
                icon: "google_hangouts_icon",
                pattern: #"https?://hangouts\.google\.com/[^\s]*"#),

            // Google Duo
            desc(
                .duo,
                icon: "google_duo_icon",
                pattern: #"https?://duo\.app\.goo\.gl/[^\s]*"#),

            // Zoom (web)
            desc(
                .zoom,
                icon: "zoom_icon",
                pattern:
                    #"https:\/\/(?:[a-zA-Z0-9-.]+)?zoom(-x)?\.(?:us|com|com\.cn|de)\/(?:my|[a-z]{1,2}|webinar)\/[-a-zA-Z0-9()@:%_\+.~#?&=\/]*"#,
                nativeAppBrowserName: "Zoom"
            ),

            // Zoom (native app scheme)
            desc(
                .zoom_native,
                icon: "zoom_icon",
                pattern:
                    #"zoommtg://([a-z0-9-.]+)?zoom(-x)?\.(?:us|com|com\.cn|de)/join[-a-zA-Z0-9()@:%_\+.~#?&=\/]*"#
            ),

            // ZoomGov
            desc(
                .zoomgov,
                icon: "zoom_icon",
                pattern: #"https?://([a-z0-9.]+)?zoomgov\.com/j/[a-zA-Z0-9?&=]+"#),

            // Reclaim.ai (uses Zoom links)
            desc(
                .reclaim,
                icon: "zoom_icon",
                pattern: #"https?://reclaim\.ai/z/[A-Za-z0-9./]+"#),

            // Microsoft Teams
            desc(
                .teams,
                icon: "ms_teams_icon",
                pattern:
                    #"https?://(gov.)?teams\.microsoft\.(com|us)/l/meetup-join/[a-zA-Z0-9_%\/=\-\+\.?]+"#,
                nativeAppBrowserName: "Teams"
            ),

            // Cisco Webex
            desc(
                .webex,
                icon: "webex_icon",
                pattern:
                    #"https?://(?:[A-Za-z0-9-]+\.)?webex\.com(?:(?:/[-A-Za-z0-9]+/j\.php\?MTID=[A-Za-z0-9]+(?:&\S*)?)|(?:/(?:meet|join)/[A-Za-z0-9\-._@]+(?:\?\S*)?))"#
            ),

            // Jitsi
            desc(
                .jitsi,
                icon: "jitsi_icon",
                pattern: #"https?://meet\.jit\.si/[^\s]*"#,
                nativeAppBrowserName: "Jitsi"),

            // Amazon Chime
            desc(
                .chime,
                icon: "amazon_chime_icon",
                pattern: #"https?://([a-z0-9-.]+)?chime\.aws/[0-9]*"#),

            // Ring Central
            desc(
                .ringcentral,
                icon: "ringcentral_icon",
                pattern: #"https?://([a-z0-9.]+)?ringcentral\.com/[^\s]*"#),

            // GoToMeeting
            desc(
                .gotomeeting,
                icon: "gotomeeting_icon",
                pattern: #"https?://([a-z0-9.]+)?gotomeeting\.com/[^\s]*"#),

            // GoToWebinar
            desc(
                .gotowebinar,
                icon: "gotowebinar_icon",
                pattern: #"https?://([a-z0-9.]+)?gotowebinar\.com/[^\s]*"#),

            // BlueJeans
            desc(
                .bluejeans,
                icon: "bluejeans_icon",
                pattern: #"https?://([a-z0-9.]+)?bluejeans\.com/[^\s]*"#),

            // 8x8
            desc(
                .eight_x_eight,
                icon: "8x8_icon",
                height: 8,
                pattern: #"https?://8x8\.vc/[^\s]*"#),

            // Demio
            desc(
                .demio,
                icon: "demio_icon",
                pattern: #"https?://event\.demio\.com/[^\s]*"#),

            // Join.me
            desc(
                .join_me,
                icon: "joinme_icon",
                height: 10,
                pattern: #"https?://join\.me/[^\s]*"#),

            // Whereby
            desc(
                .whereby,
                icon: "whereby_icon",
                height: 18,
                pattern: #"https?://whereby\.com/[^\s]*"#),

            // Uber Conference
            desc(
                .uberconference,
                icon: "uberconference_icon",
                pattern: #"https?://uberconference\.com/[^\s]*"#),

            // Blizz (rebranded to TeamViewer Meeting)
            desc(
                .blizz,
                icon: "teamviewer_meeting_icon",
                pattern: #"https?://go\.blizz\.com/[^\s]*"#),

            // TeamViewer Meeting
            desc(
                .teamviewer_meeting,
                icon: "teamviewer_meeting_icon",
                pattern: #"https?://go\.teamviewer\.com/[^\s]*"#),

            // VSee
            desc(
                .vsee,
                icon: "vsee_icon",
                pattern: #"https?://vsee\.com/[^\s]*"#),

            // StarLeaf
            desc(
                .starleaf,
                icon: "starleaf_icon",
                pattern: #"https?://meet\.starleaf\.com/[^\s]*"#),

            // Tencent VooV
            desc(
                .voov,
                icon: "voov_icon",
                pattern: #"https?://voovmeeting\.com/[^\s]*"#),

            // Facebook Workspace
            desc(
                .facebook_workspace,
                icon: "facebook_workplace_icon",
                pattern: #"https?://([a-z0-9-.]+)?workplace\.com/groupcall/[^\s]+"#),

            // Lifesize
            desc(
                .lifesize,
                icon: "lifesize_icon",
                pattern: #"https?://call\.lifesizecloud\.com/[^\s]*"#),

            // Skype
            desc(
                .skype,
                icon: "skype_icon",
                pattern: #"https?://join\.skype\.com/[^\s]*"#),

            // Skype for Business
            desc(
                .skype4biz,
                icon: "skype_business_icon",
                pattern: #"https?://meet\.lync\.com/[^\s]*"#),

            // Skype for Business (self-hosted)
            desc(
                .skype4biz_selfhosted,
                icon: "skype_business_icon",
                pattern: #"https?:\/\/(meet|join)\.[^\s]*\/[a-z0-9.]+/meet\/[A-Za-z0-9./]+"#),

            // FaceTime (link-based)
            desc(
                .facetime,
                icon: "facetime_icon",
                pattern: #"https://facetime\.apple\.com/join[^\s]*"#),

            // FaceTime Audio — no URL pattern, opened via facetime-audio://
            desc(
                .facetimeaudio,
                icon: "facetime_icon"),

            // YouTube
            desc(
                .youtube,
                icon: "youtube_icon",
                pattern: #"https?://((www|m)\.)?(youtube\.com|youtu\.be)/[^\s]*"#),

            // Vonage Meetings
            desc(
                .vonageMeetings,
                icon: "vonage_icon",
                pattern: #"https?://meetings\.vonage\.com/[0-9]{9}"#),

            // Around (no custom icon)
            desc(
                .around,
                icon: "no_online_session",
                pattern: #"https?://(meet\.)?around\.co/[^\s]*"#),

            // Jam (no custom icon)
            desc(
                .jam,
                icon: "no_online_session",
                pattern: #"https?://jam\.systems/[^\s]*"#),

            // Discord (no custom icon)
            desc(
                .discord,
                icon: "no_online_session",
                pattern:
                    #"(http|https|discord)://(www\.)?(canary\.)?discord(app)?\.([a-zA-Z]{2,})(.+)?"#
            ),

            // Blackboard Collaborate (no custom icon)
            desc(
                .blackboard_collab,
                icon: "no_online_session",
                pattern: #"https?://us\.bbcollab\.com/[^\s]*"#),

            // Any Link — catch-all, no URL pattern
            desc(
                .url,
                icon: "NSTouchBarOpenInBrowserTemplate"),

            // CoScreen
            desc(
                .coscreen,
                icon: "coscreen_icon",
                pattern: #"https?://join\.coscreen\.co/[^\s]*"#),

            // Vowel
            desc(
                .vowel,
                icon: "vowel_icon",
                pattern: #"https?://([a-z0-9.]+)?vowel\.com/#/g/[^\s]*"#),

            // Zhumu
            desc(
                .zhumu,
                icon: "zhumu_icon",
                pattern: #"https://welink\.zhumu\.com/j/[0-9]+?pwd=[a-zA-Z0-9]+"#),

            // Lark
            desc(
                .lark,
                icon: "lark_icon",
                pattern: #"https://vc\.larksuite\.com/j/[0-9]+"#),

            // Feishu
            desc(
                .feishu,
                icon: "feishu_icon",
                pattern: #"https://vc\.feishu\.cn/j/[0-9]+"#),

            // Vimeo
            desc(
                .vimeo,
                icon: "vimeo_icon",
                pattern:
                    #"https://vimeo\.com/(showcase|event)/[0-9]+|https://venues\.vimeo\.com/[^\s]+"#
            ),

            // oVice
            desc(
                .ovice,
                icon: "ovice_icon",
                pattern: #"https://([a-z0-9-.]+)?ovice\.(in|com)/[^\s]*"#),

            // Luma (no custom icon)
            desc(
                .luma,
                icon: "no_online_session",
                pattern: #"https://lu\.ma/join/[^\s]*"#),

            // Preply
            desc(
                .preply,
                icon: "preply_icon",
                pattern: #"https://preply\.com/[^\s]*"#),

            // UserZoom
            desc(
                .userzoom,
                icon: "userzoom_icon",
                pattern: #"https://go\.userzoom\.com/participate/[a-z0-9-]+"#),

            // Venue
            desc(
                .venue,
                icon: "venue_icon",
                height: 4,
                pattern: #"https://app\.venue\.live/app/[^\s]*"#),

            // Teemyco
            desc(
                .teemyco,
                icon: "teemyco_icon",
                pattern: #"https://app\.teemyco\.com/room/[^\s]*"#),

            // Demodesk
            desc(
                .demodesk,
                icon: "demodesk_icon",
                pattern: #"https://demodesk\.com/[^\s]*"#),

            // Zoho Cliq
            desc(
                .zoho_cliq,
                icon: "zoho_cliq_icon",
                pattern: #"https://cliq\.zoho\.eu/meetings/[^\s]*"#),

            // Slack (huddle)
            desc(
                .slack,
                icon: "slack_icon",
                pattern: #"https?://app\.slack\.com/huddle/[A-Za-z0-9./]+"#,
                nativeAppBrowserName: "Slack"),

            // Gather
            desc(
                .gather,
                icon: "gather_icon",
                pattern:
                    #"https?://app.gather.town/app/[A-Za-z0-9]+/[A-Za-z0-9_%\-]+\?(spawnToken|meeting)=[^\s]*"#
            ),

            // Pop
            desc(
                .pop,
                icon: "pop_icon",
                pattern: #"https?://pop\.com/j/[0-9-]+"#),

            // Chorus
            desc(
                .chorus,
                icon: "chorus_icon",
                pattern: #"https?://go\.chorus\.ai/[^\s]+"#),

            // Gong
            desc(
                .gong,
                icon: "gong_icon",
                pattern: #"https?://([a-z0-9-.]+)?join\.gong\.io/[^\s]+"#),

            // Livestorm
            desc(
                .livestorm,
                icon: "livestorm_icon",
                pattern: #"https?://app\.livestorm\.com/p/[^\s]+"#),

            // Tuple
            desc(
                .tuple,
                icon: "tuple_icon",
                pattern: #"https://tuple\.app/c/[^\s]*"#),

            // Pumble
            desc(
                .pumble,
                icon: "pumble_icon",
                pattern: #"https?://meet\.pumble\.com/[a-z-]+"#),

            // Suit Conference
            desc(
                .suitConference,
                icon: "suit_conference_icon",
                pattern: #"https?://([a-z0-9.]+)?conference\.istesuit\.com/[^\s]*+"#),

            // Doxy.me
            desc(
                .doxyMe,
                icon: "doxy_me_icon",
                pattern: #"https://([a-z0-9.]+)?doxy\.me/[^\s]*"#),

            // Cal Video
            desc(
                .calcom,
                icon: "calcom_icon",
                pattern: #"https?://app.cal\.com/video/[A-Za-z0-9./]+"#),

            // zm.page
            desc(
                .zmPage,
                icon: "zm_page_icon",
                pattern: #"https?://([a-zA-Z0-9.]+)\.zm\.page"#),

            // LiveKit Meet
            desc(
                .livekit,
                icon: "livekit_icon",
                pattern: #"https?://meet[a-zA-Z0-9.]*\.livekit\.io/rooms/[a-zA-Z0-9-#]+"#),

            // Meetecho
            desc(
                .meetecho,
                icon: "meetecho_icon",
                pattern: #"https?://meetings\.conf\.meetecho\.com/.+"#),

            // StreamYard
            desc(
                .streamyard,
                icon: "streamyard_icon",
                pattern:
                    #"https://(?:www\.)?streamyard\.com/(?:guest/)?([a-z0-9]{8,13})(?:/|\?[^ \n]*)?"#
            ),

            // Riverside
            desc(
                .riverside,
                icon: "riverside_icon",
                pattern: #"https?://riverside\.(com|fm)/studio/[^\s]*"#,
                nativeAppBrowserName: "Riverside"),

            // Other — catch-all for custom regex matches, no URL pattern
            desc(
                .other,
                icon: "no_online_session"),
        ]
    }()
    // swiftlint:enable function_body_length
}
