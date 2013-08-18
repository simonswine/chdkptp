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

based on code from chdk tools/rawconvert.c and core/raw.c
*/
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>
#include "lbuf.h"
#include "rawimg.h"

#define RAWIMG_LIST "rawimg.rawimg_list" // keeps references to associated lbufs
#define RAWIMG_LIST_META "rawimg.rawimg_list_meta" // meta table

unsigned raw_get_pixel_10l(const uint8_t *p, unsigned row_bytes, unsigned x, unsigned y);
unsigned raw_get_pixel_10b(const uint8_t *p, unsigned row_bytes, unsigned x, unsigned y);

unsigned raw_get_pixel_12l(const uint8_t *p, unsigned row_bytes, unsigned x, unsigned y);
unsigned raw_get_pixel_12b(const uint8_t *p, unsigned row_bytes, unsigned x, unsigned y);

unsigned raw_get_pixel_14l(const uint8_t *p, unsigned row_bytes, unsigned x, unsigned y);
unsigned raw_get_pixel_14b(const uint8_t *p, unsigned row_bytes, unsigned x, unsigned y);

// funny case for macros
#define RAW_ENDIAN_l 0
#define RAW_ENDIAN_b 1

#define RAW_BLOCK_BYTES_10l 10
#define RAW_BLOCK_BYTES_10b 5

#define RAW_BLOCK_BYTES_12l 6
#define RAW_BLOCK_BYTES_12b 3

#define RAW_BLOCK_BYTES_14l 14
#define RAW_BLOCK_BYTES_14b 7

typedef unsigned (*get_pixel_func_t)(const uint8_t *p, unsigned row_bytes, unsigned x, unsigned y);
typedef unsigned (*set_pixel_func_t)(uint8_t *p, unsigned row_bytes, unsigned x, unsigned y, unsigned value);

typedef struct {
	int bpp;
	int endian;
	int block_bytes;
	int block_pixels;
	get_pixel_func_t get_pixel;
} raw_format_t;

typedef struct {
	raw_format_t *fmt;
	unsigned row_bytes;
	unsigned width;
	unsigned height;
	uint8_t *data;
} raw_image_t;

#define FMT_DEF_SINGLE(BPP,ENDIAN) \
{ \
	BPP, \
	RAW_ENDIAN_##ENDIAN, \
	RAW_BLOCK_BYTES_##BPP##ENDIAN, \
	RAW_BLOCK_BYTES_##BPP##ENDIAN*8/BPP, \
	raw_get_pixel_##BPP##ENDIAN, \
}

#define FMT_DEF(BPP) \
	FMT_DEF_SINGLE(BPP,l), \
	FMT_DEF_SINGLE(BPP,b)

raw_format_t raw_formats[] = {
	FMT_DEF(10),
	FMT_DEF(12),
	FMT_DEF(14),
};

static const int raw_num_formats = sizeof(raw_formats)/sizeof(raw_format_t);

unsigned raw_get_pixel_10l(const uint8_t *p, unsigned row_bytes, unsigned x, unsigned y)
{
	const uint8_t *addr = p + y * row_bytes + (x/8) * 10;
	switch (x&7) {
		case 0: return ((0x3fc&(((unsigned short)addr[1])<<2)) | (addr[0] >> 6));
		case 1: return ((0x3f0&(((unsigned short)addr[0])<<4)) | (addr[3] >> 4));
		case 2: return ((0x3c0&(((unsigned short)addr[3])<<6)) | (addr[2] >> 2));
		case 3: return ((0x300&(((unsigned short)addr[2])<<8)) | (addr[5]));
		case 4: return ((0x3fc&(((unsigned short)addr[4])<<2)) | (addr[7] >> 6));
		case 5: return ((0x3f0&(((unsigned short)addr[7])<<4)) | (addr[6] >> 4));
		case 6: return ((0x3c0&(((unsigned short)addr[6])<<6)) | (addr[9] >> 2));
		case 7: return ((0x300&(((unsigned short)addr[9])<<8)) | (addr[8]));
	}
	return 0;
}

