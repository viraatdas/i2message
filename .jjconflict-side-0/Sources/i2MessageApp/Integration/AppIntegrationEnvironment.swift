import Foundation
import i2MessageCore

struct AppIntegrationEnvironment {
    let permissionManager: any PermissionManaging
    let messagingActions: any MessagingActionServicing
    let notificationHook: any MessagingNotificationHooking

    static func live() -> AppIntegrationEnvironment {
        let automation = MacOSMessagesAutomationController()
        let permissionManager = MacOSPermissionManager(automation: automation)
        let handoff = MacOSMessagesHandoffController(automation: automation)
        let messagingActions = SafeMessagingActionService(
            automation: automation,
            handoff: handoff,
            permissionManager: permissionManager
        )
        let notificationHook = MacOSNotificationHook()

        return AppIntegrationEnvironment(
            permissionManager: permissionManager,
            messagingActions: messagingActions,
            notificationHook: notificationHook
        )
    }
}
