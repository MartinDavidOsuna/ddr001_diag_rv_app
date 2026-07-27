import 'package:ddr001diag/features/sync/sync_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('describe la confirmación remota cuando hay conexión real', () {
    expect(syncConnectionMessage(true), contains('Conectado a la API'));
    expect(syncConnectionMessage(true), isNot(contains('Simulación local')));
  });

  test('explica la persistencia local cuando no hay conexión', () {
    expect(syncConnectionMessage(false), contains('permanecen guardados'));
    expect(syncConnectionMessage(false), contains('recuperar la conexión'));
  });
}
