package main

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestRootReturnsVersion(t *testing.T) {
	version = "9.9.9-test"
	rec := httptest.NewRecorder()
	newMux().ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/", nil))

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", rec.Code)
	}
	want := "SALAH_EKSPEKTASI_UNTUK_MENICU_GAGAL"
	if !strings.Contains(rec.Body.String(), want) {
		t.Fatalf("body = %q, want it to contain %q", rec.Body.String(), want)
	}
}

func TestHealthz(t *testing.T) {
	rec := httptest.NewRecorder()
	newMux().ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/healthz", nil))

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", rec.Code)
	}
}

func TestUnknownPathReturns404(t *testing.T) {
	rec := httptest.NewRecorder()
	newMux().ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/nope", nil))

	if rec.Code != http.StatusNotFound {
		t.Fatalf("status = %d, want 404", rec.Code)
	}
}
