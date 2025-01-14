## ## Prefs
## This modules implements some simple procedures to save user preferences in a KDL file. 
## 
## To do so you'll use the `KdlPrefs` object:
## ```nim
## type KdlPrefs*[T] = object
##   path*: string
##   default*: T
##   content*: T
## ```
## As you can see it consists of:
## - The path to store the preferences file in.
## - The default preferences.
## - The current preferences.
## The `default` and `content` fields are generics because you're supposed to create an object with the preferences as fields, though if you want to use `KdlDoc` you still can:
## ```nim
## import kdl, kdl/prefs
## 
## type
##   Theme* = enum
##     tDark, tLight
## 
##   Lang* = enum
##     lEs, lEn, lJp
## 
##   Prefs* = object
##     theme*: Theme
##     lang*: Lang
##     age*: Option[Natural]
##     name*: Option[string]
## 
## var p = initKPrefs(path = "prefs.kdl", default = Prefs(theme: tLight, lang: lEn))
## 
## assert p.content == Prefs(theme: tLight, lang: lEn, age: Natural.none, name: string.none) # Default value
## 
## p[lang] = lEs ## p[lang]= is a shortcut for p.content.lang=
## 
## assert p[lang] == lEs # p[lang] is a shortcut for p.content.lang
## 
## p.save() # Write the changes to the file
## ```
## If you run the code above once it will run without complains, but if you run it twice the first `assert` will fail since now `lang` is not `lEn` but `lEs`.
## 
## If we want to reset `lang` to its default value, we can do as the following:
## ```nim
## import kdl, kdl/prefs
## 
## type
##   Theme* = enum
##     tDark, tLight
## 
##   Lang* = enum
##     lEs, lEn, lJp
## 
##   Prefs* = object
##     theme*: Theme
##     lang*: Lang
##     age*: Option[Natural]
##     name*: Option[string]
## 
## var p = initKPrefs(path = "prefs.kdl", default = Prefs(theme: tLight, lang: lEn))
## 
## p[lang] = p{lang} ## p{lang} is a shortcut for p.default.lang
## 
## assert p.content == Prefs(theme: tLight, lang: lEn, age: Natural.none, name: string.none) # Default value
## 
## p[lang] = lEs ## p.content.lang = lEs
## 
## assert p[lang] == lEs # assert p.content.lang == les
## 
## p.save() # Write the changes to the file
## ```
{.used.}

import std/[tables, os]
import parser, types

proc initKPrefs*(path: string, default: KdlDoc, stream = false): KdlPrefs[KdlDoc] =
  ## Initialize a KdlPrefs object, loading the content from path if it exists or using the default content.
  ## - Use `stream` to parse the file as a `FileStream`.

  result = KdlPrefs[KdlDoc](path: path, default: default)
  result.content = 
    if path.fileExists:
      if stream:
        parseKdlFileStream(path)
      else:
        parseKdlFile(path)
    else:
      default

proc initKPrefs*[T](path: string, default: T, stream = false): KdlPrefs[T] =
  ## Initialize a KdlPrefs object, loading the content from path if it exists or using the default content.
  ## - Use `stream` to parse the file as a `FileStream`.

  result = KdlPrefs[T](path: path, default: default)

  if path.fileExists:
    if stream:
      parseKdlFileStream(path).decode(result.content)
    else:
      parseKdlFile(path).decode(result.content)
  else:
    result.content = default

proc save*(prefs: KdlPrefs[KdlDoc]) =
  ## Saves the content to the path.
  prefs.path.splitPath.head.createDir()
  prefs.path.writeFile($prefs.content & '\n')

proc save*(prefs: KdlPrefs[auto]) =
  ## Saves the content to the path encoding it to KDL.
  prefs.path.splitPath.head.createDir()
  prefs.path.writeFile(prefs.content.encode())

proc removeFile*(prefs: KdlPrefs[auto]) =
  ## Deletes the preferences file if it exists.
  if prefs.path.fileExists:
    prefs.path.removeFile

template `[]`*(prefs: KdlPrefs[auto], field): untyped = 
  ## `prefs[field]` -> `prefs.content.field`
  prefs.content.field

template `[]=`*(prefs: KdlPrefs[auto], field, val): untyped = 
  ## `prefs[field] = val` -> `prefs.content.field = val`
  prefs.content.field = val

template `{}`*(prefs: KdlPrefs[auto], field): untyped = 
  ## `prefs{field}` -> `prefs.default.field`
  prefs.default.field
