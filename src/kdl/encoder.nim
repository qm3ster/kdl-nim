## ## Encoder
## This module implements a serializer for different types and objects into KDL documents, nodes and values:
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
  import std/options
  import kdl

  type
    Package = object
      name*, version*: string
      authors*: Option[seq[string]]
      description*, licenseFile*, edition*: Option[string]

  const doc = parseKdl("""
"name" "kdl"
"version" "0.0.0"
"authors" {
  "-" "Kat Marchán <kzm@zkat.tech>"
}
"description" "kat's document language"
"licenseFile" "LICENSE.md"
"edition" "2018"
    """)

  assert Package(name: "kdl", version: "0.0.0", authors: @["Kat Marchán <kzm@zkat.tech>"].some, description: "kat's document language".some, licenseFile: "LICENSE.md".some, edition: "2018".some).encode() == doc

## ### Custom Encode Hooks
## If you need to encode a specific type in a specific way you may use custom encode hooks.
## 
## To do so, you'll have to overload the `encodeHook` procedure with the following signatura:
## ```nim
## proc encodeHook*(a: MyType, v: var KdlSome)
## ```
## Where `KdlSome` is one of `KdlDoc`, `KdlNode` or `KdlVal`.
runnableExamples:
  import std/times
  import kdl
  
  proc encodeHook*(a: DateTime, v: var KdlDoc) = 
    v = @[
      initKNode("year", args = @[encode(a.year, KdlVal)]), 
      initKNode("month", args = @[encode(a.month, KdlVal)]), 
      initKNode("day", args = @[encode(a.monthday, KdlVal)]), 
      initKNode("hour", args = @[encode(a.hour, KdlVal)]), 
      initKNode("minute", args = @[encode(a.minute, KdlVal)]), 
      initKNode("second", args = @[encode(a.second, KdlVal)]), 
      initKNode("nanosecond", args = @[encode(a.nanosecond, KdlVal)]), 
    ]

  const doc = parseKdl("""
"year" 2022
"month" "October"
"day" 15
"hour" 12
"minute" 4
"second" 0
"nanosecond" 0
  """)

  assert dateTime(2022, mOct, 15, 12, 04).encode() == doc

import std/[typetraits, strformat, enumerate, options, strtabs, tables, sets]
import nodes, utils, types

# ----- Index -----

proc encode*(a: auto, v: var KdlDoc)
proc encode*(a: auto, v: var KdlVal)
proc encode*(a: auto, v: var KdlNode, name: string)
proc encode*(a: auto): KdlDoc
proc encode*(a: auto, name: string): KdlNode
proc encode*[T: KdlSome](a: auto, _: typedesc[T]): T

proc encodeHook*(a: List, v: var KdlDoc)
proc encodeHook*(a: Object, v: var KdlDoc)
proc encodeHook*(a: ref, v: var KdlDoc)

proc encodeHook*(a: KdlVal, v: var KdlNode, name: string)
proc encodeHook*(a: List, v: var KdlNode, name: string)
proc encodeHook*(a: Object, v: var KdlNode, name: string)
proc encodeHook*(a: ref, v: var KdlNode, name: string)
proc encodeHook*(a: auto, v: var KdlNode, name: string)

proc encodeHook*(a: Value, v: var KdlVal)
proc encodeHook*(a: cstring, v: var KdlVal)
proc encodeHook*(a: char, v: var KdlVal)
proc encodeHook*(a: KdlVal, v: var KdlVal)
proc encodeHook*(a: enum, v: var KdlVal)
proc encodeHook*(a: List, v: var KdlVal)

# ----- KdlSome -----

proc encode*(a: auto, v: var KdlDoc) = 
  mixin encodeHook
  encodeHook(a, v)

proc encode*(a: auto, v: var KdlVal) = 
  mixin encodeHook
  encodeHook(a, v)

proc encode*(a: auto, v: var KdlNode, name: string) = 
  mixin encodeHook
  encodeHook(a, v, name)

proc encode*(a: auto): KdlDoc = 
  encode(a, result)

proc encode*(a: auto, name: string): KdlNode = 
  encode(a, result, name)

