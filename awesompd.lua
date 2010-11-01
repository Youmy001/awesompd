local naughty = naughty
local awful = awful

awesompd = {}

-- Constants
awesompd.MOUSE_LEFT = 1
awesompd.MOUSE_MIDDLE = 2
awesompd.MOUSE_RIGHT = 3
awesompd.MOUSE_SCROLL_UP = 4
awesompd.MOUSE_SCROLL_DOWN = 5
awesompd.NOTIFY_VOLUME = 1
awesompd.NOTIFY_REPEAT = 2
awesompd.NOTIFY_RANDOM = 3
awesompd.NOTIFY_SINGLE = 4
awesompd.NOTIFY_CONSUME = 5

function awesompd.try_load(file)
   local f = io.open(file)
   if f then
      io.close(f)
      return file
   else
      return nil
   end
end

awesompd.ICONS = {}
awesompd.ICONS.PLAY = awesompd.try_load("/home/unlogic/.config/awesome/play_icon.png")
awesompd.ICONS.PAUSE = awesompd.try_load("/home/unlogic/.config/awesome/pause_icon.png")
awesompd.ICONS.PLAY_PAUSE = awesompd.try_load("/home/unlogic/.config/awesome/play_pause_icon.png")
awesompd.ICONS.STOP = awesompd.try_load("/home/unlogic/.config/awesome/stop_icon.png")
awesompd.ICONS.NEXT = awesompd.try_load("/home/unlogic/.config/awesome/next_icon.png")
awesompd.ICONS.PREV = awesompd.try_load("/home/unlogic/.config/awesome/prev_icon.png")
awesompd.ICONS.CHECK = awesompd.try_load("/home/unlogic/.config/awesome/check_icon.png")
awesompd.ICONS.RADIO = awesompd.try_load("/home/unlogic/.config/awesome/radio_icon.png")
awesompd.ICONS_LOADED = true

function awesompd:create()
-- Initialization
   instance = {}
   setmetatable(instance,self)
   self.__index = self
   instance.current_server = 1
   instance.widget = widget({ type = "textbox" })
   instance.notification = nil
   instance.scroll_pos = 1
   instance.text = ""
   instance.status = "Stopped"
   instance.status_text = "Stopped"
   instance.to_notify = false
   instance.connected = true
   instance.promptbox = {}
   for s = 1, screen.count() do
      instance.promptbox[s] = awful.widget.prompt({ layout = awful.widget.layout.horizontal.leftright })      
   end
   instance.recreate_playback = true
   instance.recreate_list = true
   instance.recreate_servers = true
   instance.recreate_options = true
   instance.current_number = 0
   instance.menu_shown = false

-- Default user options
   instance.servers = { { server = "localhost", port = 6600 } }
   instance.font = "Monospace"
   instance.scrolling = true
   instance.output_size = 30
   instance.update_interval = 10

-- Widget configuration
   instance.widget:add_signal("mouse::enter", function(c)
				   instance:notify_track()
				end)
   instance.widget:add_signal("mouse::leave", function(c)
				   instance:remove_hint()
				end)

   return instance
end

function awesompd:run()
   self:update_track()
   self:update_state()
   awful.hooks.timer.register(1, function () self:update_widget() end)
   awful.hooks.timer.register(self.update_interval, function () self:update_track() end)
end

-- Slightly modified function awful.util.table.join
function awesompd.ajoin(buttons)
    local result = {}
    for i = 1, table.getn(buttons) do
        if buttons[i] then
            for k, v in pairs(buttons[i]) do
                if type(k) == "number" then
                    table.insert(result, v)
                else
                    result[k] = v
                end
            end
        end
    end
    return result
 end

-- Function that registers buttons on the widget.
function awesompd:register_buttons(buttons)
   widget_buttons = {}
   for b=1,table.getn(buttons) do
      mods = self.split(buttons[b][1],"+")
      table.insert(widget_buttons, awful.button(mods, buttons[b][2], buttons[b][3]))
   end
