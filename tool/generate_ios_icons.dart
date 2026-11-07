import 'dart:io';
import 'dart:isolate';

/// Preserve the Xcode project because the pinned icon generator also rewrites
/// unrelated ASSETCATALOG settings. The existing AppIcon name stays in use.
Future<void> main() async {
  final project = File('ios/Runner.xcodeproj/project.pbxproj');
  final config = File('.dart_tool/package_config.json').absolute;
  final library = await Isolate.resolvePackageUri(
    Uri.parse('package:flutter_launcher_icons/main.dart'),
  );
  if (!await project.exists() || !await config.exists() || library == null) {
    stderr.writeln(
      'Run flutter pub get, then run this command from the project root.',
    );
    exitCode = 1;
    return;
  }
  final original = await project.readAsBytes();
  try {
    final result = await Process.run(Platform.resolvedExecutable, [
      '--disable-dart-dev',
      '--packages=${config.path}',
      File.fromUri(library.resolve('../bin/flutter_launcher_icons.dart')).path,
      '--file',
      'ios_launcher_icons.yaml',
    ]);
    stdout.write(result.stdout);
    stderr.write(result.stderr);
    exitCode = result.exitCode;
  } finally {
    await project.writeAsBytes(original, flush: true);
  }
}
