--[[
  Licensed under GNU General Public License v2
   * (c) 2014, Yauheni Kirylau
--]]

local awful		= require("awful")
local naughty		= require("naughty")
local beautiful		= require("beautiful")
local os		= { getenv	= os.getenv }
local string		= { format	= string.format }
local setmetatable	= setmetatable

local helpers		= require("actionless.helpers")
local h_string		= require("actionless.string")
local common_widget	= require("actionless.widgets.common").widget
local markup		= require("actionless.markup")
local async		= require("actionless.async")

local backends		= require("actionless.widgets.music.backends")
local tag_parser	= require("actionless.widgets.music.tag_parser")


-- player infos
local player = {
  widget=common_widget(),
  id=nil,
  cmd=nil,
  player_status = {
    state=nil,
    title=nil,
    artist=nil,
    album=nil,
    date=nil,
    file=nil
  },
  cover="/tmp/awesome_cover.png"
}

local parse_status_callback = function(player_status)
  player.parse_status(player_status)
end

local show_notification_callback = function()
  player.show_notification()
end

local function worker(args)
  local args            = args or {}
  local update_interval = args.update_interval or 2
  local timeout         = args.timeout or 5
  local default_art     = args.default_art or ""
  local backend_name    = args.backend or "mpd"
  local cover_size      = args.cover_size or 100
  local font            = args.font
                          or beautiful.tasklist_font or beautiful.font
  local bg = args.bg or beautiful.panel_bg or beautiful.bg
  local fg = args.fg or beautiful.panel_fg or beautiful.fg
  player.widget:set_bg(bg)
  player.widget:set_fg(fg)
  local text_color      = beautiful.player_text or fg or beautiful.fg_normal


  --[[
      music player backends:

      backend should have methods:
      * .toggle ()
      * .next_song ()
      * .prev_song ()
      * .update (parse_status_callback)
      optional:
      * .init(args)
      * .resize_cover(coversize, default_art, show_notification_callback)
  --]]

  if backend_name == 'mpd' then
    player.backend = backends.mpd
    player.backend.init(args)
    player.cmd = args.player_cmd or 'st -e ncmpcpp'
  elseif backend_name == 'cmus' then
    player.backend = backends.cmus
    player.cmd = args.player_cmd or 'st -e cmus'
  elseif backend_name == 'clementine' then
    player.backend = backends.clementine
    player.cmd = args.player_cmd or 'clementine'
  elseif backend_name == 'spotify' then
    player.backend = backends.spotify
    player.cmd = args.player_cmd or 'spotify'
  end

  helpers.set_map("current player track", nil)

-------------------------------------------------------------------------------
  function player.run_player()
    awful.util.spawn_with_shell(player.cmd)
  end
-------------------------------------------------------------------------------
  function player.hide_notification()
    if player.id ~= nil then
      naughty.destroy(player.id)
      player.id = nil
    end
  end
-------------------------------------------------------------------------------
  function player.show_notification()
    local text
    player.hide_notification()
    if player.player_status.album or player.player_status.date then
      text = string.format(
        "%s (%s)\n%s",
        player.player_status.album,
        player.player_status.date,
        player.player_status.artist
      )
    else
      text = string.format(
        "%s\n%s",
        player.player_status.artist,
        player.player_status.file
      )
    end
    player.id = naughty.notify({
      icon = player.cover,
      title = player.player_status.title,
      text = text,
      timeout = timeout
    })
  end
-------------------------------------------------------------------------------
  function player.toggle()
    if player.player_status.state ~= 'pause'
      and player.player_status.state ~= 'play'
    then
      player.run_player()
      return
    end
    player.backend.toggle()
    player.update()
  end

  function player.next_song()
    player.backend.next_song()
    player.update()
  end

  function player.prev_song()
    player.backend.prev_song()
    player.update()
  end

  player.widget:connect_signal(
    "mouse::enter", function () player.show_notification() end)
  player.widget:connect_signal(
    "mouse::leave", function () player.hide_notification() end)
  player.widget:buttons(awful.util.table.join(
    awful.button({ }, 1, player.toggle),
    awful.button({ }, 5, player.next_song),
    awful.button({ }, 4, player.prev_song)
  ))
-------------------------------------------------------------------------------
  function player.update()
    player.backend.update(parse_status_callback)
  end
-------------------------------------------------------------------------------
  function player.parse_status(player_status)
    player_status = tag_parser.predict_missing_tags(player_status)
    player.player_status = player_status

    local artist = ""
    local title = ""

    if player_status.state == "play" then
      -- playing
      artist = player_status.artist or "playing"
      title = player_status.title or " "
      player.widget:set_icon('music_on')
      if #artist + #title > 40 then
        if #artist > 15 then
          artist = h_string.max_length(artist, 15) .. "…"
        end
        if #player_status.title > 25 then
          title = h_string.max_length(title, 25) .. "…"
        end
      end
      artist = markup.fg.color(text_color, h_string.escape(artist))
      title = h_string.escape(title)
      -- playing new song
      if player_status.title ~= helpers.get_map("current player track") then
        helpers.set_map("current player track", player_status.title)
        player.resize_cover()
      end
    elseif player_status.state == "pause" then
      -- paused
      artist = "player"
      title  = "paused"
      helpers.set_map("current player track", nil)
      player.widget:set_icon('music')
    else
      -- stop
      player.widget:set_icon('music_off')
    end


    if player_status.state == "play" or player_status.state == "pause" then
      player.widget:set_bg(bg)
      player.widget:set_fg(fg)
      player.widget:set_markup(
        markup.font(font,
           " " ..
          (beautiful.panel_enbolden_details
            and markup.bold(artist)
            or artist)
          .. " " ..
          markup.fg.color(fg,
            title)
          .. " ")
      )
    else
      if beautiful.show_widget_icon then
        player.widget:set_icon('music')
      else
        player.widget:set_text('(m)')
      end
      player.widget:set_bg(fg)
      player.widget:set_fg(bg)
    end
  end
-------------------------------------------------------------------------------
function player.resize_cover()
  -- backend supports it:
  if player.backend.resize_cover then
    return player.backend.resize_cover(
      player.player_status, cover_size, player.cover, show_notification_callback
    )
  end
  -- fallback:
  local resize = string.format('%sx%s', cover_size, cover_size)
  if not player.player_status.cover then
    player.player_status.cover = default_art
  end
  async.execute(
    string.format(
      [[convert %q -thumbnail %q -gravity center -background "none" -extent %q %q]],
      player.player_status.cover,
      resize,
      resize,
      player.cover
    ),
    function(f) player.show_notification() end
  )
end
-------------------------------------------------------------------------------
  helpers.newtimer("player", update_interval, player.update)
  return setmetatable(player, { __index = player.widget })
end

return setmetatable(
  player,
  { __call = function(_, ...)
      return worker(...)
    end
  }
)
