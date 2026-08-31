import AppKit

@MainActor
enum MainMenuBuilder {
    static func make(delegate: AppDelegate) -> NSMenu {
        let main = NSMenu()
        main.addItem(menuItem(title: "MarkdStage", submenu: applicationMenu(delegate)))
        main.addItem(menuItem(title: "File", submenu: fileMenu(delegate)))
        main.addItem(menuItem(title: "Presentation", submenu: presentationMenu(delegate)))
        main.addItem(menuItem(title: "View", submenu: viewMenu(delegate)))
        main.addItem(menuItem(title: "Window", submenu: windowMenu()))
        main.addItem(menuItem(title: "Help", submenu: helpMenu(delegate)))
        return main
    }

    private static func applicationMenu(_ delegate: AppDelegate) -> NSMenu {
        let menu = NSMenu(title: "MarkdStage")
        menu.addItem(item("About MarkdStage", action: #selector(delegate.showAboutPanel(_:)), target: delegate))
        menu.addItem(.separator())
        menu.addItem(item("Hide MarkdStage", action: #selector(NSApplication.hide(_:)), key: "h"))
        let hideOthers = item("Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), key: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(hideOthers)
        menu.addItem(item("Show All", action: #selector(NSApplication.unhideAllApplications(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Quit MarkdStage", action: #selector(NSApplication.terminate(_:)), key: "q"))
        return menu
    }

    private static func fileMenu(_ delegate: AppDelegate) -> NSMenu {
        let menu = NSMenu(title: "File")
        menu.addItem(item("Open…", action: #selector(delegate.openDocument(_:)), key: "o", target: delegate))
        menu.addItem(item(
            "Close Markdown",
            action: #selector(delegate.closeDocument(_:)),
            target: delegate
        ))
        menu.addItem(.separator())
        let export = item("Export as PDF…", action: #selector(delegate.exportPDF(_:)), key: "e", target: delegate)
        export.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(export)
        menu.addItem(.separator())
        menu.addItem(item("Close Window", action: #selector(NSWindow.performClose(_:)), key: "w"))
        return menu
    }

    private static func presentationMenu(_ delegate: AppDelegate) -> NSMenu {
        let menu = NSMenu(title: "Presentation")
        let previous = item("Previous Slide", action: #selector(delegate.previousSlide(_:)), key: "\u{F702}", target: delegate)
        previous.keyEquivalentModifierMask = []
        menu.addItem(previous)
        let next = item("Next Slide", action: #selector(delegate.nextSlide(_:)), key: "\u{F703}", target: delegate)
        next.keyEquivalentModifierMask = []
        menu.addItem(next)
        menu.addItem(.separator())
        let first = item("First Slide", action: #selector(delegate.firstSlide(_:)), key: "\u{F702}", target: delegate)
        first.keyEquivalentModifierMask = [.command]
        menu.addItem(first)
        let last = item("Last Slide", action: #selector(delegate.lastSlide(_:)), key: "\u{F703}", target: delegate)
        last.keyEquivalentModifierMask = [.command]
        menu.addItem(last)
        menu.addItem(.separator())
        let present = item(
            "Start or End Presentation",
            action: #selector(delegate.togglePresentation(_:)),
            key: "\r",
            target: delegate
        )
        present.keyEquivalentModifierMask = [.command]
        menu.addItem(present)
        return menu
    }

    private static func viewMenu(_ delegate: AppDelegate) -> NSMenu {
        let menu = NSMenu(title: "View")
        let audienceFullScreen = item(
            "Toggle Audience Full Screen",
            action: #selector(delegate.toggleAudienceFullScreen(_:)),
            key: "f",
            target: delegate
        )
        audienceFullScreen.keyEquivalentModifierMask = [.command, .control]
        menu.addItem(audienceFullScreen)
        return menu
    }

    private static func windowMenu() -> NSMenu {
        let menu = NSMenu(title: "Window")
        menu.addItem(item("Minimize", action: #selector(NSWindow.performMiniaturize(_:)), key: "m"))
        menu.addItem(item("Zoom", action: #selector(NSWindow.performZoom(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:))))
        return menu
    }

    private static func helpMenu(_ delegate: AppDelegate) -> NSMenu {
        let menu = NSMenu(title: "Help")
        menu.addItem(item(
            "MarkdStage on GitHub",
            action: #selector(delegate.openProjectWebsite(_:)),
            target: delegate
        ))
        return menu
    }

    private static func menuItem(title: String, submenu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem()
        item.title = title
        item.submenu = submenu
        return item
    }

    private static func item(
        _ title: String,
        action: Selector,
        key: String = "",
        target: AnyObject? = nil
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = target
        return item
    }
}
