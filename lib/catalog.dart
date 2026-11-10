/// The decision models Athena can download, pinned to one Hugging Face revision each, and which
/// one a phone gets: the biggest that leaves the phone room to breathe.
library;

const _gib = 1024 * 1024 * 1024;

class ModelInfo {
  const ModelInfo({
    required this.id,
    required this.name,
    required this.repo,
    required this.revision,
    required this.file,
    required this.bytes,
    required this.sha256,
    required this.minRamGiB,
    required this.contextTokens,
    required this.license,
    required this.licenseUrl,
    required this.blurb,
  });

  final String id;
  final String name;
  final String repo;
  final String revision; // a commit, so a re-uploaded file cannot change under us
  final String file;
  final int bytes;
  final String sha256;

  /// The least RAM the phone reports for this model to be offered. Phones report a little under
  /// the size on the box (Android keeps some for itself), so the thresholds sit below it.
  final double minRamGiB;

  /// The longest request in tokens. kneejerk sizes its batch, and on iPhone the GPU buffers, to it.
  final int contextTokens;
  final String license;
  final String licenseUrl;
  final String blurb;

  String get url => 'https://huggingface.co/$repo/resolve/$revision/$file';
  String get size => formatBytes(bytes);

  /// How much pasted text fits: the context less the question and template, at a cautious
  /// 3.5 characters a token.
  int get maxTextChars => ((contextTokens - 150) * 3.5).floor();
}

/// Best first. A phone gets the first model whose minRamGiB it meets.
const catalog = <ModelInfo>[
  ModelInfo(
    id: 'h2o-lightning-4b',
    name: 'H2O Lightning 4B',
    repo: 'h2oai/h2o-lightning-4b-gguf',
    revision: '61f8d8b7a8c2d84426d0d143ca187f65d235934b',
    file: 'h2o-lightning-4b-IQ3_XXS.gguf',
    bytes: 1904497696,
    sha256: '666cede4296c13a23baa5165188e3113614f0609acedc7bd97afc938c54e2753',
    minRamGiB: 7.0,
    contextTokens: 1024,
    license: 'Apache 2.0',
    licenseUrl: 'https://huggingface.co/h2oai/h2o-lightning-4b-gguf/blob/main/LICENSE',
    blurb: 'The most careful answers. For phones with 8 GB of memory or more.',
  ),
  ModelInfo(
    id: 'd1-2b',
    name: 'Liquid d1 2B',
    repo: 'LiquidAI/d1-2B-GGUF',
    revision: '4a181094d1b6addfaa3a0956f78e7ab2aa406a0c',
    file: 'd1-2B-Q4_K_M.gguf',
    bytes: 1099629888,
    sha256: 'adca5789ad30ae6027e8e936749bb9f19673097492ab26fa1c5b69643ca50b4b',
    minRamGiB: 5.0,
    contextTokens: 1024,
    license: 'LFM Open License v1.0',
    licenseUrl: 'https://huggingface.co/LiquidAI/d1-2B-GGUF/blob/main/LICENSE',
    blurb: 'Fast and sharp. For phones with 6 GB of memory or more.',
  ),
  ModelInfo(
    id: 'kev-0.8b',
    name: 'Kev 0.8B',
    repo: 'ggml-org/Kev-0.8B-GGUF',
    revision: '9231cb757e3320120077e42e52371971968f008d',
    file: 'Kev-0.8B-Q8_0.gguf',
    bytes: 812406304,
    sha256: '27278f34eb3273bceea4c053dc50dd61a5161da21a718c4aacdf8fd5830771d0',
    minRamGiB: 3.3,
    contextTokens: 512,
    license: 'Apache 2.0',
    licenseUrl: 'https://huggingface.co/ggml-org/Kev-0.8B-GGUF',
    blurb: 'Small and quick. For phones with 4 GB of memory.',
  ),
  ModelInfo(
    id: 'vllm-d3-edge',
    name: 'vLLM d3 Edge',
    repo: 'ggml-org/vllm-d3-edge-GGUF',
    revision: 'e59a4bd76e00c243e08f01182f55fd1893142d95',
    file: 'vllm-d3-edge-Q8_0.gguf',
    bytes: 806232480,
    sha256: 'bdffd3a44a2535d8672d3ca7cf110c61bf1fe95788a3d249f18b3310cc0f85cd',
    minRamGiB: 3.3,
    contextTokens: 512,
    license: 'Apache 2.0',
    licenseUrl: 'https://huggingface.co/ggml-org/vllm-d3-edge-GGUF',
    blurb: 'Another small one, the same size as Kev. For phones with 4 GB of memory.',
  ),
  ModelInfo(
    id: 'laya',
    name: 'Laya',
    repo: 'ggml-org/Laya-GGUF',
    revision: '845f314dd047fc2444a5289a4d50c1e1d59e27e1',
    file: 'Laya-Q8_0.gguf',
    bytes: 449397600,
    sha256: 'c06528c5746d3bb8baa72a27938be95abbfd0b226f8471e8a9e365ed0bb066d2',
    minRamGiB: 2.5,
    contextTokens: 512,
    license: 'Apache 2.0',
    licenseUrl: 'https://huggingface.co/ggml-org/Laya-GGUF',
    blurb: 'The smallest. For phones with 3 GB of memory.',
  ),
];

double ramGiB(int bytes) => bytes / _gib;

/// The model a phone with this much RAM gets, or null if it has too little for any.
ModelInfo? recommendedModel(int ramBytes) {
  for (final m in catalog) {
    if (ramGiB(ramBytes) >= m.minRamGiB) return m;
  }
  return null;
}

/// Every model this phone can run, best first.
List<ModelInfo> modelsThatFit(int ramBytes) => [
      for (final m in catalog)
        if (ramGiB(ramBytes) >= m.minRamGiB) m,
    ];

ModelInfo? modelById(String? id) {
  for (final m in catalog) {
    if (m.id == id) return m;
  }
  return null;
}

/// Phones report less than the box says; this is the number on the box: 3.7 GiB → "4 GB".
String marketingRam(int bytes) {
  const sizes = [1, 2, 3, 4, 6, 8, 12, 16, 24, 32];
  final gib = ramGiB(bytes);
  for (final s in sizes) {
    if (gib <= s * 1.0) return '$s GB';
  }
  return '${gib.round()} GB';
}

String formatBytes(int bytes) {
  if (bytes >= 1000 * 1000 * 1000) return '${(bytes / 1e9).toStringAsFixed(1)} GB';
  return '${(bytes / 1e6).round()} MB';
}
