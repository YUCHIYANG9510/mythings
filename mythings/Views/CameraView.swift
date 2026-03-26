//
//  CameraView.swift
//  mythings
//
//  Created by Designer on 2025/8/25.
//

import SwiftUI
import AVFoundation
import UIKit

// MARK: - Layout Constants
private enum Layout {
    static let shutterSize: CGFloat = 68
    static let shutterRingSize: CGFloat = 84
    static let shutterBottomPadding: CGFloat = 30
    static let toolbarHorizontalPadding: CGFloat = 16
    static let toolbarTopPadding: CGFloat = 14
    static let iconSize: CGFloat = 22
    static let smallIconSize: CGFloat = 20
    static let captureBlinkDuration: TimeInterval = 0.15
    static let captureBlinkFadeOut: TimeInterval = 0.25
    static let captureSpringResponse: Double = 0.35
    static let captureSpringDamping: Double = 0.7
}

// MARK: - Public API
struct CameraPicker: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedImage: UIImage?
    
    @StateObject private var camera = CameraService()
    @AppStorage("cameraFlashMode") private var flashModeRawValue: Int = 0
    @AppStorage("cameraShowGrid") private var showGrid: Bool = true
    
    @State private var showPermissionAlert = false
    @State private var isBusy = false
    @State private var didCaptureBlink = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var cameraPosition: AVCaptureDevice.Position = .back
    
    private var flashMode: AVCaptureDevice.FlashMode {
        get { AVCaptureDevice.FlashMode(rawValue: flashModeRawValue) ?? .off }
        set { flashModeRawValue = newValue.rawValue }
    }
    
    var body: some View {
        ZStack {
            CameraPreviewView(session: camera.session)
                .ignoresSafeArea()
                .onAppear { Task { await setup() } }
                .onDisappear { camera.stop() }
                .overlay(alignment: .center) {
                    if showGrid { RuleOfThirdsGrid().allowsHitTesting(false) }
                }
            
            // 頂部工具列
            VStack {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: Layout.iconSize, weight: .semibold))
                    }
                    .tint(.white)
                    .accessibilityLabel("關閉相機")
                    
                    Spacer()
                    
                    Button {
                        Task {
                            await switchCamera()
                        }
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath.camera")
                            .font(.system(size: Layout.smallIconSize, weight: .semibold))
                    }
                    .tint(.white)
                    .accessibilityLabel("切換相機")
                    
                    Button {
                        flashModeRawValue = flashMode == .off ? AVCaptureDevice.FlashMode.on.rawValue : AVCaptureDevice.FlashMode.off.rawValue
                    } label: {
                        Image(systemName: flashMode == .on ? "bolt.fill" : "bolt.slash.fill")
                            .font(.system(size: Layout.smallIconSize, weight: .semibold))
                    }
                    .tint(.white)
                    .accessibilityLabel(flashMode == .on ? "關閉閃光燈" : "開啟閃光燈")
                    
                    Button {
                        showGrid.toggle()
                    } label: {
                        Image(systemName: "square.grid.3x3")
                            .font(.system(size: Layout.smallIconSize, weight: .semibold))
                    }
                    .tint(.white)
                    .accessibilityLabel(showGrid ? "隱藏格線" : "顯示格線")
                }
                .padding(.horizontal, Layout.toolbarHorizontalPadding)
                .padding(.top, Layout.toolbarTopPadding)
                
                Spacer()
                
                // 快門區
                HStack {
                    Spacer()
                    Button {
                        capturePhoto()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(.white.opacity(0.18))
                                .frame(width: Layout.shutterRingSize, height: Layout.shutterRingSize)
                            Circle()
                                .fill(.white)
                                .frame(width: Layout.shutterSize, height: Layout.shutterSize)
                        }
                    }
                    .disabled(isBusy)
                    .padding(.bottom, Layout.shutterBottomPadding)
                    .accessibilityLabel("拍照")
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
            Button("取消", role: .cancel) {
                dismiss()
            }
        } message: {
            Text("請在「設定 > 隱私權 > 相機」允許此 App 使用相機。")
        }
        .alert("錯誤", isPresented: $showError) {
            Button("確定", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "發生未知錯誤")
        }
    }
    
    // MARK: - Private Methods
    
    private func setup() async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        
        switch status {
        case .authorized:
            await configureAndStartCamera()
            
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if granted {
                await configureAndStartCamera()
            } else {
                await MainActor.run {
                    showPermissionAlert = true
                }
            }
            
        case .denied, .restricted:
            await MainActor.run {
                showPermissionAlert = true
            }
            
        @unknown default:
            await MainActor.run {
                showPermissionAlert = true
            }
        }
    }
    
    private func configureAndStartCamera() async {
        let ok = await camera.configure(position: cameraPosition)
        if ok {
            await camera.start()
        } else {
            await MainActor.run {
                errorMessage = "無法初始化相機"
                showError = true
            }
        }
    }
    
    private func switchCamera() async {
        cameraPosition = cameraPosition == .back ? .front : .back
        await camera.switchCamera(to: cameraPosition)
    }
    
    private func capturePhoto() {
        guard !isBusy else { return }
        isBusy = true
        
        camera.capturePhoto(flashMode: flashMode) { [weak camera] result in
            switch result {
            case .success(let image):
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                withAnimation(.spring(response: Layout.captureSpringResponse, 
                                    dampingFraction: Layout.captureSpringDamping)) {
                    didCaptureBlink = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + Layout.captureBlinkDuration) {
                    withAnimation(.easeOut(duration: Layout.captureBlinkFadeOut)) {
                        didCaptureBlink = false
                    }
                }
                selectedImage = image
                dismiss()
                
            case .failure(let error):
                errorMessage = error.localizedDescription
                showError = true
            }
            
            isBusy = false
        }
    }
}

