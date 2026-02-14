//go:build linux

package main

import (
	"encoding/binary"
	"fmt"
	"log"
	"os"
	"os/exec"
	"syscall"
	"unsafe"
)

// Linux input constants
const (
	evSyn        = 0x00
	evKey        = 0x01
	evRel        = 0x02
	synReport    = 0x00
	relX         = 0x00
	relY         = 0x01
	relWheel     = 0x08
	relHWheel    = 0x06
	btnLeft      = 0x110
	btnRight     = 0x111
	btnMiddle    = 0x112
	busUSB       = 0x03
	uiDevSetup   = 0x405c5503
	uiDevCreate  = 0x5501
	uiDevDestroy = 0x5502
	uiSetEvBit   = 0x40045564
	uiSetKeyBit  = 0x40045565
	uiSetRelBit  = 0x40045566
)

type inputEvent struct {
	Time  syscall.Timeval
	Type  uint16
	Code  uint16
	Value int32
}

type uinputSetup struct {
	ID           inputID
	Name         [80]byte
	FFEffectsMax uint32
}

type inputID struct {
	BusType uint16
	Vendor  uint16
	Product uint16
	Version uint16
}

type linuxInput struct {
	fd       *os.File
	textTool string
}

// macOS CGKeyCode -> Linux KEY_* mapping
var macToLinux = map[uint16]uint16{
	// Letters
	0x00: 30, // A
	0x01: 31, // S
	0x02: 32, // D
	0x03: 33, // F
	0x04: 35, // H
	0x05: 34, // G
	0x06: 44, // Z
	0x07: 45, // X
	0x08: 46, // C
	0x09: 47, // V
	0x0B: 48, // B
	0x0C: 16, // Q
	0x0D: 17, // W
	0x0E: 18, // E
	0x0F: 19, // R
	0x10: 21, // Y
	0x11: 20, // T
	0x0A: 0,  // (unused on macOS, placeholder)
	0x1F: 24, // O
	0x20: 22, // U
	0x22: 23, // I
	0x23: 25, // P
	0x25: 38, // L
	0x26: 36, // J
	0x28: 37, // K
	0x2D: 49, // N
	0x2E: 50, // M

	// Numbers
	0x12: 2,  // 1
	0x13: 3,  // 2
	0x14: 4,  // 3
	0x15: 5,  // 4
	0x17: 6,  // 5
	0x16: 7,  // 6
	0x1A: 8,  // 7
	0x1C: 9,  // 8
	0x19: 10, // 9
	0x1D: 11, // 0

	// Symbols
	0x1B: 12, // Minus
	0x18: 13, // Equal
	0x21: 26, // LeftBracket
	0x1E: 27, // RightBracket
	0x2A: 43, // Backslash
	0x29: 39, // Semicolon
	0x27: 40, // Quote
	0x2B: 51, // Comma
	0x2F: 52, // Period
	0x2C: 53, // Slash
	0x32: 41, // Grave

	// Control
	0x24: 28,  // Return
	0x30: 15,  // Tab
	0x31: 57,  // Space
	0x33: 14,  // Backspace
	0x35: 1,   // Escape
	0x75: 111, // ForwardDelete

	// Modifiers
	0x37: 125, // Command -> KEY_LEFTMETA
	0x38: 42,  // Shift
	0x39: 58,  // CapsLock
	0x3A: 56,  // Option -> KEY_LEFTALT
	0x3B: 29,  // Control
	0x3C: 54,  // RightShift
	0x3D: 100, // RightOption -> KEY_RIGHTALT
	0x3E: 97,  // RightControl

	// F-keys
	0x7A: 59, // F1
	0x78: 60, // F2
	0x63: 61, // F3
	0x76: 62, // F4
	0x60: 63, // F5
	0x61: 64, // F6
	0x62: 65, // F7
	0x64: 66, // F8
	0x65: 67, // F9
	0x6D: 68, // F10
	0x67: 87, // F11
	0x6F: 88, // F12

	// Navigation
	0x73: 102, // Home
	0x77: 107, // End
	0x74: 104, // PageUp
	0x79: 109, // PageDown
	0x7B: 105, // LeftArrow
	0x7C: 106, // RightArrow
	0x7D: 108, // DownArrow
	0x7E: 103, // UpArrow
}

func NewInputHandler() (InputHandler, error) {
	log.Println("Linux input handler (uinput)")
	log.Println("NOTE: /dev/uinput must be accessible (try: sudo chmod 0660 /dev/uinput && sudo chown root:$USER /dev/uinput)")

	fd, err := os.OpenFile("/dev/uinput", os.O_WRONLY, 0)
	if err != nil {
		return nil, fmt.Errorf("open /dev/uinput: %w", err)
	}

	l := &linuxInput{fd: fd}
	if err := l.setup(); err != nil {
		fd.Close()
		return nil, err
	}

	l.detectTextTool()
	return l, nil
}

