package main

import (
	"encoding/binary"
	"errors"
	"math"
	"runtime"
)

const (
	MsgAuthRequest  = 0x01
	MsgAuthResponse = 0x02
	MsgMouseMove    = 0x03
	MsgMouseButton  = 0x04
	MsgScroll       = 0x05
	MsgKeyEvent     = 0x06
	MsgPing         = 0x07
	MsgPong         = 0x08
	MsgPlatformInfo = 0x09
	MsgTypeText     = 0x0A
)

const (
	PlatformMacOS   = 0
	PlatformLinux   = 1
	PlatformWindows = 2
)

const (
	ButtonLeft   = 0
	ButtonRight  = 1
	ButtonMiddle = 2
)

var errMalformed = errors.New("malformed message")

type AuthRequest struct {
	Password string
}

type MouseMove struct {
	DX, DY float32
}

type MouseButtonEvent struct {
	Button  uint8
	Pressed bool
}

type ScrollEvent struct {
	DX, DY float32
}

type KeyEvent struct {
	Keycode uint16
	Pressed bool
}

type TypeTextData struct {
	Text string
}

type Message struct {
	Type        byte
	Auth        *AuthRequest
	MouseMove   *MouseMove
	MouseButton *MouseButtonEvent
	Scroll      *ScrollEvent
	Key         *KeyEvent
	Text        *TypeTextData
}

func ParseMessage(data []byte) (Message, error) {
	if len(data) == 0 {
		return Message{}, errMalformed
	}

	msg := Message{Type: data[0]}

	switch data[0] {
	case MsgAuthRequest:
		if len(data) < 3 {
			return msg, errMalformed
		}
		pwLen := binary.BigEndian.Uint16(data[1:3])
		if len(data) < 3+int(pwLen) {
			return msg, errMalformed
		}
		msg.Auth = &AuthRequest{Password: string(data[3 : 3+pwLen])}

	case MsgMouseMove:
		if len(data) < 9 {
			return msg, errMalformed
		}
		msg.MouseMove = &MouseMove{
			DX: math.Float32frombits(binary.BigEndian.Uint32(data[1:5])),
			DY: math.Float32frombits(binary.BigEndian.Uint32(data[5:9])),
		}

	case MsgMouseButton:
		if len(data) < 3 {
			return msg, errMalformed
		}
		msg.MouseButton = &MouseButtonEvent{
			Button:  data[1],
			Pressed: data[2] == 1,
		}

	case MsgScroll:
		if len(data) < 9 {
			return msg, errMalformed
		}
		msg.Scroll = &ScrollEvent{
			DX: math.Float32frombits(binary.BigEndian.Uint32(data[1:5])),
			DY: math.Float32frombits(binary.BigEndian.Uint32(data[5:9])),
		}

	case MsgKeyEvent:
		if len(data) < 4 {
			return msg, errMalformed
		}
		msg.Key = &KeyEvent{
			Keycode: binary.BigEndian.Uint16(data[1:3]),
			Pressed: data[3] == 1,
		}

	case MsgTypeText:
		if len(data) < 3 {
			return msg, errMalformed
		}
		textLen := binary.BigEndian.Uint16(data[1:3])
		if len(data) < 3+int(textLen) {
			return msg, errMalformed
		}
		msg.Text = &TypeTextData{Text: string(data[3 : 3+textLen])}

	case MsgPing:
		// No payload

	default:
		return msg, errMalformed
	}

	return msg, nil
}

func EncodeAuthResponse(success bool) []byte {
	b := byte(0)
	if success {
		b = 1
	}
	return []byte{MsgAuthResponse, b}
}

func EncodePong() []byte {
	return []byte{MsgPong}
}

func EncodePlatformInfo() []byte {
	var platform byte
	switch runtime.GOOS {
	case "darwin":
		platform = PlatformMacOS
	case "linux":
		platform = PlatformLinux
	case "windows":
		platform = PlatformWindows
	}
	return []byte{MsgPlatformInfo, platform}
}
