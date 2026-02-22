import 'package:flutter/foundation.dart';

import 'ssh_service.dart';

class OnboardingService {
  final SSHService _ssh;

  OnboardingService(this._ssh);

  /// Check if RISE is already installed on the server
  Future<OnboardingCheckResult> checkExistingInstallation() async {
    final installed = await _ssh.checkRISEInstalled();

    if (!installed) {
      return OnboardingCheckResult(
        status: OnboardingStatus.notInstalled,
        message: 'RISE is not installed on this server',
      );
    }

    // Get version
    final version = await _ssh.getRISEVersion();

    return OnboardingCheckResult(
      status: OnboardingStatus.alreadyInstalled,
      message: 'RISE is already installed',
      version: version,
    );
  }

  /// Install RISE on a fresh server
  Future<OnboardingResult> installRISE({
    required String securityMode,
    required String publicKey,
  }) async {
    // Step 1: Download and run setup-env.sh
    debugPrint('Step 1: Running setup-env.sh...');
    var result = await _ssh.execute(
      'curl -fsSL https://raw.githubusercontent.com/RiseBare/RISE-Bare/main/scripts/setup-env.sh | sudo bash',
    );

    if (!result.success) {
      return OnboardingResult(
        success: false,
        error: 'Failed to run setup-env.sh: ${result.error}',
      );
    }

    // Step 2: Download all RISE scripts
    debugPrint('Step 2: Downloading RISE scripts...');
    final scripts = [
      'rise-firewall.sh',
      'rise-docker.sh',
      'rise-update.sh',
      'rise-onboard.sh',
      'rise-health.sh',
    ];

    for (final script in scripts) {
      final downloadResult = await _ssh.execute(
        'curl -fsSL https://raw.githubusercontent.com/RiseBare/RISE-Bare/main/scripts/$script -o /usr/local/bin/$script && chmod +x /usr/local/bin/$script',
      );

      if (!downloadResult.success) {
        return OnboardingResult(
          success: false,
          error: 'Failed to download $script: ${downloadResult.error}',
        );
      }
    }

    // Step 3: Run rise-onboard.sh to configure the server
    debugPrint('Step 3: Running rise-onboard.sh...');
    result = await _ssh.execute(
      '/usr/local/bin/rise-onboard.sh --security-mode $securityMode --add-key "$publicKey"',
    );

    if (!result.success) {
      return OnboardingResult(
        success: false,
        error: 'Failed to run rise-onboard.sh: ${result.error}',
      );
    }

    // Step 4: Verify installation
    final installed = await _ssh.checkRISEInstalled();
    if (!installed) {
      return OnboardingResult(
        success: false,
        error: 'Installation verification failed',
      );
    }

    return OnboardingResult(
      success: true,
      message: 'RISE installed successfully',
      version: await _ssh.getRISEVersion(),
    );
  }

  /// Add this device's SSH key to an existing RISE installation
  Future<OnboardingResult> addDeviceToExistingServer(String publicKey) async {
    final result = await _ssh.execute(
      '/usr/local/bin/rise-onboard.sh --add-key "$publicKey"',
    );

    if (!result.success) {
      return OnboardingResult(
        success: false,
        error: 'Failed to add SSH key: ${result.error}',
      );
    }

    return OnboardingResult(
      success: true,
      message: 'SSH key added successfully',
    );
  }

  /// Get server info from RISE installation
  Future<Map<String, dynamic>?> getServerInfo() async {
    final result = await _ssh.execute('/usr/local/bin/rise-health.sh --json 2>/dev/null');

    if (result.success) {
      return {
        'version': await _ssh.getRISEVersion(),
        'output': result.output,
      };
    }
    return null;
  }
}

enum OnboardingStatus {
  notInstalled,
  alreadyInstalled,
}

class OnboardingCheckResult {
  final OnboardingStatus status;
  final String message;
  final String? version;

  OnboardingCheckResult({
    required this.status,
    required this.message,
    this.version,
  });
}

class OnboardingResult {
  final bool success;
  final String? message;
  final String? error;
  final String? version;

  OnboardingResult({
    required this.success,
    this.message,
    this.error,
    this.version,
  });
}
