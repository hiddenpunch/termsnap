// Termsnap 메뉴 막대 앱. 저장·복원 로직은 termsnap.py 가 하고, 이 앱은 상태 표시와 버튼만 맡는다.
import AppKit
import ServiceManagement

// 스크립트는 앱 안(Resources)에 들어 있다. 파이썬은 있는 것 중 먼저 찾은 것을 쓴다(macOS 기본 3.9 로도 돈다).
let script = Bundle.main.path(forResource: "termsnap", ofType: "py") ?? ""
let python = ["/opt/homebrew/bin/python3", "/usr/local/bin/python3", "/usr/bin/python3"]
    .first { FileManager.default.isExecutableFile(atPath: $0) } ?? "/usr/bin/python3"
let ghosttyBundleID = "com.mitchellh.ghostty"
let snapshotInterval: TimeInterval = 300   // 5분마다 자동 저장

@discardableResult
func termsnap(_ args: [String]) -> String {
    guard FileManager.default.fileExists(atPath: script) else { return "" }
    let p = Process()
    p.executableURL = URL(fileURLWithPath: python)
    p.arguments = [script] + args
    p.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin", "HOME": NSHomeDirectory(), "PYTHONUTF8": "1"]
    let out = Pipe()
    p.standardOutput = out
    p.standardError = FileHandle.nullDevice
    do { try p.run() } catch { return "" }
    let data = out.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return String(data: data, encoding: .utf8) ?? ""
}

func json(_ text: String) -> Any? {
    guard let data = text.data(using: .utf8) else { return nil }
    return try? JSONSerialization.jsonObject(with: data)
}

struct Counts {
    var takenAt = "", windows = 0, tabs = 0, terminals = 0, claude = 0, codex = 0, other = 0
    init(_ d: [String: Any]) {
        takenAt = d["taken_at"] as? String ?? ""
        windows = d["windows"] as? Int ?? 0; tabs = d["tabs"] as? Int ?? 0; terminals = d["terminals"] as? Int ?? 0
        claude = d["claude"] as? Int ?? 0; codex = d["codex"] as? Int ?? 0; other = d["other"] as? Int ?? 0
    }
    var layout: String { "창 \(windows) · 탭 \(tabs) · 분할 \(terminals)" }
    var kinds: String { "Claude \(claude) · Codex \(codex) · 기타 \(other)" }
}

struct RestorePoint {
    var counts: Counts, state: String, causeKo: String, alert: Bool, detectedAt: String
}

/// 복원 메뉴에 나오는 저장본 하나.
struct Entry {
    var id: String, label: String, counts: Counts
}

struct Status {
    var latest: Counts?
    var restorePoint: RestorePoint?
    var entries: [Entry] = []
    static func load() -> Status {
        var s = Status()
        if let d = json(termsnap(["status"])) as? [String: Any] {
            if let l = d["latest"] as? [String: Any] { s.latest = Counts(l) }
            if let r = d["restore_point"] as? [String: Any] {
                s.restorePoint = RestorePoint(counts: Counts(r), state: r["state"] as? String ?? "", causeKo: r["cause_ko"] as? String ?? "",
                                              alert: r["alert"] as? Bool ?? false, detectedAt: r["detected_at"] as? String ?? "")
            }
        }
        if let list = json(termsnap(["list"])) as? [[String: Any]] {
            s.entries = list.map { Entry(id: $0["id"] as? String ?? "", label: $0["label"] as? String ?? "", counts: Counts($0)) }
        }
        return s
    }
}

func parse(_ iso: String) -> Date? {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
    return f.date(from: iso)
}

func ago(_ iso: String) -> String {
    guard let d = parse(iso) else { return "기록 없음" }
    let m = Int(Date().timeIntervalSince(d) / 60)
    if m < 1 { return "방금" }
    if m < 60 { return "\(m)분 전" }
    if m < 60 * 24 { return "\(m / 60)시간 전" }
    return "\(m / 60 / 24)일 전"
}