func (l *linuxInput) setup() error {
	// Enable event types
	if err := ioctl(l.fd, uiSetEvBit, evKey); err != nil {
		return fmt.Errorf("set EV_KEY: %w", err)
	}
	if err := ioctl(l.fd, uiSetEvBit, evRel); err != nil {
		return fmt.Errorf("set EV_REL: %w", err)
	}

	// Enable all needed keycodes
	allKeys := make(map[uint16]bool)
	for _, code := range macToLinux {
		if code > 0 {
			allKeys[code] = true
		}
	}
	// Also add mouse buttons
	allKeys[btnLeft] = true
	allKeys[btnRight] = true
	allKeys[btnMiddle] = true

	for code := range allKeys {
		if err := ioctl(l.fd, uiSetKeyBit, uintptr(code)); err != nil {
			return fmt.Errorf("set key %d: %w", code, err)
		}
	}

	// Enable relative axes
	for _, axis := range []uintptr{relX, relY, relWheel, relHWheel} {
		if err := ioctl(l.fd, uiSetRelBit, axis); err != nil {
			return fmt.Errorf("set rel axis %d: %w", axis, err)
		}
	}

	// Setup device info
	setup := uinputSetup{
		ID: inputID{
			BusType: busUSB,
			Vendor:  0x1234,
			Product: 0xdead,
			Version: 1,
		},
	}
	copy(setup.Name[:], "dead-kbd virtual input")

	if _, _, errno := syscall.Syscall(syscall.SYS_IOCTL, l.fd.Fd(), uiDevSetup, uintptr(unsafe.Pointer(&setup))); errno != 0 {
		return fmt.Errorf("UI_DEV_SETUP: %w", errno)
	}

	if _, _, errno := syscall.Syscall(syscall.SYS_IOCTL, l.fd.Fd(), uiDevCreate, 0); errno != 0 {
		return fmt.Errorf("UI_DEV_CREATE: %w", errno)
	}

	return nil
}

func (l *linuxInput) emit(evType, code uint16, value int32) {
	ev := inputEvent{
		Type:  evType,
		Code:  code,
		Value: value,
	}
	binary.Write(l.fd, binary.LittleEndian, &ev)
}

func (l *linuxInput) sync() {
	l.emit(evSyn, synReport, 0)
}

func (l *linuxInput) MoveMouse(dx, dy float32) {
	l.emit(evRel, relX, int32(dx))
	l.emit(evRel, relY, int32(dy))
	l.sync()
}

func (l *linuxInput) MouseButton(button uint8, pressed bool) {
	var code uint16
	switch button {
	case ButtonLeft:
		code = btnLeft
	case ButtonRight:
		code = btnRight
	case ButtonMiddle:
		code = btnMiddle
	default:
		return
	}

	val := int32(0)
	if pressed {
		val = 1
	}
	l.emit(evKey, code, val)
	l.sync()
}

func (l *linuxInput) Scroll(dx, dy float32) {
	if dy != 0 {
		l.emit(evRel, relWheel, int32(dy))
	}
	if dx != 0 {
		l.emit(evRel, relHWheel, int32(dx))
	}
	l.sync()
}

func (l *linuxInput) KeyEvent(keycode uint16, pressed bool) {
	linuxCode, ok := macToLinux[keycode]
	if !ok {
		log.Printf("Unknown macOS keycode: 0x%02X", keycode)
		return
	}

	val := int32(0)
	if pressed {
		val = 1
	}
	l.emit(evKey, linuxCode, val)
	l.sync()
}

func (l *linuxInput) detectTextTool() {
	tools := []string{"xdotool", "ydotool"}
	if os.Getenv("WAYLAND_DISPLAY") != "" {
		tools = []string{"wtype", "xdotool", "ydotool"}
	}
	for _, tool := range tools {
		if _, err := exec.LookPath(tool); err == nil {
			l.textTool = tool
			log.Printf("TypeText tool: %s", tool)
			return
		}
	}
	log.Println("WARNING: No text input tool found. Install xdotool (X11) or wtype (Wayland).")
}

func (l *linuxInput) TypeText(text string) {
	var cmd *exec.Cmd
	switch l.textTool {
	case "wtype":
		cmd = exec.Command("wtype", "--", text)
	case "xdotool":
		cmd = exec.Command("xdotool", "type", "--clearmodifiers", "--", text)
	case "ydotool":
		cmd = exec.Command("ydotool", "type", "--", text)
	default:
		return
	}
	if err := cmd.Run(); err != nil {
		log.Printf("TypeText failed: %v", err)
	}
}

func (l *linuxInput) Close() {
	syscall.Syscall(syscall.SYS_IOCTL, l.fd.Fd(), uiDevDestroy, 0)
	l.fd.Close()
}

func ioctl(fd *os.File, request uintptr, val uintptr) error {
	if _, _, errno := syscall.Syscall(syscall.SYS_IOCTL, fd.Fd(), request, val); errno != 0 {
		return errno
	}
	return nil
}