unsigned raw_get_pixel_10b(const uint8_t *p, unsigned row_bytes, unsigned x, unsigned y)
{
	const uint8_t *addr = p + y * row_bytes + (x/4) * 5;

	switch (x&3) {
		case 0: return ((0x3fc&(((unsigned short)addr[0])<<2)) | (addr[1] >> 6));
		case 1: return ((0x3f0&(((unsigned short)addr[1])<<4)) | (addr[2] >> 4));
		case 2: return ((0x3c0&(((unsigned short)addr[2])<<6)) | (addr[3] >> 2));
		case 3: return ((0x300&(((unsigned short)addr[3])<<8)) | (addr[4]));
	}
	return 0;
}

/*
void raw_set_pixel_10l(uint8_t *p, unsigned row_bytes, unsigned x, unsigned y, unsigned value)
{
	uint8_t* addr = p + y*row_bytes + (x>>3)*10;
	switch (x&7) {
		case 0:
			addr[0] = (addr[0]&0x3F)|(value<<6); 
			addr[1] = value>>2;
		break;
		case 1:
			addr[0] = (addr[0]&0xC0)|(value>>4);
			addr[3] = (addr[3]&0x0F)|(value<<4);
		break;
		case 2:
			addr[2] = (addr[2]&0x03)|(value<<2);
			addr[3] = (addr[3]&0xF0)|(value>>6);
		break;
		case 3:
			addr[2] = (addr[2]&0xFC)|(value>>8); 
			addr[5] = value;
		break;
		case 4:
			addr[4] = value>>2;
			addr[7] = (addr[7]&0x3F)|(value<<6);
		break;
		case 5:
			addr[6] = (addr[6]&0x0F)|(value<<4);
			addr[7] = (addr[7]&0xC0)|(value>>4);
		break;
		case 6:
			addr[6] = (addr[6]&0xF0)|(value>>6);
			addr[9] = (addr[9]&0x03)|(value<<2);
		break;
		case 7:
			addr[8] = value;
			addr[9] = (addr[9]&0xFC)|(value>>8);
		break;
	}
}
*/

unsigned raw_get_pixel_12l(const uint8_t *p, unsigned row_bytes, unsigned x, unsigned y)
{
	const uint8_t *addr = p + y * row_bytes + (x/4) * 6;
	switch (x&3) {
		case 0: return ((unsigned short)(addr[1]) << 4) | (addr[0] >> 4);
		case 1: return ((unsigned short)(addr[0] & 0x0F) << 8) | (addr[3]);
		case 2: return ((unsigned short)(addr[2]) << 4) | (addr[5] >> 4);
		case 3: return ((unsigned short)(addr[5] & 0x0F) << 8) | (addr[4]);
	}
	return 0;
}

unsigned raw_get_pixel_12b(const uint8_t *p, unsigned row_bytes, unsigned x, unsigned y)
{
	const uint8_t *addr = p + y * row_bytes + (x/2) * 3;
	if (x&1)
		return ((unsigned short)(addr[1] & 0x0F) << 8) | (addr[2]);
	return ((unsigned short)(addr[0]) << 4) | (addr[1] >> 4);
}

// TODO set unused / unfinished
/*
unsigned raw_set_pixel_12l(const uint8_t *p, unsigned row_bytes, unsigned x, unsigned y, unsigned value)
{
	const uint8_t *addr = p + y * row_bytes + (x/4) * 6;
 switch (x&3) {
  case 0: 
   addr[0] = (addr[0]&0x0F) | (unsigned char)(value << 4);
   addr[1] = (unsigned char)(value >> 4);
   break;
  case 1: 
   addr[0] = (addr[0]&0xF0) | (unsigned char)(value >> 8);
   addr[3] = (unsigned char)value;
   break;
  case 2: 
   addr[2] = (unsigned char)(value >> 4);
   addr[5] = (addr[5]&0x0F) | (unsigned char)(value << 4);
   break;
  case 3: 
   addr[4] = (unsigned char)value;
   addr[5] = (addr[5]&0xF0) | (unsigned char)(value >> 8);
   break;
 }
}

unsigned raw_set_pixel_12b(const uint8_t *p, unsigned row_bytes, unsigned x, unsigned y, unsigned value)
{
	const uint8_t *addr = p + y * row_bytes + (x/2) * 3;
 switch (x&1) {
  case 0: 
   addr[0] = (unsigned char)(value >> 4);
   addr[1] = (addr[1]&0x0F) | (unsigned char)(value << 4);
   break;
  case 1: 
   addr[1] = (addr[1]&0xF0) | (unsigned char)(value >> 8);
   addr[2] = (unsigned char)value;
   break;
 }
}
*/

