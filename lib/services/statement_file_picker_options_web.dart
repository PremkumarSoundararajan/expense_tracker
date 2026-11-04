import 'package:file_picker/file_picker.dart';
import 'package:file_picker_web/file_picker_web.dart' show FilePickerWebOptions;

WebOptions statementFilePickerWebOptions() =>
    const FilePickerWebOptions(cancelUploadOnWindowBlur: false);
