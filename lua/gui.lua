--[[ 
gui scratchpad
based on the button example from the IUP distribution
this file is licensed under the same terms as the IUP examples
]]
local gui = {}

-- defines released button image
img_release = iup.image {
      {1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1},
      {1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,2},
      {1,1,3,3,3,3,3,3,3,3,3,3,3,3,2,2},
      {1,1,3,3,3,3,3,3,3,3,3,3,3,3,2,2},
      {1,1,3,3,3,3,3,3,3,3,3,3,3,3,2,2},
      {1,1,3,3,3,3,3,3,3,3,3,3,3,3,2,2},
      {1,1,3,3,3,3,3,3,3,3,3,3,3,3,2,2},
      {1,1,3,3,3,3,3,3,4,4,3,3,3,3,2,2},
      {1,1,3,3,3,3,3,4,4,4,4,3,3,3,2,2},
      {1,1,3,3,3,3,3,4,4,4,4,3,3,3,2,2},
      {1,1,3,3,3,3,3,3,4,4,3,3,3,3,2,2},
      {1,1,3,3,3,3,3,3,3,3,3,3,3,3,2,2},
      {1,1,3,3,3,3,3,3,3,3,3,3,3,3,2,2},
      {1,1,3,3,3,3,3,3,3,3,3,3,3,3,2,2},
      {1,1,3,3,3,3,3,3,3,3,3,3,3,3,2,2},
      {1,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2},
      {2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2};
      colors = { "215 215 215", "40 40 40", "30 50 210", "240 0 0" }
}

-- defines pressed button image
img_press = iup.image {
      {1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1},
      {1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,2},
      {1,1,3,3,3,3,3,3,3,3,3,3,3,3,2,2},
      {1,1,3,3,3,3,3,3,3,3,3,3,3,3,2,2},
      {1,1,3,3,3,3,3,3,3,3,3,3,3,3,2,2},
      {1,1,3,3,3,3,3,3,3,3,3,3,3,3,2,2},
      {1,1,3,3,3,3,3,4,4,3,3,3,3,3,2,2},
      {1,1,3,3,3,3,4,4,4,4,3,3,3,3,2,2},
      {1,1,3,3,3,3,4,4,4,4,3,3,3,3,2,2},
      {1,1,3,3,3,3,3,4,4,3,3,3,3,3,2,2},
      {1,1,3,3,3,3,3,3,3,3,3,3,3,3,2,2},
      {1,1,3,3,3,3,3,3,3,3,3,3,3,3,2,2},
      {1,1,3,3,3,3,3,3,3,3,3,3,3,3,2,2},
      {1,1,3,3,3,3,3,3,3,3,3,3,3,3,2,2},
      {1,1,3,3,3,3,3,3,3,3,3,3,3,3,2,2},
      {1,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2},
      {2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2};
      colors = { "40 40 40", "215 215 215", "0 20 180", "210 0 0" }
}

-- defines deactivated button image
img_inactive = iup.image {
      {1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1},
      {1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,2},
      {1,1,3,3,3,3,3,3,3,3,3,3,3,3,2,2},
      {1,1,3,3,3,3,3,3,3,3,3,3,3,3,2,2},
      {1,1,3,3,3,3,3,3,3,3,3,3,3,3,2,2},
      {1,1,3,3,3,3,3,3,3,3,3,3,3,3,2,2},
      {1,1,3,3,3,3,3,3,3,3,3,3,3,3,2,2},
      {1,1,3,3,3,3,3,3,4,4,3,3,3,3,2,2},
      {1,1,3,3,3,3,3,4,4,4,4,3,3,3,2,2},
      {1,1,3,3,3,3,3,4,4,4,4,3,3,3,2,2},
      {1,1,3,3,3,3,3,3,4,4,3,3,3,3,2,2},
      {1,1,3,3,3,3,3,3,3,3,3,3,3,3,2,2},
      {1,1,3,3,3,3,3,3,3,3,3,3,3,3,2,2},
      {1,1,3,3,3,3,3,3,3,3,3,3,3,3,2,2},
      {1,1,3,3,3,3,3,3,3,3,3,3,3,3,2,2},
      {1,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2},
      {2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2};
      colors = { "215 215 215", "40 40 40", "100 100 100", "200 200 200" }
}