--   self.widget:buttons(widget_buttons)
   self.widget:buttons(self.ajoin(widget_buttons))
end

-- /// Group of mpc command functions ///

function awesompd:command(com,hook)
   io.popen(self:mpcquery() .. com):read("*all")
   t = hook and hook(self)
end

function awesompd:command_toggle()
   return function()
	     self:command("toggle",self.update_track)
	  end
end

function awesompd:command_next_track()
   return function()
	     self:command("next",self.update_track)
	  end
end

function awesompd:command_prev_track()
   return function()
	     self:command("seek 0")
	     self:command("prev",self.update_track)
	  end
end

function awesompd:command_play_specific(n)
   return function()
	     self:command("play " .. n,self.update_track)
	  end
end

function awesompd:command_stop()
   return function()
	     self:command("stop",self.update_track)
	  end
end

function awesompd:command_volume_up()
   return function()
	     self:command("volume +5",self.update_state)
	     self:notify_state(self.NOTIFY_VOLUME)
	  end
end

function awesompd:command_volume_down()
   return function()
	     self:command("volume -5",self.update_state)
	     self:notify_state(self.NOTIFY_VOLUME)
	  end
end

function awesompd:command_random_toggle()
   return function()
	     self:command("random",self.update_state)
	     self:notify_state(self.NOTIFY_RANDOM)
	  end
end

function awesompd:command_repeat_toggle()
   return function()
	     self:command("repeat",self.update_state)
	     self:notify_state(self.NOTIFY_REPEAT)
	  end
end

function awesompd:command_single_toggle()
   return function()
	     self:command("single",self.update_state)
	     self:notify_state(self.NOTIFY_SINGLE)
	  end
end

function awesompd:command_consume_toggle()
   return function()
	     self:command("consume",self.update_state)
	     self:notify_state(self.NOTIFY_CONSUME)
	  end
end

function awesompd:command_echo_prompt()
   return function()
	     self:run_prompt("Sample text: ",function(s)
						   self:add_hint("Prompt",s)						   
						end)
	  end
end

-- /// End of mpc command functions ///

-- /// Menu generation functions ///

function awesompd:command_show_menu()
   return function()
	     self:remove_hint()
	     self:check_list()
	     self:check_playlists()
	     if self.recreate_playback or
		self.recreate_options or
		self.recreate_list then
		--		self.recreate_playlists then
		if self.main_menu ~= nil then
		   self.main_menu:hide()
		end
		local new_menu = {}
		if self.connected then
		   table.insert(new_menu, { "Playback", self:get_playback_menu() })
--		   table.insert(new_menu, { "Options",  self:get_options_menu() })
		   table.insert(new_menu, { "List", self:get_list_menu() })
		end
		table.insert(new_menu, { "Servers", self:get_servers_menu() })
--		new_menu[3] = { "Playlists", self:get_playlists_menu() }
		self.main_menu = awful.menu({ items = new_menu,
					 width = 300
				      })
	     end
	     self.main_menu:toggle()
	  end
end

function awesompd:get_playback_menu()
   if self.recreate_playback then
      local new_menu = {}
      table.insert(new_menu, { "Play\\Pause", self:command_toggle(), self.ICONS.PLAY_PAUSE })
      if self.connected and self.status ~= "Stopped" then
	 if self.current_number ~= 1 then
	    table.insert(new_menu, { "Prev: " .. self.list_array[self.current_number - 1], 
				     self:command_prev_track(), self.ICONS.PREV })
	 end
	 if self.current_number ~= table.getn(self.list_array) then
	    table.insert(new_menu, { "Next: " .. self.list_array[self.current_number + 1], 
				     self:command_next_track(), self.ICONS.NEXT })
	 end
	 table.insert(new_menu, { "Stop", self:command_stop(), self.ICONS.STOP })
      end
      self.recreate_playback = false
      playback_menu = new_menu
   end
   return playback_menu
end

