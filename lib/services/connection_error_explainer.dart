import 'vpn_service.dart';

/// A short, human explanation of why a connection did not work and what the
/// user can do next.
class ConnectionInsight {
  final String title;
  final String hint;

  /// Whether trying other saved profiles is a sensible next step.
  final bool suggestOtherRoute;

  const ConnectionInsight({
    required this.title,
    required this.hint,
    this.suggestOtherRoute = true,
  });
}

/// Turns raw engine, socket and SSH errors into guidance a person can act on.
///
/// The raw text stays available in Connection Story; this is only the
/// first-line explanation shown on the home screen.
class ConnectionErrorExplainer {
  const ConnectionErrorExplainer._();

  static ConnectionInsight explain(String? raw) {
    final text = (raw ?? '').toLowerCase();

    if (raw == kTunnelNoInternetError || text.contains('no internet passed')) {
      return const ConnectionInsight(
        title: 'Connected, but the internet is not reachable',
        hint:
            'The tunnel started, yet no request passed through it. This route '
            'is probably blocked or overloaded right now.',
      );
    }
    if (raw == kEngineStartTimeoutError ||
        text.contains('did not start this profile')) {
      return const ConnectionInsight(
        title: 'This profile could not be started',
        hint:
            'The VPN engine rejected its settings. It may use a feature this '
            'app does not support yet. Another route will probably work.',
      );
    }
    if (text.contains('permission')) {
      return const ConnectionInsight(
        title: 'VPN permission is needed',
        hint:
            'Android did not allow the VPN request. Tap connect again and '
            'choose Allow when Android asks.',
        suggestOtherRoute: false,
      );
    }
    if (text.contains('failed to initialize') ||
        text.contains('not supported on web')) {
      return const ConnectionInsight(
        title: 'The VPN engine could not start',
        hint:
            'Close and reopen the app. If this keeps happening, install the '
            'latest release again.',
        suggestOtherRoute: false,
      );
    }
    if (text.contains('slowdns')) {
      return const ConnectionInsight(
        title: 'This SSH transport is not supported yet',
        hint:
            'SSH over SlowDNS profiles can be stored but not connected in this '
            'version. Choose another profile.',
      );
    }
    if (text.contains('auth') ||
        text.contains('password') ||
        text.contains('username')) {
      return const ConnectionInsight(
        title: 'The server rejected the sign-in',
        hint:
            'Check the username and password saved in this profile, or ask '
            'the profile provider for fresh credentials.',
      );
    }
    if (text.contains('host lookup') ||
        text.contains('no address associated') ||
        text.contains('nodename nor servname') ||
        text.contains('host is empty')) {
      return const ConnectionInsight(
        title: 'The server address could not be found',
        hint:
            'Your network could not resolve this server name. Check that you '
            'are online, or try another profile.',
      );
    }
    if (text.contains('timed out') ||
        text.contains('timeout') ||
        text.contains('refused') ||
        text.contains('unreachable') ||
        text.contains('reset by peer') ||
        text.contains('socketexception') ||
        text.contains('closed by the server')) {
      return const ConnectionInsight(
        title: 'The server did not answer',
        hint:
            'This route is unreachable from your network right now. Another '
            'saved profile may still work.',
      );
    }
    if (text.contains('url is invalid') ||
        text.contains('formatexception') ||
        text.contains('invalid')) {
      return const ConnectionInsight(
        title: 'This profile looks damaged',
        hint:
            'Some fields in the saved link could not be read. Import a fresh '
            'copy of the profile.',
      );
    }
    return const ConnectionInsight(
      title: 'The connection did not complete',
      hint: 'Try again, or let Smart Connect pick another saved route.',
    );
  }
}
