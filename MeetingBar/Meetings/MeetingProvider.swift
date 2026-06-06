//
//  MeetingProvider.swift
//  MeetingBar
//
//  Single source of truth for meeting-provider metadata: the struct, the
//  static catalogue of all built-in providers, and ID-based lookup.
//
//  Replaces the earlier split of MeetingProviderDescriptor.swift +
//  MeetingProviderRegistry.swift. Adding a new provider means adding one
//  static property to the `Built-in providers` extension and listing it in
//  `MeetingProvider.all` — no other file needs to change.
//
//  Pure domain data — no AppKit or Defaults imports.
//

/// Per-provider metadata used by detection, opening, icon rendering, and the
/// preferences UI.
///
/// `id` is a stable string identity. For built-in providers it equals the
/// `rawValue` of the corresponding `MeetingServices` case so existing
/// persistence (bookmarks, browser preferences) continues to decode.
struct MeetingProvider: Equatable, Sendable {
    /// Stable string identity. For built-in providers this equals `MeetingServices.rawValue`.
    let id: String

    /// Human-readable display name.
    let displayName: String

    /// `NSImage(named:)` key for the provider icon.
    /// System template image names (e.g. "NSTouchBarOpenInBrowserTemplate") are valid here.
    let iconName: String

    /// Rendered icon width in points. Almost always 16.
    let iconWidth: Double

    /// Rendered icon height in points. Varies by provider logo aspect ratio.
    let iconHeight: Double

    /// URL detection regex pattern. `nil` for providers that don't use URL matching
    /// (e.g. phone, facetimeaudio, url catch-all, other).
    let regexPattern: String?

    /// Name of the per-provider native-app "browser" sentinel that appears in the
    /// browser picker for this provider. `nil` means only real browsers are shown.
    /// Plain String so the type stays free of AppKit / Defaults imports.
    let nativeAppBrowserName: String?
}

// MARK: - Lookup

extension MeetingProvider {
    /// Look up a provider by its stable string `id`.
    static func provider(for id: String) -> MeetingProvider? {
        byID[id]
    }

    /// Convenience lookup directly from a `MeetingServices` case.
    static func provider(for service: MeetingServices) -> MeetingProvider? {
        provider(for: service.rawValue)
    }

    /// All built-in providers keyed by `MeetingServices` for the regex map.
    /// Used by `MeetingLinkDetection` to compile the runtime regex catalogue.
    static var regexPatterns: [MeetingServices: String] {
        var result: [MeetingServices: String] = [:]
        for provider in all {
            guard let pattern = provider.regexPattern,
                let service = MeetingServices(rawValue: provider.id)
            else { continue }
            result[service] = pattern
        }
        return result
    }

    private static let byID: [String: MeetingProvider] = {
        Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }()
}

// MARK: - Built-in providers

