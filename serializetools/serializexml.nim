## Support for serialization of objects to and from xml

import xmltree, typeinfo, macros, strutils, tables, array1d

proc storeAnyXML(s: XmlNode, a: Any) =
  ## writes the XML representation of the Any `a`.
  case a.kind
  of akNone: assert false
  of akBool: s.add(newText($getBool(a)))
  of akChar:
    let ch = getChar(a)
    s.add(newText($ch))
  of akSet:
    for e in elements(a):
      var ss = newElement("elem")
      ss.add(newText($e))
      s.add(ss)
  of akEnum: s.add(newText(getEnumField(a)))
  of akString:
    var x = getString(a)
    s.add(newText(x))
  of akInt..akInt64, akUInt..akUInt64: s.add(newText($getBiggestInt(a)))
  of akFloat..akFloat128: s.add(newText($getBiggestFloat(a)))
  else:
    raise newException(IOError, "storeAnyXML: error in xml writer - unsupported kind= " & $a.kind)

proc storeArrayLeafXML[T](data: T): XmlNode =
  ## Arrays or Seqs of numbers are space separate and take the form  <x>1.0 5.1</x>  rather than `elem`.
  var dest: string =  ""
  var i = 0
  for s in items(data):
    if i > 0: dest.add(" ")
    dest.add($s)
    inc(i)
  result = newText(dest)

proc doStoreXML[T](name: string, data: T): XmlNode =
  result = newElement(name)
  # Compile-time telephone book. The style of keys varies according to the type
  when (T is char|bool|SomeNumber|string|set|enum):
    var d: T
    shallowCopy(d, data)
    storeAnyXML(result, toAny(d))

  elif (T is Array1dO):
    when (data[0] is SomeNumber):
      result.add(storeArrayLeafXML(data.data))
    else:
      for v in data.data.items:
        result.add(doStoreXML("elem", v))

  elif (T is Table):
    for k, v in data.pairs:
      var ss  = newElement("elem")
      ss.add(doStoreXML("Key", k))
      ss.add(doStoreXML("Val", v))
      result.add(ss)

  elif (T is array|seq):
    when (data[0] is SomeNumber):
      result.add(storeArrayLeafXML(data))
    else:
      for v in data.items:
        result.add(doStoreXML("elem", v))

  elif (T is tuple):
    for k, v in data.fieldPairs:
      result.add(doStoreXML($k, v))

  elif (T is object):
    for k, v in data.fieldPairs:
      result.add(doStoreXML(k, v))

  else:
    raise newException(IOError, "doStoreXML: error - unsupported type of output: repr(data)= " & repr(data))

# Main serialization function
macro serializeXML*(x: typed): untyped =
  ## Serialize data `x` into an XML representation
  result = newCall(bindSym"doStoreXML", toStrLit(x), x)


#--------------------------------------------------------------------------
# Deserialization support
#
proc loadAnyXML(s: XmlNode, a: Any) =
  ## Read a single xml node
#  echo "loadAnyXML: s.tag= ", s.tag, "  s.kind= ", s.kind, "  a.kind= ", a.kind
#  echo "loadAnyXML: s.kind= ", s.kind
  if s.kind != xnElement:
    raise newException(IOError, "loadAnyXML: internal error: illegal xml - kind of xml node should be xnElement")

  # Walk through all the cases
  case a.kind
  of akNone: assert false
  of akBool:
    if s.len == 1:
      for ss in items(s):
        case ss.text
        of "false": setBiggestInt(a, 0)
        of "true": setBiggestInt(a, 1)
        else: 
          raise newException(IOError, "loadAnyXML: 'true' or 'false' expected for a bool")
    else:
      raise newException(IOError, "loadAnyXML: illegal xml - bool expected")

  of akChar:
    if s.len == 1:
      for ss in items(s):
        if ss.text.len == 1:
          setBiggestInt(a, ord(ss.text[0]))
        else:
          raise newException(IOError, "loadAnyXML: illegal xml - char expected")
    else:
      raise newException(IOError, "loadAnyXML: illegal xml - char expected")

  of akString:
    if s.len == 1:
      for ss in items(s):
        setString(a, ss.text)
    else:
      raise newException(IOError, "loadAnyXML: illegal xml - string expected")

  of akInt..akInt64, akUInt..akUInt64:
    if s.len == 1:
      for ss in items(s):
        setBiggestInt(a, parseBiggestInt(ss.text))
    else:
      raise newException(IOError, "loadAnyXML: illegal xml - integer expected")

  of akFloat..akFloat128:
    if s.len == 1:
      for ss in items(s):
        setBiggestFloat(a, parseFloat(ss.text))
    else:
      raise newException(IOError, "loadAnyXML: illegal xml - float expected")

  of akArray:
    var i = 0
    for ss in items(s):
      loadAnyXML(ss, a[i])
      inc(i)
  of akSequence:
    invokeNewSeq(a, 0)
    var i = 0
    for ss in items(s):
      extendSeq(a)
      loadAnyXML(ss, a[i])
      inc(i)
  of akSet:
    for ss in items(s):
      inclSetElement(a, parseInt(ss[0].text))
  of akObject, akTuple:
    if a.kind == akObject: setObjectRuntimeType(a)
    for ss in items(s):
      let fieldName = tag(ss)
      loadAnyXML(ss, a[fieldName])
  else:
    raise newException(IOError, "loadAnyXML: error in XML deserializer - unsupported kind = " & $a.kind)


