import 'package:flutter/material.dart';
import '../../core/cache/cache_manager.dart';

/// Initialization screen shown during first launch cache download
class InitializationScreen extends StatefulWidget {
  final Stream<CacheInitProgress> progressStream;
  final VoidCallback onComplete;
  final void Function(String error)? onError;

  const InitializationScreen({
    super.key,
    required this.progressStream,
    required this.onComplete,
    this.onError,
  });

  @override
  State<InitializationScreen> createState() => _InitializationScreenState();
}

class _InitializationScreenState extends State<InitializationScreen> {
  CacheInitProgress? _progress;
  String? _error;

  @override
  void initState() {
    super.initState();
    _listenToProgress();
  }

  void _listenToProgress() {
    widget.progressStream.listen(
      (progress) {
        if (mounted) {
          setState(() {
            _progress = progress;
            if (progress.error != null) {
              _error = progress.error;
            }
          });

          if (progress.isComplete) {
            widget.onComplete();
          }
        }
      },
      onError: (error) {
        if (mounted) {
          setState(() {
            _error = error.toString();
          });
          widget.onError?.call(error.toString());
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo placeholder
              Icon(
                Icons.security,
                size: 80,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 24),

              // Title
              Text(
                'RISE Bare',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),

              // Status text
              Text(
                _error != null
                    ? 'Error downloading files'
                    : _progress?.isComplete == true
                        ? 'Ready!'
                        : 'Initializing RISE...',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: _error != null
                          ? Theme.of(context).colorScheme.error
                          : null,
                    ),
              ),
              const SizedBox(height: 32),

              // Progress indicator
              if (_progress != null && _error == null) ...[
                // Current file
                Text(
                  _progress!.currentFile,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.secondary,
                      ),
                ),
                const SizedBox(height: 16),

                // Progress bar
                SizedBox(
                  width: 250,
                  child: LinearProgressIndicator(
                    value: _progress!.total > 0
                        ? _progress!.downloaded / _progress!.total
                        : null,
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 8),

                // Download count
                Text(
                  'Downloading (${_progress!.downloaded}/${_progress!.total})',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],

              // Error message
              if (_error != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _error = null;
                    });
                    _listenToProgress();
                  },
                  child: const Text('Retry'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
