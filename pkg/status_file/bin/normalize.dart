// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:args/args.dart';
import 'package:status_file/canonical_status_file.dart';
import 'package:status_file/status_file.dart' as status_file;
import 'package:status_file/status_file_linter.dart';
import 'package:status_file/status_file_normalizer.dart';
import 'package:status_file/utils.dart';

ArgParser buildParser() {
  var parser = ArgParser();
  parser.addFlag("overwrite",
      abbr: 'w',
      negatable: false,
      defaultsTo: false,
      help: "Overwrite input files with formatted output.");
  parser.addFlag("delete-non-existing",
      abbr: 'd',
      negatable: true,
      defaultsTo: true,
      help: "Remove non-existing test entries.");
  parser.addFlag("help",
      abbr: "h",
      negatable: false,
      defaultsTo: false,
      help: "Show help and commands for this tool.");
  return parser;
}

void printHelp(ArgParser parser) {
  print("Usage: dart status_file/bin/normalize.dart <path>");
  print(parser.usage);
}

void main(List<String> arguments) {
  var parser = buildParser();
  var results = parser.parse(arguments);
  if (results["help"]) {
    printHelp(parser);
    return;
  }
  if (results.rest.isEmpty) {
    printHelp(parser);
    exit(1);
  }
  print("");
  bool overwrite = results["overwrite"];
  bool deleteNonExisting = results["delete-non-existing"];
  for (var path in results.rest) {
    if (FileSystemEntity.isFileSync(path)) {
      normalizeFile(path, overwrite, deleteNonExisting: deleteNonExisting);
    } else if (FileSystemEntity.isDirectorySync(path)) {
      Directory(path).listSync(recursive: true).forEach((entry) {
        if (!canLint(entry.path)) {
          return;
        }
        normalizeFile(entry.path, overwrite,
            deleteNonExisting: deleteNonExisting);
      });
    }
  }
}

bool normalizeFile(String path, bool writeFile,
    {required bool deleteNonExisting}) {
  try {
    var statusFile = StatusFile.read(path);
    var normalizedStatusFile =
        normalizeStatusFile(statusFile, deleteNonExisting: deleteNonExisting);
    if (writeFile) {
      File(path).writeAsStringSync(normalizedStatusFile.toString());
      print("Normalized $path");
    } else {
      print(normalizedStatusFile);
    }
    // Check if there are linting errors remaining, such as line comments,
    // that needs to be handled manually.
    var lintErrors =
        lint(normalizedStatusFile, checkForNonExisting: deleteNonExisting);
    if (lintErrors.isNotEmpty) {
      print("The normalizer could not remove all linting errors. The following "
          "has to be removed manually:");
      lintErrors.forEach(print);
    }
  } on status_file.SyntaxError catch (error) {
    stderr.writeln("Could not parse $path:\n$error");
  }
  return false;
}
