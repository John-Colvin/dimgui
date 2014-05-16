/*
 * Copyright (c) 2009-2010 Mikko Mononen memon@inside.org
 *
 * This software is provided 'as-is', without any express or implied
 * warranty.  In no event will the authors be held liable for any damages
 * arising from the use of this software.
 * Permission is granted to anyone to use this software for any purpose,
 * including commercial applications, and to alter it and redistribute it
 * freely, subject to the following restrictions:
 * 1. The origin of this software must not be misrepresented; you must not
 *    claim that you wrote the original software. If you use this software
 *    in a product, an acknowledgment in the product documentation would be
 *    appreciated but is not required.
 * 2. Altered source versions must be plainly marked as such, and must not be
 *    misrepresented as being the original software.
 * 3. This notice may not be removed or altered from any source distribution.
 */
module imgui.gui;

import std.math;
import std.stdio;
import std.string;

import imgui.gl3_renderer;

/** Globals start. */

__gshared imguiGfxCmd[GFXCMD_QUEUE_SIZE] g_gfxCmdQueue;
__gshared uint g_gfxCmdQueueSize = 0;
__gshared int  g_scrollTop        = 0;
__gshared int  g_scrollBottom     = 0;
__gshared int  g_scrollRight      = 0;
__gshared int  g_scrollAreaTop    = 0;
__gshared int* g_scrollVal        = null;
__gshared int  g_focusTop         = 0;
__gshared int  g_focusBottom      = 0;
__gshared uint g_scrollId = 0;
__gshared bool g_insideScrollArea = false;
__gshared GuiState g_state;

/** Globals end. */

enum GFXCMD_QUEUE_SIZE   = 5000;
enum BUTTON_HEIGHT       = 20;
enum SLIDER_HEIGHT       = 20;
enum SLIDER_MARKER_WIDTH = 10;
enum CHECK_SIZE          = 8;
enum DEFAULT_SPACING     = 4;
enum TEXT_HEIGHT         = 8;
enum SCROLL_AREA_PADDING = 6;
enum INDENT_SIZE         = 16;
enum AREA_HEADER         = 28;

alias imguiMouseButton = int;
enum : imguiMouseButton
{
    IMGUI_MBUT_LEFT  = 0x01,
    IMGUI_MBUT_RIGHT = 0x02,
}

alias imguiTextAlign = int;
enum : imguiTextAlign
{
    IMGUI_ALIGN_LEFT,
    IMGUI_ALIGN_CENTER,
    IMGUI_ALIGN_RIGHT,
}

// Pull render interface.
alias imguiGfxCmdType = int;
enum : imguiGfxCmdType
{
    IMGUI_GFXCMD_RECT,
    IMGUI_GFXCMD_TRIANGLE,
    IMGUI_GFXCMD_LINE,
    IMGUI_GFXCMD_TEXT,
    IMGUI_GFXCMD_SCISSOR,
}

uint imguiRGBA(ubyte r, ubyte g, ubyte b, ubyte a = 255)
{
    return (r) | (g << 8) | (b << 16) | (a << 24);
}

struct imguiGfxRect
{
    short x, y, w, h, r;
}

struct imguiGfxText
{
    short x, y, align_;
    string text;
}

struct imguiGfxLine
{
    short x0, y0, x1, y1, r;
}

struct imguiGfxCmd
{
    char type;
    char flags;
    byte[2] pad;
    uint col;

    union
    {
        imguiGfxLine line;
        imguiGfxRect rect;
        imguiGfxText text;
    }
}

void resetGfxCmdQueue()
{
    g_gfxCmdQueueSize = 0;
}

void addGfxCmdScissor(int x, int y, int w, int h)
{
    if (g_gfxCmdQueueSize >= GFXCMD_QUEUE_SIZE)
        return;
    auto cmd = &g_gfxCmdQueue[g_gfxCmdQueueSize++];
    cmd.type   = IMGUI_GFXCMD_SCISSOR;
    cmd.flags  = x < 0 ? 0 : 1;         // on/off flag.
    cmd.col    = 0;
    cmd.rect.x = cast(short)x;
    cmd.rect.y = cast(short)y;
    cmd.rect.w = cast(short)w;
    cmd.rect.h = cast(short)h;
}

