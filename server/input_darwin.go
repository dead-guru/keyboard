//go:build darwin

package main

/*
#cgo LDFLAGS: -framework CoreGraphics
#include <CoreGraphics/CoreGraphics.h>

// Wrapper for variadic CGEventCreateScrollWheelEvent (cgo cannot call variadic C functions directly)
static CGEventRef createScrollEvent(int32_t dy, int32_t dx) {
    return CGEventCreateScrollWheelEvent(NULL, kCGScrollEventUnitPixel, 2, dy, dx);
}

// Type Unicode text regardless of active keyboard layout
static void typeUnicodeText(const uint16_t *chars, int count) {
    CGEventRef keyDown = CGEventCreateKeyboardEvent(NULL, 0, true);
    CGEventKeyboardSetUnicodeString(keyDown, (UniCharCount)count, chars);
    CGEventPost(kCGHIDEventTap, keyDown);
    CFRelease(keyDown);

    CGEventRef keyUp = CGEventCreateKeyboardEvent(NULL, 0, false);
    CGEventPost(kCGHIDEventTap, keyUp);
    CFRelease(keyUp);
}
*/
import "C"

import (
	"log"
	"unicode/utf16"
	"unsafe"
)

// CGEvent modifier flag masks
const (
	flagCapsLock uint64 = 0x00010000
	flagShift    uint64 = 0x00020000
	flagControl  uint64 = 0x00040000
	flagOption   uint64 = 0x00080000
	flagCommand  uint64 = 0x00100000
)

type darwinInput struct {
	curX, curY   float64
	screenW      float64
	screenH      float64
	leftPressed  bool
	rightPressed bool
	modFlags     uint64
}

func NewInputHandler() (InputHandler, error) {
	log.Println("macOS input handler initialized")
	log.Println("NOTE: Accessibility permissions are required (System Settings > Privacy & Security > Accessibility)")

	d := &darwinInput{}

	// Get current mouse position
	event := C.CGEventCreate(0)
	point := C.CGEventGetLocation(event)
	C.CFRelease(C.CFTypeRef(event))
	d.curX = float64(point.x)
	d.curY = float64(point.y)

	// Get main display size
	mainDisplay := C.CGMainDisplayID()
	d.screenW = float64(C.CGDisplayPixelsWide(mainDisplay))
	d.screenH = float64(C.CGDisplayPixelsHigh(mainDisplay))

	return d, nil
}

func (d *darwinInput) MoveMouse(dx, dy float32) {
	d.curX += float64(dx)
	d.curY += float64(dy)

	// Clamp to screen bounds
	d.curX = clamp(d.curX, 0, d.screenW-1)
	d.curY = clamp(d.curY, 0, d.screenH-1)

	point := C.CGPointMake(C.CGFloat(d.curX), C.CGFloat(d.curY))

	eventType := C.kCGEventMouseMoved
	mouseButton := C.kCGMouseButtonLeft

	if d.leftPressed {
		eventType = C.kCGEventLeftMouseDragged
	} else if d.rightPressed {
		eventType = C.kCGEventRightMouseDragged
		mouseButton = C.kCGMouseButtonRight
	}

	event := C.CGEventCreateMouseEvent(0, C.CGEventType(eventType), point, C.CGMouseButton(mouseButton))
	C.CGEventPost(C.kCGHIDEventTap, event)
	C.CFRelease(C.CFTypeRef(event))
}

func (d *darwinInput) MouseButton(button uint8, pressed bool) {
	point := C.CGPointMake(C.CGFloat(d.curX), C.CGFloat(d.curY))

	var eventType C.CGEventType
	var mouseButton C.CGMouseButton

	switch button {
	case ButtonLeft:
		d.leftPressed = pressed
		mouseButton = C.kCGMouseButtonLeft
		if pressed {
			eventType = C.kCGEventLeftMouseDown
		} else {
			eventType = C.kCGEventLeftMouseUp
		}
	case ButtonRight:
		d.rightPressed = pressed
		mouseButton = C.kCGMouseButtonRight
		if pressed {
			eventType = C.kCGEventRightMouseDown
		} else {
			eventType = C.kCGEventRightMouseUp
		}
	case ButtonMiddle:
		mouseButton = C.kCGMouseButtonCenter
		if pressed {
			eventType = C.kCGEventOtherMouseDown
		} else {
			eventType = C.kCGEventOtherMouseUp
		}
	default:
		return
	}

	event := C.CGEventCreateMouseEvent(0, eventType, point, mouseButton)
	C.CGEventPost(C.kCGHIDEventTap, event)
	C.CFRelease(C.CFTypeRef(event))
}

func (d *darwinInput) Scroll(dx, dy float32) {
	event := C.createScrollEvent(C.int32_t(dy), C.int32_t(dx))
	C.CGEventPost(C.kCGHIDEventTap, event)
	C.CFRelease(C.CFTypeRef(event))
}

func modifierFlag(keycode uint16) uint64 {
	switch keycode {
	case 0x38, 0x3C: // Left/Right Shift
		return flagShift
	case 0x3B, 0x3E: // Left/Right Control
		return flagControl
	case 0x3A, 0x3D: // Left/Right Option
		return flagOption
	case 0x37, 0x36: // Left/Right Command
		return flagCommand
	case 0x39: // CapsLock
		return flagCapsLock
	default:
		return 0
	}
}

func (d *darwinInput) KeyEvent(keycode uint16, pressed bool) {
	if flag := modifierFlag(keycode); flag != 0 {
		if pressed {
			d.modFlags |= flag
		} else {
			d.modFlags &^= flag
		}
	}

	event := C.CGEventCreateKeyboardEvent(0, C.CGKeyCode(keycode), C.bool(pressed))
	C.CGEventSetFlags(event, C.CGEventFlags(d.modFlags))
	C.CGEventPost(C.kCGHIDEventTap, event)
	C.CFRelease(C.CFTypeRef(event))
}

func (d *darwinInput) TypeText(text string) {
	runes := []rune(text)
	if len(runes) == 0 {
		return
	}
	chars := utf16.Encode(runes)
	C.typeUnicodeText((*C.uint16_t)(unsafe.Pointer(&chars[0])), C.int(len(chars)))
}

func (d *darwinInput) Close() {}

func clamp(v, min, max float64) float64 {
	if v < min {
		return min
	}
	if v > max {
		return max
	}
	return v
}
