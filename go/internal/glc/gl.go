// Package glc is a minimal OpenGL 2.1 binding, hand-written for this demo.
// The whole point of the piece is software rendering: the CPU computes every
// pixel, and the GPU is used for exactly one thing — blitting the finished
// framebuffer onto the screen as a fullscreen textured quad.
package glc

/*
#cgo darwin LDFLAGS: -framework OpenGL
#define GL_SILENCE_DEPRECATION
#include <OpenGL/gl.h>
*/
import "C"

import "unsafe"

type GLenum = C.GLenum
type GLint = C.GLint
type GLsizei = C.GLsizei
type GLfloat = C.GLfloat
type GLuint = C.GLuint

const (
	Texture2D    = C.GL_TEXTURE_2D
	Rgba         = C.GL_RGBA
	UnsignedByte = C.GL_UNSIGNED_BYTE
	Nearest      = C.GL_NEAREST
	Linear       = C.GL_LINEAR
	TextureMin   = C.GL_TEXTURE_MIN_FILTER
	TextureMag   = C.GL_TEXTURE_MAG_FILTER
	TextureWrapS = C.GL_TEXTURE_WRAP_S
	TextureWrapT = C.GL_TEXTURE_WRAP_T
	ClampToEdge  = C.GL_CLAMP_TO_EDGE

	ColorBufferBit = C.GL_COLOR_BUFFER_BIT
	Projection     = C.GL_PROJECTION
	ModelView      = C.GL_MODELVIEW
	Quads          = C.GL_QUADS

	Blend        = C.GL_BLEND
	SrcAlpha     = C.GL_SRC_ALPHA
	OneMinusSrca = C.GL_ONE_MINUS_SRC_ALPHA

	TextureEnv      = C.GL_TEXTURE_ENV
	TextureEnvMode  = C.GL_TEXTURE_ENV_MODE
	Modulate        = C.GL_MODULATE
	UnpackAlignment = C.GL_UNPACK_ALIGNMENT
	UnpackRowLength = C.GL_UNPACK_ROW_LENGTH
)

func Viewport(x, y, w, h int) { C.glViewport(C.GLint(x), C.GLint(y), C.GLsizei(w), C.GLsizei(h)) }

func ClearColor(r, g, b, a float32) {
	C.glClearColor(C.GLclampf(r), C.GLclampf(g), C.GLclampf(b), C.GLclampf(a))
}

func Clear(mask GLenum) { C.glClear(C.GLbitfield(mask)) }

func Enable(c GLenum)  { C.glEnable(c) }
func Disable(c GLenum) { C.glDisable(c) }

func GenTexture() uint32 {
	var id C.GLuint
	C.glGenTextures(1, &id)
	return uint32(id)
}

func BindTexture(target GLenum, id uint32) { C.glBindTexture(target, C.GLuint(id)) }

func TexParameteri(target, pname GLenum, param int32) {
	C.glTexParameteri(target, pname, C.GLint(param))
}

func PixelStorei(pname GLenum, param int32) {
	C.glPixelStorei(pname, C.GLint(param))
}

// TexImage2D allocates the storage for a w*h RGBA texture.
func TexImage2D(target GLenum, level int32, internal int32, w, h int32, format, typ GLenum) {
	C.glTexImage2D(target, C.GLint(level), C.GLint(internal),
		C.GLsizei(w), C.GLsizei(h), 0, format, typ, nil)
}

// TexSubImage2D uploads a w*h RGBA8 buffer into the current texture.
func TexSubImage2D(target GLenum, level int32, x, y, w, h int32, format, typ GLenum, pixels unsafe.Pointer) {
	C.glTexSubImage2D(target, C.GLint(level), C.GLint(x), C.GLint(y),
		C.GLsizei(w), C.GLsizei(h), format, typ, pixels)
}

func MatrixMode(mode GLenum) { C.glMatrixMode(mode) }
func LoadIdentity()          { C.glLoadIdentity() }

func Ortho(left, right, bottom, top, near, far float64) {
	C.glOrtho(C.GLdouble(left), C.GLdouble(right), C.GLdouble(bottom),
		C.GLdouble(top), C.GLdouble(near), C.GLdouble(far))
}

func Color4f(r, g, b, a float32) {
	C.glColor4f(C.GLfloat(r), C.GLfloat(g), C.GLfloat(b), C.GLfloat(a))
}

func Begin(mode GLenum) { C.glBegin(mode) }
func End()              { C.glEnd() }

func TexCoord2f(s, t float32) { C.glTexCoord2f(C.GLfloat(s), C.GLfloat(t)) }
func Vertex2f(x, y float32)   { C.glVertex2f(C.GLfloat(x), C.GLfloat(y)) }
func Vertex2i(x, y int32)     { C.glVertex2i(C.GLint(x), C.GLint(y)) }

// DrawFullscreenRGBA blits an RGBA8 buffer (w*h*4 bytes) over the whole
// viewport. The texture upload is the only per-frame GPU traffic.
func DrawFullscreenRGBA(tex uint32, w, h int, pixels unsafe.Pointer) {
	PixelStorei(UnpackAlignment, 4)
	PixelStorei(UnpackRowLength, 0)
	BindTexture(Texture2D, tex)
	TexSubImage2D(Texture2D, 0, 0, 0, int32(w), int32(h), Rgba, UnsignedByte, pixels)

	MatrixMode(ModelView)
	LoadIdentity()
	Enable(Texture2D)
	Color4f(1, 1, 1, 1)
	Begin(Quads)
	TexCoord2f(0, 0)
	Vertex2f(-1, 1)
	TexCoord2f(1, 0)
	Vertex2f(1, 1)
	TexCoord2f(1, 1)
	Vertex2f(1, -1)
	TexCoord2f(0, 1)
	Vertex2f(-1, -1)
	End()
	Disable(Texture2D)
}

// InitBlitState configures the projection and a neareast-filtered texture
// object ready for DrawFullscreenRGBA.
func InitBlitState(w, h int) uint32 {
	tex := GenTexture()
	BindTexture(Texture2D, tex)
	TexParameteri(Texture2D, TextureMin, int32(Nearest))
	TexParameteri(Texture2D, TextureMag, int32(Nearest))
	TexParameteri(Texture2D, TextureWrapS, int32(ClampToEdge))
	TexParameteri(Texture2D, TextureWrapT, int32(ClampToEdge))
	TexImage2D(Texture2D, 0, C.GL_RGBA8, int32(w), int32(h), Rgba, UnsignedByte)

	C.glTexEnvi(TextureEnv, TextureEnvMode, C.GLint(Modulate))

	MatrixMode(Projection)
	LoadIdentity()
	// the quad in DrawFullscreenRGBA is drawn in clip space (-1..1), so the
	// projection has to be the identity-ish mapping, not 0..1: with 0..1 the
	// window showed one quarter of the frame stretched over the whole screen
	Ortho(-1, 1, -1, 1, -1, 1)
	MatrixMode(ModelView)
	LoadIdentity()
	return tex
}
