import 'package:file_selector/file_selector.dart';

/// Native file and folder pickers, behind an interface for testability.
abstract interface class DirectoryPicker {
  Future<String?> pickDirectory({String? initialDirectory});
  Future<String?> pickExecutable({String? initialDirectory});
}

class NativeDirectoryPicker implements DirectoryPicker {
  const NativeDirectoryPicker();

  @override
  Future<String?> pickDirectory({String? initialDirectory}) => getDirectoryPath(
        initialDirectory: initialDirectory,
        confirmButtonText: 'Choose',
      );

  @override
  Future<String?> pickExecutable({String? initialDirectory}) async {
    final file = await openFile(
      initialDirectory: initialDirectory,
      confirmButtonText: 'Use this file',
    );
    return file?.path;
  }
}
