--[[
 Copyright (C) 2010-2011 <reyalp (at) gmail dot com>

  This program is free software; you can redistribute it and/or modify
  it under the terms of the GNU General Public License version 2 as
  published by the Free Software Foundation.

  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program; if not, write to the Free Software
  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
--]]
--[[
CLI commands for manipulating DNG images
]]
-- store info for DNG cli commands, global for easy script access
local m = {
	--selected = current selected dng, or nil
	list={},
}
-- current batch information, empty if not in batch
local batch={
	--current -- current dng object
	--relpath
	--src
	--pretend
}

m.get_index = function(to_find)
	for i,d in ipairs(m.list) do
		if d == to_find then
			return i
		end
	end
	return nil
end

--[[
get dng for command, using numeric index or defaulting to selected or batch current
]]
m.get_sel_batch = function(index_arg)
	if index_arg ~= nil then
		return m.list[tonumber(index_arg)] -- nil if invalid
	end
	if batch.current then
		return batch.current
	end
	return m.selected
end
m.get_sel_nobatch = function(index_arg)
	if index_arg ~= nil then
		return m.list[tonumber(index_arg)] -- nil if invalid
	end
	return m.selected
end

--[[
prepare output path for a file write
opts: {
	over:bool  -- overwrite existing
	sfx:string -- suffix to replace .dng
	pretend:bool -- don't make any changes
}
]]
local function prepare_dst_path(d,name,opts)
	opts=util.extend_table({},opts)
	local sfx = opts.sfx
	if type(name) == 'string' then
		if lfs.attributes(name,'mode') == 'directory' then
			name = fsutil.joinpath(name,fsutil.basename(d.filename))
		else
			sfx = nil -- if name specified, don't mess with suffix
		end
	else
		if batch.odir then
			name = fsutil.joinpath_cam(batch.odir,batch.relpath)
		else
			name = d.filename
		end
	end
	if sfx then
		name = fsutil.remove_sfx(name,'.dng') .. sfx
	end


	local m = lfs.attributes(name,'mode')
	if m == 'file' then
		if not opts.over then
			return false, 'file exists, use -over to overwrite '..tostring(name)
		end
	elseif m then -- TODO might want to allow
		return false, "can't overwrite non-file "..tostring(filename)
	else
		-- doesn't exist, might need to create dir
		if not opts.pretend then
			local dstdir = fsutil.dirname(name)
			local status, err = fsutil.mkdir_m(dstdir)
			if not status then 
				return false, err
			end
		end
	end
	return name
end

local function do_dump_thumb(d,args)
	local ext
	if args.tfmt == 'ppm' then
		ext = '.ppm'
	elseif args.tfmt then
		return false, 'invalid thumbnail format requested: '..tostring(args.tfmt)
	else
		ext = '.rgb'
	end

	local filename,err = prepare_dst_path(d,args.thm,{sfx='_thm'..ext,over=args.over,pretend=args.pretend})
	if not filename then
		return false, err
	end
	if args.pretend then
		printf("dump thumb: %s\n",tostring(filename))
		return true
	end
	if not args.tfmt then
		d.main_ifd:write_image_data(filename)
	elseif args.tfmt == 'ppm' then
		-- TODO should check that it's actually an RGB8 thumb
		local fh, err = io.open(filename,'wb')
		if not fh then
			return false,err
		end
		fh:write(string.format('P6\n%d\n%d\n%d\n',
			d.main_ifd.byname.ImageWidth:getel(),
			d.main_ifd.byname.ImageLength:getel(),255))
		d.main_ifd:write_image_data(fh)
		fh:close()
	end
	return true
end

