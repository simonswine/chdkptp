--[[
 Copyright (C) 2010-2012 <reyalp (at) gmail dot com>
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

]]
--[[
lua helper functions for working with the chdk.* c api
]]

local chdku={}
chdku.rlibs = require('rlibs')

-- format a script message in a human readable way
function chdku.format_script_msg(msg)
	if msg.type == 'none' then
		return ''
	end
	local r=string.format("%d:%s:",msg.script_id,msg.type)
	-- for user messages, type is clear from value, strings quoted, others not
	if msg.type == 'user' or msg.type == 'return' then
		if msg.subtype == 'boolean' or msg.subtype == 'integer' or msg.subtype == 'nil' then
			r = r .. tostring(msg.value)
		elseif msg.subtype == 'string' then
			r = r .. string.format("'%s'",msg.value)
		else
			r = r .. msg.subtype .. ':' .. tostring(msg.value)
		end
	elseif msg.type == 'error' then
		r = r .. msg.subtype .. ':' .. tostring(msg.value)
	end
	return r
end

--[[
Camera timestamps are in seconds since Jan 1, 1970 in current camera time
PC timestamps (linux, windows) are since Jan 1, 1970 UTC
return offset of current PC time from UTC time, in seconds
]]
function chdku.ts_get_offset()
	-- local timestamp, assumed to be seconds since unix epoch
	local tslocal=os.time()
	-- !*t returns a table of hours, minutes etc in UTC (without a timezone spec)
	-- os.time turns this into a timestamp, treating as local time
	return tslocal - os.time(os.date('!*t',tslocal))
end

--[[
covert a timestamp from the camera to the equivalent local time on the pc
]]
function chdku.ts_cam2pc(tscam)
	local tspc = tscam - chdku.ts_get_offset()
	-- TODO
	-- on windows, a time < 0 causes os.date to return nil 
	-- these can appear from the cam if you set 0 with utime and have a negative utc offset
	-- since this is a bogus date anyway, just force it to zero to avoid runtime errors
	if tspc > 0 then
		return tspc
	end
	return 0
end

--[[
covert a timestamp from the pc to the equivalent on the camera
default to current time if none given
]]
function chdku.ts_pc2cam(tspc)
	if not tspc then
		tspc = os.time()
	end
	local tscam = tspc + chdku.ts_get_offset()
	-- TODO
	-- cameras handle < 0 times inconsistently (vxworks > 2100, dryos < 1970)
	if tscam > 0 then
		return tscam
	end
	return 0
end

--[[ 
connection methods, added to the connection object
]]
local con_methods = {}
--[[
check whether this cameras model and serial number match those given
assumes self.ptpdev is up to date
TODO - ugly
]]
function con_methods:match_ptp_info(match) 
	match = util.extend_table({model='.*',serial_number='.*'},match)
	-- older cams don't have serial
	local serial = ''
	if self.ptpdev.serial_number then
		serial = self.ptpdev.serial_number
	end
--	printf('model %s (%s) serial_number %s (%s)\n',ptp_info.model,match.model,ptp_info.serial_number, match.serial_number)
	return (string.find(self.ptpdev.model,match.model) and string.find(serial,match.serial_number))
end

--[[
return a list of remote directory contents
dirlist[,err]=con:listdir(path,opts)
path should be directory, without a trailing slash (except in the case of A/...)
opts may be a table, or a string containing lua code for a table
returns directory listing as table, or false,error
note may return an empty table if target is not a directory
]]
function con_methods:listdir(path,opts) 
	if type(opts) == 'table' then
		opts = serialize(opts)
	elseif type(opts) ~= 'string' and type(opts) ~= 'nil' then
		return false, "invalid options"
	end
	if opts then
		opts = ','..opts
	else
		opts = ''
	end
	local results={}
	local i=1
	local status,err=self:execwait("return ls('"..path.."'"..opts..")",{
		libs='ls',
		msgs=chdku.msg_unbatcher(results),
	})
	if not status then
		return false,err
	end

	return results
end

local function mdownload_single(lcon,finfo,lopts,src,dst)
	local st
	-- if not always overwrite, check local
	if lopts.overwrite ~= true then
		st = lfs.attributes(dst)
	end
	if st then
		local skip
		if not lopts.overwrite then
			skip=true
		elseif type(lopts.overwrite) == 'function' then
			skip = not lopts.overwrite(lcon,lopts,finfo,st,src,dst)
		else
			error("unexpected overwrite option")
		end
		if skip then
			-- TODO
			printf('skip existing %s\n',dst)
			return true
		end
	end
	-- ptp download fails on zero byte files (zero size data phase, possibly other problems)
	if finfo.st.size > 0 then
		-- TODO should download to a temp file and move to final when complete
		local status,err = lcon:download(src,dst)
		if not status then
			return status,err
		end
	else
		local f,err=io.open(dst,"wb")
		f:close()
	end
	if lopts.mtime then
		status,err = lfs.touch(dst,chdku.ts_cam2pc(finfo.st.mtime));
		if not status then
			return status,err
		end
	end
	return true
