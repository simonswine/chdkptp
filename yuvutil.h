/*
 *
 * Copyright (C) 2010-2012 <reyalp (at) gmail dot com>
 *
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation; either version 2 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program; if not, write to the Free Software
 *  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
 */

#ifndef YUVUTIL_H
#define YUVUTIL_H
typedef void (*yuv_palette_to_rgb_fn)(const char *palette, uint8_t pixel,char *r,char *g,char *b);
typedef void (*yuv_palette_to_rgba_fn)(const char *palette, uint8_t pixel,char *r,char *g,char *b,char *a);
yuv_palette_to_rgb_fn yuv_get_palette_to_rgb_fn(unsigned type);

void yuv_bmp_type1_blend_rgb(const char *palette, uint8_t pixel,char *r,char *g,char *b);
void yuv_live_to_cd_rgb(const char *p_yuv,unsigned width,unsigned height,char *r,char *g,char *b);
extern const char yuv_default_type1_palette[];
#endif
