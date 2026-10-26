package main

import (
	"net/http"
	"os"
)

func main() {
	srv := &http.Server{Addr: "127.0.0.1:" + os.Args[1], Handler: http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { w.Write([]byte("local REALITY TLS target")) })}
	if err := srv.ListenAndServeTLS(os.Args[2], os.Args[3]); err != nil {
		panic(err)
	}
}
