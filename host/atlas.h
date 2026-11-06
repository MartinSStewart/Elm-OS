/* The texture atlas that every triangle samples (see elm/src/Sprite.elm).
 *
 * 256 x 256 pixels, one byte each: how much of the pixel is covered, 0 to 255.
 * A triangle's colour is multiplied by it, so the atlas only holds shapes:
 *
 *   x 0-250, y 0-180     town-collab's 10 x 18 pixel font, 25 glyphs to a row
 *   x 0-12, y 184-203    the mouse cursor's outline (12 x 19, tip at the top left)
 *   x 16-28, y 184-203   the mouse cursor's fill; Elm draws the two in different colours
 *   x 248-256, y 248-256 solid, for flat colours
 *
 * Both renderers build it the same way: /init for the CPU, elmos-gpu for the GPU.
 */
#include <string.h>

#include "font.h"

#define ATLAS_SIZE 256

#define CURSOR_W 12
#define CURSOR_H 19
#define CURSOR_Y 184
#define CURSOR_FILL_X 16

/* X: outline, o: fill. */
static const char* const cursor[CURSOR_H] = {
    "X           ",
    "XX          ",
    "XoX         ",
    "XooX        ",
    "XoooX       ",
    "XooooX      ",
    "XoooooX     ",
    "XooooooX    ",
    "XoooooooX   ",
    "XooooooooX  ",
    "XoooooooooX ",
    "XooooooXXXXX",
    "XoooXooX    ",
    "XooXXooX    ",
    "XoX  XooX   ",
    "XX   XooX   ",
    "X     XooX  ",
    "      XooX  ",
    "       XX   ",
};

static void atlas_build(unsigned char* a) {
    memset(a, 0, ATLAS_SIZE * ATLAS_SIZE);
    for (int y = 0; y < FONT_H; y++)
        for (int x = 0; x < FONT_W; x++)
            if (font_bits[y * FONT_STRIDE + x / 8] & (0x80 >> (x % 8))) a[y * ATLAS_SIZE + x] = 255;
    for (int y = 0; y < CURSOR_H; y++)
        for (int x = 0; x < CURSOR_W; x++) {
            if (cursor[y][x] == 'X') a[(CURSOR_Y + y) * ATLAS_SIZE + x] = 255;
            if (cursor[y][x] == 'o') a[(CURSOR_Y + y) * ATLAS_SIZE + CURSOR_FILL_X + x] = 255;
        }
    for (int y = 248; y < ATLAS_SIZE; y++) memset(a + y * ATLAS_SIZE + 248, 255, ATLAS_SIZE - 248);
}

/* One triangle as /init hands it to a renderer: the 13 numbers Elm sends per triangle,
 * x, y, u, v for each corner (screen and atlas pixels), then the colour as 0xRRGGBBAA. */
typedef struct {
    float p[3][4];
    unsigned int rgba;
} Tri;