void addGfxCmdRect(float x, float y, float w, float h, uint color)
{
    if (g_gfxCmdQueueSize >= GFXCMD_QUEUE_SIZE)
        return;
    auto cmd = &g_gfxCmdQueue[g_gfxCmdQueueSize++];
    cmd.type   = IMGUI_GFXCMD_RECT;
    cmd.flags  = 0;
    cmd.col    = color;
    cmd.rect.x = cast(short)(x * 8.0f);
    cmd.rect.y = cast(short)(y * 8.0f);
    cmd.rect.w = cast(short)(w * 8.0f);
    cmd.rect.h = cast(short)(h * 8.0f);
    cmd.rect.r = 0;
}

void addGfxCmdLine(float x0, float y0, float x1, float y1, float r, uint color)
{
    if (g_gfxCmdQueueSize >= GFXCMD_QUEUE_SIZE)
        return;
    auto cmd = &g_gfxCmdQueue[g_gfxCmdQueueSize++];
    cmd.type    = IMGUI_GFXCMD_LINE;
    cmd.flags   = 0;
    cmd.col     = color;
    cmd.line.x0 = cast(short)(x0 * 8.0f);
    cmd.line.y0 = cast(short)(y0 * 8.0f);
    cmd.line.x1 = cast(short)(x1 * 8.0f);
    cmd.line.y1 = cast(short)(y1 * 8.0f);
    cmd.line.r  = cast(short)(r * 8.0f);
}

void addGfxCmdRoundedRect(float x, float y, float w, float h, float r, uint color)
{
    if (g_gfxCmdQueueSize >= GFXCMD_QUEUE_SIZE)
        return;
    auto cmd = &g_gfxCmdQueue[g_gfxCmdQueueSize++];
    cmd.type   = IMGUI_GFXCMD_RECT;
    cmd.flags  = 0;
    cmd.col    = color;
    cmd.rect.x = cast(short)(x * 8.0f);
    cmd.rect.y = cast(short)(y * 8.0f);
    cmd.rect.w = cast(short)(w * 8.0f);
    cmd.rect.h = cast(short)(h * 8.0f);
    cmd.rect.r = cast(short)(r * 8.0f);
}

void addGfxCmdTriangle(int x, int y, int w, int h, int flags, uint color)
{
    if (g_gfxCmdQueueSize >= GFXCMD_QUEUE_SIZE)
        return;
    auto cmd = &g_gfxCmdQueue[g_gfxCmdQueueSize++];
    cmd.type   = IMGUI_GFXCMD_TRIANGLE;
    cmd.flags  = cast(byte)flags;
    cmd.col    = color;
    cmd.rect.x = cast(short)(x * 8.0f);
    cmd.rect.y = cast(short)(y * 8.0f);
    cmd.rect.w = cast(short)(w * 8.0f);
    cmd.rect.h = cast(short)(h * 8.0f);
}

void addGfxCmdText(int x, int y, int align_, string text, uint color)
{
    if (g_gfxCmdQueueSize >= GFXCMD_QUEUE_SIZE)
        return;
    auto cmd = &g_gfxCmdQueue[g_gfxCmdQueueSize++];
    cmd.type       = IMGUI_GFXCMD_TEXT;
    cmd.flags      = 0;
    cmd.col        = color;
    cmd.text.x     = cast(short)x;
    cmd.text.y     = cast(short)y;
    cmd.text.align_ = cast(short)align_;
    cmd.text.text  = text;
}

struct GuiState
{
    bool left;
    bool leftPressed, leftReleased;
    int mx = -1, my = -1;
    int scroll;
    uint active;
    uint hot;
    uint hotToBe;
    bool isHot;
    bool isActive;
    bool wentActive;
    int dragX, dragY;
    float dragOrig;
    int widgetX, widgetY, widgetW = 100;
    bool insideCurrentScroll;

    uint areaId;
    uint widgetId;
}