func clock(_ iso: String) -> String {
    guard let d = parse(iso) else { return iso }
    let f = DateFormatter()
    f.dateFormat = Calendar.current.isDateInToday(d) ? "'오늘' HH:mm" : (Calendar.current.isDateInYesterday(d) ? "'어제' HH:mm" : "M/d HH:mm")
    return f.string(from: d)
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let work = DispatchQueue(label: "termsnap.work")
    var status = Status()

    func applicationDidFinishLaunching(_ note: Notification) {
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        render()
        // 시작할 때 한 번 저장해 그사이 세션이 사라졌는지(재부팅·로그아웃) 판정한다
        background { termsnap(["snapshot", "--quiet"]) }
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.background {} }
        Timer.scheduledTimer(withTimeInterval: snapshotInterval, repeats: true) { [weak self] _ in
            self?.background { termsnap(["snapshot", "--quiet"]) }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard app?.bundleIdentifier == ghosttyBundleID else { return }
            // 충돌 보고서가 써질 시간을 준 뒤 저장해, 종료인지 충돌인지 가린다
            self?.work.asyncAfter(deadline: .now() + 5) {
                termsnap(["snapshot", "--quiet"])
                self?.reload()
            }
        }
    }

    /// 백그라운드에서 일을 하고 상태를 다시 읽어 화면에 반영한다.
    func background(_ job: @escaping () -> Void) {
        work.async { job(); self.reload() }
    }

    func reload() {
        let s = Status.load()
        DispatchQueue.main.async {
            self.status = s
            self.render()
            self.notifyIfNeeded()
        }
    }

    func render() {
        guard let button = item.button else { return }
        button.image = menuBarGlyph()   // icon/glyph.swift: 앱 아이콘 A 를 단색 윤곽선으로 옮긴 것
        button.imagePosition = .imageLeading
        if let rp = status.restorePoint, rp.alert {
            let t = NSMutableAttributedString(string: " ●", attributes: [.foregroundColor: NSColor.systemRed])
            t.append(NSAttributedString(string: " \(rp.counts.terminals)", attributes: [.font: NSFont.menuBarFont(ofSize: 0)]))
            button.attributedTitle = t
        } else {
            button.attributedTitle = NSAttributedString(string: "")
        }
    }

    func notifyIfNeeded() {
        guard let rp = status.restorePoint, rp.alert else { return }
        let key = "notifiedRestorePoint"
        guard UserDefaults.standard.string(forKey: key) != rp.detectedAt else { return }
        UserDefaults.standard.set(rp.detectedAt, forKey: key)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", "display notification \"복원할 세션 \(rp.counts.terminals)개가 있습니다 (\(rp.causeKo))\" with title \"Termsnap\""]
        try? p.run()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        func info(_ title: String, in m: NSMenu = menu) {
            let i = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            i.isEnabled = false
            m.addItem(i)
        }
        func action(_ title: String, _ sel: Selector, id: String? = nil, in m: NSMenu = menu) {
            let i = NSMenuItem(title: title, action: sel, keyEquivalent: "")
            i.target = self
            i.representedObject = id
            m.addItem(i)
        }
        if !FileManager.default.fileExists(atPath: script) {
            info("앱 안에서 termsnap.py 를 찾지 못했습니다")
        }
        if let rp = status.restorePoint, rp.state == "pending" {
            action("복원 — \(rp.counts.layout)", #selector(restore(_:)), id: "restore-point")
            info("   \(rp.causeKo) · \(ago(rp.counts.takenAt)) 저장본 · \(rp.counts.kinds)")
            action("이번엔 복원 안 함", #selector(dismiss))
            menu.addItem(.separator())
        }
        if let l = status.latest {
            info("마지막 저장: \(ago(l.takenAt))")
            info("\(l.layout)")
            info("\(l.kinds)")
        } else {
            info("저장본이 없습니다")
        }
        menu.addItem(.separator())
        action("지금 저장", #selector(saveNow))
        // 복원은 항상 보여 준다. 저장본을 골라 복원한다.
        let sub = NSMenu()
        for e in status.entries {
            let name = e.label.isEmpty ? clock(e.counts.takenAt) : "\(e.label) · \(clock(e.counts.takenAt))"
            action("\(name) — 분할 \(e.counts.terminals) (Claude \(e.counts.claude) · Codex \(e.counts.codex))", #selector(restore(_:)), id: e.id, in: sub)
        }
        if status.entries.isEmpty { info("저장본이 없습니다", in: sub) }
        let restoreItem = NSMenuItem(title: "복원", action: nil, keyEquivalent: "")
        restoreItem.submenu = sub
        menu.addItem(restoreItem)
        action("저장본 내용 보기", #selector(showContents))
        menu.addItem(.separator())
        let login = NSMenuItem(title: "로그인 시 실행", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        action("종료", #selector(quit))
        // 메뉴를 여는 순간 지금 상태를 저장해 둔다. 복원을 누르면 이 저장본으로 바로 계산해 팝업이 늦지 않다.
        background { termsnap(["snapshot", "--quiet"]) }
    }

    @objc func saveNow() { background { termsnap(["snapshot", "--quiet"]) } }
    @objc func dismiss() { background { termsnap(["dismiss"]) } }
    @objc func quit() { NSApp.terminate(nil) }

    @objc func toggleLogin() {
        let svc = SMAppService.mainApp
        do {
            if svc.status == .enabled { try svc.unregister() } else { try svc.register() }
        } catch {
            let a = NSAlert()
            a.messageText = "로그인 항목을 바꾸지 못했습니다"
            a.informativeText = "시스템 설정 → 일반 → 로그인 항목에서 직접 켜 주세요.\n\(error.localizedDescription)"
            NSApp.activate(ignoringOtherApps: true)
            a.runModal()
        }
    }

    /// 터미널이 이미 열려 있으면 어떻게 열지 묻고, 없으면 바로 복원한다.
    @objc func restore(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        // 저장 작업이 도는 중이어도 기다리지 않게 별도 큐에서 최신 저장본으로 계산한다
        DispatchQueue.global(qos: .userInitiated).async {
            let plan = json(termsnap(["plan", id, "--cached"])) as? [String: Any] ?? [:]
            let live = plan["live"] as? Int ?? 0, busy = plan["busy"] as? Int ?? 0
            let all = plan["all"] as? Int ?? 0, missing = plan["missing"] as? Int ?? 0, skipped = plan["skipped"] as? Int ?? 0
            if live == 0 {
                termsnap(["restore", id, "--mode", "all"])
                self.reload()
                return
            }
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "지금 터미널 \(live)개가 열려 있습니다"
                alert.informativeText = """
                없는 것만 열기: \(missing)개를 열고, 이미 떠 있는 \(skipped)개는 건너뜁니다.
                전부 추가로 열기: 중복과 상관없이 \(all)개를 모두 엽니다.
                전부 종료하고 열기: 지금 열린 \(live)개를 닫고 \(all)개를 엽니다.\(busy > 0 ? " 작업 중인 세션 \(busy)개가 중단됩니다." : "")
                """
                let bMissing = alert.addButton(withTitle: "없는 것만 추가로 열기")
                alert.addButton(withTitle: "중복 상관없이 전부 추가로 열기")
                let bReplace = alert.addButton(withTitle: "기존 터미널을 전부 종료하고 열기")
                alert.addButton(withTitle: "취소")
                bMissing.isEnabled = missing > 0
                bReplace.hasDestructiveAction = true
                NSApp.activate(ignoringOtherApps: true)
                let mode: String
                switch alert.runModal() {
                case .alertFirstButtonReturn: mode = "missing"
                case .alertSecondButtonReturn: mode = "all"
                case .alertThirdButtonReturn: mode = "replace"
                default: return
                }
                self.background { termsnap(["restore", id, "--mode", mode]) }
            }
        }
    }

    @objc func showContents() {
        work.async {
            let text = termsnap(["show", "--latest"])
            let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("termsnap-show.txt")
            try? text.write(to: url, atomically: true, encoding: .utf8)
            DispatchQueue.main.async {
                NSWorkspace.shared.open([url], withApplicationAt: URL(fileURLWithPath: "/System/Applications/TextEdit.app"),
                                        configuration: NSWorkspace.OpenConfiguration())
            }
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
