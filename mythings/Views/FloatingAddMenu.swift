//
//  FloatingAddMenu.swift
//  mythings
//
//  Created by Designer on 2025/8/15.
//

import SwiftUI

struct FloatingAddMenu: View {
    @Binding var isOpen: Bool
    @Binding var showCamera: Bool
    @Binding var showImagePicker: Bool
    @Environment(\.colorScheme) private var colorScheme
    @State private var showFirstButton = false
    @State private var showSecondButton = false

    var body: some View {
        ZStack {
            if isOpen {
                Color.black.opacity(0.25)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture { toggle(false) }
            }
            
            VStack {
                Spacer()
                
                // 展開的選項（居中顯示）
                if isOpen {
                    HStack {
                        Spacer()
                        HStack(spacing: 12) {
                            CircularIconButton(system: "photo.on.rectangle", label: "相簿", isVisible: showFirstButton) {
                                toggle(false); UIImpactFeedbackGenerator(style: .light).impactOccurred(); showImagePicker = true
                            }
                            CircularIconButton(system: "camera.fill", label: "拍照", isVisible: showSecondButton) {
                                toggle(false); UIImpactFeedbackGenerator(style: .light).impactOccurred(); showCamera = true
                            }
                        }
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .move(edge: .bottom).combined(with: .opacity)
                        ))
                        Spacer()
                    }
                    .padding(.bottom, 16)
                }
                
                // + 按鈕（居中）
                HStack {
                    Spacer()
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        toggle(!isOpen)
                    } label: {
                        Image(systemName: "plus")
                            .font(.title2.bold())
                            .frame(width: 60, height: 60)
                            .foregroundStyle(colorScheme == .dark ? .black : .white)
                            .background(colorScheme == .dark ? Color.white : Color.black)
                            .clipShape(Circle())
                            .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
                            .scaleEffect(isOpen ? 0.9 : 1.0)
                            .rotationEffect(.degrees(isOpen ? 45 : 0))
                    }
                    Spacer()
                }
                
                Spacer().frame(height: 30)
            }
        }
        .onChange(of: isOpen) { _, newValue in
            if newValue {
                showFirstButton = false; showSecondButton = false
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7).delay(0.1)) { showFirstButton = true }
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7).delay(0.2)) { showSecondButton = true }
            } else {
                showFirstButton = false; showSecondButton = false
            }
        }
    };    private func toggle(_ open: Bool) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { isOpen = open }
    }
}

private struct CircularIconButton: View {
    let system: String
    let label: String
    let isVisible: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var isPressed = false
    var body: some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.title3.bold())
                .frame(width: 60, height: 60)
                .foregroundStyle(colorScheme == .dark ? Color.white : Color.black)
                .background(colorScheme == .dark ? Color.black : Color.white)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
        }
        .accessibilityLabel(Text(label))
        .scaleEffect(isVisible ? (isPressed ? 0.9 : 1.0) : 0.1)
        .opacity(isVisible ? 1.0 : 0.0)
        .animation(.spring(response: 0.4, dampingFraction: 0.6), value: isVisible)
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: isPressed)
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
    }
}
