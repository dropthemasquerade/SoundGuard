import Foundation

/// A classic message alert the user captures from the real app or device.
/// The original recordings are not bundled.
struct NotificationPreset: Identifiable, Equatable {
    var id: String
    var name: String
    var hint: String
    var profile: SoundProfile
    var instruction: String

    static let catalog: [NotificationPreset] = [
        NotificationPreset(
            id: "zoom",
            name: "Zoom",
            hint: "chat",
            profile: .beep,
            instruction: "Play Zoom's classic chat message sound once, on speaker, close to this iPhone."
        ),
        NotificationPreset(
            id: "slack",
            name: "Slack",
            hint: "knock brush",
            profile: .custom,
            instruction: "Play Slack's classic Knock Brush notification once, on speaker, close to this iPhone."
        ),
        NotificationPreset(
            id: "telegram",
            name: "Telegram",
            hint: "default",
            profile: .beep,
            instruction: "Play Telegram's default message sound once, on speaker, close to this iPhone."
        ),
        NotificationPreset(
            id: "wechat",
            name: "WeChat",
            hint: "message",
            profile: .beep,
            instruction: "Play WeChat's classic new-message sound once, on speaker, close to this iPhone."
        ),
        NotificationPreset(
            id: "qq",
            name: "QQ",
            hint: "message",
            profile: .beep,
            instruction: "Play QQ's classic message beep once, on speaker, close to this iPhone."
        ),
        NotificationPreset(
            id: "iphone",
            name: "iPhone",
            hint: "tri-tone",
            profile: .beep,
            instruction: "Play the classic Tri-tone text sound. Settings → Sounds & Haptics → Text Tone → Tri-tone. Hold that iPhone close to this one."
        )
    ]
}
