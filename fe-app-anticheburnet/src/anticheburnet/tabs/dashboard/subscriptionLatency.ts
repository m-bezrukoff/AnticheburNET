import { AnticheburNET } from '../../types';

type LatencyMember = AnticheburNET.UrlTestMember;

function preserveMember<T extends LatencyMember>(next: T, previous?: T): T {
  // A reused tag may point to a changed server. Only keep values for the same link.
  if (
    next.latency ||
    !previous?.latency ||
    next.type !== previous.type ||
    !next.link ||
    next.link !== previous.link
  ) {
    return next;
  }

  return { ...next, latency: previous.latency };
}

export function preserveSubscriptionLatency(
  next: AnticheburNET.OutboundGroup,
  previous?: AnticheburNET.OutboundGroup,
): AnticheburNET.OutboundGroup {
  if (!previous) {
    return next;
  }

  return {
    ...next,
    outbounds: next.outbounds.map((outbound) => {
      if (outbound.runtimeAvailable === false) {
        return outbound;
      }
      const old = previous.outbounds.find(
        (item) => item.code === outbound.code,
      );
      const result = preserveMember(outbound, old);
      const preserved = {
        ...result,
        ...(outbound.urlTestInfo
          ? {
              urlTestInfo: {
                ...outbound.urlTestInfo,
                outbounds: outbound.urlTestInfo.outbounds.map((member) =>
                  preserveMember(
                    member,
                    old?.urlTestInfo?.outbounds.find(
                      (item) => item.code === member.code,
                    ),
                  ),
                ),
              },
            }
          : {}),
        ...(outbound.priorityInfo
          ? {
              priorityInfo: {
                ...outbound.priorityInfo,
                outbounds: outbound.priorityInfo.outbounds.map((member) =>
                  preserveMember(
                    member,
                    old?.priorityInfo?.outbounds.find(
                      (item) => item.code === member.code,
                    ),
                  ),
                ),
              },
            }
          : {}),
      };
      const group = preserved.urlTestInfo || preserved.priorityInfo;
      if (!preserved.latency && group?.selectedCode) {
        preserved.latency =
          group.outbounds.find((member) => member.code === group.selectedCode)
            ?.latency || 0;
      }
      return preserved;
    }),
  };
}

export function getSubscriptionLatencyTest(
  section: AnticheburNET.OutboundGroup,
) {
  if (
    !section.outbounds.some((outbound) => outbound.runtimeAvailable !== false)
  ) {
    return null;
  }

  if (section.withTagSelect) {
    return section.latencyTestCodes?.length
      ? {
          type: 'proxy_list' as const,
          tag: JSON.stringify(section.latencyTestCodes),
        }
      : {
          type: 'group' as const,
          tag: section.latencyTestCode || section.code,
        };
  }

  return {
    type: 'proxy' as const,
    tag: section.outbounds[0].code,
    timeout: section.latencyTestTimeout,
  };
}
