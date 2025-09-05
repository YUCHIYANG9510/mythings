//
//  CanvasBoardView.swift
//  mythings
//
//  Created by Designer on 2025/9/4.
//

import SwiftUI

struct CanvasBoardView: View {
    let items: [Item]
    let imageLoader: ImageMemoryCache

    // 版面設定
    private let itemSize: CGFloat = 160
    private let itemSpacing: CGFloat = 24
    private let edgePadding: CGFloat = 32
    private let columnsCount: Int = 6

    // 交錯位移（讓欄與欄之間上下錯開）
    private var staggerOffsetY: CGFloat { (itemSize + itemSpacing) * 0.5 }

    // 依據交錯排版計算白板尺寸
    private var boardSize: CGSize {
        let totalColumns = CGFloat(columnsCount)
        let rows = CGFloat((items.count + columnsCount - 1) / columnsCount)

        let width = edgePadding * 2
        + totalColumns * itemSize
        + max(0, totalColumns - 1) * itemSpacing

        // 高度要加上交錯帶來的額外空間（最後一欄可能下移）
        let heightBase = edgePadding * 2
        + rows * itemSize
        + max(0, rows - 1) * itemSpacing

        // 當有超過 1 欄時，最底下可能被偶數欄下移多佔 0.5 個格距
        let extra = columnsCount > 1 ? staggerOffsetY : 0

        return CGSize(width: max(width, 800), height: max(heightBase + extra, 600))
    }

    // 平移狀態
    @State private var offset: CGSize = .zero
    @State private var lastDrag: CGSize = .zero

    // 預覽
    @State private var previewing: Item?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                LinearGradient(colors: [Color(.systemBackground), Color(.systemGray6)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                    .ignoresSafeArea()

                ZStack {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        let pos = staggeredPosition(for: index)
                        CanvasItemCell(item: item, imageLoader: imageLoader) { tapped in
                            previewing = tapped
                        }
                        .position(x: pos.x, y: pos.y)
                    }
                }
                .frame(width: boardSize.width, height: boardSize.height)
                .offset(x: offset.width, y: offset.height)
                .contentShape(Rectangle()) // 讓整塊可拖
                .gesture(panGesture(viewSize: geo.size))
                .animation(.spring(response: 0.22, dampingFraction: 0.9), value: offset)
            }
            .onAppear { centerContentIfSmaller(in: geo.size) }
            .onChange(of: geo.size) { _, newSize in centerContentIfSmaller(in: newSize) }
            .sheet(item: $previewing) { item in
                CanvasPreview(item: item, imageLoader: imageLoader)
                    .presentationDetents([.medium, .large])
                    .presentationCornerRadius(24)
            }
        }
    }

    // MARK: - 交錯網格位置
    private func staggeredPosition(for index: Int) -> CGPoint {
        let col = index % columnsCount
        let row = index / columnsCount

        let x = edgePadding + itemSize / 2 + CGFloat(col) * (itemSize + itemSpacing)

        // 偶數欄（或你想的任一規則）往下位移半格距
        let yBase = edgePadding + itemSize / 2 + CGFloat(row) * (itemSize + itemSpacing)
        let y = (col % 2 == 1) ? (yBase + staggerOffsetY) : yBase

        return CGPoint(x: x, y: y)
    }

    // MARK: - 初始化：內容比螢幕小時置中
    private func centerContentIfSmaller(in viewSize: CGSize) {
        let bounds = panBounds(in: viewSize)
        let centeredX = bounds.minX == bounds.maxX ? (viewSize.width - boardSize.width) / 2 : bounds.minX
        let centeredY = bounds.minY == bounds.maxY ? (viewSize.height - boardSize.height) / 2 : bounds.minY

        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            offset = CGSize(width: centeredX, height: centeredY)
            lastDrag = offset
        }
    }

    // MARK: - 拖移（含彈性邊界 + 慣性）
    private func panGesture(viewSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                let raw = CGSize(width: lastDrag.width + value.translation.width,
                                 height: lastDrag.height + value.translation.height)

                // 邊界與 60pt 橡皮筋
                let b = panBounds(in: viewSize)
                let eased = rubberBand(raw, within: b, band: 60)
                offset = eased
            }
            .onEnded { value in
                // 以預測位移估出動量，做慣性目標點
                let extra = CGSize(width: value.predictedEndTranslation.width - value.translation.width,
                                   height: value.predictedEndTranslation.height - value.translation.height)

                // 動量縮放係數（數字越大慣性越強）
                let momentumScale: CGFloat = 0.25
                let target = CGSize(width: offset.width + extra.width * momentumScale,
                                    height: offset.height + extra.height * momentumScale)

                // 收斂到合法邊界
                let b = panBounds(in: viewSize)
                let clamped = clamp(target, within: b)

                withAnimation(.interpolatingSpring(stiffness: 220, damping: 28)) {
                    offset = clamped
                    lastDrag = clamped
                }
            }
    }

    // 依視窗與內容大小計算可平移邊界
    private func panBounds(in viewSize: CGSize) -> (minX: CGFloat, maxX: CGFloat, minY: CGFloat, maxY: CGFloat) {
        // 若內容比視窗小，min==max，代表不需要滾動；否則保留 edgePadding 的內距
        let minX = min(edgePadding, viewSize.width - boardSize.width - edgePadding)
        let maxX = edgePadding
        let minY = min(edgePadding, viewSize.height - boardSize.height - edgePadding)
        let maxY = edgePadding
        return (minX, maxX, minY, maxY)
    }

    // 邊界內夾取
    private func clamp(_ value: CGSize, within b: (minX: CGFloat, maxX: CGFloat, minY: CGFloat, maxY: CGFloat)) -> CGSize {
        CGSize(width: min(b.maxX, max(b.minX, value.width)),
               height: min(b.maxY, max(b.minY, value.height)))
    }

    // 橡皮筋效果：超出邊界時放慢
    private func rubberBand(_ value: CGSize, within b: (minX: CGFloat, maxX: CGFloat, minY: CGFloat, maxY: CGFloat), band: CGFloat) -> CGSize {
        func banded(_ v: CGFloat, min: CGFloat, max: CGFloat) -> CGFloat {
            if v < min {
                let d = min - v
                return min - band * log1p(d / band)
            } else if v > max {
                let d = v - max
                return max + band * log1p(d / band)
            }
            return v
        }
        return CGSize(width: banded(value.width, min: b.minX, max: b.maxX),
                      height: banded(value.height, min: b.minY, max: b.maxY))
    }
}