extension MeetingProvider {
    // swiftlint:disable function_body_length
    static let all: [MeetingProvider] = {
        // Helper — most icons are 16×16; non-default heights are explicit.
        func make(
            _ service: MeetingServices,
            icon: String,
            height: Double = 16,
            pattern: String? = nil,
            nativeAppBrowserName: String? = nil
        ) -> MeetingProvider {
            MeetingProvider(
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
            make(.phone, icon: "NSTouchBarCommunicationAudioTemplate"),

            // Google Meet
            make(
                .meet,
                icon: "google_meet_icon",
                height: 13.2,
                pattern: #"https?://meet.google.com/(_meet/)?[a-z-]+"#,
                nativeAppBrowserName: "MeetInOne"),

            // Google Meet Stream
            make(
                .meetStream,
                icon: "google_meet_icon",
                height: 13.2,
                pattern: #"https?://stream\.meet\.google\.com/stream/[a-z0-9-]+"#),

            // Google Hangouts (deprecated)
            make(
                .hangouts,
                icon: "google_hangouts_icon",
                pattern: #"https?://hangouts\.google\.com/[^\s]*"#),

            // Google Duo
            make(
                .duo,
                icon: "google_duo_icon",
                pattern: #"https?://duo\.app\.goo\.gl/[^\s]*"#),

            // Zoom (web)
            make(
                .zoom,
                icon: "zoom_icon",
                pattern:
                    #"https:\/\/(?:[a-zA-Z0-9-.]+)?zoom(-x)?\.(?:us|com|com\.cn|de)\/(?:my|[a-z]{1,2}|webinar)\/[-a-zA-Z0-9()@:%_\+.~#?&=\/]*"#,
                nativeAppBrowserName: "Zoom"
            ),

            // Zoom (native app scheme)
            make(
                .zoom_native,
                icon: "zoom_icon",
                pattern:
                    #"zoommtg://([a-z0-9-.]+)?zoom(-x)?\.(?:us|com|com\.cn|de)/join[-a-zA-Z0-9()@:%_\+.~#?&=\/]*"#
            ),

            // ZoomGov
            make(
                .zoomgov,
                icon: "zoom_icon",
                pattern: #"https?://([a-z0-9.]+)?zoomgov\.com/j/[a-zA-Z0-9?&=]+"#),

            // Reclaim.ai (uses Zoom links)
            make(
                .reclaim,
                icon: "zoom_icon",
                pattern: #"https?://reclaim\.ai/z/[A-Za-z0-9./]+"#),

            // Microsoft Teams
            make(
                .teams,
                icon: "ms_teams_icon",
                pattern:
                    #"https?://(gov\.)?teams\.microsoft\.(com|us)/(l/meetup-join/[a-zA-Z0-9_%\/=\-\+\.?]+(?:&[^\s]+)?|meet/\d+\?p=[A-Za-z0-9_\-]+(?:&[^\s]+)?)"#,
                nativeAppBrowserName: "Teams"
            ),

            // Cisco Webex
            make(
                .webex,
                icon: "webex_icon",
                pattern:
                    #"https?://(?:[A-Za-z0-9-]+\.)?webex\.com(?:(?:/[-A-Za-z0-9]+/j\.php\?MTID=[A-Za-z0-9]+(?:&\S*)?)|(?:/(?:meet|join)/[A-Za-z0-9\-._@]+(?:\?\S*)?))"#
            ),

            // Jitsi
            make(
                .jitsi,
                icon: "jitsi_icon",
                pattern: #"https?://meet\.jit\.si/[^\s]*"#,
                nativeAppBrowserName: "Jitsi"),

            // Amazon Chime
            make(
                .chime,
                icon: "amazon_chime_icon",
                pattern: #"https?://([a-z0-9-.]+)?chime\.aws/[0-9]*"#),

            // Ring Central
            make(
                .ringcentral,
                icon: "ringcentral_icon",
                pattern: #"https?://([a-z0-9.]+)?ringcentral\.com/[^\s]*"#),

            // GoToMeeting
            make(
                .gotomeeting,
                icon: "gotomeeting_icon",
                pattern: #"https?://([a-z0-9.]+)?gotomeeting\.com/[^\s]*"#),

            // GoToWebinar
            make(
                .gotowebinar,
                icon: "gotowebinar_icon",
                pattern: #"https?://([a-z0-9.]+)?gotowebinar\.com/[^\s]*"#),

            // BlueJeans
            make(
                .bluejeans,
                icon: "bluejeans_icon",
                pattern: #"https?://([a-z0-9.]+)?bluejeans\.com/[^\s]*"#),

            // 8x8
            make(
                .eight_x_eight,
                icon: "8x8_icon",
                height: 8,
                pattern: #"https?://8x8\.vc/[^\s]*"#),

            // Demio
            make(
                .demio,
                icon: "demio_icon",
                pattern: #"https?://event\.demio\.com/[^\s]*"#),

            // Join.me
            make(
                .join_me,
                icon: "joinme_icon",
                height: 10,
                pattern: #"https?://join\.me/[^\s]*"#),

            // Whereby
            make(
                .whereby,
                icon: "whereby_icon",
                height: 18,
                pattern: #"https?://whereby\.com/[^\s]*"#),

            // Uber Conference
            make(
                .uberconference,
                icon: "uberconference_icon",
                pattern: #"https?://uberconference\.com/[^\s]*"#),

            // Blizz (rebranded to TeamViewer Meeting)
            make(
                .blizz,
                icon: "teamviewer_meeting_icon",
                pattern: #"https?://go\.blizz\.com/[^\s]*"#),

            // TeamViewer Meeting
            make(
                .teamviewer_meeting,
                icon: "teamviewer_meeting_icon",
                pattern: #"https?://go\.teamviewer\.com/[^\s]*"#),

            // VSee
            make(
                .vsee,
                icon: "vsee_icon",
                pattern: #"https?://vsee\.com/[^\s]*"#),

            // StarLeaf
            make(
                .starleaf,
                icon: "starleaf_icon",
                pattern: #"https?://meet\.starleaf\.com/[^\s]*"#),

            // Tencent VooV
            make(
                .voov,
                icon: "voov_icon",
                pattern: #"https?://voovmeeting\.com/[^\s]*"#),

            // Facebook Workspace
            make(
                .facebook_workspace,
                icon: "facebook_workplace_icon",
                pattern: #"https?://([a-z0-9-.]+)?workplace\.com/groupcall/[^\s]+"#),

            // Lifesize
            make(
                .lifesize,
                icon: "lifesize_icon",
                pattern: #"https?://call\.lifesizecloud\.com/[^\s]*"#),

            // Skype
            make(
                .skype,
                icon: "skype_icon",
                pattern: #"https?://join\.skype\.com/[^\s]*"#),

            // Skype for Business
            make(
                .skype4biz,
                icon: "skype_business_icon",
                pattern: #"https?://meet\.lync\.com/[^\s]*"#),

            // Skype for Business (self-hosted)
            make(
                .skype4biz_selfhosted,
                icon: "skype_business_icon",
                pattern: #"https?:\/\/(meet|join)\.[^\s]*\/[a-z0-9.]+/meet\/[A-Za-z0-9./]+"#),

            // FaceTime (link-based)
            make(
                .facetime,
                icon: "facetime_icon",
                pattern: #"https://facetime\.apple\.com/join[^\s]*"#),

            // FaceTime Audio — no URL pattern, opened via facetime-audio://
            make(.facetimeaudio, icon: "facetime_icon"),

            // YouTube
            make(
                .youtube,
                icon: "youtube_icon",
                pattern: #"https?://((www|m)\.)?(youtube\.com|youtu\.be)/[^\s]*"#),

            // Vonage Meetings
            make(
                .vonageMeetings,
                icon: "vonage_icon",
                pattern: #"https?://meetings\.vonage\.com/[0-9]{9}"#),

            // Around (no custom icon)
            make(
                .around,
                icon: "no_online_session",
                pattern: #"https?://(meet\.)?around\.co/[^\s]*"#),

            // Jam (no custom icon)
            make(
                .jam,
                icon: "no_online_session",
                pattern: #"https?://jam\.systems/[^\s]*"#),

            // Discord (no custom icon)
            make(
                .discord,
                icon: "no_online_session",
                pattern:
                    #"(http|https|discord)://(www\.)?(canary\.)?discord(app)?\.([a-zA-Z]{2,})(.+)?"#
            ),

            // Blackboard Collaborate (no custom icon)
            make(
                .blackboard_collab,
                icon: "no_online_session",
                pattern: #"https?://us\.bbcollab\.com/[^\s]*"#),

            // Any Link — catch-all, no URL pattern
            make(.url, icon: "NSTouchBarOpenInBrowserTemplate"),

            // CoScreen
            make(
                .coscreen,
                icon: "coscreen_icon",
                pattern: #"https?://join\.coscreen\.co/[^\s]*"#),

            // Vowel
            make(
                .vowel,
                icon: "vowel_icon",
                pattern: #"https?://([a-z0-9.]+)?vowel\.com/#/g/[^\s]*"#),

            // Zhumu
            make(
                .zhumu,
                icon: "zhumu_icon",
                pattern: #"https://welink\.zhumu\.com/j/[0-9]+?pwd=[a-zA-Z0-9]+"#),

            // Lark
            make(
                .lark,
                icon: "lark_icon",
                pattern: #"https://vc\.larksuite\.com/j/[0-9]+"#),

            // Feishu
            make(
                .feishu,
                icon: "feishu_icon",
                pattern: #"https://vc\.feishu\.cn/j/[0-9]+"#),

            // Vimeo
            make(
                .vimeo,
                icon: "vimeo_icon",
                pattern:
                    #"https://vimeo\.com/(showcase|event)/[0-9]+|https://venues\.vimeo\.com/[^\s]+"#
            ),

            // oVice
            make(
                .ovice,
                icon: "ovice_icon",
                pattern: #"https://([a-z0-9-.]+)?ovice\.(in|com)/[^\s]*"#),

            // Luma (no custom icon)
            make(
                .luma,
                icon: "no_online_session",
                pattern: #"https://lu\.ma/join/[^\s]*"#),

            // Preply
            make(
                .preply,
                icon: "preply_icon",
                pattern: #"https://preply\.com/[^\s]*"#),

            // UserZoom
            make(
                .userzoom,
                icon: "userzoom_icon",
                pattern: #"https://go\.userzoom\.com/participate/[a-z0-9-]+"#),

            // Venue
            make(
                .venue,
                icon: "venue_icon",
                height: 4,
                pattern: #"https://app\.venue\.live/app/[^\s]*"#),

            // Teemyco
            make(
                .teemyco,
                icon: "teemyco_icon",
                pattern: #"https://app\.teemyco\.com/room/[^\s]*"#),

            // Demodesk
            make(
                .demodesk,
                icon: "demodesk_icon",
                pattern: #"https://demodesk\.com/[^\s]*"#),

            // Zoho Cliq
            make(
                .zoho_cliq,
                icon: "zoho_cliq_icon",
                pattern: #"https://cliq\.zoho\.eu/meetings/[^\s]*"#),

            // Slack (huddle)
            make(
                .slack,
                icon: "slack_icon",
                pattern: #"https?://app\.slack\.com/huddle/[A-Za-z0-9./]+"#,
                nativeAppBrowserName: "Slack"),

            // Gather
            make(
                .gather,
                icon: "gather_icon",
                pattern:
                    #"https?://app.gather.town/app/[A-Za-z0-9]+/[A-Za-z0-9_%\-]+\?(spawnToken|meeting)=[^\s]*"#
            ),

            // Pop
            make(
                .pop,
                icon: "pop_icon",
                pattern: #"https?://pop\.com/j/[0-9-]+"#),

            // Chorus
            make(
                .chorus,
                icon: "chorus_icon",
                pattern: #"https?://go\.chorus\.ai/[^\s]+"#),

            // Gong
            make(
                .gong,
                icon: "gong_icon",
                pattern: #"https?://([a-z0-9-.]+)?join\.gong\.io/[^\s]+"#),

            // Livestorm
            make(
                .livestorm,
                icon: "livestorm_icon",
                pattern: #"https?://app\.livestorm\.com/p/[^\s]+"#),

            // Tuple
            make(
                .tuple,
                icon: "tuple_icon",
                pattern: #"https://tuple\.app/c/[^\s]*"#),

            // Pumble
            make(
                .pumble,
                icon: "pumble_icon",
                pattern: #"https?://meet\.pumble\.com/[a-z-]+"#),

            // Suit Conference
            make(
                .suitConference,
                icon: "suit_conference_icon",
                pattern: #"https?://([a-z0-9.]+)?conference\.istesuit\.com/[^\s]*+"#),

            // Doxy.me
            make(
                .doxyMe,
                icon: "doxy_me_icon",
                pattern: #"https://([a-z0-9.]+)?doxy\.me/[^\s]*"#),

            // Cal Video
            make(
                .calcom,
                icon: "calcom_icon",
                pattern: #"https?://app.cal\.com/video/[A-Za-z0-9./]+"#),

            // zm.page
            make(
                .zmPage,
                icon: "zm_page_icon",
                pattern: #"https?://([a-zA-Z0-9.]+)\.zm\.page"#),

            // LiveKit Meet
            make(
                .livekit,
                icon: "livekit_icon",
                pattern: #"https?://meet[a-zA-Z0-9.]*\.livekit\.io/rooms/[a-zA-Z0-9-#]+"#),

            // Meetecho
            make(
                .meetecho,
                icon: "meetecho_icon",
                pattern: #"https?://meetings\.conf\.meetecho\.com/.+"#),

            // StreamYard
            make(
                .streamyard,
                icon: "streamyard_icon",
                pattern:
                    #"https://(?:www\.)?streamyard\.com/(?:guest/)?([a-z0-9]{8,13})(?:/|\?[^ \n]*)?"#
            ),

            // Riverside
            make(
                .riverside,
                icon: "riverside_icon",
                pattern: #"https?://riverside\.(com|fm)/studio/[^\s]*"#,
                nativeAppBrowserName: "Riverside"),

            // Other — catch-all for custom regex matches, no URL pattern
            make(.other, icon: "no_online_session")
        ]
    }()
    // swiftlint:enable function_body_length
}