end

--[[
download files and directories
status[,err]=con:mdownload(srcpaths,dstpath,opts)
opts:
	mtime=bool -- keep (default) or discard remote mtime NOTE files only for now
	overwrite=bool|function -- overwrite if existing found
other opts are passed to find_files
]]
function con_methods:mdownload(srcpaths,dstpath,opts)
	if not dstpath then
		dstpath = '.'
	end
	local lopts=extend_table({mtime=true,overwrite=true},opts)
	local ropts=extend_table({},opts)
	ropts.dirsfirst=true
	-- unset options that don't apply to remote
	ropts.mtime=nil
	ropts.overwrite=nil
	local dstmode = lfs.attributes(dstpath,'mode')
	if dstmode and dstmode ~= 'directory' then
		return false,'mdownload: dest must be a directory'
	end
	local files={}
	if lopts.dbgmem then
		files._dbg_fn=function(self,chunk) 
			if chunk._dbg then
				printf("dbg: %s\n",tostring(chunk._dbg))
			end
		end
	end
	local status,rstatus,rerr = self:execwait('return ff_mdownload('..serialize(srcpaths)..','..serialize(ropts)..')',
										{libs={'ff_mdownload'},msgs=chdku.msg_unbatcher(files)})

	if not status then
		return false,rstatus
	end
	if not rstatus then
		return false,rerr
	end

	if #files == 0 then
		warnf("no matching files\n");
		return true
	end

	local mkdir, download
	local function nop()
		return true
	end
	if lopts.pretend then
		mkdir=nop
		download=nop
	else
		mkdir=fsutil.mkdir_m
		download=mdownload_single
	end


	if not dstmode then
		local status,err=fsutil.mkdir_m(dstpath)
		if not status then
			return false,err
		end
	end

	for i,finfo in ipairs(files) do
		local relpath
		local src,dst
		src = finfo.full
		if #finfo.path == 1 then
			relpath = finfo.name
		else
			if #finfo.path == 2 then
				relpath = finfo.path[2]
			else
				relpath = fsutil.joinpath(unpack(finfo.path,2))
			end
		end
		dst=fsutil.joinpath(dstpath,relpath)
		if finfo.st.is_dir then
			local status,err = mkdir(dst)
			if not status then
				return false,err
			end
		else
			local dst_dir = fsutil.dirname(dst)
			if dst_dir ~= '.' then
				local status,err = mkdir(dst_dir)
				if not status then
					return false,err
				end
			end
			-- TODO this should be optional
			printf("%s->%s\n",src,dst);
			local status, err=download(self,finfo,lopts,src,dst)
			if not status then
				return status,err
			end
		end
	end
	return true
end

--[[
upload files and directories
status[,err]=con:mupload(srcpaths,dstpath,opts)
opts are as for find_files, plus
	pretend: just print what would be done
	mtime: preserve mtime of local files
]]
local function mupload_fn(self,opts)
	local con=opts.con
	if #self.rpath == 0 and self.cur.st.mode == 'directory' then
		return true
	end
	if self.cur.name == '.' or self.cur.name == '..' then
		return true
	end
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
	local dst=fsutil.joinpath_cam(opts.mu_dst,relpath)
	if self.cur.st.mode == 'directory' then
		if opts.pretend then
			printf('remote mkdir_m(%s)\n',dst)
		else
			local status,err=con:mkdir_m(dst)
			if not status then
				return false,err
			end
		end
		opts.lastdir = dst
	else
		local dst_dir=fsutil.dirname_cam(dst)
		-- cache target directory so we don't have an extra stat call for every file in that dir
		if opts.lastdir ~= dst_dir then
			local st,err=con:stat(dst_dir)
			if st then
				if not st.is_dir then
					return false, 'not a directory: '..dst_dir
				end
			else
				if opts.pretend then
					printf('remote mkdir_m(%s)\n',dst_dir)
				else
					local status,err=con:mkdir_m(dst_dir)
					if not status then
						return false,err
					end
				end
			end
			opts.lastdir = dst_dir
		end
		-- TODO stat'ing in batches would be faster
		st,err=con:stat(dst)
		if st and not st.is_file then
			return false, 'not a file: '..dst
		end
		-- TODO timestamp comparison
		printf('%s->%s\n',src,dst)
		if not opts.pretend then
			local status,err = con:upload(src,dst)
			if not status then
				return false,err
			end
			if opts.mtime then
				-- TODO updating times in batches would be faster
				local status,err = con:utime(dst,chdku.ts_pc2cam(self.cur.st.modification))
				if not status then
					return false,err
				end
			end
		end
	end
	return true