connect_icon = iup.label{
	image = img_release,
	iminactive = img_inactive,
	active = "NO",
}

connect_label = iup.label{
	title = string.format("host:%d.%d cam:-.- ",chdk.host_api_version()),
}

-- creates a button
btn_connect = iup.button{ 
	title = "Connect",
	size = "48x"
}

function update_connection_status()
	local host_major, host_minor = chdk.host_api_version()
	if con:is_connected() then
		connect_icon.active = "YES"
		btn_connect.title = "Disconnect"
		local cam_major, cam_minor = con:camera_api_version()
		connect_label.title = string.format("host:%d.%d cam:%d.%d",host_major,host_minor,cam_major,cam_minor)
	else
		connect_icon.active = "NO"
		btn_connect.title = "Connect"
		connect_label.title = string.format("host:%d.%d cam:-.-",host_major,host_minor)
	end
end

function btn_connect:action()
	if con:is_connected() then
		con:disconnect()
	else
		-- TODO temp, connect to the "first" device, need to add cam selection
		-- mostly copied from cli connect
		local devs = chdk.list_usb_devices()
		if #devs > 0 then
			con = chdku.connection(devs[1])
			add_status(con:connect())
		else
			add_status(false,"no devices available")
		end
	end
	update_connection_status()
end

-- creates a text box
inputtext = iup.text{ 
--	size = "700x",
	expand = "HORIZONTAL",
}

statustext = iup.text{ 
--	size = "700x256",
	multiline = "YES",
	readonly = "YES",
	expand = "YES",
}

function statusprint(...)
	local args={...}
	local s = tostring(args[1])
	for i=2,#args do
		s=s .. ' ' .. tostring(args[i])
	end
	statustext.append = s
end
--[[
device_menu = iup.menu
{
  {"Refresh devices"},
  {"Disconnect"},
  {},
} 
menu = iup.menu
{
  {
    "Device",
	device_menu
  },
}
--]]


--[[
status_timer = iup.timer{ 
	time = "500",
}
function status_timer:action_cb()
	if chdk.is_connected() then
		connect_icon.active = "YES"
		btn_connect.title = "Disconnect"
		connect_label.title = "connected"
	else
		connect_icon.active = "NO"
		btn_connect.title = "Connect"
		connect_label.title = "not connected"
	end
end
--]]
-- creates a button
btn_exec = iup.button{ 
	title = "Execute",
--	size = "EIGHTHxEIGHTH"
}

-- creates a button entitled Exit
btn_exit = iup.button{ title = "Exit" }

cam_btns={}
function cam_btn(name,title)
	if not title then
		title = name
	end
	cam_btns[name] = iup.button{
		title=title,
		size='31x15', -- couldn't get normalizer to work for some reason
		action=function(self)
			add_status(con:execlua('click("' .. name .. '")'))
		end,
	}
end
cam_btn("erase")
cam_btn("up")
cam_btn("print")
cam_btn("left")
cam_btn("set")
cam_btn("right")
cam_btn("display","disp")
cam_btn("down")
cam_btn("menu")

cam_btn_frame = iup.frame{
	iup.vbox{
		iup.hbox{ 
			cam_btns.erase,
			cam_btns.up,
			cam_btns.print,
		},
		iup.hbox{ 
			cam_btns.left,
			cam_btns.set,
			cam_btns.right,
		},
		iup.hbox{ 
			cam_btns.display,
			cam_btns.down,
			cam_btns.menu,
		},
		iup.hbox{ 
			iup.button{
				title='zoom+',
				size='45x15',
				action=function(self)
					add_status(con:execlua('click("zoom_in")'))
				end,
			},
			iup.fill{
			},
			iup.button{
				title='zoom-',
				size='45x15',
				action=function(self)
					add_status(con:execlua('click("zoom_out")'))
				end,
			},
		},
		iup.button{
			title='shoot',
			size='94x15',
			action=function(self)
				add_status(con:execlua('shoot()'))
			end,
		}
	} ;
	title = "Camera Controls",
}

