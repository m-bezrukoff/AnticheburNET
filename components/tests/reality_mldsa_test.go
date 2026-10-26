//go:build with_utls

package tls

import (
	"github.com/cloudflare/circl/sign/mldsa/mldsa65"
	"testing"
)

func TestAnticheburNETRealityMLDSA(t *testing.T) {
	var seed [32]byte
	seed[0] = 42
	pub, priv := mldsa65.NewKeyFromSeed(&seed)
	transcript := []byte("authenticated REALITY client and server hello")
	signature := make([]byte, mldsa65.SignatureSize)
	if err := mldsa65.SignTo(priv, transcript, nil, false, signature); err != nil {
		t.Fatal(err)
	}
	if err := verifyRealityMLDSA(pub.Bytes(), transcript, signature); err != nil {
		t.Fatal(err)
	}
	for name, values := range map[string][][]byte{
		"bad key":            {[]byte("invalid"), transcript, signature},
		"changed transcript": {pub.Bytes(), []byte("changed"), signature},
		"missing signature":  {pub.Bytes(), transcript, nil},
	} {
		t.Run(name, func(t *testing.T) {
			if verifyRealityMLDSA(values[0], values[1], values[2]) == nil {
				t.Fatal("unauthenticated proof accepted")
			}
		})
	}
	signature[0] ^= 1
	if verifyRealityMLDSA(pub.Bytes(), transcript, signature) == nil {
		t.Fatal("corrupted signature accepted")
	}
}
