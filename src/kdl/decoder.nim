## ## Decoder
## This module implements a deserializer for KDL documents, nodes and values into different types and objects:
## - `char`
## - `bool`
## - `Option[T]`
## - `SomeNumber`
## - `StringTableRef`
## - `enum` and `HoleyEnum`
## - `string` and `cstring`
## - `KdlVal` (object variant)
## - `seq[T]` and `array[I, T]`
## - `HashSet[A]` and `OrderedSet[A]`
## - `Table[string, T]` and `OrderedTable[string, T]`
## - `object`, `ref` and `tuple` (including object variants)
## - Plus any type you implement.
runnableExamples:
  import kdl

  type
    Package = object
      name*, version*: string
      authors*: Option[seq[string]]
      description*, licenseFile*, edition*: Option[string]

    Deps = Table[string, string]

  const doc = parseKdl("""
package {
  name "kdl"
  version "0.0.0"
  description "kat's document language"
  authors "Kat Marchán <kzm@zkat.tech>"
  license-file "LICENSE.md"
  edition "2018"
}
dependencies {
  nom "6.0.1"
  thiserror "1.0.22"
}""")

  const package = doc.decode(Package, "package")
  const dependencies = doc.decode(Deps, "dependencies")

  assert package == Package(
    name: "kdl", 
    version: "0.0.0", 
    authors: @["Kat Marchán <kzm@zkat.tech>"].some, 
    description: "kat's document language".some, 
    licenseFile: "LICENSE.md".some, 
    edition: "2018".some
  )
  assert dependencies == {"nom": "6.0.1", "thiserror": "1.0.22"}.toTable

## ### Custom Hooks
## #### Decode hook
## Use custom decode hooks to decode your types, your way.
## 
## To do it you have to overload the `decodeHook` procedure with the following signature:
## ```nim
## proc decodeHook*(a: KdlSome, v: var MyType)
## ```
## Where `KdlSome` is one of `KdlDoc`, `KdlNode` or `KdlVal`:
## - `KdlDoc` is called when `doc.decode()`.
## - `KdlNode` is called when `doc.decode("node-name")`, or when parsing a field like `MyObj(a: MyType)` in `myobj-node {a "some representation of MyType"}`.
## - `KdlVal` is called when decoding arguments (`seq[MyType]`) or properties like `MyObj(a: MyType)` in `myobj-node a="another representation of MyType"`.
runnableExamples:
  import std/times
  import kdl
  import kdl/utils # kdl/utils define some useful internal procedures such as `eqIdent`, which checks the equality of two strings ignore case, underscores and dashes in an efficient way.

  proc decodeHook*(a: KdlVal, v: var DateTime) = 
    assert a.isString
    v = a.getString.parse("yyyy-MM-dd")

  proc decodeHook*(a: KdlNode, v: var DateTime) = 
    case a.args.len
    of 6: # year month day hour minute second
      v = dateTime(
        a.args[0].decode(int), 
        a.args[1].decode(Month), 
        a.args[2].decode(MonthdayRange), 
        a.args[3].decode(HourRange), 
        a.args[4].decode(MinuteRange), 
        a.args[5].decode(SecondRange)
      )
    of 3: # year month day
      v = dateTime(
        a.args[0].decode(int), 
        a.args[1].decode(Month), 
        a.args[2].decode(MonthdayRange), 
      )
    of 1: # yyyy-MM-dd 
      a.args[0].decode(v)
    else:
      doAssert a.args.len in {1, 3, 6}

    if "hour" in a.props:
      v.hour = a.props["hour"].getInt
    if "minute" in a.props:
      v.minute = a.props["minute"].getInt
    if "second" in a.props:
      v.second = a.props["second"].getInt
    if "nanosecond" in a.props:
      v.nanosecond = a.props["nanosecond"].getInt
    if "offset" in a.props:
      v.utcOffset = a.props["offset"].get(int)

  proc decodeHook*(a: KdlDoc, v: var DateTime) = 
    if a.len == 0: return

    var
      year: int
      month: Month
      day: MonthdayRange = 1
      hour: HourRange
      minute: MinuteRange
      second: SecondRange
      nanosecond: NanosecondRange

    for node in a:
      if node.name.eqIdent "year":
        node.decode(year)
      elif node.name.eqIdent "month":
        node.decode(month)
      elif node.name.eqIdent "day":
        node.decode(day)
      elif node.name.eqIdent "hour":
        node.decode(hour)
      elif node.name.eqIdent "minute":
        node.decode(minute)
      elif node.name.eqIdent "second":
        node.decode(second)
      elif node.name.eqIdent "nanosecond":
        node.decode(nanosecond)

    v = dateTime(year, month, day, hour, minute, second, nanosecond)

  assert parseKdl("""
  year 2022
  month 10 // or "October"
  day 15
  hour 12
  minute 10
  """).decode(DateTime) == dateTime(2022, mOct, 15, 12, 10)

  assert parseKdl("date 2022 \"October\" 15 12 04 00").decode(DateTime, "date") == dateTime(2022, mOct, 15, 12, 04)

  assert parseKdl("author birthday=\"2000-10-15\" name=\"Nobody\"")[0]["birthday"].decode(DateTime) == dateTime(2000, mOct, 15)

