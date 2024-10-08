// Copyright (c) 2018, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analysis_server/src/services/correction/fix.dart';
import 'package:analyzer_plugin/utilities/fixes/fixes.dart';
import 'package:linter/src/lint_names.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'fix_processor.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(RemoveEmptyElseBulkTest);
    defineReflectiveTests(RemoveEmptyElseTest);
  });
}

@reflectiveTest
class RemoveEmptyElseBulkTest extends BulkFixProcessorTest {
  @override
  String get lintCode => LintNames.avoid_empty_else;

  Future<void> test_singleFile() async {
    await resolveTestCode('''
void f(bool cond) {
  if (cond) {
    //
  }
  else ;
}

void f2(bool cond) {
  if (cond) {
    //
  } else ;
}
''');
    await assertHasFix('''
void f(bool cond) {
  if (cond) {
    //
  }
}

void f2(bool cond) {
  if (cond) {
    //
  }
}
''');
  }
}

@reflectiveTest
class RemoveEmptyElseTest extends FixProcessorLintTest {
  @override
  FixKind get kind => DartFixKind.REMOVE_EMPTY_ELSE;

  @override
  String get lintCode => LintNames.avoid_empty_else;

  Future<void> test_newLine() async {
    await resolveTestCode('''
void foo(bool cond) {
  if (cond) {
    //
  }
  else ;
}
''');
    await assertHasFix('''
void foo(bool cond) {
  if (cond) {
    //
  }
}
''');
  }

  Future<void> test_sameLine() async {
    await resolveTestCode('''
void foo(bool cond) {
  if (cond) {
    //
  } else ;
}
''');
    await assertHasFix('''
void foo(bool cond) {
  if (cond) {
    //
  }
}
''');
  }
}
