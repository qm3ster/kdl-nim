import std/[strformat, strutils, options, tables, macros]

import types, utils

export options, tables

# ----- Initializers -----

proc initKNode*(name: string, tag = string.none, args: openarray[KdlVal] = newSeq[KdlVal](), props = initTable[string, KdlVal](), children: openarray[KdlNode] = newSeq[KdlNode]()): KdlNode = 
  KdlNode(tag: tag, name: name, args: @args, props: props, children: @children)

proc initKVal*(val: string, tag = string.none): KdlVal = 
  KdlVal(tag: tag, kind: KString, str: val)

proc initKVal*(val: SomeFloat, tag = string.none): KdlVal = 
  KdlVal(tag: tag, kind: KFloat, fnum: val.float)

proc initKVal*(val: bool, tag = string.none): KdlVal = 
  KdlVal(tag: tag, kind: KBool, boolean: val)

proc initKVal*(val: SomeInteger, tag = string.none): KdlVal = 
  KdlVal(tag: tag, kind: KInt, num: val.int64)

proc initKVal*(val: typeof(nil), tag = string.none): KdlVal = 
  KdlVal(tag: tag, kind: KNull)

proc initKVal*(val: KdlVal): KdlVal = val

proc initKString*(val = string.default, tag = string.none): KdlVal = 
  initKVal(val, tag)

proc initKFloat*(val: SomeFloat = float.default, tag = string.none): KdlVal = 
  initKVal(val.float, tag)

proc initKBool*(val = bool.default, tag = string.none): KdlVal = 
  initKVal(val, tag)

proc initKNull*(tag = string.none): KdlVal = 
  KdlVal(tag: tag, kind: KNull)

proc initKInt*(val: SomeInteger = int64.default, tag = string.none): KdlVal = 
  initKVal(val.int64, tag)

# ----- Comparisions -----

proc isString*(val: KdlVal): bool = 
  val.kind == KString

proc isFloat*(val: KdlVal): bool = 
  val.kind == KFloat

proc isBool*(val: KdlVal): bool = 
  val.kind == KBool

proc isInt*(val: KdlVal): bool = 
  val.kind == KInt

proc isNull*(val: KdlVal): bool = 
  val.kind == KNull

proc isEmpty*(val: KdlVal): bool = 
  val.kind == KEmpty

# ----- Getters -----

proc getString*(val: KdlVal): string = 
  check val.isString()
  val.str

proc getFloat*(val: KdlVal): float = 
  check val.isFloat()
  val.fnum

proc getBool*(val: KdlVal): bool = 
  check val.isBool()
  val.boolean

proc getInt*(val: KdlVal): int64 = 
  check val.isInt()
  val.num

proc get*[T: SomeNumber or string or bool](val: KdlVal, x: typedesc[T]): T = 
  ## Tries to get and convert val to T, raises an error when it cannot.
  runnableExamples:
    let val = initKFloat(3.14)

    assert val.get(int) == 3
    assert val.get(uint) == 3u
    assert val.get(float) == 3.14
    assert val.get(float32) == 3.14f

  when T is string:
    result = 
      case val.kind
      of KFloat:
        $val.getFloat()
      of KString:
        val.getString()
      of KBool:
        $val.getBool()
      of KNull:
        "null"
      of KInt:
        $val.getInt()
      of KEmpty:
        "empty"
  elif T is SomeNumber:
    check val.isFloat or val.isInt

    result = 
      if val.isInt:
        T(val.getInt)
      else:
        T(val.getFloat)
  elif T is bool:
    check val.isBool

    result = val.getBool

# ----- Setters -----

proc setString*(val: var KdlVal, x: string) = 
  check val.isString()
  val.str = x

proc setFloat*(val: var KdlVal, x: SomeFloat) = 
  check val.isFloat()
  val.fnum = x

proc setBool*(val: var KdlVal, x: bool) = 
  check val.isBool()
  val.boolean = x

proc setInt*(val: var KdlVal, x: SomeInteger) = 
  check val.isInt()
  val.num = x

proc setTo*[T: SomeNumber or string or bool](val: var KdlVal, x: T) = 
  ## Tries to set val to x, raises an error when types are not compatible.
  runnableExamples:
    var val = initKFloat(3.14)

    val.setTo(100u8)

    assert val.getFloat() == 100

    val.setTo(20.12e2f)

    assert val.get(float32) == 20.12e2f

  when T is string:
    val.setString(x)
  elif T is SomeNumber:
    if val.isInt:
      val.setInt(x.int64)
    else:
      val.setFloat(x.float)
  elif T is bool:
    val.setBool(x)

