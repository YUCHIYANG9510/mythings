//
//  CanvasBoardView.swift
//  mythings
//

import SwiftUI

struct CanvasBoardView: View {
    let items: [Item]
    let imageLoader: ImageMemoryCache

    // 版面設定
    private let edgePadding: CGFloat = 10
    private let minItemSize: CGFloat = 60
    private let maxItemSize: CGFloat = 120
    private let baseItemSize: CGFloat = 90

    // Quick Look（按住顯示，放手消失）
    @State private var quickLookItem: Item?
    @State private var showQuickLook: Bool = false

    // 浮動物件與畫布
    @State private var floatingItems: [FloatingItem] = []
    @State private var canvasSize: CGSize = .zero

    // 動畫控制
    @State private var animationTimer: Timer?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                LinearGradient(colors: [Color(.systemBackground), Color(.systemGray6)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                    .ignoresSafeArea()

                // 漂浮的物件
                ForEach(floatingItems, id: \.item.id) { floatingItem in
                    CanvasItemCell(
                        item: floatingItem.item,
                        imageLoader: imageLoader,
                        size: floatingItem.size,
                        rotation: floatingItem.rotation,
                        // 按住開始 -> 顯示卡片
                        onHoldBegan: { item in
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            pauseAnimation()
                            quickLookItem = item
                            withAnimation(.spring(response: 0.1, dampingFraction: 0.9)) {
                                showQuickLook = true
                            }
                        },
                        // 放手 -> 關閉卡片
                        onHoldEnded: {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.95)) {
                                showQuickLook = false
                            }
                            // 稍微等收合動畫再恢復
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                                startAnimation()
                                quickLookItem = nil
                            }
                        }
                    )
                    .position(floatingItem.position)
                }

                // Quick Look 卡片（無全屏遮罩，僅卡片有毛玻璃）
                if let item = quickLookItem, showQuickLook {
                    QuickLookCardView(item: item, imageLoader: imageLoader)
                        .transition(.scale.combined(with: .opacity))
                        .zIndex(10)
                }
            }
            .onAppear {
                canvasSize = geo.size
                initializeFloatingItems()
                startAnimation()
            }
            .onChange(of: geo.size) { _, newSize in
                canvasSize = newSize
                updateBoundariesForItems()
            }
            .onDisappear { stopAnimation() }
        }
    }

    // MARK: - 初始化漂浮物件
    private func initializeFloatingItems() {
        guard !items.isEmpty else { return }

        var newFloatingItems: [FloatingItem] = []
        for item in items {
            let sizeVariation = CGFloat.random(in: 0.8...1.3)
            let size = min(max(baseItemSize * sizeVariation, minItemSize), maxItemSize)

            let position = CGPoint(
                x: CGFloat.random(in: edgePadding + size/2...canvasSize.width - edgePadding - size/2),
                y: CGFloat.random(in: edgePadding + size/2...canvasSize.height - edgePadding - size/2)
            )

            let velocity = CGPoint(x: CGFloat.random(in: -0.5...0.5),
                                   y: CGFloat.random(in: -0.5...0.5))

            let rotation = Double.random(in: 0...360)
            let rotationSpeed = Double.random(in: -2...2)

            newFloatingItems.append(FloatingItem(
                item: item,
                position: position,
                velocity: velocity,
                size: size,
                rotation: rotation,
                rotationSpeed: rotationSpeed
            ))
        }

        withAnimation(.easeInOut(duration: 0.5)) {
            floatingItems = newFloatingItems
        }
    }

    // MARK: - 開始 / 暫停 / 停止動畫
    private func startAnimation() {
        guard animationTimer == nil else { return }
        animationTimer = Timer.scheduledTimer(withTimeInterval: 1/60, repeats: true) { _ in
            updateFloatingItems()
        }
    }
    private func pauseAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
    }
    private func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
    }

    // MARK: - 更新物件位置
    private func updateFloatingItems() {
        withAnimation(.linear(duration: 1/60)) {
            for index in floatingItems.indices {
                var item = floatingItems[index]

                item.position.x += item.velocity.x
                item.position.y += item.velocity.y

                let half = item.size / 2
                let damping: CGFloat = 0.85

                if item.position.x - half <= edgePadding {
                    item.position.x = edgePadding + half
                    item.velocity.x = abs(item.velocity.x) * damping
                } else if item.position.x + half >= canvasSize.width - edgePadding {
                    item.position.x = canvasSize.width - edgePadding - half
                    item.velocity.x = -abs(item.velocity.x) * damping
                }

                if item.position.y - half <= edgePadding {
                    item.position.y = edgePadding + half
                    item.velocity.y = abs(item.velocity.y) * damping
                } else if item.position.y + half >= canvasSize.height - edgePadding {
                    item.position.y = canvasSize.height - edgePadding - half
                    item.velocity.y = -abs(item.velocity.y) * damping
                }

                item.velocity.x *= 0.9995
                item.velocity.y *= 0.9995
                if abs(item.velocity.x) < 0.05 && abs(item.velocity.y) < 0.05 {
                    item.velocity.x += CGFloat.random(in: -0.1...0.1)
                    item.velocity.y += CGFloat.random(in: -0.1...0.1)
                }

                floatingItems[index] = item
            }
        }
    }

    // MARK: - 更新邊界（螢幕尺寸改變時）
    private func updateBoundariesForItems() {
        for index in floatingItems.indices {
            let item = floatingItems[index]
            let half = item.size / 2
            let clampedX = max(edgePadding + half, min(item.position.x, canvasSize.width - edgePadding - half))
            let clampedY = max(edgePadding + half, min(item.position.y, canvasSize.height - edgePadding - half))
            floatingItems[index].position = CGPoint(x: clampedX, y: clampedY)
        }
    }
}

