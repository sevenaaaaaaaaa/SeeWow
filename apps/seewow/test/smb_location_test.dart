import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/sources/native_bridge.dart';
import 'package:seewow/sources/smb_mounter.dart';

void main() {
  test('accepts host/share without a scheme', () {
    expect(
      SmbMounter.normalizeSmbLocation('192.168.1.10/媒体/电影'),
      'smb://192.168.1.10/媒体/电影',
    );
    final spec = SmbMounter.parseSmbLocation('192.168.1.10/媒体/电影');
    expect(spec.host, '192.168.1.10');
    expect(spec.share, '媒体');
    expect(spec.subpath, '电影');
  });

  test('normalizes backslash, trailing slash and full smb URLs', () {
    expect(
      SmbMounter.normalizeSmbLocation(r'\\192.168.1.10\media\'),
      'smb://192.168.1.10/media',
    );
    expect(
      SmbMounter.normalizeSmbLocation('smb://nas.local/Share/Sub/'),
      'smb://nas.local/Share/Sub',
    );
    expect(
      SmbMounter.normalizeSmbLocation('  //nas.local/Share  '),
      'smb://nas.local/Share',
    );
  });

  test('rejects credentials, query strings and missing share', () {
    expect(
      () => SmbMounter.normalizeSmbLocation('smb://user:pass@nas/Share'),
      throwsA(isA<NativeException>()),
    );
    expect(
      () => SmbMounter.normalizeSmbLocation('smb://nas/Share?x=1'),
      throwsA(isA<NativeException>()),
    );
    expect(
      () => SmbMounter.normalizeSmbLocation('smb://nas'),
      throwsA(isA<NativeException>()),
    );
    expect(
      () => SmbMounter.normalizeSmbLocation('   '),
      throwsA(isA<NativeException>()),
    );
  });
}