bool anyActive()
{
    return g_state.active != 0;
}

bool isActive(uint id)
{
    return g_state.active == id;
}

bool isHot(uint id)
{
    return g_state.hot == id;
}

bool inRect(int x, int y, int w, int h, bool checkScroll = true)
{
    return (!checkScroll || g_state.insideCurrentScroll) && g_state.mx >= x && g_state.mx <= x + w && g_state.my >= y && g_state.my <= y + h;
}

void clearInput()
{
    g_state.leftPressed  = false;
    g_state.leftReleased = false;
    g_state.scroll       = 0;
}

void clearActive()
{
    g_state.active = 0;

    // mark all UI for this frame as processed
    clearInput();
}

void setActive(uint id)
{
    g_state.active     = id;
    g_state.wentActive = true;
}

void setHot(uint id)
{
    g_state.hotToBe = id;
}

bool buttonLogic(uint id, bool over)
{
    bool res = false;

    // process down
    if (!anyActive())
    {
        if (over)
            setHot(id);

        if (isHot(id) && g_state.leftPressed)
            setActive(id);
    }

    // if button is active, then react on left up
    if (isActive(id))
    {
        g_state.isActive = true;

        if (over)
            setHot(id);

        if (g_state.leftReleased)
        {
            if (isHot(id))
                res = true;
            clearActive();
        }
    }

    if (isHot(id))
        g_state.isHot = true;

    return res;
}

void updateInput(int mx, int my, ubyte mbut, int scroll)
{
    bool left = (mbut & IMGUI_MBUT_LEFT) != 0;

    g_state.mx = mx;
    g_state.my = my;
    g_state.leftPressed  = !g_state.left && left;
    g_state.leftReleased = g_state.left && !left;
    g_state.left         = left;

    g_state.scroll = scroll;
}

void imguiBeginFrame(int mx, int my, ubyte mbut, int scroll)
{
    updateInput(mx, my, mbut, scroll);

    g_state.hot     = g_state.hotToBe;
    g_state.hotToBe = 0;

    g_state.wentActive = false;
    g_state.isActive   = false;
    g_state.isHot      = false;

    g_state.widgetX = 0;
    g_state.widgetY = 0;
    g_state.widgetW = 0;

    g_state.areaId   = 1;
    g_state.widgetId = 1;

    resetGfxCmdQueue();
}

void imguiEndFrame()
{
    clearInput();
}

const imguiGfxCmd* imguiGetRenderQueue()
{
    return g_gfxCmdQueue.ptr;
}

int imguiGetRenderQueueSize()
{
    return g_gfxCmdQueueSize;
}

bool imguiBeginScrollArea(string name, int x, int y, int w, int h, int* scroll)
{
    g_state.areaId++;
    g_state.widgetId = 0;
    g_scrollId       = (g_state.areaId << 16) | g_state.widgetId;

    g_state.widgetX = x + SCROLL_AREA_PADDING;
    g_state.widgetY = y + h - AREA_HEADER + (*scroll);
    g_state.widgetW = w - SCROLL_AREA_PADDING * 4;
    g_scrollTop     = y - AREA_HEADER + h;
    g_scrollBottom  = y + SCROLL_AREA_PADDING;
    g_scrollRight   = x + w - SCROLL_AREA_PADDING * 3;
    g_scrollVal     = scroll;

    g_scrollAreaTop = g_state.widgetY;

    g_focusTop    = y - AREA_HEADER;
    g_focusBottom = y - AREA_HEADER + h;

    g_insideScrollArea = inRect(x, y, w, h, false);
    g_state.insideCurrentScroll = g_insideScrollArea;

    addGfxCmdRoundedRect(cast(float)x, cast(float)y, cast(float)w, cast(float)h, 6, imguiRGBA(0, 0, 0, 192));

    addGfxCmdText(x + AREA_HEADER / 2, y + h - AREA_HEADER / 2 - TEXT_HEIGHT / 2, IMGUI_ALIGN_LEFT, name, imguiRGBA(255, 255, 255, 128));

    addGfxCmdScissor(x + SCROLL_AREA_PADDING, y + SCROLL_AREA_PADDING, w - SCROLL_AREA_PADDING * 4, h - AREA_HEADER - SCROLL_AREA_PADDING);

    return g_insideScrollArea;
}