camfiletree=iup.tree{}
camfiletree.name="Camera"
camfiletree.state="collapsed"
camfiletree.addexpanded="NO"
-- camfiletree.addroot="YES"

function camfiletree:get_data(id)
	return iup.TreeGetUserId(self,id)
end

-- TODO
filetreedata_getfullpath = function(self)
	-- root is special special, we don't want to add slashes
	if self.name == 'A/' then
		return 'A/'
	end
	if self.path == 'A/' then
		return self.path .. self.name
	end
	return self.path .. '/' .. self.name
end

function camfiletree:set_data(id,data)
	data.fullpath = filetreedata_getfullpath
	iup.TreeSetUserId(self,id,data)
end

function do_download_dialog(data)
	local remotepath = data:fullpath()
	local filedlg = iup.filedlg{
		dialogtype = "SAVE",
		title = "Download "..remotepath, 
		filter = "*.*", 
		filterinfo = "all files",
		file = fsutil.basename(remotepath)
	} 

-- Shows file dialog in the center of the screen
	statusprint('download dialog ' .. remotepath)
	filedlg:popup (iup.ANYWHERE, iup.ANYWHERE)

-- Gets file dialog status
	local status = filedlg.status

-- new or overwrite (windows native dialog already prompts for overwrite)
	if status == "1" or status == "0" then 
		statusprint("d "..remotepath.."->"..filedlg.value)
		-- can't use mdownload here because local name might be different than remote basename
		add_status(con:download(remotepath,filedlg.value))
		add_status(lfs.touch(filedlg.value,chdku.ts_cam2pc(data.stat.mtime)))
-- canceled
--	elseif status == "-1" then 
	end
end

function do_dir_download_dialog(data)
	local remotepath = data:fullpath()
	local filedlg = iup.filedlg{
		dialogtype = "DIR",
		title = "Download contents of "..remotepath, 
	} 

-- Shows file dialog in the center of the screen
	statusprint('download dialog ' .. remotepath)
	filedlg:popup (iup.ANYWHERE, iup.ANYWHERE)

-- Gets file dialog status
	local status = filedlg.status

-- new or overwrite (windows native dialog already prompts for overwrite)
	if status == "0" then 
		statusprint("d "..remotepath.."->"..filedlg.value)
		-- can't use mdownload here because local name might be different than remote basename
		add_status(con:mdownload({remotepath},filedlg.value))
	end
end

function do_upload_dialog(remotepath)
	local filedlg = iup.filedlg{
		dialogtype = "OPEN",
		title = "Upload to: "..remotepath, 
		filter = "*.*", 
		filterinfo = "all files",
		multiplefiles = "yes",
	} 
	statusprint('upload dialog ' .. remotepath)
	filedlg:popup (iup.ANYWHERE, iup.ANYWHERE)

-- Gets file dialog status
	local status = filedlg.status
	local value = filedlg.value
