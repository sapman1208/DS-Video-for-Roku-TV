sub init()
      m.top.observeField("authData", "onDataReady")
      m.top.observeField("category", "onDataReady")
      m.top.observeField("focus", "onGroupFocusChange")
      m.items = []
      m.categories = []
      m.focusArea = "items"
      m.focusedIndex = 0
      m.lastKey = ""
      m.pendingNavIdx = -1
      m.posterRetryAttempts = {}
      m.posterRetryQueue = []
      m.posterRetryCursor = 0
      m.initialPosterRetryPass = 0
      nav = m.top.findNode("categoryList")
      nav.observeField("itemSelected", "onNavSelected")
      nav.observeField("itemFocused", "onNavFocused")
      nav.observeField("focus", "onNavFocus")
      m.top.observeField("focusNavCategory", "onFocusNavCategory")
      m.top.observeField("refreshLists", "onRefreshLists")
      m.top.observeField("refreshArtwork", "onRefreshArtwork")
      m.top.findNode("navLoadTimer").observeField("fire", "onNavLoadTimer")
      m.top.findNode("posterRetryTimer").observeField("fire", "onPosterRetryTimer")
      m.top.findNode("initialPosterRetryTimer").observeField("fire", "onInitialPosterRetryTimer")
      m.top.findNode("scrollPosterRetryTimer").observeField("fire", "onScrollPosterRetryTimer")
  end sub

  ' Safely read a string from multiple possible field names — no integer conversion
  ' Safely read a string from multiple possible field names.
  ' Never calls cstr() — it only accepts numerics in BrightScript.
  ' Uses stri() for integers, str().trim() for floats.
  function safeStr(item as object, keys as object) as string
      for each k in keys
          v = item.lookUp(k)
          if v <> invalid
              t = type(v)
              if t = "roString" or t = "String" then return v
              if t = "roInteger" or t = "Integer" or t = "roLongInteger" or t = "LongInteger"
                  s = stri(v)
                  return s.trim()
              end if
              if t = "roFloat" or t = "Float" or t = "roDouble" or t = "Double"
                  s = stri(int(v))
                  return s.trim()
              end if
          end if
      end for
      return ""
  end function

  function firstNonZeroStr(item as object, keys as object) as string
      for each k in keys
          v = safeStr(item, [k])
          v = v.trim()
          if v <> "" and v <> "0" then return v
      end for
      return ""
  end function

  function fileInfoFromFileObject(f as dynamic, info as object) as object
      if f = invalid or type(f) <> "roAssociativeArray" then return info
      if info.id = invalid
          fid = f.lookUp("id")
          if fid = invalid then fid = f.lookUp("file_id")
          if fid <> invalid then info.id = fid
      end if
      if info.watched = invalid
          info.watched = f.lookUp("file_watched")
          if info.watched = invalid then info.watched = f.lookUp("watched")
      end if
      if info.path = ""
          p = f.lookUp("path")
          if p = invalid then p = f.lookUp("sharepath")
          if p = invalid then p = f.lookUp("file_path")
          if p <> invalid then info.path = p
      end if
      return info
  end function

  function fileInfoFromValue(value as dynamic, info as object) as object
      if value = invalid then return info
      valueType = type(value)
      if valueType = "roArray"
          if value.count() > 0 then info = fileInfoFromFileObject(value[0], info)
      else if valueType = "roAssociativeArray"
          info = fileInfoFromFileObject(value, info)
      end if
      return info
  end function

  function fileInfoFromItem(item as object) as object
      info = { id: invalid, path: "", watched: invalid }

      additional = item.lookUp("additional")
      if additional <> invalid
          info = fileInfoFromValue(additional.lookUp("file"), info)
          info = fileInfoFromValue(additional.lookUp("files"), info)
      end if

      info = fileInfoFromValue(item.lookUp("file"), info)
      info = fileInfoFromValue(item.lookUp("files"), info)

      if info.id = invalid
          fid = item.lookUp("file_id")
          if fid = invalid then fid = item.lookUp("fid")
          if fid <> invalid then info.id = fid
      end if
      if info.path = ""
          p = item.lookUp("filePath")
          if p = invalid then p = item.lookUp("path")
          if p = invalid then p = item.lookUp("sharepath")
          if p = invalid then p = item.lookUp("file_path")
          if p <> invalid then info.path = p
      end if

      return info
  end function

  function hasPlaylistEpisodeFields(item as object) as boolean
      if item = invalid then return false
      season = safeStr(item, ["seasonNumber", "season_number", "seasonText", "season", "season_num", "season_index"])
      episode = safeStr(item, ["episodeNumber", "episode_number", "episodeText", "episode", "episode_num", "ep_num", "ep_index"])
      if season <> "" and season <> "0" then return true
      if episode <> "" and episode <> "0" then return true
      if safeStr(item, ["episodeTitle", "episode_title"]) <> "" then return true
      if safeStr(item, ["showTitle", "show_title", "tvshow_title", "seriesTitle"]) <> "" then return true
      return false
  end function

  function playbackTypeForItem(item as object, category as string, fallbackType as string) as string
      savedType = ""
      if item <> invalid then savedType = lcase(safeStr(item, ["type"]))
      if savedType = "tvshow_episode" or savedType = "episode" then return "episode"
      if savedType = "home_video" or savedType = "homevideo" then return "homevideo"
      if savedType = "tv_record" then return "homevideo"
      if savedType = "movie" then return "movie"
      if savedType = "video"
          if hasPlaylistEpisodeFields(item) then return "episode"
          return "movie"
      end if
      return fallbackType
  end function

  sub onDataReady(event as object)
      if event = invalid
          ' Manual refresh path.
      end if
      if m.top.authData = invalid then return
      if m.top.category = invalid then return
      if m.top.category = "" then return

      category = m.top.category
      authData = m.top.authData
      loadNavCategories(authData)

      localKey = localListKeyForCategory(category)
      if localKey <> ""
          m.localListKey = localKey
          m.top.findNode("loadingLabel").visible = false
          m.top.findNode("errorLabel").visible = false
          m.top.findNode("videoGrid").visible = false
          m.category = category
          applyGridLayout(category)
          task = createObject("roSGNode", "APITask")
          task.request = {
              action: "listCollectionVideos",
              baseUrl: authData.baseUrl,
              sid: authData.sid,
              synoToken: authData.synoToken,
              proxyBaseUrl: authData.proxyBaseUrl,
              localKey: localKey,
              collectionId: collectionIdForLocalKey(localKey)
          }
          task.observeField("response", "onCollectionItemsLoaded")
          task.control = "RUN"
          m.collectionTask = task
          return
      end if

      if category = "movies"
          action = "listMovies"
      else if category = "tvshows"
          action = "listTVShows"
      else if category = "playlists"
          action = "listPlaylists"
      else if category = "tvrecordings"
          action = "listTVRecordings"
      else
          action = "listHomeVideos"
      end if

      m.top.findNode("loadingLabel").visible = false
      m.top.findNode("errorLabel").visible = false
      m.top.findNode("videoGrid").visible = false
      applyGridLayout(category)

      task = createObject("roSGNode", "APITask")
      task.request = {
          action: action,
          baseUrl: authData.baseUrl,
          sid: authData.sid,
          synoToken: authData.synoToken,
          proxyBaseUrl: authData.proxyBaseUrl,
          libraryId: m.top.libraryId
      }
      task.observeField("response", "onItemsLoaded")
      task.control = "RUN"
      m.loadTask = task
  end sub

  sub onCollectionItemsLoaded(event as object)
      m.top.findNode("loadingLabel").visible = false
      response = event.getData()
      localItems = loadLocalList(m.localListKey)
      removedItems = loadLocalList(m.localListKey + "_removed")
      items = []
      useLocalFallback = true
      if response <> invalid and response.success = true and response.items <> invalid
          items = response.items
          useLocalFallback = false
      end if
      if useLocalFallback
          items = filterRemovedItems(items, removedItems)
          items = mergeLocalItems(items, filterRemovedItems(localItems, removedItems))
      else
          items = mergeLocalItems(items, filterRemovedItems(pendingLocalItems(localItems), removedItems))
      end if
      items = uniquePlaylistItems(items)
      m.items = items
      resetPosterRetryState()
      if m.items.count() = 0
          showError("No items found in this playlist.")
      else
          populateGrid(m.items)
          if m.category <> "playlists"
              startInitialPosterRetryTimer()
          end if
      end if
  end sub

  sub onRefreshLists(event as object)
      if event = invalid then return
      if m.top.authData = invalid then return
      category = m.top.category
      if category = invalid then return
      if localListKeyForCategory(category) = "" and category <> "playlists" then return
      onDataReady(invalid)
  end sub

  sub onItemsLoaded(event as object)
      m.top.findNode("loadingLabel").visible = false
      response = event.getData()

      if response = invalid
          showError("No response received.")
          return
      end if
      if response.success <> true
          msg = "Failed to load content."
          if response.error <> invalid and response.error <> "" then msg = response.error
          if response.detail <> invalid and response.detail <> "" then msg = msg + chr(10) + left(response.detail, 200)
          showError(msg)
          return
      end if

      items = response.items
      if items = invalid or items.count() = 0
          showError("No items found in this category.")
          return
      end if

      m.items = items
      resetPosterRetryState()
      m.category = m.top.category
      populateGrid(items)
      if m.category <> "playlists"
          startInitialPosterRetryTimer()
      end if
  end sub

  sub applyGridLayout(category as string)
      grid = m.top.findNode("videoGrid")
      movieGrid = m.top.findNode("playlistMovieGrid")
      episodeGrid = m.top.findNode("playlistEpisodeGrid")
      if movieGrid <> invalid then movieGrid.visible = false
      if episodeGrid <> invalid then episodeGrid.visible = false
      titleLabel = m.top.findNode("pageTitleLabel")
      title = pageTitleForCategory(category)
      titleLabel.text = title
      showTitle = category = "playlists" or left(category, 6) = "local_"
      titleLabel.visible = showTitle
      if category = "homevideos" or category = "tvrecordings"
          grid.translation = [98, 120]
          grid.itemSize = [520, 392]
          grid.itemSpacing = [82, 30]
          grid.numColumns = 3
          grid.numRows = 2
      else if category = "playlists"
          grid.translation = [48, 150]
          grid.itemSize = [220, 274]
          grid.itemSpacing = [45, 22]
          grid.numColumns = 7
          grid.numRows = 1
      else
          if showTitle
              grid.translation = [48, 150]
          else
              grid.translation = [48, 120]
          end if
          grid.itemSize = [220, 430]
          grid.itemSpacing = [45, 22]
          grid.numColumns = 7
          grid.numRows = 2
      end if
  end sub

  sub populateGrid(items as object)
      category = m.category
      grid = m.top.findNode("videoGrid")
      if left(category, 6) = "local_"
          populatePlaylistSplitGrid(items)
          return
      end if
      content = createObject("roSGNode", "ContentNode")
      idx = 0

      for each item in items
          node = content.createChild("ContentNode")
          if left(category, 6) = "local_"
              node.title = playlistItemTitle(item)
          else
              node.title = safeStr(item, ["title", "name", "file_name"])
          end if
          if node.title = "" then node.title = "Untitled"
          iconUrl = safeStr(item, ["iconUrl"])
          if category = "homevideos"
              node.addFields({ layoutMode: "homeLandscape" })
              cols = 3
          else if category = "tvrecordings"
              node.addFields({ layoutMode: "homeLandscape" })
              cols = 3
          else if category = "playlists" and iconUrl <> ""
              node.addFields({ layoutMode: "playlistSelector" })
              cols = 7
          else if iconUrl <> ""
              node.addFields({ layoutMode: "icon" })
              cols = 7
          else if left(category, 6) = "local_" and not playlistItemIsMovie(item)
              node.addFields({ layoutMode: "playlistEpisode" })
              cols = 7
          else if category = "movies" or category = "tvshows" or left(category, 6) = "local_" or m.top.libraryId <> invalid
              node.addFields({ layoutMode: "compactPortrait" })
              cols = 7
          else
              node.addFields({ layoutMode: "portrait" })
              cols = 7
          end if
          if iconUrl <> ""
              node.addFields({ iconUrl: iconUrl })
          end if
          preventDown = "false"
          if idx + cols >= items.count() then preventDown = "true"
          preventUp = "false"
          if idx < cols then preventUp = "true"
          node.addFields({
              preventWrapUp: preventUp,
              preventWrapDown: preventDown
          })

          if left(category, 6) = "local_"
              node.description = playlistItemMeta(item)
          else if category = "movies"
              node.description = safeStr(item, ["original_available", "year", "create_time"])
          else if category = "tvshows"
              node.description = ""
          else
              node.description = safeStr(item, ["create_time", "date"])
          end if
          if iconUrl = "" and shouldAssignPosterInitially(category, idx, cols)
              poster = posterUrl(item, m.top.authData, category)
              if poster <> ""
                  printArtworkPick("grid", categoryLabel(category), item, posterSource(item, m.top.authData, category))
                  item.addReplace("posterRemoteUrl", poster)
                  item.addReplace("posterUrl", poster)
                  node.HDPosterUrl = poster
                  node.SDPosterUrl = poster
              end if
          end if
          idx = idx + 1
      end for

      grid.content = content
      grid.visible = true
      if m.categories.count() > 0
          focusActiveNav()
      else
          grid.setFocus(true)
      end if
      grid.observeField("itemFocused", "onItemFocused")
      grid.observeField("itemSelected", "onItemSelected")
  end sub

  sub populatePlaylistSplitGrid(items as object)
      grid = m.top.findNode("videoGrid")
      movieGrid = m.top.findNode("playlistMovieGrid")
      episodeGrid = m.top.findNode("playlistEpisodeGrid")
      if grid <> invalid then grid.visible = false
      if movieGrid = invalid or episodeGrid = invalid then return

      m.playlistMovieItems = []
      m.playlistEpisodeItems = []
      movieContent = createObject("roSGNode", "ContentNode")
      episodeContent = createObject("roSGNode", "ContentNode")

      for each item in items
          if playlistItemIsMovie(item)
              m.playlistMovieItems.push(item)
              node = playlistContentNode(item, "playlistMovie", m.playlistMovieItems.count() - 1)
              movieContent.appendChild(node)
          else
              m.playlistEpisodeItems.push(item)
              node = playlistContentNode(item, "playlistWide", m.playlistEpisodeItems.count() - 1)
              episodeContent.appendChild(node)
          end if
      end for

      movieGrid.content = movieContent
      episodeGrid.content = episodeContent
      movieRows = 1
      if movieContent.getChildCount() > 7 then movieRows = 2
      movieGrid.numRows = movieRows
      episodeRows = 1
      if episodeContent.getChildCount() > 3 then episodeRows = 2
      episodeGrid.numRows = episodeRows
      if movieContent.getChildCount() > 0
          episodeGrid.translation = [98, 630]
      else
          episodeGrid.translation = [98, 150]
      end if
      movieGrid.visible = movieContent.getChildCount() > 0
      episodeGrid.visible = episodeContent.getChildCount() > 0
      if movieRows > 1 and movieGrid.visible = true then episodeGrid.visible = false
      movieGrid.observeField("itemFocused", "onPlaylistMovieFocused")
      movieGrid.observeField("itemSelected", "onPlaylistMovieSelected")
      episodeGrid.observeField("itemFocused", "onPlaylistEpisodeFocused")
      episodeGrid.observeField("itemSelected", "onPlaylistEpisodeSelected")
      if movieGrid.visible
          movieGrid.setFocus(true)
          m.focusArea = "playlistMovies"
      else if episodeGrid.visible
          episodeGrid.setFocus(true)
          m.focusArea = "playlistEpisodes"
      end if
  end sub

  function playlistContentNode(item as object, layoutMode as string, idx as integer) as object
      node = createObject("roSGNode", "ContentNode")
      node.title = playlistItemTitle(item)
      if node.title = "" then node.title = "Untitled"
      node.description = playlistItemMeta(item)
      node.addFields({ layoutMode: layoutMode, playlistIndex: idx })
      if layoutMode = "playlistWide"
          dateText = playlistItemDate(item)
          if dateText <> "" then node.addFields({ playlistDate: dateText })
      end if
      poster = posterUrl(item, m.top.authData, m.category)
      if poster <> ""
          printArtworkPick("grid", categoryLabel(m.category), item, posterSource(item, m.top.authData, m.category))
          item.addReplace("posterRemoteUrl", poster)
          item.addReplace("posterUrl", poster)
          node.HDPosterUrl = poster
          node.SDPosterUrl = poster
      end if
      return node
  end function

  sub onPlaylistMovieFocused(event as object)
      m.focusedIndex = event.getData()
      m.focusArea = "playlistMovies"
  end sub

  sub onPlaylistEpisodeFocused(event as object)
      m.focusedIndex = event.getData()
      m.focusArea = "playlistEpisodes"
  end sub

  sub onPlaylistMovieSelected(event as object)
      idx = event.getData()
      if m.playlistMovieItems = invalid or idx < 0 or idx >= m.playlistMovieItems.count() then return
      stopArtworkTimers()
      selectVideoItem(m.playlistMovieItems[idx], m.category)
  end sub

  sub onPlaylistEpisodeSelected(event as object)
      idx = event.getData()
      if m.playlistEpisodeItems = invalid or idx < 0 or idx >= m.playlistEpisodeItems.count() then return
      stopArtworkTimers()
      selectVideoItem(m.playlistEpisodeItems[idx], m.category)
  end sub

  function focusPlaylistMovieIndex(target as integer) as boolean
      if m.playlistMovieItems = invalid then return false
      if target < 0 or target >= m.playlistMovieItems.count() then return false
      movieGrid = m.top.findNode("playlistMovieGrid")
      if movieGrid = invalid then return false
      episodeGrid = m.top.findNode("playlistEpisodeGrid")
      if episodeGrid <> invalid
          episodeGrid.translation = [98, 630]
          if m.playlistMovieItems <> invalid and m.playlistMovieItems.count() > 7 then episodeGrid.visible = false
      end if
      movieGrid.visible = true
      movieGrid.jumpToItem = target
      movieGrid.setFocus(true)
      m.focusedIndex = target
      m.focusArea = "playlistMovies"
      return true
  end function

  function focusPlaylistEpisodeSection() as boolean
      episodeGrid = m.top.findNode("playlistEpisodeGrid")
      if episodeGrid = invalid then return false
      if m.playlistEpisodeItems = invalid or m.playlistEpisodeItems.count() = 0 then return false
      movieGrid = m.top.findNode("playlistMovieGrid")
      if movieGrid <> invalid then movieGrid.visible = false
      episodeGrid.translation = [98, 150]
      episodeGrid.visible = true
      episodeGrid.jumpToItem = 0
      episodeGrid.setFocus(true)
      m.focusedIndex = 0
      m.focusArea = "playlistEpisodes"
      return true
  end function

  function focusPlaylistEpisodeIndex(target as integer) as boolean
      if m.playlistEpisodeItems = invalid then return false
      if target < 0 or target >= m.playlistEpisodeItems.count() then return false
      episodeGrid = m.top.findNode("playlistEpisodeGrid")
      if episodeGrid = invalid then return false
      episodeGrid.visible = true
      episodeGrid.jumpToItem = target
      episodeGrid.setFocus(true)
      m.focusedIndex = target
      m.focusArea = "playlistEpisodes"
      return true
  end function

  function shouldAssignPosterInitially(category as string, idx as integer, cols as integer) as boolean
      if shouldDeferArtworkCache(category) then return idx < cols * 4
      return true
  end function

  function playlistItemMeta(item as object) as string
      mediaType = lcase(safeStr(item, ["type"]))
      if playlistItemIsMovie(item)
          dateText = safeStr(item, ["originalAvailable", "original_available", "originally_available", "air_date", "year", "create_time", "date"])
          if dateText <> "" and dateText <> "0" then return dateText
          return ""
      end if
      showTitle = safeStr(item, ["showTitle", "show_title", "tvshow_title", "series_title", "parent_title"])
      if showTitle = "" then showTitle = showTitleFromPlaylistPath(item)
      if showTitle = "" and mediaType = "tvshow" then showTitle = safeStr(item, ["title", "name"])

      season = safeStr(item, ["seasonNumber", "season_number", "seasonText", "season", "season_num", "season_index"])
      episode = safeStr(item, ["episodeNumber", "episode_number", "episodeText", "episode", "episode_num", "ep_num", "ep_index"])
      if season = "" or season = "0" or episode = "" or episode = "0"
          parsed = seasonEpisodeFromPlaylistPath(item)
          if season = "" or season = "0" then season = parsed.season
          if episode = "" or episode = "0" then episode = parsed.episode
      end if
      episodeLine = ""
      if season <> "" and season <> "0" and episode <> "" and episode <> "0"
          episodeLine = "Season " + season + " - Episode " + episode
      else if episode <> "" and episode <> "0"
          episodeLine = "Episode " + episode
      end if

      episodeTitle = playlistEpisodeTitle(item)
      meta = ""
      if episodeLine <> ""
          meta = meta + episodeLine
      end if
      if episodeTitle <> ""
          if meta <> "" then meta = meta + chr(10)
          meta = meta + episodeTitle
      end if
      return meta
  end function

  function playlistItemDate(item as object) as string
      dateText = safeStr(item, ["originalAvailable", "original_available", "originally_available", "original_available_date", "originally_available_date", "airDate", "air_date", "premiered", "date", "release_date", "year"])
      if dateText <> "" and dateText <> "0" then return dateText
      additional = item.lookUp("additional")
      if additional <> invalid
          dateText = safeStr(additional, ["originalAvailable", "original_available", "originally_available", "original_available_date", "originally_available_date", "airDate", "air_date", "premiered", "date", "release_date", "year"])
          if dateText <> "" and dateText <> "0" then return dateText
          extra = additional.lookUp("extra")
          if extra <> invalid
              dateText = safeStr(extra, ["originalAvailable", "original_available", "originally_available", "original_available_date", "originally_available_date", "airDate", "air_date", "premiered", "date", "release_date", "year"])
              if dateText <> "" and dateText <> "0" then return dateText
          end if
      end if
      return ""
  end function

  function playlistItemIsMovie(item as object) as boolean
      mediaType = lcase(safeStr(item, ["type"]))
      if mediaType = "movie" then return true
      path = lcase(playlistPathText(item))
      if instr(1, path, "/movies/") > 0 then return true
      return false
  end function

  function playlistItemTitle(item as object) as string
      if playlistItemIsMovie(item) then return safeStr(item, ["title", "name", "file_name"])
      showTitle = safeStr(item, ["showTitle", "show_title", "tvshow_title", "series_title", "parent_title"])
      if showTitle = "" then showTitle = showTitleFromPlaylistPath(item)
      if showTitle <> "" then return showTitle
      return safeStr(item, ["title", "name", "file_name"])
  end function

  function playlistEpisodeTitle(item as object) as string
      mediaType = lcase(safeStr(item, ["type"]))
      if mediaType = "movie" then return ""
      showTitle = playlistItemTitle(item)
      title = safeStr(item, ["episodeTitle", "episode_title"])
      if title <> "" and lcase(title.trim()) <> lcase(showTitle.trim()) then return title
      pathTitle = episodeTitleFromPlaylistPath(item)
      if pathTitle <> "" then return pathTitle
      title = safeStr(item, ["title", "name"])
      if title <> "" and lcase(title.trim()) <> lcase(showTitle.trim()) then return title
      return ""
  end function

  function playlistPathText(item as object) as string
      text = safeStr(item, ["filePath", "path"])
      if text <> "" then return text
      fileInfo = fileInfoFromItem(item)
      if fileInfo.path <> invalid and fileInfo.path <> "" then return fileInfo.path
      text = safeStr(item, ["file_name", "filename", "title", "name"])
      if text <> "" then return text
      return ""
  end function

  function showTitleFromPlaylistPath(item as object) as string
      text = playlistPathText(item)
      if text = "" then return ""
      slash = 0
      i = 1
      while i <= len(text)
          if mid(text, i, 1) = "/" then slash = i
          i = i + 1
      end while
      fileName = text
      if slash > 0 then fileName = mid(text, slash + 1)
      marker = instr(1, fileName, " - S")
      if marker <= 1 then marker = instr(1, fileName, " - s")
      if marker > 1 then return left(fileName, marker - 1).trim()
      return ""
  end function

  function seasonEpisodeFromPlaylistPath(item as object) as object
      result = { season: "", episode: "" }
      text = playlistPathText(item)
      if text = "" then return result
      lower = lcase(text)
      marker = instr(1, lower, "s")
      while marker > 0 and marker + 5 <= len(lower)
          if mid(lower, marker + 3, 1) = "e"
              seasonText = mid(lower, marker + 1, 2)
              episodeText = mid(lower, marker + 4, 2)
              if isDigits(seasonText) and isDigits(episodeText)
                  result.season = stripLeadingZero(seasonText)
                  result.episode = stripLeadingZero(episodeText)
                  return result
              end if
          end if
          nextStart = marker + 1
          marker = instr(nextStart, lower, "s")
      end while
      return result
  end function

  function episodeTitleFromPlaylistPath(item as object) as string
      text = playlistPathText(item)
      if text = "" then return ""
      slash = 0
      i = 1
      while i <= len(text)
          if mid(text, i, 1) = "/" then slash = i
          i = i + 1
      end while
      fileName = text
      if slash > 0 then fileName = mid(text, slash + 1)
      dot = 0
      i = len(fileName)
      while i >= 1
          if mid(fileName, i, 1) = "."
              dot = i
              exit while
          end if
          i = i - 1
      end while
      if dot > 1 then fileName = left(fileName, dot - 1)
      lower = lcase(fileName)
      marker = instr(1, lower, " - s")
      if marker <= 0 then marker = instr(1, lower, " s")
      if marker <= 0 then return ""
      titleMarker = instr(marker + 1, fileName, " - ")
      if titleMarker <= 0 then return ""
      return mid(fileName, titleMarker + 3).trim()
  end function

  function isDigits(text as string) as boolean
      if text = "" then return false
      i = 1
      while i <= len(text)
          c = asc(mid(text, i, 1))
          if c < 48 or c > 57 then return false
          i = i + 1
      end while
      return true
  end function

  function stripLeadingZero(text as string) as string
      while len(text) > 1 and left(text, 1) = "0"
          text = mid(text, 2)
      end while
      return text
  end function

  function shouldDeferArtworkCache(category as string) as boolean
      return category = "movies" or category = "tvshows" or category = "homevideos" or category = "tvrecordings"
  end function

  function shouldCacheIanShowGridArtwork(category as string) as boolean
      return category = "ians-shows" or (category = "tvshows" and tvShowProxyPosterAllowed(category))
  end function

  function categoryLabel(category as string) as string
      if category = "tvshows" and tvShowProxyPosterAllowed(category) then return "ians-shows"
      return category
  end function

  sub printArtworkPick(surface as string, category as string, item as object, source as string)
      title = safeStr(item, ["title", "name", "file_name"])
      idText = safeStr(item, ["id", "videoStationId", "posterId"])
      mapper = safeStr(item, ["mapper_id", "mapperId"])
      print "ARTWORK_PICK surface="; surface; " category="; category; " source="; source; " title="; title; " id="; idText; " mapper="; mapper
  end sub

  sub onRefreshArtwork(event as object)
      if event = invalid then return
      if m.items = invalid or m.items.count() = 0 then return
      grid = m.top.findNode("videoGrid")
      focused = m.focusedIndex
      if grid <> invalid and grid.itemFocused >= 0 then focused = grid.itemFocused
      populateGrid(m.items)
      if grid <> invalid and focused >= 0 and focused < m.items.count()
          grid.jumpToItem = focused
          grid.setFocus(true)
          m.focusArea = "items"
      end if
  end sub

  sub onItemFocused(event as object)
      idx = event.getData()
      if idx < 0 then return
      m.focusedIndex = idx
      if m.category = "playlists" then return
      schedulePosterRows(idx)
      startScrollPosterRetryTimer()
  end sub

  sub schedulePosterRows(idx as integer)
      if m.category = "playlists" then return
      if m.items = invalid or m.items.count() = 0 then return
      cols = columnsForCategory(m.category)
      row = int(idx / cols)
      startRow = row - 3
      endRow = row + 3
      if startRow < 0 then startRow = 0
      maxRow = int((m.items.count() - 1) / cols)
      if endRow > maxRow then endRow = maxRow

      startIdx = startRow * cols
      endIdx = ((endRow + 1) * cols) - 1
      if endIdx >= m.items.count() then endIdx = m.items.count() - 1
      i = startIdx
      while i <= endIdx
          enqueuePosterRetry(i, false)
          i = i + 1
      end while

      timer = m.top.findNode("posterRetryTimer")
      if timer = invalid then return
      if m.posterRetryQueue.count() > 0
          retryNextPosterBatch()
          if m.posterRetryQueue.count() > 0 then timer.control = "start"
      end if
  end sub

  sub scheduleInitialPosterRows()
      if m.category = "playlists" then return
      if m.items = invalid or m.items.count() = 0 then return
      cols = columnsForCategory(m.category)
      endIdx = (cols * 4) - 1
      if endIdx >= m.items.count() then endIdx = m.items.count() - 1

      i = 0
      while i <= endIdx
          enqueuePosterRetry(i, false)
          i = i + 1
      end while

      timer = m.top.findNode("posterRetryTimer")
      if timer = invalid then return
      if m.posterRetryQueue.count() > 0
          retryNextPosterBatch()
          if m.posterRetryQueue.count() > 0 then timer.control = "start"
      end if
  end sub

  sub startInitialPosterRetryTimer()
      timer = m.top.findNode("initialPosterRetryTimer")
      if timer = invalid then return
      m.initialPosterRetryPass = 0
      timer.control = "stop"
      timer.control = "start"
  end sub

  sub onInitialPosterRetryTimer(event as object)
      if event = invalid then return
      m.initialPosterRetryPass = m.initialPosterRetryPass + 1
      scheduleInitialPosterRows()
      schedulePosterRows(m.focusedIndex)
      if m.initialPosterRetryPass < 1
          timer = m.top.findNode("initialPosterRetryTimer")
          if timer <> invalid
              timer.control = "stop"
              timer.control = "start"
          end if
      end if
  end sub

  sub startScrollPosterRetryTimer()
      timer = m.top.findNode("scrollPosterRetryTimer")
      if timer = invalid then return
      timer.control = "stop"
      timer.control = "start"
  end sub

  sub onScrollPosterRetryTimer(event as object)
      if event = invalid then return
      schedulePosterRows(m.focusedIndex)
  end sub

  sub resetPosterRetryState()
      timer = m.top.findNode("posterRetryTimer")
      if timer <> invalid then timer.control = "stop"
      m.posterRetryAttempts = {}
      m.posterRetryQueue = []
      m.posterRetryCursor = 0
  end sub

  sub stopArtworkTimers()
      timer = m.top.findNode("posterRetryTimer")
      if timer <> invalid then timer.control = "stop"
      timer = m.top.findNode("initialPosterRetryTimer")
      if timer <> invalid then timer.control = "stop"
      timer = m.top.findNode("scrollPosterRetryTimer")
      if timer <> invalid then timer.control = "stop"
      m.posterRetryQueue = []
  end sub

  sub enqueuePosterRetry(idx as integer, forceFreshAttempts as boolean)
      if not artworkNeedsRetry(idx) then return
      key = posterAttemptKey(idx)
      attempts = 0
      existing = m.posterRetryAttempts.lookUp(key)
      if existing <> invalid then attempts = existing
      if forceFreshAttempts
          attempts = 0
          m.posterRetryAttempts.addReplace(key, attempts)
      end if
      if attempts >= maxPosterRetryAttempts() then return
      if not posterQueueContains(idx) then m.posterRetryQueue.push(idx)
  end sub

  function posterQueueContains(idx as integer) as boolean
      for each queuedIdx in m.posterRetryQueue
          if queuedIdx = idx then return true
      end for
      return false
  end function

  sub onPosterRetryTimer(event as object)
      if event = invalid then return
      retryNextPosterBatch()
  end sub

  sub retryNextPosterBatch()
      timer = m.top.findNode("posterRetryTimer")
      if m.posterRetryQueue = invalid or m.posterRetryQueue.count() = 0
          if timer <> invalid then timer.control = "stop"
          return
      end if

      batchSize = 5
      processed = 0
      while processed < batchSize and m.posterRetryQueue.count() > 0
          idx = m.posterRetryQueue[0]
          if artworkNeedsRetry(idx)
              key = posterAttemptKey(idx)
              attempts = 0
              existing = m.posterRetryAttempts.lookUp(key)
              if existing <> invalid then attempts = existing
              if attempts >= maxPosterRetryAttempts()
                  m.posterRetryQueue.delete(0)
              else
                  attempts = attempts + 1
                  m.posterRetryAttempts.addReplace(key, attempts)
                  retryPosterForIndex(idx, attempts)
                  m.posterRetryQueue.delete(0)
                  if attempts < maxPosterRetryAttempts() then m.posterRetryQueue.push(idx)
                  processed = processed + 1
              end if
          else
              m.posterRetryQueue.delete(0)
          end if
      end while
      if m.posterRetryQueue.count() = 0 and timer <> invalid then timer.control = "stop"
  end sub

  function posterAttemptKey(idx as integer) as string
      return stri(idx).trim()
  end function

  function maxPosterRetryAttempts() as integer
      return 1
  end function

  function artworkNeedsRetry(idx as integer) as boolean
      if m.items = invalid or m.items.count() = 0 then return false
      if idx < 0 or idx >= m.items.count() then return false
      grid = m.top.findNode("videoGrid")
      if grid = invalid or grid.content = invalid then return false
      node = grid.content.getChild(idx)
      if node = invalid then return false
      if node.hasField("artworkLoaded") and node.artworkLoaded = "true" then return false
      nodePoster = ""
      if node.HDPosterUrl <> invalid then nodePoster = node.HDPosterUrl
      if isLocalArtworkUrl(nodePoster) then return false
      item = m.items[idx]
      baseUrl = remotePosterUrl(item, m.top.authData, m.category)
      return isHttpUrl(baseUrl)
  end function

  sub retryPosterForIndex(idx as integer, attempt as integer)
      if m.items = invalid or m.items.count() = 0 then return
      if idx < 0 or idx >= m.items.count() then return
      grid = m.top.findNode("videoGrid")
      if grid = invalid or grid.content = invalid then return
      node = grid.content.getChild(idx)
      if node = invalid then return
      if node.hasField("artworkLoaded") and node.artworkLoaded = "true" then return
      item = m.items[idx]
      baseUrl = remotePosterUrl(item, m.top.authData, m.category)
      if not isHttpUrl(baseUrl) then return
      retryUrl = artworkRetryUrl(baseUrl, attempt)
      printArtworkPick("grid-retry", categoryLabel(m.category), item, posterSource(item, m.top.authData, m.category))
      node.HDPosterUrl = retryUrl
      node.SDPosterUrl = retryUrl
  end sub

  function columnsForCategory(category as string) as integer
      if category = "homevideos" or category = "tvrecordings" then return 3
      if category = "playlists" then return 7
      return 7
  end function

  sub onItemSelected(event as object)
      idx = event.getData()
      if idx < 0 or idx >= m.items.count() then return
      stopArtworkTimers()

      item = m.items[idx]
      authData = m.top.authData
      category = m.category

      ' Keep IDs as raw values — cstr() in APITask handles the URL construction safely
      rawId = item.lookUp("id")
      if rawId = invalid then rawId = "0"

      if category = "playlists"
          playlistType = item.lookUp("playlistType")
          if playlistType <> invalid and playlistType <> ""
              m.top.selectedCategory = {
                  category: "local_" + playlistType,
                  title: safeStr(item, ["title", "name"]),
                  libraryId: invalid
              }
              return
          end if
          m.top.selectedVideo = {
              type: "playlist",
              id: rawId,
              title: safeStr(item, ["title", "name"]),
              authData: authData
          }
          return
      end if

      if category = "tvshows"
          idCandidates = []
          idCandidates.push(rawId)
          savedCandidates = item.lookUp("idCandidates")
          if savedCandidates <> invalid
              for each candidate in savedCandidates
                  idCandidates.push(candidate)
              end for
          end if
          mapperId = safeStr(item, ["mapper_id", "mapperId"])
          if mapperId <> "" and mapperId <> "0" then idCandidates.push(mapperId)
          tvshowId = item.lookUp("tvshow_id")
          if tvshowId <> invalid then idCandidates.push(tvshowId)
	          m.top.selectedVideo = {
	              type: "tvshow",
	              id: rawId,
	              idCandidates: idCandidates,
	              title: safeStr(item, ["title", "name"]),
	              mapperId: mapperId,
	              libraryId: m.top.libraryId,
	              sourceLibraryTitle: m.top.pageLabel,
	              posterUrl: posterUrl(item, authData, category),
	              posterRemoteUrl: safeStr(item, ["posterRemoteUrl"]),
	              backdropUrl: backdropUrl(item, authData),
	              backdropRemoteUrl: safeStr(item, ["backdropRemoteUrl"]),
		              originalAvailable: firstNonZeroStr(item, ["originalAvailable", "original_available", "originally_available", "date", "air_date", "year", "create_time"]),
		              authData: authData
		          }
              print "DETAIL_HANDOFF type=tvshow category="; categoryLabel(category); " title="; safeStr(item, ["title", "name"]); " posterSource="; posterSource(item, authData, category); " backdropSource="; backdropSource(item, authData)
	          return
	      end if

      selectVideoItem(item, category)
  end sub

  sub selectVideoItem(item as object, category as string)
      if item = invalid then return
      authData = m.top.authData
      rawId = item.lookUp("id")
      if rawId = invalid then rawId = "0"

      fileInfo = fileInfoFromItem(item)
      rawFileId = fileInfo.id
      if rawFileId = invalid then rawFileId = rawId

      itemType = "video"
      if category = "movies" then itemType = "movie"
      if category = "homevideos" then itemType = "homevideo"
      if category = "tvrecordings" then itemType = "homevideo"
      itemType = playbackTypeForItem(item, category, itemType)
      if itemType = "movie"
          print "MOVIE_SELECT title="; safeStr(item, ["title", "name", "file_name"]); " id="; safeStr({ value: rawId }, ["value"]); " fileId="; safeStr({ value: rawFileId }, ["value"]); " pathLen="; len(fileInfo.path)
      end if
      sourceListKey = localListKeyForCategory(category)
      sourceItemKey = savedItemKey(item)

          m.top.selectedVideo = {
              type: itemType,
	              id: rawId,
	              fileId: rawFileId,
	              mapperId: item.lookUp("mapper_id"),
	              libraryId: m.top.libraryId,
		              filePath: fileInfo.path,
		              originalAvailable: firstNonZeroStr(item, ["originalAvailable", "original_available", "originally_available", "date", "air_date", "year", "create_time"]),
	              title: safeStr(item, ["title", "name", "file_name"]),
	              summary: summaryForDetail(item),
	              watchedRatio: numberForDetail(item, ["watched_ratio", "watchedRatio"]),
	              fileWatched: fileInfo.watched,
	              lastWatched: numberForDetail(item, ["last_watched", "lastWatched"]),
	              rating: numberForDetail(item, ["rating", "rate", "user_rating", "userRating", "my_rating", "myRating"]),
	              posterUrl: posterUrl(item, authData, category),
	              posterRemoteUrl: safeStr(item, ["posterRemoteUrl"]),
	              backdropUrl: backdropUrl(item, authData),
	              backdropRemoteUrl: safeStr(item, ["backdropRemoteUrl"]),
	              seasonNumber: safeStr(item, ["seasonNumber", "season_number", "seasonText", "season", "season_num", "season_index"]),
	              episodeNumber: safeStr(item, ["episodeNumber", "episode_number", "episodeText", "episode", "episode_num", "ep_num", "ep_index"]),
	              episodeMeta: safeStr(item, ["episodeMeta"]),
	              sourceListKey: sourceListKey,
		              sourceItemKey: sourceItemKey,
		              authData: authData
		          }
              print "DETAIL_HANDOFF type="; itemType; " category="; categoryLabel(category); " title="; safeStr(item, ["title", "name", "file_name"]); " posterSource="; posterSource(item, authData, category); " backdropSource="; backdropSource(item, authData)
      end sub

  function summaryForDetail(item as object) as string
      title = safeStr(item, ["title", "name", "file_name"])
      summary = ""
      additional = item.lookUp("additional")
      if additional <> invalid
          summary = safeStr(additional, ["summary", "description"])
          if summary = ""
              extra = additional.lookUp("extra")
              if extra <> invalid then summary = safeStr(extra, ["summary", "description"])
          end if
      end if
      if summary = "" then summary = safeStr(item, ["summary", "description"])
      if summary = "" then summary = safeStr(item, ["tagline"])
      if summary <> "" and title <> "" and lcase(summary.trim()) = lcase(title.trim()) then return ""
      return summary
  end function

  function numberForDetail(item as object, keys as object) as integer
      value = firstNumberFromObject(item, keys)
      if value >= 0 then return value
      additional = item.lookUp("additional")
      if additional <> invalid
          value = firstNumberFromObject(additional, keys)
          if value >= 0 then return value
      end if
      return 0
  end function

  function firstNumberFromObject(item as object, keys as object) as integer
      if item = invalid then return -1
      for each key in keys
          value = item.lookUp(key)
          if value <> invalid
              t = type(value)
              if t = "roInteger" or t = "Integer" then return value
              if t = "roFloat" or t = "Float" then return int(value)
              if t = "roString" or t = "String"
                  trimmed = value.trim()
                  if trimmed <> "" then return int(val(trimmed))
              end if
          end if
      end for
      return -1
  end function

  function localListKeyForCategory(category as string) as string
      if category = "local_favorites" then return "favorites"
      if category = "local_watchlist" then return "watchlist"
      if category = "local_shared" then return "shared"
      return ""
  end function

  function collectionIdForLocalKey(key as string) as string
      if key = "favorites" then return "-1"
      if key = "watchlist" then return "-2"
      if key = "shared" then return "-3"
      return key
  end function

  function mergeLocalItems(remoteItems as object, localItems as object) as object
      merged = []
      for each item in remoteItems
          merged.push(item)
      end for
      for each localItem in localItems
          key = savedItemKey(localItem)
          found = false
          for each existing in merged
              if savedItemKey(existing) = key then found = true
          end for
          if not found then merged.push(localItem)
      end for
      return merged
  end function

  function pendingLocalItems(items as object) as object
      pending = []
      if items = invalid then return pending
      for each item in items
          value = item.lookUp("pendingAdd")
          if value <> invalid and (value = true or value = "true") then pending.push(item)
      end for
      return pending
  end function

  function uniquePlaylistItems(items as object) as object
      unique = []
      if items = invalid then return unique
      for each item in items
          key = playlistUniqueKey(item)
          existingIdx = -1
          i = 0
          while i < unique.count()
              if playlistUniqueKey(unique[i]) = key
                  existingIdx = i
                  exit while
              end if
              i = i + 1
          end while
          if existingIdx < 0
              unique.push(item)
          else if playlistItemScore(item) > playlistItemScore(unique[existingIdx])
              print "PLAYLIST_DEDUPE replace key="; key; " old="; safeStr(unique[existingIdx], ["title", "name", "file_name"]); " new="; safeStr(item, ["title", "name", "file_name"])
              unique[existingIdx] = item
          else
              print "PLAYLIST_DEDUPE keep key="; key; " kept="; safeStr(unique[existingIdx], ["title", "name", "file_name"]); " skipped="; safeStr(item, ["title", "name", "file_name"])
          end if
      end for
      return unique
  end function

  function playlistUniqueKey(item as object) as string
      if item = invalid then return "invalid"
      mapper = safeStr(item, ["mapper_id", "mapperId"])
      if mapper <> "" and mapper <> "0" then return "mapper:" + mapper
      mediaType = safeStr(item, ["type"])
      if mediaType = "" then mediaType = "video"
      idText = safeStr(item, ["id", "videoStationId"])
      if idText <> "" and idText <> "0" then return mediaType + ":" + idText
      fileInfo = fileInfoFromItem(item)
      if fileInfo.path <> "" then return mediaType + ":path:" + lcase(fileInfo.path)
      title = safeStr(item, ["title", "name", "file_name"])
      return mediaType + ":title:" + lcase(title)
  end function

  function playlistItemScore(item as object) as integer
      if item = invalid then return 0
      score = 0
      mediaType = lcase(safeStr(item, ["type"]))
      if mediaType = "episode" or mediaType = "tvshow_episode" then score = score + 60
      if mediaType = "movie" then score = score + 40
      if mediaType = "homevideo" or mediaType = "home_video" then score = score + 30
      idText = safeStr(item, ["id", "videoStationId"])
      if idText <> "" and idText <> "0" and val(idText) > 0 then score = score + 80
      mapper = safeStr(item, ["mapper_id", "mapperId"])
      if mapper <> "" and mapper <> "0" then score = score + 20
      if safeStr(item, ["showTitle", "show_title", "tvshow_title", "series_title", "parent_title"]) <> "" then score = score + 15
      season = safeStr(item, ["seasonNumber", "season_number", "seasonText", "season", "season_num", "season_index"])
      episode = safeStr(item, ["episodeNumber", "episode_number", "episodeText", "episode", "episode_num", "ep_num", "ep_index"])
      if season <> "" and season <> "0" then score = score + 10
      if episode <> "" and episode <> "0" then score = score + 10
      if safeStr(item, ["summary", "description"]) <> "" then score = score + 5
      if fileInfoFromItem(item).path <> "" then score = score + 5
      return score
  end function

  function filterRemovedItems(items as object, removedKeys as object) as object
      if items = invalid then return []
      if removedKeys = invalid or removedKeys.count() = 0 then return items
      filtered = []
      for each item in items
          removed = false
          keys = itemMatchKeys(item)
          for each key in keys
              for each removedKey in removedKeys
                  if removedKey = key then removed = true
              end for
          end for
          if not removed then filtered.push(item)
      end for
      return filtered
  end function

  function itemMatchKeys(item as object) as object
      keys = []
      mainKey = savedItemKey(item)
      if mainKey <> "" then keys.push(mainKey)
      itemType = safeStr(item, ["type"])
      if itemType = "" then itemType = "video"
      idText = safeStr(item, ["id"])
      if idText <> "" and idText <> "0" then keys.push(itemType + ":" + idText)
      fileId = safeStr(item, ["fileId", "file_id"])
      if fileId <> "" and fileId <> "0" then keys.push(itemType + ":file:" + fileId)
      mapper = safeStr(item, ["mapper_id", "mapperId"])
      if mapper <> "" and mapper <> "0" then keys.push(itemType + ":mapper:" + mapper)
      title = safeStr(item, ["title", "name", "file_name"])
      if title <> "" then keys.push(itemType + ":title:" + lcase(title))
      return keys
  end function

  function savedItemKey(item as object) as string
      if item = invalid then return ""
      key = item.lookUp("listKey")
      if key = invalid then key = item.lookUp("listkey")
      if key = invalid then key = item.lookUp("key")
      if key <> invalid and key <> "" then return key
      prefix = safeStr(item, ["type"])
      if prefix = "" then prefix = "video"
      idText = safeStr(item, ["id"])
      if idText <> "" and idText <> "0" then return prefix + ":" + idText
      pathText = safeStr(item, ["filePath", "path"])
      if pathText <> "" then return prefix + ":" + pathText
      return prefix + ":" + safeStr(item, ["title", "name"])
  end function

  function loadLocalList(key as string) as object
      reg = createObject("roRegistrySection", "DSVideoLists")
      if not reg.exists(key) then return []
      raw = reg.read(key)
      if raw = invalid or raw = "" then return []
      parsed = parseJson(raw)
      if parsed = invalid then return []
      return parsed
  end function

  sub showError(msg as string)
      m.top.findNode("errorLabel").text = msg
      m.top.findNode("errorLabel").visible = true
  end sub

  function pageTitleForCategory(category as string) as string
      if category = "local_favorites" then return "Favorites"
      if category = "local_watchlist" then return "Watch List"
      if category = "local_shared" then return "Shared Videos"
      if m.top.pageLabel <> invalid and m.top.pageLabel <> "" then return m.top.pageLabel
      if category = "movies" then return "Movie"
      if category = "tvshows" then return "TV Show"
      if category = "homevideos" then return "Home Video"
      if category = "tvrecordings" then return "TV Recordings"
      if category = "playlists" then return "Playlist"
      return "Library"
  end function

	  function posterUrl(item as object, authData as dynamic, category as string) as string
	      if authData = invalid then return ""
	      savedPoster = item.lookUp("posterUrl")
	      remotePoster = item.lookUp("posterRemoteUrl")
	      if isLocalArtworkUrl(savedPoster)
	          return savedPoster
	      end if
	      synologyPoster = synologyPosterUrl(item, authData, category)
	      if synologyPoster <> ""
	          return synologyPoster
	      end if
	      if remotePoster <> invalid and remotePoster <> "" and isHttpUrl(remotePoster)
	          return remotePoster
	      end if
	      if savedPoster <> invalid and savedPoster <> ""
	          return savedPoster
	      end if
	      return ""
	  end function

      function posterSource(item as object, authData as dynamic, category as string) as string
          savedPoster = item.lookUp("posterUrl")
          if isLocalArtworkUrl(savedPoster) then return "cachefs"
          if synologyPosterUrl(item, authData, category) <> "" then return "synology-poster"
          remotePoster = item.lookUp("posterRemoteUrl")
          if remotePoster <> invalid and remotePoster <> "" and isHttpUrl(remotePoster) then return "remote"
          if savedPoster <> invalid and savedPoster <> "" then return "saved"
          return "none"
      end function

      function remotePosterUrl(item as object, authData as dynamic, category as string) as string
          synologyPoster = synologyPosterUrl(item, authData, category)
          if synologyPoster <> "" then return synologyPoster
          remotePoster = safeStr(item, ["posterRemoteUrl"])
          if isHttpUrl(remotePoster) then return remotePoster
          savedPoster = safeStr(item, ["posterUrl"])
          if isHttpUrl(savedPoster) then return savedPoster
          return posterUrl(item, authData, category)
      end function

      function tvShowProxyPosterAllowed(category as string) as boolean
          if category <> "tvshows" and category <> "ians-shows" then return false
          if m.top.libraryId = invalid then return false
          libraryId = safeStr({ value: m.top.libraryId }, ["value"])
          libraryId = libraryId.trim()
          return libraryId <> "" and libraryId <> "0"
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

      function retryKeyForItem(item as object, idx as integer) as string
          idText = safeStr(item, ["id", "mapper_id", "mapperId", "title", "name"])
          if idText = "" then idText = stri(idx)
          return idText.trim()
      end function

	  function synologyPosterUrl(item as object, authData as dynamic, category as string) as string
	      if authData = invalid then return ""
	      baseUrl = authData.baseUrl
	      sid = authData.sid
	      if baseUrl = invalid or baseUrl = "" or sid = invalid or sid = "" then return ""
	      token = ""
	      if authData.synoToken <> invalid then token = authData.synoToken

	      id = firstNonZeroStr(item, ["posterId", "id", "videoStationId"])
	      if id = "" or id = "0" then id = firstNonZeroStr(item, ["mapper_id", "mapperId"])
	      id = id.trim()
	      if id = "" or id = "0" then return ""

	      mediaType = "movie"
	      if category = "tvshows" then mediaType = "tvshow"
	      if category = "homevideos" then mediaType = "home_video"
	      if category = "tvrecordings" then mediaType = "tv_record"
	      savedType = item.lookUp("type")
	      if savedType <> invalid and savedType <> ""
	          if savedType = "episode" then mediaType = "tvshow_episode"
	          if savedType = "movie" then mediaType = "movie"
	          if savedType = "homevideo" then mediaType = "home_video"
	      end if

	      mtime = posterMtime(item)
	      if mediaType = "tvshow"
	          url = baseUrl + "/webapi/entry.cgi?type=tvshow&id=" + id
	          if mtime <> "" then url = url + "&mtime=" + escapeQueryValue(mtime)
	          url = url + "&api=SYNO.VideoStation2.Poster&method=get&version=1&resolution=%222x%22"
	          url = url + "&_sid=" + sid
	          if token <> "" then url = url + "&SynoToken=" + token
	          return url
	      end if

	      url = baseUrl + "/webapi/entry.cgi?api=SYNO.VideoStation2.Poster&version=1&method=get&_sid=" + sid + "&id=" + id + "&type=" + mediaType
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

	  function backdropUrl(item as object, authData as dynamic) as string
	      savedBackdrop = item.lookUp("backdropUrl")
	      if savedBackdrop <> invalid and savedBackdrop <> "" then return savedBackdrop
	      if authData = invalid then return ""
          synologyBackdrop = synologyBackdropUrl(item, authData)
          if synologyBackdrop <> "" then return synologyBackdrop
	      return ""
	  end function

      function backdropSource(item as object, authData as dynamic) as string
          savedBackdrop = item.lookUp("backdropUrl")
          if isLocalArtworkUrl(savedBackdrop) then return "cachefs"
          if savedBackdrop <> invalid and savedBackdrop <> "" then return backdropSourceFromUrl(savedBackdrop)
          if synologyBackdropUrl(item, authData) <> "" then return "synology-backdrop"
          if authData = invalid then return "none"
          return "none"
      end function

      function backdropSourceFromUrl(url as dynamic) as string
          if url = invalid then return "none"
          if type(url) <> "roString" and type(url) <> "String" then return "saved"
          lower = lcase(url)
          if instr(1, lower, "syno.videostation2.backdrop") > 0 then return "synology-backdrop"
          return "saved"
      end function

      function synologyBackdropUrl(item as object, authData as dynamic) as string
          if authData = invalid then return ""
          baseUrl = authData.baseUrl
          sid = authData.sid
          if baseUrl = invalid or baseUrl = "" or sid = invalid or sid = "" then return ""
          id = firstNonZeroStr(item, ["id", "videoStationId", "mapper_id", "mapperId"])
          id = id.trim()
          if id = "" or id = "0" then return ""
          mediaType = "movie"
          category = m.category
          if category = "tvshows" then mediaType = "tvshow"
          if category = "homevideos" then mediaType = "home_video"
          if category = "tvrecordings" then mediaType = "tv_record"
          savedType = item.lookUp("type")
          if savedType <> invalid and savedType <> ""
              if savedType = "episode" then mediaType = "tvshow_episode"
              if savedType = "movie" then mediaType = "movie"
              if savedType = "homevideo" then mediaType = "home_video"
          end if
          mtime = backdropMtime(item)
          mapper = safeStr(item, ["mapper_id", "mapperId"])
          mapper = mapper.trim()
          if mapper = "" or mapper = "0" then mapper = id
          if mapper <> "" and mapper <> "0"
              url = baseUrl + "/webapi/entry.cgi?mapper_id=" + mapper
              if mtime <> "" then url = url + "&mtime=" + escapeQueryValue(mtime)
              url = url + "&api=SYNO.VideoStation2.Backdrop&method=get&version=1"
              url = url + "&_sid=" + sid
              if authData.synoToken <> invalid and authData.synoToken <> "" then url = url + "&SynoToken=" + authData.synoToken
              return url
          end if

          url = baseUrl + "/webapi/entry.cgi?api=SYNO.VideoStation2.Backdrop&version=1&method=get&_sid=" + sid + "&id=" + id + "&type=" + mediaType
          if mtime <> "" then url = url + "&mtime=" + escapeQueryValue(mtime)
          if authData.synoToken <> invalid and authData.synoToken <> "" then url = url + "&SynoToken=" + authData.synoToken
          return url
      end function

      function backdropMtime(item as object) as string
          mtime = safeStr(item, ["backdrop_mtime", "backdropMtime"])
          if mtime <> "" then return mtime.trim()
          additional = item.lookUp("additional")
          if additional <> invalid
              mtime = safeStr(additional, ["backdrop_mtime", "backdropMtime"])
              if mtime <> "" then return mtime.trim()
          end if
          return ""
      end function

    ' When the VideoGrid Group itself gains focus (e.g. after doBack()),
    ' redirect to the inner grid node so the d-pad works immediately.
    sub onGroupFocusChange(event as object)
        if event.getData() = true
            if left(m.category, 6) = "local_"
                movieGrid = m.top.findNode("playlistMovieGrid")
                episodeGrid = m.top.findNode("playlistEpisodeGrid")
                if movieGrid <> invalid and movieGrid.visible = true
                    movieGrid.setFocus(true)
                    m.focusArea = "playlistMovies"
                    return
                else if episodeGrid <> invalid and episodeGrid.visible = true
                    episodeGrid.setFocus(true)
                    m.focusArea = "playlistEpisodes"
                    return
                end if
            end if
            innerGrid = m.top.findNode("videoGrid")
            if innerGrid <> invalid and innerGrid.visible = true
                innerGrid.setFocus(true)
            end if
        end if
    end sub

  function onKeyEvent(key as string, press as boolean) as boolean
      if not press then return false
      m.lastKey = key
      if key = "up" and m.focusArea = "items"
          cols = 7
          if m.category = "homevideos" or m.category = "tvrecordings" then cols = 3
          if m.focusedIndex < cols
              m.top.findNode("categoryList").setFocus(true)
              m.focusArea = "nav"
              return true
          end if
      end if
      if key = "up" and m.focusArea = "playlistEpisodes"
          movieGrid = m.top.findNode("playlistMovieGrid")
          if movieGrid <> invalid and movieGrid.visible = true
              movieGrid.setFocus(true)
              m.focusArea = "playlistMovies"
              return true
          else if m.playlistMovieItems <> invalid and m.playlistMovieItems.count() > 0
              bottomRowStart = int((m.playlistMovieItems.count() - 1) / 7) * 7
              if focusPlaylistMovieIndex(bottomRowStart) then return true
          end if
          m.top.findNode("categoryList").setFocus(true)
          m.focusArea = "nav"
          return true
      end if
      if key = "up" and m.focusArea = "playlistMovies"
          if m.focusedIndex >= 7
              target = m.focusedIndex - 7
              if focusPlaylistMovieIndex(target) then return true
          end if
          m.top.findNode("categoryList").setFocus(true)
          m.focusArea = "nav"
          return true
      end if
      if key = "left" and m.focusArea = "playlistMovies"
          pageStart = int(m.focusedIndex / 7) * 7
          if m.focusedIndex = pageStart and pageStart > 0
              if focusPlaylistMovieIndex(pageStart - 1) then return true
          end if
      end if
      if key = "down" and m.focusArea = "nav"
          if left(m.category, 6) = "local_"
              movieGrid = m.top.findNode("playlistMovieGrid")
              episodeGrid = m.top.findNode("playlistEpisodeGrid")
              if movieGrid <> invalid and movieGrid.visible = true
                  movieGrid.setFocus(true)
                  m.focusArea = "playlistMovies"
              else if episodeGrid <> invalid and episodeGrid.visible = true
                  episodeGrid.setFocus(true)
                  m.focusArea = "playlistEpisodes"
              end if
          else
              m.top.findNode("videoGrid").setFocus(true)
              m.focusArea = "items"
          end if
          return true
      end if
      if key = "down" and m.focusArea = "playlistMovies"
          if m.playlistMovieItems <> invalid
              currentRow = int(m.focusedIndex / 7)
              nextRowStart = (currentRow + 1) * 7
              if nextRowStart < m.playlistMovieItems.count()
                  target = m.focusedIndex + 7
                  if target >= m.playlistMovieItems.count() then target = nextRowStart
                  if focusPlaylistMovieIndex(target) then return true
              end if
          end if
          if focusPlaylistEpisodeSection() then return true
          return true
      end if
      if key = "down" and m.focusArea = "playlistEpisodes"
          if m.playlistEpisodeItems <> invalid
              currentRow = int(m.focusedIndex / 3)
              nextRowStart = (currentRow + 1) * 3
              if nextRowStart < m.playlistEpisodeItems.count()
                  target = m.focusedIndex + 3
                  if target >= m.playlistEpisodeItems.count() then target = nextRowStart
                  if focusPlaylistEpisodeIndex(target) then return true
              end if
          end if
          return true
      end if
      if key = "down" and m.focusArea = "items"
          if focusNextAvailableGridRowItem() then return true
      end if
      if key = "back"
          if m.focusArea = "nav" then return false
          if left(m.category, 6) = "local_"
              m.top.backPressed = true
              return true
          end if
          m.top.findNode("categoryList").setFocus(true)
          m.focusArea = "nav"
          return true
      end if
      return false
  end function

  function focusNextAvailableGridRowItem() as boolean
      if m.items = invalid then return false
      total = m.items.count()
      if total = 0 then return false

      grid = m.top.findNode("videoGrid")
      if grid = invalid then return false

      idx = m.focusedIndex
      if grid.itemFocused >= 0 then idx = grid.itemFocused
      if idx < 0 or idx >= total - 1 then return false

      cols = 7
      if m.category = "homevideos" or m.category = "tvrecordings" then cols = 3
      belowIdx = idx + cols
      if belowIdx < total then return false

      nextRow = int(idx / cols) + 1
      target = nextRow * cols
      if target >= total then return false
      grid.jumpToItem = target
      grid.setFocus(true)
      m.focusedIndex = target
      m.focusArea = "items"
      schedulePosterRows(target)
      return true
  end function

  sub onNavFocus(event as object)
      if event.getData() = true then m.focusArea = "nav"
  end sub

  sub onNavSelected(event as object)
      idx = event.getData()
      stopArtworkTimers()
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
      focusNavCategory(event.getData())
  end sub

  sub focusNavCategory(category as string)
      idx = categoryIndex(category)
      nav = m.top.findNode("categoryList")
      if idx >= 0 then nav.jumpToItem = idx
      nav.setFocus(true)
      m.focusArea = "nav"
  end sub

  function categoryIndex(category as string) as integer
      i = 0
      while i < m.categories.count()
          if m.categories[i].lookUp("category") = category then return i
          i = i + 1
      end while
      return -1
  end function

  function activeCategoryIndex() as integer
      i = 0
      while i < m.categories.count()
          cat = m.categories[i]
          activeCategory = m.top.category
          if left(activeCategory, 6) = "local_" then activeCategory = "playlists"
          if cat.lookUp("category") = activeCategory
              activeLibrary = m.top.libraryId
              catLibrary = cat.lookUp("libraryId")
              if activeLibrary = invalid or activeLibrary = "" or activeLibrary = catLibrary then return i
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
  