void imguiEndScrollArea()
{
    // Disable scissoring.
    addGfxCmdScissor(-1, -1, -1, -1);

    // Draw scroll bar
    int x = g_scrollRight + SCROLL_AREA_PADDING / 2;
    int y = g_scrollBottom;
    int w = SCROLL_AREA_PADDING * 2;
    int h = g_scrollTop - g_scrollBottom;

    int stop = g_scrollAreaTop;
    int sbot = g_state.widgetY;
    int sh   = stop - sbot;   // The scrollable area height.

    float barHeight = cast(float)h / cast(float)sh;

    if (barHeight < 1)
    {
        float barY = cast(float)(y - sbot) / cast(float)sh;

        if (barY < 0)
            barY = 0;

        if (barY > 1)
            barY = 1;

        // Handle scroll bar logic.
        uint hid = g_scrollId;
        int hx = x;
        int hy = y + cast(int)(barY * h);
        int hw = w;
        int hh = cast(int)(barHeight * h);

        const int range = h - (hh - 1);
        bool over       = inRect(hx, hy, hw, hh);
        buttonLogic(hid, over);

        if (isActive(hid))
        {
            float u = cast(float)(hy - y) / cast(float)range;

            if (g_state.wentActive)
            {
                g_state.dragY    = g_state.my;
                g_state.dragOrig = u;
            }

            if (g_state.dragY != g_state.my)
            {
                u = g_state.dragOrig + (g_state.my - g_state.dragY) / cast(float)range;

                if (u < 0)
                    u = 0;

                if (u > 1)
                    u = 1;
                *g_scrollVal = cast(int)((1 - u) * (sh - h));
            }
        }

        // BG
        addGfxCmdRoundedRect(cast(float)x, cast(float)y, cast(float)w, cast(float)h, cast(float)w / 2 - 1, imguiRGBA(0, 0, 0, 196));

        // Bar
        if (isActive(hid))
            addGfxCmdRoundedRect(cast(float)hx, cast(float)hy, cast(float)hw, cast(float)hh, cast(float)w / 2 - 1, imguiRGBA(255, 196, 0, 196));
        else
            addGfxCmdRoundedRect(cast(float)hx, cast(float)hy, cast(float)hw, cast(float)hh, cast(float)w / 2 - 1, isHot(hid) ? imguiRGBA(255, 196, 0, 96) : imguiRGBA(255, 255, 255, 64));

        // Handle mouse scrolling.
        if (g_insideScrollArea)         // && !anyActive())
        {
            if (g_state.scroll)
            {
                *g_scrollVal += 20 * g_state.scroll;

                if (*g_scrollVal < 0)
                    *g_scrollVal = 0;

                if (*g_scrollVal > (sh - h))
                    *g_scrollVal = (sh - h);
            }
        }
    }
    g_state.insideCurrentScroll = false;
}

bool imguiButton(string text, bool enabled = true)
{
    g_state.widgetId++;
    uint id = (g_state.areaId << 16) | g_state.widgetId;

    int x = g_state.widgetX;
    int y = g_state.widgetY - BUTTON_HEIGHT;
    int w = g_state.widgetW;
    int h = BUTTON_HEIGHT;
    g_state.widgetY -= BUTTON_HEIGHT + DEFAULT_SPACING;

    bool over = enabled && inRect(x, y, w, h);
    bool res  = buttonLogic(id, over);

    addGfxCmdRoundedRect(cast(float)x, cast(float)y, cast(float)w, cast(float)h, cast(float)BUTTON_HEIGHT / 2 - 1, imguiRGBA(128, 128, 128, isActive(id) ? 196 : 96));

    if (enabled)
        addGfxCmdText(x + BUTTON_HEIGHT / 2, y + BUTTON_HEIGHT / 2 - TEXT_HEIGHT / 2, IMGUI_ALIGN_LEFT, text, isHot(id) ? imguiRGBA(255, 196, 0, 255) : imguiRGBA(255, 255, 255, 200));
    else
        addGfxCmdText(x + BUTTON_HEIGHT / 2, y + BUTTON_HEIGHT / 2 - TEXT_HEIGHT / 2, IMGUI_ALIGN_LEFT, text, imguiRGBA(128, 128, 128, 200));

    return res;
}

