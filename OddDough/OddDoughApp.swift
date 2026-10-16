import SwiftUI

@main
struct OddDoughApp: App {
    var body: some Scene {
        WindowGroup {
            WebViewContainer()
                .ignoresSafeArea(.keyboard)
        }
    }
}