#--------------------------------------------------------------------------
proc loadArrayLeaf(a: Any, src: string) =
  ## Read in `a` from the string in `src`
  # Walk through possible Number types
  case a.kind
  of akNone: assert false
  of akBool:
    case src:
      of "false": setBiggestInt(a, 0)
      of "true": setBiggestInt(a, 1)
      else: 
        raise newException(IOError, "loadArrayLeaf: 'true' or 'false' expected for a bool")
  of akChar:
    setBiggestInt(a, ord(src[0]))
  of akInt..akInt64, akUInt..akUInt64:
    setBiggestInt(a, parseBiggestInt(src))
  of akFloat..akFloat128:
    setBiggestFloat(a, parseFloat(src))
  else:
    raise newException(IOError, "loadArrayLeaf: unsupported destination kind= " & $a.kind)


# forward decl
proc deserializeXML*[T](s: XmlNode, path: string): T
  ## reads an XML representation `s` and transforms it to a ``T``.

# Implementation functions
proc deserializeArrayXML[T](s: XmlNode, path: string, val: var openArray[T]) =
  ## reads an XML representation `s` and transforms it to an openarray.
  if tag(s) != path:
    raise newException(IOError, "Array: path= " & path & " does not match XmlNode tag= " & tag(s))
  when T is SomeNumber:
    if s.len != 1:
      raise newException(IOError, "Array: Error reading a compact xml array")

    # Must parse the string of the form    <x>15.0 1 19.0</x>
    let a = splitWhitespace(s[0].text)
    for i in 0..a.len-1:
      loadArrayLeaf(toAny(val[i]), a[i])
  else:
    if s.len != 1:
      raise newException(IOError, "Array: Error reading a verbose xml array")
    for i in 0..val.len-1:
      val[i] = deserializeXML[T](s[i], "elem")

proc deserializeSeqXML[T](s: XmlNode, path: string, val: var seq[T]) =
  ## reads an XML representation `s` and transforms it to an seq.
  if tag(s) != path:
    raise newException(IOError, "Sequence: path= " & path & " does not match XmlNode tag= " & tag(s))

  when T is SomeNumber:
    if s.len != 1:
      raise newException(IOError, "Sequence: Error reading a compact xml array")
    # Must parse the string of the form    <x>15.0 1 19.0</x>
    let a = splitWhitespace(s[0].text)
    val = newSeq[T](a.len)
    for i in 0..a.len-1:
      loadArrayLeaf(toAny(val[i]), a[i])
  else:
    val = newSeq[T](s.len)
    for i in 0..s.len-1:
      val[i] = deserializeXML[T](s[i], "elem")

proc deserializeTupleXML(s: XmlNode, path: string, val: var tuple) =
  ## reads an XML representation `s` and transforms it to an seq.
  if tag(s) != path:
    raise newException(IOError, "Tuple: path= " & path & " does not match XmlNode tag= " & tag(s))

  for k, v in fieldPairs(val):
    let sk = s.child(k)
    if sk == nil:
      raise newException(IOError, "Tuple: Error in tuple xml - missing k= " & k)
    v = deserializeXML[type(v)](sk, k)

proc deserializeTableXML[K,V](s: XmlNode, path: string, val: var Table[K,V]) =
  ## reads an XML representation `s` and transforms it to a Table[K,V]
  if tag(s) != path:
    raise newException(IOError, "Table: path= " & path & " does not match XmlNode tag= " & tag(s))

  val = initTable[K,V]()
  for i in 0..s.len-1:
    if tag(s[i]) != "elem":
      raise newException(IOError, "Table: error reading table: expected key=elem, but found XmlNode tag= " & tag(s) )

    let sk = s[i].child("Key")
    if sk == nil:
      raise newException(IOError, "Table: missing Key")
    var k: K = deserializeXML[K](sk, "Key")

    let sv = s[i].child("Val")
    if sv == nil:
      raise newException(IOError, "Table: missing Val")

    var v: V = deserializeXML[V](sv, "Val")
    val.add(k, v)


proc deserializeXML*[T](s: XmlNode, path: string): T =
  ## reads an XML representation `s` and transforms it to a ``T``, and check the key is `path`
#  echo "deserXML:  s.tag= ", s.tag, "  s.kind= ", s.kind, "  path= ", path
#  echo "deserXML:  s.kind= ", s.kind, "  path= ", path
#  echo "deserXML:  s= ", s, "  path= ", path
  when (T is char|bool|SomeNumber|string|set|enum):
    if tag(s) != path:
      raise newException(IOError, "deserialize: path= " & path & " does not match XmlNode tag= " & tag(s))
    loadAnyXML(s, toAny(result))
  elif (T is Array1dO):
    deserializeSeqXML(s, path, result.data)
  elif (T is Table):
    deserializeTableXML(s, path, result)
  elif (T is array):
    deserializeArrayXML(s, path, result)
  elif (T is seq):
    deserializeSeqXML(s, path, result)
  elif (T is tuple):
    deserializeTupleXML(s, path, result)
  elif (T is object):
    if tag(s) != path:
      raise newException(IOError, "deserialize: path= " & path & " does not match XmlNode tag= " & tag(s))
    for k, v in fieldPairs(result):
      let sk = s.child(k)
      if sk == nil:
        raise newException(IOError, "Error in object xml - missing key= " & k)
      v = deserializeXML[type(v)](sk, k)
  elif (T is set):
    deserializeSetXML(s, path, result)
  else: 
    raise newException(IOError, "deserializeXML: error - unsupported type")

proc deserializeXML*[T](s: XmlNode): T =
  ## reads an XML representation `s` and transforms it to a ``T``.
  result = deserializeXML[T](s, tag(s))
