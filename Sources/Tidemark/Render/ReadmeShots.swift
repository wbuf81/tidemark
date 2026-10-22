import AppKit
import SwiftUI
import TidemarkCore

/// The pictures the README shows (`readme-*`), composed from the real views: the main window and the
/// first-run window drawn offscreen, the widget view itself, and a few plainly illustrative cards for
/// the macOS steps (drawn in Tidemark's palette, never copies of Apple's screens). `scripts/make-readme-images.sh`
/// copies them to docs/images. `readme-gif-N` are the five status frames of widget-status.gif.
enum ReadmeShots: ShotProvider {
    static var section: (title: String, about: String) {
        ("The README's pictures", "The pictures docs/images is made from (`readme-*`), at the demo moment: the hero (the window on Week with the widget beside a Dock), the first-run steps, the widget beside the Dock, three illustrative cards for the macOS steps, and one frame per Claude Code status for the status GIF (`readme-gif-0` to `-4`: Idle, Thinking, Working, Needs you, Done). `scripts/make-readme-images.sh` turns them into the files in docs/images.")
    }

    /// The statuses the GIF cycles through, in order.
    static let gifMoods: [CodeMood] = [.idle, .thinking, .tool, .permission, .done]

    @MainActor static func shots(_ stage: RenderStage) -> [Shot] {
        func shot(_ state: String, _ about: String, _ draw: @escaping @MainActor (Bool) -> NSBitmapImageRep?) -> Shot {
            Shot(screen: "readme", state: state, about: about, byLook: false, draw: draw)
        }
        func firstRun(_ step: Int, _ dark: Bool) -> NSBitmapImageRep? {
            let state = FirstRunState()
            state.step = step
            let window = FirstRunController.frame(model: stage.demo(stage.scenarios[0], week: stage.week()), state: state, actions: FirstRunActions())
            guard let image = Offscreen.image(of: window, dark: dark) else { return nil }
            return Renderer.picture(ReadmeFirstRun(window: image), dark: dark)
        }
        var shots: [Shot] = [
            shot("hero", "The README's hero: Tidemark's window on Week, and the widget beside a Dock, on a soft desktop gradient (880 points wide)") { dark in
                let window = MainWindowController.frame(model: stage.demo(stage.scenarios[0]), actions: .none, section: .week,
                                                        calendar: DemoCalendar.store(), now: { stage.now })
                guard let image = Offscreen.image(of: window, dark: dark) else { return nil }
                let widget = stage.mock([.personal], mood: .thinking, week: stage.mockWeek())
                return Renderer.picture(ReadmeHero(window: image, model: widget), dark: dark)
            },
            shot("step-reads", "First run, step 2 of 4: What Tidemark reads") { firstRun(2, $0) },
            shot("step-plan-limits", "First run, step 3 of 4: Show your plan's limits? with Anthropic's warning") { firstRun(3, $0) },
            shot("step-widget", "The widget beside the Dock") { dark in
                Renderer.picture(ReadmeDockScene(model: stage.mock([.personal], mood: .thinking, week: stage.mockWeek())), dark: dark)
            },
            shot("step-download", "Illustration: the Tidemark icon with an arrow into the Applications folder") { dark in
                Renderer.picture(ReadmeDownload(), dark: dark)
            },
            shot("step-not-opened", "Illustration: an alert-style card, \u{201C}Tidemark\u{201D} Not Opened, with Done and Move to Bin") { dark in
                Renderer.picture(ReadmeNotOpened(), dark: dark)
            },
            shot("step-open-anyway", "Illustration: a Privacy & Security row, \u{201C}Tidemark\u{201D} was blocked, with Open Anyway highlighted") { dark in
                Renderer.picture(ReadmeOpenAnyway(), dark: dark)
            },
        ]
        for (i, mood) in gifMoods.enumerated() {
            shots.append(shot("gif-\(i)", "Status GIF frame \(i + 1) of \(gifMoods.count): Claude Code \(mood.word), plan cards unchanged") { dark in
                let model = stage.mock([.personal, .harbor], mood: mood, week: stage.mockWeek())
                model.hooksConnected = true
                return Renderer.picture(RenderWidgetScene(model: model, width: 560), dark: dark)
            })
        }
        return shots
    }
}

// MARK: Pieces

/// The soft desktop behind the README's pictures: one gradient per look, never a real wallpaper.
struct ReadmeDesktop: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        LinearGradient(colors: scheme == .dark
                       ? [Color(red: 0.07, green: 0.10, blue: 0.15), Color(red: 0.09, green: 0.19, blue: 0.23), Color(red: 0.15, green: 0.13, blue: 0.20)]
                       : [Color(red: 0.90, green: 0.93, blue: 0.97), Color(red: 0.84, green: 0.90, blue: 0.95), Color(red: 0.96, green: 0.92, blue: 0.91)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// A drawn window picture, rounded and lifted off the desktop.
struct ReadmeWindowImage: View {
    let rep: NSBitmapImageRep
    let width: CGFloat
    init(_ rep: NSBitmapImageRep, width: CGFloat) { self.rep = rep; self.width = width }
    var body: some View {
        let ratio = CGFloat(rep.pixelsHigh) / CGFloat(rep.pixelsWide)
        Group {
            if let cg = rep.cgImage {
                Image(decorative: cg, scale: 1).resizable().interpolation(.high)
            } else { Color.clear }
        }
        .frame(width: width, height: width * ratio)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Palette.line, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.22), radius: 16, y: 8)
    }
}

