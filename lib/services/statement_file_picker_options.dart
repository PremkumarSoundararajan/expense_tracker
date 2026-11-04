import 'package:file_picker/file_picker.dart';

import 'statement_file_picker_options_stub.dart'
    if (dart.library.js_interop) 'statement_file_picker_options_web.dart'
    as platform;

WebOptions statementFilePickerWebOptions() =>
    platform.statementFilePickerWebOptions();
