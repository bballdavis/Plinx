import SwiftUI
import PlinxUI

struct PlinxContentView: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(PlexAPIContext.self) private var plexApiContext
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(LibraryStore.self) private var libraryStore
    @Environment(MainCoordinator.self) private var mainCoordinator

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch sessionManager.status {
            case .hydrating:
                PlinxieLoadingView()
            case .signedOut:
                SignInView(
                    viewModel: SignInViewModel(
                        sessionManager: sessionManager,
                        context: plexApiContext,
                    ),
                )
            case .needsProfileSelection:
                NavigationStack {
                    ProfileSwitcherView(
                        viewModel: ProfileSwitcherViewModel(
                            context: plexApiContext,
                            sessionManager: sessionManager,
                        ),
                    )
                }
            case .needsServerSelection:
                NavigationStack {
                    SelectServerView(
                        viewModel: ServerSelectionViewModel(
                            sessionManager: sessionManager,
                            context: plexApiContext,
                        ),
                    )
                }
            case .ready:
                RootTabView()
            }
        }
        .fullScreenCover(isPresented: Bindable(mainCoordinator).isPresentingPlayer) {
            if let playQueue = mainCoordinator.selectedPlayQueue {
                PlayerWrapper(
                    viewModel: PlayerViewModel(
                        playQueue: playQueue,
                        context: plexApiContext,
                        shouldResumeFromOffset: mainCoordinator.shouldResumeFromOffset
                    )
                )
            }
        }
    }
}
