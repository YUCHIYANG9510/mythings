//
//  CanvasBoardView.swift
//  mythings
//
//  Created by Designer on 2025/9/4.
//

import SwiftUI

// MARK: - Canvas 白板主視圖
struct CanvasBoardView: View {
    let items: [Item]
    let imageLoader: ImageMemoryCache

    // 大白板尺寸（可調整）
    private let boardSize = CGSize(width: 2400, height: 1800)

    // 縮放/平移狀態
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastDrag: CGSize = .zero

    // 預覽
    @State private var previewing: Item?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.white

                // 內容容器
                ZStack {
                    ForEach(items) { item in
                        let pos = stablePosition(for: item.id, in: boardSize)
                        CanvasItemCell(item: item, imageLoader: imageLoader)
                            .position(x: pos.x, y: pos.y)
                    }
                }
                .frame(width: boardSize.width, height: boardSize.height)
                .scaleEffect(scale)
                .offset(x: offset.width, y: offset.height)
                .gesture(canvasGestures(viewSize: geo.size))
                .animation(.spring(response: 0.25, dampingFraction: 0.9), value: scale)
                .animation(.spring(response: 0.25, dampingFraction: 0.9), value: offset)
            }
            .onReceive(NotificationCenter.default.publisher(for: .canvasItemTapped)) { output in
                if let tapped = output.object as? Item {
                    previewing = tapped
                }
            }
            .sheet(item: $previewing) { item in
                CanvasPreview(item: item, imageLoader: imageLoader)
                    .presentationDetents([.medium, .large])
                    .presentationCornerRadius(24)
            }
        }
    }

    // MARK: 手勢（雙指縮放 + 拖曳平移）
    private func canvasGestures(viewSize: CGSize) -> some Gesture {
        let magnify = MagnificationGesture()
            .onChanged { value in
                let newScale = (lastScale * value)
                // 夾在 0.5 ~ 2.5 之間
                scale = min(max(newScale, 0.5), 2.5)
            }
            .onEnded { _ in
                lastScale = scale
            }

        let drag = DragGesture(minimumDistance: 2)
            .onChanged { val in
                offset = CGSize(width: lastDrag.width + val.translation.width,
                                height: lastDrag.height + val.translation.height)
            }
            .onEnded { _ in
                lastDrag = offset
            }

        return drag.simultaneously(with: magnify)
    }

    // MARK: 給每個 item 生成「穩定隨機」座標
    private func stablePosition(for id: UUID, in size: CGSize) -> CGPoint {
        var hasher = Hasher()
        hasher.combine(id)
        let seed = hasher.finalize()

        // 兩個 0~1 的隨機（但可重現）
        let u = CGFloat(abs(seed &* 1103515245 &+ 12345) % 10_000) / 10_000.0
        let v = CGFloat(abs((seed ^ 0x9e3779b9) &* 1103515245 &+ 12345) % 10_000) / 10_000.0

        // 預留邊界 80，避免貼邊
        let margin: CGFloat = 80
        let x = margin + u * (size.width - 2 * margin)
        let y = margin + v * (size.height - 2 * margin)
        return CGPoint(x: x, y: y)
    }
}

// MARK: - 白板內的單一物件（圖片 + 標題）
struct CanvasItemCell: View {
    let item: Item
    let imageLoader: ImageMemoryCache
    @State private var image: UIImage?

    var body: some View {
        VStack(spacing: 8) {
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 140, height: 140)
                } else {
                    ZStack {
                        Color(.systemGray6)
                        ProgressView()
                    }
                    .frame(width: 140, height: 140)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 4)

            Text(item.name)
                .font(.subheadline)
                .foregroundColor(.black)
        }
        .onTapGesture {
            // 透過環境發通知（用 PreferenceKey 也可以），這裡簡化用 NotificationCenter 不太優雅。
            // 在本檔實作我們直接用環視 .sheet 的做法：交由父視圖處理。
            NotificationCenter.default.post(name: .canvasItemTapped, object: item)
        }
        .onAppear {
            // 載圖（走你已有的快取）
            imageLoader.loadImage(named: item.imageName) { img in
                self.image = img
            }
        }
        // 接收點擊事件並轉給上層（因為這個 cell 沒持有 preview state）
        .onReceive(NotificationCenter.default.publisher(for: .canvasItemTapped)) { note in
            // no-op；此行僅避免 SwiftUI 早期版本在無訂閱者時的 warning
        }
        // 把事件往上 bubble：由父層 CanvasBoardView 來 .sheet
        .background(
            CanvasItemTapBridge(item: item)
        )
    }
}

// 事件橋（讓父視圖抓到點擊的 item）
private struct CanvasItemTapBridge: UIViewRepresentable {
    let item: Item
    func makeUIView(context: Context) -> UIView { UIView() }
    func updateUIView(_ uiView: UIView, context: Context) {
        // 當前沒有需要更新的事情
    }
}

private extension Notification.Name {
    static let canvasItemTapped = Notification.Name("canvasItemTapped")
}

struct CanvasPreview: View {
    let item: Item
    let imageLoader: ImageMemoryCache
    @State private var image: UIImage?

    var body: some View {
        VStack(spacing: 16) {
            Capsule().fill(Color.secondary.opacity(0.3))
                .frame(width: 40, height: 4)
                .padding(.top, 8)

            Text(item.name)
                .font(.headline)

            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 360)
                        .cornerRadius(12)
                } else {
                    ZStack {
                        Color(.systemGray6)
                        ProgressView()
                    }
                    .frame(height: 240)
                    .cornerRadius(12)
                }
            }
            .padding(.horizontal, 20)

            Spacer(minLength: 0)
        }
        .onAppear {
            imageLoader.loadImage(named: item.imageName) { img in
                self.image = img
            }
        }
        .padding(.bottom, 12)
    }
}
