//
//  EditPhotoView.swift
//  mythings
//
//  Created by Designer on 2025/8/25.
//

import SwiftUI
import UIKit

enum BackgroundMode: String, CaseIterable, Equatable {
    case original   // 保留背景
    case cutout     // 去背
}

enum ProcessingState {
    case idle           // 沒有處理
    case starting       // 開始處理（顯示原圖）
    case separating     // 背景分離中
    case highlighting   // 主體強調
    case completed      // 處理完成
}

struct EditPhotoView: View {
    let original: UIImage
    /// 傳入的去背函式（由外部提供，內部只負責呼叫）
    let removeBG: (UIImage) async -> UIImage?
    /// 完成後回傳「最後圖」
    let onDone: (UIImage) -> Void
    /// 取消編輯時回呼（外層負責 dismiss 與清理）
    let onCancel: () -> Void

    @State private var mode: BackgroundMode
    @State private var cutout: UIImage?
    @State private var isProcessing = false

    // 動畫狀態
    @State private var processingState: ProcessingState = .idle
    @State private var backgroundOpacity: Double = 1.0
    @State private var subjectScale: Double = 1.0
    @State private var subjectBrightness: Double = 0.0
    @State private var showProcessingText = false

    init(
        original: UIImage,
        removeBG: @escaping (UIImage) async -> UIImage?,
        onDone: @escaping (UIImage) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.original = original
        self.removeBG = removeBG
        self.onDone = onDone
        self.onCancel = onCancel

        // ✅ 手動初始化 @State
        _mode = State(initialValue: .cutout) // 若想預設去背，改成 .cutout
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                // 預覽區 - 加入動畫效果
                ZStack {
                    Color(.systemGray6)

                    // 動畫預覽層
                    if mode == .cutout && processingState != .idle {
                        animatedPreviewLayer
                    } else {
                        // 一般預覽（無動畫）
                        currentPreview
                            .resizable()
                            .scaledToFit()
                            .padding()
                    }

                    // 處理中覆蓋層
                    if isProcessing && processingState != .idle {
                        VStack(spacing: 12) {
                            if showProcessingText {
                                ProgressView()
                                    .scaleEffect(1.2)
                                Text("Removing background...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(16)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .opacity(processingState == .starting ? 1 : 0)
                        .animation(.easeInOut(duration: 0.3), value: processingState)
                    } else if isProcessing {
                        // 傳統 loading（當沒有動畫時）
                        ProgressView("Removing background...")
                            .padding(12)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                .frame(maxHeight: 420)
                .clipShape(RoundedRectangle(cornerRadius: 16))

                // 切換區
                VStack(spacing: 12) {
                    Picker("Background", selection: $mode) {
                        Text("Keep background").tag(BackgroundMode.original)
                        Text("Remove background").tag(BackgroundMode.cutout)
                    }
                    .pickerStyle(.segmented)
                    .disabled(isProcessing)
                }
                .padding(.horizontal)

                Spacer()

                // 動作區
                HStack(spacing: 12) {
                    Button(role: .cancel) {
                        onCancel()
                    } label: {
                        Text("Cancel")
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isProcessing)

                    Button {
                        let useCut = (mode == .cutout)
                        let finalImage = useCut ? (cutout ?? original) : original
                        onDone(finalImage)
                    } label: {
                        Text("Use Photo")
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isProcessing)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            .padding()
            .navigationTitle("Edit Photo")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: mode) { oldValue, newValue in
                if newValue == .cutout, cutout == nil {
                    Task { await ensureCutoutWithAnimation() }
                } else if newValue == .original {
                    resetAnimationState()
                }
            }


            .task {
                // 若預設就是 cutout，先算一次並快取
                if mode == .cutout, cutout == nil {
                    await ensureCutoutWithAnimation()
                }
            }
        }
    }

    private var currentPreview: Image {
        if mode == .original { return Image(uiImage: original) }
        if let cutout { return Image(uiImage: cutout) }
        return Image(uiImage: original) // cutout 還沒好時先顯示原圖 + loading
    }

    // 動畫預覽層
    @ViewBuilder
    private var animatedPreviewLayer: some View {
        ZStack {
            // 背景層（原圖）
            if processingState != .completed {
                Image(uiImage: original)
                    .resizable()
                    .scaledToFit()
                    .padding()
                    .opacity(backgroundOpacity)
                    .animation(.easeInOut(duration: 0.8), value: backgroundOpacity)
            }

            // 主體層（去背圖）
            if let cutout = cutout, processingState != .starting {
                Image(uiImage: cutout)
                    .resizable()
                    .scaledToFit()
                    .padding()
                    .scaleEffect(subjectScale)
                    .brightness(subjectBrightness)
                    .animation(.easeInOut(duration: 0.6), value: subjectScale)
                    .animation(.easeInOut(duration: 0.4), value: subjectBrightness)
            }
        }
    }

    @MainActor
    private func ensureCutoutWithAnimation() async {
        guard !isProcessing else { return }

        // 如果已經有 cutout，直接顯示不需要動畫
        if cutout != nil {
            processingState = .completed
            return
        }

        isProcessing = true

        // 開始動畫流程
        await performBackgroundRemovalAnimation()
    }

    @MainActor
    private func performBackgroundRemovalAnimation() async {
        // 第一階段：開始處理（0.5秒）
        processingState = .starting
        showProcessingText = true
        backgroundOpacity = 1.0
        subjectScale = 1.0
        subjectBrightness = 0.0

        // 稍微停頓，給人「正在分析」的感覺
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5秒

        // 開始實際的去背處理（背景執行）
        let backgroundTask = Task {
            await removeBG(original)
        }

        // 第二階段：背景分離動畫（0.8秒）
        processingState = .separating
        showProcessingText = false

        withAnimation(.easeInOut(duration: 0.8)) {
            backgroundOpacity = 0.1 // 背景淡出但不完全消失
        }

        try? await Task.sleep(nanoseconds: 400_000_000) // 0.4秒

        // 等待去背處理完成
        let result = await backgroundTask.value
        guard let processed = result else {
            // 處理失敗，回到原始狀態
            resetAnimationState()
            isProcessing = false
            return
        }

        cutout = processed

        // 第三階段：主體強調（0.6秒）
        processingState = .highlighting
        withAnimation(.easeInOut(duration: 0.4)) {
            backgroundOpacity = 0.0 // 背景完全消失
            subjectScale = 1.02     // 輕微放大
            subjectBrightness = 0.1 // 輕微提亮
        }

        try? await Task.sleep(nanoseconds: 300_000_000) // 0.3秒

        // 第四階段：完成狀態
        processingState = .completed

        withAnimation(.easeInOut(duration: 0.3)) {
            subjectScale = 1.0       // 回到正常大小
            subjectBrightness = 0.05 // 保持輕微提亮
        }

        // 輕微的完成回饋
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        isProcessing = false
    }

    private func resetAnimationState() {
        withAnimation(.easeInOut(duration: 0.3)) {
            processingState = .idle
            backgroundOpacity = 1.0
            subjectScale = 1.0
            subjectBrightness = 0.0
            showProcessingText = false
        }
    }

    // 若之後想走「無動畫快取 cutout」路徑，可保留這個方法（目前未被呼叫）
    @MainActor
    private func ensureCutout() async {
        guard !isProcessing else { return }
        isProcessing = true
        let result = await removeBG(original)
        cutout = result ?? cutout
        isProcessing = false
    }
}