function awesompd:get_list_menu()
   if self.recreate_list then
      local new_menu = {}
      for i = 1, table.getn(self.list_array) do
	 new_menu[i] = {self.list_array[i], 
			self:command_play_specific(i),
			self.current_number == i and 
			(self.status == "Playing" and self.ICONS.PLAY or self.ICONS.PAUSE)
			or nil}
      end
      self.recreate_list = false
      self.list_menu = new_menu
   end
   return self.list_menu
end

function awesompd:get_servers_menu()
   if self.recreate_servers then
      local new_menu = {}
      for i = 1, table.getn(self.servers) do
	 table.insert(new_menu, {"Server: " .. self.servers[i].server .. 
				 ", port: " .. self.servers[i].port,
			      function() self:change_server(i) end,
			      i == self.current_server and self.ICONS.RADIO or nil})
      end
      self.servers_menu = new_menu
   end
   return self.servers_menu
end

function awesompd:get_options_menu()
   if self.recreate_options then 
      local new_menu = {}
      update_state()
      table.insert(new_menu, { "Repeat", self:command_repeat_toggle(), 
			       self.state_repeat == "on" and self.ICONS.CHECK or nil})
      table.insert(new_menu, { "Random", self:command_random_toggle(), 
			       self.state_random == "on" and self.ICONS.CHECK or nil})
      table.insert(new_menu, { "Single", self:command_single_toggle(), 
			       self.state_single == "on" and self.ICONS.CHECK or nil})
      table.insert(new_menu, { "Consume", self:command_consume_toggle(), 
			       self.state_consume == "on" and self.ICONS.CHECK or nil})
      self.options_menu = new_menu
      self.recreate_options = false
      return self.options_menu
   end
end

function awesompd:check_list()
   local bus = io.popen(self:mpcquery() .. "playlist")
   local info = bus:read("*all")
   bus:close()
   if info ~= self.list_line then
      self.list_line = info
      self.list_array = self.split(info,"\n")
      self.recreate_list = true
   end
end

function awesompd:check_playlists()
   local bus = io.popen(self:mpcquery() .. "lsplaylists")
   local info = bus:read("*all")
   bus:close()
   if info ~= self.playlists_line then
      self.playlists_line = info
      self.recreate_playlists = true
   end
end

function awesompd:change_server(server_number)
   self.current_server = server_number
   self:remove_hint()
   self.recreate_playback = true
   self.recreate_list = true
   self.recreate_playlists = true
   self.recreate_servers = true
   self:update_track()
   self:update_state()
end

-- /// End of menu generation functions ///

function awesompd:add_hint(hint_title, hint_text)
   self:remove_hint()
   self.notification = naughty.notify({ title      =  hint_title
					, text       = hint_text
					, timeout    = 5
					, position   = "top_right"
				     })
end

function awesompd:remove_hint()
   if self.notification ~= nil then
      naughty.destroy(self.notification)
      self.notification = nil
   end
end

function awesompd:notify_track()
   if self.status ~= "Stopped" then
      self:add_hint(self.status_text, self.text)
   end
end

function awesompd:notify_state(state_changed)
   state_array = { "Volume: " .. self.state_volume ,
		   "Repeat: " .. self.state_repeat ,
		   "Random: " .. self.state_random ,
		   "Single: " .. self.state_single ,
		   "Consume: " .. self.state_consume }
   state_header = state_array[state_changed]
   table.remove(state_array,state_changed)
   full_state = state_array[1]
   for i = 2, table.getn(state_array) do
      full_state = full_state .. "\n" .. state_array[i]
   end
   self:add_hint(state_header, full_state)
end

function awesompd:wrap_output(text)
   return '<span font="' .. self.font .. '">| ' .. text .. ' |</span>'
end

function awesompd.split (s,t)
   local l = {n=0}
   local f = function (s)
		l.n = l.n + 1
		l[l.n] = s
	     end
   local p = "%s*(.-)%s*"..t.."%s*"
   s = string.gsub(s,"^%s+","")
   s = string.gsub(s,"%s+$","")
   s = string.gsub(s,p,f)
   l.n = l.n + 1
   l[l.n] = string.gsub(s,"(%s%s*)$","")
   return l
