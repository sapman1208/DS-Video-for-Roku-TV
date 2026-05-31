sub init()
      m.top.observeField("showData", "onShowDataSet")
      m.episodes = []
      m.viewMode = "episodes"
      m.seasons = []
      m.currentSeason = -1
      m.focusArea = "episodes"
      m.episodeFocusedIndex = 0
      m.lastKey = ""
      m.categories = []
      m.pendingNavIdx = -1
      nav = m.top.findNode("categoryList")
      nav.observeField("itemSelected", "onNavSelected")
      nav.observeField("itemFocused", "onNavFocused")
      nav.observeField("focus", "onNavFocus")
      m.top.observeField("focusNavCategory", "onFocusNavCategory")
      m.top.findNode("navLoadTimer").observeField("fire", "onNavLoadTimer")
      m.top.findNode("seasonGrid").observeField("itemSelected", "onSeasonSelected")
      m.top.findNode("seasonGrid").observeField("itemFocused", "onSeasonFocused")
      m.top.findNode("seasonGrid").observeField("focus", "onSeasonFocus")
      m.top.findNode("episodeGrid").observeField("itemSelected", "onEpisodeSelected")
      m.top.findNode("episodeGrid").observeField("itemFocused", "onEpisodeFocused")
      m.top.findNode("episodeGrid").observeField("focus", "onEpisodeFocus")
  end sub

  ' Safely read a string from multiple possible field names.
  ' Never calls cstr() — it only accepts numerics in BrightScript.
  ' Uses stri() for integers, str().trim() for floats.
  function safeStr(item as object, keys as object) as string
      for each k in keys
          v = item.lookUp(k)
          if v <> invalid
              t = type(v)
              if t = "roString" or t = "String" then return v
              if t = "roInteger" or t = "Integer" then return stri(v)
              if t = "roFloat" or t = "Float" then return stri(int(v))
          end if
      end for
      return ""
  end function

  function fileInfoFromItem(item as object) as object
      info = { id: invalid, path: "" }

      additional = item.lookUp("additional")
      if additional <> invalid
          fileList = additional.lookUp("file")
          if fileList <> invalid and fileList.count() > 0
              f = fileList[0]
              info.id = f.lookUp("id")
              p = f.lookUp("path")
              if p <> invalid then info.path = p
          end if
      end if

      if info.id = invalid or info.path = ""
          fileList = item.lookUp("file")
          if fileList <> invalid and fileList.count() > 0
              f = fileList[0]
              if info.id = invalid then info.id = f.lookUp("id")
              if info.path = ""
                  p = f.lookUp("path")
                  if p <> invalid then info.path = p
              end if
          end if
      end if

      return info
  end function

  sub onShowDataSet(event as object)
      showData = event.getData()
      if showData = invalid then return

      titleStr = showData.title
      if titleStr = invalid then titleStr = "TV Show"
      m.top.findNode("showTitle").text = titleStr

      authData = m.top.authData
      if authData = invalid then return
      loadNavCategories(authData)

      task = createObject("roSGNode", "APITask")
      task.request = {
          action: "listEpisodes",
          baseUrl: authData.baseUrl,
          proxyBaseUrl: authData.proxyBaseUrl,
          sid: authData.sid,
          synoToken: authData.synoToken,
          tvshowId: showData.id,
          tvshowIdCandidates: showData.idCandidates,
          showTitle: showData.title
      }
      task.observeField("response", "onEpisodesLoaded")
      task.control = "RUN"
      m.loadTask = task
  end sub

  sub onEpisodesLoaded(event as object)
      response = event.getData()
      loadingLbl = m.top.findNode("loadingLabel")
      if loadingLbl <> invalid then loadingLbl.visible = false

      if response = invalid or response.success <> true
          errLbl = m.top.findNode("errorLabel")
          if errLbl <> invalid then errLbl.text = "Could not load episodes."
          if errLbl <> invalid then errLbl.visible = true
          return
      end if

      episodes = response.items
      if episodes = invalid or episodes.count() = 0
          errLbl = m.top.findNode("errorLabel")
          msg = "No playable episodes found."
          if response.detail <> invalid and response.detail <> "" then msg = msg + chr(10) + left(response.detail, 1200)
          if errLbl <> invalid then errLbl.text = msg
          if errLbl <> invalid then errLbl.visible = true
          return
      end if

      m.episodes = episodes
      m.seasons = seasonsFromEpisodes(episodes)
      if m.seasons.count() > 0 then m.currentSeason = m.seasons[0]
      populateSeasonTabs()
      populateEpisodeGrid(episodes, m.currentSeason)
      startArtworkCache(episodes)
  end sub

  sub startArtworkCache(items as object)
      if items = invalid or items.count() = 0 then return
      m.top.artworkCacheRequest = {
          items: items,
          maxItems: 0,
          includeBackdrops: true,
          source: "episodes",
          nonce: createCacheNonce()
      }
  end sub

  function createCacheNonce() as string
      dt = createObject("roDateTime")
      stamp = stri(dt.asSeconds()).trim()
      randomPart = stri(rnd(1000000000)).trim()
      return stamp + "-" + randomPart
  end function

  sub populateSeasonTabs()
      grid = m.top.findNode("seasonGrid")
      content = createObject("roSGNode", "ContentNode")

      for each season in m.seasons
          node = content.createChild("ContentNode")
          if season > 0
              label = stri(season)
              node.title = label.trim()
          else
              node.title = "Specials"
          end if
          selectedValue = "false"
          if season = m.currentSeason then selectedValue = "true"
          node.addFields({ isSelectedSeason: selectedValue })
      end for

      grid.content = content
      grid.visible = true
  end sub

  sub populateEpisodeGrid(episodes as object, season as integer)
      m.viewMode = "episodes"
      m.currentSeason = season
      grid = m.top.findNode("episodeGrid")
      content = createObject("roSGNode", "ContentNode")
      showTitle = safeStr(m.top.showData, ["title", "name"])
      m.top.findNode("showTitle").text = showTitle
      idx = 0
      totalSeasonEpisodes = seasonEpisodeCount(season)

      for each ep in episodes
          if episodeSeason(ep) <> season then
              ' skip other seasons
          else
          node = content.createChild("ContentNode")

          en = episodeNumber(ep)
          epTitle = episodeDisplayTitle(ep)
          if en > 0
              epNum = stri(en)
              epNum = epNum.trim()
              lowerTitle = lcase(epTitle)
              if epTitle = "" or lowerTitle = "episode " + epNum or lowerTitle = "episode 0" + epNum
                  node.title = "Episode " + epNum
              else
                  node.title = epTitle
              end if
          else
              node.title = epTitle
          end if

          if en > 0
              epNum = stri(en)
              node.description = "Episode " + epNum.trim()
          else
              node.description = ""
          end if
          poster = posterUrl(ep, m.top.authData)
          if poster <> ""
              node.HDPosterUrl = poster
              node.SDPosterUrl = poster
          end if
          preventDown = "false"
          if idx + 3 >= totalSeasonEpisodes then preventDown = "true"
          preventUp = "false"
          if idx < 3 then preventUp = "true"
          node.addFields({
              preventWrapUp: preventUp,
              preventWrapDown: preventDown
          })
          idx = idx + 1
          end if
      end for

      grid.content = content
      grid.visible = true
      if m.keepSeasonFocus = true
          seasonGrid = m.top.findNode("seasonGrid")
          seasonGrid.jumpToItem = seasonIndex(season)
          seasonGrid.setFocus(true)
          m.focusArea = "seasons"
          m.keepSeasonFocus = false
      else
          seasonGrid = m.top.findNode("seasonGrid")
          seasonGrid.jumpToItem = seasonIndex(season)
          seasonGrid.setFocus(true)
          m.focusArea = "seasons"
      end if
  end sub

  function seasonEpisodeCount(season as integer) as integer
      count = 0
      for each ep in m.episodes
          if episodeSeason(ep) = season then count = count + 1
      end for
      return count
  end function

  sub onSeasonSelected(event as object)
      idx = event.getData()
      if idx < 0 or idx >= m.seasons.count() then return
      m.currentSeason = m.seasons[idx]
      m.keepSeasonFocus = true
      populateSeasonTabs()
      populateEpisodeGrid(m.episodes, m.currentSeason)
  end sub

  sub onSeasonFocused(event as object)
      idx = event.getData()
      if idx < 0 or idx >= m.seasons.count() then return
      season = m.seasons[idx]
      if season = m.currentSeason then return
      m.currentSeason = season
      m.keepSeasonFocus = true
      populateSeasonTabs()
      populateEpisodeGrid(m.episodes, m.currentSeason)
  end sub

  function seasonIndex(season as integer) as integer
      i = 0
      while i < m.seasons.count()
          if m.seasons[i] = season then return i
          i = i + 1
      end while
      return 0
  end function

  sub onSeasonFocus(event as object)
      if event.getData() = true then m.focusArea = "seasons"
  end sub

  sub onEpisodeFocus(event as object)
      if event.getData() = true then m.focusArea = "episodes"
  end sub

  sub onEpisodeFocused(event as object)
      idx = event.getData()
      if idx < 0 then return
      m.episodeFocusedIndex = idx
  end sub

  ' zeroPad works with both integer and string inputs safely
  function zeroPad(n as dynamic) as string
      if n = invalid then return "00"
      t = type(n)
      if t = "roString" or t = "String"
          nStr = n.trim()
      else if t = "roInteger" or t = "Integer"
          nStr = stri(n)
          nStr = nStr.trim()
      else if t = "roFloat" or t = "Float"
          nStr = stri(int(n))
          nStr = nStr.trim()
      else
          return "00"
      end if
      if nStr.len() < 2 then return "0" + nStr
      return nStr
  end function

  function seasonsFromEpisodes(episodes as object) as object
      seasons = []
      for each ep in episodes
          s = episodeSeason(ep)
          found = false
          for each existing in seasons
              if existing = s then found = true
          end for
          if not found then seasons.push(s)
      end for

      sorted = []
      for each s in seasons
          sorted.push(s)
      end for

      i = 0
      while i < sorted.count()
          j = i + 1
          while j < sorted.count()
              if sorted[j] < sorted[i]
                  tmp = sorted[i]
                  sorted[i] = sorted[j]
                  sorted[j] = tmp
              end if
              j = j + 1
          end while
          i = i + 1
      end while
      return sorted
  end function

  function episodeSeason(ep as object) as integer
      value = firstNumber(ep, ["seasonText", "seasonNumber", "season_number", "season", "season_num", "season_index"])
      if value > 0 then return value
      info = episodeInfoFromEpisode(ep)
      return info.season
  end function

  function episodeNumber(ep as object) as integer
      value = firstNumber(ep, ["episodeText", "episodeNumber", "episode_number", "episode", "episode_num", "ep_num", "ep_index"])
      if value > 0 then return value
      info = episodeInfoFromEpisode(ep)
      return info.episode
  end function

  function firstNumber(item as object, keys as object) as integer
      for each k in keys
          v = item.lookUp(k)
          n = numberValue(v)
          if n > 0 then return n
      end for
      return 0
  end function

  function episodeInfoFromEpisode(ep as object) as object
      fileInfo = fileInfoFromItem(ep)
      if fileInfo.path <> "" then return episodeInfoFromPath(fileInfo.path)
      title = safeStr(ep, ["title", "name"])
      return episodeInfoFromPath(title)
  end function

  function episodeDisplayTitle(ep as object) as string
      title = cleanEpisodeTitle(safeStr(ep, ["title", "name"]))
      showTitle = cleanEpisodeTitle(safeStr(m.top.showData, ["title", "name"]))
      info = episodeInfoFromEpisode(ep)

      if info.title <> invalid and info.title <> ""
          fallback = cleanEpisodeTitle(info.title)
          if title = "" or isReleaseTitle(title) or isGenericEpisodeTitle(title) or lcase(title) = lcase(showTitle)
              title = fallback
          end if
      end if

      if title = "" and info.episode > 0
          episodeLabel = stri(info.episode)
          title = "Episode " + episodeLabel.trim()
      end if
      return title
  end function

  function episodeInfoFromPath(path as string) as object
      name = baseNameNoExt(path)
      lower = lcase(name)
      season = 0
      episode = 0
      markerEnd = 0

      idx = 1
      while idx <= len(lower) - 5
          if mid(lower, idx, 1) = "s" and mid(lower, idx + 3, 1) = "e"
              season = int(val(mid(lower, idx + 1, 2)))
              episode = int(val(mid(lower, idx + 4, 2)))
              if season > 0 or episode > 0
                  markerEnd = idx + 5
                  idx = len(lower)
              end if
          else if mid(lower, idx, 1) = "s" and mid(lower, idx + 4, 1) = "e"
              season = int(val(mid(lower, idx + 1, 2)))
              episode = int(val(mid(lower, idx + 5, 2)))
              if season > 0 or episode > 0
                  markerEnd = idx + 6
                  idx = len(lower)
              end if
          end if
          idx = idx + 1
      end while

      if markerEnd = 0
          idx = 1
          while idx <= len(lower) - 3
              ch = mid(lower, idx, 1)
              code = asc(ch)
              if code >= 48 and code <= 57 and mid(lower, idx + 2, 1) = "x"
                  season = int(val(ch))
                  episode = int(val(mid(lower, idx + 3, 2)))
                  if season > 0 or episode > 0
                      markerEnd = idx + 4
                      idx = len(lower)
                  end if
              end if
              idx = idx + 1
          end while
      end if

      title = name
      if markerEnd > 0 and markerEnd < len(name) then title = mid(name, markerEnd + 1)
      title = cleanEpisodeTitle(title)
      if title = "" and episode > 0
          episodeLabel = stri(episode)
          title = "Episode " + episodeLabel.trim()
      end if

      return { season: season, episode: episode, title: title }
  end function

  function cleanEpisodeTitle(value as string) as string
      out = ""
      lastSpace = false
      idx = 1
      while idx <= len(value)
          ch = mid(value, idx, 1)
          if ch = "." or ch = "_" or ch = "-" then ch = " "
          if ch = " "
              if not lastSpace
                  out = out + ch
                  lastSpace = true
              end if
          else
              out = out + ch
              lastSpace = false
          end if
          idx = idx + 1
      end while

      cleaned = out.trim()
      lower = lcase(cleaned)
      cutStartTokens = ["2160p", "1080p", "720p", "480p", "hdtv", "webrip", "web dl", "web ", "hevc", "x265", "x264", "xvid", "h264", "internal", "proper", "repack", "eztv", "["]
      for each token in cutStartTokens
          if left(lower, len(token)) = token then return ""
      end for
      cutTokens = [" 2160p", " 1080p", " 720p", " 480p", " hdtv", " webrip", " web dl", " web ", " hevc", " x265", " x264", " xvid", " h264", " internal", " proper", " repack", " eztv", "["]
      cutAt = 0
      for each token in cutTokens
          tokenPos = instr(1, lower, token)
          if tokenPos > 0 and (cutAt = 0 or tokenPos < cutAt) then cutAt = tokenPos
      end for
      if cutAt > 0
          cleaned = left(cleaned, cutAt - 1)
          cleaned = cleaned.trim()
      end if
      return cleaned
  end function

  function isReleaseTitle(value as string) as boolean
      lower = lcase(value)
      tokens = [" 2160p", " 1080p", " 720p", " 480p", " hdtv", " webrip", " web dl", " hevc", " x265", " x264", " xvid", " h264", " internal", " proper", " repack"]
      for each token in tokens
          if instr(1, lower, token) > 0 then return true
      end for
      return false
  end function

  function isGenericEpisodeTitle(value as string) as boolean
      lower = lcase(value)
      if left(lower, 8) <> "episode " then return false
      rest = mid(lower, 9)
      if rest = "" then return false
      idx = 1
      while idx <= len(rest)
          code = asc(mid(rest, idx, 1))
          if code < 48 or code > 57 then return false
          idx = idx + 1
      end while
      return true
  end function

  function baseNameNoExt(path as string) as string
      name = path
      lastSlash = 0
      idx = 1
      while idx <= len(path)
          if mid(path, idx, 1) = "/" then lastSlash = idx
          idx = idx + 1
      end while
      if lastSlash > 0 then name = mid(path, lastSlash + 1)
      lname = lcase(name)
      extensions = [".mkv", ".mp4", ".avi", ".m4v", ".mov", ".webm", ".m2ts"]
      for each ext in extensions
          if right(lname, len(ext)) = ext then return left(name, len(name) - len(ext))
      end for
      return name
  end function

  function isZeroEpisode(sn as dynamic, en as dynamic) as boolean
      return numberValue(sn) = 0 and numberValue(en) = 0
  end function

  function numberValue(n as dynamic) as integer
      if n = invalid then return -1
      t = type(n)
      if t = "roInteger" or t = "Integer" then return n
      if t = "roFloat" or t = "Float" then return int(n)
      if t = "roString" or t = "String" then return int(val(n))
      return -1
  end function

  sub onEpisodeSelected(event as object)
      idx = event.getData()
      seasonEpisodes = []
      for each epItem in m.episodes
          if episodeSeason(epItem) = m.currentSeason then seasonEpisodes.push(epItem)
      end for

      if idx < 0 or idx >= seasonEpisodes.count() then return

      ep = seasonEpisodes[idx]
      authData = m.top.authData

      epId = ep.lookUp("id")
      if epId = invalid then epId = "0"

      fileInfo = fileInfoFromItem(ep)
      rawFileId = fileInfo.id
      if rawFileId = invalid then rawFileId = epId
      epNumber = episodeNumber(ep)
      if epNumber <= 0 then epNumber = idx + 1
      seasonNumber = episodeSeason(ep)
      episodeMeta = "Episode"
      if seasonNumber > 0 and epNumber > 0
          episodeMeta = "Season " + stri(seasonNumber).trim() + " - Episode " + stri(epNumber).trim()
      else if epNumber > 0
          episodeMeta = "Episode " + stri(epNumber).trim()
      end if

      m.top.selectedVideo = {
          type: "episode",
          id: epId,
          fileId: rawFileId,
          mapperId: ep.lookUp("mapper_id"),
          showMapperId: m.top.showData.lookUp("mapperId"),
          filePath: fileInfo.path,
          seasonNumber: seasonNumber,
          episodeNumber: epNumber,
          episodeMeta: episodeMeta,
          title: safeStr(ep, ["title", "name"]),
          summary: safeStr(ep, ["summary", "description", "tagline"]),
          posterUrl: posterUrl(ep, authData),
          posterRemoteUrl: safeStr(ep, ["posterRemoteUrl"]),
          backdropUrl: showBackdropUrl(authData),
          backdropRemoteUrl: safeStr(m.top.showData, ["backdropRemoteUrl"]),
          authData: authData
      }
  end sub

  function onKeyEvent(key as string, press as boolean) as boolean
      if not press then return false
      m.lastKey = key
      if key = "up" and m.focusArea = "seasons"
          m.top.findNode("categoryList").setFocus(true)
          m.focusArea = "nav"
          return true
      end if
      if key = "up" and m.focusArea = "episodes" and m.episodeFocusedIndex < 3
          m.top.findNode("seasonGrid").setFocus(true)
          m.focusArea = "seasons"
          return true
      end if
      if key = "down" and m.focusArea = "nav"
          m.top.findNode("seasonGrid").setFocus(true)
          m.focusArea = "seasons"
          return true
      end if
      if key = "down" and m.focusArea = "seasons"
          m.top.findNode("episodeGrid").setFocus(true)
          m.focusArea = "episodes"
          return true
      end if
      if key = "back"
          m.top.backPressed = true
          return true
      end if
      return false
  end function

  function posterUrl(item as object, authData as dynamic) as string
	      savedPoster = item.lookUp("posterUrl")
	      if savedPoster <> invalid and savedPoster <> "" then return savedPoster
	      if authData = invalid then return ""
	      proxyBase = authData.proxyBaseUrl
	      if proxyBase <> invalid and proxyBase <> ""
	          mapperId = item.lookUp("mapper_id")
	          if mapperId = invalid then mapperId = item.lookUp("id")
	          mapper = safeStr({ value: mapperId }, ["value"])
	          mapper = mapper.trim()
		          if mapper <> "" and mapper <> "0"
		              fallback = showMapperId()
		              if fallback <> "" and fallback <> "0" then return proxyBase + "/poster?mapper_id=" + mapper + "&fallback_mapper_id=" + fallback + "&format=jpg"
		              return proxyBase + "/poster?mapper_id=" + mapper + "&format=jpg"
		          end if
	      end if
	      return synologyEpisodePosterUrl(item, authData)
	  end function

  function synologyEpisodePosterUrl(item as object, authData as dynamic) as string
      if authData = invalid then return ""
      baseUrl = authData.baseUrl
      sid = authData.sid
      if baseUrl = invalid or baseUrl = "" or sid = invalid or sid = "" then return ""
      id = safeStr(item, ["id"])
      id = id.trim()
      if id = "" or id = "0" then return ""
      return baseUrl + "/webapi/VideoStation/poster.cgi?api=SYNO.VideoStation.Poster&version=2&method=getimage&_sid=" + sid + "&id=" + id + "&type=tvshow_episode&poster_mtime=" + posterMtime(item)
  end function

  function posterMtime(item as object) as string
      mtime = safeStr(item, ["poster_mtime", "posterMtime"])
      if mtime <> "" then return mtime.trim()
      additional = item.lookUp("additional")
      if additional <> invalid
          mtime = safeStr(additional, ["poster_mtime", "posterMtime"])
          if mtime <> "" then return mtime.trim()
      end if
      return ""
  end function

  function showBackdropUrl(authData as dynamic) as string
      if m.top.showData <> invalid
          savedBackdrop = m.top.showData.lookUp("backdropUrl")
          if savedBackdrop <> invalid and savedBackdrop <> "" then return savedBackdrop
      end if
      if authData = invalid then return ""
      proxyBase = authData.proxyBaseUrl
      if proxyBase = invalid or proxyBase = "" then return ""
	      mapper = showMapperId()
	      if mapper = "" or mapper = "0" then return ""
	      return proxyBase + "/backdrop?mapper_id=" + mapper + "&format=jpg"
	  end function

	  function showMapperId() as string
	      if m.top.showData = invalid then return ""
	      mapperId = m.top.showData.lookUp("mapperId")
	      if mapperId = invalid then mapperId = m.top.showData.lookUp("mapper_id")
	      mapper = safeStr({ value: mapperId }, ["value"])
	      return mapper.trim()
	  end function

  sub onNavFocus(event as object)
      if event.getData() = true then m.focusArea = "nav"
  end sub

  sub onNavSelected(event as object)
      idx = event.getData()
      if idx >= 0 and idx < m.categories.count() then m.top.selectedCategory = categoryPayload(idx)
  end sub

  sub onNavFocused(event as object)
      ' Moving across the nav should only move focus. Press OK to load a library.
  end sub

  sub onNavLoadTimer(event as object)
      ' Kept for older component XML; nav selection is now OK-only.
  end sub

  function categoryPayload(idx as integer) as object
      return {
          category: m.categories[idx].category,
          title: m.categories[idx].title,
          libraryId: m.categories[idx].lookUp("libraryId")
      }
  end function

  sub loadNavCategories(authData as object)
      if m.categories.count() > 0 then return
      if m.top.navCategories <> invalid and m.top.navCategories.count() > 0
          m.categories = m.top.navCategories
          populateNavCategories()
          return
      end if
      task = createObject("roSGNode", "APITask")
      task.request = {
          action: "listLibraries",
          baseUrl: authData.baseUrl,
          proxyBaseUrl: authData.proxyBaseUrl,
          sid: authData.sid,
          synoToken: authData.synoToken
      }
      task.observeField("response", "onNavLoaded")
      task.control = "RUN"
      m.navTask = task
  end sub

  sub onNavLoaded(event as object)
      response = event.getData()
      if response = invalid or response.success <> true then return
      items = response.items
      if items = invalid then return
      m.categories = orderedCategories(items)
      m.categories.push({ title: "Settings", category: "settings", desc: "Edit NAS login and transcode settings" })
      populateNavCategories()
  end sub

  sub populateNavCategories()
      contentNode = createObject("roSGNode", "ContentNode")
      for each cat in m.categories
          item = contentNode.createChild("ContentNode")
          item.title = cat.title
      end for
      nav = m.top.findNode("categoryList")
      nav.content = contentNode
      nav.numColumns = m.categories.count()
      focusActiveNav()
  end sub

  sub focusActiveNav()
      nav = m.top.findNode("categoryList")
      activeIdx = activeCategoryIndex()
      if activeIdx >= 0 then nav.jumpToItem = activeIdx
      nav.setFocus(true)
      m.focusArea = "nav"
  end sub

  sub onFocusNavCategory(event as object)
      if event.getData() = "settings"
          nav = m.top.findNode("categoryList")
          idx = m.categories.count() - 1
          if idx >= 0 then nav.jumpToItem = idx
          nav.setFocus(true)
          m.focusArea = "nav"
      end if
  end sub

  function activeCategoryIndex() as integer
      i = 0
      activeLibrary = invalid
      if m.top.showData <> invalid then activeLibrary = m.top.showData.lookUp("libraryId")
      while i < m.categories.count()
          cat = m.categories[i]
          if cat.lookUp("category") = "tvshows"
              catLibrary = cat.lookUp("libraryId")
              if activeLibrary <> invalid and activeLibrary <> "" and activeLibrary = catLibrary then return i
          end if
          i = i + 1
      end while
      i = 0
      while i < m.categories.count()
          cat = m.categories[i]
          if cat.lookUp("category") = "tvshows"
              catLibrary = cat.lookUp("libraryId")
              if activeLibrary = invalid or activeLibrary = "" or catLibrary = invalid or catLibrary = "" then return i
          end if
          i = i + 1
      end while
      return -1
  end function

  function orderedCategories(items as object) as object
      ordered = []
      addCategoryByTitle(ordered, items, "Movie")
      addCategoryByTitle(ordered, items, "TV Show")
      addCategoryByTitle(ordered, items, "Home Video")
      addCategoryByTitle(ordered, items, "Ian's Shows")
      for each item in items
          title = item.lookUp("title")
          if title <> invalid and title <> "Settings"
              exists = false
              for each existing in ordered
                  if existing.lookUp("title") = title then exists = true
              end for
              if not exists then ordered.push(item)
          end if
      end for
      return ordered
  end function

  sub addCategoryByTitle(target as object, items as object, wanted as string)
      for each item in items
          title = item.lookUp("title")
          if title <> invalid and lcase(title) = lcase(wanted)
              target.push(item)
              return
          end if
      end for
  end sub
  