bool imguiItem(string text, bool enabled = true)
{
    g_state.widgetId++;
    uint id = (g_state.areaId << 16) | g_state.widgetId;

    int x = g_state.widgetX;
    int y = g_state.widgetY - BUTTON_HEIGHT;
    int w = g_state.widgetW;
    int h = BUTTON_HEIGHT;
    g_state.widgetY -= BUTTON_HEIGHT + DEFAULT_SPACING;

    bool over = enabled && inRect(x, y, w, h);
    bool res  = buttonLogic(id, over);

    if (isHot(id))
        addGfxCmdRoundedRect(cast(float)x, cast(float)y, cast(float)w, cast(float)h, 2.0f, imguiRGBA(255, 196, 0, isActive(id) ? 196 : 96));

    if (enabled)
        addGfxCmdText(x + BUTTON_HEIGHT / 2, y + BUTTON_HEIGHT / 2 - TEXT_HEIGHT / 2, IMGUI_ALIGN_LEFT, text, imguiRGBA(255, 255, 255, 200));
    else
        addGfxCmdText(x + BUTTON_HEIGHT / 2, y + BUTTON_HEIGHT / 2 - TEXT_HEIGHT / 2, IMGUI_ALIGN_LEFT, text, imguiRGBA(128, 128, 128, 200));

    return res;
}

bool imguiCheck(string text, bool checked, bool enabled = true)
{
    g_state.widgetId++;
    uint id = (g_state.areaId << 16) | g_state.widgetId;

    int x = g_state.widgetX;
    int y = g_state.widgetY - BUTTON_HEIGHT;
    int w = g_state.widgetW;
    int h = BUTTON_HEIGHT;
    g_state.widgetY -= BUTTON_HEIGHT + DEFAULT_SPACING;

    bool over = enabled && inRect(x, y, w, h);
    bool res  = buttonLogic(id, over);

    const int cx = x + BUTTON_HEIGHT / 2 - CHECK_SIZE / 2;
    const int cy = y + BUTTON_HEIGHT / 2 - CHECK_SIZE / 2;
    addGfxCmdRoundedRect(cast(float)cx - 3, cast(float)cy - 3, cast(float)CHECK_SIZE + 6, cast(float)CHECK_SIZE + 6, 4, imguiRGBA(128, 128, 128, isActive(id) ? 196 : 96));

    if (checked)
    {
        if (enabled)
            addGfxCmdRoundedRect(cast(float)cx, cast(float)cy, cast(float)CHECK_SIZE, cast(float)CHECK_SIZE, cast(float)CHECK_SIZE / 2 - 1, imguiRGBA(255, 255, 255, isActive(id) ? 255 : 200));
        else
            addGfxCmdRoundedRect(cast(float)cx, cast(float)cy, cast(float)CHECK_SIZE, cast(float)CHECK_SIZE, cast(float)CHECK_SIZE / 2 - 1, imguiRGBA(128, 128, 128, 200));
    }

    if (enabled)
        addGfxCmdText(x + BUTTON_HEIGHT, y + BUTTON_HEIGHT / 2 - TEXT_HEIGHT / 2, IMGUI_ALIGN_LEFT, text, isHot(id) ? imguiRGBA(255, 196, 0, 255) : imguiRGBA(255, 255, 255, 200));
    else
        addGfxCmdText(x + BUTTON_HEIGHT, y + BUTTON_HEIGHT / 2 - TEXT_HEIGHT / 2, IMGUI_ALIGN_LEFT, text, imguiRGBA(128, 128, 128, 200));

    return res;
}

