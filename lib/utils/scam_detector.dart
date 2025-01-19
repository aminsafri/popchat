// lib/utils/scam_detector.dart

import 'dart:convert';
import 'dart:math';
import 'package:flutter/services.dart';

class ScamDetector {
  late Map<String, int> vocabulary;
  late List<double> idfValues;
  late List<List<double>> denseLayerWeights;
  late List<double> denseLayerBiases;
  late List<List<double>> outputLayerWeights;
  late List<double> outputLayerBiases;

  ScamDetector();

  /// Load TF-IDF metadata + model weights from JSON.
  /// Ensure JSON uses floating-point (e.g. 0.0) for numeric entries to avoid issues.
  Future<void> loadModel() async {
    // 1) Load TF-IDF metadata
    final tfidfData = await rootBundle.loadString('assets/tfidf_metadata.json');
    final tfidf = jsonDecode(tfidfData);

    // vocabulary => Map<String,int>
    final rawVocab = tfidf['vocabulary'] as Map<String, dynamic>;
    vocabulary = rawVocab.map((key, val) => MapEntry(key, val as int));

    // idfValues => we cast to List<dynamic>, then convert to double
    final rawIdf = tfidf['idf_values'] as List<dynamic>;
    idfValues = rawIdf.map((e) => (e as num).toDouble()).toList();

    // 2) Load model weights
    final weightsData = await rootBundle.loadString('assets/model_weights.json');
    final weights = jsonDecode(weightsData) as List<dynamic>;
    // e.g. weights = [denseLayerW, denseLayerB, outputLayerW, outputLayerB]

    // [0] => denseLayerWeights => List<List<double>>
    final rawDenseWeights = weights[0] as List<dynamic>;
    denseLayerWeights = rawDenseWeights.map((row) {
      final rowList = row as List<dynamic>;
      return rowList.map((e) => (e as num).toDouble()).toList();
    }).toList();

    // [1] => denseLayerBiases => List<double>
    final rawDenseBiases = weights[1] as List<dynamic>;
    denseLayerBiases = rawDenseBiases.map((e) => (e as num).toDouble()).toList();

    // [2] => outputLayerWeights => List<List<double>>
    final rawOutputWeights = weights[2] as List<dynamic>;
    outputLayerWeights = rawOutputWeights.map((row) {
      final rowList = row as List<dynamic>;
      return rowList.map((e) => (e as num).toDouble()).toList();
    }).toList();

    // [3] => outputLayerBiases => List<double>
    final rawOutputBiases = weights[3] as List<dynamic>;
    outputLayerBiases = rawOutputBiases.map((e) => (e as num).toDouble()).toList();
  }

  double sigmoid(double x) => 1 / (1 + exp(-x));

  /// Convert text -> TF-IDF vector
  List<double> calculateTFIDF(String text) {
    final tokens = text.toLowerCase().split(RegExp(r'[\s,\.]+'));
    final termFreq = <int, double>{};

    // Count term frequencies
    for (final token in tokens) {
      if (vocabulary.containsKey(token)) {
        final idx = vocabulary[token]!;
        termFreq[idx] = (termFreq[idx] ?? 0) + 1.0;
      }
    }

    // Build TF-IDF vector
    final tfidf = List<double>.filled(vocabulary.length, 0.0);
    termFreq.forEach((idx, freq) {
      // Guard: idx should be within idfValues
      if (idx >= 0 && idx < idfValues.length) {
        tfidf[idx] = freq * idfValues[idx];
      }
    });
    return tfidf;
  }

  /// Return true if predicted "scam" probability > 0.8
  bool isScam(String text) {
    final tfidfVector = calculateTFIDF(text);

    // 1) Dense layer
    // We'll clamp iteration to avoid out-of-range
    final denseOutLen = min(denseLayerWeights.length, denseLayerBiases.length);
    final denseOutput = List<double>.filled(denseOutLen, 0.0);

    for (int i = 0; i < denseOutLen; i++) {
      // clamp j to min(denseLayerWeights[i].length, tfidfVector.length)
      final rowLen = min(denseLayerWeights[i].length, tfidfVector.length);
      for (int j = 0; j < rowLen; j++) {
        denseOutput[i] += tfidfVector[j] * denseLayerWeights[i][j];
      }
      denseOutput[i] += denseLayerBiases[i];
      // ReLU
      denseOutput[i] = max(0, denseOutput[i]);
    }

    // 2) Output layer
    // clamp i to min(denseOutput.length, outputLayerWeights.length)
    final outLen = min(denseOutput.length, outputLayerWeights.length);
    double output = 0.0;

    // If your final bias is also just 1 element (like outputLayerBiases[0]),
    // you can add that after the loop or inside.
    // We'll add it after to keep it consistent with original code:
    for (int i = 0; i < outLen; i++) {
      // Usually outputLayerWeights[i] might be length=1 if it's a single output
      if (outputLayerWeights[i].isNotEmpty) {
        output += denseOutput[i] * outputLayerWeights[i][0];
      }
    }

    // Add the first (or only) bias
    if (outputLayerBiases.isNotEmpty) {
      output += outputLayerBiases[0];
    }

    // or if your code used to do:
    //  double output = outputLayerBiases[0];
    //  for i in ...
    // => Up to you, just be consistent:
    final probability = sigmoid(output);
    return probability > 0.8;
  }
}