## #### New hook
## With new hooks you can initialize types with default values before decoding.
## Use the following signature when overloading `newHook`:
## ```nim
## proc newHook*(v: var MyType)
## ```
## *Note: by default for object variants modifying a discriminator field will end in a compilation error, if you are sure about it, disable this behavior by compiling with the following flag -d:kdlDecoderNoCaseTransitionError.*
runnableExamples:
  import kdl

  type Foo = object
    x*: int

  proc newHook*(v: var Foo) = 
    v.x = 5 # You may also do `v = Foo(x: 5)`

  assert parseKdl("").decode(Foo) == Foo(x: 5)

## #### Post hook
## Post hooks are called after decoding any (default, for custom decode hooks you have to call `postHookable(v)` explicitly) type.
## 
## Overloads of `postHook` must use the following signature:
## ```nim
## proc postHook*(v: var MyType)
## ```
runnableExamples:
  import kdl

  type Foo = object
    x*: int

  proc postHook*(v: var Foo) = 
    inc v.x

  assert parseKdl("x 1").decode(Foo) == Foo(x: 2) # 2 because x after postHook got incremented by one

## #### Enum hook
## Enum hooks are useful for parsing enums in a custom manner.
## 
## You can overload `enumHook` with two different signatures:
## ```nim
## proc enumHook*(a: string, v: var MyEnum)
## ```
## ```nim
## proc enumHook*(a: int, v: var MyEnum)
## ```
## *Note: by default decoding an integer into a holey enum raises an error, to override this behaviour compile with -d:kdlDecoderAllowHoleyEnums.*
runnableExamples:
  import std/[strformat, strutils]
  import kdl

  type MyEnum = enum
    meNorth, meSouth, meWest, meEast

  proc enumHook*(a: string, v: var MyEnum) = 
    case a.toLowerAscii
    of "north":
      v = meNorth
    of "south":
      v = meSouth
    of "west":
      v = meWest
    of "east":
      v = meEast
    else:
      raise newException(ValueError, &"invalid enum value {a} for {$typeof(v)}")

  proc enumHook*(a: int, v: var MyEnum) = 
    case a
    of 0xbeef:
      v = meNorth
    of 0xcafe:
      v = meSouth
    of 0xface:
      v = meWest
    of 0xdead:
      v = meEast
    else:
      raise newException(ValueError, &"invalid enum value {a} for {$typeof(v)}")

  assert parseKdl("""
  node "north" "south" "west" "east"
  """).decode(seq[MyEnum], "node") == @[meNorth, meSouth, meWest, meEast]

  assert parseKdl("""
  node 0xbeef 0xcafe 0xface 0xdead
  """).decode(seq[MyEnum], "node") == @[meNorth, meSouth, meWest, meEast]

## #### Rename hook
## As its name suggests, a rename hook renames the fields of an object in any way you want.
## 
## Follow this signature when overloading `renameHook`:
## ```nim
## proc renameHook*(_: typedesc[MyType], fieldName: var string)
## ```
runnableExamples:
  import kdl

  type Foo = object
    kind*: string
    list*: seq[int]

  proc renameHook*(_: typedesc[Foo], fieldName: var string) = 
    fieldName = 
      case fieldName
      of "type":
        "kind"
      of "array":
        "list"
      else:
        fieldName

  # Here we rename "type" to "kind" and "array" to "list".
  assert parseKdl("""
  type "string"
  array 1 2 3
  """).decode(Foo) == Foo(kind: "string", list: @[1, 2, 3])

