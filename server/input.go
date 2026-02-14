package main

// InputHandler abstracts platform-specific input simulation.
type InputHandler interface {
	MoveMouse(dx, dy float32)
	MouseButton(button uint8, pressed bool)
	Scroll(dx, dy float32)
	KeyEvent(keycode uint16, pressed bool)
	TypeText(text string)
	Close()
}