// MARK: - 白板內的單一物件（重新設計）
struct CanvasItemCell: View {
    let item: Item
    let imageLoader: ImageMemoryCache
    @State private var image: UIImage?
    @State private var isPressed = false
    let onTap: (Item) -> Void

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 140, height: 140)
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.systemGray6))
                    .overlay(
                        ProgressView().scaleEffect(0.9)
                    )
                    .frame(width: 140, height: 140)
            }
        }
        .frame(width: 160, height: 160) // 保持原本格子尺寸，方便對齊
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isPressed)
        .onTapGesture { onTap(item) }
        .pressEvents(
            onPress: { isPressed = true },
            onRelease: { isPressed = false }
        )
        .onAppear {
            imageLoader.loadImage(named: item.imageName) { img in
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        self.image = img
                    }
                }
            }
        }
    }
}

// MARK: - 點擊後的預覽視窗
struct CanvasPreview: View {
    let item: Item
    let imageLoader: ImageMemoryCache
    @State private var image: UIImage?

    var body: some View {
        VStack(spacing: 16) {
            Capsule()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 40, height: 4)
                .padding(.top, 8)

            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 420)
                } else {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(.systemGray6))
                        .overlay(ProgressView())
                        .frame(height: 300)
                }
            }
            .padding(.horizontal, 20)

            Spacer(minLength: 0)
        }
        .onAppear {
            imageLoader.loadImage(named: item.imageName) { img in
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        self.image = img
                    }
                }
            }
        }
        .padding(.bottom, 20)
    }
}

// MARK: - 按壓事件 Helper
extension View {
    func pressEvents(onPress: @escaping () -> Void, onRelease: @escaping () -> Void) -> some View {
        self.simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in onPress() }
                .onEnded { _ in onRelease() }
        )
    }
}
