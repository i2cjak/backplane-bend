// Backplane fonts (FreeType + fontconfig)
// =======================================
//
// System fonts, anti-aliased. Both libraries are opened at run time
// (dlopen), so the binary links neither and needs no headers: the few
// FreeType structs we read are declared below with the public 2.x layout
// (stable since 2.0; checked against FreeType 2.14's headers with
// offsetof). A machine without libfreetype.so.6 gets ENOTSUP from
// Font.open and the app keeps its bitmap font.
//
// Everything crosses as Base types (strings, U32, lists of U32 words);
// src/gfx/text.bend decodes them.
//
//   Font.find(pattern)        fontconfig match: (family, (file, index))
//   Font.open(path, index, px) a face id (small integer)
//   Font.metrics(face)        [ascender, descender, height, max advance]
//                             in 26.6 pixels (descender as a magnitude)
//   Font.glyph(face, cp)      [found, advance, left + 32768, top + 32768,
//                             w, h, coverage...] advance in 26.6; coverage
//                             is w*h bytes row-major, four per word, first
//                             pixel in the low byte; [] on error
//   Font.kern(face, a, b)     kerning between two code points, 26.6,
//                             biased by 32768

#include <dlfcn.h>
#include <stdint.h>

#define FX_BIAS 32768

typedef struct { long x, y; } FxVector;
typedef struct { long xMin, yMin, xMax, yMax; } FxBBox;
typedef struct { void* data; void (*finalizer)(void*); } FxGeneric;

typedef struct {
  long width, height, horiBearingX, horiBearingY, horiAdvance;
  long vertBearingX, vertBearingY, vertAdvance;
} FxGlyphMetrics;

typedef struct {
  unsigned int   rows;
  unsigned int   width;
  int            pitch;
  unsigned char* buffer;
  unsigned short num_grays;
  unsigned char  pixel_mode;
  unsigned char  palette_mode;
  void*          palette;
} FxBitmap;

typedef struct {
  unsigned short x_ppem, y_ppem;
  long           x_scale, y_scale;
  long           ascender, descender, height, max_advance;
} FxSizeMetrics;

typedef struct {
  void*         face;
  FxGeneric     generic;
  FxSizeMetrics metrics;
} FxSize;

// the prefix of FT_GlyphSlotRec we read
typedef struct {
  void*          library;
  void*          face;
  void*          next;
  unsigned int   glyph_index;
  FxGeneric      generic;
  FxGlyphMetrics metrics;
  long           linearHoriAdvance;
  long           linearVertAdvance;
  FxVector       advance;
  int            format;
  FxBitmap       bitmap;
  int            bitmap_left;
  int            bitmap_top;
} FxSlot;

// the prefix of FT_FaceRec we read
typedef struct {
  long           num_faces, face_index, face_flags, style_flags, num_glyphs;
  char*          family_name;
  char*          style_name;
  int            num_fixed_sizes;
  void*          available_sizes;
  int            num_charmaps;
  void*          charmaps;
  FxGeneric      generic;
  FxBBox         bbox;
  unsigned short units_per_EM;
  short          ascender, descender, height;
  short          max_advance_width, max_advance_height;
  short          underline_position, underline_thickness;
  FxSlot*        glyph;
  FxSize*        size;
  void*          charmap;
} FxFace;

#define FX_LOAD_NO_BITMAP     0x8
#define FX_LOAD_TARGET_LIGHT  0x10000
#define FX_RENDER_MODE_NORMAL 0
#define FX_PIXEL_MODE_GRAY    2
#define FX_KERNING_DEFAULT    0

#define FX_FT_FNS(X) \
  X(FT_Init_FreeType, int, (void**)) \
  X(FT_New_Face, int, (void*, const char*, long, FxFace**)) \
  X(FT_Set_Pixel_Sizes, int, (FxFace*, unsigned, unsigned)) \
  X(FT_Get_Char_Index, unsigned, (FxFace*, unsigned long)) \
  X(FT_Load_Glyph, int, (FxFace*, unsigned, int32_t)) \
  X(FT_Render_Glyph, int, (FxSlot*, int)) \
  X(FT_Get_Kerning, int, (FxFace*, unsigned, unsigned, unsigned, FxVector*))

#define FX_FC_FNS(X) \
  X(FcInitLoadConfigAndFonts, void*, (void)) \
  X(FcNameParse, void*, (const unsigned char*)) \
  X(FcConfigSubstitute, int, (void*, void*, int)) \
  X(FcDefaultSubstitute, void, (void*)) \
  X(FcFontMatch, void*, (void*, void*, int*)) \
  X(FcPatternGetString, int, (void*, const char*, int, unsigned char**)) \
  X(FcPatternGetInteger, int, (void*, const char*, int, int*)) \
  X(FcPatternDestroy, void, (void*))

