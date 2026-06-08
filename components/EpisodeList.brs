sub init()
      m.top.observeField("showData", "onShowDataSet")
      m.episodes = []
      m.viewMode = "episodes"
      m.seasons = []
      m.currentSeason = -1
      m.focusArea = "seasons"
      m.episodeFocusedIndex = 0
      m.lastKey = ""
      m.categories = []
      m.pendingNavIdx = -1
      m.posterRetryAttempts = {}
      m.posterRetryQueue = []
      m.posterRetryCursor = 0
      nav = m.top.findNode("categoryList")
      nav.observeField("itemSelected", "onNavSelected")
      nav.observeField("itemFocused", "onNavFocused")
      nav.observeField("focus", "onNavFocus")
      m.top.observeField("navCategories", "onNavCategoriesSet")
      m.top.observeField("focusNavCategory", "onFocusNavCategory")
      m.top.observeField("refreshArtwork", "onRefreshArtwork")
      m.top.observeField("playbackFocusVideo", "onPlaybackFocusVideo")
      m.top.findNode("navLoadTimer").observeField("fire", "onNavLoadTimer")
      m.top.findNode("posterRetryTimer").observeField("fire", "onPosterRetryTimer")
      m.top.findNode("initialPosterRetryTimer").observeField("fire", "onInitialPosterRetryTimer")
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
              if t = "roInteger" or t = "Integer" or t = "roInt" or t = "roLongInteger" or t = "LongInteger" then return stri(v)
              if t = "roFloat" or t = "Float" or t = "roDouble" or t = "Double" then return stri(int(v))
          end if
      end for
      return ""
  end function

  function fileInfoFromItem(item as object) as object
      info = { id: invalid, path: "", watched: invalid }

      additional = item.lookUp("additional")
      if additional <> invalid
          fileList = additional.lookUp("file")
          if fileList <> invalid and fileList.count() > 0
              f = fileList[0]
              info.id = f.lookUp("id")
              info.watched = f.lookUp("file_watched")
              if info.watched = invalid then info.watched = f.lookUp("watched")
              p = f.lookUp("path")
              if p <> invalid then info.path = p
          end if
      end if

      if info.id = invalid or info.path = ""
          fileList = item.lookUp("file")
          if fileList <> invalid and fileList.count() > 0
              f = fileList[0]
              if info.id = invalid then info.id = f.lookUp("id")
              if info.watched = invalid
                  info.watched = f.lookUp("file_watched")
                  if info.watched = invalid then info.watched = f.lookUp("watched")
              end if
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
      refreshActiveNav()

      task = createObject("roSGNode", "APITask")
      task.request = {
          action: "listEpisodes",
          baseUrl: authData.baseUrl,
          proxyBaseUrl: authData.proxyBaseUrl,
          sid: authData.sid,
          synoToken: authData.synoToken,
          tvshowId: showData.id,
          tvshowIdCandidates: showData.idCandidates,
          libraryId: showData.libraryId,
          sourceLibraryTitle: showData.sourceLibraryTitle,
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

      episodes = sortEpisodesForAutoplay(episodes)
      m.episodes = episodes
      m.top.episodeItems = episodes
      resetPosterRetryState()
      m.seasons = seasonsFromEpisodes(episodes)
      if m.seasons.count() > 0 then m.currentSeason = initialSeason(m.seasons)
      populateSeasonTabs()
      populateEpisodeGrid(episodes, m.currentSeason)
      startInitialSeasonPosterRetryTimer()
  end sub

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
          dateText = episodeDateText(ep)
          if dateText <> "" then node.addFields({ episodeDate: dateText })
          if shouldAssignEpisodePosterInitially(idx)
              poster = posterUrl(ep, m.top.authData)
              if poster <> ""
                  print "ARTWORK_PICK surface=episode-grid category=episodes source="; episodePosterSource(ep, m.top.authData); " title="; episodeDisplayTitle(ep); " id="; safeStr(ep, ["id", "posterId", "videoStationId"]); " mapper="; safeStr(ep, ["mapper_id", "mapperId"])
                  ep.addReplace("posterRemoteUrl", poster)
                  ep.addReplace("posterUrl", poster)
                  node.HDPosterUrl = episodeArtworkUrlForGrid(poster)
                  node.SDPosterUrl = node.HDPosterUrl
              end if
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

  function shouldAssignEpisodePosterInitially(idx as integer) as boolean
      return true
  end function

  function episodeArtworkUrlForGrid(url as string) as string
      if not isHttpUrl(url) then return url
      sep = "?"
      if instr(1, url, "?") > 0 then sep = "&"
      seasonText = stri(m.currentSeason)
      return url + sep + "roku_season_view=" + seasonText.trim()
  end function

  sub onRefreshArtwork(event as object)
      if event = invalid then return
      if m.episodes = invalid or m.episodes.count() = 0 then return
      grid = m.top.findNode("episodeGrid")
      previousFocusArea = m.focusArea
      focused = m.episodeFocusedIndex
      if grid <> invalid and grid.itemFocused >= 0 then focused = grid.itemFocused
      populateEpisodeGrid(m.episodes, m.currentSeason)
      if previousFocusArea = "episodes" and grid <> invalid and focused >= 0
          grid.jumpToItem = focused
          grid.setFocus(true)
          m.focusArea = "episodes"
      else if previousFocusArea = "nav"
          nav = m.top.findNode("categoryList")
          if nav <> invalid then nav.setFocus(true)
          m.focusArea = "nav"
      else
          seasonGrid = m.top.findNode("seasonGrid")
          if seasonGrid <> invalid
              seasonGrid.jumpToItem = seasonIndex(m.currentSeason)
              seasonGrid.setFocus(true)
          end if
          m.focusArea = "seasons"
      end if
  end sub

  sub onPlaybackFocusVideo(event as object)
      videoData = event.getData()
      if videoData = invalid or m.episodes = invalid or m.episodes.count() = 0 then return
      targetSeason = numberValue(videoData.lookUp("seasonNumber"))
      targetEpisode = numberValue(videoData.lookUp("episodeNumber"))
      resolved = playbackFocusTarget(videoData)
      resolvedIdx = -1
      if resolved <> invalid
          targetSeason = resolved.season
          resolvedIdx = resolved.idx
      end if
      if targetSeason < 0 then targetSeason = m.currentSeason
      if targetSeason <> m.currentSeason
          m.currentSeason = targetSeason
          populateSeasonTabs()
          populateEpisodeGrid(m.episodes, m.currentSeason)
      end if

      seasonEpisodes = episodesForCurrentSeason()
      idx = resolvedIdx
      if idx < 0 then idx = episodeIndexForVideo(videoData, seasonEpisodes)
      if idx < 0 and targetEpisode > 0
          scan = 0
          while scan < seasonEpisodes.count()
              if episodeNumber(seasonEpisodes[scan]) = targetEpisode then idx = scan
              scan = scan + 1
          end while
      end if
      if idx < 0 then return

      grid = m.top.findNode("episodeGrid")
      if grid <> invalid
          m.episodeFocusedIndex = idx
          grid.jumpToItem = idx
          grid.setFocus(true)
          m.focusArea = "episodes"
      end if
  end sub

  function playbackFocusTarget(videoData as object) as dynamic
      if videoData = invalid then return invalid
      targetKey = episodeVideoKey(videoData)
      targetTitle = lcase(safeStr(videoData, ["title", "name"]))
      for each season in m.seasons
          seasonEpisodes = episodesForSeason(season)
          idx = 0
          while idx < seasonEpisodes.count()
              ep = seasonEpisodes[idx]
              matched = false
              if targetKey <> "" and episodeRawKey(ep) = targetKey then matched = true
              if not matched and targetTitle <> ""
                  epTitle = lcase(episodeDisplayTitle(ep))
                  rawTitle = lcase(safeStr(ep, ["title", "name"]))
                  if epTitle = targetTitle or rawTitle = targetTitle then matched = true
              end if
              if matched then return { season: season, idx: idx }
              idx = idx + 1
          end while
      end for
      return invalid
  end function

  function episodesForSeason(season as integer) as object
      seasonEpisodes = []
      for each ep in m.episodes
          if episodeSeason(ep) = season then seasonEpisodes.push(ep)
      end for
      return seasonEpisodes
  end function

  function episodeIndexForVideo(videoData as object, seasonEpisodes as object) as integer
      if videoData = invalid or seasonEpisodes = invalid then return -1
      targetKey = episodeVideoKey(videoData)
      idx = 0
      while idx < seasonEpisodes.count()
          candidate = seasonEpisodes[idx]
          if episodeRawKey(candidate) = targetKey then return idx
          idx = idx + 1
      end while
      return -1
  end function

  function episodeRawKey(ep as object) as string
      if ep = invalid then return ""
      fileInfo = fileInfoFromItem(ep)
      if fileInfo.path <> invalid and fileInfo.path <> "" then return "path:" + fileInfo.path
      if fileInfo.id <> invalid and fileInfo.id <> "" then return "file:" + safeStr({ value: fileInfo.id }, ["value"])
      epId = ep.lookUp("id")
      if epId <> invalid and epId <> "" then return "id:" + safeStr({ value: epId }, ["value"])
      return "se:" + stri(episodeSeason(ep)).trim() + "x" + stri(episodeNumber(ep)).trim()
  end function

  function episodeVideoKey(item as object) as string
      if item = invalid then return ""
      if item.filePath <> invalid and item.filePath <> "" then return "path:" + item.filePath
      if item.fileId <> invalid and item.fileId <> "" then return "file:" + safeStr({ value: item.fileId }, ["value"])
      if item.id <> invalid and item.id <> "" then return "id:" + safeStr({ value: item.id }, ["value"])
      return "se:" + safeStr({ value: item.seasonNumber }, ["value"]) + "x" + safeStr({ value: item.episodeNumber }, ["value"])
  end function

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
      resetPosterRetryState()
      m.episodeFocusedIndex = 0
      populateEpisodeGrid(m.episodes, m.currentSeason)
      startInitialSeasonPosterRetryTimer()
  end sub

  sub onSeasonFocused(event as object)
      idx = event.getData()
      if idx < 0 or idx >= m.seasons.count() then return
      season = m.seasons[idx]
      if season = m.currentSeason then return
      m.currentSeason = season
      m.keepSeasonFocus = true
      resetPosterRetryState()
      m.episodeFocusedIndex = 0
      populateEpisodeGrid(m.episodes, m.currentSeason)
      startInitialSeasonPosterRetryTimer()
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
      scheduleSeasonPosterRetry()
  end sub

  sub scheduleSeasonPosterRetry()
      seasonEpisodes = episodesForCurrentSeason()
      if seasonEpisodes.count() = 0 then return

      cols = 3
      focused = m.episodeFocusedIndex
      if focused < 0 then focused = 0
      row = int(focused / cols)
      startRow = row - 3
      endRow = row + 3
      if startRow < 0 then startRow = 0
      maxRow = int((seasonEpisodes.count() - 1) / cols)
      if endRow > maxRow then endRow = maxRow

      startIdx = startRow * cols
      endIdx = ((endRow + 1) * cols) - 1
      if endIdx >= seasonEpisodes.count() then endIdx = seasonEpisodes.count() - 1

      i = startIdx
      while i <= endIdx
          enqueueEpisodePosterRetry(i, seasonEpisodes)
          i = i + 1
      end while
      timer = m.top.findNode("posterRetryTimer")
      if timer = invalid then return
      if m.posterRetryQueue.count() > 0
          retryNextEpisodePosterBatch()
          if m.posterRetryQueue.count() > 0 then timer.control = "start"
      end if
  end sub

  sub startInitialSeasonPosterRetryTimer()
      timer = m.top.findNode("initialPosterRetryTimer")
      if timer = invalid then return
      timer.control = "stop"
      timer.control = "start"
  end sub

  sub onInitialPosterRetryTimer(event as object)
      if event = invalid then return
      scheduleSeasonPosterRetry()
  end sub

  sub resetPosterRetryState()
      timer = m.top.findNode("posterRetryTimer")
      if timer <> invalid then timer.control = "stop"
      m.posterRetryAttempts = {}
      m.posterRetryQueue = []
      m.posterRetryCursor = 0
  end sub

  sub stopEpisodeArtworkTimers()
      timer = m.top.findNode("posterRetryTimer")
      if timer <> invalid then timer.control = "stop"
      timer = m.top.findNode("initialPosterRetryTimer")
      if timer <> invalid then timer.control = "stop"
      m.posterRetryQueue = []
  end sub

  sub enqueueEpisodePosterRetry(idx as integer, seasonEpisodes as object)
      if not episodeArtworkNeedsRetry(idx, seasonEpisodes) then return
      key = episodeAttemptKey(idx)
      attempts = 0
      existing = m.posterRetryAttempts.lookUp(key)
      if existing <> invalid then attempts = existing
      if attempts >= maxEpisodePosterRetryAttempts() then return
      if not episodeQueueContains(idx) then m.posterRetryQueue.push(idx)
  end sub

  function episodeQueueContains(idx as integer) as boolean
      for each queuedIdx in m.posterRetryQueue
          if queuedIdx = idx then return true
      end for
      return false
  end function

  sub onPosterRetryTimer(event as object)
      if event = invalid then return
      retryNextEpisodePosterBatch()
  end sub

  sub retryNextEpisodePosterBatch()
      timer = m.top.findNode("posterRetryTimer")
      if m.posterRetryQueue = invalid or m.posterRetryQueue.count() = 0
          if timer <> invalid then timer.control = "stop"
          return
      end if
      seasonEpisodes = episodesForCurrentSeason()
      batchSize = 4
      processed = 0
      while processed < batchSize and m.posterRetryQueue.count() > 0
          idx = m.posterRetryQueue[0]
          if episodeArtworkNeedsRetry(idx, seasonEpisodes)
              key = episodeAttemptKey(idx)
              attempts = 0
              existing = m.posterRetryAttempts.lookUp(key)
              if existing <> invalid then attempts = existing
              if attempts >= maxEpisodePosterRetryAttempts()
                  m.posterRetryQueue.delete(0)
              else
                  attempts = attempts + 1
                  m.posterRetryAttempts.addReplace(key, attempts)
                  retryEpisodePosterForIndex(idx, seasonEpisodes, attempts)
                  m.posterRetryQueue.delete(0)
                  if attempts < maxEpisodePosterRetryAttempts() then m.posterRetryQueue.push(idx)
                  processed = processed + 1
              end if
          else
              m.posterRetryQueue.delete(0)
          end if
      end while
      if m.posterRetryQueue.count() = 0 and timer <> invalid then timer.control = "stop"
  end sub

  function episodeAttemptKey(idx as integer) as string
      return stri(m.currentSeason).trim() + ":" + stri(idx).trim()
  end function

  function maxEpisodePosterRetryAttempts() as integer
      return 1
  end function

  function episodeArtworkNeedsRetry(idx as integer, seasonEpisodes as object) as boolean
      grid = m.top.findNode("episodeGrid")
      if grid = invalid or grid.content = invalid then return false
      node = grid.content.getChild(idx)
      if node = invalid then return false
      if node.hasField("artworkLoaded") and node.artworkLoaded = "true" then return false
      nodePoster = ""
      if node.HDPosterUrl <> invalid then nodePoster = node.HDPosterUrl
      if isLocalArtworkUrl(nodePoster) then return false

      if idx < 0 or idx >= seasonEpisodes.count() then return false
      ep = seasonEpisodes[idx]
      baseUrl = remotePosterUrl(ep, m.top.authData)
      return isHttpUrl(baseUrl)
  end function

  sub retryEpisodePosterForIndex(idx as integer, seasonEpisodes as object, attempt as integer)
      if idx < 0 or idx >= seasonEpisodes.count() then return
      grid = m.top.findNode("episodeGrid")
      if grid = invalid or grid.content = invalid then return
      node = grid.content.getChild(idx)
      if node = invalid then return
      if node.hasField("artworkLoaded") and node.artworkLoaded = "true" then return
      ep = seasonEpisodes[idx]
      baseUrl = remotePosterUrl(ep, m.top.authData)
      if not isHttpUrl(baseUrl) then return
      retryUrl = artworkRetryUrl(baseUrl, attempt)
      print "ARTWORK_PICK surface=episode-retry category=episodes source="; episodePosterSource(ep, m.top.authData); " title="; safeStr(ep, ["title", "name"]); " id="; safeStr(ep, ["id", "posterId", "videoStationId"]); " mapper="; safeStr(ep, ["mapper_id", "mapperId"])
      node.HDPosterUrl = retryUrl
      node.SDPosterUrl = retryUrl
  end sub

  function episodesForCurrentSeason() as object
      seasonEpisodes = []
      for each ep in m.episodes
          if episodeSeason(ep) = m.currentSeason then seasonEpisodes.push(ep)
      end for
      return seasonEpisodes
  end function

  ' zeroPad works with both integer and string inputs safely
  function zeroPad(n as dynamic) as string
      if n = invalid then return "00"
      t = type(n)
      if t = "roString" or t = "String"
          nStr = n.trim()
      else if t = "roInteger" or t = "Integer" or t = "roInt" or t = "roLongInteger" or t = "LongInteger"
          nStr = stri(n)
          nStr = nStr.trim()
      else if t = "roFloat" or t = "Float" or t = "roDouble" or t = "Double"
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

  function initialSeason(seasons as object) as integer
      if seasons = invalid or seasons.count() = 0 then return 0
      for each season in seasons
          if season = 1 then return 1
      end for
      for each season in seasons
          if season > 0 then return season
      end for
      return seasons[0]
  end function

  function episodeSeason(ep as object) as integer
      value = firstNumber(ep, ["seasonText", "seasonNumber", "season_number", "season", "season_num", "season_index"])
      if value > 0 then return value
      info = episodeInfoFromEpisode(ep)
      if info.season > 0
          ep.addReplace("season", info.season)
          ep.addReplace("season_number", info.season)
          ep.addReplace("seasonNumber", info.season)
      end if
      return info.season
  end function

  function episodeNumber(ep as object) as integer
      value = firstNumber(ep, ["episodeText", "episodeNumber", "episode_number", "episode", "episode_num", "ep_num", "ep_index"])
      if value > 0 then return value
      info = episodeInfoFromEpisode(ep)
      if info.episode > 0
          ep.addReplace("episode", info.episode)
          ep.addReplace("episode_number", info.episode)
          ep.addReplace("episodeNumber", info.episode)
      end if
      return info.episode
  end function

  function firstNumber(item as object, keys as object) as integer
      for each k in keys
          v = item.lookUp(k)
          n = numberValue(v)
          if n > 0 then return n
      end for
      additional = item.lookUp("additional")
      if additional <> invalid
          for each k in keys
              v = additional.lookUp(k)
              n = numberValue(v)
              if n > 0 then return n
          end for
      end if
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
      if t = "roInteger" or t = "Integer" or t = "roInt" or t = "roLongInteger" or t = "LongInteger" or t = "roInt" or t = "roLongInteger" or t = "LongInteger" then return int(n)
      if t = "roFloat" or t = "Float" or t = "roDouble" or t = "Double" or t = "roDouble" or t = "Double" then return int(n)
      if t = "roString" or t = "String" then return int(val(n))
      return -1
  end function

  sub onEpisodeSelected(event as object)
      idx = event.getData()
      stopEpisodeArtworkTimers()
      seasonEpisodes = []
      for each epItem in m.episodes
          if episodeSeason(epItem) = m.currentSeason then seasonEpisodes.push(epItem)
      end for

      if idx < 0 or idx >= seasonEpisodes.count() then return

      ep = seasonEpisodes[idx]
      authData = m.top.authData
      selected = episodeVideoPayload(ep, authData, idx)
      m.top.selectedVideo = selected
  end sub

  function autoplayEpisodeList(authData as object) as object
      playlist = []
      if m.episodes = invalid then return playlist
      seasonEpisodes = sortEpisodesForAutoplay(m.episodes)
      idx = 0
      while idx < seasonEpisodes.count()
          playlist.push(autoplayEpisodePayload(seasonEpisodes[idx], authData, idx))
          idx = idx + 1
      end while
      return playlist
  end function

  function sortEpisodesForAutoplay(episodes as object) as object
      sorted = []
      for each ep in episodes
          sorted.push(ep)
      end for
      i = 0
      while i < sorted.count()
          j = i + 1
          while j < sorted.count()
              leftSeason = episodeSeason(sorted[i])
              rightSeason = episodeSeason(sorted[j])
              leftNum = episodeNumber(sorted[i])
              rightNum = episodeNumber(sorted[j])
              shouldSwap = false
              if rightSeason > 0 and (leftSeason <= 0 or rightSeason < leftSeason)
                  shouldSwap = true
              else if rightSeason = leftSeason and rightNum > 0 and (leftNum <= 0 or rightNum < leftNum)
                  shouldSwap = true
              end if
              if shouldSwap
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

  function autoplayEpisodePayload(ep as object, authData as object, fallbackIndex as integer) as object
      epId = ep.lookUp("id")
      if epId = invalid then epId = "0"

      fileInfo = fileInfoFromItem(ep)
      rawFileId = fileInfo.id
      if rawFileId = invalid then rawFileId = epId
      epNumber = episodeNumber(ep)
      if epNumber <= 0 then epNumber = fallbackIndex + 1
      seasonNumber = episodeSeason(ep)
      episodeMeta = "Episode"
      if seasonNumber > 0 and epNumber > 0
          episodeMeta = "Season " + stri(seasonNumber).trim() + " - Episode " + stri(epNumber).trim()
      else if epNumber > 0
          episodeMeta = "Episode " + stri(epNumber).trim()
      end if

      return {
          type: "episode",
          id: epId,
          fileId: rawFileId,
          mapperId: ep.lookUp("mapper_id"),
          showMapperId: m.top.showData.lookUp("mapperId"),
          showTitle: safeStr(m.top.showData, ["title", "name"]),
          filePath: fileInfo.path,
          seasonNumber: seasonNumber,
          episodeNumber: epNumber,
          episodeMeta: episodeMeta,
          originalAvailable: episodeDateText(ep),
          resumePosition: firstNumber(ep, ["resumePosition", "watch_position", "position"]),
          title: safeStr(ep, ["title", "name"]),
          authData: authData
      }
  end function

  function episodeVideoPayload(ep as object, authData as object, fallbackIndex as integer) as object
      epId = ep.lookUp("id")
      if epId = invalid then epId = "0"

      fileInfo = fileInfoFromItem(ep)
      rawFileId = fileInfo.id
      if rawFileId = invalid then rawFileId = epId
      epNumber = episodeNumber(ep)
      if epNumber <= 0 then epNumber = fallbackIndex + 1
      seasonNumber = episodeSeason(ep)
      episodeMeta = "Episode"
      if seasonNumber > 0 and epNumber > 0
          episodeMeta = "Season " + stri(seasonNumber).trim() + " - Episode " + stri(epNumber).trim()
      else if epNumber > 0
          episodeMeta = "Episode " + stri(epNumber).trim()
      end if
      originalAvailable = episodeDateText(ep)

      summary = episodeSummaryText(ep)
      detailPoster = posterUrl(ep, authData)
      detailBackdrop = showBackdropUrl(authData)
      backdropSource = showBackdropSource(authData)
      rating = firstNumber(ep, ["rating", "rate", "user_rating", "userRating", "my_rating", "myRating"])
      print "DETAIL_HANDOFF type=episode title="; safeStr(ep, ["title", "name"]); " date="; originalAvailable; " rating="; rating; " posterSource="; episodePosterSource(ep, authData); " backdropSource="; backdropSource; " summaryLen="; len(summary)
      return {
          type: "episode",
          id: epId,
          fileId: rawFileId,
          mapperId: ep.lookUp("mapper_id"),
          showMapperId: m.top.showData.lookUp("mapperId"),
          showTitle: safeStr(m.top.showData, ["title", "name"]),
          filePath: fileInfo.path,
          seasonNumber: seasonNumber,
          episodeNumber: epNumber,
          episodeMeta: episodeMeta,
          originalAvailable: originalAvailable,
          resumePosition: firstNumber(ep, ["resumePosition", "watch_position", "position"]),
          watchedRatio: firstNumber(ep, ["watched_ratio", "watchedRatio"]),
          fileWatched: fileInfo.watched,
          lastWatched: firstNumber(ep, ["last_watched", "lastWatched"]),
          rating: rating,
          title: safeStr(ep, ["title", "name"]),
          summary: summary,
          posterUrl: detailPoster,
          posterRemoteUrl: safeStr(ep, ["posterRemoteUrl"]),
          backdropUrl: detailBackdrop,
          backdropRemoteUrl: detailBackdrop,
          authData: authData
      }
  end function

  function autoplayIndexForEpisode(selected as object, playlist as object) as integer
      if selected = invalid or playlist = invalid then return -1
      selectedKey = autoplayVideoKey(selected)
      idx = 0
      while idx < playlist.count()
          if autoplayVideoKey(playlist[idx]) = selectedKey then return idx
          idx = idx + 1
      end while
      return -1
  end function

  function autoplayVideoKey(item as object) as string
      if item = invalid then return ""
      if item.filePath <> invalid and item.filePath <> "" then return "path:" + item.filePath
      if item.fileId <> invalid and item.fileId <> "" then return "file:" + safeStr({ value: item.fileId }, ["value"])
      if item.id <> invalid and item.id <> "" then return "id:" + safeStr({ value: item.id }, ["value"])
      season = safeStr({ value: item.seasonNumber }, ["value"])
      episode = safeStr({ value: item.episodeNumber }, ["value"])
      return "se:" + season + "x" + episode
  end function

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
          startInitialSeasonPosterRetryTimer()
          return true
      end if
      if key = "down" and m.focusArea = "episodes"
          if focusNextAvailableEpisodeRowItem() then return true
      end if
      if (key = "left" or key = "right") and m.focusArea = "episodes"
          scheduleSeasonPosterRetry()
      end if
      if key = "back"
          if m.focusArea = "episodes"
              m.top.findNode("seasonGrid").setFocus(true)
              m.focusArea = "seasons"
              return true
          end if
          if m.focusArea = "seasons"
              m.top.backPressed = true
              return true
          end if
          if m.focusArea = "nav" then return false
          return true
      end if
      return false
  end function

  function focusNextAvailableEpisodeRowItem() as boolean
      seasonEpisodes = episodesForCurrentSeason()
      if seasonEpisodes = invalid then return false
      total = seasonEpisodes.count()
      if total = 0 then return false

      grid = m.top.findNode("episodeGrid")
      if grid = invalid then return false

      idx = m.episodeFocusedIndex
      if grid.itemFocused >= 0 then idx = grid.itemFocused
      if idx < 0 or idx >= total - 1 then return false

      cols = 3
      belowIdx = idx + cols
      if belowIdx < total then return false

      nextRow = int(idx / cols) + 1
      target = nextRow * cols
      if target >= total then return false
      grid.jumpToItem = target
      grid.setFocus(true)
      m.episodeFocusedIndex = target
      m.focusArea = "episodes"
      scheduleSeasonPosterRetry()
      return true
  end function

  function episodeSummaryText(item as object) as string
      summary = summaryTextFromValue(item.lookUp("summary"))
      if summary <> "" then return summary
      summary = summaryTextFromValue(item.lookUp("description"))
      if summary <> "" then return summary
      additional = item.lookUp("additional")
      if additional <> invalid
          summary = summaryTextFromValue(additional.lookUp("summary"))
          if summary <> "" then return summary
          summary = summaryTextFromValue(additional.lookUp("description"))
          if summary <> "" then return summary
          extra = additional.lookUp("extra")
          if extra <> invalid
              if type(extra) = "roAssociativeArray"
                  summary = summaryTextFromValue(extra.lookUp("summary"))
                  if summary <> "" then return summary
                  summary = summaryTextFromValue(extra.lookUp("description"))
                  if summary <> "" then return summary
              end if
          end if
      end if
      return ""
  end function

  function episodeDateText(item as object) as string
      value = safeStr(item, ["original_available", "originally_available", "originalAvailable", "date", "air_date", "premiered", "year"])
      if value = ""
          additional = item.lookUp("additional")
          if additional <> invalid
              value = safeStr(additional, ["original_available", "originally_available", "originalAvailable", "date", "air_date", "premiered", "year"])
              if value = ""
                  extra = additional.lookUp("extra")
                  if extra <> invalid
                      value = safeStr(extra, ["original_available", "originally_available", "originalAvailable", "date", "air_date", "premiered", "year"])
                  end if
              end if
          end if
      end if
      value = value.trim()
      if value = "0" then return ""
      if value = "0000-00-00" then return ""
      return value
  end function

  function summaryTextFromValue(value as dynamic) as string
      if value = invalid then return ""
      t = type(value)
      if t = "roAssociativeArray"
          summary = safeStr(value, ["summary", "description"])
          if summary <> "" then return summary
          return ""
      end if
      return safeStr({ value: value }, ["value"])
  end function

  function posterUrl(item as object, authData as dynamic) as string
	      if authData = invalid then return ""
	      savedPoster = item.lookUp("posterUrl")
	      if isLocalArtworkUrl(savedPoster) then return savedPoster
	      synologyPoster = synologyEpisodePosterUrl(item, authData)
	      if synologyPoster <> "" then return synologyPoster
	      remotePoster = item.lookUp("posterRemoteUrl")
	      if remotePoster <> invalid and remotePoster <> "" and isHttpUrl(remotePoster) and not hasFallbackMapper(remotePoster) then return remotePoster
	      if savedPoster <> invalid and savedPoster <> "" and not hasFallbackMapper(savedPoster) then return savedPoster
	      return ""
	  end function

  function episodePosterSource(item as object, authData as dynamic) as string
      if authData = invalid then return "none"
      savedPoster = item.lookUp("posterUrl")
      if isLocalArtworkUrl(savedPoster) then return "cachefs"
      if synologyEpisodePosterUrl(item, authData) <> "" then return "synology-poster"
      remotePoster = item.lookUp("posterRemoteUrl")
      if remotePoster <> invalid and remotePoster <> "" and isHttpUrl(remotePoster) and not hasFallbackMapper(remotePoster) then return "remote"
      if savedPoster <> invalid and savedPoster <> "" and not hasFallbackMapper(savedPoster) then return "saved"
      return "none"
  end function

  function remotePosterUrl(item as object, authData as dynamic) as string
      synologyPoster = synologyEpisodePosterUrl(item, authData)
      if synologyPoster <> "" then return synologyPoster
      remotePoster = safeStr(item, ["posterRemoteUrl"])
      if isHttpUrl(remotePoster) and not hasFallbackMapper(remotePoster) then return remotePoster
      savedPoster = safeStr(item, ["posterUrl"])
      if isHttpUrl(savedPoster) and not hasFallbackMapper(savedPoster) then return savedPoster
      return posterUrl(item, authData)
  end function

  function hasFallbackMapper(url as dynamic) as boolean
      if url = invalid then return false
      if type(url) <> "roString" and type(url) <> "String" then return false
      return instr(1, lcase(url), "fallback_mapper_id=") > 0
  end function

  function isHttpUrl(url as dynamic) as boolean
      if url = invalid then return false
      if type(url) <> "roString" and type(url) <> "String" then return false
      lower = lcase(url)
      return left(lower, 7) = "http://" or left(lower, 8) = "https://"
  end function

  function isLocalArtworkUrl(url as dynamic) as boolean
      if url = invalid then return false
      if type(url) <> "roString" and type(url) <> "String" then return false
      lower = lcase(url)
      return left(lower, 9) = "cachefs:/" or left(lower, 5) = "pkg:/" or left(lower, 5) = "tmp:/"
  end function

  function artworkRetryUrl(url as string, attempt as integer) as string
      sep = "?"
      if instr(1, url, "?") > 0 then sep = "&"
      attemptText = stri(attempt)
      attemptText = attemptText.trim()
      return url + sep + "roku_img_retry=" + attemptText
  end function

  function retryKeyForEpisode(item as object, idx as integer) as string
      idText = safeStr(item, ["id", "mapper_id", "mapperId", "title", "name"])
      if idText = "" then idText = stri(idx)
      return stri(m.currentSeason).trim() + ":" + idText.trim()
  end function

  function synologyEpisodePosterUrl(item as object, authData as dynamic) as string
      if authData = invalid then return ""
      baseUrl = authData.baseUrl
      sid = authData.sid
      if baseUrl = invalid or baseUrl = "" or sid = invalid or sid = "" then return ""
      token = ""
      if authData.synoToken <> invalid then token = authData.synoToken
      id = safeStr(item, ["posterId", "videoStationId", "id"])
      if id = "" or id = "0" then id = safeStr(item, ["mapper_id", "mapperId"])
      id = id.trim()
      if id = "" or id = "0" then return ""
      url = baseUrl + "/webapi/entry.cgi?api=SYNO.VideoStation2.Poster&version=1&method=get&_sid=" + sid + "&id=" + id + "&type=tvshow_episode"
      mtime = posterMtime(item)
      if mtime <> "" then url = url + "&mtime=" + escapeQueryValue(mtime)
      if token <> "" then url = url + "&SynoToken=" + token
      return url
  end function

  function escapeQueryValue(value as string) as string
      out = ""
      idx = 1
      while idx <= len(value)
          ch = mid(value, idx, 1)
          if ch = " "
              out = out + "%20"
          else if ch = ":"
              out = out + "%3A"
          else if ch = "+"
              out = out + "%2B"
          else if ch = "#"
              out = out + "%23"
          else if ch = "%"
              out = out + "%25"
          else
              out = out + ch
          end if
          idx = idx + 1
      end while
      return out
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
      return ""
		  end function

  function showBackdropSource(authData as dynamic) as string
      if m.top.showData <> invalid
          savedBackdrop = m.top.showData.lookUp("backdropUrl")
          if isLocalArtworkUrl(savedBackdrop) then return "cachefs"
          if savedBackdrop <> invalid and savedBackdrop <> "" then return backdropSourceFromUrl(savedBackdrop)
      end if
      return "none"
  end function

  function backdropSourceFromUrl(url as dynamic) as string
      if url = invalid then return "none"
      if type(url) <> "roString" and type(url) <> "String" then return "saved"
      lower = lcase(url)
      if instr(1, lower, "syno.videostation2.backdrop") > 0 then return "synology-backdrop"
      return "saved"
  end function

	  function showMapperId() as string
	      if m.top.showData = invalid then return ""
	      mapper = safeStr(m.top.showData, ["mapperId", "mapper_id", "showMapperId", "show_mapper_id"])
	      return mapper.trim()
	  end function

  sub onNavFocus(event as object)
      if event.getData() = true then m.focusArea = "nav"
  end sub

  sub onNavSelected(event as object)
      idx = event.getData()
      stopEpisodeArtworkTimers()
      if idx >= 0 and idx < m.categories.count() then m.top.selectedCategory = categoryPayload(idx)
  end sub

  sub onNavFocused(event as object)
      if event = invalid then return
      ' Moving across the nav should only move focus. Press OK to load a library.
  end sub

  sub onNavLoadTimer(event as object)
      if event = invalid then return
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

  sub onNavCategoriesSet(event as object)
      cats = event.getData()
      if cats = invalid or cats.count() = 0 then return
      m.categories = cats
      populateNavCategories()
  end sub

  sub populateNavCategories()
      refreshActiveNav()
  end sub

  sub focusActiveNav()
      nav = m.top.findNode("categoryList")
      refreshActiveNav()
      nav.setFocus(true)
      m.focusArea = "nav"
  end sub

  sub refreshActiveNav()
      nav = m.top.findNode("categoryList")
      if nav = invalid then return
      activeIdx = activeCategoryIndex()
      contentNode = createObject("roSGNode", "ContentNode")
      idx = 0
      for each cat in m.categories
          item = contentNode.createChild("ContentNode")
          item.title = cat.title
          activeValue = "false"
          if idx = activeIdx then activeValue = "true"
          item.addFields({ isActiveNav: activeValue })
          idx = idx + 1
      end for
      nav.content = invalid
      nav.content = contentNode
      nav.numColumns = m.categories.count()
      if activeIdx >= 0 then nav.jumpToItem = activeIdx
      print "NAV_ACTIVE screen=episodes idx="; activeIdx
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
      activeTitle = ""
      if m.top.showData <> invalid then activeTitle = safeStr(m.top.showData, ["sourceLibraryTitle", "libraryTitle"])
      if activeTitle <> ""
          while i < m.categories.count()
              cat = m.categories[i]
              if cat.lookUp("category") = "tvshows" and lcase(safeStr(cat, ["title"])) = lcase(activeTitle)
                  return i
              end if
              i = i + 1
          end while
      end if
      i = 0
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
  
