import SwiftUI
import AppKit

struct IconView: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 185, style: .continuous)
                .fill(Color.white)
                .frame(width: 824, height: 824)

            Text("P")
                .font(.custom("Bodoni 72", size: 680).weight(.bold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color(red: 0.168, green: 0.165, blue: 0.353),
                            Color(red: 0.357, green: 0.247, blue: 0.627)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .offset(y: 30)
        }
        .frame(width: 1024, height: 1024)
    }
}

@MainActor
func renderIcon() {
    let renderer = ImageRenderer(content: IconView())
    renderer.scale = 1.0
    guard let nsImage = renderer.nsImage,
          let tiff = nsImage.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let data = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write("render failed\n".data(using: .utf8)!)
        exit(1)
    }
    let path = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
    do {
        try data.write(to: URL(fileURLWithPath: path))
        print("wrote \(path) (\(data.count) bytes)")
    } catch {
        FileHandle.standardError.write("write failed: \(error)\n".data(using: .utf8)!)
        exit(1)
    }
}

MainActor.assumeIsolated {
    renderIcon()
}