end

function awesompd:mpcquery()
   return "mpc -h " .. self.servers[self.current_server].server .. 
      " -p " .. self.servers[self.current_server].port .. " "
end

function awesompd:set_text(text)
   self.widget.text = self:wrap_output(text)
end

function awesompd.find_pattern(text, pattern, start)
   return string.sub(text, string.find(text, pattern, start))
end

function awesompd:scroll_text(text)
   if self.output_size > string.len(text) then
      result = text
   elseif self.scroll_pos + self.output_size - 1 > string.len(text) then 
      text = text .. " "
      result = string.sub(text, self.scroll_pos)
      result = result .. string.sub(text, 1, self.scroll_pos + self.output_size - 1 - string.len(text))
      self.scroll_pos = self.scroll_pos + 1
      if self.scroll_pos > string.len(text) then
	 self.scroll_pos = 1
      end
   else
      text = text .. " "
      result = string.sub(text, self.scroll_pos, self.scroll_pos + self.output_size - 1)
      self.scroll_pos = self.scroll_pos + 1
   end
   return result
end

function awesompd:update_widget()
   self:set_text(self:scroll_text(self.text))
   self:check_notify()
end

function awesompd:check_notify()
   if self.to_notify then
      self:notify_track()
      self.to_notify = false
   end
end

function awesompd:notify_disconnect()
      self:add_hint("Disconnected", "Cannot connect to " .. self.servers[self.current_server].server ..
		    " on port " .. self.servers[self.current_server].port)
end

function awesompd:update_track()
   local bus = io.popen(self:mpcquery())
   local info = bus:read("*all")
   bus:close()
   local info_ar = self.split(info,"\n")
   if string.len(info) == 0 then
      self.text = "Disconnected"
      if self.connected then
	 self:notify_disconnect()
	 self.connected = false
	 self.recreate_list = true
      end
   elseif string.find(info_ar[1],"volume:") then
      self.connected = true
      self.text = "MPD stopped"
      if self.status ~= "Stopped" then
	 self.status = "Stopped"
	 self.current_number = 0
	 self.recreate_playback = true
	 self.recreate_list = true
      end
   else      
      self.connected = true
      local new_track = info_ar[1]
      if new_track ~= self.text then
	 self.text = new_track
	 self.to_notify = true
	 self.recreate_playback = true
	 self.recreate_list = true
	 self.current_number = tonumber(self.find_pattern(info_ar[2],"%d+"))
      end
      local tmp_pst = string.find(info_ar[2],"%d+%:%d+%/")
      local progress = self.find_pattern(info_ar[2],"%#%d+/%d+") .. " " .. string.sub(info_ar[2],tmp_pst)   
      newstatus = "Playing"
      if string.find(info_ar[2],"paused") then
	 newstatus = "Paused"
      end
      if newstatus ~= self.status then
	 self.to_notify = true
	 self.recreate_list = true
      end
      self.status = newstatus
      self.status_text = self.status .. " " .. progress
   end
end

function awesompd:update_state()
   local bus = io.popen(self:mpcquery())
   local info = bus:read("*all")
   bus:close()
   local info_ar = self.split(info,"\n")
   state_string = info_ar[3]
   if string.find(info_ar[1],"volume:") then
      state_string = info_ar[1]
   end
   self.state_volume = self.find_pattern(state_string,"%d+%% ")
   if string.find(state_string,"repeat: on") then
      self.state_repeat = "on"
   else
      self.state_repeat = "off"
   end
   if string.find(state_string,"random: on") then
      self.state_random = "on"
   else
      self.state_random = "off"
   end
   if string.find(state_string,"single: on") then
      self.state_single = "on"
   else
      self.state_single = "off"
   end
   if string.find(state_string,"consume: on") then
      self.state_consume = "on"
   else
      self.state_consume = "off"
   end
   self.recreate_options = true
end

function awesompd:run_prompt(welcome,hook)
   awful.prompt.run({ prompt = welcome },
		    self.promptbox[mouse.screen].widget,
		    hook)
end
