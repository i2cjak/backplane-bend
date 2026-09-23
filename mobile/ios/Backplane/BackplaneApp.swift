import SwiftUI

@main
struct BackplaneApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                // backplane://pair?url=... opens straight into that hub
                .onOpenURL { url in
                    if url.scheme == "backplane" { model.pair(url.absoluteString) }
                }
        }
    }
}