unsigned raw_get_pixel_14l(const uint8_t *p, unsigned row_bytes, unsigned x, unsigned y)
{
	const uint8_t *addr = p + y * row_bytes + (x/8) * 14;
    switch (x%8) {
        case 0: return ((unsigned short)(addr[ 1])        <<  6) | (addr[ 0] >> 2);
        case 1: return ((unsigned short)(addr[ 0] & 0x03) << 12) | (addr[ 3] << 4) | (addr[ 2] >> 4);
        case 2: return ((unsigned short)(addr[ 2] & 0x0F) << 10) | (addr[ 5] << 2) | (addr[ 4] >> 6);
        case 3: return ((unsigned short)(addr[ 4] & 0x3F) <<  8) | (addr[ 7]);
        case 4: return ((unsigned short)(addr[ 6])        <<  6) | (addr[ 9] >> 2);
        case 5: return ((unsigned short)(addr[ 9] & 0x03) << 12) | (addr[ 8] << 4) | (addr[11] >> 4);
        case 6: return ((unsigned short)(addr[11] & 0x0F) << 10) | (addr[10] << 2) | (addr[13] >> 6);
        case 7: return ((unsigned short)(addr[13] & 0x3F) <<  8) | (addr[12]);
    }
	return 0;
}

unsigned raw_get_pixel_14b(const uint8_t *p, unsigned row_bytes, unsigned x, unsigned y)
{
	const uint8_t *addr = p + y * row_bytes + (x/4) * 7;
    switch (x%4) {
        case 0: return ((unsigned short)(addr[ 0])        <<  6) | (addr[ 1] >> 2);
        case 1: return ((unsigned short)(addr[ 1] & 0x03) << 12) | (addr[ 2] << 4) | (addr[ 3] >> 4);
        case 2: return ((unsigned short)(addr[ 3] & 0x0F) << 10) | (addr[ 4] << 2) | (addr[ 5] >> 6);
        case 3: return ((unsigned short)(addr[ 5] & 0x3F) <<  8) | (addr[ 6]);
    }
	return 0;
}

/*
set 14 le
    unsigned char* addr=(unsigned char*)rawadr+y*camera_sensor.raw_rowlen+(x/8)*14;
    switch (x%8) {
        case 0: addr[ 0]=(addr[0]&0x03)|(value<< 2); addr[ 1]=value>>6;                                                         break;
        case 1: addr[ 0]=(addr[0]&0xFC)|(value>>12); addr[ 2]=(addr[ 2]&0x0F)|(value<< 4); addr[ 3]=value>>4;                   break;
        case 2: addr[ 2]=(addr[2]&0xF0)|(value>>10); addr[ 4]=(addr[ 4]&0x3F)|(value<< 6); addr[ 5]=value>>2;                   break;
        case 3: addr[ 4]=(addr[4]&0xC0)|(value>> 8); addr[ 7]=value;                                                            break;
        case 4: addr[ 6]=value>>6;                   addr[ 9]=(addr[ 9]&0x03)|(value<< 2);                                      break;
        case 5: addr[ 8]=value>>4;                   addr[ 9]=(addr[ 9]&0xFC)|(value>>12); addr[11]=(addr[11]&0x0F)|(value<<4); break;
        case 6: addr[10]=value>>2;                   addr[11]=(addr[11]&0xF0)|(value>>10); addr[13]=(addr[13]&0x3F)|(value<<6); break;
        case 7: addr[12]=value;                      addr[13]=(addr[13]&0xC0)|(value>> 8);                                      break;
    }

*/

/*
pixel=img:get_pixel(x,y)
nil if out of bounds
*/
static int rawimg_lua_get_pixel(lua_State *L) {
	raw_image_t* img = (raw_image_t *)luaL_checkudata(L, 1, RAWIMG_META);
	unsigned x = luaL_checknumber(L,2);
	unsigned y = luaL_checknumber(L,3);
	if(x >= img->width || y >= img->height) {
		lua_pushnil(L);
	} else {
		lua_pushnumber(L,img->fmt->get_pixel(img->data,img->row_bytes,x,y));
	}
	return 1;
}

