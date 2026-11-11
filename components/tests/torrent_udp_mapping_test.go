package torrent_test

import (
	"context"
	"encoding/json"
	"sync"
	"testing"
	"time"

	"github.com/sagernet/sing-box/adapter"
	"github.com/sagernet/sing-box/common/sniff"
	C "github.com/sagernet/sing-box/constant"
	"github.com/sagernet/sing-box/option"
	"github.com/sagernet/sing-tun"
	"github.com/sagernet/sing/common/buf"
	M "github.com/sagernet/sing/common/metadata"
	N "github.com/sagernet/sing/common/network"
)

type packetRoute struct {
	destination M.Socksaddr
	firstPeer   M.Socksaddr
	direct      bool
}

type routingProbe struct {
	packets chan packetRoute
	workers sync.WaitGroup
}

func (p *routingProbe) NewPacketConnectionEx(ctx context.Context, conn N.PacketConn, source, firstPeer M.Socksaddr, onClose N.CloseHandlerFunc) {
	p.workers.Add(1)
	defer p.workers.Done()
	defer conn.Close()
	if onClose != nil {
		defer onClose(nil)
	}
	metadata := adapter.InboundContext{Source: source, Destination: firstPeer}
	first := true
	for {
		buffer := buf.NewPacket()
		destination, err := conn.ReadPacket(buffer)
		if err != nil {
			buffer.Release()
			return
		}
		// Like the router, sniff once when this NAT session is routed. Later
		// packets retain that decision even if their destination/protocol differs.
		if first {
			_ = sniff.PeekPacket(ctx, &metadata, buffer.Bytes(), sniff.UTP, sniff.UDPTracker)
			first = false
		}
		buffer.Release()
		p.packets <- packetRoute{destination, firstPeer, metadata.Protocol == C.ProtocolBitTorrent}
	}
}

type discardPacketWriter struct{}

func (discardPacketWriter) WritePacket(buffer *buf.Buffer, _ M.Socksaddr) error {
	buffer.Release()
	return nil
}

func TestTorrentUDPDestinationRouting(t *testing.T) {
	dht := []byte("d1:ad2:id20:aaaaaaaaaaaaaaaaaaaae1:q4:ping1:t2:aa1:y1:qe")
	utp := make([]byte, 20)
	utp[0] = 0x41 // BEP 29: ST_SYN, uTP version 1.
	for _, family := range []struct {
		name, source, bootstrap, peer, other string
	}{
		{"IPv4", "192.0.2.100:47617", "198.51.100.1:6881", "198.51.100.2:6881", "198.51.100.3:6881"},
		{"IPv6", "[2001:db8::100]:47617", "[2001:db8::1]:6881", "[2001:db8::2]:6881", "[2001:db8::3]:6881"},
	} {
		for _, mapping := range []string{"", "address_and_port_dependent"} {
			name := mapping
			if name == "" {
				name = "default_reproduces_leak"
			}
			t.Run(family.name+"/"+name, func(t *testing.T) {
				var options option.TProxyInboundOptions
				if err := json.Unmarshal([]byte(`{"udp_mapping":"`+mapping+`"}`), &options); err != nil {
					t.Fatal(err)
				}
				probe := &routingProbe{packets: make(chan packetRoute, 8)}
				nat := tun.NewUDPNat(tun.UDPNatOptions{
					Handler: probe,
					Prepare: func(_, _ M.Socksaddr, _ any) (bool, context.Context, N.PacketWriter, N.CloseHandlerFunc) {
						return true, context.Background(), discardPacketWriter{}, nil
					},
					Timeout: time.Minute,
					Mapping: tun.NATMapping(options.UDPMapping),
					MaxSize: 16,
				})
				if err := nat.Start(); err != nil {
					t.Fatal(err)
				}
				defer func() { nat.Close(); probe.workers.Wait() }()
				source := M.ParseSocksaddr(family.source)
				bootstrap := M.ParseSocksaddr(family.bootstrap)
				sameAddress := bootstrap
				sameAddress.Port++
				peer := M.ParseSocksaddr(family.peer)
				isolated := mapping == "address_and_port_dependent"
				for _, step := range []struct {
					destination M.Socksaddr
					payload     []byte
					wantDirect  bool
				}{
					{bootstrap, dht, false},
					{sameAddress, utp, isolated},
					{peer, utp, isolated},
					{M.ParseSocksaddr(family.other), dht, false},
					{peer, []byte("later packet retains the peer route"), isolated},
				} {
					nat.NewPacket([][]byte{step.payload}, source, step.destination, nil)
					select {
					case got := <-probe.packets:
						if got.destination != step.destination || got.direct != step.wantDirect {
							t.Fatalf("destination %v: got %+v, want direct=%v", step.destination, got, step.wantDirect)
						}
						wantFirst := bootstrap
						if isolated {
							wantFirst = step.destination
						}
						if got.firstPeer != wantFirst {
							t.Fatalf("destination %v inherited session for %v, want %v", step.destination, got.firstPeer, wantFirst)
						}
					case <-time.After(2 * time.Second):
						t.Fatal("UDP NAT did not dispatch the packet")
					}
				}
			})
		}
	}
}
