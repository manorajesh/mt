//
//  parser.cpp
//  mt
//
//  Created by Mano Rajesh on 12/20/25.
//

#include "parser.hpp"

#include <algorithm>

#if defined(__aarch64__) || defined(__arm64__)
#include <arm_neon.h>
#define TP_NEON 1
#else
#define TP_NEON 0
#endif

TerminalParser::TerminalParser(TerminalOps& ops) : _ops(ops) {}

void TerminalParser::reset() {
    _state = State::Ground;
    _params.clear();
    _curParam = -1;
    _paramHasDigits = false;
    _str.clear();
    _oscSawEsc = false;
}

static inline bool is_special(uint8_t c) {
    return (c < 0x20) || (c == 0x7F) || (c == 0x1B);
}

#if TP_NEON

static inline bool neon_any_special(uint8x16_t v) {
    uint8x16_t is_c0  = vcltq_u8(v, vdupq_n_u8(0x20));
    uint8x16_t is_del = vceqq_u8(v, vdupq_n_u8(0x7F));
    uint8x16_t is_esc = vceqq_u8(v, vdupq_n_u8(0x1B));
    uint8x16_t m = vorrq_u8(is_c0, vorrq_u8(is_del, is_esc));
    return vmaxvq_u8(m) != 0;
}

static inline const uint8_t* findSpecialNeon(const uint8_t* p, const uint8_t* end) {
    while ((size_t)(end - p) >= 64) {
        uint8x16_t v0 = vld1q_u8(p +  0);
        uint8x16_t v1 = vld1q_u8(p + 16);
        uint8x16_t v2 = vld1q_u8(p + 32);
        uint8x16_t v3 = vld1q_u8(p + 48);
        
        if (!neon_any_special(v0) && !neon_any_special(v1) &&
            !neon_any_special(v2) && !neon_any_special(v3)) {
            p += 64;
            continue;
        }
        break;
    }
    
    while ((size_t)(end - p) >= 16) {
        uint8x16_t v = vld1q_u8(p);
        if (!neon_any_special(v)) {
            p += 16;
            continue;
        }
        
        for (int i = 0; i < 16; ++i) {
            uint8_t c = p[i];
            if (is_special(c)) return p + i;
        }
        p += 16;
    }
    
    while (p < end) {
        if (is_special(*p)) return p;
        ++p;
    }
    return end;
}

#endif // TP_NEON

const uint8_t* TerminalParser::findSpecial(const uint8_t* p, const uint8_t* end) {
#if TP_NEON
    return findSpecialNeon(p, end);
#else
    while (p < end) {
        if (is_special(*p)) return p;
        ++p;
    }
    return end;
#endif
}

void TerminalParser::consume(const uint8_t* data, size_t len) {
    const uint8_t* p = data;
    const uint8_t* end = data + len;
    
    while (p < end) {
        switch (_state) {
            case State::Ground: {
                const uint8_t* s = findSpecial(p, end);
                if (s > p) {
                    _ops.putBytes(p, (size_t)(s - p));
                    p = s;
                    if (p >= end) break;
                }
                
                uint8_t c = *p++;
                if (c == 0x1B) {
                    _state = State::Escape;
                } else if (c == 0x7F) {
                    // DEL ignored by default
                } else {
                    handleControl(c);
                }
            } break;
                
            case State::Escape: {
                if (p >= end) return;
                uint8_t c = *p++;
                handleEscape(c);
            } break;
                
            case State::CSI: {
                if (p >= end) return;
                uint8_t c = *p++;
                
                if (c >= '0' && c <= '9') {
                    csiParamDigit(c);
                } else if (c == ';') {
                    csiParamSep();
                } else if (c >= 0x40 && c <= 0x7E) {
                    csiFinal(c);
                    _state = State::Ground;
                } else {
                    // ignore intermediates
                }
            } break;
                
            case State::OSC: {
                if (p >= end) return;
                uint8_t b = *p++;
                
                if (_oscSawEsc) {
                    _oscSawEsc = false;
                    if (b == '\\') { // ST
                        oscEnd();
                        _state = State::Ground;
                        break;
                    }
                }
                
                if (b == 0x07) { // BEL
                    oscEnd();
                    _state = State::Ground;
                } else if (b == 0x1B) {
                    _oscSawEsc = true;
                } else {
                    oscByte(b);
                }
            } break;
                
            case State::IgnoreString: {
                if (p >= end) return;
                uint8_t b = *p++;
                static bool sawEsc = false;
                if (sawEsc) {
                    sawEsc = false;
                    if (b == '\\') _state = State::Ground;
                } else if (b == 0x1B) {
                    sawEsc = true;
                }
            } break;
        }
    }
}

