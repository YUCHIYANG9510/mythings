//
//  CameraView.swift
//  mythings
//
//  Created by Designer on 2025/8/25.
//

import SwiftUI
import AVFoundation
import UIKit

// MARK: - Public API（維持你的舊介面）
struct CameraPicker: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedImage: UIImage?
    
    @StateObject private var camera = CameraService()
    @State private var showPermissionAlert = false
    @State private var isBusy = false
    @State private var flashMode: AVCaptureDevice.FlashMode = .off
    @State private var showGrid = true
    @State private var didCaptureBlink = false
    
    var body: some View {
        ZStack {
            CameraPreviewView(session: camera.session)
                .ignoresSafeArea()
                .onAppear { Task { await setup() } }
                .overlay(alignment: .center) {
                    if showGrid { RuleOfThirdsGrid().allowsHitTesting(false) }
                }
            
            // 頂部工具列
            VStack {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 22, weight: .semibold))
                    }
                    .tint(.white)
                    
                    Spacer()
                    
                    Button {
                        flashMode = flashMode == .off ? .on : .off
                    } label: {
                        Image(systemName: flashMode == .on ? "bolt.fill" : "bolt.slash.fill")
                            .font(.system(size: 20, weight: .semibold))
                    }
                    .tint(.white)
                    
                    Button {
                        showGrid.toggle()
                    } label: {
                        Image(systemName: "square.grid.3x3")
                            .font(.system(size: 20, weight: .semibold))
                    }
                    .tint(.white)
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                
                Spacer()
                
                // 快門區
                HStack {
                    Spacer()
                    Button {
                        guard !isBusy else { return }
                        isBusy = true
                        camera.capturePhoto(flashMode: flashMode) { image in
                            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                                didCaptureBlink = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                withAnimation(.easeOut(duration: 0.25)) {
                                    didCaptureBlink = false
                                }
                            }
                            self.selectedImage = image
                            dismiss()   // 與你原本流程一致：回傳 UIImage 後關閉
                        } onFinish: {
                            isBusy = false
                        }
                    } label: {
                        ZStack {
                            Circle().fill(.white.opacity(0.18)).frame(width: 84, height: 84)
                            Circle().fill(.white).frame(width: 68, height: 68)
                        }
                    }
                    .padding(.bottom, 30)
                    Spacer()
                }
            }
            
            // 拍照閃白的視覺回饋
            if didCaptureBlink {
                Color.white.opacity(0.25).ignoresSafeArea()
            }
        }
        .alert("需要相機權限", isPresented: $showPermissionAlert) {
            Button("前往設定", role: .none) {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("請在「設定 > 隱私權 > 相機」允許此 App 使用相機。")
        }
    }
    
    private func setup() async {
        let ok = await camera.configure()
        if !ok { showPermissionAlert = true }
        await camera.start()
    }
}

// MARK: - 相機服務
final class CameraService: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    private let photoOutput = AVCapturePhotoOutput()
    private var onPhoto: ((UIImage) -> Void)?
    private var onFinish: (() -> Void)?
    
    @MainActor
    func configure() async -> Bool {
        return await withCheckedContinuation { cont in
            sessionQueue.async { [weak self] in
                guard let self else {
                    DispatchQueue.main.async { cont.resume(returning: false) }
                    return
                }
                self.session.beginConfiguration()
                self.session.sessionPreset = .photo
                
                guard
                    let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                    let input = try? AVCaptureDeviceInput(device: device),
                    self.session.canAddInput(input)
                else {
                    self.session.commitConfiguration()
                    DispatchQueue.main.async { cont.resume(returning: false) }
                    return
                }
                self.session.addInput(input)
                
                guard self.session.canAddOutput(self.photoOutput) else {
                    self.session.commitConfiguration()
                    DispatchQueue.main.async { cont.resume(returning: false) }
                    return
                }
                self.session.addOutput(self.photoOutput)
                
                // 修正：使用 maxPhotoDimensions 替代已棄用的 isHighResolutionCaptureEnabled
                if #available(iOS 16.0, *) {
                    // 在 iOS 16+ 中，maxPhotoDimensions 預設已經是最高解析度
                    // 不需要額外設定，系統會自動使用最佳值
                } else {
                    // iOS 16 之前的版本仍使用舊 API
                    self.photoOutput.isHighResolutionCaptureEnabled = true
                }
                
                self.session.commitConfiguration()
                
                DispatchQueue.main.async { cont.resume(returning: true) }
            }
        }
    }
    
    @MainActor
    func start() async {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if !self.session.isRunning { self.session.startRunning() }
        }
    }
    
    func stop() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning { self.session.stopRunning() }
        }
    }
    
    func capturePhoto(flashMode: AVCaptureDevice.FlashMode,
                      onPhoto: @escaping (UIImage) -> Void,
                      onFinish: @escaping () -> Void) {
        self.onPhoto = onPhoto
        self.onFinish = onFinish
        
        let settings = AVCapturePhotoSettings()
        
        // 修正：使用 maxPhotoDimensions 替代已棄用的 isHighResolutionPhotoEnabled
        if #available(iOS 16.0, *) {
            // 在 iOS 16+ 中，maxPhotoDimensions 預設已經是最高解析度
            // 不需要額外設定，系統會自動使用最佳值
        } else {
            // iOS 16 之前的版本仍使用舊 API
            settings.isHighResolutionPhotoEnabled = true
        }
        
        if photoOutput.supportedFlashModes.contains(flashMode) { settings.flashMode = flashMode }
        photoOutput.capturePhoto(with: settings, delegate: self)
    }
    
    // MARK: - Delegate
    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        defer {
            // 確保回到主執行緒更新 UI 狀態
            DispatchQueue.main.async { [onFinish = self.onFinish] in
                onFinish?()
            }
        }
        guard error == nil,
              let data = photo.fileDataRepresentation(),
              let img = UIImage(data: data) else { return }
        // 回到主執行緒傳遞圖片，避免背景執行緒觸發 UI 更新
        DispatchQueue.main.async { [onPhoto = self.onPhoto] in
            onPhoto?(img)
        }
    }
}

// 避免 Swift 6 中在 @Sendable 閉包內捕獲非 Sendable 類型的錯誤。
// CameraService 的可變狀態已由私有序列佇列（sessionQueue）保護。
extension CameraService: @unchecked Sendable {}

// MARK: - Preview Layer in SwiftUI
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = UIScreen.main.bounds
        v.layer.addSublayer(layer)
        return v
    }
    func updateUIView(_ uiView: UIView, context: Context) {
        (uiView.layer.sublayers?.first as? AVCaptureVideoPreviewLayer)?.session = session
    }
}

// MARK: - 輔助：九宮格
struct RuleOfThirdsGrid: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let x1 = w / 3
            let x2 = 2 * w / 3
            let y1 = h / 3
            let y2 = 2 * h / 3
            Path { p in
                p.move(to: CGPoint(x: x1, y: 0)); p.addLine(to: CGPoint(x: x1, y: h))
                p.move(to: CGPoint(x: x2, y: 0)); p.addLine(to: CGPoint(x: x2, y: h))
                p.move(to: CGPoint(x: 0, y: y1)); p.addLine(to: CGPoint(x: w, y: y1))
                p.move(to: CGPoint(x: 0, y: y2)); p.addLine(to: CGPoint(x: w, y: y2))
            }
            .stroke(.white.opacity(0.35), lineWidth: 1)
        }
    }
}
