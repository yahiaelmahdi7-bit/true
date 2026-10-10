import AppKit
import ApplicationServices
import ImageIO
import Vision
import os

/// Nova's hands on whatever app is on screen — the "super fast desktop assistant" loop, built
/// on Jev (`JevClient`), the Accessibility API, and Vision OCR when accessibility is blind.
///
/// ## The loop
///
/// One step = **look, decide, act**. LOOK walks the frontmost app's focused window through the
/// accessibility tree into a short numbered table of controls ("3: button 'Send' (top-left)"),
/// adds the app's whole menu tree as off-screen controls, and — only when the tree is thin, as
/// it is for Electron apps, Spotify, games — OCRs a capture of that window and adds the text it
/// finds as clickable rows. DECIDE is ONE Jev request that asks several things at once — *which
/// operation* (click, type, press keys, open an app, press Enter, scroll, wait, done, blocked)
/// and *which row / which shortcut / which app / which value* for each operation that needs one
/// — and reads only the head that matches the operation it chose (the "operation + target heads
/// in one round trip" shape from browser-use's jev-ultrafast). ACT presses the row's element
/// through AX, falling back to a click at its centre; typing goes through the same
/// `TextInjector` dictation uses. Then it looks again, up to forty times.
///
/// ## Planning on top
///
/// A goal bigger than one window ("reply to Ben's last email saying I'll be late") is spotted by
/// the same first request (`scope`), and the slow brain writes a 2–6 line plan — the ONLY place
/// free text is ever generated (a reply body, a search query). Each line then runs through this
/// loop with the plan as state. Jev picks every action; the LLM only ever writes words.
///
/// ## Why Jev, and why AX first
///
/// Jev reads a labelled table in a few hundred milliseconds for a fraction of a cent, and it
/// answers with a CHOICE and a confidence — never a coordinate, never a selector, never prose.
/// So the model can only ever pick a row this code observed, and every row it picks is re-read
/// for its live geometry before anything is pressed. The accessibility tree is what the Mac
/// itself uses and Axon already holds the grant; OCR is the fallback because a screenshot costs
/// ~300 ms and Screen Recording permission, and because text on screen is not always a control.
///
/// ## What it refuses, and why
///
/// - **Consequential controls are never pressed on their own.** Send, Pay, Delete, Sign in,
///   Install, Allow… (and ⌘↩ "send") stop the loop and park the press behind one spoken "go
///   ahead" (30 s). A misread of "click share" as "click send" would otherwise send an
///   unfinished email. Everything else runs.
/// - **Password fields are neither read nor typed into.** They appear in the table as
///   "password field (not readable)" so the model knows they exist, and nothing more.
/// - **Below 0.4 confidence it stops and says so** — on the operation AND on the target. A 35%
///   guess at which button is "the one" is a guess, and a guess with a mouse is a click.
/// - **Two steps with no visible change stop it.** A loop that clicks the same disabled button
///   forever is the failure every computer-use demo hides.
/// - **From ambient words (no wake word) only goals with no consequential verb run** — see
///   `NovaReflex.Verdict.isAmbientCommand`.
///
/// Every step is logged (category `computer-use`) and every run is written as JSON under
/// `~/Library/Application Support/Axon/ComputerUse/` — the table, the answers, the action — so a
/// bad run can be replayed against the model and the questions tuned, instead of argued about.
enum ComputerUse {

    // MARK: - Limits

    /// Steps per goal. A form fill is 4–6; a cross-app errand with a plan can be thirty.
    static let maxSteps = 40
    /// Floors on acting: on the operation choice and on the target choice, independently.
    static let minOperationConfidence = 0.4
    static let minTargetConfidence = 0.4
    /// Consecutive steps whose table came back unchanged after an action before she stops.
    static let unchangedStepLimit = 2
    /// Rows offered to the model. Accuracy falls with irrelevant state, and a screen with 300
    /// controls is mostly irrelevant to any one goal; the ones kept are enabled and on screen first.
    static let maxControls = 140
    /// The AX walk's own bounds: after this many nodes or this long, what's been seen is the table.
    static let walkNodeCap = 2000
    static let walkDeadline: TimeInterval = 0.6
    /// Menu items offered as off-screen controls (the whole tree, depth-first, capped).
    static let maxMenuItems = 150
    static let maxMenuDepth = 4
    /// Fewer AX rows than this means the tree is blind (Electron, Spotify, a game) and OCR runs.
    static let thinTableThreshold = 3
    /// How long a parked consequential press waits for "go ahead".
    static let confirmationWindow: TimeInterval = 30
    /// Jev's deadline per step. Longer than the reflex's 0.9 s: a table is bigger than a sentence.
    static let stepTimeout: TimeInterval = 2
    /// The planner's deadline. It writes six lines, not an essay.
    static let planTimeout: TimeInterval = 25
    /// Drafting a reply. Shorter than the planner: it writes a paragraph, not a plan.
    static let composeTimeout: TimeInterval = 20

    // MARK: - The table (pure, testable)

    /// One control as the model sees it. `index` is the only thing the model ever hands back.
    struct Control: Sendable, Equatable, Codable {
        let index: Int
        /// A human word for the role: button, field, text area, checkbox, link, tab, row, menu item, text…
        let role: String
        let label: String
        let value: String?
        let frame: CGRect
        let enabled: Bool
        let focused: Bool
        /// A menu item: reachable by press, not visible as a rectangle.
        let offscreen: Bool
        /// A password field (or a field labelled as one): listed, never read, never typed into.
        let secure: Bool
        /// Where in the window, in the words a person would use ("top-right").
        let place: String
        /// "ax" or "ocr" — OCR rows are text the camera saw; pressing one is a click at its centre.
        var source: String = "ax"

        static let typeableRoles: Set<String> = ["field", "text area", "search field", "combo box"]
        var canType: Bool { Self.typeableRoles.contains(role) && !secure && enabled }
        var canClick: Bool { !secure && enabled }

        /// The row as one line — the same string goes into the state AND the choice criteria, so
        /// the model's option text and the description it reasons over can't disagree.
        var line: String {
            var s = "\(index): \(role)"
            if secure { s += " (not readable)" }
            if !label.isEmpty { s += " '\(label)'" }
            if let value, !value.isEmpty, !secure { s += " = \"\(value)\"" }
            s += offscreen ? " (menu, off-screen)" : " (\(place))"
            if source == "ocr" { s += ", seen by camera" }
            if !enabled { s += ", disabled" }
            if focused { s += ", focused" }
            return s
        }
    }

    struct ScreenTable: Sendable, Equatable, Codable {
        let app: String
        let window: String
        let controls: [Control]

        /// What "the screen changed" means: the rows and their state, not their pixels. A
        /// cursor blink or a clock tick must not count as progress.
        var signature: String {
            var h = Hasher()
            h.combine(app); h.combine(window)
            for c in controls { h.combine(c.line) }
            return String(h.finalize())
        }
        var lines: [String] { controls.map(\.line) }
    }

    /// What the AX walk reads off one node before any judgment. A value type so the pruning and
    /// labelling can be exercised with synthetic nodes and no window at all.
    struct RawNode: Sendable, Equatable {
        var role: String
        var subrole: String? = nil
        var title: String? = nil
        var description: String? = nil
        var value: String? = nil
        var placeholder: String? = nil
        var labelledBy: String? = nil
        var frame: CGRect = .zero
        var enabled = true
        var focused = false
        var offscreen = false
        var source = "ax"
    }

    /// AX roles that DO something when pressed or typed into, mapped to the word the model sees.
    /// Static text is deliberately absent: a label is attached to its control through
    /// `labelledBy`, and a caption on its own is not a target — unless OCR is all there is.
    ///
    /// `AXUnknown` is present, and that is not sloppiness. Chromium and Electron apps hand their
    /// real controls to accessibility with no role at all: Dia's tab list arrives as seventeen
    /// `AXUnknown` nodes carrying the tab titles ("WhatsApp", "InvSearch Cockpit") and nothing
    /// else. Dropping them is why Nova was blind in the user's own browser and fell back to
    /// OCR'ing the tab strip. They earn their row only when they carry a label and a real
    /// rectangle — `prune` enforces both — so an anonymous layout box still can't become a target.
    static let actionableRoles: [String: String] = [
        "AXButton": "button", "AXMenuButton": "menu button", "AXPopUpButton": "popup",
        "AXCheckBox": "checkbox", "AXRadioButton": "radio", "AXDisclosureTriangle": "disclosure",
        "AXTextField": "field", "AXTextArea": "text area", "AXSearchField": "search field",
        "AXComboBox": "combo box", "AXLink": "link", "AXTab": "tab", "AXRow": "row",
        "AXCell": "cell", "AXMenuItem": "menu item", "AXSlider": "slider", "AXIncrementor": "stepper",
        "AXToolbarButton": "button", "AXSwitch": "switch", "AXImage": "image button",
        "AXUnknown": "item", "AXHeading": "heading",
        "OCRText": "text",
    ]

