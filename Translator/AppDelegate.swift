
import Cocoa
import NaturalLanguage
import Network

@main
class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    
    var statusItem: NSStatusItem!
    var timer: Timer?
    var lastClipboard = ""
    var targetLang = "en"
    var autoCopyEnabled = false
    var isPaused = false
    var activePopovers: [NSPopover] = []
    
    // Translation history
    struct TranslationEntry {
        let original: String
        let translation: String
        let from: String
        let to: String
        let timestamp: Date
    }
    var translationHistory: [TranslationEntry] = []
    let maxHistoryItems = 3
    
    let maxLength = 4000
    let pollInterval = 0.4

    // MARK: - App Lifecycle
    
    func applicationDidFinishLaunching(_ notification: Notification) {

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        // Create custom pill-shaped button view
        if let button = statusItem.button {
            let customView = StatusBarPillView()
            customView.appDelegate = self
            customView.frame = NSRect(x: 0, y: 0, width: 120, height: 22)
            customView.autoresizingMask = [.minXMargin, .maxXMargin]
            button.addSubview(customView)
            button.frame = customView.frame
        }
        
        updateMenu()
        updateStatusBarView()
        startMonitoring()
    }
    
    func updateStatusBarView() {
        if let button = statusItem.button,
           let pillView = button.subviews.first as? StatusBarPillView {
            pillView.languageCode = targetLang.uppercased()
            pillView.autoCopyEnabled = autoCopyEnabled
            pillView.isPaused = isPaused
            pillView.needsDisplay = true
        }
    }
    
    // MARK: - Menu
    
    func updateMenu() {
        let menu = NSMenu()
        
        menu.addItem(NSMenuItem(title: "Translator", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())

        let manualTranslateItem = NSMenuItem(title: "Translate Text…", action: #selector(promptTranslateText), keyEquivalent: "t")
        menu.addItem(manualTranslateItem)
        menu.addItem(.separator())
        
        let langMenu = NSMenu()
        let languages = [
            ("en", "English"),
            ("es", "Spanish"),
            ("ko", "Korean"),
            ("vi", "Vietnamese"),
            ("ja", "Japanese"),
            ("de", "German"),
            ("fr", "French")
        ]
        
        for (code, name) in languages {
            let item = NSMenuItem(title: name, action: #selector(selectLanguage(_:)), keyEquivalent: "")
            item.representedObject = code
            item.state = (code == targetLang) ? .on : .off
            langMenu.addItem(item)
        }
        
        let langItem = NSMenuItem(title: "Target Language", action: nil, keyEquivalent: "")
        langItem.submenu = langMenu
        menu.addItem(langItem)
        
        menu.addItem(.separator())
        
        let autoToggle = NSMenuItem(title: "Auto-copy Translation", action: #selector(toggleAutoCopy), keyEquivalent: "a")
        autoToggle.state = autoCopyEnabled ? .on : .off
        menu.addItem(autoToggle)
        
        let pauseItem = NSMenuItem(title: isPaused ? "Resume" : "Pause", action: #selector(togglePause), keyEquivalent: "p")
        menu.addItem(pauseItem)

        menu.addItem(.separator())
        
        // Translation History
        if !translationHistory.isEmpty {
            let historyMenu = NSMenu()
            for (index, entry) in translationHistory.enumerated() {
                // Create submenu for each history item
                let historySubmenu = NSMenu()
                
                // Copy buttons - smaller text
                let originalItem = NSMenuItem(title: "Copy Orig", action: #selector(copyOriginal(_:)), keyEquivalent: "")
                originalItem.representedObject = index
                originalItem.toolTip = entry.original
                historySubmenu.addItem(originalItem)
                
                let translationItem = NSMenuItem(title: "Copy Trans", action: #selector(copyTranslation(_:)), keyEquivalent: "")
                translationItem.representedObject = index
                translationItem.toolTip = entry.translation
                historySubmenu.addItem(translationItem)
                
                historySubmenu.addItem(.separator())
                
                // Show complete original text (non-clickable, wrapped)
                let originalFullItem = NSMenuItem(title: "Original:", action: nil, keyEquivalent: "")
                originalFullItem.isEnabled = false
                historySubmenu.addItem(originalFullItem)
                
                // Split long text into multiple menu items if needed
                let maxLength = 80
                if entry.original.count <= maxLength {
                    let originalTextItem = NSMenuItem(title: entry.original, action: nil, keyEquivalent: "")
                    originalTextItem.isEnabled = false
                    historySubmenu.addItem(originalTextItem)
                } else {
                    // Split into chunks
                    var remaining = entry.original
                    while !remaining.isEmpty {
                        let chunk = String(remaining.prefix(maxLength))
                        remaining = String(remaining.dropFirst(maxLength))
                        let chunkItem = NSMenuItem(title: chunk, action: nil, keyEquivalent: "")
                        chunkItem.isEnabled = false
                        historySubmenu.addItem(chunkItem)
                    }
                }
                
                historySubmenu.addItem(.separator())
                
                // Show complete translation text (non-clickable, wrapped)
                let translationFullItem = NSMenuItem(title: "Translation:", action: nil, keyEquivalent: "")
                translationFullItem.isEnabled = false
                historySubmenu.addItem(translationFullItem)
                
                // Split long translation into multiple menu items if needed
                if entry.translation.count <= maxLength {
                    let translationTextItem = NSMenuItem(title: entry.translation, action: nil, keyEquivalent: "")
                    translationTextItem.isEnabled = false
                    historySubmenu.addItem(translationTextItem)
                } else {
                    // Split into chunks
                    var remaining = entry.translation
                    while !remaining.isEmpty {
                        let chunk = String(remaining.prefix(maxLength))
                        remaining = String(remaining.dropFirst(maxLength))
                        let chunkItem = NSMenuItem(title: chunk, action: nil, keyEquivalent: "")
                        chunkItem.isEnabled = false
                        historySubmenu.addItem(chunkItem)
                    }
                }
                
                // Main history item with submenu
                let historyItem = NSMenuItem(title: "\(entry.from.uppercased()) → \(entry.to.uppercased())", action: nil, keyEquivalent: "")
                historyItem.submenu = historySubmenu
                historyMenu.addItem(historyItem)
            }
            
            let historyMenuItem = NSMenuItem(title: "History", action: nil, keyEquivalent: "")
            historyMenuItem.submenu = historyMenu
            menu.addItem(historyMenuItem)
            menu.addItem(.separator())
        }
        
        let refreshItem = NSMenuItem(title: "Refresh", action: #selector(refresh), keyEquivalent: "r")
        menu.addItem(refreshItem)
        
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        
        self.statusItem.menu = menu
    }

    @objc func promptTranslateText() {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "Translate Text"
        alert.informativeText = "Enter text to translate to \(targetLang.uppercased())."
        alert.addButton(withTitle: "Translate")
        alert.addButton(withTitle: "Cancel")

        let accessoryWidth: CGFloat = 360
        let accessoryHeight: CGFloat = 120

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: accessoryWidth, height: accessoryHeight))
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .bezelBorder

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: accessoryWidth, height: accessoryHeight))
        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.font = .systemFont(ofSize: 13)
        textView.string = NSPasteboard.general.string(forType: .string) ?? ""
        textView.textContainer?.widthTracksTextView = true
        textView.isHorizontallyResizable = false

        scrollView.documentView = textView
        alert.accessoryView = scrollView
        alert.window.initialFirstResponder = textView
        alert.window.makeFirstResponder(textView)

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }

        let input = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }

        // Show quick feedback while translating
        showInfo("Translating…")

        detectLanguage(input) { [weak self] detectedLang in
            guard let self else { return }
            let fromLang = detectedLang ?? "auto"
            let toLang = self.targetLang

            Task {
                let translated = await self.translateWithGoogle(text: input, from: fromLang, to: toLang)
                await MainActor.run {
                    guard let translated else {
                        self.showInfo("Translation failed.\nCheck internet.")
                        return
                    }

                    if self.autoCopyEnabled {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(translated, forType: .string)
                        self.lastClipboard = translated
                    }

                    // Save to history
                    let entry = TranslationEntry(
                        original: input,
                        translation: translated,
                        from: fromLang,
                        to: toLang,
                        timestamp: Date()
                    )
                    self.translationHistory.insert(entry, at: 0)
                    if self.translationHistory.count > self.maxHistoryItems {
                        self.translationHistory.removeLast()
                    }
                    self.updateMenu()

                    // Show result
                    self.showPopover(
                        original: input,
                        translation: translated,
                        from: fromLang,
                        to: toLang,
                        showBoth: true
                    )
                }
            }
        }
    }
    
    @objc func selectLanguage(_ sender: NSMenuItem) {
        if let code = sender.representedObject as? String {
            targetLang = code
            updateMenu()
            updateStatusBarView()
        }
    }
    
    @objc func toggleAutoCopy() {
        autoCopyEnabled.toggle()
        updateMenu()
        updateStatusBarView()
        
        if autoCopyEnabled {
            refresh()
            if let text = NSPasteboard.general.string(forType: .string),
               !text.isEmpty,
               text.count <= maxLength {
                translateText(text)
            }
        }
    }
    
    @objc func togglePause() {
        isPaused.toggle()
        updateMenu()
        updateStatusBarView()
    }
    
    @objc func copyOriginal(_ sender: NSMenuItem) {
        if let index = sender.representedObject as? Int,
           index < translationHistory.count {
            let entry = translationHistory[index]
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(entry.original, forType: .string)
        }
    }
    
    @objc func copyTranslation(_ sender: NSMenuItem) {
        if let index = sender.representedObject as? Int,
           index < translationHistory.count {
            let entry = translationHistory[index]
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(entry.translation, forType: .string)
        }
    }
    
    @objc func refresh() {
        // Clear clipboard tracking
        lastClipboard = ""
        
        // Stop current monitoring
        timer?.invalidate()
        timer = nil
        
        // Close any open popovers
        closeAllPopovers()
        
        // Restart monitoring
        startMonitoring()
        
        // Update UI
        updateMenu()
        updateStatusBarView()
    }
    
    @objc func quit() {
        NSApplication.shared.terminate(nil)
    }
    
    // MARK: - Clipboard Monitoring
    
    func startMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.checkClipboard()
        }
    }
    
    func checkClipboard() {
        guard !isPaused else { return }
        
        let pb = NSPasteboard.general
        guard
            let text = pb.string(forType: .string),
            !text.isEmpty,
            text != lastClipboard,
            text.count <= maxLength
        else { return }
        
        let lower = text.lowercased()

        // Skip system / error spam
        if lower.contains("nsurlerrordomain") ||
           lower.contains("could not be found") ||
           lower.contains("resolved 0 endpoints") ||
           lower.contains("fatal error") {
            lastClipboard = text
            return
        }

        lastClipboard = text
        translateText(text)
    }
    
    // MARK: - Translation
    
    func translateText(_ text: String) {
        detectLanguage(text) { [weak self] detectedLang in
            guard let self, let detectedLang else { return }
            let toLang = self.targetLanguage(for: detectedLang)

            // Skip if detected language matches target language
            if detectedLang == toLang {
                self.lastClipboard = text
                return
            }

            Task {
                // Translate to target language
                let translated = await self.translateWithGoogle(
                    text: text,
                    from: detectedLang,
                    to: toLang
                )
                    
                await MainActor.run {
                    guard let translated else {
                        Task {
                            let dnsOK = await self.checkDNS()
                            await MainActor.run {
                                self.showInfo(
                                    dnsOK
                                    ? "Translation failed.\nCheck internet."
                                    : "DNS is broken.\n\nFix:\n• Toggle Wi-Fi\n• Restart Mac\n• Use 8.8.8.8"
                                )
                            }
                        }
                        return
                    }

                    // If auto-copy is enabled: copy the translation and show it
                    if self.autoCopyEnabled {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(translated, forType: .string)
                        self.lastClipboard = translated

                        self.updateTargetLanguageForFuture(detectedLang)
                        
                        // Add to history
                        let entry = TranslationEntry(
                            original: text,
                            translation: translated,
                            from: detectedLang,
                            to: toLang,
                            timestamp: Date()
                        )
                        self.translationHistory.insert(entry, at: 0)
                        if self.translationHistory.count > self.maxHistoryItems {
                            self.translationHistory.removeLast()
                        }
                        
                        // Show popover with both original and translation
                        self.showPopover(
                            original: text,
                            translation: translated,
                            from: detectedLang,
                            to: toLang,
                            showBoth: true
                        )
                        
                        // Update menu to show history
                        self.updateMenu()
                    } else {
                        // If auto-copy is disabled
                        self.lastClipboard = text
                        
                        // Always show a single translation in the selected target language.
                        let entry = TranslationEntry(
                            original: text,
                            translation: translated,
                            from: detectedLang,
                            to: toLang,
                            timestamp: Date()
                        )
                        self.translationHistory.insert(entry, at: 0)
                        if self.translationHistory.count > self.maxHistoryItems {
                            self.translationHistory.removeLast()
                        }
                        
                        self.showPopover(
                            original: text,
                            translation: translated,
                            from: detectedLang,
                            to: toLang,
                            showBoth: true
                        )
                        
                        // Update menu to show history
                        self.updateMenu()
                    }
                    
                    // Update menu to show history
                    self.updateMenu()
                }
            }
        }
    }

    private func targetLanguage(for detectedLang: String) -> String {
        // Always translate non-English clipboard text to English.
        if detectedLang != "en" {
            return "en"
        }
        return targetLang
    }

    private func updateTargetLanguageForFuture(_ detectedLang: String) {
        guard detectedLang != targetLang else { return }
        targetLang = detectedLang
        updateMenu()
        updateStatusBarView()
    }
    
    func detectLanguage(_ text: String, completion: @escaping (String?) -> Void) {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        completion(recognizer.dominantLanguage?.rawValue)
    }
    
    // MARK: - Google Translate

    func translateWithGoogle(
        text: String,
        from sourceLang: String,
        to targetLang: String
    ) async -> String? {

        guard let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }

        let urlString =
        "https://translate.googleapis.com/translate_a/single?client=gtx&sl=\(sourceLang)&tl=\(targetLang)&dt=t&q=\(encoded)"

        guard let url = URL(string: urlString) else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)

            if let json = try JSONSerialization.jsonObject(with: data) as? [Any],
               let arr = json.first as? [Any] {

                var result = ""
                for seg in arr {
                    if let segArr = seg as? [Any],
                       let txt = segArr.first as? String {
                        result += txt
                    }
                }
                return result.isEmpty ? nil : result
            }
        } catch {
            return nil
        }
        return nil
    }

    // MARK: - DNS Check (Correct)

    func checkDNS() async -> Bool {
        await withCheckedContinuation { cont in
            let endpoint = NWEndpoint.hostPort(host: "www.google.com", port: 443)
            let conn = NWConnection(to: endpoint, using: .tcp)

            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    conn.cancel()
                    cont.resume(returning: true)
                case .failed:
                    conn.cancel()
                    cont.resume(returning: false)
                default:
                    break
        }
    }
            conn.start(queue: .global())
        }
    }
    
    // MARK: - UI

    func popoverDidClose(_ notification: Notification) {
        if let pop = notification.object as? NSPopover {
            removePopover(pop)
        }
    }
    
    private func createPopover() -> NSPopover {
        let pop = NSPopover()
        pop.behavior = .transient
        pop.delegate = self
        
        let vc = PopoverViewController()
        vc.onClose = { [weak self, weak pop] in
            guard let self, let pop else { return }
            pop.performClose(nil)
            self.removePopover(pop)
        }
        pop.contentViewController = vc
        return pop
    }
    
    private func removePopover(_ popover: NSPopover) {
        if let index = activePopovers.firstIndex(where: { $0 === popover }) {
            activePopovers.remove(at: index)
        }
    }
    
    private func closeAllPopovers() {
        let open = activePopovers
        activePopovers.removeAll()
        for pop in open where pop.isShown {
            pop.performClose(nil)
        }
    }
    
    func showPopover(original: String, translation: String, from: String, to: String, showBoth: Bool = false) {
        guard let button = statusItem.button else { return }
        
        let pop = createPopover()
        if let vc = pop.contentViewController as? PopoverViewController {
            vc.setContent(original: original, translation: translation, from: from, to: to, showBoth: showBoth)
        }
        
        activePopovers.append(pop)
        pop.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        
        // Auto-close based on message length - longer display time
        let delay = showBoth ? min(max(12.0, Double(translation.count) / 25.0), 30.0) : min(max(10.0, Double(translation.count) / 30.0), 25.0)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak pop] in
            guard let self, let pop else { return }
            pop.performClose(nil)
            self.removePopover(pop)
        }
    }
    
    func showInfo(_ message: String) {
        guard let button = statusItem.button else { return }
        
        let pop = createPopover()
        if let vc = pop.contentViewController as? PopoverViewController {
            vc.setInfo(message)
        }
        
        activePopovers.append(pop)
        pop.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        
        // Auto-close based on message length - longer display time
        let delay = min(max(8.0, Double(message.count) / 40.0), 20.0)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak pop] in
            guard let self, let pop else { return }
            pop.performClose(nil)
            self.removePopover(pop)
        }
    }
    
    // MARK: - Popover View
    
    class PopoverViewController: NSViewController {
        
        private var containerView: NSView!
        private var titleLabel: NSTextField!
        private var closeButton: NSButton!
        private var originalContainer: NSView!
        private var originalLabel: NSTextField!
        private var translationContainer: NSScrollView!
        private var translationLabel: NSTextField!
        
        var onClose: (() -> Void)?
        
        private let minWidth: CGFloat = 280
        private let maxWidth: CGFloat = 600
        private let minHeight: CGFloat = 100
        private let maxHeight: CGFloat = 500
        private let padding: CGFloat = 16
        private let innerPadding: CGFloat = 12
        private let cornerRadius: CGFloat = 12
        
        override func loadView() {
            // Main container
            containerView = NSView(frame: NSRect(x: 0, y: 0, width: minWidth, height: minHeight))
            
            // Title
            titleLabel = NSTextField(labelWithString: "")
            titleLabel.font = .systemFont(ofSize: 11, weight: .medium)
            titleLabel.alignment = .center
            titleLabel.textColor = .secondaryLabelColor
            containerView.addSubview(titleLabel)
            
            // Close button
            closeButton = NSButton(title: "×", target: self, action: #selector(closeTapped))
            closeButton.isBordered = false
            closeButton.font = .systemFont(ofSize: 13, weight: .semibold)
            closeButton.contentTintColor = .secondaryLabelColor
            closeButton.focusRingType = .none
            containerView.addSubview(closeButton)
            
            // Original text container (with background)
            originalContainer = NSView()
            originalContainer.wantsLayer = true
            originalContainer.layer?.cornerRadius = 8
            originalContainer.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.5).cgColor
            originalContainer.isHidden = true
            
            originalLabel = NSTextField(wrappingLabelWithString: "")
            originalLabel.font = .systemFont(ofSize: 12)
            originalLabel.alignment = .left
            originalLabel.textColor = .secondaryLabelColor
            originalLabel.isEditable = false
            originalLabel.isSelectable = true
            originalLabel.backgroundColor = .clear
            originalLabel.maximumNumberOfLines = 4
            originalLabel.lineBreakMode = .byTruncatingTail
            originalContainer.addSubview(originalLabel)
            containerView.addSubview(originalContainer)
            
            // Translation scroll view
            translationContainer = NSScrollView()
            translationContainer.hasVerticalScroller = true
            translationContainer.hasHorizontalScroller = false
            translationContainer.autohidesScrollers = true
            translationContainer.borderType = .noBorder
            translationContainer.backgroundColor = .clear
            translationContainer.drawsBackground = false
            
            translationLabel = NSTextField(wrappingLabelWithString: "")
            translationLabel.font = .systemFont(ofSize: 15, weight: .medium)
            translationLabel.alignment = .left
            translationLabel.textColor = .labelColor
            translationLabel.isEditable = false
            translationLabel.isSelectable = true
            translationLabel.backgroundColor = .clear
            translationLabel.maximumNumberOfLines = 0
            
            translationContainer.documentView = translationLabel
            containerView.addSubview(translationContainer)
            
            view = containerView
        }
        
        private func updateLayout() {
            let width = containerView.bounds.width
            let height = containerView.bounds.height
            
            // Title at top
            titleLabel.frame = NSRect(
                x: padding,
                y: height - 30,
                width: width - padding * 2,
                height: 20
            )
            
            closeButton.frame = NSRect(
                x: width - padding - 18,
                y: height - 28,
                width: 18,
                height: 18
            )
            
            var currentY: CGFloat = padding
            
            // Original text box (if visible)
            if !originalContainer.isHidden {
                let maxOriginalHeight: CGFloat = 80
                let originalTextHeight = originalLabel.attributedStringValue.boundingRect(
                    with: NSSize(width: width - padding * 2 - innerPadding * 2, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading]
                ).height
                
                let originalHeight = min(originalTextHeight + innerPadding * 2, maxOriginalHeight)
                
                originalContainer.frame = NSRect(
                    x: padding,
                    y: currentY,
                    width: width - padding * 2,
                    height: originalHeight
                )
                
                originalLabel.frame = NSRect(
                    x: innerPadding,
                    y: innerPadding,
                    width: originalContainer.bounds.width - innerPadding * 2,
                    height: originalHeight - innerPadding * 2
                )
                
                currentY += originalHeight + 12
            }
            
            // Translation area
            let translationHeight = height - currentY - 40
            translationContainer.frame = NSRect(
                x: padding,
                y: currentY,
                width: width - padding * 2,
                height: max(translationHeight, 60)
            )
            
            // Update translation label size
            let textWidth = translationContainer.bounds.width
            translationLabel.frame.size.width = textWidth
            let textHeight = translationLabel.attributedStringValue.boundingRect(
                with: NSSize(width: textWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading]
            ).height
            translationLabel.frame.size.height = max(textHeight + 20, translationContainer.bounds.height)
            
            if let documentView = translationContainer.documentView {
                documentView.frame.size = translationLabel.frame.size
            }
        }
        
        private func calculateSize(for text: String, hasOriginal: Bool) -> NSSize {
            let textLength = text.count
            
            // Dynamic width based on text length
            let dynamicWidth: CGFloat = {
                if textLength < 50 { return 300 }
                if textLength < 150 { return 400 }
                if textLength < 300 { return 500 }
                return maxWidth
            }()
            
            let width = min(dynamicWidth, maxWidth)
            
            // Calculate text height
            let textWidth = width - padding * 2
            let attributed = NSAttributedString(
                string: text,
                attributes: [.font: NSFont.systemFont(ofSize: 15, weight: .medium)]
            )
            let textHeight = attributed.boundingRect(
                with: NSSize(width: textWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading]
            ).height
            
            // Calculate total height
            var totalHeight: CGFloat = 40 + padding * 2 // Title + padding
            
            if hasOriginal {
                totalHeight += min(80, 60) + 12 // Original box + spacing
            }
            
            totalHeight += textHeight + 20 // Translation text + buffer
            
            let height = min(max(totalHeight, minHeight), maxHeight)
            
            return NSSize(width: width, height: height)
        }
        
        func setContent(original: String, translation: String, from: String, to: String, showBoth: Bool) {
            _ = view
            
            titleLabel.stringValue = "\(from.uppercased()) → \(to.uppercased())"
            
            // Original text
            if showBoth {
                originalContainer.isHidden = false
                originalLabel.stringValue = original
            } else {
                originalContainer.isHidden = true
            }
            
            // Translation
            let textLength = translation.count
            let fontSize: CGFloat = textLength < 50 ? 15 : (textLength < 200 ? 14 : 13)
            translationLabel.font = .systemFont(ofSize: fontSize, weight: .medium)
            translationLabel.stringValue = translation
            
            // Resize
            let size = calculateSize(for: translation, hasOriginal: showBoth)
            containerView.frame.size = size
            view.frame.size = size
            
            updateLayout()
        }
        
        func setInfo(_ message: String) {
            _ = view
            
            titleLabel.stringValue = "Translator"
            originalContainer.isHidden = true
            
            translationLabel.font = .systemFont(ofSize: 13, weight: .regular)
            translationLabel.stringValue = message
            
            let size = calculateSize(for: message, hasOriginal: false)
            containerView.frame.size = size
            view.frame.size = size
            
            updateLayout()
        }
        
        @objc private func closeTapped() {
            onClose?()
        }
    }
    
    // MARK: - Status Bar Pill View
    
    class StatusBarPillView: NSView {
        weak var appDelegate: AppDelegate?
        
        var languageCode: String = "ES" {
            didSet { needsDisplay = true }
        }
        var autoCopyEnabled: Bool = false {
            didSet { needsDisplay = true }
        }
        var isPaused: Bool = false {
            didSet { needsDisplay = true }
        }
        
        private let padding: CGFloat = 8
        private let buttonWidth: CGFloat = 26
        private let buttonHeight: CGFloat = 18
        private let cornerRadius: CGFloat = 11
        private let buttonCornerRadius: CGFloat = 7
        
        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            setupView()
        }
        
        required init?(coder: NSCoder) {
            super.init(coder: coder)
            setupView()
        }
        
        private func setupView() {
            wantsLayer = true
            layer?.cornerRadius = cornerRadius
        }
        
        override func draw(_ dirtyRect: NSRect) {
            super.draw(dirtyRect)
            
            guard let context = NSGraphicsContext.current?.cgContext else { return }
            context.saveGState()
            
            let isDarkMode = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            
            // Background with subtle gradient
            let bgPath = NSBezierPath(roundedRect: bounds, xRadius: cornerRadius, yRadius: cornerRadius)
            
            if isDarkMode {
                NSColor(white: 0.2, alpha: 0.9).setFill()
            } else {
                NSColor(white: 0.95, alpha: 0.95).setFill()
            }
            bgPath.fill()
            
            // Border
            let borderColor = isDarkMode ? NSColor.white.withAlphaComponent(0.1) : NSColor.black.withAlphaComponent(0.08)
            borderColor.setStroke()
            bgPath.lineWidth = 0.5
            bgPath.stroke()
            
            context.restoreGState()
            
            // Positions
            let langX = padding + 2
            let aButtonX = bounds.width - buttonWidth * 2 - padding
            let pButtonX = bounds.width - buttonWidth - padding + 2
            let centerY = bounds.midY
            
            // Language code
            let langAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: NSColor.labelColor
            ]
            let langString = NSAttributedString(string: languageCode, attributes: langAttributes)
            let langSize = langString.size()
            langString.draw(at: NSPoint(x: langX, y: centerY - langSize.height / 2))
            
            // Buttons
            let aButtonRect = NSRect(x: aButtonX, y: centerY - buttonHeight / 2, width: buttonWidth, height: buttonHeight)
            let pButtonRect = NSRect(x: pButtonX, y: centerY - buttonHeight / 2, width: buttonWidth, height: buttonHeight)
            
            drawButton(text: "A", in: aButtonRect, isSelected: autoCopyEnabled, color: NSColor.systemGreen)
            drawButton(text: "P", in: pButtonRect, isSelected: isPaused, color: NSColor.systemOrange)
        }
        
        private func drawButton(text: String, in rect: NSRect, isSelected: Bool, color: NSColor) {
            let isDarkMode = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let bgPath = NSBezierPath(roundedRect: rect, xRadius: buttonCornerRadius, yRadius: buttonCornerRadius)
            
            if isSelected {
                // Filled background
                color.withAlphaComponent(isDarkMode ? 0.25 : 0.2).setFill()
                bgPath.fill()
                
                // Border
                color.withAlphaComponent(0.8).setStroke()
                bgPath.lineWidth = 1.5
                bgPath.stroke()
            } else {
                // Subtle background
                (isDarkMode ? NSColor.white.withAlphaComponent(0.05) : NSColor.black.withAlphaComponent(0.03)).setFill()
                bgPath.fill()
                
                // Subtle border
                (isDarkMode ? NSColor.white.withAlphaComponent(0.1) : NSColor.black.withAlphaComponent(0.1)).setStroke()
                bgPath.lineWidth = 0.5
                bgPath.stroke()
            }
            
            // Text
            let textColor = isSelected ? color : NSColor.secondaryLabelColor
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: textColor
            ]
            let string = NSAttributedString(string: text, attributes: attributes)
            let size = string.size()
            string.draw(at: NSPoint(
                x: rect.midX - size.width / 2,
                y: rect.midY - size.height / 2
            ))
        }
        
        override func mouseDown(with event: NSEvent) {
            let locationInView = convert(event.locationInWindow, from: nil)
            let location = locationInView.x.isNaN ? event.locationInWindow.x : locationInView.x
            let yLocation = locationInView.y.isNaN ? event.locationInWindow.y : locationInView.y
            
            let aButtonX = bounds.width - buttonWidth * 2 - padding
            let pButtonX = bounds.width - buttonWidth - padding + 2
            let centerY = bounds.midY
            let buttonYMin = centerY - buttonHeight / 2
            let buttonYMax = centerY + buttonHeight / 2
            
            let isInButtonHeight = yLocation >= buttonYMin && yLocation <= buttonYMax
            
            if isInButtonHeight && location >= aButtonX && location < (aButtonX + buttonWidth) {
                appDelegate?.toggleAutoCopy()
            } else if isInButtonHeight && location >= pButtonX && location <= (pButtonX + buttonWidth) {
                appDelegate?.togglePause()
            } else {
                if let button = superview as? NSStatusBarButton {
                    button.performClick(nil)
                }
            }
        }
        
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
            return true
        }
        
        override var intrinsicContentSize: NSSize {
            return NSSize(width: 120, height: 22)
        }
    }
}
