package main

import (
	"flag"
	"fmt"
	"log"
	"net"
	"os"
	"os/signal"
	"syscall"

	"golang.org/x/crypto/bcrypt"
)

func main() {
	log.SetOutput(os.Stderr)
	log.SetFlags(log.Ltime | log.Lmsgprefix)
	log.SetPrefix("[deadkbd] ")

	port := flag.Int("port", 9877, "Port to listen on")
	password := flag.String("password", "", "Required password for authentication")
	tlsCert := flag.String("tls-cert", "", "Path to TLS certificate (optional)")
	tlsKey := flag.String("tls-key", "", "Path to TLS private key (optional)")
	flag.Parse()

	if *password == "" {
		fmt.Fprintln(os.Stderr, "Error: --password is required")
		flag.Usage()
		os.Exit(1)
	}

	hash, err := bcrypt.GenerateFromPassword([]byte(*password), bcrypt.DefaultCost)
	if err != nil {
		log.Fatalf("Failed to hash password: %v", err)
	}

	input, err := NewInputHandler()
	if err != nil {
		log.Fatalf("Failed to initialize input handler: %v", err)
	}
	defer input.Close()

	srv := NewServer(*port, hash, input, *tlsCert, *tlsKey)

	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)
	go func() {
		<-sigCh
		log.Println("Shutting down...")
		srv.Shutdown()
	}()

	printBanner(*port, *tlsCert != "")

	if err := srv.ListenAndServe(); err != nil {
		log.Fatalf("Server error: %v", err)
	}
}

func printBanner(port int, tls bool) {
	scheme := "ws"
	if tls {
		scheme = "wss"
	}

	fmt.Println("dead-kbd server")
	fmt.Println("───────────────")
	fmt.Printf("Listening on port %d\n", port)

	addrs, err := net.InterfaceAddrs()
	if err == nil {
		for _, addr := range addrs {
			if ipNet, ok := addr.(*net.IPNet); ok && !ipNet.IP.IsLoopback() && ipNet.IP.To4() != nil {
				fmt.Printf("Connect: %s://%s:%d\n", scheme, ipNet.IP, port)
			}
		}
	}

	fmt.Println()
}
