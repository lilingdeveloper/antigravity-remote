//
//  QRScannerView.swift
//  AntigravityRemote
//
//  原生 AVFoundation 二维码扫描器:
//  支持扫描 Mac 端生成的配对二维码 (agyremote://pair?... 或 http://100.x.y.z:8789 或 JSON)
//  一键完成 Tailscale 节点绑定、AuthKey 自动登录与 Mac 主机连接。
//

import SwiftUI
import AVFoundation
import UIKit

public struct QRScannerSheet: View {
    public var onScanned: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var manualInput: String = ""
    @State private var cameraError: String?

    public init(onScanned: @escaping (String) -> Void) {
        self.onScanned = onScanned
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                ZStack {
                    QRScannerRepresentable(
                        onCodeScanned: { code in
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                            onScanned(code)
                            dismiss()
                        },
                        onError: { err in
                            cameraError = err
                        }
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.blue.opacity(0.8), lineWidth: 2)
                    )

                    // 取景框指示
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(style: StrokeStyle(lineWidth: 2.5, dash: [12, 8]))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(width: 220, height: 220)

                    if let cameraError {
                        VStack(spacing: 8) {
                            Image(systemName: "camera.fill")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                            Text(cameraError)
                                .font(.callout)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 20)
                        }
                        .padding(20)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 340)
                .padding(.horizontal, 16)

                VStack(spacing: 6) {
                    Text("将取景框对准 Mac 上的配对二维码")
                        .font(.headline)
                    Text("在 Mac 浏览器打开 http://127.0.0.1:8789/qr 或运行 ./show-qr.sh 即可显示配对二维码")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                Divider()
                    .padding(.horizontal, 16)

                VStack(alignment: .leading, spacing: 8) {
                    Text("或者直接粘贴配对链接 / Tailscale IP：")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    HStack {
                        TextField("agyremote://pair?... 或 100.x.y.z", text: $manualInput)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textFieldStyle(.roundedBorder)
                        Button("连接") {
                            let trimmed = manualInput.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty else { return }
                            onScanned(trimmed)
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(manualInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .padding(.horizontal, 16)

                Spacer()
            }
            .padding(.top, 12)
            .navigationTitle("扫码建立 Tailscale 连接")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}

private struct QRScannerRepresentable: UIViewControllerRepresentable {
    var onCodeScanned: (String) -> Void
    var onError: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerViewController {
        let vc = ScannerViewController()
        vc.onCodeScanned = onCodeScanned
        vc.onError = onError
        return vc
    }

    func updateUIViewController(_ uiViewController: ScannerViewController, context: Context) {}

    final class ScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
        var onCodeScanned: ((String) -> Void)?
        var onError: ((String) -> Void)?

        private let session = AVCaptureSession()
        private var previewLayer: AVCaptureVideoPreviewLayer?
        private var hasScanned = false

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .black
            setupCamera()
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            previewLayer?.frame = view.bounds
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            if session.isRunning {
                session.stopRunning()
            }
        }

        private func setupCamera() {
            guard let device = AVCaptureDevice.default(for: .video) else {
                onError?("当前设备无可用相机，请使用下方输入框手动粘贴配对码")
                return
            }
            do {
                let input = try AVCaptureDeviceInput(device: device)
                if session.canAddInput(input) {
                    session.addInput(input)
                }
                let output = AVCaptureMetadataOutput()
                if session.canAddOutput(output) {
                    session.addOutput(output)
                    output.setMetadataObjectsDelegate(self, queue: .main)
                    output.metadataObjectTypes = [.qr]
                }
                let layer = AVCaptureVideoPreviewLayer(session: session)
                layer.videoGravity = .resizeAspectFill
                layer.frame = view.bounds
                view.layer.addSublayer(layer)
                self.previewLayer = layer

                DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                    self?.session.startRunning()
                }
            } catch {
                onError?("无法访问相机：请在系统设置中允许 AGY Remote 使用相机")
            }
        }

        func metadataOutput(
            _ output: AVCaptureMetadataOutput,
            didOutput metadataObjects: [AVMetadataObject],
            from connection: AVCaptureConnection
        ) {
            guard !hasScanned,
                  let obj = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                  let str = obj.stringValue,
                  !str.isEmpty else { return }
            hasScanned = true
            session.stopRunning()
            onCodeScanned?(str)
        }
    }
}