/// A first-run step: the window itself, drawn as it is, on the desktop gradient.
struct ReadmeFirstRun: View {
    let window: NSBitmapImageRep
    var body: some View {
        ReadmeWindowImage(window, width: window.size.width)
            .padding(32)
            .background(ReadmeDesktop())
    }
}

/// Tidemark's icon (Resources/icon/tidemark.svg), drawn.
struct ReadmeIcon: View {
    var size: CGFloat
    var body: some View {
        let k = size / 824   // the svg's tile is 824 of 1024 units
        ZStack {
            RoundedRectangle(cornerRadius: 185 * k, style: .continuous)
                .fill(Color(red: 0.949, green: 0.965, blue: 0.976))
                .shadow(color: .black.opacity(0.22), radius: 6 * size / 100, y: 3 * size / 100)
            IconInner(size: size)
        }
        .frame(width: size, height: size)
    }
}

private struct IconInner: View {
    var size: CGFloat
    var body: some View {
        let u = size / 128   // the tile is 128 units across
        ZStack {
            Circle().stroke(Color(red: 0.835, green: 0.882, blue: 0.918), lineWidth: 14 * u).frame(width: 76 * u, height: 76 * u)
            Circle().trim(from: 0, to: 167.0 / 238.76)
                .rotation(.degrees(-90))
                .stroke(Color(red: 0.122, green: 0.498, blue: 0.651), style: StrokeStyle(lineWidth: 14 * u, lineCap: .round))
                .frame(width: 76 * u, height: 76 * u)
            Circle().fill(Color(red: 0.902, green: 0.937, blue: 0.961)).frame(width: 52 * u, height: 52 * u)
            ScaledShape(box: 128) { p in
                p.move(to: CGPoint(x: 38, y: 70))
                p.addCurve(to: CGPoint(x: 64, y: 70), control1: CGPoint(x: 46, y: 65), control2: CGPoint(x: 54, y: 75))
                p.addCurve(to: CGPoint(x: 90, y: 70), control1: CGPoint(x: 74, y: 65), control2: CGPoint(x: 82, y: 65))
                p.svgArc(to: CGPoint(x: 38, y: 70), r: 26)
                p.closeSubpath()
            }
            .fill(Color(red: 0.247, green: 0.655, blue: 0.788))
            .frame(width: size, height: size)
            .mask(Circle().frame(width: 52 * u, height: 52 * u))
        }
        .frame(width: size, height: size)
    }
}

/// A Dock: a rounded bar of plain app tiles and Tidemark's icon, drawn for the picture.
struct ReadmeDock: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let tiles: [[Color]] = [
            [Color(red: 0.36, green: 0.62, blue: 0.95), Color(red: 0.20, green: 0.40, blue: 0.85)],
            [Color(red: 0.95, green: 0.70, blue: 0.35), Color(red: 0.90, green: 0.45, blue: 0.25)],
            [Color(red: 0.45, green: 0.80, blue: 0.55), Color(red: 0.20, green: 0.60, blue: 0.40)],
            [Color(red: 0.70, green: 0.55, blue: 0.90), Color(red: 0.45, green: 0.35, blue: 0.80)],
            [Color(red: 0.62, green: 0.66, blue: 0.72), Color(red: 0.40, green: 0.44, blue: 0.50)],
        ]
        HStack(spacing: 9) {
            ForEach(Array(tiles.enumerated()), id: \.offset) { _, c in
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(LinearGradient(colors: c, startPoint: .top, endPoint: .bottom))
                    .frame(width: 44, height: 44)
            }
            ReadmeIcon(size: 44)
            Capsule().fill(Palette.dim.opacity(0.4)).frame(width: 1, height: 36)
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.80, green: 0.83, blue: 0.87), Color(red: 0.62, green: 0.67, blue: 0.73)], startPoint: .top, endPoint: .bottom))
                .frame(width: 44, height: 44)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(scheme == .dark ? Color.white.opacity(0.10) : Color.white.opacity(0.62)))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(scheme == .dark ? Color.white.opacity(0.16) : Color.white.opacity(0.85), lineWidth: 1))
    }
}

/// The Dock with the widget beside it, as the app lays them out.
struct ReadmeDockRow: View {
    @ObservedObject var model: AppModel
    var widgetWidth: CGFloat = 330
    var body: some View {
        HStack(spacing: 14) {
            ReadmeDock()
            WidgetView(model: model, actions: .none, width: widgetWidth).fixedSize()
        }
    }
}

