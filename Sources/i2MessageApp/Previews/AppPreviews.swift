import SwiftUI

#Preview("Full Shell") {
    ContentView()
        .environmentObject(AppPreviewFactory.shellModel())
        .frame(width: 1220, height: 760)
}

#Preview("Search Workspace") {
    SearchWorkspaceView()
        .environmentObject(AppPreviewFactory.searchModel())
        .frame(width: 920, height: 680)
}

#Preview("Contacts") {
    ContactsWorkspaceView()
        .environmentObject(AppPreviewFactory.contactsModel())
        .frame(width: 920, height: 680)
}

@MainActor
private enum AppPreviewFactory {
    static func shellModel() -> AppViewModel {
        AppViewModel(dependencies: .mock(delayNanoseconds: 0))
    }

    static func searchModel() -> AppViewModel {
        let model = AppViewModel(dependencies: .mock(delayNanoseconds: 0))
        model.sidebarDestination = .search
        model.searchQuery = "semantic index"
        return model
    }

    static func contactsModel() -> AppViewModel {
        let model = AppViewModel(dependencies: .mock(delayNanoseconds: 0))
        model.sidebarDestination = .contacts
        return model
    }
}
