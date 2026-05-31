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
      nav = m.top.findNode("categoryList")
      nav.observeField("itemSelected", "onNavSelected")
      nav.observeField("itemFocused", "onNavFocused")
      nav.observeField("focus", "onNavFocus")
      m.top.observeField("focusNavCategory", "onFocusNavCategory")
      m.top.observeField("refreshLists", "onRefreshLists")
      m.top.findNode("navLoadTimer").observeField("fire", "onNavLoadTimer")
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
      if m.items.count() = 0
          showError("No items found in this playlist.")
      else
          populateGrid(m.items)
          startArtworkCache(m.items)
      end if
  end sub

  sub onRefreshLists(event as object)
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
      m.category = m.top.category
      populateGrid(items)
      startArtworkCache(items)
  end sub

  sub startArtworkCache(items as object)
      if items = invalid or items.count() = 0 then return
      m.top.artworkCacheRequest = {
          items: items,
          maxItems: 0,
          includeBackdrops: true,
          source: m.category,
          nonce: createCacheNonce()
      }
  end sub

  function createCacheNonce() as string
      dt = createObject("roDateTime")
      stamp = stri(dt.asSeconds()).trim()
      randomPart = stri(rnd(1000000000)).trim()
      return stamp + "-" + randomPart
  end function

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
          if iconUrl = ""
              poster = posterUrl(item, m.top.authData, category)
              if poster <> ""
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

  sub onItemFocused(event as object)
      idx = event.getData()
      if idx < 0 then return
      m.focusedIndex = idx
  end sub

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
          mapperId = item.lookUp("mapper_id")
          if mapperId <> invalid then idCandidates.push(mapperId)
          tvshowId = item.lookUp("tvshow_id")
          if tvshowId <> invalid then idCandidates.push(tvshowId)

	          m.top.selectedVideo = {
	              type: "tvshow",
	              id: rawId,
	              idCandidates: idCandidates,
	              title: safeStr(item, ["title", "name"]),
	              mapperId: item.lookUp("mapper_id"),
	              libraryId: m.top.libraryId,
	              posterUrl: posterUrl(item, authData, category),
	              posterRemoteUrl: safeStr(item, ["posterRemoteUrl"]),
	              backdropUrl: backdropUrl(item, authData),
	              backdropRemoteUrl: safeStr(item, ["backdropRemoteUrl"]),
	              originalAvailable: safeStr(item, ["original_available", "year", "create_time"]),
	              authData: authData
	          }
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
	              summary: safeStr(item, ["summary", "description", "tagline"]),
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
  end sub

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
	      savedPoster = item.lookUp("posterUrl")
	      if savedPoster <> invalid and savedPoster <> "" then return savedPoster
	      if authData = invalid then return ""
	      proxyBase = authData.proxyBaseUrl
	      if proxyBase <> invalid and proxyBase <> ""
	          mapperId = item.lookUp("mapper_id")
	          if mapperId = invalid then mapperId = item.lookUp("mapperId")
	          if mapperId = invalid then mapperId = item.lookUp("id")
	          mapper = safeStr({ value: mapperId }, ["value"])
	          mapper = mapper.trim()
	          if mapper <> "" and mapper <> "0" then return proxyBase + "/poster?mapper_id=" + mapper + "&format=jpg"
	      end if
	      return synologyPosterUrl(item, authData, category)
	  end function

	  function synologyPosterUrl(item as object, authData as dynamic, category as string) as string
	      if authData = invalid then return ""
	      baseUrl = authData.baseUrl
	      sid = authData.sid
	      if baseUrl = invalid or baseUrl = "" or sid = invalid or sid = "" then return ""

	      id = safeStr(item, ["id"])
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

	      return baseUrl + "/webapi/VideoStation/poster.cgi?api=SYNO.VideoStation.Poster&version=2&method=getimage&_sid=" + sid + "&id=" + id + "&type=" + mediaType + "&poster_mtime=" + posterMtime(item)
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
	      proxyBase = authData.proxyBaseUrl
	      if proxyBase = invalid or proxyBase = "" then return ""
	      mapperId = item.lookUp("mapper_id")
	      if mapperId = invalid then mapperId = item.lookUp("mapperId")
	      mapper = safeStr({ value: mapperId }, ["value"])
	      mapper = mapper.trim()
	      if mapper = "" or mapper = "0" then return ""
	      return proxyBase + "/backdrop?mapper_id=" + mapper + "&format=jpg"
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
  