#define FX_PTR(name, ret, args) static __attribute__((unused)) ret (*fx_##name) args;
FX_FT_FNS(FX_PTR)
FX_FC_FNS(FX_PTR)

#define FX_SYM(name, ret, args) \
  if ((fx_##name = (ret (*) args)dlsym(lib, #name)) == NULL) { return 0; }

static void*   fx_lib = NULL;
static FxFace* fx_faces[256];
static u32     fx_nfaces = 0;

// FreeType, loaded and initialised once
static __attribute__((unused)) int fx_ft_load(void) {
  static int state = 0;
  if (state != 0) {
    return state > 0;
  }
  state = -1;
  void* lib = dlopen("libfreetype.so.6", RTLD_NOW | RTLD_LOCAL);
  if (lib == NULL) {
    return 0;
  }
  FX_FT_FNS(FX_SYM)
  if (fx_FT_Init_FreeType(&fx_lib) != 0) {
    return 0;
  }
  state = 1;
  return 1;
}

static __attribute__((unused)) void* fx_fc_load(void) {
  static int state = 0;
  static void* config = NULL;
  if (state != 0) {
    return state > 0 ? config : NULL;
  }
  state = -1;
  void* lib = dlopen("libfontconfig.so.1", RTLD_NOW | RTLD_LOCAL);
  if (lib == NULL) {
    return NULL;
  }
  FX_FC_FNS(FX_SYM)
  config = fx_FcInitLoadConfigAndFonts();
  if (config == NULL) {
    return NULL;
  }
  state = 1;
  return config;
}

static __attribute__((unused)) FxFace* fx_face(u32 id) {
  return id < fx_nfaces ? fx_faces[id] : NULL;
}

// the n words as a Bend List<U32>
static __attribute__((unused)) Term fx_list(Env e, const u32* ws, u64 n) {
  Term xs = term_pak(CID_NIL, 0);
  for (u64 i = n; i > 0; i -= 1) {
    xs = io_node(e, CID_CON, (Term)ws[i - 1], xs);
  }
  return xs;
}

#ifdef CID_FONT_FIND

// the best system font for a fontconfig pattern ("DejaVu Sans Mono",
// "monospace:weight=bold"): (family, (file, index))
Term font_find_run(Env e, Term* f, IoWork* w) {
  u64 n = 0;
  char* pat = io_cstr(e, f[0], &n);
  void* config = fx_fc_load();
  if (config == NULL) {
    free(pat);
    return io_fail(e, ENOTSUP, "fontconfig (libfontconfig.so.1) is not available");
  }
  void* p = fx_FcNameParse((const unsigned char*)pat);
  free(pat);
  if (p == NULL) {
    return io_fail(e, EINVAL, "bad font pattern");
  }
  fx_FcConfigSubstitute(config, p, 0);
  fx_FcDefaultSubstitute(p);
  int res = 0;
  void* m = fx_FcFontMatch(config, p, &res);
  fx_FcPatternDestroy(p);
  unsigned char* file = NULL;
  unsigned char* family = NULL;
  int index = 0;
  if (m == NULL || fx_FcPatternGetString(m, "file", 0, &file) != 0 || file == NULL) {
    if (m) {
      fx_FcPatternDestroy(m);
    }
    return io_fail(e, ENOENT, "no font matches");
  }
  if (fx_FcPatternGetString(m, "family", 0, &family) != 0 || family == NULL) {
    family = (unsigned char*)"";
  }
  fx_FcPatternGetInteger(m, "index", 0, &index);
  Term r = io_tup(e, io_str(e, (char*)family, strlen((char*)family)),
    io_tup(e, io_str(e, (char*)file, strlen((char*)file)), (Term)(u32)index));
  fx_FcPatternDestroy(m);
  return io_done(e, r);
}

static void __attribute__((constructor)) font_find_use(void) {
  io_eff(CID_FONT_FIND, font_find_run, 0);
}

#endif

#ifdef CID_FONT_OPEN

// a face of the font file at px pixels per em
Term font_open_run(Env e, Term* f, IoWork* w) {
  u64 n = 0;
  char* path = io_cstr(e, f[0], &n);
  long index = (long)(u32)f[1];
  u32 px = (u32)f[2];
  if (!fx_ft_load()) {
    free(path);
    return io_fail(e, ENOTSUP, "FreeType (libfreetype.so.6) is not available");
  }
  if (fx_nfaces >= 256) {
    free(path);
    return io_fail(e, EMFILE, "too many font faces");
  }
  FxFace* face = NULL;
  int err = fx_FT_New_Face(fx_lib, path, index, &face);
  free(path);
  if (err != 0 || face == NULL) {
    return io_fail(e, ENOENT, "FreeType cannot open the font");
  }
  if (fx_FT_Set_Pixel_Sizes(face, 0, px ? px : 13) != 0) {
    return io_fail(e, EINVAL, "FreeType cannot size the font");
  }
  fx_faces[fx_nfaces] = face;
  fx_nfaces += 1;
  return io_done(e, (Term)(fx_nfaces - 1));
}

static void __attribute__((constructor)) font_open_use(void) {
  io_eff(CID_FONT_OPEN, font_open_run, 0);
}

#endif

#ifdef CID_FONT_METRICS

Term font_metrics_run(Env e, Term* f, IoWork* w) {
  FxFace* face = fx_face((u32)f[0]);
  if (face == NULL) {
    return fx_list(e, NULL, 0);
  }
  FxSizeMetrics* m = &face->size->metrics;
  long desc = m->descender < 0 ? -m->descender : m->descender;
  u32 ws[4] = { (u32)m->ascender, (u32)desc, (u32)m->height, (u32)m->max_advance };
  return fx_list(e, ws, 4);
}

static void __attribute__((constructor)) font_metrics_use(void) {
  io_eff(CID_FONT_METRICS, font_metrics_run, 0);
}

#endif

#ifdef CID_FONT_GLYPH

// FreeType's coverage is linear, and the rasterizer blends in sRGB, so
// light text on a dark ground comes out thin. Browsers correct for it
// (Skia's contrast / gamma hack); this lifts mid coverage the same way,
// about a 1.3 gamma, leaving 0 and 255 alone.
static u32 fx_boost(u32 c) {
  return c + c * (255 - c) * 3 / 2550;
}

// one glyph, hinted lightly (vertical only, like browsers on Linux) and
// rendered as 8-bit grayscale coverage
Term font_glyph_run(Env e, Term* f, IoWork* w) {
  FxFace* face = fx_face((u32)f[0]);
  u32 cp = (u32)f[1];
  if (face == NULL) {
    return fx_list(e, NULL, 0);
  }
  unsigned gi = fx_FT_Get_Char_Index(face, cp);
  if (fx_FT_Load_Glyph(face, gi, FX_LOAD_TARGET_LIGHT | FX_LOAD_NO_BITMAP) != 0
    || fx_FT_Render_Glyph(face->glyph, FX_RENDER_MODE_NORMAL) != 0) {
    return fx_list(e, NULL, 0);
  }
  FxSlot* s = face->glyph;
  FxBitmap* b = &s->bitmap;
  u32 bw = b->pixel_mode == FX_PIXEL_MODE_GRAY ? b->width : 0;
  u32 bh = b->pixel_mode == FX_PIXEL_MODE_GRAY ? b->rows : 0;
  u64 nb = (u64)bw * bh;
  u64 nw = 6 + (nb + 3) / 4;
  u32* ws = io_mem(calloc(nw, 4));
  ws[0] = gi != 0;
  ws[1] = (u32)s->advance.x;
  ws[2] = (u32)(s->bitmap_left + FX_BIAS);
  ws[3] = (u32)(s->bitmap_top + FX_BIAS);
  ws[4] = bw;
  ws[5] = bh;
  u64 k = 0;
  for (u32 y = 0; y < bh; y += 1) {
    const unsigned char* row = b->buffer + (long)y * b->pitch;
    for (u32 x = 0; x < bw; x += 1) {
      ws[6 + k / 4] |= fx_boost(row[x]) << ((k % 4) * 8);
      k += 1;
    }
  }
  Term r = fx_list(e, ws, nw);
  free(ws);
  return r;
}

static void __attribute__((constructor)) font_glyph_use(void) {
  io_eff(CID_FONT_GLYPH, font_glyph_run, 0);
}

#endif

#ifdef CID_FONT_KERN

Term font_kern_run(Env e, Term* f, IoWork* w) {
  FxFace* face = fx_face((u32)f[0]);
  FxVector k = { 0, 0 };
  if (face != NULL) {
    unsigned a = fx_FT_Get_Char_Index(face, (u32)f[1]);
    unsigned b = fx_FT_Get_Char_Index(face, (u32)f[2]);
    if (fx_FT_Get_Kerning(face, a, b, FX_KERNING_DEFAULT, &k) != 0) {
      k.x = 0;
    }
  }
  return (Term)(u32)(k.x + FX_BIAS);
}

static void __attribute__((constructor)) font_kern_use(void) {
  io_eff(CID_FONT_KERN, font_kern_run, 0);
}

#endif
