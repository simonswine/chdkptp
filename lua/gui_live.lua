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
]]
--[[
module for live view gui
]]
local m={
--[[
note - these are 'private' but exposed in the module for easier debugging
container -- outermost widget
icnv -- iup canvas
vp_active -- viewport streaming selected
bm_active -- bitmap streaming selected
timer -- timer for fetching updates
statslabel -- text for stats
]]
}
function m.live_support()
	return (cd ~= nil
			and type(cd.CreateCanvas) == 'function'
			and type(chdk.put_live_image_to_canvas ) == 'function')
end

local stats={
	t_start_frame = ustime.new(),
	t_end_frame = ustime.new(),
	t_start_xfer = ustime.new(),
	t_end_xfer = ustime.new(),
	t_start_draw = ustime.new(),
	t_end_draw = ustime.new(),
	t_start = ustime.new(),
	t_stop = ustime.new(),
}
function stats:init_counters()
	self.count_xfer = 0
	self.count_frame = 0
	self.xfer_last = 0
	self.xfer_total = 0
end

stats:init_counters()

function stats:start()
	if self.run then
		return
	end
	self:init_counters()
	self.t_start:get()
	self.run = true
end
function stats:stop()
	if not self.run then
		return
	end
	self.run = false
	self.t_stop:get()
end

function stats:start_frame()
	self.t_start_frame:get()
	self.count_frame = self.count_frame + 1
end

function stats:end_frame()
	self.t_end_frame:get()
end
function stats:start_xfer()
	self.t_start_xfer:get()
	self.count_xfer = self.count_xfer + 1
end
function stats:end_xfer(bytes)
	self.t_end_xfer:get()
	self.xfer_last = bytes
	self.xfer_total = self.xfer_total + bytes
end
function stats:get()
	local run
	local t_end
	-- TODO a rolling average would be more useful
	local fps_avg = 0
	local frame_time =0
	local bps_avg = 0
	local xfer_time = 0
	local bps_last = 0

	if self.run then
		run = "yes"
		t_end = self.t_end_frame
	else
		run = "no"
		t_end = self.t_stop
	end
	local tsec = (t_end:diffms(self.t_start)/1000)
	if tsec == 0 then
		tsec = 1 
	end
	if self.count_frame > 0 then
		fps_avg = self.count_frame/tsec
		frame_time = self.t_end_frame:diffms(self.t_start_frame)
	end
	if self.count_xfer > 0 then
		-- note this includes sleep
		bps_avg = self.xfer_total/tsec
		xfer_time = self.t_end_xfer:diffms(self.t_start_xfer)
		-- instananeous
		bps_last = self.xfer_last/xfer_time*1000
	end
	-- TODO this rapidly spams lua with lots of unique strings
	return string.format(
[[Running: %s
FPS avg: %0.2f
Frame last ms: %d
T/P avg kb/s: %d
Xfer last ms: %d
Xfer kb: %d
Xfer last kb/s: %d]],
		run,
		fps_avg,
		frame_time,
		bps_avg/1024,
		xfer_time,
		self.xfer_last/1024,
		bps_last/1024)
end


function m.get_current_frame_data()
	if m.dump_replay then
		return m.dump_replay_frame
	end
	if con.live then
		return con.live.frame
	end
end

function m.get_current_base_data()
	if m.dump_replay then
		return m.dump_replay_base
	end
	if con.live.base then
		return con.live.base
	end
end

local function toggle_vp(ih,state)
	m.vp_active = (state == 1)
end

local function toggle_bm(ih,state)
	m.bm_active = (state == 1)
end

--[[
update canvas size from base and frame
]]
local function update_canvas_size(base,frame)
	-- TODO would be good to have a whole buffer mode for debugging
	-- TODO this needs to account for "virtual" size for letterboxed etc
	local vp_width = chdku.live_get_frame_field(frame,'vp_width')/2
	local vp_height = chdku.live_get_frame_field(frame,'vp_height')

	local w,h = gui.parsesize(m.icnv.rastersize)
	
	local update
	if w ~= vp_width  then
		w = vp_width
		update = true
	end
	if h ~= vp_height  then
		h = vp_height
		update = true
	end
	if update then
		m.icnv.rastersize = w.."x"..h
		iup.Refresh(m.container)
		gui.resize_for_content()
	end
end

local function update_should_run()
	if not m.live_con_valid then
		return false
	end
	if not con:is_connected() or m.tabs.value ~= m.container then
		return false
	end
	return (m.vp_active or m.bm_active)
end

local function update_base_data(base)
	printf('update base data:\n')
	for i,f in ipairs(chdku.live_base_fields) do
		printf("%s:%s\n",f,tostring(chdku.live_get_base_field(base,f)))
	end
end

