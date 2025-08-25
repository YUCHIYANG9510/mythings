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

struct EditPhotoView: View {
    let original: UIImage
    /// 傳入的去背函式（由外部提供，內部只負責呼叫）
    let removeBG: (UIImage) async -> UIImage?
    /// 完成後回傳「最後圖」與是否採用去背（用於更新使用者偏好）
    let onDone: (UIImage, Bool) -> Void
    /// 取消編輯時回呼（外層負責 dismiss 與清理）
    let onCancel: () -> Void
    /// 初始預設選擇（從 AppStorage 讀到）
    let initialPrefRemoveBG: Bool

    @State private var mode: BackgroundMode
    @State private var cutout: UIImage?
    @State private var isProcessing = false
    @State private var rememberChoice = false        // 「記住我的選擇」開關

    init(
        original: UIImage,
        initialPrefRemoveBG: Bool,
        removeBG: @escaping (UIImage) async -> UIImage?,
        onDone: @escaping (UIImage, Bool) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.original = original
        self.initialPrefRemoveBG = initialPrefRemoveBG
        self.removeBG = removeBG
        self.onDone = onDone
        self.onCancel = onCancel
        _mode = State(initialValue: initialPrefRemoveBG ? .cutout : .original)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                // 預覽區
                ZStack {
                    Color(.systemGray6)
                    currentPreview
                        .resizable()
                        .scaledToFit()
                        .padding()
                        .overlay {
                            if isProcessing {
                                ProgressView("Removing background...")
                                    .padding(12)
                                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                            }
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

                    Toggle("Remember my choice", isOn: $rememberChoice)
                        .tint(.primary)
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
                    }
                    .buttonStyle(.bordered)

                    Button {
                        let useCut = (mode == .cutout)
                        let finalImage = useCut ? (cutout ?? original) : original
                        // 若有勾選記住偏好，新的偏好 = 目前選擇；否則維持原偏好
                        let newPref = rememberChoice ? useCut : initialPrefRemoveBG
                        onDone(finalImage, newPref)
                    } label: {
                        Text("Use Photo")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            .padding()
            .navigationTitle("Edit Photo")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: mode) {
                if mode == .cutout, cutout == nil {
                    Task { await ensureCutout() }
                }
            }

            .task {
                // 若預設就是 cutout，先算一次並快取
                if mode == .cutout, cutout == nil {
                    await ensureCutout()
                }
            }
        }
    }

    private var currentPreview: Image {
        if mode == .original { return Image(uiImage: original) }
        if let cutout { return Image(uiImage: cutout) }
        return Image(uiImage: original) // cutout 還沒好時先顯示原圖 + loading
    }

    @MainActor
    private func ensureCutout() async {
        guard !isProcessing else { return }
        isProcessing = true
        let result = await removeBG(original)
        cutout = result ?? cutout
        isProcessing = false
    }
}
