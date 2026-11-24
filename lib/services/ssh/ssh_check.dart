import 'dart:async';
import 'dart:io';

import '../../models/ssh_config.dart';
import 'ssh_session.dart';
import 'udpgw.dart';

enum SshCheckOutcome { passed, warning, failed, skipped }

class SshCheckResult {
  final SshCheckStep step;
  final SshCheckOutcome outcome;
  final String detail;
  final int? milliseconds;

  const SshCheckResult(
    this.step,
    this.outcome, {
    this.detail = '',
    this.milliseconds,
  });
}

class SshCheckReport {
  final List<SshCheckResult> results;
  final String? banner;

  const SshCheckReport(this.results, {this.banner});

  /// Connecting will work (warnings allowed).
  bool get canConnect =>
      results.every((r) => r.outcome != SshCheckOutcome.failed) &&
      results.any((r) => r.step == SshCheckStep.signIn);

  bool get hasWarnings =>
      results.any((r) => r.outcome == SshCheckOutcome.warning);
}

/// Tries each step a connection will use and reports them one by one.
class SshCheck {
  const SshCheck._();

  /// The steps that apply to [config], in order.
  static List<SshCheckStep> stepsFor(SshConfig config) => [
    SshCheckStep.reach,
    if (config.usesTls) SshCheckStep.tls,
    if (config.configType == SshConfigType.websocket ||
        (config.payload ?? '').trim().isNotEmpty ||
        (config.httpProxy ?? '').trim().isNotEmpty)
      SshCheckStep.upgrade,
    SshCheckStep.signIn,
    if (config.udpEnabled) SshCheckStep.udpgw,
    SshCheckStep.dns,
  ];

  static Future<SshCheckReport> run(
    SshConfig config, {
    void Function(SshCheckResult result)? onResult,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final results = <SshCheckResult>[];
    void report(SshCheckResult result) {
      results.add(result);
      onResult?.call(result);
    }

    final steps = stepsFor(config);
    final stopwatch = Stopwatch()..start();
    SshSession session;
    try {
      session = await SshSession.connect(
        config,
        timeout: timeout,
        onStep: (step) {
          switch (step) {
            case SshCheckStep.reach:
              report(
                SshCheckResult(
                  step,
                  SshCheckOutcome.passed,
                  milliseconds: stopwatch.elapsedMilliseconds,
                ),
              );
            case SshCheckStep.tls:
              report(
                SshCheckResult(
                  step,
                  SshCheckOutcome.passed,
                  detail: 'SNI ${config.tlsServerName}',
                ),
              );
            case SshCheckStep.upgrade:
              report(
                const SshCheckResult(
                  SshCheckStep.upgrade,
                  SshCheckOutcome.passed,
                ),
              );
            case SshCheckStep.signIn:
              report(
                SshCheckResult(
                  step,
                  SshCheckOutcome.passed,
                  detail: 'as ${config.sshUsername}',
                ),
              );
            case SshCheckStep.udpgw:
            case SshCheckStep.dns:
              break;
          }
        },
      );
    } on SshSessionException catch (error) {
      report(
        SshCheckResult(
          error.step,
          SshCheckOutcome.failed,
          detail: error.message,
        ),
      );
      for (final step in steps.skipWhile((s) => s != error.step).skip(1)) {
        report(SshCheckResult(step, SshCheckOutcome.skipped));
      }
      return SshCheckReport(results);
    }

    var dnsDone = false;
    try {
      if (config.udpEnabled) {
        final ok = await _udpgwWorks(session, config);
        report(
          ok
              ? SshCheckResult(
                  SshCheckStep.udpgw,
                  SshCheckOutcome.passed,
                  detail: 'Port ${config.udpgwPort}',
                )
              : SshCheckResult(
                  SshCheckStep.udpgw,
                  SshCheckOutcome.warning,
                  detail:
                      'Port ${config.udpgwPort} did not answer · web still works',
                ),
        );
        if (ok && config.udpgwTransparentDNS) {
          report(
            const SshCheckResult(
              SshCheckStep.dns,
              SshCheckOutcome.passed,
              detail: 'Answered by the server',
            ),
          );
          dnsDone = true;
        }
      }
      if (!dnsDone) {
        final server =
            InternetAddress.tryParse(config.dnsServer ?? '') ??
            InternetAddress('1.1.1.1');
        final (id, query) = DnsMessage.query('www.google.com');
        final answer = await DnsOverTcp.ask(session.openTcp, server, query);
        report(
          answer != null && DnsMessage.isAnswer(answer, id)
              ? SshCheckResult(
                  SshCheckStep.dns,
                  SshCheckOutcome.passed,
                  detail: server.address,
                )
              : SshCheckResult(
                  SshCheckStep.dns,
                  SshCheckOutcome.failed,
                  detail: 'No DNS answer through the tunnel',
                ),
        );
      }
    } finally {
      session.close();
    }
    return SshCheckReport(results, banner: session.banner);
  }

  static Future<bool> _udpgwWorks(SshSession session, SshConfig config) async {
    UdpgwSession? gateway;
    try {
      final stream = await session
          .openTcp('127.0.0.1', config.udpgwPort)
          .timeout(const Duration(seconds: 6));
      gateway = UdpgwSession(stream.stream, stream.sink);
      final (id, query) = DnsMessage.query('www.google.com');
      final completer = Completer<bool>();
      gateway.send(
        key: 'check',
        address: InternetAddress('8.8.8.8'),
        port: 53,
        data: query,
        dns: config.udpgwTransparentDNS,
        onReply: (packet) {
          if (!completer.isCompleted) {
            completer.complete(DnsMessage.isAnswer(packet.data, id));
          }
        },
      );
      return await completer.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () => false,
      );
    } catch (_) {
      return false;
    } finally {
      await gateway?.close();
    }
  }
}