struct ReadmeDockScene: View {
    @ObservedObject var model: AppModel
    var body: some View {
        ReadmeDockRow(model: model)
            .padding(.horizontal, 28).padding(.top, 52).padding(.bottom, 24)
            .background(ReadmeDesktop())
    }
}

struct ReadmeHero: View {
    let window: NSBitmapImageRep
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(spacing: 26) {
            ReadmeWindowImage(window, width: 690)
            ReadmeDockRow(model: model)
        }
        .frame(width: 880)
        .padding(.top, 34).padding(.bottom, 26)
        .background(ReadmeDesktop())
    }
}

/// "Illustration" in a corner, so no picture here is taken for a screenshot of macOS.
private struct IllustrationTag: View {
    var body: some View {
        Text("Illustration")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(Palette.dim)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Capsule().fill(Palette.tile.opacity(0.8)))
            .overlay(Capsule().strokeBorder(Palette.line, lineWidth: 0.5))
    }
}

private struct Pill: View {
    let text: String
    var primary = false
    var halo = false
    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(primary ? Color.white : Palette.fg)
            .padding(.horizontal, 16).frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(primary ? Palette.blue : Palette.tile))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(primary ? Color.clear : Palette.track, lineWidth: 1))
            .padding(halo ? 5 : 0)
            .overlay(halo ? RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Palette.blue.opacity(0.55), lineWidth: 2.5) : nil)
    }
}

struct ReadmeDownload: View {
    var body: some View {
        HStack(spacing: 34) {
            VStack(spacing: 10) {
                ReadmeIcon(size: 104)
                Text("Tidemark").font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.bright)
            }
            VStack(spacing: 6) {
                Text("Drag").font(.system(size: 12)).foregroundStyle(Palette.dim)
                ZStack {
                    Capsule().fill(Palette.blue).frame(width: 110, height: 4)
                    Path { p in
                        p.move(to: CGPoint(x: 8, y: 0)); p.addLine(to: CGPoint(x: 22, y: 12)); p.addLine(to: CGPoint(x: 8, y: 24))
                    }
                    .stroke(Palette.blue, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                    .frame(width: 24, height: 24).offset(x: 46)
                }
                .frame(width: 130, height: 24)
            }
            VStack(spacing: 10) {
                ZStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(red: 0.36, green: 0.62, blue: 0.95).opacity(0.75))
                        .frame(width: 52, height: 22).offset(x: -26, y: -8)
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(LinearGradient(colors: [Color(red: 0.45, green: 0.72, blue: 0.98), Color(red: 0.25, green: 0.52, blue: 0.90)], startPoint: .top, endPoint: .bottom))
                        .frame(width: 112, height: 88)
                }
                .frame(width: 112, height: 96, alignment: .bottom)
                Text("Applications").font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.bright)
            }
        }
        .padding(.horizontal, 54).padding(.vertical, 48)
        .frame(width: 640)
        .background(ReadmeDesktop())
        .overlay(IllustrationTag().padding(12), alignment: .bottomTrailing)
    }
}

struct ReadmeNotOpened: View {
    var body: some View {
        ZStack {
            ReadmeDesktop()
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 16) {
                    ReadmeIcon(size: 64)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\u{201C}Tidemark\u{201D} Not Opened")
                            .font(.system(size: 15, weight: .bold)).foregroundStyle(Palette.bright)
                        Text("Apple could not verify \u{201C}Tidemark\u{201D} is free of malware that may harm your Mac or compromise your privacy.")
                            .font(.system(size: 13)).foregroundStyle(Palette.fg)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                HStack(spacing: 10) {
                    Spacer()
                    Pill(text: "Move to Bin")
                    Pill(text: "Done", primary: true)
                }
                .padding(.top, 20)
            }
            .padding(22)
            .frame(width: 400)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.tile))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.line, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.22), radius: 18, y: 9)
        }
        .frame(width: 640, height: 250)
        .overlay(IllustrationTag().padding(12), alignment: .bottomTrailing)
    }
}

struct ReadmeOpenAnyway: View {
    var body: some View {
        ZStack {
            ReadmeDesktop()
            VStack(alignment: .leading, spacing: 0) {
                Text("Privacy & Security")
                    .font(.system(size: 15, weight: .bold)).foregroundStyle(Palette.bright)
                    .padding(.horizontal, 20).padding(.vertical, 14)
                Rectangle().fill(Palette.line).frame(height: 0.5)
                Text("Security").font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.dim)
                    .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 8)
                HStack(spacing: 12) {
                    Text("\u{201C}Tidemark\u{201D} was blocked to protect your Mac.")
                        .font(.system(size: 13)).foregroundStyle(Palette.fg)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Pill(text: "Open Anyway", primary: true, halo: true)
                }
                .padding(.horizontal, 20).padding(.bottom, 16)
            }
            .frame(width: 520)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.tile))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.line, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.22), radius: 18, y: 9)
        }
        .frame(width: 640, height: 220)
        .overlay(IllustrationTag().padding(12), alignment: .bottomTrailing)
    }
}