end

function con_methods:mupload(srcpaths,dstpath,opts)
	opts = util.extend_table({mtime=true},opts)
	opts.dirsfirst=true
	opts.mu_dst=dstpath
	opts.con=self
	return fsutil.find_files(srcpaths,opts,mupload_fn)
end

--[[
delete files and directories
opts are as for find_files, plus
	pretend:only return file name and action, don't delete
	skip_topdirs: top level directories passed in paths will not be removed 
		e.g. mdelete({'A/FOO'},{skip_topdirs=true}) will delete everything in FOO, but not foo itself
	ignore_errors: ignore failed deletes
]]
function con_methods:mdelete(paths,opts)
	opts=extend_table({},opts)
	opts.dirsfirst=false -- delete directories only after recursing into
	local results
	local msg_handler
	if opts.msg_handler then
		msg_handler = opts.msg_handler
		opts.msg_handler = nil -- don't serialize
	else
		results={}
		msg_handler = chdku.msg_unbatcher(results)
	end
	local status,err = self:call_remote('ff_mdelete',{libs={'ff_mdelete'},msgs=msg_handler},paths,opts)

	if not status then
		return false,err
	end
	if results then
		return results
	end
	return true
end

--[[
wrapper for remote functions, serialize args, combine remote and local error status 
func must be a string that evaluates to a function on the camera
returns remote function return values on success, false + message on failure
]]
function con_methods:call_remote(func,opts,...)
	local args = {...}
	local argstrs = {}
	-- preserve nils between values (not trailing ones but shouldn't matter in most cases)
	for i = 1,table.maxn(args) do
		argstrs[i] = serialize(args[i])
	end

	local code = "return "..func.."("..table.concat(argstrs,',')..")"
--	printf("%s\n",code)
	local results = {self:execwait(code,opts)}
	-- if local status is good, return remote
	if results[1] then
		-- start at 2 to discard local status
		return unpack(results,2,table.maxn(results)) -- maxn expression preserves nils
	end
	-- else return local error
	return false,results[2]
end

function con_methods:stat(path)
	return self:call_remote('os.stat',nil,path)
end

function con_methods:utime(path,mtime,atime)
	return self:call_remote('os.utime',nil,path,mtime,atime)
end

function con_methods:mdkir(path)
	return self:call_remote('os.mkdir',nil,path)
end

function con_methods:remove(path)
	return self:call_remote('os.remove',nil,path)
end

function con_methods:mkdir_m(path)
	return self:call_remote('mkdir_m',{libs='mkdir_m'},path)
end

--[[
sort an array of stat+name by directory status, name
]]
function chdku.sortdir_stat(list)
	table.sort(list,function(a,b) 
			if a.is_dir and not b.is_dir then
				return true
			end
			if not a.is_dir and b.is_dir then
				return false
			end
			return a.name < b.name
		end)
end

--[[
read pending messages and return error from current script, if available
]]
function con_methods:get_error_msg()
	while true do
		local msg,err = self:read_msg()
		if not msg then
			return false
		end
		if msg.type == 'none' then
			return false
		end
		if msg.type == 'error' and msg.script_id == self:get_script_id() then
			return msg.value
		end
		warnf("chdku.get_error_msg: ignoring message %s\n",chdku.format_script_msg(msg))
	end
end

--[[
format a remote lua error from chdku.exec using line number information
]]
local function format_exec_error(libs,code,errmsg)
	local lnum=tonumber(string.match(errmsg,'^%s*:(%d+):'))
	if not lnum then
		print('no match '..errmsg)
		return errmsg
	end
	local l = 0
	local lprev, errlib, errlnum
	for i,lib in ipairs(libs.list) do
		lprev = l
		l = l + lib.lines + 1 -- TODO we add \n after each lib when building code
		if l >= lnum then
			errlib = lib
			errlnum = lnum - lprev
			break
		end
	end
	if errlib then
		return string.format("%s\nrlib %s:%d\n",errmsg,errlib.name,errlnum)
	else
		return string.format("%s\nuser code: %d\n",errmsg,lnum - l)
	end
end

--[[
read and discard all pending messages. Returns false,error if message functions fails, otherwise true
]]
function con_methods:flushmsgs()
	repeat
		local msg,err=self:read_msg()
		if not msg then
			return false, err
		end
	until msg.type == 'none' 
	return true
end

--[[
return a closure to be used with as a chdku.exec msgs function, which unbatches messages msg_batcher into t
]]
function chdku.msg_unbatcher(t)
	local i=1
	return function(msg)
		if msg.subtype ~= 'table' then
			return false, 'unexpected message value'
		end
		local chunk,err=unserialize(msg.value)
		if err then
			return false, err
		end
		for j,v in ipairs(chunk) do
			t[i]=v
			i=i+1
		end
		if type(t._dbg_fn) == 'function' then
			t:_dbg_fn(chunk)
		end
		return true
	end
end
--[[ 
wrapper for chdk.execlua, using optional code from rlibs
status[,err]=con:exec("code",opts)
opts {
	libs={"rlib name1","rlib name2"...} -- rlib code to be prepended to "code"
	wait=bool -- wait for script to complete, return values will be returned after status if true
	nodefaultlib=bool -- don't automatically include default rlibs
	clobber=bool -- if false, will check script-status and refuse to execute if script is already running
				-- clobbering is likely to result in crashes / memory leaks in current versions of CHDK!
	flushmsgs=bool -- if true (default) read and silently discard any pending messages before running script
					-- not applicable if clobber is true, since the running script could just spew messages indefinitely
	-- below only apply if with wait
	msgs={table|callback} -- table or function to receive user script messages
	rets={table|callback} -- table or function to receive script return values, instead of returning them
	fdata={any lua value} -- data to be passed as second argument to callbacks
	initwait={ms|false} -- passed to wait_status, wait before first poll
	poll={ms} -- passed to wait_status, poll interval after ramp up
	pollstart={ms|false} -- passed to wait_status, initial poll interval, ramps up to poll
}
callbacks
	status[,err] = f(message,fdata)
	processing continues if status is true, otherwise aborts and returns err
]]
-- use serialize by default
chdku.default_libs={
	'serialize_msgs',
}

--[[
convenience, defaults wait=true
]]
function con_methods:execwait(code,opts_in)
	return self:exec(code,extend_table({wait=true,initwait=5},opts_in))
end

function con_methods:exec(code,opts_in)
	-- setup the options
	local opts = extend_table({flushmsgs=true},opts_in)
	local liblist={}
	-- add default libs, unless disabled
	-- TODO default libs should be per connection
	if not opts.nodefaultlib then
		extend_table(liblist,chdku.default_libs)
	end
	-- allow a single lib to be given as by name
	if type(opts.libs) == 'string' then
		liblist={opts.libs}
	else
		extend_table(liblist,opts.libs)
	end

	-- check for already running script and flush messages
	if not opts.clobber then
		-- TODO this causes a round trip.
		-- Could track locally if a script has been started since last script_status call showed complete/no messages
		-- wouldn't be safe vs scripts started in cam ui
		local status,err = self:script_status()
		if not status then
			return false,err
		end
		if status.run then
			return false,"a script is already running"
		end
		if opts.flushmsgs and status.msg then
			status,err=self:flushmsgs()
			if not status then
				return false,err
			end
		end
	end

	-- build the complete script from user code and rlibs
	local libs = chdku.rlibs:build(liblist)
	code = libs:code() .. code

	-- try to start the script
	local status,err=self:execlua(code)
	if not status then
		-- syntax error, try to fetch the error message
		if err == 'syntax' then
			local msg = self:get_error_msg()
			if msg then
				return false,format_exec_error(libs,code,msg)
			end
		end
		--  other unspecified error, or fetching syntax/compile error message failed
		return false,err
	end

	-- if not waiting, we're done
	if not opts.wait then
		return true
	end

	-- to collect return values
	-- first result is our status
	local results={true}
	local i=2

	-- process messages and wait for script to end
	while true do
		status,err=self:wait_status{
			msg=true,
			run=false,
			initwait=opts.initwait,
			poll=opts.poll,
			pollstart=opts.pollstart
		}
		if not status then
			return false,tostring(err)
		end
		if status.msg then
			local msg,err=self:read_msg()
			if not msg then
				return false, err
			end
			if msg.script_id ~= self:get_script_id() then
				warnf("chdku.exec: message from unexpected script %s\n",msg.script_id,chdku.format_script_msg(msg))
			elseif msg.type == 'user' then
				if type(opts.msgs) == 'function' then
					local status,err = opts.msgs(msg,opts.fdata)
					if not status then
						return false,err
					end
				elseif type(opts.msgs) == 'table' then
					table.insert(opts.msgs,msg)
				else
					warnf("chdku.exec: unexpected user message %s\n",chdku.format_script_msg(msg))
				end
			elseif msg.type == 'return' then
				if type(opts.rets) == 'function' then
					local status,err = opts.rets(msg,opts.fdata)
					if not status then
						return false,err
					end
				elseif type(opts.rets) == 'table' then
					table.insert(opts.rets,msg)
				else
					-- if serialize_msgs is not selected, table return values will be strings
					if msg.subtype == 'table' and libs.map['serialize_msgs'] then
						results[i] = unserialize(msg.value)
					else
						results[i] = msg.value
					end
					i=i+1
				end
			elseif msg.type == 'error' then
				return false, format_exec_error(libs,code,msg.value)
			else
				return false, 'unexpected message type'
			end
		-- script is completed and all messages have been processed
		elseif status.run == false then
			-- returns were handled by callback or table
			if opts.rets then
				return true
			else
				return unpack(results,1,table.maxn(results)) -- maxn expression preserves nils
			end
		end
	end
end

--[[
convenience method, get a message of a specific type
mtype=<string> - expected message type
msubtype=<string|nil> - expected subtype, or nil for any
munserialize=<bool> - unserialize and return the message value, only valid for user/return

returns
status,message|msg value
status first since message value could decode to false/nil
]]
function con_methods:read_msg_strict(opts)
	opts=extend_table({},opts)
	local msg,err=self:read_msg()
	if not msg or msg.type == 'none' then
		return false, err
	end
	if msg.script_id ~= self:get_script_id() then
		return false,'msg from unexpected script id'
	end
	if msg.type ~= opts.mtype then
		if msg.type == 'error' then
			return false,'unexpected error: '..msg.value
		end
		return false,'unexpected msg type: '..msg.type

	end
	if opts.msubtype and msg.subtype ~= opts.msubtype then
		return false,'wrong message subtype: ' ..msg.subtype
	end
	if opts.munserialize then
		local v = util.unserialize(msg.value)
		if opts.msubtype and type(v) ~= opts.msubtype then
			return false,'unserialize failed'
		end
		return true,v
	end
	return true,msg
end
--[[
convenience method, wait for a single message and return it
opts passed wait_status, and read_msg_strict
]]
function con_methods:wait_msg(opts)
	opts=extend_table({},opts)
	opts.msg=true
	opts.run=nil
	local status,err=self:wait_status(opts)
	if not status then
		return false,err
	end
	if status.timeout then
		return false,'timeout'
	end
	if not status.msg then
		return false,'no msg'
	end
	return self:read_msg_strict(opts)
end

-- bit number to ext + id mapping
chdku.remotecap_dtypes={
	[0]={
		ext='jpg',
		id=1,
		max_chunks=16, -- should be much less, but exact value not certain
	},
	{ 
		ext='raw',
		id=2,
		max_chunks=1,
	},
	{ 
		ext='dng_hdr', -- header only
		id=4,
		max_chunks=1,
	},
}

--[[
return a handler function that just downloads the data to a file
TODO should stream to disk in C code like download
]]
function con_methods:rc_handler_file(dir,filename,ext)
	return function(lcon,hdata)
		local err
		-- if not specified, use remote
		if not filename then
			filename,err = hdata.remotename()
			if not filename then
				return false, err
			end
		end

		if ext then
			filename = filename..'.'..ext
		else
			filename = filename..'.'..hdata.ext
		end

		if dir then
			filename = fsutil.joinpath(dir,filename)
		end
		cli.dbgmsg('rc file %s %d\n',filename,hdata.id)
		
		local fh,err = io.open(filename,'wb')
		if not fh then
			return false, err
		end

		local chunk
		local n_chunks = 0
		-- note only jpeg has multiple chunks
		repeat
			cli.dbgmsg('rc chunk get %s %d %d\n',filename,hdata.id,n_chunks)
			chunk,err=lcon:rcgetchunk(hdata.id)	
			if not chunk then
				fh:close()
				return false,err
			end
			cli.dbgmsg('rc chunk size:%d offset:%s last:%s\n',
						chunk.size,
						tostring(chunk.offset),
						tostring(chunk.last))

			if chunk.offset then
				fh:seek('set',chunk.offset)
			end
			chunk.data:fwrite(fh)
			n_chunks = n_chunks + 1
		until chunk.last or n_chunks > hdata.max_chunks
		fh:close()
		if n_chunks > hdata.max_chunks then
			return false, 'exceeded max_chunks'
		end
		return true
	end
end
--[[
fetch remote capture data
status,errmsg=con:get_remotecap_data(opts)
opts:
	timeout, initwait, poll, pollstart -- passed to wait_status
	jpg=handler,
	raw=handler,
	dng_hdr=handler,
handler:
	f(lcon,handler_data)
handler_data:
	ext -- extension from remotecap dtypes
	id  -- data type number
	opts -- options passed to get_remotecap_data
	remotename() -- returns remote name, requesting only if needed
]]
function con_methods:get_remotecap_data(opts)
	opts=util.extend_table({
		timeout=20000,
	},opts)
	local wait_opts=util.extend_table({rsdata=true},opts,{keys={'timeout','initwait','poll','pollstart'}})

	local toget = {}
	local handlers = {}

	-- TODO can probalby combine these
	if opts.jpg then
		toget[0] = true
		handlers[0] = opts.jpg
	end
	if opts.raw then
		toget[1] = true
		handlers[1] = opts.raw
	end
	if opts.dng_hdr then
		toget[2] = true
		handlers[2] = opts.dng_hdr
	end

	-- function to return remote name if needed
	local remotename
	local getremotename = function()
		if not remotename then
			local err
			remotename,err = self:rcgetname()
			if not remotename then
				return false, err
			end
		end
		return remotename
	end

	local done
	while not done do
		local status,err = con:wait_status(wait_opts)
		if not status then
			return false,'wait_status '..tostring(err)
		end
		if status.timeout then
			return false,'timed out'
		end
		if status.rsdata == 0x10000000 then
			return false,'remote shoot error'
		end
		local avail = util.bit_unpack(status.rsdata)
		local n_toget = 0
		for i=0,2 do
			if avail[i] == 1 then
				if not toget[i] then
					-- TODO could have a nop handler
					return false, string.format('unexpected type %d',i)
				end
				local hdata = util.extend_table({
					remotename=getremotename,
					opts=opts,
				},chdku.remotecap_dtypes[i])

				local status, err = handlers[i](self,hdata)
				if not status then
					return false,tostring(err)
				end
				toget[i] = nil
			end
			if toget[i] then
				n_toget = n_toget + 1
			end
		end
		if n_toget == 0 then
			done = true
		end
	end
	return true
end
--[[
sleep until specified status is met
status,errmsg=con:wait_status(opts)
opts:
{
	-- msg/run bool values cause the function to return when the status matches the given value
	-- if not set, status of that item is ignored
	msg=bool
	run=bool
	rsdata=bool -- if true, return when remote shoot data available, data in status.rsdata
	timeout=<number> -- timeout in ms
	poll=<number> -- polling interval in ms
	pollstart=<number> -- if not false, start polling at pollstart, double interval each iteration until poll is reached
	initwait=<number> -- wait N ms before first poll. If this is long enough for call to finish, saves round trip
}
status: table with msg and run set to last status, and timeout set if timeout expired, or false,errormessage on error
TODO for gui, this should yield in lua, resume from timer or something
]]
function con_methods:wait_status(opts)
	opts = util.extend_table({
		poll=250,
		pollstart=4,
		timeout=86400000 -- 1 day
	},opts)
	local timeleft = opts.timeout
	local sleeptime
	if opts.poll < 50 then
		opts.poll = 50
	end
	if opts.pollstart then
		sleeptime = opts.pollstart
	else
		sleeptime = opts.poll
	end
	if opts.initwait then
		sys.sleep(opts.initwait)
		timeleft = timeleft - opts.initwait
	end
	-- if waiting on remotecap state, make sure it's supported
	if opts.rsdata then
		-- temp for development version
		if self.apiver.MINOR < 107 then
			return false, 'camera does not support remotecap'
		end
		if type(self.rcisready) ~= 'function' then
			return false, 'client does not support remotecap'
		end
	end

	while true do
		local status,msg = self:script_status()
		if not status then
			return false,msg
		end
		-- TODO this should be available in script_status call
		if opts.rsdata then
			status.rsdata,msg = self:rcisready()
			if not status.rsdata then
				return false,msg
			end
			if status.rsdata ~= 0 then
				return status
			end
		end
		if status.run == opts.run or status.msg == opts.msg then
			return status
		end
		if timeleft > 0 then
			if opts.pollstart and sleeptime < opts.poll then
				sleeptime = sleeptime * 2
				if sleeptime > opts.poll then
					sleeptime = opts.poll
				end
			end
			if timeleft < sleeptime then
				sleeptime = timeleft
			end
			sys.sleep(sleeptime)
			timeleft = timeleft - sleeptime
		else
			status.timeout=true
			return status
		end
	end
end

--[[
set usbdev, ptpdev apiver for current connection
]]
function con_methods:update_connection_info()
	-- this currently can't fail, devinfo is always stored in connection object
	self.usbdev=self:get_usb_devinfo()
	local status,err=self:get_ptp_devinfo()	
	if status then
		self.ptpdev = status
	else
		return false,err
	end
	local major,minor=self:camera_api_version()
	if not major then
		return false,minor
	end
	self.apiver={MAJOR=major,MINOR=minor}
	return true
end
--[[
override low level connect to gather some useful information that shouldn't change over life of connection
opts{
	raw:bool -- just call the low level connect (saves ~40ms)
}
]]
function con_methods:connect(opts)
	opts = util.extend_table({},opts)
	self.live = nil
	local status,err=chdk_connection.connect(self._con)
	if not status then
		return false,err
	end
	if opts.raw then
		return true
	end
	return self:update_connection_info()
end

--[[
attempt to reconnect to the device
opts{
	wait=<ms> -- amount of time to wait, default 2 sec to avoid probs with dev numbers changing
	strict=bool -- fail if model, pid or serial number changes
}
if strict is not set, reconnect to different device returns true, <message>
]]
function con_methods:reconnect(opts)
	opts=util.extend_table({
		wait=2000,
		strict=true,
	},opts)
	if self:is_connected() then
		self:disconnect()
	end
	local ptpdev = self.ptpdev
	local usbdev = self.usbdev
	-- appears to be needed to avoid device numbers changing (reset too soon ?)
	sys.sleep(opts.wait)
	local status,err = self:connect()
	if not status then
		return status,err
	end
	if ptpdev.model ~= self.ptpdev.model
			or ptpdev.serial_number ~= self.ptpdev.serial_number
			or usbdev.product_id ~= self.usbdev.product_id then
		if opts.strict then
			self:disconnect()
			return false,'reconnected to a different device'
		else
			return true,'reconnected to a different device'
		end
	end
	return true
end

--[[
all assumed to be 32 bit signed ints for the moment
]]

chdku.live_fields={
	'version_major',
	'version_minor',
	'lcd_aspect_ratio',
	'palette_type',
	'palette_data_start',
	'vp_desc_start',
	'bm_desc_start',
}

chdku.live_fb_desc_fields={
	'fb_type',
	'data_start',
	'buffer_width',

	'visible_width',
	'visible_height',

	'margin_left',
	'margin_top',
	'margin_right',
	'margin_bot',
}

chdku.live_frame_map={}
chdku.live_fb_desc_map={}

--[[
init name->offset mapping
]]
local function live_init_maps()
	for i,name in ipairs(chdku.live_fields) do
		chdku.live_frame_map[name] = (i-1)*4
	end
	for i,name in ipairs(chdku.live_fb_desc_fields) do
		chdku.live_fb_desc_map[name] = (i-1)*4
	end
end
live_init_maps()

function chdku.live_get_frame_field(frame,field)
	if not frame then
		return nil
	end
	return frame:get_i32(chdku.live_frame_map[field])
end
local live_info_meta={
	__index=function(t,key)
		local frame = rawget(t,'_frame')
		if frame and chdku.live_frame_map[key] then
			return chdku.live_get_frame_field(frame,key)
		end
	end
}
local live_fb_desc_meta={
	__index=function(t,key)
		local frame = t._lv._frame
		if frame and chdku.live_fb_desc_map[key] then
			return frame:get_i32(t:offset()+chdku.live_fb_desc_map[key])
		end
	end
}

local live_fb_desc_methods={
	get_screen_width = function(self) 
		return self.margin_left + self.visible_width + self.margin_right;
	end,
	get_screen_height = function(self) 
		return self.margin_top + self.visible_height + self.margin_bot;
	end,
	offset = function(self) 
		return chdku.live_get_frame_field(self._lv._frame,self._offset_name)
	end,
}
function chdku.live_fb_desc_wrap(lv,fb_pfx)
	local t=util.extend_table({
		_offset_name = fb_pfx .. '_desc_start',
		_lv = lv,
	},live_fb_desc_methods);
	setmetatable(t,live_fb_desc_meta)
	return t
end

function chdku.live_wrap(frame)
	local t={_frame = frame}
	t.vp = chdku.live_fb_desc_wrap(t,'vp')
	t.bm = chdku.live_fb_desc_wrap(t,'bm')
	setmetatable(t,live_info_meta)
	return t
end

--[[
NOTE this only tells if the CHDK protocol supports live view
the live sub-protocol might not be fully compatible
]]
function con_methods:live_is_api_compatible()
	if con.apiver.MAJOR == 2 and con.apiver.MINOR >= 3 then
		return true
	end
end

function con_methods:live_get_frame(what)
	if not self.live then
		self.live = chdku.live_wrap()
	end

	local frame, err = self:get_live_data(self.live._frame,what)
	if frame then
		self.live._frame = frame
		return true
	end
	return false, err
end

function con_methods:live_dump_start(filename)
	if not self:is_connected() then
		return false,'not connected'
	end
	if not self:live_is_api_compatible() then
		return false,'api not compatible'
	end
	-- TODO
	if not self.live then
		self.live = chdku.live_wrap()
	end
	if not filename then
		filename = string.format('chdk_%x_%s.lvdump',con.usbdev.product_id,os.date('%Y%m%d_%H%M%S'))
	end
	--printf('recording to %s\n',dumpname)
	self.live.dump_fh = io.open(filename,"wb")
	if not self.live.dump_fh then
		return false, 'failed to open dumpfile'
	end

	-- used to write the size field of each frame
	self.live.dump_sz_buf = lbuf.new(4)

	-- header (magic, size of following data, version major, version minor)
	-- TODO this is ugly
	self.live.dump_fh:write('chlv') -- magic
	self.live.dump_sz_buf:set_u32(0,8) -- header size (version major, minor)
	self.live.dump_sz_buf:fwrite(self.live.dump_fh)
	self.live.dump_sz_buf:set_u32(0,1) -- version major
	self.live.dump_sz_buf:fwrite(self.live.dump_fh)
	self.live.dump_sz_buf:set_u32(0,0) -- version minor
	self.live.dump_sz_buf:fwrite(self.live.dump_fh)

	self.live.dump_size = 16;

	self.live.dump_fn = filename
	return true
end

function con_methods:live_dump_frame()
	if not self.live or not self.live.dump_fh then
		return false,'not initialized'
	end
	if not self.live._frame then
		return false,'no frame'
	end

	self.live.dump_sz_buf:set_u32(0,self.live._frame:len())
	self.live.dump_sz_buf:fwrite(self.live.dump_fh)
	self.live._frame:fwrite(self.live.dump_fh)
	self.live.dump_size = self.live.dump_size + self.live._frame:len() + 4
	return true
end

-- TODO should ensure this is automatically called when connection is closed, or re-connected
function con_methods:live_dump_end()
	if self.live.dump_fh then
		self.live.dump_fh:close()
		self.live.dump_fh=nil
	end
end

--[[
meta table for wrapped connection object
]]
local con_meta = {
	__index = function(t,key)
		return con_methods[key]
	end
}

--[[
proxy connection methods from low level object to chdku
]]
local function init_connection_methods()
	for name,func in pairs(chdk_connection) do
		if con_methods[name] == nil and type(func) == 'function' then
			con_methods[name] = function(self,...)
				return chdk_connection[name](self._con,...)
			end
		end
	end
end

init_connection_methods()

-- host api version
chdku.apiver = chdk.host_api_version()
-- host progam version
chdku.ver = chdk.program_version()

--[[
bool = chdku.match_device(devinfo,match)
attempt to find a device specified by the match table 
{
	bus='bus pattern'
	dev='device pattern'
	product_id = number
}
]]
function chdku.match_device(devinfo,match) 
	--[[
	printf('try bus:%s (%s) dev:%s (%s) pid:%s (%s)\n',
		devinfo.bus, match.bus,
		devinfo.dev, match.dev,
		devinfo.product_id, tostring(match.product_id))
	--]]
	if string.find(devinfo.bus,match.bus) and string.find(devinfo.dev,match.dev) then
		return (match.product_id == nil or tonumber(match.product_id)==devinfo.product_id)
	end
	return false
end
--[[
return a connection object wrapped with chdku methods
devspec is a table specifying the bus and device name to connect to
no checking is done on the existence of the device
if devspec is null, a dummy connection is returned

TODO this returns a *new* wrapper object, even
if one already exist for the underlying object
not clear if this is desirable, could cache a table of them
]]
function chdku.connection(devspec)
	local con = {}
	setmetatable(con,con_meta)
	con._con = chdk.connection(devspec)
	return con
end

return chdku