    /// Labels that spend money, send words, destroy data, or grant access. Matched as whole
    /// words, case-insensitively, anywhere in the label. Conservative on purpose: a false
    /// positive costs one "go ahead"; a false negative sends the email.
    static let consequentialWords: [String] = [
        "send", "submit", "pay", "purchase", "buy", "delete", "remove", "confirm", "sign in",
        "log in", "login", "install", "allow", "checkout", "check out", "place order", "discard",
        "trash", "unsubscribe", "transfer", "publish", "post", "share now", "accept", "empty trash",
        "erase", "format", "uninstall", "grant", "authorize", "authorise",
    ]

    nonisolated static func isConsequential(_ label: String) -> Bool {
        let words = label.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        let joined = " " + words.joined(separator: " ") + " "
        return consequentialWords.contains { joined.contains(" \($0) ") }
    }

    /// Where a frame sits inside its window, as a person would say it.
    nonisolated static func place(of frame: CGRect, in window: CGRect) -> String {
        guard window.width > 0, window.height > 0 else { return "on screen" }
        let fx = (frame.midX - window.minX) / window.width
        let fy = (frame.midY - window.minY) / window.height
        let col = fx < 1.0 / 3 ? "left" : (fx > 2.0 / 3 ? "right" : "")
        let row = fy < 1.0 / 3 ? "top" : (fy > 2.0 / 3 ? "bottom" : "")
        switch (row, col) {
        case ("", ""): return "centre"
        case ("", let c): return c
        case (let r, ""): return r
        case (let r, let c): return "\(r)-\(c)"
        }
    }