// MARK: - Camera Errors

enum CameraError: LocalizedError {
    case configurationFailed
    case captureSessionNotRunning
    case photoProcessingFailed
    case noImageData
    
    var errorDescription: String? {
        switch self {
        case .configurationFailed:
            return "相機配置失敗"
        case .captureSessionNotRunning:
            return "相機未運作"
        case .photoProcessingFailed:
            return "照片處理失敗"
        case .noImageData:
            return "無法取得照片資料"
        }
    }
}

// MARK: - 相機服務
final class CameraService: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    private let photoOutput = AVCapturePhotoOutput()
    private var currentInput: AVCaptureDeviceInput?
    private var onPhotoResult: ((Result<UIImage, Error>) -> Void)?
    
    @MainActor
    func configure(position: AVCaptureDevice.Position = .back) async -> Bool {
        return await withCheckedContinuation { cont in
            sessionQueue.async { [weak self] in
                guard let self else {
                    DispatchQueue.main.async { cont.resume(returning: false) }
                    return
                }
                
                self.session.beginConfiguration()
                self.session.sessionPreset = .photo
                
                // Remove existing input if any
                if let currentInput = self.currentInput {
                    self.session.removeInput(currentInput)
                    self.currentInput = nil
                }
                
                guard
                    let device = AVCaptureDevice.default(.builtInWideAngleCamera, 
                                                        for: .video, 
                                                        position: position),
                    let input = try? AVCaptureDeviceInput(device: device),
                    self.session.canAddInput(input)
                else {
                    self.session.commitConfiguration()
                    DispatchQueue.main.async { cont.resume(returning: false) }
                    return
                }
                
                self.session.addInput(input)
                self.currentInput = input
                
                // Only add output if it hasn't been added yet
                if !self.session.outputs.contains(self.photoOutput) {
                    guard self.session.canAddOutput(self.photoOutput) else {
                        self.session.commitConfiguration()
                        DispatchQueue.main.async { cont.resume(returning: false) }
                        return
                    }
                    self.session.addOutput(self.photoOutput)
                }
                
                // 配置最高解析度照片
                if #available(iOS 16.0, *) {
                    // iOS 16+ 使用 maxPhotoDimensions
                    // 系統預設會使用設備支援的最大尺寸
                } else {
                    // iOS 16 之前使用舊 API
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
    
    @MainActor
    func switchCamera(to position: AVCaptureDevice.Position) async {
        stop()
        // Small delay to ensure session is fully stopped
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
        _ = await configure(position: position)
        await start()
    }
    
    func capturePhoto(flashMode: AVCaptureDevice.FlashMode,
                      completion: @escaping (Result<UIImage, Error>) -> Void) {
        self.onPhotoResult = completion
        
        let settings = AVCapturePhotoSettings()
        
        // 配置最高解析度照片
        if #available(iOS 16.0, *) {
            // iOS 16+ 可以明確設定最大尺寸
            let maxDimensions = photoOutput.maxPhotoDimensions
            if maxDimensions.width > 0 && maxDimensions.height > 0 {
                settings.maxPhotoDimensions = maxDimensions
            }
        } else {
            // iOS 16 之前使用舊 API
            settings.isHighResolutionPhotoEnabled = true
        }
        
        if photoOutput.supportedFlashModes.contains(flashMode) { 
            settings.flashMode = flashMode 
        }
        
        photoOutput.capturePhoto(with: settings, delegate: self)
    }
    
    // MARK: - Delegate
    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        // Capture the callback and clear it immediately to avoid retain cycles
        let callback = self.onPhotoResult
        self.onPhotoResult = nil
        
        // Check for errors first
        if let error = error {
            DispatchQueue.main.async {
                callback?(.failure(error))
            }
            return
        }
        
        // Try to get image data
        guard let data = photo.fileDataRepresentation() else {
            DispatchQueue.main.async {
                callback?(.failure(CameraError.noImageData))
            }
            return
        }
        
        // Try to create UIImage
        guard let img = UIImage(data: data) else {
            DispatchQueue.main.async {
                callback?(.failure(CameraError.photoProcessingFailed))
            }
            return
        }
        
        // Success - return image on main thread
        DispatchQueue.main.async {
            callback?(.success(img))
        }
    }
}

// 避免 Swift 6 中在 @Sendable 閉包內捕獲非 Sendable 類型的錯誤。
// CameraService 的可變狀態已由私有序列佇列（sessionQueue）保護，
// 所有 session 相關的操作都在 sessionQueue 上序列化執行，確保線程安全。
extension CameraService: @unchecked Sendable {}

// MARK: - Preview Layer in SwiftUI
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    
    func makeUIView(context: Context) -> PreviewContainer {
        PreviewContainer(session: session)
    }
    
    func updateUIView(_ uiView: PreviewContainer, context: Context) {
        uiView.previewLayer.session = session
    }
}

// Custom UIView container that properly handles layout changes
final class PreviewContainer: UIView {
    let previewLayer: AVCaptureVideoPreviewLayer
    
    init(session: AVCaptureSession) {
        self.previewLayer = AVCaptureVideoPreviewLayer(session: session)
        super.init(frame: .zero)
        previewLayer.videoGravity = .resizeAspectFill
        layer.addSublayer(previewLayer)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        // Update preview layer frame on any layout change (rotation, etc.)
        previewLayer.frame = bounds
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
