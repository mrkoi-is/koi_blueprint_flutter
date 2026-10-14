final class TextAnalysis {
  const TextAnalysis(this.engine, this.unit, this.count);
  final String engine;
  final String unit;
  final int count;
}

abstract interface class TextAnalysisEngine {
  Future<TextAnalysis> analyze(String text);
}
