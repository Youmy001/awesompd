---------------------------------------------------------------------------
-- @author Alexander Yakushev &lt;yakushev.alex@gmail.com&gt;
-- @copyright 2010-2011 Alexander Yakushev
-- @release v0.9.1
---------------------------------------------------------------------------

require('utf8')
require('jamendo')
local beautiful = require('beautiful')
local naughty = naughty
local awful = awful


-- Debug stuff

local enable_dbg = false
local function dbg (...)
   if enable_dbg then
      print(...)
   end
end

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
awesompd.ESCAPE_SYMBOL_MAPPING = {}
awesompd.ESCAPE_SYMBOL_MAPPING["&"] = "&amp;"
-- Menus do not handle symbol escaping correctly, so they need their
-- own mapping.
awesompd.ESCAPE_MENU_SYMBOL_MAPPING = {}
awesompd.ESCAPE_MENU_SYMBOL_MAPPING["&"] = "'n'"

-- Icons

-- Helper function for loading icons.  Checks if an icon exists, and
-- if it does, returns the path to icon, nil otherwise.
function awesompd.try_load(file)
   local f = io.open(file)
   if f then
      io.close(f)
      return file
   else
      return nil
   end
end

function awesompd.load_icons(path)
   awesompd.ICONS = {}
   awesompd.ICONS.PLAY = awesompd.try_load(path .. "/play_icon.png")
   awesompd.ICONS.PAUSE = awesompd.try_load(path .. "/pause_icon.png")
   awesompd.ICONS.PLAY_PAUSE = awesompd.try_load(path .. "/play_pause_icon.png")
   awesompd.ICONS.STOP = awesompd.try_load(path .. "/stop_icon.png")
   awesompd.ICONS.NEXT = awesompd.try_load(path .. "/next_icon.png")
   awesompd.ICONS.PREV = awesompd.try_load(path .. "/prev_icon.png")
   awesompd.ICONS.CHECK = awesompd.try_load(path .. "/check_icon.png")
   awesompd.ICONS.RADIO = awesompd.try_load(path .. "/radio_icon.png")
end

-- Function that returns a new awesompd object.
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

   instance.recreate_menu = true
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
   instance.path_to_icons = ""
   instance.ldecorator = " "
   instance.rdecorator = " "

-- Widget configuration
   instance.widget:add_signal("mouse::enter", function(c)
                                                 instance:notify_track()
                                              end)
   instance.widget:add_signal("mouse::leave", function(c)
                                                 instance:remove_hint()
                                              end)
   return instance
end

-- Registers timers for the widget
function awesompd:run()
   enable_dbg = self.debug_mode
   self:update_track()
   self:check_playlists()
   self.load_icons(self.path_to_icons)
   self.update_widget_timer = timer({ timeout = 1 })
   self.update_widget_timer:add_signal("timeout", function() 
                                                     self:update_widget() 
                                                  end)
   self.update_widget_timer:start()
   self.update_track_timer = timer({ timeout = self.update_interval })
   self.update_track_timer:add_signal("timeout", function() 
                                                    self:update_track() 
                                                 end)
   self.update_track_timer:start()
end

-- Slightly modified function awful.util.table.join.
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
      if type(buttons[b][1]) == "string" then
         mods = { buttons[b][1] }
      else
         mods = buttons[b][1]
      end
      table.insert(widget_buttons, 
                   awful.button(mods, buttons[b][2], buttons[b][3]))
   end
   self.widget:buttons(self.ajoin(widget_buttons))
end

-- /// Group of mpc command functions ///

function awesompd:command(com,hook)
   local file = io.popen(self:mpcquery() .. com)
   if hook then
      hook(self,file)
   end
   file:close()
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
             self:command("volume +5",self.update_track)
             self:notify_state(self.NOTIFY_VOLUME)
          end
end

function awesompd:command_volume_down()
   return function()
             self:command("volume -5",self.update_track)
             self:notify_state(self.NOTIFY_VOLUME)
          end
end

function awesompd:command_random_toggle()
   return function()
             self:command("random",self.update_track)
             self:notify_state(self.NOTIFY_RANDOM)
          end
end

function awesompd:command_repeat_toggle()
   return function()
             self:command("repeat",self.update_track)
             self:notify_state(self.NOTIFY_REPEAT)
          end
end

function awesompd:command_single_toggle()
   return function()
             self:command("single",self.update_track)
             self:notify_state(self.NOTIFY_SINGLE)
          end
