import Base
import ./svg.bend as S

# The icon set: SVG path data on a 24 x 24 grid, drawn with a 2-unit
# round stroke unless a layer says fill. One source for both UIs: the
# window rasterizes these (src/gfx/icon.bend), the web client writes them
# as inline <svg> (src/web/icon.bend).
#
# The paths are Lucide's (https://lucide.dev), with <circle>, <rect> and
# <line> elements written as paths and rectangle corners squared (house
# rule). Lucide's licence:
#
#   ISC License
#
#   Copyright (c) for portions of Lucide are held by Cole Bemis 2013-2022
#   as part of Feather (MIT). All other copyright (c) for Lucide are held
#   by Lucide Contributors 2022.
#
#   Permission to use, copy, modify, and/or distribute this software for
#   any purpose with or without fee is hereby granted, provided that the
#   above copyright notice and this permission notice appear in all
#   copies.
#
#   THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL
#   WARRANTIES WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED
#   WARRANTIES OF MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE
#   AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL
#   DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR
#   PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER
#   TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR
#   PERFORMANCE OF THIS SOFTWARE.
#
#   Feather (MIT): Copyright (c) 2013-2022 Cole Bemis. Permission is
#   hereby granted, free of charge, to any person obtaining a copy of this
#   software to deal in it without restriction, subject to including this
#   notice; it is provided "as is", without warranty of any kind.

# one path of an icon: stroked, or filled (even-odd)
type Layer is Data:
  Layer{d: String, fill: Bool}

type IDef is Data:
  IDef{name: String, layers: List<&2, Layer>}

def Icon.s(d: String) -> Layer:
  Layer{d, False{}}

def Icon.all() -> List<&2, IDef>:
  [IDef{"plus", [Icon.s("M5 12h14"), Icon.s("M12 5v14")]},
   IDef{"x", [Icon.s("M18 6 6 18"), Icon.s("m6 6 12 12")]},
   IDef{"chevron-down", [Icon.s("m6 9 6 6 6-6")]},
   IDef{"chevron-right", [Icon.s("m9 18 6-6-6-6")]},
   IDef{"settings", [Icon.s("M12.22 2h-.44a2 2 0 0 0-2 2v.18a2 2 0 0 1-1 1.73l-.43.25a2 2 0 0 1-2 0l-.15-.08a2 2 0 0 0-2.73.73l-.22.38a2 2 0 0 0 .73 2.73l.15.1a2 2 0 0 1 1 1.72v.51a2 2 0 0 1-1 1.74l-.15.09a2 2 0 0 0-.73 2.73l.22.38a2 2 0 0 0 2.73.73l.15-.08a2 2 0 0 1 2 0l.43.25a2 2 0 0 1 1 1.73V20a2 2 0 0 0 2 2h.44a2 2 0 0 0 2-2v-.18a2 2 0 0 1 1-1.73l.43-.25a2 2 0 0 1 2 0l.15.08a2 2 0 0 0 2.73-.73l.22-.39a2 2 0 0 0-.73-2.73l-.15-.08a2 2 0 0 1-1-1.74v-.5a2 2 0 0 1 1-1.74l.15-.09a2 2 0 0 0 .73-2.73l-.22-.38a2 2 0 0 0-2.73-.73l-.15.08a2 2 0 0 1-2 0l-.43-.25a2 2 0 0 1-1-1.73V4a2 2 0 0 0-2-2z"),
     Icon.s("M9 12a3 3 0 1 0 6 0a3 3 0 1 0-6 0")]},
   IDef{"paperclip", [Icon.s("m21.44 11.05-9.19 9.19a6 6 0 0 1-8.49-8.49l8.57-8.57A4 4 0 1 1 18 8.84l-8.59 8.57a2 2 0 0 1-2.83-2.83l8.49-8.48")]},
   IDef{"arrow-up", [Icon.s("m5 12 7-7 7 7"), Icon.s("M12 19V5")]},
   IDef{"send", [Icon.s("M14.536 21.686a.5.5 0 0 0 .937-.024l6.5-19a.496.496 0 0 0-.635-.635l-19 6.5a.5.5 0 0 0-.024.937l7.93 3.18a2 2 0 0 1 1.112 1.11z"), Icon.s("m21.854 2.147-10.94 10.939")]},
   IDef{"stop", [Layer{"M6 6h12v12H6z", True{}}]},
   IDef{"terminal", [Icon.s("m4 17 6-6-6-6"), Icon.s("M12 19h8")]},
   IDef{"git-branch", [Icon.s("M6 3v12"), Icon.s("M15 6a3 3 0 1 0 6 0a3 3 0 1 0-6 0"), Icon.s("M3 18a3 3 0 1 0 6 0a3 3 0 1 0-6 0"), Icon.s("M18 9a9 9 0 0 1-9 9")]},
   IDef{"panel-right", [Icon.s("M3 3h18v18H3z"), Icon.s("M15 3v18")]},
   IDef{"link", [Icon.s("M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71"), Icon.s("M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71")]},
   IDef{"external-link", [Icon.s("M15 3h6v6"), Icon.s("M10 14 21 3"), Icon.s("M18 13v8H3V6h8")]},
   IDef{"zoom-in", [Icon.s("M3 11a8 8 0 1 0 16 0a8 8 0 1 0-16 0"), Icon.s("m21 21-4.35-4.35"), Icon.s("M11 8v6"), Icon.s("M8 11h6")]},
   IDef{"zoom-out", [Icon.s("M3 11a8 8 0 1 0 16 0a8 8 0 1 0-16 0"), Icon.s("m21 21-4.35-4.35"), Icon.s("M8 11h6")]},
   IDef{"maximize", [Icon.s("M15 3h6v6"), Icon.s("M9 21H3v-6"), Icon.s("m21 3-7 7"), Icon.s("m3 21 7-7")]},
   IDef{"circuit-board", [Icon.s("M3 3h18v18H3z"), Icon.s("M11 9h4a2 2 0 0 0 2-2V3"), Icon.s("M7 9a2 2 0 1 0 4 0a2 2 0 1 0-4 0"), Icon.s("M7 21v-4a2 2 0 0 1 2-2h4"), Icon.s("M13 15a2 2 0 1 0 4 0a2 2 0 1 0-4 0")]},
   IDef{"box", [Icon.s("M21 8a2 2 0 0 0-1-1.73l-7-4a2 2 0 0 0-2 0l-7 4A2 2 0 0 0 3 8v8a2 2 0 0 0 1 1.73l7 4a2 2 0 0 0 2 0l7-4A2 2 0 0 0 21 16Z"), Icon.s("m3.3 7 8.7 5 8.7-5"), Icon.s("M12 22V12")]},
   IDef{"diff", [Icon.s("M12 3v14"), Icon.s("M5 10h14"), Icon.s("M5 21h14")]},
   IDef{"copy", [Icon.s("M8 8h14v14H8z"), Icon.s("M4 16c-1.1 0-2-.9-2-2V4c0-1.1.9-2 2-2h10c1.1 0 2 .9 2 2")]},
   IDef{"folder-plus", [Icon.s("M12 10v6"), Icon.s("M9 13h6"), Icon.s("M20 20a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-7.9a2 2 0 0 1-1.69-.9L9.6 3.9A2 2 0 0 0 7.93 3H4a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2Z")]}]

