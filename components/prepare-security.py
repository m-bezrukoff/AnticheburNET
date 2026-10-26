"""Add REALITY ML-DSA verification to the pinned extended core, fail closed."""
from pathlib import Path
import shutil
import sys

source = Path(sys.argv[1])
root = Path(__file__).resolve().parent


def edit(file, before, after):
    path = source / file
    text = path.read_text(encoding="utf-8")
    if after in text:
        return
    if text.count(before) != 1:
        raise SystemExit(f"Pinned security patch context missing: {file}")
    path.write_text(text.replace(before, after), encoding="utf-8", newline="\n")


edit("option/tls.go", 'SupportX25519MLKEM768 bool   `json:"support_x25519mlkem768,omitempty"`',
     'SupportX25519MLKEM768 bool   `json:"support_x25519mlkem768,omitempty"`\n\tMLDSA65Verify string `json:"mldsa65_verify,omitempty"`')
edit("common/tls/reality_client.go", "supportX25519MLKEM768 bool", "supportX25519MLKEM768 bool\n\tmldsa65Verify []byte")
edit("common/tls/reality_client.go",
     "var config Config = &RealityClientConfig{ctx, uClient.(*UTLSClientConfig), publicKey, shortID, options.Reality.SupportX25519MLKEM768}",
     """var verify []byte
    if options.Reality.MLDSA65Verify != "" {
        verify, err = base64.RawURLEncoding.DecodeString(options.Reality.MLDSA65Verify)
        if err != nil || len(verify) != 1952 { return nil, E.New("invalid REALITY mldsa65_verify") }
    }
    var config Config = &RealityClientConfig{ctx, uClient.(*UTLSClientConfig), publicKey, shortID, options.Reality.SupportX25519MLKEM768, verify}""")
edit("common/tls/reality_client.go", "serverName string\n\tauthKey    []byte", "serverName string\n\tauthKey    []byte\n\tmldsa65Verify []byte")
edit("common/tls/reality_client.go", "serverName: e.uClient.ServerName(),", "serverName: e.uClient.ServerName(), mldsa65Verify: e.mldsa65Verify,")
edit("common/tls/reality_client.go", "e.supportX25519MLKEM768,\n", "e.supportX25519MLKEM768,\n        e.mldsa65Verify,\n")
edit("common/tls/reality_client.go", "if bytes.Equal(h.Sum(nil), certs[0].Signature) {",
     """if bytes.Equal(h.Sum(nil), certs[0].Signature) {
            if len(c.mldsa65Verify) != 0 {
                h.Write(c.HandshakeState.Hello.Raw)
                h.Write(c.HandshakeState.ServerHello.Raw)
                if len(certs[0].Extensions) == 0 { return E.New("missing REALITY ML-DSA signature") }
                if err := verifyRealityMLDSA(c.mldsa65Verify, h.Sum(nil), certs[0].Extensions[0].Value); err != nil { return err }
            }""")
shutil.copyfile(root / "sing-box/reality_mldsa.go", source / "common/tls/reality_mldsa.go")
shutil.copyfile(root / "tests/reality_mldsa_test.go", source / "common/tls/reality_mldsa_test.go")