# ----- Operators -----

proc `$`*(val: KdlVal): string = 
  if val.tag.isSome:
    result = &"({val.tag.get.quoted})"

  result.add:
    case val.kind
    of KFloat:
      $val.getFloat()
    of KString:
      val.getString().quoted
    of KBool:
      $val.getBool()
    of KNull:
      "null"
    of KInt:
      $val.getInt()
    of KEmpty:
      "empty"

proc `$`*(doc: KdlDoc): string

proc `$`*(node: KdlNode): string = 
  if node.tag.isSome:
    result = &"({node.tag.get.quoted})"

  result.add node.name.quoted()

  if node.args.len > 0:
    result.add " "
    for e, val in node.args:
      if e in 1..node.args.high:
        result.add " "

      result.add $val

  if node.props.len > 0:
    result.add " "
    var count = 0
    for key, val in node.props:
      if count in 1..<node.props.len:
        result.add " "

      result.add &"{key.quoted}={val}"

      inc count

  if node.children.len > 0:
    result.add " {\n"
    result.add indent($node.children, 2)
    result.add "\n}"

proc `$`*(doc: KdlDoc): string = 
  for e, node in doc:
    result.add $node
    if e < doc.high:
      result.add "\n"

proc `==`*(val1, val2: KdlVal): bool = 
  ## Checks if val1 and val2 have the same value. They must be of the same kind.

  check val1.kind == val2.kind

  case val1.kind
  of KString:
    val1.getString() == val2.getString()
  of KFloat:
    val1.getFloat() == val2.getFloat()
  of KBool:
    val1.getBool() == val2.getBool()
  of KNull, KEmpty:
    true
  of KInt:
    val1.getInt() == val2.getInt()

proc `==`*[T: SomeNumber or string or bool](val: KdlVal, x: T): bool = 
  ## Checks if val is x, raises an error when they are not comparable.

  when T is string:
    check val.isString
    result = val.getString() == x
  elif T is SomeNumber:
    check val.isFloat or val.isInt

    result = 
      if val.isInt:
        val.getInt() == x.int64
      else:
        val.getFloat() == x.float
  elif T is bool:
    check val.isBool

    result = val.getBool() == x

proc `[]`*(node: KdlNode, key: string): KdlVal = 
  ## Gets the value of the key property.
  node.props[key]

proc `[]`*(node: var KdlNode, key: string): var KdlVal = # TODO test
  ## Gets the value of the key property.
  node.props[key]

proc `[]=`*(node: var KdlNode, key: string, val: KdlVal) = 
  ## Sets the key property to val in node.
  node.props[key] = val

proc hasKey*(node: KdlNode, key: string): bool = 
  ## Checks if node has the key property.
  node.props.hasKey(key)

proc contains*(node: KdlNode, key: string): bool = 
  ## Checks if node has the key property.
  node.props.contains(key)

proc contains*(node: KdlNode, val: KdlVal): bool = 
  ## Checks if node has the val argument.
  node.args.contains(val)

proc contains*(node: KdlNode, child: KdlNode): bool = 
  ## Checks if node has the child children.
  node.children.contains(child)

proc add*(node: var KdlNode, val: KdlVal) = 
  ## Adds val to node's arguments.

  node.args.add(val)

proc add*(node: var KdlNode, child: KdlNode) = 
  ## Adds child to node's children.

  node.children.add(child)

# ----- Macros -----

const identNodes = {nnkStrLit, nnkRStrLit, nnkTripleStrLit, nnkIdent}

proc strIdent(node: NimNode): NimNode = 
  node.expectKind(identNodes)
  newStrLitNode(node.strVal)

proc withTag(body: NimNode): tuple[body, tag: NimNode] = 
  result.tag = newCall("none", ident"string")

  if body.kind == nnkBracketExpr:
    result.body = body[0]
    result.tag = newCall("some", body[1].strIdent)
  else:
    result.body = body

  result.tag = newTree(nnkExprEqExpr, ident"tag", result.tag)

proc toKdlValImpl(body: NimNode): NimNode = 
  let (value, tag) = body.withTag()

  newCall("initKVal", value, tag)