## 
## ----------
## 
## As you may have noticed if you looked through the API, there is `newHook` and `newHookable`, `enumHook` and `enumHookable`. 
## Any hook suffixed -able, actually calls the hook itself after making sure there is an overload that matches it. 
## You should not overload these as they are meant for internal use, the reason they are exported is because when implementing your custom decode hooks you may also want to use them.
##  
## So remember: for custom behaviour, overload -hook suffixed procedures; to make use of these hooks call the -hookable suffixed procedures, you don't call these unless you want their behavior within your custom decode hooks.
## 
## ----------
## 
## All of these examples were taken out from the [tests](https://github.com/Patitotective/kdl-nim/blob/main/tests/test_serializer.nim), so if you need more, check them out.

import std/[typetraits, strformat, strutils, strtabs, tables, sets]
import nodes, utils, types

proc rfind(a: KdlDoc, s: string): Option[KdlNode] = 
  for i in countdown(a.high, 0):
    if a[i].name.eqIdent s:
      return a[i].some

proc find(a: KdlNode, s: string): Option[KdlVal] = 
  for key, val in a.props:
    if key.eqIdent s:
      return val.some

proc rfindRename(a: KdlDoc, s: string, T: typedesc): Option[KdlNode] = 
  for i in countdown(a.high, 0):
    if a[i].name.renameHookable(T).eqIdent s:
      return a[i].some

proc findRename(a: KdlNode, s: string, T: typedesc): Option[KdlVal] = 
  for key, val in a.props:
    if key.renameHookable(T).eqIdent s:
      return val.some

# ----- Index -----

proc decode*(a: KdlSome, v: var auto)
proc decode*[T](a: KdlSome, _: typedesc[T]): T
proc decodeHook*[T: KdlSome](a: T, v: var T)
proc decodeHook*(a: KdlSome, v: var proc)

proc decode*(a: KdlDoc, v: var auto, name: string)
proc decode*[T](a: KdlDoc, _: typedesc[T], name: string): T
proc decodeHook*(a: KdlDoc, v: var Object)
proc decodeHook*(a: KdlDoc, v: var List)
proc decodeHook*(a: KdlDoc, v: var ref)

proc decodeHook*(a: KdlNode, v: var Object)
proc decodeHook*(a: KdlNode, v: var List)
proc decodeHook*(a: KdlNode, v: var auto)
proc decodeHook*(a: KdlNode, v: var ref)

proc decodeHook*[T: Value](a: KdlVal, v: var T)
proc decodeHook*[T: enum](a: KdlVal, v: var T)
proc decodeHook*(a: KdlVal, v: var char)
proc decodeHook*(a: KdlVal, v: var cstring)
proc decodeHook*[T: array](a: KdlVal, v: var T)
proc decodeHook*(a: KdlVal, v: var seq)
proc decodeHook*(a: KdlVal, v: var Object)
proc decodeHook*(a: KdlVal, v: var ref)

# ----- Hooks -----

proc newHook*[T](v: var T) = 
  when v is range:
    if v notin T.low..T.high:
      v = T.low

proc postHook*(v: var auto) = 
  discard

proc enumHook*[T: enum](a: int, v: var T) = 
  when T is HoleyEnum and not defined(kdlDecoderAllowHoleyEnums):
    fail &"forbidden int-to-HoleyEnum conversion ({a} -> {$T}); compile with -d:kdlDecoderAllowHoleyEnums"
  else:
    v = T(a)

proc enumHook*[T: enum](a: string, v: var T) = 
  v = parseEnum[T](a)

proc renameHook*(_: typedesc, fieldName: var string) = 
  discard

proc newHookable*(v: var auto) = 
  when not defined(kdlDecoderNoCaseTransitionError):
    {.push warningAsError[CaseTransition]: on.}
  mixin newHook
  newHook(v)

proc postHookable*(v: var auto) = 
  mixin postHook
  postHook(v)

proc enumHookable*[T: enum](a: string or int, v: var T) = 
  mixin enumHook
  enumHook(a, v)

proc enumHookable*[T: enum](_: typedesc[T], a: string or int): T = 
  mixin enumHook
  enumHook(a, result)

proc renameHookable*(fieldName: string, a: typedesc): string = 
  mixin renameHook
  result = fieldName
  renameHook(a, result)

