import SwiftUI

struct HomeView: View {
    var body: some View {
        NavigationView {
            FeaturePlaceholderView(
                systemImage: "house",
                titleKey: "home.placeholder.title",
                messageKey: "home.placeholder.message"
            )
            .navigationTitle("tab.home")
            .navigationBarTitleDisplayMode(.large)
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}
