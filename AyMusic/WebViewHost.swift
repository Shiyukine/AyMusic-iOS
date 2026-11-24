//
//  WebViewHost.swift
//  AyMusic
//
//  WebKit only lets <audio>/<video> elements load once the web view is in a UIWindow (Page::canStartMedia follows
//  ActivityState::IsInWindow). When iOS launches the app in background (Control Center play while it was closed),
//  SwiftUI builds the view and loads the page but attaches no window until the app comes to the foreground, so no
//  music could start. WebViewHostView keeps the WKWebView in an offscreen window while the SwiftUI hierarchy has
//  none, and moves it into the real one as soon as one exists (and back when it leaves, e.g. on a navigation push).
//

import UIKit
import WebKit

final class OffscreenWindow {
    static let shared = OffscreenWindow()
    
    private lazy var window: UIWindow = {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let w = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: UIScreen.main.bounds)
        w.frame = UIScreen.main.bounds
        w.windowLevel = UIWindow.Level(rawValue: -1000)
        w.alpha = 0
        w.isUserInteractionEnabled = false
        w.rootViewController = UIViewController()
        return w
    }()
    
    func park(_ view: UIView) {
        window.isHidden = false
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.frame = window.bounds
        window.addSubview(view)
    }
    
    func hideIfEmpty() {
        if window.subviews.isEmpty { window.isHidden = true }
    }
}

final class WebViewHostView: UIView {
    let webView: WKWebView
    
    init(webView: WKWebView) {
        self.webView = webView
        super.init(frame: .zero)
        backgroundColor = .clear
        // No window yet at this point: park the web view so WebKit considers the page "in window" right away
        OffscreenWindow.shared.park(webView)
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            webView.frame = bounds
            addSubview(webView)
            OffscreenWindow.shared.hideIfEmpty()
        } else if webView.superview === self {
            OffscreenWindow.shared.park(webView)
        }
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        if webView.superview === self { webView.frame = bounds }
    }
}
