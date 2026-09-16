# Dependency provenance

## SQLCipher

The local CSQLite target vendors SQLCipher community **v4.19.0**, official commit `c4b275a47932888216bade83aff2bbc73df0ff85`, from https://github.com/sqlcipher/sqlcipher. `scripts/vendor-sqlcipher.py` reproduces the amalgamation and copies upstream license files. Builds do not fetch this dependency from the network.

`Sources/CSQLite/sqlcipher.inc` and `include/sqlite3.h` are generated upstream source. `CSQLite.c` wraps the amalgamation with the Apple platform header and a local suppression for upstream integer-narrowing warnings. Application source warnings remain enabled. Package.swift enables the CommonCrypto provider, codec initialization, in-memory temporary storage, FTS5 and thread safety. No system libsqlite3 is linked by this target.

The app bundles the upstream SQLCipher BSD-3-Clause and SQLite public-domain notices in Resources/Licenses. These notices are separate from the optional audio driver license.

## Optional virtual audio driver

The BlackHole-derived prototype, pinned source and license/build instructions are documented in [DriverPrototype/README.md](../DriverPrototype/README.md). It builds separately and is not installed or embedded in the app. Public display name: Chup! Mic. Device UID: `ChupMic2ch_UID`; driver bundle ID: `com.chup.mic.prototype`. Distribution licensing and installer/signing remain release work.

## Development tools

XcodeGen generates the checked-in Xcode project; XcodeBuildMCP 2.7.0 provides native build automation through its CLI. Node dependencies are pinned in backend/package-lock.json. Tool caches, request journals, credentials and build artifacts are ignored by Git.

## Offline dictation

The Xcode app links only WhisperKit from [Argmax OSS Swift](https://github.com/argmaxinc/argmax-oss-swift), pinned at `ea872ffd35705aa757f33033500b9b0d40bd38df` in project.yml. ArgmaxCore is its transitive target. SwiftPM resolution is checked in with the Xcode workspace; argument-parser is a resolved package but its CLI is not shipped. MIT and incorporated Apache notices are bundled under Resources/Licenses.

`App/Resources/LocalSpeechModel.json` pins the Core ML Turbo 626 MB variant and tokenizer to immutable upstream revisions with byte lengths and SHA-256 for all 19 files (629,711,418 bytes). The one-time download is separate from builds. Installed assets live in `~/Library/Application Support/Chup/Models/whisper-turbo-626mb-v1`. Inference does not download anything. A small app-owned tokenizer protocol adapter uses the SDK’s public tokenizer factory because its ready-made wrapper initializer is internal. Word-level timestamps are disabled.

## Local comparison lab

FluidAudio **v0.13.6**, revision `57551cd90e0bbec342766244358bcf08afb05290`, is linked as a separate local ASR runtime for the comparison lab. Its Apache-2.0 license and included fastcluster/VBx notices ship under Resources/Licenses. This uses the upstream FluidInference SDK directly; no Ghost Pepper source is copied.

`App/Resources/ParakeetModel.json` pins 21 Core ML/vocabulary files (483,103,089 bytes) from `FluidInference/parakeet-tdt-0.6b-v3-coreml`, revision `7dd20fe6b1797d35f5e3307e8b1732d9a178edfe`, with individual SHA-256 and byte lengths. These exact artifacts differ in size from generic estimates for the model family. Original NVIDIA weights and the conversion are attributed in `Parakeet-Attribution.txt`; the model card lists CC BY 4.0. Assets live in `~/Library/Application Support/Chup/Models/parakeet-v3-7dd20fe-v1` and have explicit download/repair/removal controls.

Inference constructs `AsrModels` from verified local `MLModel` files and the vocabulary. It does not call FluidAudio download/recovery helpers. The preprocessor uses CPU; the encoder/decoder/joint use CPU and Neural Engine. The model is a lab candidate, not a replacement for the default dictation model. First-use compilation can take substantially longer than a later run; no speed ranking is implied by the download size or vendor benchmarks.
