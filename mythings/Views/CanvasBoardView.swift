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
    private let edgePadding: CGFloat = 10
    private let minItemSize: CGFloat = 60
    private let maxItemSize: CGFloat = 120
    private let baseItemSize: CGFloat = 90

    // 點擊預覽
    @State private var previewing: Item?
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
                        rotation: floatingItem.rotation
                    ) { tapped in
                        // 點擊時暫停動畫
                        pauseAnimation()
                        previewing = tapped
                    }
                    .position(floatingItem.position)
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
            .onDisappear {
                stopAnimation()
            }
            .sheet(item: $previewing) { item in
                CanvasPreview(item: item, imageLoader: imageLoader)
                    .presentationDetents([.medium, .large])
                    .presentationCornerRadius(24)
                    .onDisappear {
                        // 預覽關閉後恢復動畫
                        startAnimation()
                    }
            }
        }
    }

    // MARK: - 初始化漂浮物件
    private func initializeFloatingItems() {
        guard !items.isEmpty else { return }
        
        var newFloatingItems: [FloatingItem] = []
        
        for item in items {
            // 隨機大小
            let sizeVariation = CGFloat.random(in: 0.8...1.3)
            let size = min(max(baseItemSize * sizeVariation, minItemSize), maxItemSize)
            
            // 隨機初始位置
            let position = CGPoint(
                x: CGFloat.random(in: edgePadding + size/2...canvasSize.width - edgePadding - size/2),
                y: CGFloat.random(in: edgePadding + size/2...canvasSize.height - edgePadding - size/2)
            )
            
            // 隨機初始速度（超級緩慢優雅）
            let velocity = CGPoint(
                x: CGFloat.random(in: -0.5...0.5),
                y: CGFloat.random(in: -0.5...0.5)
            )
            
            // 隨機旋轉和旋轉速度
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
    
    // MARK: - 開始動畫
    private func startAnimation() {
        guard animationTimer == nil else { return }
        
        animationTimer = Timer.scheduledTimer(withTimeInterval: 1/60, repeats: true) { _ in
            updateFloatingItems()
        }
    }
    
    // MARK: - 暫停動畫
    private func pauseAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
    }
    
    // MARK: - 停止動畫
    private func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
    }
    
    // MARK: - 更新物件位置
    private func updateFloatingItems() {
        withAnimation(.linear(duration: 1/60)) {
            for index in floatingItems.indices {
                var item = floatingItems[index]
                
                // 更新位置
                item.position.x += item.velocity.x
                item.position.y += item.velocity.y
                
                // 旋轉保持不變（不自動旋轉）
                
                // 邊界碰撞檢測與反彈（物理性反彈）
                let halfSize = item.size / 2
                let dampingFactor: CGFloat = 0.85  // 反彈時的能量衰減
                
                // 左右邊界
                if item.position.x - halfSize <= edgePadding {
                    item.position.x = edgePadding + halfSize
                    item.velocity.x = abs(item.velocity.x) * dampingFactor // 反彈衰減
                } else if item.position.x + halfSize >= canvasSize.width - edgePadding {
                    item.position.x = canvasSize.width - edgePadding - halfSize
                    item.velocity.x = -abs(item.velocity.x) * dampingFactor // 反彈衰減
                }
                
                // 上下邊界
                if item.position.y - halfSize <= edgePadding {
                    item.position.y = edgePadding + halfSize
                    item.velocity.y = abs(item.velocity.y) * dampingFactor // 反彈衰減
                } else if item.position.y + halfSize >= canvasSize.height - edgePadding {
                    item.position.y = canvasSize.height - edgePadding - halfSize
                    item.velocity.y = -abs(item.velocity.y) * dampingFactor // 反彈衰減
                }
                
                // 添加微小的空氣阻力，讓動畫更自然
                item.velocity.x *= 0.9995
                item.velocity.y *= 0.9995
                
                // 添加微小的隨機擾動，避免物件完全靜止
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
            let halfSize = item.size / 2
            
            // 確保物件在新的邊界內
            let clampedX = max(edgePadding + halfSize,
                              min(item.position.x, canvasSize.width - edgePadding - halfSize))
            let clampedY = max(edgePadding + halfSize,
                              min(item.position.y, canvasSize.height - edgePadding - halfSize))
            
            floatingItems[index].position = CGPoint(x: clampedX, y: clampedY)
        }
    }
}

// MARK: - 漂浮物件數據結構
struct FloatingItem {
    let item: Item
    var position: CGPoint
    var velocity: CGPoint  // 移動速度
    let size: CGFloat
    var rotation: Double
    let rotationSpeed: Double  // 旋轉速度
}

// MARK: - 改進的物件格子（支持可變大小和旋轉）
struct CanvasItemCell: View {
    let item: Item
    let imageLoader: ImageMemoryCache
    let size: CGFloat
    let rotation: Double
    @State private var image: UIImage?
    @State private var isPressed = false
    let onTap: (Item) -> Void

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
                    .overlay(
                        ProgressView().scaleEffect(0.8)
                    )
                    .frame(width: size, height: size)
            }
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(rotation))
        .scaleEffect(isPressed ? 0.9 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
        .onTapGesture {
            // 輕微的點擊回饋
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()
            onTap(item)
        }
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
