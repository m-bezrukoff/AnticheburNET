import { ValidationResult } from './types';
import { isValidPort, parseHostPort } from './hostPort';

function decodeBase64(value: string): string {
  return atob(value.replace(/-/g, '+').replace(/_/g, '/'));
}

export function validateShadowsocksUrl(url: string): ValidationResult {
  if (!url.startsWith('ss://')) {
    return {
      valid: false,
      message: _('Invalid Shadowsocks URL: must start with ss://'),
    };
  }

  try {
    if (!url || /\s/.test(url)) {
      return {
        valid: false,
        message: _('Invalid Shadowsocks URL: must not contain spaces'),
      };
    }

    const body = url.slice('ss://'.length).split(/[?#]/, 1)[0];
    const authority = body.includes('@') ? body : decodeBase64(body);
    const separator = authority.lastIndexOf('@');
    if (separator < 0) {
      return {
        valid: false,
        message: _('Invalid Shadowsocks URL: missing server address'),
      };
    }

    const userInfo = authority
      .slice(0, separator)
      .replace(/%([\da-f]{2})/gi, (_, byte: string) =>
        String.fromCharCode(Number.parseInt(byte, 16)),
      );
    if (!userInfo) {
      return {
        valid: false,
        message: _('Invalid Shadowsocks URL: missing credentials'),
      };
    }

    const credentials = userInfo.includes(':')
      ? userInfo
      : decodeBase64(userInfo);
    const colon = credentials.indexOf(':');
    if (colon <= 0 || colon === credentials.length - 1) {
      return {
        valid: false,
        message: _(
          'Invalid Shadowsocks URL: decoded credentials must contain method:password',
        ),
      };
    }

    const hostPort = authority.slice(separator + 1).replace(/\/$/, '');
    const parsedHostPort = parseHostPort(hostPort);
    if (!parsedHostPort) {
      return {
        valid: false,
        message: _('Invalid Shadowsocks URL: invalid server and port'),
      };
    }

    const { port } = parsedHostPort;
    if (!port) {
      return {
        valid: false,
        message: _('Invalid Shadowsocks URL: missing port'),
      };
    }

    if (!isValidPort(port)) {
      return {
        valid: false,
        message: _('Invalid port number. Must be between 1 and 65535'),
      };
    }
  } catch (_e) {
    return {
      valid: false,
      message: _('Invalid Shadowsocks URL: parsing failed'),
    };
  }

  return { valid: true, message: _('Valid') };
}
