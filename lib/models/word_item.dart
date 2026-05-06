class WordItem {
  final String word;
  final String image;
  final String audio;

  /// ID into Aya_Dataset words_id.json. When set, the classifier uses the
  /// per-word model trained for this specific word; null falls back to the
  /// generic pronunciation model.
  final int? datasetWordId;

  WordItem({
    required this.word,
    required this.image,
    required this.audio,
    this.datasetWordId,
  });
}