# ----- KdlSome -----

proc decode*(a: KdlSome, v: var auto) = 
  mixin decodeHook

  # Don't initialize object variants yet
  when not isObjVariant(typeof v):
    newHookable(v)

  decodeHook(a, v)

proc decode*[T](a: KdlSome, _: typedesc[T]): T = 
  decode(a, result)

proc decodeHook*[T: KdlSome](a: T, v: var T) = 
  v = a

proc decodeHook*(a: KdlSome, v: var proc) = 
  fail &"{$typeof(v)} not implemented for {$typeof(a)}"

# ----- KdlDoc -----

proc decode*(a: KdlDoc, v: var auto, name: string) = 
  var found = -1
  for e in countdown(a.high, 0):
    if a[e].name.eqIdent name:
      found = e
      break

  if found < 0:
    fail "Could not find a any node for " & name.quoted

  decode(a[found], v)

proc decode*[T](a: KdlDoc, _: typedesc[T], name: string): T = 
  decode(a, result, name)

proc decodeHook*(a: KdlDoc, v: var Object) = 
  type T = typeof(v)
  when T is tuple and not isNamedTuple(T): # Unnamed tuple
    var count = 0
    for fieldName, field in v.fieldPairs:
      if count > a.high:
        fail &"Expected an argument at index {count+1} in {a}"

      decode(a[count], field)
      inc count
  else:
    const discKeys = getDiscriminants(T) # Object variant discriminator keys

    when discKeys.len > 0:
      template discriminatorSetter(key, typ): untyped = 
        let discFieldNode = a.rfindRename(key, T)

        if discFieldNode.isSome:
          decode(discFieldNode.get, typ)
        else:
          var x: typeofdesc typ
          newHookable(x)
          x

      v = initCaseObject(T, discriminatorSetter)
      newHookable(v)

    for fieldName, field in v.fieldPairs:
      when fieldName notin discKeys: # Ignore discriminant field name
        var found = false

        for node in a:
          if node.name.renameHookable(T).eqIdent fieldName:
            decode(node, field)
            found = true

        if not found:
          newHookable(field)

  postHookable(v)

proc decodeHook*(a: KdlDoc, v: var List) = 
  when v is seq:
    v.setLen a.len
  
  for e, node in a:
    decode(node, v[e])

  postHookable(v)

proc decodeHook*(a: KdlDoc, v: var ref) = 
  if v.isNil: new v
  decode(a, v[])

# ----- KdlNode -----

proc decodeHook*(a: KdlNode, v: var Object) = 
  type T = typeof(v)
  when T is tuple and not isNamedTuple(T): # Unnamed tuple
    var count = 0
    for fieldName, field in v.fieldPairs:
      if count > a.args.high:
        fail &"Expected an argument at index {count+1} in {a}"

      decode(a.args[count], field)
      inc count
  else:
    const discKeys = getDiscriminants(T) # Object variant discriminator keys
    when discKeys.len > 0:
      template discriminatorSetter(key, typ): untyped = 
        # let key1 = key.renameHookable(T)
        let discFieldNode = a.children.rfindRename(key, T) # Find a children
        let discFieldProp = a.findRename(key, T) # Find a property

        if discFieldNode.isSome:
          decode(discFieldNode.get, typ)
        elif discFieldProp.isSome:
          decode(discFieldProp.get, typ)
        else:
          var x: typeofdesc typ
          newHookable(x)
          x

      v = initCaseObject(T, discriminatorSetter)
      newHookable(v)

    for fieldName, field in v.fieldPairs:
      when fieldName notin discKeys: # Ignore discriminant field name
        var found = false
        for key, _ in a.props:
          if key.renameHookable(T).eqIdent fieldName:
            decode(a.props[key], field)
            found = true

        for node in a.children:
          if node.name.renameHookable(T).eqIdent fieldName:
            decode(node, field)
            found = true

        if not found:
          newHookable(field)

  postHookable(v)

proc decodeHook*(a: KdlNode, v: var List) = 
  when v is seq:
    v.setLen a.args.len + a.children.len

  var count = 0

  for arg in a.args:
    if count >= v.len: break
    decode(arg, v[count])

    inc count

  for child in a.children:
    if count >= v.len: break
    decode(child, v[count])
    inc count

  postHookable(v)