local function do_dump_raw(d,args)
	local ext='.raw'
	local bpp,endian
	local fmt='asis'

	if args.rfmt then
		bpp,endian,fmt=string.match(args.rfmt,'(%d+)([lb]?)(%a*)')
		bpp = tonumber(bpp)
		if endian == '' then
			endian = nil -- use dump_image defaults
		elseif endian == 'l' then
			endian = 'little'
		elseif endian == 'b' then
			endian = 'big'
		else
			return false, 'invalid endian: '..tostring(endian)
		end
		if fmt == 'pgm' then
			ext = '.pgm'
		elseif fmt ~= '' then
			return false, 'invalid format: '..tostring(fmt)
		end
	end

	local filename,err = prepare_dst_path(d,args.raw,{sfx=ext,over=args.over,pretend=args.pretend})
	if not filename then
		return false, err
	end
	if args.pretend then
		printf("dump raw: %s\n",tostring(filename))
		return true
	end
	if fmt == 'asis' then
		d.raw_ifd:write_image_data(filename)
	elseif fmt == 'pgm' then
		return d:dump_image(filename,{bpp=bpp,pgm=true,endian=endian})
	else
		return d:dump_image(filename,{bpp=bpp,endian=endian})
	end
end

local dngbatch_ap=cli.argparser.create{
	patch=false,
	fmatch=false,
	rmatch=false,
	maxdepth=100,
	pretend=false,
	verbose=false,
	odir=false,
}

local dngbatch_cmds=util.flag_table{
	'info',
	'mod',
	'dump',
	'save',
}

local function dngbatch_docmd(cmd,dargs)
	if dargs.pretend or dargs.verbose then
		printf('%s %s\n',cmd.name,cmd.argstr)
		if dargs.pretend then
			-- these commands pretend at a lower level to output path names etc
			if cmd.name == 'dngsave' or cmd.name == 'dngdump' then
				cmd.args.pretend = true
			else
				return true
			end
		end
	end
	
	-- TODO based on cli.execute
	local cstatus,status,msg = xpcall(
		function()
			return cli.names[cmd.name](cmd.args)
		end,
		util.err_traceback)
	if not cstatus then
		return false,status
	end
	if not status and not msg then
		msg = cmd.name .. ' failed'
	end
	return status,msg
end

--[[
findfiles callback
]]
local function dngbatch_callback(self,opts)
	-- if directory, just keep processing
	if self.cur.st.mode == 'directory' then
		return true
	end
	if self.cur.name == '.' or self.cur.name == '..' then
		return true
	end
	local dargs = opts.dngbatch_args
	local cmds = opts.dngbatch_cmds
	local relpath
	local src=self.cur.full
	if #self.cur.path == 1 then
		relpath = self.cur.name
	else
		if #self.cur.path == 2 then
			relpath = self.cur.path[2]
		else
			relpath = fsutil.joinpath(unpack(self.cur.path,2))
		end
	end
	printf("load: %s\n",src)
	local d,err
	if dargs.pretend then
		d = {filename=src} -- dummy for pretend
	else
		d,err = dng.load(src)
		-- TODO warn and continue?
		if not d then 
			return false, err
		end
	end
	batch = {
		current = d,
		src = src,
		relpath = relpath,
		odir = dargs.odir,
		pretend = dargs.pretend,
	}
	local status
	for i,cmd in ipairs(cmds) do
		status,err = dngbatch_docmd(cmd,dargs)
		if not status then
			break
		end
	end
	-- ensure all batch vars are nil
	batch = {}
	return status,err
end

--[[
TODO there should be a generic framework for this in cli
]]
local function dngbatch_cmd(self,args)
	local err
	-- split of dngbatch args from rest, delimited by {}
	-- TODO input additional lines until }
	local args,rest = string.match(args,'^([^{]*){%s*([^}]*)}$')
	if not args then
		return false, 'parse error, missing {}?'
	end

	args,err = dngbatch_ap:parse(args)
	if not args then
		return false,err
	end

	if #args == 0  then
		return false,'no files specified'
	end

	local cmds={}
	local errors={}

	local cmdstrs = util.string_split(rest,'%s*;%s*',{empty=false})
	if #cmdstrs == 0 then
		return false, 'at least one command is required'
	end

	for i,v in ipairs(cmdstrs) do
		local cmd,largs = string.match(v,'^%s*(%a+)%s*(.*)')
		if not cmd then
			table.insert(errors,string.format('%d: failed to parse %s',i,tostring(v)))
		elseif not dngbatch_cmds[cmd] then
			table.insert(errors,string.format('%d: invalid command %s',i,tostring(cmd)))
		else
			cmd = 'dng'..cmd
			-- parse command args first to minimize errors during batch
			-- collect errors to display all at once
			local pargs, err = cli.names[cmd].args:parse(largs)
			if pargs then
				table.insert(cmds,{name=cmd,args=pargs,argstr=largs}) -- argstr is only for information with -pretend
			else
				table.insert(errors,string.format('%d: %s error %s',i,tostring(cmd),tostring(err)))
			end
		end
	end
	if #errors > 0 then
		return false,'\n'..table.concat(errors,'\n')
	end
	local opts={
		dirsfirst=true,
		fmatch=args.fmatch,
		rmatch=args.rmatch,
		pretend=args.pretend,
		maxdepth=tonumber(args.maxdepth),
		dngbatch_args=args,
		dngbatch_cmds=cmds,
	}
	return fsutil.find_files({unpack(args)},opts,dngbatch_callback)
