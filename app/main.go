package main

import (
	"context"
	"flag"
	"fmt"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"
)

// version di-inject saat build: go build -ldflags="-X main.version=1.0.0"
var version = "dev"

func newMux() *http.ServeMux {
	mux := http.NewServeMux()

	mux.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		fmt.Fprintln(w, "ok")
	})

	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/" {
			http.NotFound(w, r)
			return
		}
		fmt.Fprintf(w, "Hello, DevOps! version=%s\n", version)
	})

	return mux
}

func port() string {
	if p := os.Getenv("PORT"); p != "" {
		return p
	}
	return "8080"
}

// healthcheck dipakai oleh Docker HEALTHCHECK (image scratch tidak punya curl/wget).
func healthcheck() int {
	client := http.Client{Timeout: 2 * time.Second}
	resp, err := client.Get("http://127.0.0.1:" + port() + "/healthz")
	if err != nil {
		return 1
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return 1
	}
	return 0
}

func main() {
	hc := flag.Bool("healthcheck", false, "jalankan health check lalu exit (0 = sehat)")
	flag.Parse()
	if *hc {
		os.Exit(healthcheck())
	}

	srv := &http.Server{
		Addr:              ":" + port(),
		Handler:           newMux(),
		ReadHeaderTimeout: 5 * time.Second,
	}

	go func() {
		fmt.Println("listening on :" + port() + " version=" + version)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			fmt.Println("server error:", err)
			os.Exit(1)
		}
	}()

	// Graceful shutdown: docker stop/restart mengirim SIGTERM.
	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGINT, syscall.SIGTERM)
	<-stop

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	_ = srv.Shutdown(ctx)
	fmt.Println("shutdown complete")
}
