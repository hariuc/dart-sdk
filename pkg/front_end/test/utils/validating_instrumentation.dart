// Copyright (c) 2017, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert' show utf8;
import 'dart:io' show File;
import 'dart:typed_data' show Uint8List;

import 'package:_fe_analyzer_shared/src/messages/severity.dart' show Severity;
import 'package:_fe_analyzer_shared/src/scanner/io.dart' show readBytesFromFile;
import 'package:_fe_analyzer_shared/src/scanner/scanner.dart'
    show ScannerResult, Token, scan;
import 'package:_fe_analyzer_shared/src/scanner/token.dart' as analyzer
    show Token;
import 'package:front_end/src/base/compiler_context.dart' show CompilerContext;
import 'package:front_end/src/base/instrumentation.dart'
    show Instrumentation, InstrumentationValue;
import 'package:front_end/src/base/messages.dart'
    show noLength, templateUnspecified;

/// Implementation of [Instrumentation] which checks property/value pairs
/// against expectations encoded in source files using "/*@...*/" comments.
class ValidatingInstrumentation implements Instrumentation {
  static final RegExp _ESCAPE_SEQUENCE = new RegExp(r'\\(.)');

  /// Map from feature names to the property names they are short for.
  static const Map<String, List<String>> _FEATURES = const {
    'inference': const [
      'typeArg',
      'typeArgs',
      'promotedType',
      'type',
      'returnType',
      'target',
    ],
    'checks': const [
      'checkGetterReturn',
      'checkReturn',
      'genericContravariant',
    ],
  };

  final CompilerContext compilerContext;

  ValidatingInstrumentation(this.compilerContext);

  /// Map from file URI to the as-yet unsatisfied expectations from that file,
  /// organized by file offset.
  final _unsatisfiedExpectations = <Uri, Map<int, List<_Expectation>>>{};

  /// Information about "testedFeatures" annotations, organized by file URI and
  /// file offset.  The inner map is guaranteed to be in ascending order of
  /// file offset.
  final _testedFeaturesState = <Uri, Map<int, Set<String>>>{};

  /// Map from file URI to a sorted list of token offsets for that file.
  final _tokenOffsets = <Uri, List<int>>{};

  /// String descriptions of the expectation mismatches found so far.
  final _problems = <String>[];

  /// Fixes that would need to be performed on source files in order for all
  /// expectations to be met, organized by file URI.  The inner map is not
  /// guaranteed to be in ascending order of file offset.
  final _fixes = <Uri, List<_Fix>>{};

  /// Indicates whether any expectation mismatches were found.
  ///
  /// Should be called after [finish].
  bool get hasProblems => _problems.isNotEmpty;

  /// Gets a description of all expectation mismatches that were found, in a
  /// form suitable for printing to the console.
  ///
  /// Should be called after [finish].
  String get problemsAsString => _problems.join('\n');

  /// Checks whether the property/value pairs passed to [record] match the
  /// expectations loaded by [loadExpectations].
  void finish() {
    _unsatisfiedExpectations.forEach((uri, expectationsForUri) {
      expectationsForUri.forEach((offset, expectationsAtOffset) {
        for (_Expectation expectation in expectationsAtOffset) {
          _problem(
              uri,
              offset,
              'expected ${expectation.property}=${expectation.value}, '
              'got nothing',
              new _Fix(
                  expectation.commentOffset, expectation.commentLength, ''));
        }
      });
    });
  }

  /// Updates the source file at [uri] based on the actual property/value
  /// pairs that were observed.
  Future<Null> fixSource(Uri uri, bool offsetsCountCharacters) async {
    uri = Uri.base.resolveUri(uri);
    List<_Fix>? fixes = _fixes[uri];
    if (fixes == null) return;
    File file = new File.fromUri(uri);
    List<int> bytes = (await file.readAsBytes()).toList();
    int convertOffset(int offset) {
      if (offsetsCountCharacters) {
        return utf8.encode(utf8.decode(bytes).substring(0, offset)).length;
      } else {
        return offset;
      }
    }

    // Apply the fixes in reverse order so that offsets don't need to be
    // adjusted after each fix.
    fixes.sort((a, b) => a.offset.compareTo(b.offset));
    for (_Fix fix in fixes.reversed) {
      bytes.replaceRange(convertOffset(fix.offset),
          convertOffset(fix.offset + fix.length), utf8.encode(fix.replacement));
    }
    await file.writeAsBytes(bytes);
  }

  /// Loads expectations from the source file located at [uri].
  ///
  /// Should be called before [finish].
  Future<Null> loadExpectations(Uri uri) async {
    uri = Uri.base.resolveUri(uri);
    Uint8List bytes = await readBytesFromFile(uri);
    Map<int, List<_Expectation>> expectations =
        _unsatisfiedExpectations.putIfAbsent(uri, () => {});
    Map<int, Set<String>> testedFeaturesState =
        _testedFeaturesState.putIfAbsent(uri, () => {});
    List<int> tokenOffsets = _tokenOffsets.putIfAbsent(uri, () => []);
    ScannerResult result = scan(bytes, includeComments: true);
    for (Token token = result.tokens; !token.isEof; token = token.next!) {
      tokenOffsets.add(token.offset);
      for (analyzer.Token? commentToken = token.precedingComments;
          commentToken != null;
          commentToken = commentToken.next) {
        String lexeme = commentToken.lexeme;
        if (lexeme.startsWith('/*@') && lexeme.endsWith('*/')) {
          String expectation = lexeme.substring(3, lexeme.length - 2);
          int equals = expectation.indexOf('=');
          String property;
          String value;
          if (equals == -1) {
            property = expectation;
            value = '';
          } else {
            property = expectation.substring(0, equals);
            value = expectation
                .substring(equals + 1)
                .replaceAllMapped(_ESCAPE_SEQUENCE, (m) => m.group(1)!);
          }
          property = property.trim();
          value = value.trim();
          if (property == 'testedFeatures') {
            Set<String> state = new Set<String>();
            for (String feature in value.split(',')) {
              feature = feature.trim();
              // If an unrecognized feature name is found, it is assumed to be
              // just a property name.
              state.addAll(_FEATURES[feature] ?? [feature]);
            }
            testedFeaturesState[commentToken.offset] = state;
          } else {
            int offset = token.charOffset;
            List<_Expectation> expectationsAtOffset =
                expectations.putIfAbsent(offset, () => []);
            expectationsAtOffset.add(new _Expectation(
                property, value, commentToken.offset, commentToken.length));
          }
        }
      }
    }
  }