proc toKdlNodeImpl(body: NimNode): NimNode = 
  var body = body

  if body.kind in identNodes + {nnkBracketExpr}:
    let (name, tag) = body.withTag()
    return newCall("initKNode", name.strIdent, tag)
  elif body.kind == nnkStmtList: # When a node has children it ends up being nnkStmtList
    body.expectLen(1)
    body = body[0]

  body.expectKind(nnkCall)
  body.expectMinLen(2)

  let (name, tag) = body[0].withTag()

  result = newCall("initKNode", name.strIdent, tag)

  var i = 1 # Index to start parsing args and props from (1 by default because )

  let args = newNimNode(nnkBracket)
  let props = newNimNode(nnkTableConstr)

  while i < body.len and body[i].kind != nnkStmtList:
    if body[i].kind == nnkExprEqExpr:
      props.add newTree(nnkExprColonExpr, body[i][0].strIdent, toKdlValImpl(body[i][1]))
    else:
      args.add newCall("initKVal", toKdlValImpl(body[i]))

    inc i

  result.add newTree(nnkExprEqExpr, ident"args", args)

  if props.len > 0:
    result.add newTree(nnkExprEqExpr, ident"props", newDotExpr(props, ident"toTable"))

  if i < body.len: # Children
    body[i].expectKind(nnkStmtList)
    result.add newTree(nnkExprEqExpr, ident"children", newCall("toKdl", body[i]))

macro toKdlVal*(body: untyped): KdlVal = 
  ## Generate a KdlVal from Nim's AST that is somehat similar to KDL's syntax.
  ## - For type annotations use a bracket expresion: `node[tag]` instead of `(tag)node`.

  toKdlValImpl(body)

macro toKdlNode*(body: untyped): KdlNode = 
  ## Generate a KdlNode from Nim's AST that is somewhat similar to KDL's syntax.
  ## - For nodes use call syntax: `node(args, props)`.
  ## - For properties use an equal expression: `key=val`.
  ## - For children pass a block to a node: `node(args, props): ...`
  runnableExamples:
    let node = toKdlNode:
      numbers(10[u8], 20[i32], myfloat=1.5[f32]):
        strings("123e4567-e89b-12d3-a456-426614174000"[uuid], "2021-02-03"[date], filter=r"$\d+"[regex])
        person[author](name="Alex")
    # It is the same as: 
    # numbers (u8)10 (i32)20 myfloat=(f32)1.5 {
    #   strings (uuid)"123e4567-e89b-12d3-a456-426614174000" (date)"2021-02-03" filter=(regex)r"$\d+"
    #   (author)person name="Alex"
    # }

  toKdlNodeImpl(body)

macro toKdl*(body: untyped): KdlDoc = 
  ## Generate a KdlDoc from Nim's AST that is somewhat similar to KDL's syntax.
  ## 
  ## See also [toKdlNode](#toKdlNode.m,untyped).

  if body.kind == nnkStmtList:
    let doc = newNimNode(nnkBracket)

    for call in body:
      doc.add toKdlNodeImpl(call)

    result = prefix(doc, "@")
  else:
    result = toKdlValImpl(body)

macro toKdlArgs*(args: varargs[typed]): untyped = 
  ## Creates an array of `KdlVal`s by calling `initKVal` through `args`.
  runnableExamples:
    assert toKdlArgs(1, 2, "a") == [1.initKVal, 2.initKVal, "a".initKVal]
    assert initKNode("name", args = toKdlArgs(nil, true, "b")) == initKNode("name", args = [initKNull(), true.initKVal, "b".initKVal])

  args.expectKind nnkBracket
  result = newNimNode(nnkBracket)
  for arg in args:
    result.add newCall("initKVal", arg)

macro toKdlProps*(props: untyped): Table[string, KdlVal] = 
  ## Creates a `Table[string, KdlVal]` from a array-of-tuples/table-constructor by calling `initKVal` through the values.
  runnableExamples:
    assert toKdlProps({"a": 1, "b": 2}) == {"a": 1.initKVal, "b": 2.initKVal}.toTable
    assert initKNode("name", props = toKdlProps({"c": nil, "d": true})) == initKNode("name", props = {"c": initKNull(), "d": true.initKVal}.toTable)

  props.expectKind nnkTableConstr
  
  result = newNimNode(nnkTableConstr)
  for i in props:
    i.expectKind nnkExprColonExpr
    result.add newTree(nnkExprColonExpr, i[0], newCall("initKVal", i[1]))

  result = newCall("toTable", result)
