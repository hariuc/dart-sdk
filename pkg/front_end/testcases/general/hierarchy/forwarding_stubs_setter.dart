// Copyright (c) 2024, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

abstract class Super {
  void set extendedConcreteCovariantSetter(covariant int i) {}

  void set extendedAbstractCovariantSetter(covariant int i);

  void set extendedConcreteCovariantImplementedSetter(covariant int i) {}

  void set extendedAbstractCovariantImplementedSetter(covariant int i);

  void set extendedConcreteImplementedCovariantSetter(int i) {}

  void set extendedAbstractImplementedCovariantSetter(int i);
}

class Interface1 {
  void set extendedConcreteCovariantImplementedSetter(int i) {}

  void set extendedAbstractCovariantImplementedSetter(int i) {}

  void set extendedConcreteImplementedCovariantSetter(covariant int i) {}

  void set extendedAbstractImplementedCovariantSetter(covariant int i) {}

  void set implementsMultipleCovariantSetter1(covariant int i) {}

  void set implementsMultipleCovariantSetter2(int i) {}
}

class Interface2 {
  void set implementsMultipleCovariantSetter1(int i) {}

  void set implementsMultipleCovariantSetter2(covariant int i) {}
}

abstract class AbstractClass extends Super implements Interface1, Interface2 {}

class ConcreteSub extends AbstractClass {}

class ConcreteClass extends Super implements Interface1, Interface2 {}

main() {}