-- new or overwrite (windows native dialog already prompts for overwrite
	if status ~= "0" then
		statusprint('upload canceled status ' .. status)
		return
	end
	statusprint('upload value ' .. tostring(value))
	local multi = {}
	local e=1
	while true do
		local s
		s,e,sub=string.find(value,'([^|]+)|',e)
		if s then
			table.insert(multi,sub)
		else
			break
		end
	end
	if #multi == 0 then
		statusprint("u "..value.."->"..fsutil.joinpath(remotepath,fsutil.basename(value)))
		add_status(con:upload(value,fsutil.joinpath(remotepath,fsutil.basename(value))))
	else
		for i = 2, #multi do
			statusprint("u "..multi[1] .. '/' .. multi[i].."->"..fsutil.joinpath(remotepath,multi[i]))
			add_status(con:upload(multi[1] .. '/' .. multi[i],fsutil.joinpath(remotepath,multi[i])))
		end
	end
end

function do_delete_dialog(data)
	local msg
	local fullpath = data:fullpath()
	if data.stat.is_dir then
		msg = 'delete directory ' .. fullpath .. ' and all contents ?'
	else
		msg = 'delete ' .. fullpath .. ' ?'
	end
	if iup.Alarm('Confirm delete',msg,'OK','Cancel') == 1 then
		add_status(con:mdelete({fullpath}))
		-- TODO should refresh
	end
end

function camfiletree:rightclick_cb(id)
	local data=self:get_data(id)
	if not data then
		return
	end
	if data.fullpath then
		statusprint('tree right click: fullpath ' .. data:fullpath())
	end
	if data.stat.is_dir then
		iup.menu{
			iup.item{
				title='Refresh',
				action=function()
					local oldstate=camfiletree['state'..id]
					statusprint('old state', oldstate)
					self:populate_branch(id,data:fullpath())
					if oldstate and oldstate ~= camfiletree['state'..id] then
						camfiletree['state'..id]=oldstate
					end
				end,
			},
			iup.item{
				title='Upload...',
				action=function()
					do_upload_dialog(data:fullpath())
				end,
			},
			iup.item{
				title='Download contents...',
				action=function()
					do_dir_download_dialog(data)
				end,
			},
			iup.item{
				title='Delete...',
				action=function()
					do_delete_dialog(data)
				end,
			},
		}:popup(iup.MOUSEPOS,iup.MOUSEPOS)
	else
		iup.menu{
			iup.item{
				title='Download...',
				action=function()
					do_download_dialog(data)
				end,
			},
			iup.item{
				title='Delete...',
				action=function()
					do_delete_dialog(data)
				end,
			},
		}:popup(iup.MOUSEPOS,iup.MOUSEPOS)
	end
end

function camfiletree:populate_branch(id,path)
	self['delnode'..id] = "CHILDREN"
	statusprint('populate branch '..id..' '..path)
	if id == 0 then
		camfiletree.state="collapsed"
	end		
	local list,msg = con:listdir(path,{stat='*'})
	if type(list) == 'table' then
		chdku.sortdir_stat(list)
		for i=#list, 1, -1 do
			st = list[i]
			if st.is_dir then
				self['addbranch'..id]=st.name
				self:set_data(self.lastaddnode,{name=st.name,stat=st,path=path})
				-- dummy, otherwise tree nodes not expandable
				-- TODO would be better to only add if dir is not empty
				self['addleaf'..self.lastaddnode] = 'dummy'
			else
				self['addleaf'..id]=st.name
				self:set_data(self.lastaddnode,{name=st.name,stat=st,path=path})
			end
		end
	end
end

function camfiletree:branchopen_cb(id)
	statusprint('branchopn_cb ' .. id)
	if not con:is_connected() then
		statusprint('branchopn_cb not connected')
		return iup.IGNORE
	end
	local path
	if id == 0 then
		path = 'A/'
		-- chdku.exec('return os.stat("A/")',{libs={'serialize','serialize_msgs'}})
		-- TODO
		-- self:set_data(0,{name='A/',stat={is_dir=true},path=''})
		camfiletree:set_data(0,{name='A/',stat={is_dir=true},path=''})
	end
	local data = self:get_data(id)
	self:populate_branch(id,data:fullpath())
end

-- empty the tree, and add dummy we always re-populate on expand anyway
-- this crashes in gtk
--[[
function camfiletree:branchclose_cb(id)
	self['delnode'..id] = "CHILDREN"
	self['addleaf'..id] = 'dummy'
end
]]

-- creates a dialog
dlg = iup.dialog{
	iup.vbox{ 
		iup.hbox{ 
			connect_icon,
			connect_label,
			iup.fill{},
			btn_connect;
		},
		iup.hbox{
			iup.tabs{
				iup.vbox{
					statustext,
					iup.hbox{
						inputtext, 
						btn_exec,
					},
				},
				camfiletree;
				tabtitle0='console',
				tabtitle1='files',
			},
			iup.vbox{
				cam_btn_frame,
				iup.hbox{
					iup.button{
						title='rec',
						size='45x15',
						action=function(self)
							add_status(con:execlua('switch_mode_usb(1)'))
						end,
					},
					iup.fill{},
					iup.button{
						title='play',
						size='45x15',
						action=function(self)
							add_status(con:execlua('switch_mode_usb(0)'))
						end,
					},
				},
				iup.fill{},
				iup.hbox{
					iup.button{
						title='shutdown',
						size='45x15',
						action=function(self)
							add_status(con:execlua('shut_down()'))
						end,
					},
					iup.fill{},
					iup.button{
						title='reboot',
						size='45x15',
						action=function(self)
							add_status(con:execlua('reboot()'))
						end,
					},
				},
			}
		},
		--[[
		iup.hbox{
			iup.fill{},
		};
		]]
		padding = '2x2'
	};
	title = "CHDK PTP", 
	resize = "YES", 
	menubox = "YES", 
	maxbox = "YES",
	minbox = "YES",
	menu = menu,
	size = "700x300",
	padding = '2x2'
}
--n1.normalize="BOTH"
cmd_history = {
	pos = 1,
	prev = function(self) 
		if self[self.pos - 1]  then
			self.pos = self.pos - 1
			return self[self.pos]
--[[
		elseif #self > 1 then
			self.pos = #self
			return self[self.pos]
--]]
		end
	end,
	next = function(self) 
		if self[self.pos + 1]  then
			self.pos = self.pos + 1
			return self[self.pos]
		end
	end,
	add = function(self,value) 
		table.insert(self,value)
		self.pos = #self+1
	end
}

function inputtext:k_any(k)
	if k == iup.K_CR then
		btn_exec:action()
	elseif k == iup.K_UP then
		local hval = cmd_history:prev()
		if hval then
			inputtext.value = hval
		end
	elseif k == iup.K_DOWN then
		inputtext.value = cmd_history:next()
	end
end

--[[
mock file object that sends to gui console
]]
status_out = {
	write=function(self,...)
		statusprint(...)
	end
}

function add_status(status,msg)
	if status then
		if msg then
			statustext.append = msg
		end
	else 
		statustext.append = "error: " .. msg
	end
end

function btn_exec:action()
	statustext.append = '> ' .. inputtext.value
	cmd_history:add(inputtext.value)
--	local status,err = chdk.execlua(inputtext.value)
	add_status(cli:execute(inputtext.value))
	inputtext.value=''
	-- handle cli exit
	if cli.finished then
		dlg:hide()
	end
end

-- callback called when the exit button is activated
function btn_exit:action()
  dlg:hide()
end

function gui:run()
--	cam_buttons_normalize.normalize="BOTH"
--[[
	device_list = chdk.list_devices()
	local devtext = ""
	for num,d in ipairs(device_list) do
		iup.Append(device_menu, iup.item{ title=num .. ": " .. d.model })
		devtext = devtext .. string.format("%d: %s %s/%s vendor %x product %x",num,d.model,d.bus,d.dev,d.vendor_id,d.product_id)
	end
	statustext.value = devtext
--]]

	-- shows dialog
	dlg:showxy( iup.CENTER, iup.CENTER)
	--status_timer.run = "YES"
	camfiletree.addbranch0="dummy"
	camfiletree:set_data(0,{name='A/',stat={is_dir=true},path=''})

	util.util_stdout = status_out
	util.util_stderr = status_out
	do_connect_option()
	update_connection_status()
	do_execute_option()

	if (iup.MainLoopLevel()==0) then
	  iup.MainLoop()
	end
end

return gui;