void TerminalParser::handleControl(uint8_t c) {
    switch (c) {
        case 0x07: _ops.bell(); break;
        case '\r': _ops.carriageReturn(); break;
        case '\n': _ops.lineFeed(); break;
        case '\b': _ops.backspace(); break;
        case '\t': _ops.tab(); break;
        default: break;
    }
}

void TerminalParser::handleEscape(uint8_t c) {
    switch (c) {
        case '[':
            csiStart();
            _state = State::CSI;
            break;
        case ']':
            oscStart();
            _state = State::OSC;
            break;
        case '\\':
            _state = State::Ground;
            break;
        default:
            _state = State::Ground;
            break;
    }
}

void TerminalParser::csiStart() {
    _params.clear();
    _curParam = -1;
    _paramHasDigits = false;
}

void TerminalParser::csiParamDigit(uint8_t d) {
    int digit = (int)(d - '0');
    if (_curParam < 0) {
        _curParam = digit;
        _paramHasDigits = true;
    } else {
        _curParam = std::min(_curParam * 10 + digit, 1000000);
        _paramHasDigits = true;
    }
}

void TerminalParser::csiParamSep() {
    if (_curParam < 0 && !_paramHasDigits) _params.push_back(-1);
    else _params.push_back(_curParam);
    _curParam = -1;
    _paramHasDigits = false;
}

int TerminalParser::clampPositiveDefault(int v, int def) {
    return (v <= 0) ? def : v;
}

void TerminalParser::csiFinal(uint8_t finalByte) {
    if (_curParam >= 0 || _paramHasDigits || !_params.empty()) {
        if (_curParam < 0 && !_paramHasDigits) _params.push_back(-1);
        else _params.push_back(_curParam);
    }
    
    auto getP = [&](size_t i) -> int {
        if (i >= _params.size()) return -1;
        return _params[i];
    };
    
    switch (finalByte) {
        case 'A': _ops.cursorUp(clampPositiveDefault(getP(0), 1)); break;
        case 'B': _ops.cursorDown(clampPositiveDefault(getP(0), 1)); break;
        case 'C': _ops.cursorForward(clampPositiveDefault(getP(0), 1)); break;
        case 'D': _ops.cursorBack(clampPositiveDefault(getP(0), 1)); break;
            
        case 'H':
        case 'f': {
            int row = clampPositiveDefault(getP(0), 1);
            int col = clampPositiveDefault(getP(1), 1);
            _ops.cursorPosition(row, col);
        } break;
            
        case 'J': {
            int mode = (getP(0) < 0 ? 0 : getP(0));
            _ops.eraseInDisplay(mode);
        } break;
            
        case 'K': {
            int mode = (getP(0) < 0 ? 0 : getP(0));
            _ops.eraseInLine(mode);
        } break;
            
        case 'm': {
            if (_params.empty()) { _ops.sgrReset(); break; }
            for (size_t i = 0; i < _params.size(); i++) {
                int p = _params[i];
                if (p < 0) p = 0;
                
                if (p == 0) _ops.sgrReset();
                else if (p == 1) _ops.sgrBold(true);
                else if (p == 22) _ops.sgrBold(false);
                else if (p == 4) _ops.sgrUnderline(true);
                else if (p == 24) _ops.sgrUnderline(false);
                else if (p == 7) _ops.sgrInverse(true);
                else if (p == 27) _ops.sgrInverse(false);
                
                else if (p >= 30 && p <= 37) _ops.sgrFgIndex(p - 30);
                else if (p == 39) _ops.sgrFgIndex(-1);
                else if (p >= 90 && p <= 97) _ops.sgrFgIndex(8 + (p - 90));
                
                else if (p >= 40 && p <= 47) _ops.sgrBgIndex(p - 40);
                else if (p == 49) _ops.sgrBgIndex(-1);
                else if (p >= 100 && p <= 107) _ops.sgrBgIndex(8 + (p - 100));
            }
        } break;
            
        default:
            break;
    }
    
    _params.clear();
    _curParam = -1;
    _paramHasDigits = false;
}

void TerminalParser::oscStart() {
    _str.clear();
    _str.reserve(64);
    _oscSawEsc = false;
}

void TerminalParser::oscByte(uint8_t b) {
    if (_str.size() < _maxStringBytes) _str.push_back((char)b);
}

void TerminalParser::oscEnd() {
    // Ignored by default; later parse _str for title, etc.
    _str.clear();
    _oscSawEsc = false;
}