end

function awesompd:command_consume_toggle()
   return function()
             self:command("consume",self.update_track)
             self:notify_state(self.NOTIFY_CONSUME)
          end
end

function awesompd:command_load_playlist(name)
   return function()
             self:command("load " .. name, function() 
                                              self.recreate_menu = true 
                                           end)
          end
end

function awesompd:command_replace_playlist(name)
   return function()
             self:command("clear")
             self:command("load " .. name)
             self:command("play 1", self.update_track)
          end
end

-- TODO: make usable prompt
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
             if self.recreate_menu then 
                local new_menu = {}
                if self.main_menu ~= nil then 
                   self.main_menu:hide() 
                end 
                if
                self.connected then 
                   self:check_list() 
                   self:check_playlists()
                   table.insert(new_menu, { "Playback", self:get_playback_menu() })
                   table.insert(new_menu, { "Options", self:get_options_menu() })
                   table.insert(new_menu, { "List", self:get_list_menu() })
                   table.insert(new_menu, { "Playlists", self:get_playlists_menu() })
                   table.insert(new_menu, 
                                { "Jamendo Top 100", 
                                  { { "MP3", self:add_jamendo_top("mp31") }, 
                                    { "Ogg Vorbis", self:add_jamendo_top("ogg2") }}})
                end 
                table.insert(new_menu, { "Servers", self:get_servers_menu() }) 
                self.main_menu = awful.menu({ items = new_menu, width = 300 }) 
                self.recreate_menu = false 
             end 
             self.main_menu:toggle() 
          end 
end
   
function awesompd:add_jamendo_top(format)
   return function ()
             local track_table = jamendo.return_track_table()
             for i = 1,table.getn(track_table) do
                self:command("add " .. track_table[i].stream)
             end
             self.recreate_menu = true
             self.recreate_list = true
          end
end

-- Returns the playback menu. Menu contains of:
-- Play\Pause - always
-- Previous - if the current track is not the first 
-- in the list and playback is not stopped
-- Next - if the current track is not the last 
-- in the list and playback is not stopped
-- Stop - if the playback is not stopped
function awesompd:get_playback_menu()
   if self.recreate_playback then
      local new_menu = {}
      table.insert(new_menu, { "Play\\Pause", 
                               self:command_toggle(), 
                               self.ICONS.PLAY_PAUSE })
      if self.connected and self.status ~= "Stopped" then
         if self.current_number ~= 1 then
            table.insert(new_menu, 
                         { "Prev: " .. 
                           awesompd.protect_string(jamendo.replace_link(
                                                      self.list_array[self.current_number - 1]),
                                                   true),
                        self:command_prev_track(), self.ICONS.PREV })
         end
         if self.current_number ~= table.getn(self.list_array) then
            table.insert(new_menu, 
                         { "Next: " .. 
                           awesompd.protect_string(jamendo.replace_link(
                                                      self.list_array[self.current_number + 1]), 
                                                   true), 
                        self:command_next_track(), self.ICONS.NEXT })
         end
         table.insert(new_menu, { "Stop", self:command_stop(), self.ICONS.STOP })
      end
      self.recreate_playback = false
      playback_menu = new_menu
   end
   return playback_menu
end

-- Returns the current playlist menu. Menu consists of all elements in the playlist.
function awesompd:get_list_menu()
   if self.recreate_list then
      local new_menu = {}
      if self.list_array then
	 local total_count = table.getn(self.list_array) 
	 local start_num = (self.current_number - 15 > 0) and self.current_number - 15 or 1
	 local end_num = (self.current_number + 15 < total_count ) and self.current_number + 15 or total_count
	 for i = start_num, end_num do
            table.insert(new_menu, { jamendo.replace_link(self.list_array[i]),
                                     self:command_play_specific(i),
                                     self.current_number == i and 
                                        (self.status == "Playing" and self.ICONS.PLAY or self.ICONS.PAUSE)
                                     or nil} )
	 end
      end
      self.recreate_list = false
      self.list_menu = new_menu
   end
   return self.list_menu
end
	     
