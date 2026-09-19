import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';

/// Estrutura DATA_BLOB da API Win32 de criptografia.
final class _DataBlob extends Struct {
  @Uint32()
  external int cbData;
  external Pointer<Uint8> pbData;
}

typedef _CryptProtectNative = Int32 Function(
  Pointer<_DataBlob>,
  Pointer<Utf16>,
  Pointer<_DataBlob>,
  Pointer<Void>,
  Pointer<Void>,
  Uint32,
  Pointer<_DataBlob>,
);
typedef _CryptProtectDart = int Function(
  Pointer<_DataBlob>,
  Pointer<Utf16>,
  Pointer<_DataBlob>,
  Pointer<Void>,
  Pointer<Void>,
  int,
  Pointer<_DataBlob>,
);

/// Armazenamento local cifrado com a DPAPI do Windows.
///
/// POR QUE ISSO EXISTE:
/// A sessão contém o access token e o refresh token — o refresh vale 7 dias de
/// acesso à conta. Até a v1.0.0f eles eram gravados em texto puro em
/// `%APPDATA%\PapoCall\session.json`, onde qualquer processo rodando com o
/// usuário (inclusive infostealers comuns, que varrem exatamente esse tipo de
/// arquivo) conseguia lê-los e assumir a conta.
///
/// A DPAPI amarra a chave de criptografia à conta do Windows do usuário:
/// o arquivo copiado para outra máquina ou lido por outro usuário é inútil.
/// A entropia adicional específica do app impede que outro programa rodando
/// com o mesmo usuário decifre o arquivo apenas por chamar a DPAPI.
class SecureStorage {
  static const int _cryptprotectUiForbidden = 0x1;
  static final List<int> _entropy = utf8.encode('PapoCall/v1/session-entropy');

  static DynamicLibrary get _crypt32 => DynamicLibrary.open('crypt32.dll');
  static DynamicLibrary get _kernel32 => DynamicLibrary.open('kernel32.dll');

  static bool get isSupported => Platform.isWindows;

  static Pointer<_DataBlob> _allocBlob(Allocator alloc, List<int> bytes) {
    final blob = alloc<_DataBlob>();
    final buffer = alloc<Uint8>(bytes.length);
    buffer.asTypedList(bytes.length).setAll(0, bytes);
    blob.ref.cbData = bytes.length;
    blob.ref.pbData = buffer;
    return blob;
  }

  static Uint8List? _call(String fn, List<int> input) {
    final arena = Arena();
    try {
      final func = _crypt32.lookupFunction<_CryptProtectNative, _CryptProtectDart>(fn);
      final inBlob = _allocBlob(arena, input);
      final entropyBlob = _allocBlob(arena, _entropy);
      final outBlob = arena<_DataBlob>();

      final ok = func(
        inBlob,
        nullptr,
        entropyBlob,
        nullptr,
        nullptr,
        _cryptprotectUiForbidden,
        outBlob,
      );

      if (ok == 0) return null;

      final result = Uint8List.fromList(
        outBlob.ref.pbData.asTypedList(outBlob.ref.cbData),
      );

      // A DPAPI aloca o buffer de saída; liberar evita vazamento de memória.
      final localFree = _kernel32.lookupFunction<
          Pointer<Void> Function(Pointer<Void>),
          Pointer<Void> Function(Pointer<Void>)>('LocalFree');
      localFree(outBlob.ref.pbData.cast<Void>());

      return result;
    } catch (_) {
      return null;
    } finally {
      arena.releaseAll();
    }
  }

  /// Grava [content] cifrado no arquivo indicado.
  /// Retorna false se a criptografia não estiver disponível — nesse caso o
  /// chamador NÃO deve gravar em texto puro como alternativa.
  static Future<bool> writeEncrypted(File file, String content) async {
    if (!isSupported) return false;

    final encrypted = _call('CryptProtectData', utf8.encode(content));
    if (encrypted == null) return false;

    await file.writeAsBytes(encrypted, flush: true);
    return true;
  }

  /// Lê e decifra o arquivo. Retorna null se não existir, estiver corrompido,
  /// ou tiver sido cifrado por outro usuário do Windows.
  static Future<String?> readEncrypted(File file) async {
    if (!isSupported) return null;

    try {
      if (!await file.exists()) return null;
      final raw = await file.readAsBytes();
      if (raw.isEmpty) return null;

      final clear = _call('CryptUnprotectData', raw);
      if (clear == null) return null;

      return utf8.decode(clear);
    } catch (_) {
      return null;
    }
  }
}