proc encode*[T: KdlSome](a: auto, _: typedesc[T]): T = 
  when T is KdlDoc:
    encode(a, result)
  elif T is KdlNode:
    encode(a, result, "node")
  elif T is KdlVal:
    encode(a, result)

# ----- KdlDoc -----

proc encodeHook*(a: List, v: var KdlDoc) = 
  v.setLen(a.len)
  for e, i in a:
    encode(i, v[e], "-")

proc encodeHook*(a: Object, v: var KdlDoc) = 
  type T = typeof(a)

  when T is tuple and not isNamedTuple(T): # Unnamed tuple
    for _, field in a.fieldPairs:
      v.add encode(field, "-")
  else:
    for fieldName, field in a.fieldPairs:
      v.add encode(field, fieldName)

proc encodeHook*(a: ref, v: var KdlDoc) = 
  encode(a[], v)

# ----- KdlNode -----

proc encodeHook*(a: KdlVal, v: var KdlNode, name: string) = 
  v = initKNode(name, args = @[a])

proc encodeHook*(a: List, v: var KdlNode, name: string) = 
  v = initKNode(name)
  v.children.setLen(a.len)
  for e, i in a:
    encode(i, v.children[e], "-")

proc encodeHook*(a: Object, v: var KdlNode, name: string) = 
  v = initKNode(name)
  type T = typeof(a)

  when T is tuple and not isNamedTuple(T): # Unnamed tuple
    for _, field in a.fieldPairs:
      v.args.add encode(field, KdlVal)
  else:
    encode(a, v.children)

proc encodeHook*(a: ref, v: var KdlNode, name: string) = 
  encode(a[], v, name)

proc encodeHook*(a: auto, v: var KdlNode, name: string) = 
  v = initKNode(name)
  v.args.setLen(1)
  encode(a, v.args[0])

# ----- KdlVal -----

proc encodeHook*(a: Value, v: var KdlVal) = 
  v = a.initKVal

proc encodeHook*(a: cstring, v: var KdlVal) = 
  if a.isNil:
    v = initKNull()
  else:
    v = initKString($a)

proc encodeHook*(a: char, v: var KdlVal) = 
  v = initKString($a)

proc encodeHook*(a: KdlVal, v: var KdlVal) = 
  v = a

proc encodeHook*(a: enum, v: var KdlVal) = 
  v = initKString($a)

proc encodeHook*(a: List, v: var KdlVal) = 
  check a.len == 1, &"cannot encode {$typeof(a)} to {$typeof(v)}"
  encode(a[0], v)

# ----- Non-primitive stdlib hooks -----

# ----- Index -----

proc encodeHook*(a: SomeTable[string, auto] or StringTableRef, v: var KdlDoc)
proc encodeHook*(a: SomeSet[auto], v: var KdlDoc)

proc encodeHook*(a: SomeTable[string, auto] or SomeSet[auto] or StringTableRef, v: var KdlNode, name: string)
proc encodeHook*(a: Option[auto], v: var KdlNode, name: string)

proc encodeHook*(a: Option[auto], v: var KdlVal)

# ----- KdlDoc -----

proc encodeHook*(a: SomeTable[string, auto] or StringTableRef, v: var KdlDoc) = 
  v.setLen(a.len)

  for e, (key, val) in enumerate(a.pairs):
    encode(val, v[e], key)

proc encodeHook*(a: SomeSet[auto], v: var KdlDoc) = 
  v.setLen(a.len)

  for e, i in enumerate(a):
    encode(i, v[e], "-")

# ----- KdlNode -----

proc encodeHook*(a: SomeTable[string, auto] or SomeSet[auto] or StringTableRef, v: var KdlNode, name: string) = 
  v = initKNode(name)
  encode(a, v.children)

proc encodeHook*(a: Option[auto], v: var KdlNode, name: string) = 
  if a.isNone:
    v = initKNode(name)
  else:
    encode(a.get, v, name)

# ----- KdlVal -----

proc encodeHook*(a: Option[auto], v: var KdlVal) = 
  if a.isNone:  
    v = initKNull()
  else:
    encode(a.get, v)