def Icon.pick(hit: Bool, ls: List<&2, Layer>, found: List<&2, Layer>) -> List<&2, Layer>:
  match hit:
    case True{}:
      ls
    case False{}:
      found

def Icon.find(ds: List<&2, IDef>, +name: String, found: List<&2, Layer>) -> List<&2, Layer>:
  match ds:
    case Nil{}:
      found
    case IDef{+n, ls} <> t:
      Icon.find(t, name, Icon.pick(String.eq(n, name), ls, found))

# an icon's layers (none for a name not in the set)
def Icon.layers(+name: String) -> List<&2, Layer>:
  Icon.find(Icon.all(), name, Nil{})

def Icon.names.go(ds: List<&2, IDef>) -> List<&2, String>:
  match ds:
    case Nil{}:
      Nil{}
    case IDef{n, _} <> t:
      n <> Icon.names.go(t)

def Icon.names() -> List<&2, String>:
  Icon.names.go(Icon.all())

# the icons the two UIs draw (laws icons_*: each is in the set)
def Icon.used() -> List<&2, String>:
  ["plus", "x", "chevron-down", "chevron-right", "settings", "paperclip", "arrow-up", "stop"]

def Icon.missing.k(none: Bool, +n: String, rest: List<&2, String>) -> List<&2, String>:
  match none:
    case True{}:
      n <> rest
    case False{}:
      rest

# the names that have no icon
def Icon.missing(ns: List<&2, String>) -> List<&2, String>:
  match ns:
    case Nil{}:
      Nil{}
    case +n <> t:
      Icon.missing.k(List.is_empty(&2, Layer, Icon.layers(n)), n, Icon.missing(t))

def Icon.starts(ss: List<&2, S.Seg>) -> Bool:
  match ss:
    case S.SM{_, _} <> _:
      True{}
    case _:
      False{}

# some layer's path does not begin with a moveto (or is empty)
def Icon.lost(ls: List<&2, Layer>) -> Bool:
  match ls:
    case Nil{}:
      False{}
    case Layer{d, _} <> t:
      Bool.or(Bool.not(Icon.starts(S.Svg.parse(d))), Icon.lost(t))

# the icons with a path that draws nothing (law icons_all_draw)
def Icon.bad(ds: List<&2, IDef>) -> List<&2, String>:
  match ds:
    case Nil{}:
      Nil{}
    case IDef{+n, ls} <> t:
      Icon.missing.k(Icon.lost(ls), n, Icon.bad(t))
