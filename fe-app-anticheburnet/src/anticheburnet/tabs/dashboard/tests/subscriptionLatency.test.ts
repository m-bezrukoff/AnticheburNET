import { describe, expect, it } from 'vitest';
import { AnticheburNET } from '../../../types';
import {
  getSubscriptionLatencyTest,
  preserveSubscriptionLatency,
} from '../subscriptionLatency';

function section(latency = 0): AnticheburNET.OutboundGroup {
  return {
    code: 'selector',
    sectionName: 'main',
    displayName: 'Main',
    withTagSelect: true,
    outbounds: [
      {
        code: 'node',
        displayName: 'Node',
        type: 'vless',
        selected: true,
        link: 'vless://same-server',
        latency,
      },
    ],
  };
}

describe('subscription latency', () => {
  it('keeps the last latency only for unchanged servers while the fresh test runs', () => {
    const before = section(42);
    const next = section();
    next.outbounds.push({
      ...next.outbounds[0],
      code: 'new-node',
      link: 'vless://new-server',
    });
    const merged = preserveSubscriptionLatency(next, before);
    expect(merged.outbounds.map((node) => node.latency)).toEqual([42, 0]);
    expect(next.outbounds[0].latency).toBe(0);
    expect(
      preserveSubscriptionLatency(section(21), before).outbounds[0].latency,
    ).toBe(21);
  });

  it('does not revive removed servers or transfer latency to a changed link with the same tag', () => {
    const next = section();
    next.outbounds[0].link = 'vless://changed-server';
    expect(
      preserveSubscriptionLatency(next, section(42)).outbounds[0].latency,
    ).toBe(0);
    next.outbounds = [];
    expect(preserveSubscriptionLatency(next, section(42)).outbounds).toEqual(
      [],
    );
  });

  it('preserves URLTest members and derives the group latency from its current selection', () => {
    const before = section();
    before.outbounds[0].urlTestInfo = {
      code: 'auto',
      displayName: 'Auto',
      selectedCode: 'member',
      outbounds: [{ ...before.outbounds[0], code: 'member', latency: 42 }],
    };
    const next = structuredClone(before);
    next.outbounds[0].urlTestInfo!.outbounds[0].latency = 0;
    const merged = preserveSubscriptionLatency(next, before);
    expect(merged.outbounds[0].urlTestInfo!.outbounds[0].latency).toBe(42);
    expect(merged.outbounds[0].latency).toBe(42);
    next.outbounds[0].urlTestInfo!.outbounds[0].link = 'vless://changed';
    expect(preserveSubscriptionLatency(next, before).outbounds[0].latency).toBe(
      0,
    );
  });

  it('uses the new node list and the same group, list and VPN probe targets as the latency button', () => {
    const next = section();
    expect(getSubscriptionLatencyTest(next)).toEqual({
      type: 'group',
      tag: 'selector',
    });
    next.latencyTestCodes = ['new-node', 'auto'];
    expect(getSubscriptionLatencyTest(next)).toEqual({
      type: 'proxy_list',
      tag: '["new-node","auto"]',
    });
    next.withTagSelect = false;
    next.latencyTestTimeout = '7000';
    expect(getSubscriptionLatencyTest(next)).toEqual({
      type: 'proxy',
      tag: 'node',
      timeout: '7000',
    });
    next.outbounds[0].runtimeAvailable = false;
    expect(getSubscriptionLatencyTest(next)).toBeNull();
  });
});
