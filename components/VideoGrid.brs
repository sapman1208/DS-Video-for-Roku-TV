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
              if t = "roInteger" or t = "Integer"
                  s = stri(v)
                  return s.trim()
              end if
              if t = "roFloat" or t = "Float"
                  s = stri(int(v))
                  return s.trim()
              end if
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
      if response <> invalid and response.success = true and response.items <> invalid
          items = response.items
      end if
      items = filterRemovedItems(items, removedItems)
      items = mergeLocalItems(items, filterRemovedItems(localItems, removedItems))
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
          grid.itemSize = [220, 300]
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
      content = createObject("roSGNode", "ContentNode")
      idx = 0

      for each item in items
          node = content.createChild("ContentNode")
          node.title = safeStr(item, ["title", "name", "file_name"])
          if node.title = "" then node.title = "Untitled"
          iconUrl = safeStr(item, ["iconUrl"])
          if category = "homevideos"
              node.addFields({ layoutMode: "homeLandscape" })
              cols = 3
          else if category = "tvrecordings"
              node.addFields({ layoutMode: "landscape" })
              cols = 3
          else if iconUrl <> ""
              node.addFields({ layoutMode: "icon" })
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

          if category = "movies" or left(category, 6) = "local_"
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

  function shouldAssignPosterInitially(category as string, idx as integer, cols as integer) as boolean
      if shouldDeferArtworkCache(category) then return idx < cols * 2
      return true
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
      startRow = row - 2
      endRow = row + 2
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
      if m.initialPosterRetryPass < 2
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

      batchSize = 4
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
      return 3
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
	              posterUrl: posterUrl(item, authData, category),
	              posterRemoteUrl: safeStr(item, ["posterRemoteUrl"]),
	              backdropUrl: backdropUrl(item, authData),
	              backdropRemoteUrl: safeStr(item, ["backdropRemoteUrl"]),
		              originalAvailable: safeStr(item, ["original_available", "year", "create_time"]),
		              authData: authData
		          }
              print "DETAIL_HANDOFF type=tvshow category="; categoryLabel(category); " title="; safeStr(item, ["title", "name"]); " posterSource="; posterSource(item, authData, category); " backdropSource="; backdropSource(item, authData)
	          return
	      end if

      fileInfo = fileInfoFromItem(item)
      rawFileId = fileInfo.id
      if rawFileId = invalid then rawFileId = rawId

      itemType = "video"
      if category = "movies" then itemType = "movie"
      if category = "homevideos" then itemType = "homevideo"
      if category = "tvrecordings" then itemType = "homevideo"
      savedType = item.lookUp("type")
      if savedType <> invalid and savedType <> "" then itemType = savedType
      sourceListKey = localListKeyForCategory(category)
      sourceItemKey = savedItemKey(item)

          m.top.selectedVideo = {
              type: itemType,
	              id: rawId,
	              fileId: rawFileId,
	              mapperId: item.lookUp("mapper_id"),
	              libraryId: m.top.libraryId,
		              filePath: fileInfo.path,
		              originalAvailable: safeStr(item, ["original_available", "year", "create_time"]),
	              title: safeStr(item, ["title", "name", "file_name"]),
	              summary: summaryForDetail(item),
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
      summary = safeStr(item, ["summary", "description", "tagline"])
      if summary <> "" and title <> "" and lcase(summary.trim()) = lcase(title.trim()) then return ""
      return summary
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

	      id = safeStr(item, ["posterId", "videoStationId", "id"])
	      if id = "" or id = "0" then id = safeStr(item, ["mapper_id", "mapperId"])
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
          id = safeStr(item, ["videoStationId", "id", "mapper_id", "mapperId"])
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
      if key = "down" and m.focusArea = "nav"
          m.top.findNode("videoGrid").setFocus(true)
          m.focusArea = "items"
          return true
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

  sub onNavFocus(event as object)
      if event.getData() = true then m.focusArea = "nav"
  end sub

  sub onNavSelected(event as object)
      idx = event.getData()
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
  
