class PreparedStatement {
  const PreparedStatement({
    required this.name,
    required this.csv,
    this.worksheetNote,
  });
  final String name;
  final String csv;
  final String? worksheetNote;
}