local last_frame_fields = {}
local function update_frame_data(frame)
	local dirty
	for i,f in ipairs(chdku.live_frame_fields) do
		local v = chdku.live_get_frame_field(frame,f)
		if v ~= last_frame_fields[f] then
			dirty = true
		end
	end
	if dirty then
		printf('update_frame_data: changed\n')
		for i,f in ipairs(chdku.live_frame_fields) do
			local v = chdku.live_get_frame_field(frame,f)
			printf("%s:%s->%s\n",f,tostring(last_frame_fields[f]),v)
			last_frame_fields[f]=v
		end
		if last_frame_fields.palette_buffer_start > 0 and last_frame_fields.palette_buffer_size > 0 then
			printf('palette:\n')
			local c=0
			---[[
			local bytes = {frame:byte(last_frame_fields.palette_buffer_start+1,
										last_frame_fields.palette_buffer_start+last_frame_fields.palette_buffer_size)}
			for i,v in ipairs(bytes) do
				printf("0x%02x,",v)
				c = c + 1
				if c == 16 then
					printf('\n')
					c=0
				else
					printf(' ')
				end
			end
			--]]
			--[[
			for i=0, m.lvidinfo.palette_buffer_size-1, 4 do
				local v = livedata:get_i32(m.lvidinfo.palette_buffer_start+i)
				printf("%08x",v)
				c = c + 1
				if c == 4 then
					c=0
					printf('\n')
				else 
					printf(' ')
				end
			end
			--]]
		end
	end
end

-- TODO this is just to allow us to read/write a binary integer record size
local dump_recsize = lbuf.new(4)

--[[
lbuf - optional lbuf to re-use, if possible
fh - file handle
returns (possibly new) lbuf or nil on eof
]]
local function read_dump_rec(lb,fh)
	if not dump_recsize:fread(fh) then
		return
	end
	local len = dump_recsize:get_u32()
	if not lb or lb:len() ~= len then
		lb = lbuf.new(len)
	end
	if lb:fread(fh) then -- on EOF, return nil
		return lb
	end
end

local function init_dump_replay()
	m.dump_replay_file = io.open(m.dump_replay_filename,"rb")
	if not m.dump_replay_file then
		printf("failed to open dumpfile\n")
		m.dump_replay = false
		return
	end
	m.dump_replay_base = read_dump_rec(m.dump_replay_frame,m.dump_replay_file)
	update_base_data(m.dump_replay_base)
end

local function end_dump_replay()
	m.dump_replay_file:close()
	m.dump_replay_file=nil
	m.dump_replay_base=nil
	m.dump_replay_frame=nil
	stats:stop()
end

local function read_dump_frame()
	stats:start()
	stats:start_xfer()

	local data = read_dump_rec(m.dump_replay_frame,m.dump_replay_file)
	-- EOF, loop
	if not data then
		end_dump_replay()
		init_dump_replay()
		data = read_dump_rec(m.dump_replay_frame,m.dump_replay_file)
	end
	m.dump_replay_frame = data
	update_frame_data(m.dump_replay_frame)
	stats:end_xfer(m.dump_replay_frame:len())
	-- TODO
	update_canvas_size(m.dump_replay_base,m.dump_replay_frame)
end

local function end_dump()
	if con.live and con.live.dump_fh then
		printf('%d bytes recorded to %s\n',tonumber(con.live.dump_size),tostring(con.live.dump_fn))
		con:live_dump_end()
	end
end

local function record_dump()
	if not m.dump_active then
		return
	end
	if not con.live.dump_fh then
		local status,err = con:live_dump_start()
		if not status then
			printf('error starting dump:%s\n',tostring(err))
			m.dump_active = false
			-- TODO update checkbox
			return
		end
		printf('recording to %s\n',con.live.dump_fn)
	end
	local status,err = con:live_dump_frame()
	if not status then
		printf('error dumping frame:%s\n',tostring(err))
		end_dump()
		m.dump_active = false
	end
end

local function toggle_dump(ih,state)
	m.dump_active = (state == 1)
	-- TODO this should be called on disconnect etc
	if not m.dumpactive then
		end_dump()
	end
end