// MARK: - 漂浮物件數據結構
struct FloatingItem {
    let item: Item
    var position: CGPoint
    var velocity: CGPoint
    let size: CGFloat
    var rotation: Double
    let rotationSpeed: Double
}

// MARK: - 物件 Cell（按住顯示 Quick Look）
struct CanvasItemCell: View {
    let item: Item
    let imageLoader: ImageMemoryCache
    let size: CGFloat
    let rotation: Double

    let onHoldBegan: (Item) -> Void
    let onHoldEnded: () -> Void

    @State private var image: UIImage?
    @State private var isPressed = false
    @State private var quickLookActive = false   // 目前是否正在顯示 QuickLook

    // 手感參數
    private let holdThreshold: Double = 0.05
    private let maxMove: CGFloat = 32

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.systemGray6))
                    .overlay(ProgressView().scaleEffect(0.8))
                    .frame(width: size, height: size)
            }
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(rotation))
        .scaleEffect(isPressed ? 0.94 : 1.0)
        .animation(.spring(response: 0.22, dampingFraction: 0.75), value: isPressed)

        // 輕點＝微幅彈跳 + 輕觸震動（不會開預覽）
        .onTapGesture {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.16, dampingFraction: 0.55)) {
                isPressed = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
                withAnimation(.spring(response: 0.24, dampingFraction: 0.8)) {
                    isPressed = false
                }
            }
        }

        // 長按才顯示 QuickLook；放手關閉
        .onLongPressGesture(
            minimumDuration: holdThreshold,
            maximumDistance: maxMove,
            pressing: { inProgress in
                // 按住時有壓下的視覺回饋
                withAnimation(.spring(response: 0.18, dampingFraction: 0.8)) {
                    isPressed = inProgress
                }
                // 放手時，如果目前有顯示 QuickLook，就關閉
                if !inProgress, quickLookActive {
                    quickLookActive = false
                    onHoldEnded()
                }
            },
            perform: {
                // ✅ 只有真正觸發長按時才顯示預覽
                quickLookActive = true
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onHoldBegan(item)
            }
        )

        .onAppear {
            imageLoader.loadImage(named: item.imageName) { img in
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        self.image = img
                    }
                }
            }
        }
    }
}


// MARK: - Quick Look 卡片（毛玻璃）
struct QuickLookCardView: View {
    let item: Item
    let imageLoader: ImageMemoryCache

    @State private var image: UIImage?
    @State private var scale: CGFloat = 0.9
    @State private var opacity: Double = 0.0

    var body: some View {
        GeometryReader { geo in
            // 只渲染一個置中的卡片（沒有全屏遮罩）
            VStack {
                ZStack {
                    // 毛玻璃卡片背景（模糊的是「卡片後方」的內容）
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                        )

                    // 圖片內容
                    Group {
                        if let image {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .padding(20)
                                .frame(maxWidth: 560, maxHeight: 560)
                        } else {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.white.opacity(0.12))
                                .overlay(ProgressView())
                                .frame(width: 260, height: 260)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                }
                .frame(width: min(geo.size.width - 40, 600),
                       height: min(geo.size.width - 40, 600))
                .scaleEffect(scale)
                .opacity(opacity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .allowsHitTesting(false) // 不攔截觸控：放手就交還給 Cell 觸發關閉
        .onAppear {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                scale = 1
                opacity = 1
            }
            imageLoader.loadImage(named: item.imageName) { img in
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        self.image = img
                    }
                }
            }
        }
    }
}
