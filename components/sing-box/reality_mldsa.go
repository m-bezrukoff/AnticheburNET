//go:build with_utls

package tls

import (
	"fmt"
	"github.com/cloudflare/circl/sign/mldsa/mldsa65"
)

// The transcript digest and certificate extension match Xray's REALITY proof.
// Authentication is accepted only after both the HMAC and this proof succeed.
func verifyRealityMLDSA(publicKey, transcript, signature []byte) error {
	key, err := mldsa65.Scheme().UnmarshalBinaryPublicKey(publicKey)
	if err != nil {
		return fmt.Errorf("invalid REALITY ML-DSA key: %w", err)
	}
	if !mldsa65.Verify(key.(*mldsa65.PublicKey), transcript, nil, signature) {
		return fmt.Errorf("invalid REALITY ML-DSA signature")
	}
	return nil
}
