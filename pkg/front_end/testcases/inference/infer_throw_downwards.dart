// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/*@testedFeatures=inference*/
library test;

T f<T>() => throw '';

var x = throw /*@typeArgs=Object*/ f();

void g() {
  var /*@type=Never*/ x = throw /*@typeArgs=Object*/ f();
}

main() {}