  @override
  void record(
      Uri uri, int offset, String property, InstrumentationValue value) {
    uri = Uri.base.resolveUri(uri);
    if (offset == -1) {
      throw _formatProblem(uri, 0, 'No offset for $property=$value', null);
    }
    Map<int, List<_Expectation>>? expectationsForUri =
        _unsatisfiedExpectations[uri];
    if (expectationsForUri == null) return;
    offset = _normalizeOffset(offset, _tokenOffsets[uri]!);
    List<_Expectation>? expectationsAtOffset = expectationsForUri[offset];
    if (expectationsAtOffset != null) {
      for (int i = 0; i < expectationsAtOffset.length; i++) {
        _Expectation expectation = expectationsAtOffset[i];
        if (expectation.property == property) {
          if (!value.matches(expectation.value)) {
            _problem(
                uri,
                offset,
                'expected $property=${expectation.value}, got '
                '$property=${value.toString()}',
                new _Fix(expectation.commentOffset, expectation.commentLength,
                    _makeExpectationComment(property, value)));
          }
          expectationsAtOffset.removeAt(i);
          return;
        }
      }
    }
    // Unexpected property/value pair.  See if we should report.
    if (_shouldCheck(property, uri, offset)) {
      _problem(
          uri,
          offset,
          'expected nothing, got $property=${value.toString()}',
          new _Fix(offset, 0, _makeExpectationComment(property, value)));
    }
  }

  String _escape(String s) {
    s = s.replaceAll(r'\', r'\\');
    if (s.endsWith('/')) {
      s = '$s ';
    }
    return s.replaceAll('/*', r'/\*').replaceAll('*/', r'*\/');
  }

  String _formatProblem(
      Uri uri, int offset, String desc, StackTrace? stackTrace) {
    return compilerContext
        .format(
            templateUnspecified
                .withArguments(
                    '$desc${stackTrace == null ? '' : '\n$stackTrace'}')
                .withLocation(uri, offset, noLength),
            Severity.internalProblem)
        .plain;
  }

  String _makeExpectationComment(String property, InstrumentationValue value) {
    return '/*@$property=${_escape(value.toString())}*/';
  }

  /// If [offset] is not one of the token offsets in [tokenOffsets], increase it
  /// until it is.
  ///
  /// Exception: if [offset] is past the last token offset in [tokenOffsets],
  /// leave it alone.
  int _normalizeOffset(int offset, List<int> tokenOffsets) {
    int i = -1;
    int j = tokenOffsets.length;
    // Invariant: (i == -1 || tokenOffsets[i] < offset) &&
    //     (j == tokenOffsets.length || offset <= tokenOffsets[j])
    while (j - i > 1) {
      int k = (i + j) ~/ 2;
      if (tokenOffsets[k] < offset) {
        i = k;
      } else {
        j = k;
      }
    }
    // Now i == j - 1
    if (j < tokenOffsets.length) {
      // tokenOffsets[j-1] < offset <= tokenOffsets[j]
      // Therefore the comment belongs with token j.
      return tokenOffsets[j];
    } else {
      // j-1 is the last token, and tokenOffsets[j-1] < offset.  Since there's
      // no later token, we can't normalize the offset.
      return offset;
    }
  }

  void _problem(Uri uri, int offset, String desc, _Fix fix) {
    _problems.add(_formatProblem(uri, offset, desc, null));
    _fixes.putIfAbsent(uri, () => []).add(fix);
  }

  /// ignore: unused_element
  void _problemWithStack(Uri uri, int offset, String desc, _Fix fix) {
    _problems.add(_formatProblem(uri, offset, desc, StackTrace.current));
    _fixes.putIfAbsent(uri, () => []).add(fix);
  }

  bool _shouldCheck(String property, Uri uri, int offset) {
    bool state = false;
    Map<int, Set<String>>? testedFeaturesStateForUri =
        _testedFeaturesState[uri];
    if (testedFeaturesStateForUri == null) return false;
    for (int i in testedFeaturesStateForUri.keys) {
      if (i > offset) break;
      Set<String> testedFeaturesStateAtOffset = testedFeaturesStateForUri[i]!;
      state = testedFeaturesStateAtOffset.contains(property);
    }
    return state;
  }
}

class _Expectation {
  final String property;
  final String value;
  final int commentOffset;
  final int commentLength;

  _Expectation(
      this.property, this.value, this.commentOffset, this.commentLength);
}

class _Fix {
  final int offset;
  final int length;
  final String replacement;

  _Fix(this.offset, this.length, this.replacement);
}