bool imguiCollapse(string text, string subtext, bool checked, bool enabled = true)
{
    g_state.widgetId++;
    uint id = (g_state.areaId << 16) | g_state.widgetId;

    int x = g_state.widgetX;
    int y = g_state.widgetY - BUTTON_HEIGHT;
    int w = g_state.widgetW;
    int h = BUTTON_HEIGHT;
    g_state.widgetY -= BUTTON_HEIGHT;     // + DEFAULT_SPACING;

    const int cx = x + BUTTON_HEIGHT / 2 - CHECK_SIZE / 2;
    const int cy = y + BUTTON_HEIGHT / 2 - CHECK_SIZE / 2;

    bool over = enabled && inRect(x, y, w, h);
    bool res  = buttonLogic(id, over);

    if (checked)
        addGfxCmdTriangle(cx, cy, CHECK_SIZE, CHECK_SIZE, 2, imguiRGBA(255, 255, 255, isActive(id) ? 255 : 200));
    else
        addGfxCmdTriangle(cx, cy, CHECK_SIZE, CHECK_SIZE, 1, imguiRGBA(255, 255, 255, isActive(id) ? 255 : 200));

    if (enabled)
        addGfxCmdText(x + BUTTON_HEIGHT, y + BUTTON_HEIGHT / 2 - TEXT_HEIGHT / 2, IMGUI_ALIGN_LEFT, text, isHot(id) ? imguiRGBA(255, 196, 0, 255) : imguiRGBA(255, 255, 255, 200));
    else
        addGfxCmdText(x + BUTTON_HEIGHT, y + BUTTON_HEIGHT / 2 - TEXT_HEIGHT / 2, IMGUI_ALIGN_LEFT, text, imguiRGBA(128, 128, 128, 200));

    if (subtext)
        addGfxCmdText(x + w - BUTTON_HEIGHT / 2, y + BUTTON_HEIGHT / 2 - TEXT_HEIGHT / 2, IMGUI_ALIGN_RIGHT, subtext, imguiRGBA(255, 255, 255, 128));

    return res;
}

void imguiLabel(string text)
{
    int x = g_state.widgetX;
    int y = g_state.widgetY - BUTTON_HEIGHT;
    g_state.widgetY -= BUTTON_HEIGHT;
    addGfxCmdText(x, y + BUTTON_HEIGHT / 2 - TEXT_HEIGHT / 2, IMGUI_ALIGN_LEFT, text, imguiRGBA(255, 255, 255, 255));
}

void imguiValue(string text)
{
    const int x = g_state.widgetX;
    const int y = g_state.widgetY - BUTTON_HEIGHT;
    const int w = g_state.widgetW;
    g_state.widgetY -= BUTTON_HEIGHT;

    addGfxCmdText(x + w - BUTTON_HEIGHT / 2, y + BUTTON_HEIGHT / 2 - TEXT_HEIGHT / 2, IMGUI_ALIGN_RIGHT, text, imguiRGBA(255, 255, 255, 200));
}

