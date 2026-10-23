import SwiftUI

struct SealFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

extension View {
    func introLandingSeal(_ intro: IntroState) -> some View {
        opacity(intro.hidesMastheadSeal ? 0 : 1)
            .background(GeometryReader { geo in
                Color.clear.preference(key: SealFrameKey.self,
                                       value: geo.frame(in: .global))
            })
    }
}

@MainActor
final class IntroState: ObservableObject {
    static let space = "usufu.root"

    enum Phase {
        case waiting
        case showing
        case landing
        case switching
        case done
    }

    @Published private(set) var phase: Phase
    @Published var target: CGRect = .zero
    private var lockedTarget: CGRect?

    private var aim: CGRect { lockedTarget ?? target }

    private let breathe: Double = 0.6
    private let hold: Double = 1.1
    private let flight: Double = 1.1
    private let dissolve: Double = 0.9

    var isRunning: Bool { phase != .done }
    var hidesMastheadSeal: Bool { phase == .waiting || phase == .showing || phase == .landing }

    init(enabled: Bool = Motion.enabled) {
        phase = enabled ? .waiting : .done
    }

    func replay() {
        guard Motion.enabled else { return }
        replaying?.cancel()
        lockedTarget = nil
        phase = .waiting
        replaying = Task { await play(brief: true) }
    }

    private var replaying: Task<Void, Never>?

    func playOnce() async {
        guard !hasPlayed else { return }
        hasPlayed = true
        await play()
    }

    private var hasPlayed = false

    func play(brief: Bool = false) async {
        guard phase == .waiting else { return }
        let hold = brief ? 0.45 : self.hold
        let flight = brief ? 0.8 : self.flight

        try? await Task.sleep(nanoseconds: 40_000_000)
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: breathe)) { phase = .showing }

        try? await Task.sleep(nanoseconds: UInt64(hold * 1_000_000_000))
        guard !Task.isCancelled else { return }
        await settleTarget()
        lockedTarget = target
        withAnimation(.timingCurve(0.55, 0, 0.2, 1, duration: flight)) { phase = .landing }

        try? await Task.sleep(nanoseconds: UInt64(flight * 1_000_000_000))
        guard !Task.isCancelled else { return }
        phase = .done
    }

    private func settleTarget() async {
        var previous = target
        for _ in 0..<12 {
            try? await Task.sleep(nanoseconds: 40_000_000)
            if target == previous, target != .zero { return }
            previous = target
        }
    }

    func playLanguageSwitch() async {
        phase = .switching
        try? await Task.sleep(nanoseconds: 380_000_000)
        withAnimation(.easeOut(duration: 0.55)) { phase = .done }
    }

    func stage(_ phase: Phase) {
        self.phase = phase
        if phase == .landing { lockedTarget = target }
    }

    func skip() {
        withAnimation(.easeOut(duration: 0.2)) { phase = .done }
    }

    var backdropOpacity: Double { phase == .landing ? 0 : 1 }
    var sealOpacity: Double { phase == .waiting ? 0 : 1 }
    var sealTint: Color { phase == .landing ? Palette.navy : Palette.introSeal }
    var isSwitching: Bool { phase == .switching }

    func openingSize(in container: CGSize) -> CGFloat {
        min(300, container.width * 0.52)
    }

    func scale(in container: CGSize) -> CGFloat {
        if phase == .switching { return 0.82 }
        guard phase == .landing, aim != .zero else {
            return phase == .waiting ? 0.92 : 1
        }
        return aim.width / max(1, openingSize(in: container))
    }

    func landing(in curtain: CGRect) -> CGPoint {
        let middle = CGPoint(x: curtain.width / 2, y: curtain.height / 2)
        guard phase == .landing, aim != .zero else { return middle }

        return CGPoint(x: aim.midX - curtain.minX, y: aim.midY - curtain.minY)
    }

    var backdropAnimation: Animation { .easeOut(duration: dissolve) }
}

struct IntroCurtain: View {
    @ObservedObject var intro: IntroState

    var body: some View {
        GeometryReader { geo in
            let curtain = geo.frame(in: .global)
            ZStack {
                Palette.introBackdrop
                    .opacity(intro.backdropOpacity)
                    .animation(intro.backdropAnimation, value: intro.backdropOpacity)
                    .ignoresSafeArea()

                USUFUSeal(size: intro.openingSize(in: geo.size), tint: intro.sealTint)
                    .animation(intro.backdropAnimation, value: intro.backdropOpacity)
                    .scaleEffect(intro.scale(in: geo.size))
                    .position(intro.landing(in: curtain))
                    .opacity(intro.sealOpacity)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .opacity(intro.isSwitching ? 1 : 1)
            .contentShape(Rectangle())
            .onTapGesture { intro.skip() }
            .accessibilityHidden(true)
        }
        .transition(.opacity)
    }
}