proc decodeHook*(a: KdlNode, v: var ref) = 
  if v.isNil: new v
  decode(a, v[])

proc decodeHook*(a: KdlNode, v: var auto) = 
  check a.args.len == 1, &"expected exactly one argument in {a}"
  decode(a.args[0], v)

# ----- KdlVal -----

proc decodeHook*[T: Value](a: KdlVal, v: var T) = 
  v = a.get(T)
  postHookable(v)

proc decodeHook*[T: enum](a: KdlVal, v: var T) = 
  case a.kind
  of KString:
    enumHookable(a.getString, v)
  of KInt:
    enumHookable(a.get(int), v)

  else:
    fail &"expected string or int in {a}"

  postHookable(v)

proc decodeHook*(a: KdlVal, v: var char) = 
  check a.isString and a.getString.len == 1, &"expected one-character-long string in a"
  v = a.getString[0]
  postHookable(v)

proc decodeHook*(a: KdlVal, v: var cstring) = 
  case a.kind
  of KNull:
    v = nil
  of KString:
    v = cstring a.getString
  else: 
    fail &"expected string or null in {a}"
  postHookable(v)

proc decodeHook*[T: array](a: KdlVal, v: var T) = 
  when v.len == 1:
    decode(a, v[0])

proc decodeHook*(a: KdlVal, v: var seq) = 
  v.setLen 1
  decode(a, v[0])

proc decodeHook*(a: KdlVal, v: var Object) = 
  fail &"{$typeof(v)} not implemented for {$typeof(a)}"

proc decodeHook*(a: KdlVal, v: var ref) = 
  if v.isNil: new v
  decode(a, v[])

# ----- Non-primitive stdlib hooks -----

# ----- Index -----

proc decodeHook*[T](a: KdlDoc, v: var SomeTable[string, T])
proc decodeHook*[T](a: KdlDoc, v: var SomeSet[T])

proc decodeHook*[T](a: KdlNode, v: var SomeTable[string, T])
proc decodeHook*[T](a: KdlNode, v: var SomeSet[T])
proc decodeHook*(a: KdlNode, v: var StringTableRef)
proc decodeHook*[T](a: KdlNode, v: var Option[T])

proc decodeHook*[T](a: KdlVal, v: var SomeSet[T])
proc decodeHook*[T](a: KdlVal, v: var Option[T])
proc decodeHook*(a: KdlVal, v: var (SomeTable[string, auto] or StringTableRef))

# ----- KdlDoc -----

proc decodeHook*[T](a: KdlDoc, v: var SomeTable[string, T]) = 
  v.clear()

  for node in a:
    v[node.name] = decode(node, T)

  postHookable(v)

proc decodeHook*[T](a: KdlDoc, v: var SomeSet[T]) = 
  v.clear()

  for node in a:
    v.incl decode(KdlDoc, T)

  postHookable(v)

# ----- KdlNode -----

proc decodeHook*[T](a: KdlNode, v: var SomeTable[string, T]) = 
  v.clear()

  for key, val in a.props:
    v[key] = decode(val, T)
    
  for node in a.children:
    v[node.name] = decode(node, T)

  postHookable(v)

proc decodeHook*[T](a: KdlNode, v: var SomeSet[T]) = 
  v.clear()

  for arg in a.args:
    v.incl decode(arg, T)

  postHookable(v)

proc decodeHook*(a: KdlNode, v: var StringTableRef) = 
  v = newStringTable()

  for key, val in a.props:
    v[key] = decode(val, string)
    
  for node in a.children:
    v[node.name] = decode(node, string)

  postHookable(v)

proc decodeHook*[T](a: KdlNode, v: var Option[T]) = 
  v = 
    try:  
      decode(a, T).some
    except KdlError:
      none[T]()

  postHookable(v)

# ----- KdlVal -----

proc decodeHook*[T](a: KdlVal, v: var SomeSet[T]) = 
  v.clear()

  v.incl decode(a, T)

  postHookable(v)

proc decodeHook*[T](a: KdlVal, v: var Option[T]) = 
  if a.isNull:  
    v = none[T]()
  else:
    v = decode(a, T).some

  postHookable(v)

proc decodeHook*(a: KdlVal, v: var (SomeTable[string, auto] or StringTableRef)) = 
  fail &"{$typeof(v)} not implemented for {$typeof(a)}"