end

m.init_cli = function()
	cli:add_commands{
	{
		names={'dngload'},
		help='load a dng file',
		arghelp="[options] <file>",
		args=cli.argparser.create({
			nosel=false,
		}),
		-- TODO options to reload or select/ignore if same file already loaded
		help_detail=[[
 file: file to load
   only DNGs generated by CHDK or chdkptp are supported
 options
   -nosel  do not automatically select loaded file
]],
		func=function(self,args) 
			if not args[1] then
				return false,'expected filename'
			end
			local d,err = dng.load(args[1])
			if not d then 
				return false,err
			end
			if not args.nosel then
				m.selected = d
			end
			table.insert(m.list,d)
			return true,'loaded '..d.filename
		end,
	},
	{
		-- backup or prompt for overwrite?
		names={'dngsave'},
		help='save a dng file',
		arghelp="[options] [image num] [file]",
		args=cli.argparser.create({
			over=false,
		}),
		help_detail=[[
 file:       file or directory to write to
   defaults to loaded name. if directory, appends original filename
 options:
   -over     overwrite existing files
]],
		func=function(self,args) 
			local filename
			local narg
			-- TODO this will prevent you from saving a file named '1' without explicit image number
			if tonumber(args[1]) then
				narg = table.remove(args,1)
			end
			local d = m.get_sel_batch(narg)
			if not d then
				return false, 'no file selected'
			end

			local filename,err = prepare_dst_path(d,args[1],{over=args.over,pretend=args.pretend})
			if not filename then
				return false, err
			end
			if args.pretend then
				printf("save: %s\n",filename)
				return true
			end

			local fh,err = io.open(filename,'wb')
			if not fh then
				return false, err
			end
			local status, err = d._lb:fwrite(fh)
			fh:close()
			if status then
				printf('wrote %s\n',filename)
				return true
			end
			return false, err
		end,
	},
	{
		-- TODO unload all option, collect garbage?
		names={'dngunload'},
		help='unload dng file',
		arghelp="[image num]",
		args=cli.argparser.create({}),
		func=function(self,args) 
			if #args > 0 then
				narg = table.remove(args,1)
			end
			local d = m.get_sel_nobatch(narg)
			if not d then
				return false, 'no file selected'
			end
			local di = m.get_index(d)
			table.remove(m.list,di)
			if d == m.selected then
				m.selected = nil
			end
			return true, 'unloaded '..tostring(d.filename)
		end,
	},
	{
		-- TODO file output, histogram, ifd values, individual ifd values
		names={'dnginfo'},
		help='display information about a dng',
		arghelp="[options] [image num]",
		args=cli.argparser.create({
			s=false,
			ifd=false,
			h=false,
			r=false,
			v=false,
		}),
		help_detail=[[
 options:
   -s   summary info, default if no other options given
   -h   tiff header
   -ifd[=<ifd>]
   	   raw, exif, main, or 0, 0.0 etc. default 0
   -r   recurse into sub-ifds
   -v   display ifd values, except image data (TODO not implemented!)
]],
		func=function(self,args) 
			local d = m.get_sel_batch(args[1])
			if not d then
				return false, 'no file selected'
			end
			if not args.h and not args.ifd then
				args.s = true
			end
			printf("%s:\n",d.filename)
			if args.s then
				d:print_summary()
			end
			if args.h then
				d:print_header()
			end
			if args.ifd then
				local ifd
				if args.ifd == true then
					ifd = d.main_ifd
				elseif args.ifd == 'raw' then
					ifd = d.raw_ifd
				elseif args.ifd == 'main' then
					ifd = d.main_ifd
				elseif args.ifd == 'exif' then
					ifd = d.exif_ifd
				else
					local path={}
					util.string_split(args.ifd,'.',{
						plain=true,
						func=function(v)
							local n=tonumber(v)
							if n then
								table.insert(path,n)
							else
								table.insert(path,v)
							end
						end
					})
					ifd = d:get_ifd(path)
				end
				if not ifd then
					return false, 'could not find ifd ',tostring(args.ifd)
				end
				d:print_ifd(ifd,{recurse=args.r})
			end
			return true
		end,
	},
	{
		names={'dnglist'},
		help='list loaded dng files',
		func=function(self,args) 
			local r=''
			for i, d in ipairs(m.list) do
				if d == m.selected then
					r = r .. '*'
				else
					r = r .. ' '
				end
				r = r .. string.format('%-3d: %s\n',i,d.filename)
			end
			return true, r
		end,
	},
	{
		names={'dngsel'},
		help='select dng',
		arghelp="<number>",
		args=cli.argparser.create({
			ifds=false,
		}),
		help_detail=[[
 number:
   dng number from dnglist to select
]],
		func=function(self,args) 
			local n = tonumber(args[1])
			if m.list[n] then
				m.selected = m.list[n]
				return true, string.format('selected %d: %s',n,m.selected.filename)
			end
			return false, 'invalid selection'
		end,
	},
	{
		names={'dngmod'},
		help='modify dng',
		arghelp="[options] [files]",
		args=cli.argparser.create({
			patch=false,
			over=false,
		}),
		help_detail=[[
 options:
   -patch[=n]   interpolate over pixels with value less than n (default 0)
]],
		func=function(self,args) 
			local d = m.get_sel_batch(args[1])
			if not d then
				return false, 'no file selected'
			end
			if args.patch then
				if args.patch == true then
					args.patch = 0
				else
					args.patch = tonumber(args.patch)
				end
				local count = d.img:patch_pixels(args.patch)
				printf('patched %d pixels\n',count)
			end
			return true
		end,
	},
	{
		names={'dngdump'},
		help='extract data from dng',
		arghelp="[options] [image num]",
		args=cli.argparser.create({
			thm=false,
			raw=false,
			rfmt=false,
			tfmt=false,
			over=false,
		}),
		help_detail=[[
 options:
   -thm[=name]   extract thumbnail to name, default dngname_thm.(rgb|ppm)
   -raw[=name]   extract raw data to name, default dngname.(raw|pgm)
   -over         overwrite existing file
   -rfmt=fmt raw format (default: unmodified from DNG)
     format is <bpp>[endian][pgm], e.g. 8pgm or 12l
	 pgm is only valid for 8 and 16 bpp
	 endian is l or b and defaults to little, except for 16 bit pgm
   -tfmt=fmt thumb format (default, unmodified rgb)
     ppm   8 bit rgb ppm
]],
		func=function(self,args) 
			local d = m.get_sel_batch(args[1])
			if not d then
				return false, 'no file selected'
			end
			if args.thm then
				local status, err = do_dump_thumb(d, args)
				if not status then
					return false, err
				end
			end
			if args.raw then
				local status, err = do_dump_raw(d, args)
				if not status then
					return false, err
				end
			end
			return true
		end,
	},
	{
		names={'dngbatch'},
		help='manipulate multiple files',
		arghelp="[options] [files] { command ; command ... }",
		-- TODO should default to DNG (case insensitive) only, outside of fmatch, with option to change
		-- TODO should allow filename substitutions for commands, e.g. dump -raw=$whatever
		help_detail=[[
 options:
   -odir             output directory, if no name specified in file commands
   -pretend          print actions instead of doing them
   -verbose[=n]      print detail about actions
 file selection
   -fmatch=<pattern> only file with path/name matching <pattern>
   -rmatch=<pattern> only recurse into directories with path/name matching <pattern>
   -maxdepth=n       only recurse into N levels of directory
 commands:
   mod dump save info
  take the same options as the corresponding standalone commands
  load and unload are implicitly called for each file
]],
		func=dngbatch_cmd,
	},
}
end

return m
