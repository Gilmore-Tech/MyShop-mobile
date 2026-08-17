import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';

void main() {
  group('fullName', () {
    test('accepts international letters, accents, and approved separators', () {
      for (final name in const [
        'Ɛsi Ɔfori',
        'Élodie',
        'E\u0301lodie',
        'O’Connor',
        "D'Arcy",
        'NʼDour',
        'Osei-Tutu',
        'Osei‐Tutu',
        'Osei‑Tutu',
        '李小龙',
        'Li',
        'Ama  Mensah',
        'Ama\u00a0\u00a0Mensah',
        '\u00a0Ama Mensah\u00a0',
      ]) {
        expect(Validators.fullName(name), isNull, reason: name);
      }
    });

    test('rejects digits, emoji, symbols, controls, and bad separators', () {
      for (final name in const [
        'Ama123',
        'Ama١',
        '123',
        'Ama😀',
        '😀',
        'Am\uFE0E',
        'Am\uFE0F',
        'Ama×',
        'Ama÷',
        'Ama_Mensah',
        'Ama@Mensah',
        'Ama.Mensah',
        "O''Connor",
        'NʼʼDour',
        'Osei--Tutu',
        "Ama-'Mensah",
        '-Ama Mensah',
        'Ama Mensah’',
        'Ama\tMensah',
        'Ama\nMensah',
        'Ama\n',
        '\nAma',
        '\u0301Ama',
      ]) {
        expect(
          Validators.fullName(name),
          Validators.invalidFullNameMessage,
          reason: name,
        );
      }
    });

    test('keeps required and Unicode grapheme length limits explicit', () {
      expect(Validators.fullName(''), 'Full name is required.');
      expect(Validators.fullName('   '), 'Full name is required.');
      expect(Validators.fullName('A'), 'Name must be at least 2 characters.');
      expect(
        Validators.fullName('E\u0301'),
        'Name must be at least 2 characters.',
      );
      expect(
        Validators.fullName(List.filled(61, 'E\u0301').join()),
        isNull,
      );
      expect(
        Validators.fullName('\u1100\u1161'),
        'Name must be at least 2 characters.',
      );
      expect(
        Validators.fullName(List.filled(61, '\u1100\u1161').join()),
        isNull,
      );
      expect(Validators.fullName(List.filled(120, 'A').join()), isNull);
      expect(
        Validators.fullName(List.filled(121, 'A').join()),
        'Name must be 120 characters or fewer.',
      );
      expect(
        Validators.fullName(List.filled(121, 'E\u0301').join()),
        'Name must be 120 characters or fewer.',
      );
    });
  });

  test('validates canonical Ghana E.164 phone numbers', () {
    expect(Validators.ghanaE164Phone('+233241234567'), isNull);
    expect(Validators.ghanaE164Phone('+233 30 123 4567'), isNull);
    expect(Validators.ghanaE164Phone('+447911123456'), isNotNull);
    expect(Validators.ghanaE164Phone('+23334123456'), isNotNull);
    expect(Validators.ghanaE164Phone('0241234567'), isNotNull);
  });
}