-- Returns the playlists menu. Menu consists of all files in the playlist folder.
function awesompd:get_playlists_menu()
   if self.recreate_playlists then
      local new_menu = {}
      if table.getn(self.playlists_array) > 0 then
	 for i = 1, table.getn(self.playlists_array) do
	    local submenu = {}
	    submenu[1] = { "Add to current", self:command_load_playlist(self.playlists_array[i]) }
	    submenu[2] = { "Replace current", self:command_replace_playlist(self.playlists_array[i]) }
	    new_menu[i] = { self.playlists_array[i], submenu }
	 end
	 table.insert(new_menu, {"", ""}) -- This is a separator
      end
      table.insert(new_menu, { "Refresh", function() self:check_playlists() end })
      self.recreate_playlists = false
      self.playlists_menu = new_menu
   end
   return self.playlists_menu
end

-- Returns the server menu. Menu consists of all servers specified by user during initialization.
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

-- Returns the options menu. Menu works like checkboxes for it's elements.
function awesompd:get_options_menu()
   if self.recreate_options then 
      local new_menu = {}
--      self:update_state()
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
   end
   return self.options_menu
end

-- Checks if the current playlist has changed after the last check.
function awesompd:check_list()
   local bus = io.popen(self:mpcquery() .. "playlist")
   local info = bus:read("*all")
   bus:close()
   if info ~= self.list_line then
      self.list_line = info
      if string.len(info) > 0 then
	 self.list_array = self.split(string.sub(info,1,string.len(info)),"\n")
      else
	 self.list_array = {}
      end
      self.recreate_menu = true
      self.recreate_list = true
   end
end

-- Checks if the collection of playlists changed after the last check.
function awesompd:check_playlists()
   local bus = io.popen(self:mpcquery() .. "lsplaylists")
   local info = bus:read("*all")
   bus:close()
   if info ~= self.playlists_line then
      self.playlists_line = info
      if string.len(info) > 0 then
	 self.playlists_array = self.split(info,"\n")
      else
	 self.playlists_array = {}
      end
      self.recreate_menu = true
      self.recreate_playlists = true
   end
end

-- Changes the current server to the specified one.
function awesompd:change_server(server_number)
   self.current_server = server_number
   self:remove_hint()
   self.recreate_menu = true
   self.recreate_playback = true
   self.recreate_list = true
   self.recreate_playlists = true
   self.recreate_servers = true
   self:update_track()
--   self:update_state()
end

-- /// End of menu generation functions ///

