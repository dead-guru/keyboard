package main

import (
	"context"
	"fmt"
	"log"
	"net/http"
	"sync"
	"time"

	"github.com/gorilla/websocket"
	"golang.org/x/crypto/bcrypt"
)

var upgrader = websocket.Upgrader{
	CheckOrigin:       func(r *http.Request) bool { return true },
	EnableCompression: false,
}

type Server struct {
	port     int
	passHash []byte
	input    InputHandler
	tlsCert  string
	tlsKey   string
	httpSrv  *http.Server
	conns    sync.Map // remote addr -> *websocket.Conn
}

func NewServer(port int, passHash []byte, input InputHandler, tlsCert, tlsKey string) *Server {
	return &Server{
		port:     port,
		passHash: passHash,
		input:    input,
		tlsCert:  tlsCert,
		tlsKey:   tlsKey,
	}
}

func (s *Server) ListenAndServe() error {
	mux := http.NewServeMux()
	mux.HandleFunc("/", s.handleWS)

	s.httpSrv = &http.Server{
		Addr:    fmt.Sprintf(":%d", s.port),
		Handler: mux,
	}

	if s.tlsCert != "" && s.tlsKey != "" {
		return s.httpSrv.ListenAndServeTLS(s.tlsCert, s.tlsKey)
	}
	return s.httpSrv.ListenAndServe()
}

func (s *Server) Shutdown() {
	closeMsg := websocket.FormatCloseMessage(websocket.CloseGoingAway, "")
	s.conns.Range(func(key, value any) bool {
		conn := value.(*websocket.Conn)
		conn.WriteMessage(websocket.CloseMessage, closeMsg)
		conn.Close()
		return true
	})

	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	s.httpSrv.Shutdown(ctx)
}

func (s *Server) handleWS(w http.ResponseWriter, r *http.Request) {
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Printf("Upgrade failed: %v", err)
		return
	}
	defer conn.Close()

	remote := conn.RemoteAddr().String()
	log.Printf("New connection from %s", remote)

	s.conns.Store(remote, conn)
	defer s.conns.Delete(remote)

	if !s.authenticate(conn, remote) {
		return
	}

	s.messageLoop(conn, remote)
}

func (s *Server) authenticate(conn *websocket.Conn, remote string) bool {
	conn.SetReadDeadline(time.Now().Add(10 * time.Second))

	_, data, err := conn.ReadMessage()
	if err != nil {
		log.Printf("[%s] Auth read error: %v", remote, err)
		return false
	}

	conn.SetReadDeadline(time.Time{})

	msg, err := ParseMessage(data)
	if err != nil || msg.Type != MsgAuthRequest {
		log.Printf("[%s] Invalid auth message", remote)
		conn.WriteMessage(websocket.BinaryMessage, EncodeAuthResponse(false))
		return false
	}

	if err := bcrypt.CompareHashAndPassword(s.passHash, []byte(msg.Auth.Password)); err != nil {
		log.Printf("[%s] Authentication failed", remote)
		conn.WriteMessage(websocket.BinaryMessage, EncodeAuthResponse(false))
		return false
	}

	log.Printf("[%s] Authenticated", remote)
	conn.WriteMessage(websocket.BinaryMessage, EncodeAuthResponse(true))
	conn.WriteMessage(websocket.BinaryMessage, EncodePlatformInfo())
	return true
}

func (s *Server) messageLoop(conn *websocket.Conn, remote string) {
	pressedKeys := make(map[uint16]bool)
	pressedButtons := make(map[uint8]bool)

	defer func() {
		for keycode := range pressedKeys {
			s.input.KeyEvent(keycode, false)
		}
		for button := range pressedButtons {
			s.input.MouseButton(button, false)
		}
		if len(pressedKeys) > 0 || len(pressedButtons) > 0 {
			log.Printf("[%s] Released %d keys and %d buttons on disconnect", remote, len(pressedKeys), len(pressedButtons))
		}
	}()

	for {
		_, data, err := conn.ReadMessage()
		if err != nil {
			if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseNormalClosure) {
				log.Printf("[%s] Read error: %v", remote, err)
			} else {
				log.Printf("[%s] Disconnected", remote)
			}
			return
		}

		msg, err := ParseMessage(data)
		if err != nil {
			log.Printf("[%s] Malformed message, ignoring", remote)
			continue
		}

		switch msg.Type {
		case MsgMouseMove:
			s.input.MoveMouse(msg.MouseMove.DX, msg.MouseMove.DY)
		case MsgMouseButton:
			if msg.MouseButton.Pressed {
				pressedButtons[msg.MouseButton.Button] = true
			} else {
				delete(pressedButtons, msg.MouseButton.Button)
			}
			s.input.MouseButton(msg.MouseButton.Button, msg.MouseButton.Pressed)
		case MsgScroll:
			s.input.Scroll(msg.Scroll.DX, msg.Scroll.DY)
		case MsgKeyEvent:
			if msg.Key.Pressed {
				pressedKeys[msg.Key.Keycode] = true
			} else {
				delete(pressedKeys, msg.Key.Keycode)
			}
			s.input.KeyEvent(msg.Key.Keycode, msg.Key.Pressed)
		case MsgTypeText:
			s.input.TypeText(msg.Text.Text)
		case MsgPing:
			conn.WriteMessage(websocket.BinaryMessage, EncodePong())
		}
	}
}
