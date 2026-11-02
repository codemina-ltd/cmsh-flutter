import 'dart:async';

import 'package:cmsh_flutter/cmsh_flutter.dart';
import 'package:flutter/material.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Cmsh.init(
    // Create an app in the CMSH portal to get your key.
    sdkKey: const String.fromEnvironment('CMSH_SDK_KEY'),
    domains: const {'go.example.com'},
    debug: true,
  );
  runApp(const ExampleApp());
}

class ExampleApp extends StatefulWidget {
  const ExampleApp({super.key});

  @override
  State<ExampleApp> createState() => _ExampleAppState();
}

class _ExampleAppState extends State<ExampleApp> {
  StreamSubscription<CmshLink>? _subscription;
  CmshLink? _link;

  @override
  void initState() {
    super.initState();
    _subscription = Cmsh.onLink.listen((link) => setState(() => _link = link));
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final link = _link;
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('CMSH example')),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 12,
            children: [
              Text(
                link == null
                    ? 'Open a CMSH link to see it here.'
                    : 'Path: ${link.path}\n'
                          'Data: ${link.data}\n'
                          'Match: ${link.matchType?.value ?? 'none'}\n'
                          'Deferred: ${link.isDeferred}',
              ),
              FilledButton(
                onPressed: () => Cmsh.identify(
                  'user_123',
                  traits: {'name': 'Sara', 'email': 'sara@example.com'},
                ),
                child: const Text('Identify'),
              ),
              OutlinedButton(
                onPressed: () =>
                    Cmsh.track('purchase', properties: {'value': 25}),
                child: const Text('Track purchase'),
              ),
              TextButton(onPressed: Cmsh.reset, child: const Text('Sign out')),
            ],
          ),
        ),
      ),
    );
  }
}
