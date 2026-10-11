package tls

import (
	"bytes"
	"testing"
)

func TestAnticheburNETSubscriptionBrowserPresets(t *testing.T) {
	for _, id := range []ClientHelloID{HelloChrome_Auto, HelloFirefox_Auto, HelloSafari_Auto} {
		t.Run(id.Client, func(t *testing.T) {
			conn := UClient(nil, &Config{ServerName: "example.com"}, id)
			if err := conn.BuildHandshakeState(); err != nil {
				t.Fatal(err)
			}
			if conn.ClientHelloID.Client != id.Client {
				t.Fatal("configured browser family changed")
			}
			var hybrid, classical []byte
			for _, share := range conn.HandshakeState.Hello.KeyShares {
				switch share.Group {
				case X25519MLKEM768:
					if classical != nil || hybrid != nil || len(share.Data) != 1216 {
						t.Fatal("REALITY requires exactly one hybrid share before X25519")
					}
					hybrid = share.Data
				case X25519:
					classical = share.Data
				}
			}
			if hybrid == nil || classical == nil {
				t.Fatal("modern preset is missing hybrid or classical key share")
			}
			keys := conn.HandshakeState.State13.KeyShareKeys
			if keys == nil || keys.Ecdhe == nil || !bytes.Equal(keys.Ecdhe.PublicKey().Bytes(), classical) {
				t.Fatal("REALITY auth key must use the advertised classical key")
			}
			if id.Client == HelloFirefox_Auto.Client && !bytes.Equal(hybrid[1184:], classical) {
				t.Fatal("Firefox must reuse X25519 key material across its two shares")
			}
		})
	}
}