bool imguiSlider(string text, float* val, float vmin, float vmax, float vinc, bool enabled = true)
{
    g_state.widgetId++;
    uint id = (g_state.areaId << 16) | g_state.widgetId;

    int x = g_state.widgetX;
    int y = g_state.widgetY - BUTTON_HEIGHT;
    int w = g_state.widgetW;
    int h = SLIDER_HEIGHT;
    g_state.widgetY -= SLIDER_HEIGHT + DEFAULT_SPACING;

    addGfxCmdRoundedRect(cast(float)x, cast(float)y, cast(float)w, cast(float)h, 4.0f, imguiRGBA(0, 0, 0, 128));

    const int range = w - SLIDER_MARKER_WIDTH;

    float u = (*val - vmin) / (vmax - vmin);

    if (u < 0)
        u = 0;

    if (u > 1)
        u = 1;
    int m = cast(int)(u * range);

    bool over       = enabled && inRect(x + m, y, SLIDER_MARKER_WIDTH, SLIDER_HEIGHT);
    bool res        = buttonLogic(id, over);
    bool valChanged = false;

    if (isActive(id))
    {
        if (g_state.wentActive)
        {
            g_state.dragX    = g_state.mx;
            g_state.dragOrig = u;
        }

        if (g_state.dragX != g_state.mx)
        {
            u = g_state.dragOrig + cast(float)(g_state.mx - g_state.dragX) / cast(float)range;

            if (u < 0)
                u = 0;

            if (u > 1)
                u = 1;
            *val       = vmin + u * (vmax - vmin);
            *val       = floor(*val / vinc + 0.5f) * vinc; // Snap to vinc
            m          = cast(int)(u * range);
            valChanged = true;
        }
    }

    if (isActive(id))
        addGfxCmdRoundedRect(cast(float)(x + m), cast(float)y, cast(float)SLIDER_MARKER_WIDTH, cast(float)SLIDER_HEIGHT, 4.0f, imguiRGBA(255, 255, 255, 255));
    else
        addGfxCmdRoundedRect(cast(float)(x + m), cast(float)y, cast(float)SLIDER_MARKER_WIDTH, cast(float)SLIDER_HEIGHT, 4.0f, isHot(id) ? imguiRGBA(255, 196, 0, 128) : imguiRGBA(255, 255, 255, 64));

    // TODO: fix this, take a look at 'nicenum'.
    int digits = cast(int)(ceil(log10(vinc)));
    char[16] fmt;
    sformat(fmt, "%%.%df", digits >= 0 ? 0 : -digits);
    char[128] msgBuf;
    sformat(msgBuf, fmt, *val);

    string msg = msgBuf.idup;

    if (enabled)
    {
        addGfxCmdText(x + SLIDER_HEIGHT / 2, y + SLIDER_HEIGHT / 2 - TEXT_HEIGHT / 2, IMGUI_ALIGN_LEFT, text, isHot(id) ? imguiRGBA(255, 196, 0, 255) : imguiRGBA(255, 255, 255, 200));
        addGfxCmdText(x + w - SLIDER_HEIGHT / 2, y + SLIDER_HEIGHT / 2 - TEXT_HEIGHT / 2, IMGUI_ALIGN_RIGHT, msg, isHot(id) ? imguiRGBA(255, 196, 0, 255) : imguiRGBA(255, 255, 255, 200));
    }
    else
    {
        addGfxCmdText(x + SLIDER_HEIGHT / 2, y + SLIDER_HEIGHT / 2 - TEXT_HEIGHT / 2, IMGUI_ALIGN_LEFT, text, imguiRGBA(128, 128, 128, 200));
        addGfxCmdText(x + w - SLIDER_HEIGHT / 2, y + SLIDER_HEIGHT / 2 - TEXT_HEIGHT / 2, IMGUI_ALIGN_RIGHT, msg, imguiRGBA(128, 128, 128, 200));
    }

    return res || valChanged;
}

void imguiIndent()
{
    g_state.widgetX += INDENT_SIZE;
    g_state.widgetW -= INDENT_SIZE;
}

void imguiUnindent()
{
    g_state.widgetX -= INDENT_SIZE;
    g_state.widgetW += INDENT_SIZE;
}

void imguiSeparator()
{
    g_state.widgetY -= DEFAULT_SPACING * 3;
}

void imguiSeparatorLine()
{
    int x = g_state.widgetX;
    int y = g_state.widgetY - DEFAULT_SPACING * 2;
    int w = g_state.widgetW;
    int h = 1;
    g_state.widgetY -= DEFAULT_SPACING * 4;

    addGfxCmdRect(cast(float)x, cast(float)y, cast(float)w, cast(float)h, imguiRGBA(255, 255, 255, 32));
}

void imguiDrawText(int x, int y, int align_, string text, uint color)
{
    addGfxCmdText(x, y, align_, text, color);
}

void imguiDrawLine(float x0, float y0, float x1, float y1, float r, uint color)
{
    addGfxCmdLine(x0, y0, x1, y1, r, color);
}

void imguiDrawRect(float x, float y, float w, float h, uint color)
{
    addGfxCmdRect(x, y, w, h, color);
}

void imguiDrawRoundedRect(float x, float y, float w, float h, float r, uint color)
{
    addGfxCmdRoundedRect(x, y, w, h, r, color);
}