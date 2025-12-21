//
//  parser.hpp
//  mt
//
//  Created by Mano Rajesh on 12/20/25.
//

#pragma once

#include <cstddef>
#include <cstdint>
#include <vector>
#include <string>

// ---- Terminal operations your model implements ----
struct TerminalOps {
    virtual ~TerminalOps() = default;
    
    // Printable bytes (may be UTF-8); your model can decode or treat as bytes.
    virtual void putBytes(const uint8_t* bytes, size_t len) = 0;
    
    // C0 controls
    virtual void bell() = 0;
    virtual void carriageReturn() = 0;
    virtual void lineFeed() = 0;
    virtual void backspace() = 0;
    virtual void tab() = 0;
    
    // Cursor + erase
    virtual void cursorUp(int n) = 0;
    virtual void cursorDown(int n) = 0;
    virtual void cursorForward(int n) = 0;
    virtual void cursorBack(int n) = 0;
    virtual void cursorPosition(int row1, int col1) = 0; // 1-based
    virtual void eraseInDisplay(int mode) = 0;           // CSI J (0/1/2/3)
    virtual void eraseInLine(int mode) = 0;              // CSI K (0/1/2)
    
    // SGR (minimal)
    virtual void sgrReset() = 0;
    virtual void sgrBold(bool on) = 0;
    virtual void sgrUnderline(bool on) = 0;
    virtual void sgrInverse(bool on) = 0;
    virtual void sgrFgIndex(int idxOrMinus1) = 0; // -1 default, else 0..15
    virtual void sgrBgIndex(int idxOrMinus1) = 0; // -1 default, else 0..15
};

class TerminalParser {
public:
    explicit TerminalParser(TerminalOps& ops);
    
    void consume(const uint8_t* data, size_t len);
    void reset();
    
    void setMaxStringBytes(size_t n) { _maxStringBytes = n; }
    
private:
    enum class State : uint8_t { Ground, Escape, CSI, OSC, IgnoreString };
    
    // Returns pointer to first "special" byte in [p,end), or end if none.
    // Special = (b < 0x20) || b == 0x7F || b == 0x1B
    static const uint8_t* findSpecial(const uint8_t* p, const uint8_t* end);
    
    void handleControl(uint8_t c);
    void handleEscape(uint8_t c);
    
    void csiStart();
    void csiParamDigit(uint8_t d);
    void csiParamSep();
    void csiFinal(uint8_t finalByte);
    
    void oscStart();
    void oscByte(uint8_t b);
    void oscEnd();
    
    static int clampPositiveDefault(int v, int def);
    
private:
    TerminalOps& _ops;
    State _state = State::Ground;
    
    // CSI
    std::vector<int> _params;
    int _curParam = -1;
    bool _paramHasDigits = false;
    
    // OSC (consumed/ignored)
    std::string _str;
    size_t _maxStringBytes = 4096;
    bool _oscSawEsc = false;
};