function awesompd:add_hint(hint_title, hint_text)
   self:remove_hint()
   self.notification = naughty.notify({ title      =  hint_title
					, text       = awesompd.protect_string(hint_text)
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
   return string.format('<span font="%s">%s%s%s</span>', 
                        self.font, self.ldecorator, 
                        awesompd.protect_string(text), self.rdecorator)
end

function awesompd.split (s,t)
   local l = {n=0}
   local f = function (s)
		l.n = l.n + 1
		l[l.n] = s
	     end
   local p = "%s*(.-)%s*"..t.."%s*"
   s = string.gsub(s,p,f)
   l.n = l.n + 1
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
   return utf8sub(text, string.find(text, pattern, start))
end

-- Scroll the text in the widget
function awesompd:scroll_text(text)
   local result = text
   if self.output_size < utf8len(text) then
      text = text .. " - "
      if self.scroll_pos + self.output_size - 1 > utf8len(text) then 
	 result = utf8sub(text, self.scroll_pos)
	 result = result .. utf8sub(text, 1, self.scroll_pos + self.output_size - 1 - utf8len(text))
	 self.scroll_pos = self.scroll_pos + 1
	 if self.scroll_pos > utf8len(text) then
	    self.scroll_pos = 1
	 end
      else
	 result = utf8sub(text, self.scroll_pos, self.scroll_pos + self.output_size - 1)
	 self.scroll_pos = self.scroll_pos + 1
      end
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

function awesompd:notify_connect()
   self:add_hint("Connected", "Connection established to " .. self.servers[self.current_server].server ..
		 " on port " .. self.servers[self.current_server].port)
end

function awesompd:notify_disconnect()
   self:add_hint("Disconnected", "Cannot connect to " .. self.servers[self.current_server].server ..
		 " on port " .. self.servers[self.current_server].port)
end

function awesompd:update_track(file)
   local file_exists = (file ~= nil)
   if not file_exists then
      file = io.popen(self:mpcquery())
   end
   local track_line = file:read("*line")
   local status_line = file:read("*line")
   local options_line = file:read("*line")
   if not file_exists then
      file:close()
   end

   if not track_line or string.len(track_line) == 0 then
      self.text = "Disconnected"
      self.unique_text = self.text
      if self.connected then
	 self:notify_disconnect()
	 self.connected = false
	 self.recreate_menu = true
      end
   else
      if not self.connected then
	 self:notify_connect()
	 self.connected = true
	 self.recreate_menu = true
      end
      if string.find(track_line,"volume:") then
	 self.text = "MPD stopped"
         self.unique_text = self.text
	 if self.status ~= "Stopped" then
	    self.status = "Stopped"
	    self.current_number = 0
	    self.recreate_menu = true
	    self.recreate_playback = true
	    self.recreate_list = true
	 end
         self:update_state(track_line)
      else
         self:update_state(options_line)
	 local new_track = track_line
	 if new_track ~= self.unique_text then
            self.text = jamendo.replace_link(new_track)
            self.unique_text = new_track
	    self.to_notify = true
	    self.recreate_menu = true
	    self.recreate_playback = true
	    self.recreate_list = true
	    self.current_number = tonumber(self.find_pattern(status_line,"%d+"))
	 end
	 local tmp_pst = string.find(status_line,"%d+%:%d+%/")
	 local progress = self.find_pattern(status_line,"%#%d+/%d+") .. " " .. string.sub(status_line,tmp_pst)   
	 newstatus = "Playing"
	 if string.find(status_line,"paused") then
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
end

function awesompd:update_state(state_string)
   self.state_volume = self.find_pattern(state_string,"%d+%% ")
   if string.find(state_string,"repeat: on") then
      self.state_repeat = self:check_set_state(self.state_repeat, "on")
   else
      self.state_repeat = self:check_set_state(self.state_repeat, "off")
   end
   if string.find(state_string,"random: on") then
      self.state_random = self:check_set_state(self.state_random, "on")
   else
      self.state_random = self:check_set_state(self.state_random, "off")
   end
   if string.find(state_string,"single: on") then
      self.state_single = self:check_set_state(self.state_single, "on")
   else
      self.state_single = self:check_set_state(self.state_single, "off")
   end
   if string.find(state_string,"consume: on") then
      self.state_consume = self:check_set_state(self.state_consume, "on")
   else
      self.state_consume = self:check_set_state(self.state_consume, "off")
   end
end

function awesompd:check_set_state(statevar, val)
   if statevar ~= val then
      self.recreate_menu = true
      self.recreate_options = true
   end
   return val
end

function awesompd:run_prompt(welcome,hook)
   awful.prompt.run({ prompt = welcome },
		    self.promptbox[mouse.screen].widget,
		    hook)
end

-- Replaces control characters with escaped ones.
-- for_menu - defines if the special escable table for menus should be
-- used.
function awesompd.protect_string(str, for_menu)
   if for_menu then
      return utf8replace(str, awesompd.ESCAPE_MENU_SYMBOL_MAPPING)
   else
      return utf8replace(str, awesompd.ESCAPE_SYMBOL_MAPPING)
   end
end

-- Displays a inputbox on the screen (looks like naugty with prompt).
-- title_text - bold text in the first line
-- prompt_text - preceding text on the second line
-- hook - function that will be called with input data
function awesompd:display_inputbox(title_text, prompt_text, hook)
   if self.inputbox then -- Inputbox already exists, do nothing
      return
   end
   local width = 200
   local height = 30
   local border_color = beautiful.bg_focus or '#535d6c'
   local margin = 5
   local wbox = wibox({ name = "awmpd_ibox", height = height , width = width, 
                        border_color = border_color, border_width = 1 })
   self.inputbox = wbox
   local ws = screen[mouse.screen].workarea

   wbox:geometry({ x = ws.width - width - 5, y = 25 })
   wbox.screen = mouse.screen
   wbox.ontop = true

   local exe_callback = function(s)
                           hook(s)
                           wbox.screen = nil
                           self.inputbox = nil
                        end
   local done_callback = function()
                            wbox.screen = nil
                            self.inputbox = nil
                         end
   local wprompt = awful.widget.prompt({ layout = awful.widget.layout.horizontal.leftright })
   local wtbox = widget({ type = "textbox" })
   wtbox:margin({ right = margin, left = margin, bottom = margin, top = margin })
   wtbox.text = "<b>" .. title_text .. "</b>"
   wbox.widgets = { wtbox, wprompt, layout = awful.widget.layout.vertical.flex }
   awful.prompt.run( { prompt = " " .. prompt_text .. ": " }, wprompt.widget, 
                     exe_callback, nil, nil, nil, done_callback)
end

-- Use it like this
-- self:display_inputbox("Search music on Jamendo", "Artist", print)