    /// Raw nodes → the table. Drops what can't be acted on, labels what can, caps the count.
    nonisolated static func prune(_ nodes: [RawNode], window: CGRect) -> [Control] {
        var out: [Control] = []
        for n in nodes {
            guard let word = actionableRoles[n.role] else { continue }
            var role = word
            let secure = n.subrole == "AXSecureTextField"
                || (Control.typeableRoles.contains(word) && (n.title ?? n.placeholder ?? n.labelledBy ?? "").lowercased().contains("password"))
            if secure { role = "password field" }
            // Tabs arrive as radio buttons inside a tab group on AppKit; the subrole says so.
            if n.subrole == "AXTabButton" { role = "tab" }
            if n.role == "AXImage", n.description == nil, n.title == nil { continue }   // decoration
            // The label: title, else what labels it, else description, else placeholder.
            let label = [n.title, n.labelledBy, n.description, n.placeholder]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty } ?? ""
            let value = secure ? nil : n.value.map { short($0, 60) }
            // A row, cell or unlabelled box with nothing to say is a grid line, not a target.
            // This is what keeps `AXUnknown` honest: a Chromium control that carries a title
            // ("WhatsApp") becomes a row, an anonymous layout box never does.
            if ["row", "cell", "text", "item", "heading"].contains(word), label.isEmpty, (value ?? "").isEmpty { continue }
            // Visible controls need a real rectangle; menu items don't have one.
            if !n.offscreen, n.frame.width < 4 || n.frame.height < 4 { continue }
            out.append(Control(
                index: 0, role: role, label: short(label, 60), value: value, frame: n.frame,
                enabled: n.enabled, focused: n.focused, offscreen: n.offscreen, secure: secure,
                place: n.offscreen ? "menu" : place(of: n.frame, in: window), source: n.source))
        }
        // Enabled, on-screen, accessibility-backed controls first; the cap cuts from the tail.
        let ranked = out.enumerated().sorted { a, b in
            let ka = (a.element.enabled ? 0 : 1, a.element.offscreen ? 1 : 0, a.element.source == "ocr" ? 1 : 0, a.offset)
            let kb = (b.element.enabled ? 0 : 1, b.element.offscreen ? 1 : 0, b.element.source == "ocr" ? 1 : 0, b.offset)
            return ka < kb
        }.map(\.element).prefix(maxControls)
        return ranked.enumerated().map { i, c in
            Control(index: i, role: c.role, label: c.label, value: c.value, frame: c.frame,
                    enabled: c.enabled, focused: c.focused, offscreen: c.offscreen, secure: c.secure,
                    place: c.place, source: c.source)
        }
    }

    /// OCR text merged under the AX rows: a camera row that sits on top of an AX control with
    /// the same words is the same thing seen twice, and is dropped. Everything else the camera
    /// read becomes a clickable "text" row — the only way into a window whose tree is blind.
    nonisolated static func merge(ax: [RawNode], ocr: [RawNode]) -> [RawNode] {
        var out = ax
        for t in ocr {
            let words = (t.title ?? "").lowercased()
            guard !words.isEmpty else { continue }
            let duplicate = ax.contains { a in
                a.frame.intersects(t.frame) && [a.title, a.labelledBy, a.description, a.value]
                    .compactMap { $0?.lowercased() }.contains { $0.contains(words) || words.contains($0) && !$0.isEmpty }
            }
            if !duplicate { out.append(t) }
        }
        return out
    }

    nonisolated private static func short(_ s: String, _ n: Int) -> String {
        let one = s.replacingOccurrences(of: "\n", with: " ")
        return one.count <= n ? one : String(one.prefix(n)) + "…"
    }

    // MARK: - Keyboard shortcuts (a fixed table: the model picks, code presses)

    struct Shortcut: Sendable, Equatable {
        let id: String
        let what: String
        let key: CGKeyCode
        let flags: CGEventFlags
        /// ⌘↩ sends in most mail and chat clients — it is a consequential press.
        var consequential = false
    }

    static let shortcuts: [Shortcut] = [
        Shortcut(id: "cmd_w", what: "close the current tab or window (⌘W)", key: 0x0D, flags: .maskCommand),
        Shortcut(id: "cmd_t", what: "new tab (⌘T)", key: 0x11, flags: .maskCommand),
        Shortcut(id: "cmd_n", what: "new window or document (⌘N)", key: 0x2D, flags: .maskCommand),
        Shortcut(id: "cmd_s", what: "save (⌘S)", key: 0x01, flags: .maskCommand),
        Shortcut(id: "cmd_f", what: "find on the page (⌘F)", key: 0x03, flags: .maskCommand),
        Shortcut(id: "cmd_l", what: "focus the browser's address bar (⌘L)", key: 0x25, flags: .maskCommand),
        Shortcut(id: "cmd_z", what: "undo (⌘Z)", key: 0x06, flags: .maskCommand),
        Shortcut(id: "cmd_shift_z", what: "redo (⇧⌘Z)", key: 0x06, flags: [.maskCommand, .maskShift]),
        Shortcut(id: "cmd_a", what: "select all (⌘A)", key: 0x00, flags: .maskCommand),
        Shortcut(id: "cmd_c", what: "copy (⌘C)", key: 0x08, flags: .maskCommand),
        Shortcut(id: "cmd_v", what: "paste (⌘V)", key: 0x09, flags: .maskCommand),
        Shortcut(id: "cmd_shift_t", what: "reopen the last closed tab (⇧⌘T)", key: 0x11, flags: [.maskCommand, .maskShift]),
        Shortcut(id: "cmd_r", what: "reload the page (⌘R)", key: 0x0F, flags: .maskCommand),
        Shortcut(id: "cmd_comma", what: "open the app's settings (⌘,)", key: 0x2B, flags: .maskCommand),
        Shortcut(id: "cmd_tab", what: "switch to the previous app (⌘⇥)", key: 0x30, flags: .maskCommand),
        Shortcut(id: "cmd_enter", what: "send / submit with ⌘↩ (mail, chat)", key: 0x24, flags: .maskCommand, consequential: true),
        Shortcut(id: "escape", what: "dismiss a dialog, popup or sheet (Esc)", key: 0x35, flags: []),
        Shortcut(id: "space", what: "play / pause media (Space)", key: 0x31, flags: []),
        Shortcut(id: "tab", what: "move to the next field (Tab)", key: 0x30, flags: []),
        Shortcut(id: "page_down", what: "page down", key: 0x79, flags: []),
        Shortcut(id: "page_up", what: "page up", key: 0x74, flags: []),
    ]

    nonisolated static func shortcut(_ id: String) -> Shortcut? { shortcuts.first { $0.id == id } }

    // MARK: - Apps the goal names (candidates, code-found; the model picks)

    /// Installed apps whose name appears in the goal, so "open spotify and play jazz" offers
    /// Spotify as an `app_target` — a closed set, never a name the model spelled.
    /// Words that are part of the INSTRUCTION, never the name of an app to open. Without this,
    /// `MacControl.resolveApp` is fuzzy enough that "capture my screen" resolves "capture" to
    /// **Image Capture**, offers it as a candidate, and the loop opens it — which is exactly what
    /// happened at 13:46 on 2026-09-23. An app name has to survive being read as a verb first.
    nonisolated static let notAnAppName: Set<String> = [
        "capture", "screen", "screenshot", "shot", "open", "close", "quit", "launch", "start",
        "show", "look", "read", "tell", "summarize", "summarise", "explain", "click", "press",
        "type", "fill", "scroll", "find", "search", "this", "that", "with", "from", "what",
        "then", "please", "again", "text", "page", "chat", "video", "thing", "stuff", "here",
        "mine", "your", "about", "after", "before", "and",
    ]

    @MainActor
    static func appCandidates(in goal: String) -> [String] {
        let tokens = goal.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 && !notAnAppName.contains($0) }
        var out: [String] = []
        for t in tokens {
            if let url = MacControl.resolveApp(t) {
                let name = url.deletingPathExtension().lastPathComponent
                if !out.contains(name) { out.append(name) }
            }
            if out.count >= 6 { break }
        }
        return out
    }

    // MARK: - Values the user supplied (pure)

    /// Text the goal itself carries for a field: an email address, or words after "type" /
    /// "write" / "saying" / "with". Jev cannot generate text, so the only thing it may ever
    /// type is something the user actually said, or a line the planner wrote for this step —
    /// and if a field needs a value it doesn't hold, the loop stops and asks rather than
    /// inventing one.
    nonisolated static func values(in goal: String) -> [String: String] {
        var out: [String: String] = [:]
        if let r = goal.range(of: #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#, options: .regularExpression) {
            out["email"] = String(goal[r])
        }
        let lower = goal.lowercased()
        for marker in [" type ", " write ", " saying ", " that says ", " with the text ", " with the words ", " enter ", " search for ", " look up "] {
            if let r = lower.range(of: marker) {
                let tail = goal[r.upperBound...].trimmingCharacters(in: CharacterSet(charactersIn: " \"'“”."))
                if !tail.isEmpty, out["email"] != tail { out["text"] = tail }
                break
            }
        }
        return out
    }

    // MARK: - Writing words he did not dictate (bounded, and never a fact)

    /// Verbs that mean "produce words", as opposed to "put these words there".
    nonisolated static let writingVerbs: [String] = [
        "write", "reply", "respond", "draft", "compose", "answer", "message", "tell him",
        "tell her", "tell them", "say that", "let them know", "let him know", "let her know",
        "send a note", "thank", "apologise", "apologize", "follow up", "chase",
    ]
    /// Field labels that must hold a FACT he supplied, never something composed. Inventing an
    /// email address, a phone number, a card or a date is fabrication with his name on it — the
    /// loop stops and asks instead. Free prose is the only thing that may ever be drafted.
    nonisolated static let factFieldWords: [String] = [
        "email", "e-mail", "phone", "mobile", "number", "card", "cvv", "postcode", "zip",
        "address", "date", "dob", "birth", "amount", "price", "quantity", "account", "iban",
        "code", "otp", "pin", "username", "user name", "id",
    ]

    /// May the loop draft the words for this field itself?
    ///
    /// Both halves are required, and the second is the important one. He has to have asked for
    /// WRITING ("reply to this", "draft a note"), and the field has to be free prose. A goal that
    /// says "fill in my email" with no email given is a missing fact, and the honest move there is
    /// to stop and ask — a composed email address is a plausible-looking invention typed into a
    /// real form under his name.
    nonisolated static func mayCompose(goal: String, field: Control) -> Bool {
        let g = goal.lowercased()
        guard writingVerbs.contains(where: { g.contains($0) }) else { return false }
        let label = (field.label + " " + (field.value ?? "")).lowercased()
        if factFieldWords.contains(where: { label.contains($0) }) { return false }
        // A text area is prose by construction; a one-line field only qualifies when it is
        // labelled as a message rather than as a value.
        if field.role == "text area" { return true }
        return ["message", "note", "comment", "reply", "body", "post", "caption", "description",
                "what's on your mind", "type a message", "write"].contains { label.contains($0) }
    }

    /// Draft the words, grounded in what is on screen, in his register.
    ///
    /// The ONE generative call inside an otherwise select-only loop, and it is fenced accordingly:
    /// it only ever produces prose for a field `mayCompose` cleared, it is told never to invent a
    /// fact, and what it writes is TYPED, never sent — every send control and ⌘↩ still park behind
    /// a spoken "go ahead". So the worst case is words he deletes, not a message he did not send.
    @MainActor
    static func compose(goal: String, table: ScreenTable, field: Control) async -> String? {
        let context = table.controls.prefix(60)
            .filter { !$0.offscreen && !$0.secure }
            .map { [$0.label, $0.value ?? ""].filter { !$0.isEmpty }.joined(separator: ": ") }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        let prompt = """
        You are drafting a short piece of text for Yahia to send, and he will read it before it         goes anywhere. Write it AS HIM.

        HOW HE WRITES: direct, leads with the point, short sentences, plain words. No greeting or         sign-off unless the surrounding conversation clearly uses one. NEVER use: an em-dash, "I         hope this finds you well", "just wanted to", "circle back", "happy to help", "let me know         if you have any questions", "delve", "moreover", "furthermore", "robust", "leverage",         "seamless", or a rule-of-three list.

        NEVER invent a fact: no dates, times, amounts, names, links or commitments that are not         already in what he asked for or in what is on screen. If a fact is needed and missing,         write the sentence without it rather than making one up.

        WHAT HE ASKED FOR: \(goal)

        WHAT IS ON SCREEN (the conversation or page he is replying to):
        \(String(context.prefix(4000)))

        Write ONLY the text that goes in the "\(field.label.isEmpty ? "message" : field.label)"         field. No preamble, no quotes around it, no explanation. Keep it under 120 words.
        """
        guard let raw = await NovaOneShot.run(prompt: prompt, timeout: composeTimeout) else { return nil }
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Models like to wrap a draft in quotes or introduce it; strip both.
        if text.hasPrefix("\"") && text.hasSuffix("\"") && text.count > 2 {
            text = String(text.dropFirst().dropLast())
        }
        if let range = text.range(of: #"^(here'?s|here is)[^:]{0,40}:\s*"#, options: [.regularExpression, .caseInsensitive]) {
            text = String(text[range.upperBound...])
        }
        text = text.replacingOccurrences(of: "—", with: "-")
        return text.isEmpty ? nil : text
    }

    // MARK: - Governor (pure)

    /// The stop rules, as a value: step cap and "nothing changed" — kept out of the loop so the
    /// arithmetic can be tested without a screen.
    struct Governor: Sendable {
        private(set) var steps = 0
        private(set) var unchanged = 0
        private var lastSignature: String?

        enum Stop: Equatable { case stepCap, noChange }

        /// Record the table seen at the top of a step. `acted` = the previous step did something
        /// that should have changed the screen (a wait doesn't count).
        mutating func observe(signature: String, afterAction acted: Bool) -> Stop? {
            steps += 1
            if steps > ComputerUse.maxSteps { return .stepCap }
            if acted, let last = lastSignature, last == signature {
                unchanged += 1
            } else if acted {
                unchanged = 0
            }
            lastSignature = signature
            return unchanged >= ComputerUse.unchangedStepLimit ? .noChange : nil
        }
    }

    // MARK: - The plan (pure shape; the slow brain fills it)

    /// A 2–6 line plan for a goal bigger than one window. `text` is the ONE place an LLM writes
    /// free words (a reply body, a search query) — the loop types it, Jev never composes it.
    struct Plan: Codable, Sendable, Equatable {
        struct Step: Codable, Sendable, Equatable {
            let `do`: String
            var app: String? = nil
            var text: String? = nil
        }
        let steps: [Step]

        nonisolated static func prompt(goal: String, frontApp: String) -> String {
            """
            You plan desktop errands for a voice assistant that can click buttons, type into fields, press \
            keyboard shortcuts, and open Mac apps — one screen at a time. Break this spoken goal into 2 to 6 \
            concrete steps, each doable in ONE app window. Where a step needs words typed (a reply, a search), \
            write them in `text` — short, in the user's voice, no placeholders. Name the app for a step in `app` \
            when it isn't the current one. Reply with JSON only: {"steps":[{"do":"…","app":"…","text":"…"}]}.
            Current app: \(frontApp). Goal: "\(goal)"
            """
        }
    }

    // MARK: - The decision (pure request, parsed reply)

    enum Operation: String, CaseIterable, Sendable {
        case click, typeText = "type_text", pressKeys = "press_keys", openApp = "open_app",
             switchTo = "switch_to",
             pressEnter = "press_enter", scrollDown = "scroll_down", scrollUp = "scroll_up",
             wait, done, blocked
    }

    enum Scope: String, Sendable { case thisWindow = "this_window", otherApp = "other_app", multiStep = "multi_step" }

    struct Decision: Sendable, Equatable {
        let operation: Operation
        let operationConfidence: Double
        /// The row for click / type_text, already validated against the table's rows.
        let target: Int?
        let targetConfidence: Double
        /// For type_text: which of the user's values to type ("email", "text").
        let valueKey: String?
        let valueConfidence: Double
        /// For press_keys: a shortcut id from `shortcuts`; for open_app: an app name from the candidates.
        let keys: String?
        let app: String?
        /// For switch_to: the `DesktopIndex` row index of an already-open tab/window to focus.
        let openTarget: Int?
        let scope: Scope?
        let scopeConfidence: Double
        let latency: TimeInterval
    }

    /// The exact Jev payload for one step. Shared with the calibration test.
    nonisolated static func request(goal: String, table: ScreenTable, history: [String],
                                    values: [String: String], apps: [String] = [],
                                    plan: [String] = [], planStep: Int? = nil,
                                    askScope: Bool = false,
                                    openRows: [DesktopIndex.Target] = []) -> (state: [String: Any], questions: [String: Any]) {
        var state: [String: Any] = [
            "goal": goal,
            "app": table.app,
            "window": table.window,
            "controls": table.lines,
            "note": "`controls` is everything on screen that can be clicked or typed into, numbered. `goal` is what the user asked for out loud (speech recognition: words may be misheard). Rows marked off-screen are menu items; rows 'seen by camera' are text the screen shows and can be clicked.",
        ]
        if !history.isEmpty { state["actions_so_far"] = Array(history.suffix(4)) }
        if !values.isEmpty { state["values_the_user_gave"] = values }
        if !apps.isEmpty { state["apps_named_in_goal"] = apps }
        // Tabs and windows ALREADY OPEN whose title the goal mentions. Code filters these down
        // to the few that could plausibly be meant before they are ever shown — a list of every
        // open tab would be mostly irrelevant state, and accuracy falls with that.
        if !openRows.isEmpty { state["already_open_and_named_in_goal"] = openRows.map(\.line) }
        if !plan.isEmpty {
            state["plan"] = plan
            if let planStep { state["current_plan_step"] = planStep + 1 }
        }

        var clickable: [String: String] = ["none": "no row should be clicked"]
        var typeable: [String: String] = ["none": "no row should be typed into"]
        for c in table.controls {
            if c.canClick { clickable[String(c.index)] = c.line }
            if c.canType { typeable[String(c.index)] = c.line }
        }
        var keyOptions: [String: String] = ["none": "no shortcut applies"]
        for s in shortcuts { keyOptions[s.id] = s.what }

        var questions: [String: Any] = [
            "operation": [
                "type": "choice",
                "instructions": [
                    "question": "What is the ONE next step toward `goal` (or toward `current_plan_step` of `plan` when a plan is given), given `controls` and `actions_so_far`?",
                    "focus": "Pick the smallest next action. Prefer a listed control over a shortcut, and a shortcut over scrolling. If what the goal is about is listed in `already_open_and_named_in_goal` and is not the window on screen now, switch_to it before anything else — opening a second copy of something the user already has open is the wrong move. If `actions_so_far` already achieved the goal, it is done. If the goal needs a value the user did not give (see `values_the_user_gave`), or nothing on this screen can do what the goal asks and no app in `apps_named_in_goal` would, it is blocked.",
                ],
                "criteria": [
                    "click": "press or click one row (a button, link, tab, checkbox, menu item, row, or text seen by camera)",
                    "type_text": "put one of `values_the_user_gave` into a field or text area — typing focuses the field itself, no click first",
                    "press_keys": "a standard keyboard shortcut does it (close tab, new tab, save, find, address bar, undo, escape, play/pause…)",
                    "open_app": "the goal is in another app that is NOT already running: open one of `apps_named_in_goal`",
                    "switch_to": "what the goal is about is ALREADY OPEN in another tab or window (see `already_open_and_named_in_goal`) — go there first, rather than opening a second copy",
                    "press_enter": "press Return in the focused field (submit a search or a form)",
                    "scroll_down": "the target isn't listed and is probably further down",
                    "scroll_up": "the target isn't listed and is probably further up",
                    "wait": "something is still loading; look again",
                    "done": "the goal is already achieved by `actions_so_far` or by what's on screen",
                    "blocked": "it can't be done from here: no matching row or shortcut, a value is missing, or the goal isn't about this Mac",
                ],
            ],
            "click_target": [
                "type": "choice",
                "instructions": [
                    "question": "If the next step is a click, which row of `controls` is it?",
                    "focus": "Prefer a row whose label says what the goal says. Prefer visible rows over off-screen menu items, and accessibility rows over rows seen by camera. `none` if no click is needed.",
                ],
                "criteria": clickable,
            ],
            "type_target": [
                "type": "choice",
                "instructions": [
                    "question": "If the next step is typing, which field of `controls` should receive it?",
                    "focus": "Match the field's label to what the value is (an email goes in a 'To' or 'Email' field; a search goes in a search field or the address bar). `none` if nothing should be typed.",
                ],
                "criteria": typeable,
            ],
            "keys_target": [
                "type": "choice",
                "instructions": "If the next step is a keyboard shortcut, which one?",
                "criteria": keyOptions,
            ],
        ]
        if !values.isEmpty {
            var options: [String: String] = ["none": "nothing should be typed"]
            for (k, v) in values { options[k] = "the user's \(k): \"\(short(v, 40))\"" }
            questions["type_value"] = [
                "type": "choice",
                "instructions": "If the next step is typing, which of `values_the_user_gave` goes into the field?",
                "criteria": options,
            ]
        }
        if !apps.isEmpty {
            var options: [String: String] = ["none": "no app needs opening"]
            for a in apps { options[a] = "open \(a)" }
            questions["app_target"] = [
                "type": "choice",
                "instructions": "If the next step is opening an app, which of `apps_named_in_goal`?",
                "criteria": options,
            ]
        }
        if !openRows.isEmpty {
            var options: [String: String] = ["none": "nothing already open needs switching to"]
            for r in openRows { options[String(r.index)] = r.line }
            questions["open_target"] = [
                "type": "choice",
                "instructions": "If the next step is switching to something already open, which row of `already_open_and_named_in_goal`?",
                "criteria": options,
            ]
        }
        if askScope {
            questions["scope"] = [
                "type": "choice",
                "instructions": [
                    "question": "How big is `goal`?",
                    "focus": "Judge the errand, not the wording. Filling a form, clicking a button, closing a tab, pressing play in the current window is this_window. Needing a different app first is other_app. Needing several screens in sequence (compose and address an email, search then pick a result then act on it, book something) is multi_step.",
                ],
                "criteria": [
                    "this_window": "one or a few actions in the window on screen now",
                    "other_app": "a single-window job, but in an app that isn't in front",
                    "multi_step": "several screens or apps in sequence, or text that has to be written (a reply, a message)",
                ],
            ]
        }
        return (state, questions)
    }

    /// Read a reply into a decision. Only the target head matching the operation is consulted;
    /// an index the table doesn't contain is `nil`, never trusted.
    nonisolated static func decision(from reply: JevClient.Reply, table: ScreenTable, apps: [String] = [],
                                     openRows: [DesktopIndex.Target] = []) -> Decision? {
        guard let op = reply.answers["operation"], let raw = op.choice,
              let operation = Operation(rawValue: raw) else { return nil }
        func row(_ head: String, allowed: (Control) -> Bool) -> (Int?, Double) {
            guard let a = reply.answers[head] else { return (nil, 0) }
            guard let choice = a.choice, choice != "none", let i = Int(choice),
                  let c = table.controls.first(where: { $0.index == i }), allowed(c)
            else { return (nil, a.confidence ?? 0) }
            return (i, a.confidence ?? 0)
        }
        var target: Int? = nil, targetConfidence = 0.0
        var valueKey: String? = nil, valueConfidence = 0.0
        var keys: String? = nil, app: String? = nil, openTarget: Int? = nil
        switch operation {
        case .click:
            (target, targetConfidence) = row("click_target", allowed: \.canClick)
        case .typeText:
            (target, targetConfidence) = row("type_target", allowed: \.canType)
            if let v = reply.answers["type_value"], let k = v.choice, k != "none" {
                valueKey = k; valueConfidence = v.confidence ?? 0
            }
        case .pressKeys:
            if let k = reply.answers["keys_target"], let id = k.choice, shortcut(id) != nil {
                keys = id; targetConfidence = k.confidence ?? 0
            }
        case .openApp:
            if let a = reply.answers["app_target"], let name = a.choice, apps.contains(name) {
                app = name; targetConfidence = a.confidence ?? 0
            }
        case .switchTo:
            // Same rule as every other target: an index the code did not offer is not trusted.
            if let a = reply.answers["open_target"], let choice = a.choice, choice != "none",
               let i = Int(choice), openRows.contains(where: { $0.index == i }) {
                openTarget = i; targetConfidence = a.confidence ?? 0
            }
        default: break
        }
        let scope = reply.answers["scope"]?.choice.flatMap { Scope(rawValue: $0) }
        return Decision(operation: operation, operationConfidence: op.confidence ?? 0,
                        target: target, targetConfidence: targetConfidence,
                        valueKey: valueKey, valueConfidence: valueConfidence,
                        keys: keys, app: app, openTarget: openTarget, scope: scope,
                        scopeConfidence: reply.answers["scope"]?.confidence ?? 0,
                        latency: reply.latency)
    }

    // MARK: - Outcome

    struct Outcome: Sendable, Equatable {
        enum Status: String, Sendable { case done, blocked, needsConfirmation, cancelled, noChange, stepCap, lowConfidence, unavailable }
        let status: Status
        let spoken: String
        let steps: Int
    }

    // MARK: - Live state (main actor)

    @MainActor private static var cancelRequested = false
    @MainActor private(set) static var isRunning = false
    @MainActor private static let log = Logger(subsystem: "net.prismlens.axon", category: "computer-use")

    /// A consequential press waiting for the word. Holds the live element (or the shortcut),
    /// not a row index: the table may have moved by the time "go ahead" arrives, and pressing
    /// "row 3" again would be pressing whatever is at row 3 now.
    @MainActor private struct PendingPress {
        let element: AXUIElement?
        let shortcut: Shortcut?
        let fallbackAt: CGRect?
        let label: String
        let goal: String
        let history: [String]
        let values: [String: String]
        let apps: [String]
        let plan: [Plan.Step]
        let planStep: Int
        let openAll: [DesktopIndex.Target]
        let stepsUsed: Int
        let expiresAt: Date
        let record: RunRecord
    }
    @MainActor private static var pending: PendingPress?

    @MainActor static var hasPendingConfirmation: Bool {
        if let p = pending, p.expiresAt <= Date() { pending = nil }
        return pending != nil
    }

    /// "Stop." — honoured between steps; the step in flight (one Jev call, one press) finishes.
    @MainActor static func cancel() {
        if isRunning { cancelRequested = true }
        pending = nil
    }

    // MARK: - Running a goal

    @MainActor
    static func run(goal: String) async -> Outcome {
        guard !isRunning else {
            return Outcome(status: .unavailable, spoken: "I'm already working the screen, sir — say stop first.", steps: 0)
        }
        guard AXIsProcessTrusted() else {
            return Outcome(status: .unavailable, spoken: "I don't have accessibility access, sir — grant it in System Settings and I'll have hands.", steps: 0)
        }
        guard JevClient.isConfigured else {
            return Outcome(status: .unavailable, spoken: "The reflex key isn't set, sir, so I can't read the screen fast enough to work it.", steps: 0)
        }
        pending = nil
        // What is already open, read ONCE for the whole run. Every step filters this list with
        // the pure matcher (free); re-reading it per step would put a quarter-second of
        // AppleScript in front of every decision for information that rarely changes mid-errand.
        let openAll = await DesktopIndex.snapshot()
        return await loop(goal: goal, history: [], values: values(in: goal), apps: appCandidates(in: goal),
                          plan: [], planStep: 0, openAll: openAll, stepsUsed: 0, record: RunRecord(goal: goal))
    }

    /// The word arrived for a parked press. `yes` presses it and carries on with the goal.
    @MainActor
    static func answerPendingConfirmation(_ yes: Bool) async -> String {
        guard let p = pending else { return "There's nothing waiting for a go-ahead, sir." }
        pending = nil
        guard p.expiresAt > Date() else { return "That \(p.label) press timed out, sir — ask me again." }
        guard yes else { return "Leaving \(p.label) alone, sir." }
        var record = p.record
        let ok: Bool
        if let s = p.shortcut { pressKeys(s); ok = true }
        else if let el = p.element { ok = press(el, fallbackAt: p.fallbackAt) }
        else { ok = false }
        record.steps.append(RunRecord.Step(table: [], answers: [:], action: "confirmed press '\(p.label)'", confidence: 1, ms: 0, note: ok ? "pressed" : "press failed"))
        log.info("computer-use confirmed press '\(p.label, privacy: .public)' ok=\(ok, privacy: .public)")
        guard ok else { record.finish("press failed"); return "I couldn't press \(p.label), sir." }
        try? await Task.sleep(nanoseconds: 500_000_000)
        let outcome = await loop(goal: p.goal, history: p.history + ["pressed '\(p.label)'"], values: p.values,
                                 apps: p.apps, plan: p.plan, planStep: p.planStep, openAll: p.openAll,
                                 stepsUsed: p.stepsUsed, record: record)
        return "Pressed \(p.label), sir. " + outcome.spoken
    }

    @MainActor
    private static func loop(goal: String, history startHistory: [String], values startValues: [String: String],
                             apps: [String], plan startPlan: [Plan.Step], planStep startPlanStep: Int,
                             openAll: [DesktopIndex.Target], stepsUsed: Int,
                             record startRecord: RunRecord) async -> Outcome {
        isRunning = true
        cancelRequested = false
        defer { isRunning = false }
        var record = startRecord
        var history = startHistory
        var values = startValues
        var plan = startPlan
        var planStep = startPlanStep
        var governor = Governor()
        var acted = false
        var steps = stepsUsed
        var askedScope = !startPlan.isEmpty || stepsUsed > 0
        // Words the loop drafted itself (never words he dictated). Surfaced when the run ends, so
        // a draft is never left in a field without her saying she wrote it.
        var composed: String?
        func finish(_ status: Outcome.Status, _ spoken: String) -> Outcome {
            record.finish(status.rawValue + ": " + spoken)
            let used = steps   // a constant for the log's escaping interpolation (release-mode race check)
            log.info("computer-use \(status.rawValue, privacy: .public) after \(used, privacy: .public) steps: \(spoken, privacy: .public)")
            return Outcome(status: status, spoken: spoken, steps: used)
        }
        /// The goal for THIS step: the plan line when a plan is running, else the spoken goal.
        func stepGoal() -> String { plan.isEmpty ? goal : plan[min(planStep, plan.count - 1)].do }
        func planLines() -> [String] { plan.enumerated().map { "\($0.offset + 1). \($0.element.do)" + ($0.element.app.map { " (in \($0))" } ?? "") } }
        func adoptPlanValues() {
            guard !plan.isEmpty, planStep < plan.count, let t = plan[planStep].text, !t.isEmpty else { return }
            values["text"] = t
        }
        adoptPlanValues()

        while steps < maxSteps {
            if cancelRequested { return finish(.cancelled, "Stopped, sir.") }
            guard let snap = await Snapshot.capture() else {
                return finish(.unavailable, "I can't see a readable window, sir.")
            }
            if let stop = governor.observe(signature: snap.table.signature, afterAction: acted) {
                switch stop {
                case .noChange: return finish(.noChange, "Nothing's changing on screen, sir — I've stopped.")
                case .stepCap: return finish(.stepCap, "That's as far as I'll take it without you, sir.")
                }
            }
            steps += 1
            // The few open tabs/windows this step's goal could plausibly mean. `match` is pure
            // string work, so this costs nothing per step, and offering eight relevant rows
            // instead of sixty irrelevant ones is what keeps the choice sharp.
            let openRows = Array(
                DesktopIndex.match(stepGoal(), in: openAll)
                    .filter { $0.score > 0 && !($0.target.app == snap.table.app && $0.target.title == snap.table.window) }
                    .prefix(8).map(\.target))
            let (state, questions) = request(goal: stepGoal(), table: snap.table, history: history, values: values,
                                             apps: apps, plan: planLines(), planStep: plan.isEmpty ? nil : planStep,
                                             askScope: !askedScope, openRows: openRows)
            let started = Date()
            guard let reply = await JevClient.ask(state: state, questions: questions, timeout: stepTimeout),
                  let d = decision(from: reply, table: snap.table, apps: apps, openRows: openRows) else {
                record.steps.append(.init(table: snap.table.lines, answers: [:], action: "no verdict", confidence: 0,
                                          ms: Int(Date().timeIntervalSince(started) * 1000), note: "timeout or bad reply"))
                return finish(.unavailable, "The screen model didn't answer in time, sir.")
            }
            if cancelRequested { return finish(.cancelled, "Stopped, sir.") }
            let ms = Int(reply.latency * 1000)
            let targetLine = d.target.flatMap { i in snap.table.controls.first { $0.index == i }?.line } ?? d.keys ?? d.app ?? "-"
            log.info("computer-use step \(steps, privacy: .public) \(d.operation.rawValue, privacy: .public) \(Int(d.operationConfidence * 100), privacy: .public)% target=\(targetLine, privacy: .public) \(Int(d.targetConfidence * 100), privacy: .public)% scope=\(d.scope?.rawValue ?? "-", privacy: .public) \(ms, privacy: .public)ms")
            var step = RunRecord.Step(table: snap.table.lines, answers: reply.answers.mapValues { RunRecord.Answer($0) },
                                      action: d.operation.rawValue + (d.target.map { " row \($0)" } ?? "") + (d.keys.map { " \($0)" } ?? "") + (d.app.map { " \($0)" } ?? ""),
                                      confidence: d.operationConfidence, ms: ms, note: "")
            defer { record.steps.append(step) }

            // PLAN FIRST when the errand is bigger than this window. Asked once, on the first
            // look; the planner is the slow brain and writes only words, never actions.
            if !askedScope {
                askedScope = true
                if let scope = d.scope, scope == .multiStep, d.scopeConfidence >= 0.5, plan.isEmpty {
                    step.note = "planning"
                    if let p = await NovaOneShot.json(Plan.self, prompt: Plan.prompt(goal: goal, frontApp: snap.table.app),
                                                      timeout: planTimeout), !p.steps.isEmpty, p.steps.count <= 8 {
                        plan = p.steps
                        planStep = 0
                        adoptPlanValues()
                        log.info("computer-use plan: \(planLines().joined(separator: " | "), privacy: .public)")
                        acted = false
                        continue   // look again with the plan in hand
                    }
                    // No plan came back: carry on with the bare goal; Jev still decides each step.
                }
            }

            guard d.operationConfidence >= minOperationConfidence else {
                step.note = "operation below floor"
                return finish(.lowConfidence, "I'm not sure what to do next on this screen, sir — I've stopped.")
            }
            switch d.operation {
            case .done:
                // A plan step done is the next step's turn; the LAST one done is the goal done.
                if !plan.isEmpty, planStep < plan.count - 1 {
                    history.append("finished step \(planStep + 1): \(plan[planStep].do)")
                    planStep += 1
                    adoptPlanValues()
                    acted = false
                    continue
                }
                if let composed {
                    return finish(.done, "Done, sir — I've drafted it: \"\(short(composed, 140))\" "
                                  + "Read it before it goes anywhere.")
                }
                return finish(.done, history.isEmpty ? "That's already done, sir." : "Done, sir.")
            case .blocked:
                let missing = values.isEmpty && goal.lowercased().contains("email") ? "I'd need your email for that, sir." : nil
                return finish(.blocked, missing ?? "I can't do that from this screen, sir.")
            case .wait:
                acted = false
                try? await Task.sleep(nanoseconds: 700_000_000)
                continue
            case .scrollDown, .scrollUp:
                scroll(snap, down: d.operation == .scrollDown)
                history.append(d.operation == .scrollDown ? "scrolled down" : "scrolled up")
            case .pressEnter:
                TextInjector.submit(afterLanding: false)
                history.append("pressed Return")
            case .openApp:
                guard let name = d.app, d.targetConfidence >= minTargetConfidence else {
                    step.note = "no confident app"
                    return finish(.lowConfidence, "I couldn't tell which app to open, sir.")
                }
                guard MacControl.open(name) != nil else {
                    step.note = "open failed"
                    return finish(.blocked, "I couldn't open \(name), sir.")
                }
                history.append("opened \(name)")
                // An app takes a moment to put a window up; the next look must see it.
                try? await Task.sleep(nanoseconds: 1_400_000_000)
            case .switchTo:
                guard let i = d.openTarget, d.targetConfidence >= minTargetConfidence,
                      let row = openRows.first(where: { $0.index == i }) else {
                    step.note = "no confident open target"
                    return finish(.lowConfidence, "I couldn't tell which open window you meant, sir.")
                }
                guard await DesktopIndex.focus(row) else {
                    step.note = "focus failed"
                    return finish(.blocked, "I couldn't get to \(row.title), sir — it may have closed.")
                }
                history.append("switched to \(row.title)")
                // A tab switch repaints; the next look must see the new page, not the old one.
                try? await Task.sleep(nanoseconds: 900_000_000)
            case .pressKeys:
                guard let id = d.keys, let s = shortcut(id), d.targetConfidence >= minTargetConfidence else {
                    step.note = "no confident shortcut"
                    return finish(.lowConfidence, "I couldn't tell which shortcut to press, sir.")
                }
                if s.consequential {
                    pending = PendingPress(element: nil, shortcut: s, fallbackAt: nil, label: s.what, goal: goal,
                                           history: history, values: values, apps: apps, plan: plan, planStep: planStep,
                                           openAll: openAll, stepsUsed: steps, expiresAt: Date().addingTimeInterval(confirmationWindow),
                                           record: record)
                    step.note = "parked: consequential shortcut"
                    return finish(.needsConfirmation, "Say 'go ahead' to \(s.what), sir.")
                }
                pressKeys(s)
                history.append("pressed \(s.what)")
            case .click:
                guard let i = d.target, d.targetConfidence >= minTargetConfidence,
                      let c = snap.table.controls.first(where: { $0.index == i }) else {
                    step.note = "no confident target"
                    return finish(.lowConfidence, "I couldn't tell which control to press, sir.")
                }
                let el = snap.element(for: i)
                if isConsequential(c.label) {
                    pending = PendingPress(element: el, shortcut: nil, fallbackAt: c.offscreen ? nil : c.frame,
                                           label: c.label, goal: goal, history: history, values: values, apps: apps,
                                           plan: plan, planStep: planStep, openAll: openAll, stepsUsed: steps,
                                           expiresAt: Date().addingTimeInterval(confirmationWindow), record: record)
                    step.note = "parked: consequential"
                    return finish(.needsConfirmation, "Say 'go ahead' to press \(c.label), sir.")
                }
                let ok: Bool
                if let el { ok = press(el, fallbackAt: c.offscreen ? nil : c.frame) }
                else { ok = click(at: CGPoint(x: c.frame.midX, y: c.frame.midY)) }   // an OCR row
                guard ok else {
                    step.note = "press failed"
                    return finish(.blocked, "I couldn't press \(c.label.isEmpty ? "that" : c.label), sir.")
                }
                history.append("clicked \(c.role) '\(c.label)'")
            case .typeText:
                guard let i = d.target, d.targetConfidence >= minTargetConfidence,
                      let c = snap.table.controls.first(where: { $0.index == i }), c.canType else {
                    step.note = "no confident field"
                    return finish(.lowConfidence, "I couldn't tell which field to fill, sir.")
                }
            var typedKey = "text"
                var text: String
                if let key = d.valueKey, let supplied = values[key] {
                    typedKey = key
                    text = supplied
                } else if mayCompose(goal: goal, field: c) {
                    // He asked for words to be WRITTEN and this is a prose field, so draft them
                    // from what is on screen. Nothing is sent: every send control still parks.
                    step.note = "composing"
                    guard let drafted = await compose(goal: stepGoal(), table: snap.table, field: c) else {
                        return finish(.blocked, "I couldn't draft that, sir — say the words and I'll type them.")
                    }
                    typedKey = "draft"
                    text = drafted
                    values["draft"] = drafted
                    composed = drafted
                    log.info("computer-use drafted \(drafted.count, privacy: .public) chars for '\(c.label, privacy: .public)'")
                } else {
                    step.note = "no value to type"
                    return finish(.blocked, "I'd need the \(values.isEmpty ? "text" : "value") for that, sir — say it and I'll fill it in.")
                }
                if let el = snap.element(for: i) { focus(el, fallbackAt: c.frame) }
                else { _ = click(at: CGPoint(x: c.frame.midX, y: c.frame.midY)) }
                try? await Task.sleep(nanoseconds: 120_000_000)
                TextInjector.land(text, mode: .type)
                history.append("typed the \(typedKey) into '\(c.label)'")
            }
            acted = true
            try? await Task.sleep(nanoseconds: 450_000_000)
        }
        return finish(.stepCap, "That's as far as I'll take it without you, sir.")
    }

    // MARK: - Acting through AX and events

    @MainActor
    private static func press(_ el: AXUIElement, fallbackAt frame: CGRect? = nil) -> Bool {
        // Revalidate: the element must still exist and (if visible) still be where the table
        // said. A dialog that closed between look and act leaves a dangling element — pressing
        // it is a no-op at best and the wrong window at worst.
        let live = liveFrame(el)
        if let frame, frame != .zero, let live, live != .zero,
           abs(live.midX - frame.midX) > 40 || abs(live.midY - frame.midY) > 40 {
            return false
        }
        if AXUIElementPerformAction(el, kAXPressAction as CFString) == .success { return true }
        guard let frame, frame != .zero else { return false }
        let at = (live ?? .zero) == .zero ? frame : live!
        return click(at: CGPoint(x: at.midX, y: at.midY))
    }

    @MainActor
    private static func focus(_ el: AXUIElement, fallbackAt frame: CGRect) {
        if AXUIElementSetAttributeValue(el, kAXFocusedAttribute as CFString, kCFBooleanTrue) == .success { return }
        _ = click(at: CGPoint(x: frame.midX, y: frame.midY))
    }

    @MainActor
    private static func click(at p: CGPoint) -> Bool {
        let src = CGEventSource(stateID: .combinedSessionState)
        guard let move = CGEvent(mouseEventSource: src, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left),
              let down = CGEvent(mouseEventSource: src, mouseType: .leftMouseDown, mouseCursorPosition: p, mouseButton: .left),
              let up = CGEvent(mouseEventSource: src, mouseType: .leftMouseUp, mouseCursorPosition: p, mouseButton: .left)
        else { return false }
        move.post(tap: .cghidEventTap)
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }

    @MainActor
    private static func pressKeys(_ s: Shortcut) {
        let src = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: s.key, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: s.key, keyDown: false)
        down?.flags = s.flags; up?.flags = s.flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    @MainActor
    private static func scroll(_ snap: Snapshot, down: Bool) {
        let p = CGPoint(x: snap.windowFrame.midX, y: snap.windowFrame.midY)
        let src = CGEventSource(stateID: .combinedSessionState)
        CGEvent(mouseEventSource: src, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
        CGEvent(scrollWheelEvent2Source: src, units: .line, wheelCount: 1, wheel1: down ? -6 : 6, wheel2: 0, wheel3: 0)?
            .post(tap: .cghidEventTap)
    }

    @MainActor
    private static func liveFrame(_ el: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?, sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(el, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let pv = posRef, let sv = sizeRef else { return nil }
        var p = CGPoint.zero, s = CGSize.zero
        AXValueGetValue(pv as! AXValue, .cgPoint, &p)
        AXValueGetValue(sv as! AXValue, .cgSize, &s)
        return CGRect(origin: p, size: s)
    }

    // MARK: - Looking: the AX walk (+ OCR when it's blind)

    /// The table plus the live elements behind each row. Main-actor and short-lived: an
    /// `AXUIElement` is a handle into another process, valid only until that process redraws.
    @MainActor
    final class Snapshot {
        let table: ScreenTable
        let windowFrame: CGRect
        private let elements: [Int: AXUIElement]
        init(table: ScreenTable, windowFrame: CGRect, elements: [Int: AXUIElement]) {
            self.table = table; self.windowFrame = windowFrame; self.elements = elements
        }
        func element(for index: Int) -> AXUIElement? { elements[index] }

        static func capture() async -> Snapshot? {
            guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
            let appEl = AXUIElementCreateApplication(app.processIdentifier)
            // Bound every AX call: a hung app must cost a fraction of a second, not the take.
            AXUIElementSetMessagingTimeout(appEl, 0.25)
            guard let window = attr(appEl, kAXFocusedWindowAttribute) as! AXUIElement?
                    ?? attr(appEl, kAXMainWindowAttribute) as! AXUIElement?
                    ?? (attr(appEl, kAXWindowsAttribute) as? [AXUIElement])?.first else { return nil }
            let title = (attr(window, kAXTitleAttribute) as? String) ?? ""
            let windowFrame = frame(of: window) ?? .zero

            var raw: [RawNode] = []
            var els: [AXUIElement?] = []
            let deadline = Date().addingTimeInterval(walkDeadline)
            var queue: [AXUIElement] = [window]
            var seen = 0
            while !queue.isEmpty, seen < walkNodeCap, Date() < deadline {
                let el = queue.removeFirst()
                seen += 1
                let role = (attr(el, kAXRoleAttribute) as? String) ?? ""
                let f = frame(of: el) ?? .zero
                if actionableRoles[role] != nil {
                    raw.append(read(el, role: role, frame: f))
                    els.append(el)
                }
                // Tables and outlines: only what's visible. Their full child list can be
                // thousands of rows, all of which the user can't see either.
                let kids: [AXUIElement]
                if ["AXTable", "AXOutline", "AXList"].contains(role),
                   let visible = attr(el, kAXVisibleRowsAttribute) as? [AXUIElement] {
                    kids = Array(visible.prefix(60))
                } else {
                    kids = Array(((attr(el, kAXChildrenAttribute) as? [AXUIElement]) ?? []).prefix(300))
                }
                queue.append(contentsOf: kids)
            }
            let axRows = raw.count

            // THE CAMERA, when the tree is blind. Electron, Spotify's web view, games: their
            // windows expose a handful of AX nodes or none. A capture of just this window
            // (multi-display safe: the window, not "the screen") run through Vision gives text
            // rows to click at. Needs Screen Recording; without it she says so in the table.
            if axRows < thinTableThreshold, windowFrame.width > 50 {
                let ocr = await OCR.rows(pid: app.processIdentifier, windowFrame: windowFrame)
                let merged = merge(ax: raw, ocr: ocr)
                for _ in raw.count..<merged.count { els.append(nil) }
                raw = merged
            }

            // Menu bar → menus → items → submenus, as off-screen controls (DWIM's trick), depth
            // first with a cap so a big app's menus don't crowd out the window.
            if let bar = attr(appEl, kAXMenuBarAttribute) as! AXUIElement?,
               let items = attr(bar, kAXChildrenAttribute) as? [AXUIElement] {
                var count = 0
                let menuDeadline = deadline.addingTimeInterval(0.35)
                func walkMenu(_ menu: AXUIElement, path: String, depth: Int) {
                    guard depth <= maxMenuDepth, count < maxMenuItems, Date() < menuDeadline,
                          let entries = attr(menu, kAXChildrenAttribute) as? [AXUIElement] else { return }
                    for entry in entries where count < maxMenuItems {
                        let t = (attr(entry, kAXTitleAttribute) as? String) ?? ""
                        guard !t.isEmpty, (attr(entry, kAXEnabledAttribute) as? Bool) ?? true else { continue }
                        let full = "\(path) › \(t)"
                        if let sub = (attr(entry, kAXChildrenAttribute) as? [AXUIElement])?.first,
                           (attr(sub, kAXRoleAttribute) as? String) == "AXMenu" {
                            walkMenu(sub, path: full, depth: depth + 1)
                        } else {
                            raw.append(RawNode(role: "AXMenuItem", title: full, enabled: true, offscreen: true))
                            els.append(entry)
                            count += 1
                        }
                    }
                }
                for item in items.dropFirst() {   // skip the Apple menu
                    let menuTitle = (attr(item, kAXTitleAttribute) as? String) ?? ""
                    guard let menu = (attr(item, kAXChildrenAttribute) as? [AXUIElement])?.first else { continue }
                    walkMenu(menu, path: menuTitle, depth: 1)
                }
            }
            // Prune keeps order within its ranking but re-indexes; map indices back by identity
            // of the raw row (frame + role + label is unique enough within one window).
            let controls = prune(raw, window: windowFrame)
            var map: [Int: AXUIElement] = [:]
            var used = Set<Int>()
            for c in controls {
                if let k = raw.indices.first(where: { i in
                    guard !used.contains(i) else { return false }
                    let n = raw[i]
                    let label = [n.title, n.labelledBy, n.description, n.placeholder]
                        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty } ?? ""
                    return n.frame == c.frame && n.offscreen == c.offscreen && short(label, 60) == c.label && n.source == c.source
                }) {
                    used.insert(k)
                    if k < els.count, let e = els[k] { map[c.index] = e }
                }
            }
            return Snapshot(table: ScreenTable(app: app.localizedName ?? "app", window: title, controls: controls),
                            windowFrame: windowFrame, elements: map)
        }

        private static func read(_ el: AXUIElement, role: String, frame: CGRect) -> RawNode {
            var n = RawNode(role: role, frame: frame)
            n.subrole = attr(el, kAXSubroleAttribute) as? String
            n.title = attr(el, kAXTitleAttribute) as? String
            n.description = attr(el, kAXDescriptionAttribute) as? String
            n.placeholder = attr(el, kAXPlaceholderValueAttribute) as? String
            if let labeller = attr(el, kAXTitleUIElementAttribute) as! AXUIElement? {
                n.labelledBy = (attr(labeller, kAXValueAttribute) as? String) ?? (attr(labeller, kAXTitleAttribute) as? String)
            }
            if n.subrole != "AXSecureTextField" {
                switch attr(el, kAXValueAttribute) {
                case let s as String: n.value = s
                case let b as Bool: n.value = b ? "on" : "off"
                case let num as NSNumber: n.value = num.stringValue
                default: break
                }
            }
            n.enabled = (attr(el, kAXEnabledAttribute) as? Bool) ?? true
            n.focused = (attr(el, kAXFocusedAttribute) as? Bool) ?? false
            return n
        }

        private static func attr(_ el: AXUIElement, _ name: String) -> AnyObject? {
            var ref: CFTypeRef?
            guard AXUIElementCopyAttributeValue(el, name as CFString, &ref) == .success else { return nil }
            return ref
        }

        private static func frame(of el: AXUIElement) -> CGRect? {
            guard let pv = attr(el, kAXPositionAttribute), let sv = attr(el, kAXSizeAttribute) else { return nil }
            var p = CGPoint.zero, s = CGSize.zero
            guard AXValueGetValue(pv as! AXValue, .cgPoint, &p), AXValueGetValue(sv as! AXValue, .cgSize, &s) else { return nil }
            return CGRect(origin: p, size: s)
        }
    }

    // MARK: - The camera: OCR for windows whose tree is blind

    /// Vision text recognition over a capture of ONE window (by window id, so it is the right
    /// display and nothing else). Used only when accessibility returned almost nothing. The
    /// capture is a screenshot of whatever that window shows — so it lives in a temp file for
    /// the milliseconds recognition takes and is deleted on every return path, never kept.
    enum OCR {
        static let maxRows = 80
        static let minConfidence: Float = 0.5

        @MainActor
        static func rows(pid: pid_t, windowFrame: CGRect) async -> [RawNode] {
            guard CGPreflightScreenCaptureAccess() else { return [] }
            guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]],
                  let win = list.first(where: {
                      ($0[kCGWindowOwnerPID as String] as? Int32) == pid && ($0[kCGWindowLayer as String] as? Int) == 0
                  }),
                  let id = win[kCGWindowNumber as String] as? Int else { return [] }
            let path = FileManager.default.temporaryDirectory
                .appendingPathComponent("axon-screen-\(UUID().uuidString).png")
            defer { try? FileManager.default.removeItem(at: path) }
            guard await capture(windowID: id, to: path),
                  let src = CGImageSourceCreateWithURL(path as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return [] }
            return recognize(image, windowFrame: windowFrame)
        }

        /// `screencapture -l <id>`: silent, one window, its own display. Bounded at 3 s.
        private static func capture(windowID: Int, to url: URL) async -> Bool {
            await withCheckedContinuation { cont in
                DispatchQueue.global(qos: .userInitiated).async {
                    let p = Process()
                    p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                    p.arguments = ["-x", "-o", "-l", String(windowID), url.path]
                    p.standardOutput = FileHandle.nullDevice
                    p.standardError = FileHandle.nullDevice
                    do { try p.run() } catch { cont.resume(returning: false); return }
                    let deadline = Date().addingTimeInterval(3)
                    while p.isRunning, Date() < deadline { usleep(20_000) }
                    if p.isRunning { p.terminate() }
                    cont.resume(returning: p.terminationStatus == 0 && FileManager.default.fileExists(atPath: url.path))
                }
            }
        }

        /// Text blocks → rows in WINDOW coordinates (top-left origin, like AX). Vision's boxes
        /// are normalised with a bottom-left origin, hence the flip.
        nonisolated static func recognize(_ image: CGImage, windowFrame: CGRect) -> [RawNode] {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .fast
            request.usesLanguageCorrection = false
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            guard (try? handler.perform([request])) != nil,
                  let results = request.results else { return [] }
            var out: [RawNode] = []
            for r in results where r.confidence >= minConfidence && out.count < maxRows {
                guard let text = r.topCandidates(1).first?.string.trimmingCharacters(in: .whitespacesAndNewlines),
                      !text.isEmpty else { continue }
                let b = r.boundingBox
                let frame = CGRect(x: windowFrame.minX + b.minX * windowFrame.width,
                                   y: windowFrame.minY + (1 - b.maxY) * windowFrame.height,
                                   width: b.width * windowFrame.width,
                                   height: b.height * windowFrame.height)
                out.append(RawNode(role: "OCRText", title: text, frame: frame, source: "ocr"))
            }
            return out
        }
    }

    // MARK: - The run record

    /// Everything a step saw and decided, written once per run so a wrong click can be replayed
    /// against the model with a better question instead of being remembered as "it misclicked".
    struct RunRecord: Codable, Sendable {
        struct Answer: Codable, Sendable {
            let choice: String?
            let confidence: Double?
            let noul: Double?
            init(_ a: JevClient.Answer) { choice = a.choice; confidence = a.confidence; noul = a.noul }
        }
        struct Step: Codable, Sendable {
            let table: [String]
            let answers: [String: Answer]
            let action: String
            let confidence: Double
            let ms: Int
            var note: String
        }
        let goal: String
        let startedAt: Date
        var steps: [Step] = []
        var outcome: String = ""

        init(goal: String) { self.goal = goal; startedAt = Date() }

        static var directory: URL {
            (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support"))
                .appendingPathComponent("Axon/ComputerUse", isDirectory: true)
        }

        mutating func finish(_ outcome: String) {
            self.outcome = outcome
            let dir = Self.directory
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime]
            let name = f.string(from: startedAt).replacingOccurrences(of: ":", with: "-") + ".json"
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            enc.dateEncodingStrategy = .iso8601
            if let data = try? enc.encode(self) { try? data.write(to: dir.appendingPathComponent(name)) }
        }
    }
}