local function toggle_play_dump(self,state)
	if state == 1 then
		local filedlg = iup.filedlg{
			dialogtype = "OPEN",
			title = "File to play", 
			filter = "*.lvdump", 
		} 
		filedlg:popup (iup.ANYWHERE, iup.ANYWHERE)

	-- Gets file dialog status
		local status = filedlg.status
		local value = filedlg.value
	-- new or overwrite (windows native dialog already prompts for overwrite
		if status ~= "0" then
			printf('play dump canceled\n')
			self.value = "OFF"
			return
		end
		printf('playing %s\n',tostring(value))
		m.dump_replay_filename = value
		init_dump_replay()
		m.dump_replay = true
	else
		end_dump_replay()
		m.dump_replay = false
	end
end


local function timer_action(self)
	if update_should_run() then
		stats:start()
		local what=0
		if m.vp_active then
			what = 1
		end
		if m.bm_active then
			what = what + 4
			what = what + 8 -- palette TODO shouldn't request if we don't understand type, but palette type is in dynamic data
		end
		if what == 0 then
			return
		end
		stats:start_xfer()
		local status,err = con:live_get_frame(what)
		if not status then
			end_dump()
			printf('error getting frame: %s\n',tostring(err))
			gui.update_connection_status() -- update connection status on error, to prevent spamming
			stats:stop()
		else
			stats:end_xfer(con.live.frame:len())
			update_frame_data(con.live.frame)
			record_dump()
			update_canvas_size(con.live.base,con.live.frame)
		end
		m.icnv:action()
	elseif m.dump_replay then
		read_dump_frame()
		m.icnv:action()
	else
		stats:stop()
	end
	m.statslabel.title = stats:get()
end

local function init_timer(time)
	if not time then
		time = "100"
	end 
	if m.timer then
		iup.Destroy(m.timer)
	end
	m.timer = iup.timer{ 
		time = time,
		action_cb = timer_action,
	}
	m.update_run_state()
end

local function update_fps(val)
	val = tonumber(val)
	if val == 0 then
		return
	end
	val = math.floor(1000/val)
	if val ~= tonumber(m.timer.time) then
		-- reset stats
		stats:stop()
		init_timer(val)
	end
end

function m.init()
	if not m.live_support() then
		return false
	end
	local icnv = iup.canvas{rastersize="360x240",border="NO",expand="NO"}
	-- testing
	--local icnv = iup.canvas{rastersize="160x100",border="NO",expand="NO"}
	m.icnv = icnv
	m.statslabel = iup.label{size="90x80",alignment="ALEFT:ATOP"}
	m.container = iup.hbox{
		iup.frame{
			icnv,
		},
		iup.vbox{
			iup.frame{
				iup.vbox{
					iup.toggle{title="Viewfinder",action=toggle_vp},
					iup.toggle{title="UI Overlay",action=toggle_bm},
					iup.hbox{
						iup.label{title="Target FPS"},
						iup.text{
							spin="YES",
							spinmax="30",
							spinmin="1",
							spininc="1",
							value="10",
							action=function(self,c,newval)
								local v = tonumber(newval)
								local min = tonumber(self.spinmin)
								local max = tonumber(self.spinmax)
								if v and v >= min and v <= max then
									self.value = tostring(v)
									self.caretpos = string.len(tostring(v))
									update_fps(self.value)
								end
								return iup.IGNORE
							end,
							spin_cb=function(self,newval)
								update_fps(newval)
							end
						},
					},
				},
				title="Stream"
			},
			iup.tabs{
				iup.vbox{
					m.statslabel,
					tabtitle="Statistics",
				},
				iup.vbox{
					tabtitle="Debug",
					iup.toggle{title="Dump to file",action=toggle_dump},
					iup.toggle{title="Play from file",action=toggle_play_dump},
				},
			},
		},
		margin="4x4",
		ngap="4"
	}

	function icnv:map_cb()
		self.ccnv = cd.CreateCanvas(cd.IUP,self)
	end

	function icnv:action()
		if m.tabs.value ~= m.container then
			return;
		end
		local ccnv = self.ccnv     -- retrieve the CD canvas from the IUP attribute
		stats:start_frame()
		ccnv:Activate()
		if m.get_current_frame_data() then
			if not chdk.put_live_image_to_canvas(ccnv,m.get_current_frame_data(),m.get_current_base_data()) then
				print('put fail')
			end
		else
			ccnv:Clear()
		end
		stats:end_frame()
	end

	--[[
	function icnv:resize_cb(w,h)
		print("Resize: Width="..w.."   Height="..h)
	end
	--]]

	m.container_title='Live'
end

function m.set_tabs(tabs)
	m.tabs = tabs
end
function m.get_container()
	return m.container
end
function m.get_container_title()
	return m.container_title
end
function m.on_connect_change(lcon)
	m.live_con_valid = false
	if con:is_connected() then
		local status, err = con:live_init_streaming()
		if not status then
			printf('error initializing live streaming: %s\n',tostring(err))
			return
		end
		
		if con.live.version_major ~= 1 then
			printf('incompatible live view version %d %d\n',tonumber(cone.live.version_major),tonumber(cone.live.version_minor))
			return
		end
		update_base_data(con.live.base)
		m.live_con_valid = true
	end
end
-- check whether we should be running, update timer
function m.update_run_state(state)
	if state == nil then
		state = (m.tabs.value == m.container)
	end
	if state then
		m.timer.run = "YES"
		stats:start()
	else
		m.timer.run = "NO"
		stats:stop()
	end
end
function m.on_tab_change(new,old)
	if not m.live_support() then
		return
	end
	if new == m.container then
		m.update_run_state(true)
	else
		m.update_run_state(false)
	end
end

-- for anything that needs to be intialized when everything is started
function m.on_dlg_run()
	init_timer()
	--m.update_run_state()
end

return m
