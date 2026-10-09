package engine

import (
	"strings"
	"testing"

	"github.com/google/uuid"
)

func TestBoundedContextIdentities(t *testing.T) {
	id := uuid.NewString()
	if _, e := contextIDs([]string{id, strings.ToUpper(id)}, 10); e == nil {
		t.Fatal("duplicate normalized identities accepted")
	}
	if _, e := contextIDs([]string{"garment"}, 10); e == nil {
		t.Fatal("untrusted identity accepted")
	}
	if _, e := contextIDs([]string{id}, 0); e == nil {
		t.Fatal("record limit ignored")
	}
	keys, e := contextIDs([]string{strings.ToUpper(id)}, 10)
	if e != nil || keys[0] != id {
		t.Fatal("identity normalization failed", e)
	}
}