static raw_format_t* rawimg_find_format(int bpp, int endian) {
	int i;
	for(i=0; i<raw_num_formats; i++) {
		raw_format_t *fmt = &raw_formats[i];
		if(fmt->endian == endian && fmt->bpp == bpp) {
			return fmt;
		}
	}
	return NULL;
}
/*
img = rawimg.bind_lbuf(lbuf, offset, width, height, bpp, endian)
TODO bayer?
*/
static int rawimg_lua_bind_lbuf(lua_State *L) {
	raw_image_t *img = (raw_image_t *)lua_newuserdata(L,sizeof(raw_image_t));
	if(!img) {
		return luaL_error(L,"failed to create userdata");;
	}

	lBuf_t *buf = (lBuf_t *)luaL_checkudata(L,1,LBUF_META);
	unsigned offset = luaL_checknumber(L,2);

	img->width = luaL_checknumber(L,3);
	img->height = luaL_checknumber(L,4);

	int bpp = luaL_checknumber(L,5);

	const char *endian_str = luaL_checkstring(L,6);
	int endian;

	if(strcmp(endian_str,"little") == 0) {
		endian = RAW_ENDIAN_l;
	} else if(strcmp(endian_str,"big") == 0) {
		endian = RAW_ENDIAN_b;
	} else {
		return luaL_error(L,"invalid endian");
	}
	
	img->fmt = rawimg_find_format(bpp,endian);
	if(!img->fmt) {
		return luaL_error(L,"unknown format");
	}
	
	if(img->width % img->fmt->block_pixels != 0) {
		return luaL_error(L,"width not a multiple of block size");
	}
	img->row_bytes = (img->width*img->fmt->bpp)/8;
	if(offset + img->row_bytes*img->height > buf->len) {
		return luaL_error(L,"size larger than data");
	}
	img->data = (uint8_t *)buf->bytes + offset;

	luaL_getmetatable(L, RAWIMG_META);
	lua_setmetatable(L, -2);
	
	// save a reference in the registry to keep lbuf from being collected until image goes away
	lua_getfield(L,LUA_REGISTRYINDEX,RAWIMG_LIST);
	lua_pushvalue(L, -2); // our user data, for use as key
	lua_pushvalue(L, 1); // lbuf, the value
	lua_settable(L, -3); //set t[img]=lbuf
	lua_pop(L,1); // done with t

	return 1;
}

static const luaL_Reg rawimg_lib[] = {
	{"bind_lbuf",rawimg_lua_bind_lbuf},
	{NULL, NULL}
};

// only for testing
/*
static int rawimg_gc(lua_State *L) {
	raw_image_t *img = (raw_image_t *)luaL_checkudata(L,1,RAWIMG_META);
	printf("collecting img %p:%dx%d\n",img->data,img->width,img->height);
	return 0;
}

static const luaL_Reg rawimg_meta_methods[] = {
  {"__gc", rawimg_gc},
  {NULL, NULL}
};
*/

static const luaL_Reg rawimg_methods[] = {
	{"get_pixel",rawimg_lua_get_pixel},
	/*
	{"set_pixel",rawimg_set_pixel},
	{"width",rawimg_get_width},
	{"height",rawimg_get_height},
	{"bpp",rawimg_get_bpp},
	{"endian",rawimg_get_endian},
	*/
	{NULL, NULL}
};

void rawimg_open(lua_State *L) {
	luaL_newmetatable(L,RAWIMG_META);

	/* use a table of methods for the __index method */
//	luaL_register(L, NULL, rawimg_meta_methods);  
	lua_newtable(L);
	luaL_register(L, NULL, rawimg_methods);  
	lua_setfield(L,-2,"__index");
	lua_pop(L,1); // done with meta table
	
	// create a table to keep track of lbufs referenced by raw images
	lua_newtable(L);
	// metatable for above
	luaL_newmetatable(L, RAWIMG_LIST_META);
	lua_pushstring(L, "k");  /* mode values: weak keys, strong values */
	lua_setfield(L, -2, "__mode");  /* metatable.__mode */
	lua_setmetatable(L,-2);
	lua_setfield(L,LUA_REGISTRYINDEX,RAWIMG_LIST);
	lua_pop(L,1); // done with list table

	luaL_register(L, "rawimg", rawimg_lib);  
}
