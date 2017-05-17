//
//  LayoutViewController.swift
//  Layout
//
//  Created by Nick Lockwood on 27/04/2017.
//  Copyright © 2017 Nick Lockwood. All rights reserved.
//

import UIKit

open class LayoutViewController: UIViewController, LayoutDelegate {

    public var layoutNode: LayoutNode? = nil {
        didSet {
            if layoutNode?.viewController == self {
                // TODO: should this use case be allowed at all?
                return
            }
            oldValue?.unmount()
            if let layoutNode = layoutNode {
                do {
                    try layoutNode.mount(in: self)
                    _dismissError()
                    layoutDidLoad()
                } catch {
                    layoutError(LayoutError(error, for: layoutNode))
                }
            }
        }
    }

    private var _loader: LayoutLoader?
    private var _state: Any = ()
    private var _errorNode: LayoutNode?
    private var _error: LayoutError? = nil

    private var isReloadable: Bool {
        return layoutNode != nil || _loader != nil
    }

    public func loadLayout(
        named: String? = nil,
        bundle: Bundle = Bundle.main,
        relativeTo: String = #file,
        state: Any = (),
        constants: [String: Any] = [:])
    {
        assert(Thread.isMainThread)
        let name = named ?? "\(type(of: self))".components(separatedBy: ".").last!
        guard let xmlURL = bundle.url(forResource: name, withExtension: nil) ??
            bundle.url(forResource: name, withExtension: "xml") else {
            layoutError(.message("No layout XML file found for `\(name)`"))
            return
        }
        loadLayout(
            withContentsOfURL: xmlURL,
            relativeTo: relativeTo,
            state: state,
            constants: constants
        )
    }

    public func loadLayout(
        withContentsOfURL xmlURL: URL,
        relativeTo: String? = #file,
        state: Any = (),
        constants: [String: Any] = [:],
        completion: ((LayoutError?) -> Void)? = nil)
    {
        if _loader == nil {
            _loader = LayoutLoader()
        }
        _loader?.loadLayout(
            withContentsOfURL: xmlURL,
            relativeTo: relativeTo,
            state: state,
            constants: constants
        ) { layoutNode, error in
            if let layoutNode = layoutNode {
                self.layoutNode = layoutNode
            }
            if let error = error {
                self.layoutError(error)
            }
            completion?(error)
        }
    }

    @objc private func _reloadLayout() {

        // Pass message up the chain to the root LayoutViewController
        var responder: UIResponder = self
        while let nextResponder = responder.next {
            if let layoutController = nextResponder as? LayoutViewController {
                layoutController._reloadLayout()
                return
            }
            responder = nextResponder
        }

        reloadLayout(withCompletion: nil)
    }

    public func reloadLayout(withCompletion completion: ((LayoutError?) -> Void)? = nil) {
        if let loader = _loader {
            loader.reloadLayout { layoutNode, error in
                if let layoutNode = layoutNode {
                    self.layoutNode = layoutNode
                }
                if let error = error {
                    self.layoutError(error)
                }
                completion?(error)
            }
        } else {
            let node = layoutNode
            layoutNode?.state = _state
            layoutNode = node
            completion?(nil)
        }
    }

    open override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        do {
            if let errorNode = _errorNode {
                try errorNode.update()
                view.bringSubview(toFront: errorNode.view)
            } else {
                try layoutNode?.update()
            }
        } catch {
            layoutError(LayoutError(error, for: layoutNode))
        }
    }

    open func layoutDidLoad() {
        // Override in subclass
    }

    open func layoutNode(_ layoutNode: LayoutNode, didDetectError error: LayoutError) {
        // TODO: should we just get rid of the layoutError() method?
        layoutError(error)
    }

    open func layoutError(_ error: LayoutError) {

        // Pass error up the chain to the first VC that can handle it
        var responder: UIResponder = self
        while let nextResponder = responder.next {
            if let layoutController = nextResponder as? LayoutViewController {
                layoutController.layoutError(error)
                return
            }
            responder = nextResponder
        }

        // If error has no changes, just re-display it
        if let errorNode = _errorNode, error == _error {
            view.bringSubview(toFront: errorNode.view)
            errorNode.view.alpha = 0.5
            UIView.animate(withDuration: 0.25) {
                errorNode.view.alpha = 1
            }
            return
        }

        // Display error
        _dismissError()
        _error = error
        _errorNode = LayoutNode(
            view: UIControl(),
            constants: [
                "error": error
            ],
            expressions: [
                "width": "100%",
                "height": "100%",
                "backgroundColor": "#f00",
                "touchDown": "_reloadLayout",
            ],
            children: [
                LayoutNode(
                    view: UILabel(),
                    expressions: [
                        "top": "40% - (height) / 2",
                        "width": "min(auto, 100% - 40)",
                        "left": "(100% - width) / 2",
                        "text": "{error}",
                        "textColor": "#fff",
                        "numberOfLines": "0",
                    ]
                ),
                LayoutNode(
                    view: UILabel(),
                    expressions: [
                        "top": "previous.bottom + 30",
                        "width": "auto",
                        "left": "(100% - width) / 2",
                        "text": "[\(reloadMessage)]",
                        "textColor": "rgba(255,255,255,0.6)",
                        "isHidden": "\(!isReloadable)",
                    ]
                ),
            ]
        )
        _errorNode!.view.alpha = 0
        try? _errorNode!.mount(in: self)
        UIView.animate(withDuration: 0.25) {
            self._errorNode?.view.alpha = 1
        }
    }

    private func _dismissError() {
        if let errorNode = _errorNode {
            view.bringSubview(toFront: errorNode.view)
            UIView.animate(withDuration: 0.25, animations: {
                errorNode.view.alpha = 0
            }, completion: { _ in
                errorNode.unmount()
            })
            _errorNode = nil
        }
        _error = nil
    }

    #if arch(i386) || arch(x86_64)

    // MARK: Only applicable when running in the simulator

    private let _keyCommands = [
        UIKeyCommand(input: "r", modifierFlags: .command, action: #selector(_reloadLayout))
    ]

    open override var keyCommands: [UIKeyCommand]? {
        return _keyCommands
    }

    private let reloadMessage = "Tap or Cmd-R to Reload"

    #else

    private let reloadMessage = "Tap to Reload"

    #endif
}