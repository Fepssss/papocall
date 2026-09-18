import 'dart:ffi';
import 'dart:io';
import 'dart:math';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

typedef _PlaySoundWNative = Int32 Function(Pointer<Utf16> pszSound, IntPtr hmod, Uint32 fdwSound);
typedef _PlaySoundWDart = int Function(Pointer<Utf16> pszSound, int hmod, int fdwSound);

enum SoundType {
  joinCall,
  leaveCall,
  screenShareStart,
  screenShareStop,
  screenWatchStart,
  screenWatchStop,
}

class SoundService {
  SoundService._();

  static DynamicLibrary? _winmm;
  static _PlaySoundWDart? _playSound;
  static final Map<SoundType, String> _soundFiles = {};
  static bool _initialized = false;
  static DateTime _lastPlayTime = DateTime.fromMillisecondsSinceEpoch(0);
  static SoundType? _lastSoundType;

  static void initialize() {
    if (_initialized) return;
    _initialized = true;

    if (!Platform.isWindows) return;

    try {
      _winmm = DynamicLibrary.open('winmm.dll');
      _playSound = _winmm!.lookupFunction<_PlaySoundWNative, _PlaySoundWDart>('PlaySoundW');

      final baseDir = Directory('${Directory.current.path}\\data\\sounds');
      if (!baseDir.existsSync()) {
        baseDir.createSync(recursive: true);
      }

      _prepareSound(baseDir, SoundType.joinCall, 'join_call.wav', () => _generateChord([523.25, 659.25], [90, 180]));
      _prepareSound(baseDir, SoundType.leaveCall, 'leave_call.wav', () => _generateChord([659.25, 440.0], [90, 190]));
      _prepareSound(baseDir, SoundType.screenShareStart, 'share_start.wav', () => _generateSweep(440.0, 880.0, 190));
      _prepareSound(baseDir, SoundType.screenShareStop, 'share_stop.wav', () => _generateSweep(880.0, 440.0, 190));
      _prepareSound(baseDir, SoundType.screenWatchStart, 'watch_start.wav', () => _generateChord([540.0, 800.0], [45, 80]));
      _prepareSound(baseDir, SoundType.screenWatchStop, 'watch_stop.wav', () => _generateChord([800.0, 540.0], [45, 80]));
    } catch (e) {
      debugPrint('Aviso ao inicializar SoundService: $e');
    }
  }

  static void _prepareSound(Directory dir, SoundType type, String fileName, Uint8List Function() generator) {
    try {
      final file = File('${dir.path}\\$fileName');
      if (!file.existsSync() || file.lengthSync() < 100) {
        file.writeAsBytesSync(generator());
      }
      _soundFiles[type] = file.path;
    } catch (e) {
      debugPrint('Erro ao preparar som $fileName: $e');
    }
  }

  static void play(SoundType type) {
    if (!Platform.isWindows) return;
    if (!_initialized) initialize();

    final now = DateTime.now();
    // Debounce mesmo som se disparado a menos de 250ms
    if (_lastSoundType == type && now.difference(_lastPlayTime).inMilliseconds < 250) {
      return;
    }
    _lastSoundType = type;
    _lastPlayTime = now;

    final filePath = _soundFiles[type];
    if (filePath == null || _playSound == null) return;

    try {
      final pPath = filePath.toNativeUtf16();
      // SND_FILENAME (0x00020000) | SND_ASYNC (0x00000001) | SND_NODEFAULT (0x00000002)
      _playSound!(pPath, 0, 0x00020003);
      calloc.free(pPath);
    } catch (e) {
      debugPrint('Erro ao reproduzir som $type: $e');
    }
  }

  static void playJoinCall() => play(SoundType.joinCall);
  static void playLeaveCall() => play(SoundType.leaveCall);
  static void playScreenShareStart() => play(SoundType.screenShareStart);
  static void playScreenShareStop() => play(SoundType.screenShareStop);
  static void playScreenWatchStart() => play(SoundType.screenWatchStart);
  static void playScreenWatchStop() => play(SoundType.screenWatchStop);

  static Uint8List _generateChord(List<double> freqs, List<int> durationsMs) {
    const sampleRate = 44100;
    int totalSamples = 0;
    for (final d in durationsMs) {
      totalSamples += (sampleRate * d / 1000).round();
    }

    final byteData = ByteData(44 + totalSamples * 2);
    _writeWavHeader(byteData, sampleRate, totalSamples);

    int offset = 44;
    for (int s = 0; s < freqs.length; s++) {
      final freq = freqs[s];
      final dur = durationsMs[s];
      final segSamples = (sampleRate * dur / 1000).round();
      for (int i = 0; i < segSamples; i++) {
        final t = i / sampleRate;
        final progress = i / segSamples;
        double env = 1.0;
        if (progress < 0.08) {
          env = progress / 0.08;
        } else {
          env = exp(-4.2 * (progress - 0.08));
        }
        // Suave harmônico
        final raw = sin(2 * pi * freq * t) + 0.25 * sin(4 * pi * freq * t);
        final sample = (raw * env * 18000).round().clamp(-32768, 32767);
        byteData.setInt16(offset, sample, Endian.little);
        offset += 2;
      }
    }
    return byteData.buffer.asUint8List();
  }

  static Uint8List _generateSweep(double startFreq, double endFreq, int durationMs) {
    const sampleRate = 44100;
    final totalSamples = (sampleRate * durationMs / 1000).round();
    final byteData = ByteData(44 + totalSamples * 2);
    _writeWavHeader(byteData, sampleRate, totalSamples);

    int offset = 44;
    double phase = 0.0;
    for (int i = 0; i < totalSamples; i++) {
      final progress = i / totalSamples;
      final currentFreq = startFreq + (endFreq - startFreq) * progress;
      phase += 2 * pi * currentFreq / sampleRate;

      double env = 1.0;
      if (progress < 0.1) {
        env = progress / 0.1;
      } else if (progress > 0.8) {
        env = (1.0 - progress) / 0.2;
      }
      final sample = (sin(phase) * env * 19000).round().clamp(-32768, 32767);
      byteData.setInt16(offset, sample, Endian.little);
      offset += 2;
    }
    return byteData.buffer.asUint8List();
  }

  static void _writeWavHeader(ByteData byteData, int sampleRate, int totalSamples) {
    // RIFF
    byteData.setUint8(0, 0x52); byteData.setUint8(1, 0x49); byteData.setUint8(2, 0x46); byteData.setUint8(3, 0x46);
    byteData.setUint32(4, 36 + totalSamples * 2, Endian.little);
    // WAVE
    byteData.setUint8(8, 0x57); byteData.setUint8(9, 0x41); byteData.setUint8(10, 0x56); byteData.setUint8(11, 0x45);
    // fmt 
    byteData.setUint8(12, 0x66); byteData.setUint8(13, 0x6D); byteData.setUint8(14, 0x74); byteData.setUint8(15, 0x20);
    byteData.setUint32(16, 16, Endian.little);
    byteData.setUint16(20, 1, Endian.little); // PCM
    byteData.setUint16(22, 1, Endian.little); // Mono
    byteData.setUint32(24, sampleRate, Endian.little);
    byteData.setUint32(28, sampleRate * 2, Endian.little);
    byteData.setUint16(32, 2, Endian.little); // Block align
    byteData.setUint16(34, 16, Endian.little); // 16 bits
    // data
    byteData.setUint8(36, 0x64); byteData.setUint8(37, 0x61); byteData.setUint8(38, 0x74); byteData.setUint8(39, 0x61);
    byteData.setUint32(40, totalSamples * 2, Endian.little);
  }
}
