//
//  TerminalView.swift
//  mt
//
//  Created by Mano Rajesh on 10/14/24.
//

import Cocoa
import CoreText

class TerminalView: NSView {
    var buffer: Buffer
    var pty: Pty?
    var fontSize: CGFloat = 10
    var font: NSFont
    var cellHeight: CGFloat
    var cellWidth: CGFloat
    
    private var textLayers: [CATextLayer] = []
    private var cursorLayer: CALayer!
    
    // Off-screen buffer for double buffering
    private var offscreenBuffer: CALayer!
    
    init(buffer: Buffer) {
        self.buffer = buffer
        font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        cellHeight = fontSize + 4
        
        // Calculate cellWidth using Core Text for accurate glyph advancement
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let attrString = NSAttributedString(string: " ", attributes: attributes)
        let size = attrString.size()
        cellWidth = size.width
        
        super.init(frame: .init())
        self.wantsLayer = true
        self.layer?.backgroundColor = NSColor.black.cgColor
        
        // Initialize the off-screen buffer
        offscreenBuffer = CALayer()
        offscreenBuffer.frame = self.bounds
        offscreenBuffer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
        offscreenBuffer.isOpaque = true
        offscreenBuffer.backgroundColor = NSColor.black.cgColor
        self.layer?.addSublayer(offscreenBuffer)  // Add as a sublayer
        
        setupTextLayers()
        setupCursorLayer()
        
        self.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(frameDidChange), name: NSView.frameDidChangeNotification, object: self)
        
        refresh()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc func frameDidChange() {
        let newRows = Int(bounds.height / cellHeight)
        let newCols = Int(bounds.width / cellWidth)
        
        pty?.resizePty(rows: UInt16(newRows), cols: UInt16(newCols))
        buffer.resizeViewport(rows: newRows, cols: newCols)
        
        cursorLayer.frame = bounds
        offscreenBuffer.frame = bounds
        
        setupTextLayers()
        updateOffscreenBuffer()
        updateCursorLayer()
    }
    
    private func setupTextLayers() {
        let rows = Int(bounds.height / cellHeight)
        textLayers.forEach({ $0.removeFromSuperlayer() })
        textLayers.removeAll()
        
        for rowIndex in 0..<rows {
            let textLayer = CATextLayer()
            textLayer.frame = frameForRow(rowIndex, rows)
            textLayer.alignmentMode = .left
            textLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
            textLayer.truncationMode = .none
            textLayer.isWrapped = false
            textLayer.backgroundColor = NSColor.clear.cgColor
            textLayer.font = font
            textLayer.fontSize = fontSize
            textLayer.foregroundColor = NSColor.white.cgColor
            textLayer.removeAllAnimations()
            offscreenBuffer.addSublayer(textLayer)  // Add to offscreenBuffer
            textLayers.append(textLayer)
        }
    }
    
    private func frameForRow(_ rowIndex: Int, _ rows: Int) -> CGRect {
        let yPosition = CGFloat(rows - rowIndex) * cellHeight
        return CGRect(origin: CGPoint(x: 0, y: yPosition), size: CGSize(width: bounds.width, height: cellHeight + 4))
    }
    
    private func setupCursorLayer() {
        cursorLayer = CALayer()
        cursorLayer.frame = CGRect(x: 0, y: 0, width: cellWidth, height: cellHeight)
        cursorLayer.backgroundColor = NSColor.gray.cgColor
        cursorLayer.isHidden = false
        offscreenBuffer.addSublayer(cursorLayer)  // Add cursor to offscreenBuffer
        
        let blinkAnimation = CABasicAnimation(keyPath: "opacity")
        blinkAnimation.fromValue = 1.0
        blinkAnimation.toValue = 0.0
        blinkAnimation.duration = 0.5
        blinkAnimation.autoreverses = true
        blinkAnimation.repeatCount = .infinity
        cursorLayer.add(blinkAnimation, forKey: "blink")
        
        updateCursorLayer()
    }
    
    private func updateOffscreenBuffer() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for index in buffer.getDirtyRows() {
            textLayers[index].string = buffer.viewportBuffer[index]
        }
        CATransaction.commit()
    }
    
    private func updateCursorLayer() {
        let cursorX = buffer.cursorPosition.x
        let cursorY = buffer.cursorPosition.y - buffer.viewport.topRow
        
        let visibleRows = Int(bounds.height / cellHeight)
        guard cursorY >= 0, cursorY < visibleRows else {
            cursorLayer.isHidden = true
            return
        }
        
        cursorLayer.isHidden = false
        let cursorRect = CGRect(
            x: CGFloat(cursorX) * cellWidth,
            y: bounds.height - CGFloat(cursorY) * cellHeight,
            width: cellWidth,
            height: cellHeight
        )
        cursorLayer.frame = cursorRect
    }
    
    func refresh() {
        updateOffscreenBuffer()
        updateCursorLayer()
    }
    
    override var acceptsFirstResponder: Bool {
        return true
    }
    
    override func becomeFirstResponder() -> Bool {
        return true
    }
    
    override func resignFirstResponder() -> Bool {
        return true
    }
    
    override func keyDown(with event: NSEvent) {
        interpretKeyEvents([event])
        let keyCode = event.keyCode
        let modifiers = event.modifierFlags
        
        if modifiers.contains(.control) {
            switch keyCode {
            case 0x08:
                pty?.sendSpecialKey(.ctrlC)
            case 0x02:
                pty?.sendSpecialKey(.ctrlD)
            case 0x06:
                pty?.sendSpecialKey(.ctrlZ)
            default:
                super.keyDown(with: event)
            }
        } else {
            switch keyCode {
            case 0x24:
                pty?.sendSpecialKey(.enter)
            case 0x33:
                buffer.handleBackspace()
                pty?.sendSpecialKey(.backspace)
            case 0x7E:
                pty?.sendSpecialKey(.arrowUp)
            case 0x7D:
                pty?.sendSpecialKey(.arrowDown)
            case 0x7B:
                pty?.sendSpecialKey(.arrowLeft)
            case 0x7C:
                pty?.sendSpecialKey(.arrowRight)
            default:
                super.keyDown(with: event)
            }
        }
    }
    
    override func scrollWheel(with event: NSEvent) {}
    
    override func insertText(_ insertString: Any) {
        if let text = insertString as? String {
            handleTextInput(text)
        }
    }
    
    private func handleTextInput(_ text: String) {
        pty?.sendInput(text)
        refresh()
    }
    
    func setPty(_ pty: Pty) {
        self.pty = pty
    }
}

enum ArrowDirection {
    case left, right, up, down
}
