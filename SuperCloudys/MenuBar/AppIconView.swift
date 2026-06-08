import SwiftUI

struct AppIconView: View {
    let path: String
    let size: CGFloat

    @State private var image: Image? = nil

    init(path: String, size: CGFloat = 16) {
        self.path = path
        self.size = size
    }

    var body: some View {
        Group {
            if let image = image {
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "app")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }
        }
        .frame(width: size, height: size)
        .task(id: path) {
            let nsImage = await AppIconCache.shared.icon(forPath: path)
            await MainActor.run {
                self.image = Image(nsImage: nsImage)
            }
        }
    }
}
