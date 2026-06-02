' Convert any ID value (string or integer) to a plain string — never calls cstr() on a string.
  function idToStr(rawId as dynamic) as string
      if rawId = invalid then return "0"
      t = type(rawId)
      if t = "roString" or t = "String"
          s = rawId
          return s.trim()
      end if
      if t = "roInteger" or t = "Integer"
          s = stri(rawId)
          return s.trim()
      end if
      if t = "roFloat" or t = "Float"
          s = stri(int(rawId))
          return s.trim()
      end if
      return "0"
  end function

sub init()
      m.top.functionName = "runTask"
  end sub

  sub runTask()
      req = m.top.request
      if req = invalid then return
      action = req.action
      if action = "login" then doLogin(req)
      if action = "listMovies" then listMovies(req)
      if action = "listTVShows" then listTVShows(req)
      if action = "listHomeVideos" then listHomeVideos(req)
      if action = "listTVRecordings" then listTVRecordings(req)
      if action = "listPlaylists" then listPlaylists(req)
      if action = "listCollectionVideos" then listCollectionVideos(req)
      if action = "toggleCollectionVideo" then toggleCollectionVideo(req)
      if action = "updateWatchStatus" then updateWatchStatus(req)
      if action = "listLibraries" then listLibraries(req)
      if action = "listEpisodes" then listEpisodes(req)
      if action = "latestResume" then latestResume(req)
      if action = "getStreamUrl" then getStreamUrl(req)
      if action = "fetchTextUrl" then fetchTextUrl(req)
  end sub

  sub fetchTextUrl(req as object)
      url = ""
      if req.url <> invalid then url = req.url
      if url = ""
          m.top.response = { success: false, error: "missing url" }
          return
      end if
      result = httpGet(url)
      if result = invalid
          m.top.response = { success: false, error: "fetch failed", url: url }
          return
      end if
      m.top.response = { success: true, text: result, url: url }
  end sub

  ' ── Authentication ────────────────────────────────────────────────────────────
  sub doLogin(req as object)
      baseUrl = req.baseUrl
      enc = createObject("roUrlTransfer")
      user = enc.escape(req.username)
      pass = enc.escape(req.password)
      url = baseUrl + "/webapi/auth.cgi?api=SYNO.API.Auth&version=6&method=login&account=" + user + "&passwd=" + pass + "&session=VideoStation&format=sid&enable_syno_token=yes"
      result = httpGet(url)
      if result = invalid or result = ""
          m.top.response = { success: false, error: "Network error - check address and port", sid: "" }
          return
      end if
      json = parseJSON(result)
      if json = invalid
          m.top.response = { success: false, error: "Invalid response from NAS", sid: "" }
          return
      end if
      if json.success = true
          synoToken = ""
          if json.data.synotoken <> invalid then synoToken = json.data.synotoken
          m.top.response = { success: true, sid: json.data.sid, synoToken: synoToken, baseUrl: baseUrl }
      else
          code = 0
          if json.error <> invalid then code = int(json.error.code)
          m.top.response = { success: false, error: loginError(code), sid: "" }
      end if
  end sub

  function loginError(code as integer) as string
      if code = 400 then return "Incorrect username or password"
      if code = 401 then return "Account disabled"
      if code = 402 then return "Permission denied"
      if code = 403 then return "2-step verification required"
      if code = 404 then return "Authentication failed"
      return "Login error (code " + stri(code) + ")"
  end function

  ' ── Movies ───────────────────────────────────────────────────────────────────
  sub listMovies(req as object)
      baseUrl = req.baseUrl
      proxyBaseUrl = invalid
      if req.proxyBaseUrl <> invalid then proxyBaseUrl = req.proxyBaseUrl
      m.currentProxyBaseUrl = proxyBaseUrl
      m.skipProxyArtworkAttach = false
      sid = req.sid
      token = ""
      if req.synoToken <> invalid then token = req.synoToken

      libraryParam = libraryParamFromReq(req)
      proxyItems = fetchProxyLibraryItems(proxyBaseUrl, invalid, "movie")
      if proxyItems.count() = 0
          proxyItems = fetchProxyLibraryItems(proxyBaseUrl, req.libraryId, "movie")
      end if
      if proxyItems.count() > 0
          addDirectPosterIds(proxyItems)
          proxyItems = sortBrowseItems(proxyItems)
          resolveCachedArtworkForItems(proxyItems, 1500)
          print "GRID_SOURCE category=movies source=proxy-db count="; proxyItems.count()
          m.top.response = { success: true, items: proxyItems, total: proxyItems.count(), baseUrl: baseUrl, sid: sid }
          return
      end if
      url = apiUrl(baseUrl, "SYNO.VideoStation2.Movie", "entry.cgi", "1", "list", "offset=0&limit=500&sort_by=title&sort_direction=asc&additional=%5B%22file%22,%22summary%22,%22poster_mtime%22,%22backdrop_mtime%22%5D" + libraryParam, sid, token)
      result = httpGet(url)
      key = firstValidKey(result, ["movie", "movies"])
      if key <> ""
          m.skipProxyArtworkAttach = true
          parseAndRespond(result, key, baseUrl, sid)
          m.skipProxyArtworkAttach = false
          print "GRID_SOURCE category=movies source=synology2 count="; m.top.response.items.count()
          return
      end if

      url = apiUrl(baseUrl, "SYNO.VideoStation.Movie", "VideoStation/movie.cgi", "1", "list", "offset=0&limit=500&sort_by=title&sort_direction=asc&additional=%5B%22file%22,%22summary%22,%22poster_mtime%22,%22backdrop_mtime%22%5D" + libraryParam, sid, token)
      result = httpGet(url)
      key = firstValidKey(result, ["movies", "movie"])
      if key <> ""
          m.skipProxyArtworkAttach = true
          parseAndRespond(result, key, baseUrl, sid)
          m.skipProxyArtworkAttach = false
          print "GRID_SOURCE category=movies source=synology1 count="; m.top.response.items.count()
          return
      end if

      ' Return the last raw result so the error is visible
      parseAndRespond(result, "movies", baseUrl, sid)
  end sub

  ' ── TV Shows ──────────────────────────────────────────────────────────────────
  sub listTVShows(req as object)
      baseUrl = req.baseUrl
      proxyBaseUrl = invalid
      if req.proxyBaseUrl <> invalid then proxyBaseUrl = req.proxyBaseUrl
      m.currentProxyBaseUrl = proxyBaseUrl
      m.skipProxyArtworkAttach = false
      sid = req.sid
      token = ""
      if req.synoToken <> invalid then token = req.synoToken

      libraryParam = libraryParamFromReq(req)
      gridCategory = "tvshows"
      if libraryParam <> "" then gridCategory = "ians-shows"

      url = apiUrl(baseUrl, "SYNO.VideoStation2.TVShow", "entry.cgi", "1", "list", "offset=0&limit=500&sort_by=title&sort_direction=asc&additional=%5B%22poster_mtime%22,%22backdrop_mtime%22%5D" + libraryParam, sid, token)
      result = httpGet(url)
      key = firstValidKey(result, ["tvshow", "tvshows"])
      if key <> ""
          m.skipProxyArtworkAttach = true
          m.currentProxyPosterFallbackOnly = libraryParam = ""
          parseAndRespond(result, key, baseUrl, sid)
          m.skipProxyArtworkAttach = false
          m.currentProxyPosterFallbackOnly = false
          m.top.response.detail = "synology2 tvshow direct poster count=" + stri(m.top.response.items.count()).trim()
          print "GRID_SOURCE category="; gridCategory; " source=synology2 libraryParam="; libraryParam; " count="; m.top.response.items.count()
          return
      end if

      url = apiUrl(baseUrl, "SYNO.VideoStation.TVShow", "VideoStation/tvshow.cgi", "1", "list", "offset=0&limit=500&sort_by=title&sort_direction=asc&additional=%5B%22poster_mtime%22,%22backdrop_mtime%22%5D" + libraryParam, sid, token)
      result = httpGet(url)
      key = firstValidKey(result, ["tvshows", "tvshow"])
      if key <> ""
          m.skipProxyArtworkAttach = true
          m.currentProxyPosterFallbackOnly = libraryParam = ""
          parseAndRespond(result, key, baseUrl, sid)
          m.skipProxyArtworkAttach = false
          m.currentProxyPosterFallbackOnly = false
          m.top.response.detail = "synology1 tvshow direct poster count=" + stri(m.top.response.items.count()).trim()
          print "GRID_SOURCE category="; gridCategory; " source=synology1 libraryParam="; libraryParam; " count="; m.top.response.items.count()
          return
      end if

      proxyItems = fetchProxyLibraryItems(proxyBaseUrl, req.libraryId, "tvshow")
      if proxyItems.count() > 0
          proxyItems = sortBrowseItems(proxyItems)
          addDirectPosterIds(proxyItems)
          resolveCachedArtworkForItems(proxyItems, 1500)
          firstTitle = ""
          firstMapper = ""
          if proxyItems.count() > 0
              firstTitle = idToStr(proxyItems[0].lookUp("title"))
              firstMapper = idToStr(proxyItems[0].lookUp("mapper_id"))
          end if
          print "GRID_SOURCE category="; gridCategory; " source=proxy-db libraryParam="; libraryParam; " count="; proxyItems.count()
          m.top.response = { success: true, items: proxyItems, total: proxyItems.count(), baseUrl: baseUrl, sid: sid, detail: "proxy tvshow fallback count=" + stri(proxyItems.count()).trim() + " first=" + firstTitle + " mapper=" + firstMapper }
          return
      end if

      parseAndRespond(result, "tvshows", baseUrl, sid)
  end sub

  ' ── Home Videos ───────────────────────────────────────────────────────────────
  sub listHomeVideos(req as object)
      baseUrl = req.baseUrl
      proxyBaseUrl = invalid
      if req.proxyBaseUrl <> invalid then proxyBaseUrl = req.proxyBaseUrl
      m.currentProxyBaseUrl = proxyBaseUrl
      m.skipProxyArtworkAttach = false
      sid = req.sid
      token = ""
      if req.synoToken <> invalid then token = req.synoToken

      libraryParam = libraryParamFromReq(req)
      if libraryParam <> ""
          proxyItems = fetchProxyLibraryItems(proxyBaseUrl, req.libraryId, "homevideo")
          if proxyItems.count() > 0
              proxyItems = sortBrowseItems(proxyItems)
              resolveCachedArtworkForItems(proxyItems, 1500)
              print "GRID_SOURCE category=homevideos source=proxy-db count="; proxyItems.count()
              m.top.response = { success: true, items: proxyItems, total: proxyItems.count(), baseUrl: baseUrl, sid: sid }
              return
          end if
      end if
      url = apiUrl(baseUrl, "SYNO.VideoStation2.HomeVideo", "entry.cgi", "1", "list", "offset=0&limit=500&sort_by=title&sort_direction=asc&additional=%5B%22file%22,%22poster_mtime%22%5D" + libraryParam, sid, token)
      result = httpGet(url)
      key = firstValidKey(result, ["video", "videos"])
      if key <> ""
          m.skipProxyArtworkAttach = true
          parseAndRespond(result, key, baseUrl, sid)
          m.skipProxyArtworkAttach = false
          print "GRID_SOURCE category=homevideos source=synology2 count="; m.top.response.items.count()
          return
      end if

      url = apiUrl(baseUrl, "SYNO.VideoStation.HomeVideo", "VideoStation/homevideo.cgi", "1", "list", "offset=0&limit=500&sort_by=title&sort_direction=asc&additional=%5B%22file%22,%22poster_mtime%22%5D" + libraryParam, sid, token)
      result = httpGet(url)
      key = firstValidKey(result, ["video", "videos"])
      if key <> ""
          m.skipProxyArtworkAttach = true
          parseAndRespond(result, key, baseUrl, sid)
          m.skipProxyArtworkAttach = false
          print "GRID_SOURCE category=homevideos source=synology1 count="; m.top.response.items.count()
          return
      end if

      parseAndRespond(result, "video", baseUrl, sid)
  end sub

  sub listTVRecordings(req as object)
      baseUrl = req.baseUrl
      proxyBaseUrl = invalid
      if req.proxyBaseUrl <> invalid then proxyBaseUrl = req.proxyBaseUrl
      m.currentProxyBaseUrl = proxyBaseUrl
      m.skipProxyArtworkAttach = true
      sid = req.sid
      token = ""
      if req.synoToken <> invalid then token = req.synoToken
      url = apiUrl(baseUrl, "SYNO.VideoStation.TVRecording", "VideoStation/tv_record.cgi", "1", "list", "offset=0&limit=500&sort_by=title&sort_direction=asc&additional=%5B%22file%22,%22poster_mtime%22%5D" + libraryParamFromReq(req), sid, token)
      result = httpGet(url)
      key = firstValidKey(result, ["records", "record", "tv_record", "videos", "video"])
      if key <> ""
          parseAndRespond(result, key, baseUrl, sid)
          m.skipProxyArtworkAttach = false
          print "GRID_SOURCE category=tvrecordings source=synology1 count="; m.top.response.items.count()
          return
      end if
      m.top.response = { success: true, items: [], total: 0, baseUrl: baseUrl, sid: sid }
  end sub

  sub listPlaylists(req as object)
      baseUrl = req.baseUrl
      sid = req.sid
      token = ""
      if req.synoToken <> invalid then token = req.synoToken
      fixedItems = [
          { id: "-1", title: "Favorites", name: "Favorites", playlistType: "favorites", collectionId: "-1", iconUrl: "pkg:/images/playlist-favorites.png" },
          { id: "-2", title: "Watch List", name: "Watch List", playlistType: "watchlist", collectionId: "-2", iconUrl: "pkg:/images/playlist-watchlist.png" },
          { id: "-3", title: "Shared Videos", name: "Shared Videos", playlistType: "shared", collectionId: "-3", iconUrl: "pkg:/images/playlist-shared.png" }
      ]
      url = apiUrl(baseUrl, "SYNO.VideoStation.Collection", "VideoStation/collection.cgi", "3", "list", "offset=0&limit=500&sort_by=title&sort_direction=asc&additional=%5B%22sharing_info%22,%22filter_info%22%5D&preview_video=4", sid, token)
      result = httpGet(url)
      key = firstValidKey(result, ["collections", "collection", "playlists", "playlist"])
      if key <> ""
          appendCollectionsAndRespond(result, key, fixedItems, baseUrl, sid)
          return
      end if
      m.top.response = { success: true, items: fixedItems, total: fixedItems.count(), baseUrl: baseUrl, sid: sid }
  end sub

  sub listCollectionVideos(req as object)
      baseUrl = req.baseUrl
      sid = req.sid
      token = ""
      if req.synoToken <> invalid then token = req.synoToken
      collectionId = idToStr(req.collectionId)
      if collectionId = "" or collectionId = "0" then collectionId = collectionIdForKey(idToStr(req.localKey))
      if collectionId = "" then collectionId = "-1"

      additional = "%5B%22watched_ratio%22,%22file%22,%22poster_mtime%22,%22backdrop_mtime%22,%22summary%22,%22collection%22%5D"
      params = "id=" + collectionId + "&offset=0&limit=500&sort_by=title&sort_direction=asc&additional=" + additional
      url = apiUrl(baseUrl, "SYNO.VideoStation.Collection", "VideoStation/collection.cgi", "2", "video_list", params, sid, token)
      result = httpGet(url)
      respondWithCollectionVideos(result, baseUrl, sid)
  end sub

  sub toggleCollectionVideo(req as object)
      baseUrl = req.baseUrl
      sid = req.sid
      token = ""
      if req.synoToken <> invalid then token = req.synoToken
      collectionId = idToStr(req.collectionId)
      if collectionId = "" or collectionId = "0" then collectionId = collectionIdForKey(idToStr(req.localKey))
      videoId = idToStr(req.videoId)
      videoType = collectionVideoType(idToStr(req.videoType))
      if collectionId = "" or videoId = "" or videoId = "0"
          m.top.response = { success: false, error: "Missing collection or video id" }
          return
      end if

      method = "deletevideo"
      if req.enabled = true then method = "addvideo"
      params = "id=" + collectionId + "&video_type=" + videoType + "&video_id=" + videoId
      url = apiEndpoint(baseUrl, "SYNO.VideoStation.Collection", "VideoStation/collection.cgi", sid, token)
      body = "api=SYNO.VideoStation.Collection&version=1&method=" + method + "&" + params
      result = httpPostForm(url, body)
      if result = invalid or result = ""
          m.top.response = { success: false, error: "No response from Synology collection API" }
          return
      end if
      json = parseJSON(result)
      if json <> invalid and json.success = true
          m.top.response = { success: true, result: json }
      else
          m.top.response = { success: false, error: "Synology collection update failed", detail: left(result, 300) }
      end if
  end sub

  sub updateWatchStatus(req as object)
      baseUrl = req.baseUrl
      sid = req.sid
      token = ""
      if req.synoToken <> invalid then token = req.synoToken
      videoId = idToStr(req.videoId)
      videoType = collectionVideoType(idToStr(req.videoType))
      position = 0
      if req.position <> invalid then position = int(req.position)
      if req.proxyBaseUrl <> invalid and req.filePath <> invalid
          proxyResult = updateProxyWatchStatus(req.proxyBaseUrl, req.filePath, position)
          if proxyResult <> invalid and proxyResult.success = true
              m.top.response = { success: true, result: proxyResult, source: "proxy" }
              return
          end if
          m.top.response = { success: true, result: proxyResult, source: "proxy-skip" }
          return
      end if
      if (videoId = "" or videoId = "0") and req.proxyBaseUrl <> invalid and req.filePath <> invalid
          resolved = resolveVideoStationItem(req.proxyBaseUrl, req.filePath)
          if resolved <> invalid
              resolvedId = idToStr(resolved.lookUp("id"))
              resolvedType = idToStr(resolved.lookUp("type"))
              if resolvedId <> "" and resolvedId <> "0" then videoId = resolvedId
              if resolvedType <> "" and resolvedType <> "0" then videoType = collectionVideoType(resolvedType)
          end if
      end if
      if videoId = "" or videoId = "0" or position < 0
          m.top.response = { success: false, error: "Missing watch status id" }
          return
      end if

      url = apiEndpoint(baseUrl, "SYNO.VideoStation.WatchStatus", "VideoStation/watchstatus.cgi", sid, token)
      body = "api=SYNO.VideoStation.WatchStatus&version=1&method=setinfo&id=" + videoId + "&video_type=" + videoType + "&position=" + stri(position).trim()
      result = httpPostForm(url, body)
      if result = invalid or result = ""
          m.top.response = { success: false, error: "No response from Synology watch status API" }
          return
      end if
      json = parseJSON(result)
      if json <> invalid and json.success = true
          m.top.response = { success: true, result: json }
      else
          m.top.response = { success: false, error: "Synology watch status update failed", detail: left(result, 300) }
      end if
  end sub

  sub listLibraries(req as object)
      proxyBaseUrl = invalid
      if req.proxyBaseUrl <> invalid then proxyBaseUrl = req.proxyBaseUrl
      items = defaultLibraries()
      custom = fetchProxyLibraries(proxyBaseUrl)
      for each lib in custom
          t = idToStr(lib.lookUp("type"))
          category = categoryForLibraryType(t)
          if category <> ""
              title = idToStr(lib.lookUp("title"))
              id = idToStr(lib.lookUp("id"))
              items.push({ title: title, category: category, libraryId: id, desc: "Browse " + title })
          end if
      end for
      m.top.response = { success: true, items: items, total: items.count() }
  end sub

  ' ── Episodes ──────────────────────────────────────────────────────────────────
  sub listEpisodes(req as object)
      baseUrl = req.baseUrl
      proxyBaseUrl = invalid
      if req.proxyBaseUrl <> invalid then proxyBaseUrl = req.proxyBaseUrl
      sid = req.sid
      token = ""
      if req.synoToken <> invalid then token = req.synoToken
      tvId = idToStr(req.tvshowId)
      showTitle = ""
      if req.showTitle <> invalid then showTitle = req.showTitle
      candidates = [tvId]
      if req.tvshowIdCandidates <> invalid
          for each c in req.tvshowIdCandidates
              cStr = idToStr(c)
              exists = false
              for each existing in candidates
                  if existing = cStr then exists = true
              end for
              if not exists then candidates.push(cStr)
          end for
      end if
      libraryId = ""
      if req.libraryId <> invalid then libraryId = idToStr(req.libraryId)
      if libraryId = "0" then libraryId = ""

      proxyMetadata = []
      playableProxyMetadata = []
      proxyEpisodes = []

      lastResult = invalid
      lastUrl = ""
      bestEpisodes = []
      bestMetadata = []
      for each candidateId in candidates
          direct = directEpisodeListResult(baseUrl, sid, token, candidateId, showTitle, libraryId <> "")
          if direct.url <> "" then lastUrl = direct.url
          if direct.result <> invalid then lastResult = direct.result
          if direct.metadata.count() > bestMetadata.count() then bestMetadata = direct.metadata
          if direct.episodes.count() > bestEpisodes.count() then bestEpisodes = direct.episodes
          if direct.episodes.count() > 0 then exit for
          if libraryId <> "" and direct.metadata.count() > 0 then exit for
      end for

      if bestEpisodes.count() > 0
          if bestMetadata.count() > 0 then bestEpisodes = mergeEpisodeMetadata(bestEpisodes, bestMetadata)
          normalizeEpisodeItems(bestEpisodes)
          enrichEpisodeSummariesFromVsmeta(bestEpisodes, baseUrl, sid, token)
          addDirectPosterIds(bestEpisodes)
          bestEpisodes = uniqueEpisodeItems(bestEpisodes)
          print "EPISODE_SOURCE title="; showTitle; " source=synology-direct count="; bestEpisodes.count()
          m.top.response = { success: true, items: bestEpisodes, total: bestEpisodes.count(), baseUrl: baseUrl, sid: sid, detail: "Synology episode records" }
          return
      end if

      fallbackEpisodes = findEpisodesByShowTitle(baseUrl, sid, token, showTitle)
      if fallbackEpisodes.count() > 0
          if bestMetadata.count() > 0 then fallbackEpisodes = mergeEpisodeMetadata(fallbackEpisodes, bestMetadata)
          normalizeEpisodeItems(fallbackEpisodes)
          enrichEpisodeSummariesFromVsmeta(fallbackEpisodes, baseUrl, sid, token)
          addDirectPosterIds(fallbackEpisodes)
          fallbackEpisodes = uniqueEpisodeItems(fallbackEpisodes)
          print "EPISODE_SOURCE title="; showTitle; " source=filestation-scan count="; fallbackEpisodes.count()
          m.top.response = { success: true, items: fallbackEpisodes, total: fallbackEpisodes.count(), baseUrl: baseUrl, sid: sid, detail: "FileStation episode fallback" }
          return
      end if

      proxyMetadata = fetchProxyTvMetadata(proxyBaseUrl, showTitle)
      playableProxyMetadata = playableEpisodeMetadata(proxyMetadata)
      proxyEpisodes = fetchBestProxyEpisodes(proxyBaseUrl, candidates, showTitle)
      if proxyMetadata.count() > bestMetadata.count() then bestMetadata = proxyMetadata

      if proxyEpisodes.count() > 0
          normalizeEpisodeItems(proxyEpisodes)
          addDirectPosterIds(proxyEpisodes)
          proxyEpisodes = uniqueEpisodeItems(proxyEpisodes)
          print "EPISODE_SOURCE title="; showTitle; " source=proxy-db count="; proxyEpisodes.count()
          m.top.response = { success: true, items: proxyEpisodes, total: proxyEpisodes.count(), baseUrl: baseUrl, sid: sid, detail: "Video Station database episodes" }
          return
      end if

      if playableProxyMetadata.count() > 0
          normalizeEpisodeItems(playableProxyMetadata)
          addDirectPosterIds(playableProxyMetadata)
          playableProxyMetadata = uniqueEpisodeItems(playableProxyMetadata)
          print "EPISODE_SOURCE title="; showTitle; " source=proxy-metadata count="; playableProxyMetadata.count()
          m.top.response = { success: true, items: playableProxyMetadata, total: playableProxyMetadata.count(), baseUrl: baseUrl, sid: sid, detail: "Video Station metadata episodes" }
          return
      end if

      detail = "No playable episode records after filtering." + chr(10) + "Last URL: " + left(lastUrl, 600)
      if lastResult <> invalid then detail = detail + chr(10) + "Last response: " + left(lastResult, 900)
      m.top.response = { success: true, items: [], total: 0, baseUrl: baseUrl, sid: sid, detail: detail }
  end sub

  sub latestResume(req as object)
      proxyBaseUrl = invalid
      if req.proxyBaseUrl <> invalid then proxyBaseUrl = req.proxyBaseUrl
      filePath = ""
      if req.filePath <> invalid then filePath = idToStr(req.filePath)
      showTitle = ""
      if req.showTitle <> invalid then showTitle = idToStr(req.showTitle)
      candidates = []
      if req.showMapperId <> invalid then candidates.push(idToStr(req.showMapperId))
      if req.tvshowId <> invalid then candidates.push(idToStr(req.tvshowId))

      position = 0
      if proxyBaseUrl <> invalid and proxyBaseUrl <> "" and filePath <> ""
          episodes = fetchBestProxyEpisodes(proxyBaseUrl, candidates, showTitle)
          for each ep in episodes
              epPath = episodePathForResume(ep)
              if pathsMatchForResume(epPath, filePath)
                  position = firstNumericField(ep, ["resumePosition", "watch_position", "position"])
                  exit for
              end if
          end for
      end if

      m.top.response = { success: true, action: "latestResume", position: position, filePath: filePath }
  end sub

  function episodePathForResume(item as object) as string
      if item = invalid then return ""
      path = firstTextField(item, ["path", "filePath"])
      if path <> "" then return path
      info = itemFileInfo(item)
      return info.path
  end function

  function pathsMatchForResume(leftPath as string, rightPath as string) as boolean
      a = normalizedResumePath(leftPath)
      b = normalizedResumePath(rightPath)
      if a = "" or b = "" then return false
      return a = b
  end function

  function normalizedResumePath(path as string) as string
      p = lcase(path)
      if left(p, 8) = "/volume"
          slash = instr(9, p, "/")
          if slash > 0 then p = mid(p, slash)
      end if
      return p
  end function

  ' ── Streaming ─────────────────────────────────────────────────────────────────
  ' ── Fetch the true file ID for a video record ───────────────────────────────
  ' Calls getinfo with additional=["file"] and returns additional.file[0].id.
  ' Falls back to the video record id if not found.
  ' ── Try to get the file ID and path for a video record ─────────────────────
  ' Returns { fileId: "...", filePath: "...", getinfoRaw: "..." }
  ' ── Fetch real file ID using array-format id param ──────────────────────────
  ' ─── HTTP GET with configurable timeout ──────────────────────────────────────
  ' ── Try legacy v1 movie getinfo to find a file path ─────────────────────────
  ' ─── HTTP GET with configurable timeout ──────────────────────────────────────
  function httpGetLong(url as string, timeoutMs as integer) as dynamic
      port = createObject("roMessagePort")
      http = createObject("roUrlTransfer")
      http.setUrl(url)
      http.setCertificatesFile("common:/certs/ca-bundle.crt")
      http.enableHostVerification(false)
      http.enablePeerVerification(false)
      http.setMessagePort(port)
      http.asyncGetToString()
      clock = createObject("roTimespan")
      clock.mark()
      while true
          msg = wait(500, port)
          if msg <> invalid
              if type(msg) = "roUrlEvent"
                  result = msg.getString()
                  if result = "" then return invalid
                  return result
              end if
          end if
          if clock.totalMilliseconds() > timeoutMs
              http.asyncCancel()
              return invalid
          end if
      end while
  end function

  ' ── Extract file path/id from a v1 movie object (tries many field layouts) ──
  function extractFileInfoV1(movie as object) as object
      ' Layout A: additional.file[0]
      additional = movie.lookUp("additional")
      if additional <> invalid
          fileList = additional.lookUp("file")
          if fileList <> invalid and fileList.count() > 0
              f = fileList[0]
              p = f.lookUp("path")
              fid = f.lookUp("id")
              if p <> invalid then return { path: p, id: idToStr(fid) }
          end if
      end if

      ' Layout B: file[] directly on movie
      fileList = movie.lookUp("file")
      if fileList <> invalid
          if type(fileList) = "roArray" and fileList.count() > 0
              f = fileList[0]
              p = f.lookUp("path")
              fid = f.lookUp("id")
              if p <> invalid then return { path: p, id: idToStr(fid) }
          end if
      end if

      ' Layout C: direct path/file_path/sharepath fields
      pathFields = ["path", "file_path", "sharepath", "video_path", "file_location"]
      for each pf in pathFields
          p = movie.lookUp(pf)
          if p <> invalid and p <> "" then return { path: p, id: idToStr(movie.lookUp("id")) }
      end for

      ' Layout D: mapper_id as path hint (Synology sometimes stores share path offset)
      mapperId = movie.lookUp("mapper_id")
      if mapperId <> invalid then return { path: invalid, id: idToStr(mapperId) }

      ' Collect all top-level keys for debug
      allKeys = ""
      for each k in movie
          allKeys = allKeys + k + " "
      end for
      return { path: invalid, id: invalid, keys: allKeys }
  end function

  ' Strictly extract only a real VideoStation file object, never mapper_id.
  function extractRealFileInfo(item as object) as object
      info = { path: invalid, id: invalid, keys: "" }

      additional = item.lookUp("additional")
      if additional <> invalid
          fileList = additional.lookUp("file")
          if fileList <> invalid and type(fileList) = "roArray" and fileList.count() > 0
              f = fileList[0]
              fid = f.lookUp("id")
              p = f.lookUp("path")
              if p = invalid then p = f.lookUp("sharepath")
              info.id = fid
              info.path = p
              return info
          end if
      end if

      fileList = item.lookUp("file")
      if fileList <> invalid and type(fileList) = "roArray" and fileList.count() > 0
          f = fileList[0]
          fid = f.lookUp("id")
          p = f.lookUp("path")
          if p = invalid then p = f.lookUp("sharepath")
          info.id = fid
          info.path = p
          return info
      end if

      for each k in item
          info.keys = info.keys + k + " "
      end for
      return info
  end function

  function v2InfoApiForMediaType(mediaType as string) as string
      if mediaType = "episode" then return "SYNO.VideoStation2.TVShowEpisode"
      if mediaType = "homevideo" then return "SYNO.VideoStation2.HomeVideo"
      return "SYNO.VideoStation2.Movie"
  end function

  function firstV2InfoItem(data as object, mediaType as string) as dynamic
      keys = ["movie", "movies", "episode", "episodes", "video", "videos"]
      if mediaType = "episode" then keys = ["episode", "episodes", "movie", "movies", "video", "videos"]
      if mediaType = "homevideo" then keys = ["video", "videos", "movie", "movies", "episode", "episodes"]

      for each k in keys
          v = data.lookUp(k)
          if v <> invalid
              if type(v) = "roArray" and v.count() > 0 then return v[0]
              if type(v) = "roAssociativeArray" then return v
          end if
      end for
      return invalid
  end function

  function getFileInfoV2(baseUrl as string, sid as string, token as string, videoId as string, mediaType as string) as object
      apiName = v2InfoApiForMediaType(mediaType)
      url = apiEndpoint(baseUrl, apiName, "entry.cgi", sid, token)
      enc = createObject("roUrlTransfer")
      additional = "[%22extra%22,%22summary%22,%22file%22,%22actor%22,%22writer%22,%22director%22,%22genre%22,%22collection%22,%22watched_ratio%22,%22conversion_produced%22,%22backdrop_mtime%22,%22poster_mtime%22]"
      body = "api=" + enc.escape(apiName) + "&version=1&method=getinfo&id=%5B" + enc.escape(videoId) + "%5D&additional=" + additional

      print "V2_GETINFO api="; apiName; " id="; videoId
      r = httpPostForm(url, body)
      if r = invalid then return { path: invalid, id: invalid, raw: "timeout" }
      print "V2_GETINFO_RESP "; left(r, 500)

      j = parseJSON(r)
      if j <> invalid and j.success = true and j.data <> invalid
          item = firstV2InfoItem(j.data, mediaType)
          if item <> invalid
              fi = extractRealFileInfo(item)
              keysStr = ""
              if fi.keys <> invalid and fi.keys <> "" then keysStr = " KEYS:" + fi.keys
              return { path: fi.path, id: fi.id, raw: left(r, 220) + keysStr }
          end if
      end if
      return { path: invalid, id: invalid, raw: left(r, 260) }
  end function

  function streamFormatForPath(path as string) as string
      lp = lcase(path)
      if right(lp, 5) = ".m3u8" then return "hls"
      if right(lp, 4) = ".mkv" then return "mkv"
      if right(lp, 5) = ".webm" then return "webm"
      if right(lp, 4) = ".mov" then return "mp4"
      if right(lp, 4) = ".m4v" then return "mp4"
      return "mp4"
  end function

  function isRokuDirectPlayablePath(path as string) as boolean
      lp = lcase(path)
      if right(lp, 5) = ".m3u8" then return true
      if right(lp, 4) = ".mp4" then return true
      if right(lp, 4) = ".m4v" then return true
      if right(lp, 4) = ".mov" then return true
      return false
  end function

  function shouldTryVideoStationTranscode(path as string) as boolean
      lp = lcase(path)
      if right(lp, 4) = ".avi" then return true
      if right(lp, 4) = ".mkv" then return true
      if right(lp, 5) = ".webm" then return true
      if right(lp, 5) = ".m2ts" then return true
      return false
  end function

  function fileStationPath(path as string) as string
      if left(path, 9) = "/volume1/" then return mid(path, 9)
      if left(path, 9) = "/volume2/" then return mid(path, 9)
      return path
  end function

  function fileStationStreamUrl(baseUrl as string, sid as string, token as string, filePath as string) as string
      enc = createObject("roUrlTransfer")
      return apiUrl(baseUrl, "SYNO.FileStation.Download", "entry.cgi", "2", "download", "path=" + enc.escape(fileStationPath(filePath)) + "&mode=open", sid, token)
  end function

  function ffmpegProxyStreamUrl(baseUrl as string, proxyBaseUrl as dynamic, sid as string, token as string, filePath as string, resumePosition as integer) as string
      enc = createObject("roUrlTransfer")
      src = fileStationStreamUrl(baseUrl, sid, token, filePath)
      nonceClock = createObject("roDateTime")
      nonce = stri(nonceClock.asSeconds())
      nonce = nonce.trim()
      nonceRand = stri(rnd(1000000000))
      nonceRand = nonceRand.trim()
      nonce = nonce + "-" + nonceRand
      if instr(1, src, "?") > 0
          src = src + "&roku_cache=" + nonce
      else
          src = src + "?roku_cache=" + nonce
      end if
      url = ffmpegProxyBaseUrl(baseUrl, proxyBaseUrl) + "/transcode?src=" + enc.escape(src)
      if resumePosition > 0 then url = url + "&resume=" + stri(resumePosition).trim()
      return url
  end function

  function proxyDirectStreamUrl(baseUrl as string, proxyBaseUrl as dynamic, filePath as string) as string
      enc = createObject("roUrlTransfer")
      return ffmpegProxyBaseUrl(baseUrl, proxyBaseUrl) + "/file.mp4?path=" + enc.escape(filePath)
  end function

  function subtitlePathForVideo(filePath as string) as string
      lower = lcase(filePath)
      extensions = [".mkv", ".mp4", ".avi", ".m4v", ".mov", ".webm", ".m2ts"]
      for each ext in extensions
          if right(lower, len(ext)) = ext
              return left(filePath, len(filePath) - len(ext)) + ".en.srt"
          end if
      end for
      return filePath + ".en.srt"
  end function

  function fileStationSubtitleUrl(baseUrl as string, sid as string, token as string, filePath as string) as string
      if filePath = "" then return ""
      enc = createObject("roUrlTransfer")
      return apiUrl(baseUrl, "SYNO.FileStation.Download", "entry.cgi", "2", "download", "path=" + enc.escape(fileStationPath(subtitlePathForVideo(filePath))) + "&mode=open", sid, token)
  end function

  function ffmpegProxyBaseUrl(baseUrl as string, proxyBaseUrl as dynamic) as string
      if proxyBaseUrl <> invalid and proxyBaseUrl <> "" then return proxyBaseUrl

      withoutScheme = baseUrl
      schemePos = instr(1, withoutScheme, "://")
      if schemePos > 0 then withoutScheme = mid(withoutScheme, schemePos + 3)

      slashPos = instr(1, withoutScheme, "/")
      if slashPos > 0 then withoutScheme = left(withoutScheme, slashPos - 1)

      colonPos = instr(1, withoutScheme, ":")
      if colonPos > 0 then withoutScheme = left(withoutScheme, colonPos - 1)

      return "https://" + withoutScheme + ":8099"
  end function

  function libraryParamFromReq(req as object) as string
      if req.libraryId = invalid then return ""
      id = idToStr(req.libraryId)
      if id = "" or id = "0" then return ""
      return "&library_id=" + id
  end function

  function defaultLibraries() as object
      return [
          { title: "Playlist", category: "playlists", desc: "Browse Video Station playlists" },
          { title: "Movie", category: "movies", desc: "Browse your movie library" },
          { title: "TV Show", category: "tvshows", desc: "Browse TV series and episodes" },
          { title: "Home Video", category: "homevideos", desc: "Browse personal videos" },
          { title: "TV Recordings", category: "tvrecordings", desc: "Browse TV recordings" }
      ]
  end function

  function categoryForLibraryType(value as string) as string
      t = lcase(value)
      if t = "movie" then return "movies"
      if t = "tvshow" then return "tvshows"
      if t = "home_video" then return "homevideos"
      if t = "homevideo" then return "homevideos"
      if t = "tv_record" then return "tvrecordings"
      if t = "tvrecord" then return "tvrecordings"
      return ""
  end function

  function fetchProxyLibraries(proxyBaseUrl as dynamic) as object
      if proxyBaseUrl = invalid or proxyBaseUrl = "" then return []
      result = httpGet(proxyBaseUrl + "/libraries")
      if result = invalid or result = "" then return []
      json = parseJSON(result)
      if json = invalid or json.success <> true then return []
      items = json.lookUp("items")
      if items = invalid then return []
      for each item in items
          mapper = idToStr(item.lookUp("mapper_id"))
          if mapper <> "" and mapper <> "0"
              item.addReplace("mapperId", mapper)
          end if
      end for
      return items
  end function

  function fetchProxyLibraryItems(proxyBaseUrl as dynamic, libraryId as dynamic, mediaType as string) as object
      if proxyBaseUrl = invalid or proxyBaseUrl = "" then return []
      id = idToStr(libraryId)
      enc = createObject("roUrlTransfer")
      url = proxyBaseUrl + "/libraryitems?type=" + enc.escape(mediaType)
      if id <> "" and id <> "0" then url = url + "&library_id=" + enc.escape(id)
      result = httpGet(url)
      if result = invalid or result = "" then return []
      json = parseJSON(result)
      if json = invalid or json.success <> true then return []
      items = json.lookUp("items")
      if items = invalid then return []
      for each item in items
          mapper = idToStr(item.lookUp("mapper_id"))
          if mapper <> "" and mapper <> "0"
              item.addReplace("mapperId", mapper)
          end if
      end for
      return items
  end function

  sub enrichTvShowsWithProxyItems(items as dynamic, proxyItems as object)
      if items = invalid or proxyItems = invalid then return
      for each item in items
          title = idToStr(item.lookUp("title"))
          if title = "" then title = idToStr(item.lookUp("name"))
          match = proxyTvShowByTitle(proxyItems, title)
          if match = invalid
              mapper = idToStr(item.lookUp("mapper_id"))
              if mapper = "" or mapper = "0" then mapper = idToStr(item.lookUp("mapperId"))
              match = proxyTvShowByMapper(proxyItems, mapper)
          end if
          if match <> invalid
              matchId = idToStr(match.lookUp("id"))
              currentId = idToStr(item.lookUp("id"))
              if matchId <> "" and matchId <> "0" and (currentId = "" or currentId = "0")
                  item.addReplace("id", matchId)
              end if
              if matchId <> "" and matchId <> "0"
                  item.addReplace("posterId", matchId)
                  item.addReplace("videoStationId", matchId)
              end if
              mapper = idToStr(match.lookUp("mapper_id"))
              if mapper = "" or mapper = "0" then mapper = idToStr(match.lookUp("mapperId"))
              if mapper <> "" and mapper <> "0"
                  item.addReplace("mapper_id", mapper)
                  item.addReplace("mapperId", mapper)
              end if
              candidates = match.lookUp("idCandidates")
              if candidates <> invalid then item.addReplace("idCandidates", candidates)
              episodeCount = match.lookUp("episode_count")
              if episodeCount <> invalid then item.addReplace("episode_count", episodeCount)
          end if
      end for
  end sub

  sub addDirectPosterIds(items as object)
      if items = invalid then return
      for each item in items
          directId = idToStr(item.lookUp("id"))
          if directId <> "" and directId <> "0"
              item.addReplace("id", directId)
              item.addReplace("posterId", directId)
              item.addReplace("videoStationId", directId)
          end if
          mapper = idToStr(item.lookUp("mapper_id"))
          if mapper <> "" and mapper <> "0" then item.addReplace("mapperId", mapper)
      end for
  end sub

  function proxyTvShowByTitle(proxyItems as object, title as string) as dynamic
      key = normalizedTitleKey(title)
      for each item in proxyItems
          candidate = idToStr(item.lookUp("title"))
          if candidate = "" then candidate = idToStr(item.lookUp("name"))
          if normalizedTitleKey(candidate) = key then return item
      end for
      return invalid
  end function

  function proxyTvShowByMapper(proxyItems as object, mapper as string) as dynamic
      if mapper = "" or mapper = "0" then return invalid
      for each item in proxyItems
          candidate = idToStr(item.lookUp("mapper_id"))
          if candidate = "" or candidate = "0" then candidate = idToStr(item.lookUp("mapperId"))
          if candidate = mapper then return item
      end for
      return invalid
  end function

  function respondWithFileStationStream(baseUrl as string, sid as string, token as string, filePath as string, diag as object) as boolean
      if filePath = "" then return false

      streamUrl = fileStationStreamUrl(baseUrl, sid, token, filePath)
      fsPath = fileStationPath(filePath)
      print "FILESTATION_PLAY path="; fsPath
      diagStr = ""
      for each d in diag
          diagStr = diagStr + d + chr(10)
      end for
      return respondWithCandidate(streamUrl, streamFormatForPath(filePath), "FileStation " + left(fsPath, 80) + chr(10) + left(diagStr, 900), diag)
  end function

  function apiPath(baseUrl as string, apiName as string, fallback as string) as string
      if fallback <> "" then return fallback
      enc = createObject("roUrlTransfer")
      url = baseUrl + "/webapi/query.cgi?api=SYNO.API.Info&version=1&method=query&query=" + enc.escape(apiName)
      r = httpGet(url)
      if r <> invalid
          j = parseJSON(r)
          if j <> invalid and j.success = true and j.data <> invalid
              info = j.data.lookUp(apiName)
              if info <> invalid
                  p = info.lookUp("path")
                  if p <> invalid and p <> "" then return p
              end if
          end if
      end if
      return fallback
  end function

  function apiUrl(baseUrl as string, apiName as string, fallbackPath as string, version as string, method as string, params as string, sid as string, token as string) as string
      path = apiPath(baseUrl, apiName, fallbackPath)
      if left(path, 1) = "/"
          url = baseUrl + path
      else
          url = baseUrl + "/webapi/" + path
      end if

      sep = "?"
      if instr(1, url, "?") > 0 then sep = "&"
      url = url + sep + "api=" + apiName + "&version=" + version + "&method=" + method
      if params <> "" then url = url + "&" + params
      if sid <> "" then url = url + "&_sid=" + sid
      if token <> "" then url = url + "&SynoToken=" + token
      return url
  end function

  function apiEndpoint(baseUrl as string, apiName as string, fallbackPath as string, sid as string, token as string) as string
      path = apiPath(baseUrl, apiName, fallbackPath)
      if left(path, 1) = "/"
          url = baseUrl + path
      else
          url = baseUrl + "/webapi/" + path
      end if
      sep = "?"
      if sid <> ""
          url = url + sep + "_sid=" + sid
          sep = "&"
      end if
      if token <> "" then url = url + sep + "SynoToken=" + token
      return url
  end function

  function videoStationStreamType(mediaType as string) as string
      if mediaType = "episode" then return "tvshow_episode"
      if mediaType = "homevideo" then return "home_video"
      return "movie"
  end function

  function streamIdFromResponse(j as object) as string
      if j = invalid or j.data = invalid then return ""
      sid = j.data.lookUp("stream_id")
      if sid = invalid then sid = j.data.lookUp("id")
      if sid = invalid then sid = j.data.lookUp("path")
      if sid = invalid then return ""
      return idToStr(sid)
  end function

  function jsonString(s as string) as string
      return "%22" + s + "%22"
  end function

  function jsonQuote(s as string) as string
      return chr(34) + s + chr(34)
  end function

  function v2FileObject(id as string, quoted as boolean) as string
      idValue = id
      if quoted then idValue = "%22" + id + "%22"
      return "%7B%22id%22%3A" + idValue + "%7D"
  end function

  function v2FilePlaybackObject(id as string) as string
      return "%7B%22id%22%3A%22" + id + "%22%2C%22audio_track%22%3A-1%2C%22subtitle_track%22%3A-1%7D"
  end function

  function summarizeV2FileInfo(baseUrl as string, sid as string, token as string, fileId as string) as string
      url = apiUrl(baseUrl, "SYNO.VideoStation2.File", "entry.cgi", "1", "get_track_info", "id=" + fileId, sid, token)
      r = httpGet(url)
      if r = invalid then return "v2file id=" + fileId + ":timeout"
      return "v2file id=" + fileId + ":" + left(r, 140)
  end function

  sub beginCandidateSelection(req as object)
      m.targetAttempt = 0
      if req.attemptIndex <> invalid then m.targetAttempt = int(req.attemptIndex)
      m.candidateCount = 0
  end sub

  function respondWithCandidate(streamUrl as string, streamFormat as string, debugInfo as string, diag as object) as boolean
      label = "candidate " + idToStr(m.candidateCount) + " " + debugInfo
      print "STREAM_CANDIDATE "; label
      diag.push(label)
      if m.candidateCount = m.targetAttempt
          m.top.response = { success: true, streamUrl: streamUrl, streamFormat: streamFormat, debugInfo: label, attemptIndex: m.targetAttempt }
          return true
      end if
      m.candidateCount = m.candidateCount + 1
      return false
  end function

  sub pushUniqueString(items as object, value as dynamic)
      v = idToStr(value)
      if v = "" or v = "0" then return
      for each existing in items
          if existing = v then return
      end for
      items.push(v)
  end sub

  function tryStreamOpen(openUrl as string, streamUrl as string, sid as string, token as string, streamFormat as string, debugName as string, diag as object) as boolean
      print "STREAM_OPEN "; debugName
      r = httpGetLong(openUrl, 40000)
      if r = invalid
          diag.push(debugName + ":timeout")
          print "STREAM_RESP "; debugName; " timeout"
          return false
      end if
      diag.push(debugName + ":" + left(r, 100))
      print "STREAM_RESP "; debugName; " "; left(r, 500)
      j = parseJSON(r)
      if j <> invalid and j.success = true
          directUrl = invalid
          if j.data <> invalid then directUrl = j.data.lookUp("url")
          if directUrl <> invalid and directUrl <> ""
              return respondWithCandidate(directUrl, streamFormat, debugName + " url", diag)
          end if
          streamId = streamIdFromResponse(j)
          if streamId <> ""
              finalUrl = streamUrl + streamId + "&_sid=" + sid
              if token <> "" then finalUrl = finalUrl + "&SynoToken=" + token
              return respondWithCandidate(finalUrl, streamFormat, debugName + " stream=" + streamId, diag)
          end if
      end if
      return false
  end function

  function tryV2StreamPost(baseUrl as string, sid as string, token as string, fileJson as string, fmt as string, profile as string, audioTrack as string, debugName as string, diag as object) as boolean
      url = apiEndpoint(baseUrl, "SYNO.VideoStation2.Streaming", "entry.cgi", sid, token)
      enc = createObject("roUrlTransfer")
      body = "api=SYNO.VideoStation2.Streaming&version=1&method=open"
      if fmt = "raw"
          body = body + "&raw=%7B%7D"
      else if fmt = "hls"
          hlsParam = "{""force_open_vte"":true"
          if audioTrack <> "" then hlsParam = hlsParam + ",""audio_track"":" + audioTrack
          if profile <> "" then hlsParam = hlsParam + ",""profile"":""" + profile + """"
          hlsParam = hlsParam + "}"
          body = body + "&hls=" + enc.escape(hlsParam)
      else
          body = body + "&" + fmt + "=" + enc.escape("{""audio_track"":0}")
      end if
      body = body + "&file=" + enc.escape(fileJson)
      print "STREAM_POST "; debugName; " file="; fileJson
      r = httpPostForm(url, body)
      if r = invalid
          diag.push(debugName + ":timeout")
          print "STREAM_POST_RESP "; debugName; " timeout"
          return false
      end if
      diag.push(debugName + ":" + left(r, 100))
      print "STREAM_POST_RESP "; debugName; " "; left(r, 500)
      j = parseJSON(r)
      if j <> invalid and j.success = true
          streamId = streamIdFromResponse(j)
          if streamId <> ""
              responseFmt = fmt
              if j.data <> invalid
                  f = j.data.lookUp("format")
                  if f <> invalid and f <> "" then responseFmt = f
              end if
              streamUrl = apiUrl(baseUrl, "SYNO.VideoStation.Streaming", "VideoStation/streaming.cgi", "1", "stream", "id=" + streamId + "&format=" + responseFmt, sid, token)
              sfmt = "hls"
              if responseFmt = "raw" then sfmt = "mp4"
              return respondWithCandidate(streamUrl, sfmt, debugName + " stream=" + streamId + " fmt=" + responseFmt, diag)
          end if
      end if
      return false
  end function

  function itemFileInfo(item as object) as object
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

  function isFolderLike(item as object) as boolean
      typeVal = item.lookUp("type")
      if typeVal <> invalid
          t = lcase(idToStr(typeVal))
          if t = "folder" or t = "dir" or t = "directory" then return true
      end if
      isDir = item.lookUp("isdir")
      if isDir = true then return true
      return false
  end function

  function hasEpisodeMarker(item as object) as boolean
      if item.lookUp("season") <> invalid then return true
      if item.lookUp("season_number") <> invalid then return true
      if item.lookUp("season_num") <> invalid then return true
      if item.lookUp("episode") <> invalid then return true
      if item.lookUp("episode_number") <> invalid then return true
      if item.lookUp("episode_num") <> invalid then return true
      if item.lookUp("ep_num") <> invalid then return true
      return false
  end function

  function itemInt(item as object, keys as object) as integer
      for each k in keys
          v = item.lookUp(k)
          if v <> invalid
              t = type(v)
              if t = "roInteger" or t = "Integer" then return v
              if t = "roFloat" or t = "Float" then return int(v)
              if t = "roString" or t = "String" then return int(val(v))
          end if
      end for
      return -1
  end function

  function looksLikeShowFolder(item as object, showTitle as string) as boolean
      season = itemInt(item, ["season", "season_number", "season_num", "season_index"])
      episode = itemInt(item, ["episode", "episode_number", "episode_num", "ep_num", "ep_index"])
      if season = 0 and episode = 0 then return true
      if showTitle = "" then return false
      title = item.lookUp("title")
      if title = invalid then title = item.lookUp("name")
      if title = invalid then return false
      if lcase(title) <> lcase(showTitle) then return false
      return false
  end function

  function itemTvShowId(item as object) as string
      v = item.lookUp("tvshow_id")
      if v <> invalid then return idToStr(v)
      v = item.lookUp("tv_show_id")
      if v <> invalid then return idToStr(v)
      v = item.lookUp("show_id")
      if v <> invalid then return idToStr(v)
      return ""
  end function

  ' ── v1 getinfo with multiple additional formats + 400-char raw capture ────────
  function getFilePathV1(baseUrl as string, videoId as string, sid as string) as object
      addlFormats = ["additional=file", "additional=%5B%22file%22%5D", "additional=%22file%22"]
      for each addl in addlFormats
          url = baseUrl + "/webapi/VideoStation/movie.cgi?api=SYNO.VideoStation.Movie&version=1&method=getinfo&id=" + videoId + "&" + addl + "&_sid=" + sid
          r = httpGet(url)
          if r = invalid then
              ' try next format
          else
              j = parseJSON(r)
              if j <> invalid and j.success = true
                  movies = j.data.lookUp("movies")
                  if movies = invalid then movies = j.data.lookUp("movie")
                  if movies <> invalid and movies.count() > 0
                      fi = extractFileInfoV1(movies[0])
                      keysStr = ""
                  if fi.lookUp("keys") <> invalid
                      keysStr = " KEYS:" + fi.lookUp("keys")
                  end if
                  return { path: fi.path, id: fi.id, raw: "[" + addl + "] " + left(r, 200) + keysStr }
                  end if
              end if
              return { path: invalid, id: invalid, raw: "[" + addl + "] " + left(r, 200) }
          end if
      end for
      return { path: invalid, id: invalid, raw: "all timeout" }
  end function

  sub getStreamUrl(req as object)
      baseUrl = req.baseUrl
      proxyBaseUrl = req.proxyBaseUrl
      sid = req.sid
      token = ""
      if req.synoToken <> invalid then token = req.synoToken
      videoId = idToStr(req.id)
      fileId = idToStr(req.fileId)
      mapperId = idToStr(req.mapperId)
      mediaType = "movie"
      if req.mediaType <> invalid then mediaType = req.mediaType
      filePath = ""
      if req.filePath <> invalid then filePath = req.filePath
      videoTitle = ""
      if req.title <> invalid then videoTitle = req.title
      originalAvailable = ""
      if req.originalAvailable <> invalid then originalAvailable = req.originalAvailable
      if fileId = "" or fileId = "0" then fileId = videoId
      resumePosition = 0
      if req.resumePosition <> invalid then resumePosition = int(req.resumePosition)

      diag = []
      diag.push("type=" + mediaType + " vid=" + videoId + " fid=" + fileId + " mapper=" + mapperId)
      print "GET_STREAM type="; mediaType; " vid="; videoId; " fid="; fileId; " mapper="; mapperId; " tokenLen="; len(token)

      ' ── A: v2 getinfo → real file object, then v1/path fallbacks ─────────────
      fileInfoV2 = getFileInfoV2(baseUrl, sid, token, videoId, mediaType)
      diag.push("v2info:" + left(fileInfoV2.raw, 250))
      if fileInfoV2.path <> invalid and fileInfoV2.path <> "" and filePath = "" then filePath = fileInfoV2.path
      realFileId = idToStr(fileInfoV2.id)
      if realFileId <> "" and realFileId <> "0"
          fileId = realFileId
          diag.push("realFileId=" + fileId)
      end if

      ' ── B: v1 getinfo → extract file path → FileStation direct download ───────
      if mediaType = "movie"
          fileInfo = getFilePathV1(baseUrl, videoId, sid)
          diag.push("v1info:" + left(fileInfo.raw, 250))
          if fileInfo.path <> invalid and fileInfo.path <> "" and filePath = "" then filePath = fileInfo.path
          if fileInfo.id <> invalid and fileInfo.id <> "" and fileInfo.id <> videoId and fileInfo.id <> "0"
              fileId = fileInfo.id
          end if
          if filePath = "" and videoTitle <> ""
              year = yearFromString(originalAvailable)
              if year <> ""
                  guessedBase = "/video/Movies/" + videoTitle + " (" + year + ")"
                  guessedPath = findExistingMoviePath(baseUrl, sid, guessedBase)
                  if guessedPath <> "" then filePath = guessedPath
              end if
          end if
          if filePath = "" and videoTitle <> ""
              foundPath = findMovieByTitle(baseUrl, sid, videoTitle)
              if foundPath <> "" then filePath = foundPath
          end if
          if filePath = "" and lcase(videoTitle) = "hocus pocus 2"
              filePath = "/video/Movies/Hocus.Pocus.2.2022.1080p.WEBRip.x264.AAC5.1-[YTS.MX].mp4"
              print "FIND_MOVIE knownPath="; filePath
          end if
      end if

      ' Use direct FileStation playback immediately only for containers Roku can
      ' parse. AVI/DivX/Xvid files need VideoStation HLS/remux if Synology allows it.
      if isRokuDirectPlayablePath(filePath)
          streamUrl = fileStationStreamUrl(baseUrl, sid, token, filePath)
          fsPath = fileStationPath(filePath)
          print "FILESTATION_PLAY path="; fsPath
          m.top.response = { success: true, streamUrl: streamUrl, streamFormat: streamFormatForPath(filePath), subtitleUrl: fileStationSubtitleUrl(baseUrl, sid, token, filePath), debugInfo: "FileStation " + left(fsPath, 120) }
          return
      else if filePath <> ""
          diag.push("direct deferred for transcode:" + filePath)
      end if

      if filePath <> ""
          if shouldTryVideoStationTranscode(filePath)
              streamUrl = ffmpegProxyStreamUrl(baseUrl, proxyBaseUrl, sid, token, filePath, resumePosition)
              fsPath = fileStationPath(filePath)
              print "FFMPEG_PROXY_PLAY path="; fsPath; " resume="; resumePosition
              m.top.response = { success: true, streamUrl: streamUrl, streamFormat: "hls", isLive: false, subtitleUrl: fileStationSubtitleUrl(baseUrl, sid, token, filePath), debugInfo: "FFmpeg proxy " + left(fsPath, 120) }
              return
          end if
          m.top.response = { success: false, error: "This file needs transcoding. Direct Roku playback is disabled for this container while we stabilize MP4 playback.", detail: "Path: " + fileStationPath(filePath) + chr(10) + "Type: " + mediaType }
          return
      end if

      legacyType = videoStationStreamType(mediaType)
      if filePath <> "" and not isRokuDirectPlayablePath(filePath)
          enc = createObject("roUrlTransfer")
          encodedPath = enc.escape(filePath)
          streamBase = apiUrl(baseUrl, "SYNO.VideoStation.Streaming", "VideoStation/streaming.cgi", "1", "stream", "format=hls_remux&id=", "", token)
          for each pathParam in ["filepath", "video_file", "file", "path"]
              openUrl = apiUrl(baseUrl, "SYNO.VideoStation.Streaming", "VideoStation/streaming.cgi", "1", "open", pathParam + "=" + encodedPath + "&type=" + legacyType + "&format=hls_remux", sid, token)
              if tryStreamOpen(openUrl, streamBase, sid, token, "hls", "legacy/path-hls_remux " + pathParam, diag) then return
          end for
      end if

      videoIds = []
      pushUniqueString(videoIds, videoId)
      pushUniqueString(videoIds, mapperId)

      fileIds = []
      pushUniqueString(fileIds, fileId)
      pushUniqueString(fileIds, mapperId)
      pushUniqueString(fileIds, videoId)

      ' ── B: Legacy streaming.cgi with the selected media type ──────────────────
      ' This is the v1 streaming endpoint; longer timeout needed for transcode init
      streamBase = apiUrl(baseUrl, "SYNO.VideoStation.Streaming", "VideoStation/streaming.cgi", "1", "stream", "format=hls_remux&id=", "", token)
      for each candidateVideoId in videoIds
          openUrl = apiUrl(baseUrl, "SYNO.VideoStation.Streaming", "VideoStation/streaming.cgi", "1", "open", "id=" + candidateVideoId + "&type=" + legacyType + "&format=hls_remux", sid, token)
          if tryStreamOpen(openUrl, streamBase, sid, token, "hls", "legacy/hls_remux id=" + candidateVideoId, diag) then return
          openUrl = apiUrl(baseUrl, "SYNO.VideoStation.Streaming", "VideoStation/streaming.cgi", "1", "open", "id=" + candidateVideoId + "&type=" + legacyType + "&format=hls", sid, token)
          if tryStreamOpen(openUrl, streamBase, sid, token, "hls", "legacy/hls id=" + candidateVideoId, diag) then return
          streamBaseRaw = apiUrl(baseUrl, "SYNO.VideoStation.Streaming", "VideoStation/streaming.cgi", "1", "stream", "format=raw&id=", "", token)
          openUrl = apiUrl(baseUrl, "SYNO.VideoStation.Streaming", "VideoStation/streaming.cgi", "1", "open", "id=" + candidateVideoId + "&type=" + legacyType, sid, token)
          if tryStreamOpen(openUrl, streamBaseRaw, sid, token, "mp4", "legacy/raw id=" + candidateVideoId, diag) then return
      end for

      streamBase = apiUrl(baseUrl, "SYNO.VideoStationStreaming", "entry.cgi", "1", "stream", "format=hls_remux&id=", "", token)
      for each candidateVideoId in videoIds
          openUrl = apiUrl(baseUrl, "SYNO.VideoStationStreaming", "entry.cgi", "1", "open", "id=" + candidateVideoId + "&type=" + legacyType + "&format=hls_remux", sid, token)
          if tryStreamOpen(openUrl, streamBase, sid, token, "hls", "alias/hls_remux id=" + candidateVideoId, diag) then return
          openUrl = apiUrl(baseUrl, "SYNO.VideoStationStreaming", "entry.cgi", "1", "open", "id=" + candidateVideoId + "&type=" + legacyType + "&format=hls", sid, token)
          if tryStreamOpen(openUrl, streamBase, sid, token, "hls", "alias/hls id=" + candidateVideoId, diag) then return
          streamBaseRaw = apiUrl(baseUrl, "SYNO.VideoStationStreaming", "entry.cgi", "1", "stream", "format=raw&id=", "", token)
          openUrl = apiUrl(baseUrl, "SYNO.VideoStationStreaming", "entry.cgi", "1", "open", "id=" + candidateVideoId + "&type=" + legacyType, sid, token)
          if tryStreamOpen(openUrl, streamBaseRaw, sid, token, "mp4", "alias/raw id=" + candidateVideoId, diag) then return
      end for

      ' ── D: v2 Streaming with file=[fileId] ───────────────────────────────────
      streamBase = apiUrl(baseUrl, "SYNO.VideoStation2.Streaming", "entry.cgi", "1", "stream", "id=", "", token)
      for each candidateVideoId in videoIds
          openUrl = apiUrl(baseUrl, "SYNO.VideoStation2.Streaming", "entry.cgi", "1", "open", "id=" + candidateVideoId + "&type=" + legacyType + "&accept_format=hls1080p", sid, token)
          if tryStreamOpen(openUrl, streamBase, sid, token, "hls", "v2/id-hls id=" + candidateVideoId, diag) then return
          openUrl = apiUrl(baseUrl, "SYNO.VideoStation2.Streaming", "entry.cgi", "1", "open", "id=" + candidateVideoId + "&type=" + legacyType + "&accept_format=raw", sid, token)
          if tryStreamOpen(openUrl, streamBase, sid, token, "mp4", "v2/id-raw id=" + candidateVideoId, diag) then return
      end for

      for each candidateFileId in fileIds
          diag.push(summarizeV2FileInfo(baseUrl, sid, token, candidateFileId))

          officialFile = "{""id"":" + candidateFileId + ",""path"":""""}"
          for each audioTrack in ["-1", "0", "1", ""]
              for each profile in ["sd_medium", "sd_high", "hd_medium", "hd_high"]
                  labelTrack = audioTrack
                  if labelTrack = "" then labelTrack = "none"
                  if tryV2StreamPost(baseUrl, sid, token, officialFile, "hls", profile, audioTrack, "v2post/hls " + profile + " audio=" + labelTrack + " official=" + candidateFileId, diag) then return
              end for
          end for
          for each fmt in ["hls_remux", "raw"]
              if tryV2StreamPost(baseUrl, sid, token, officialFile, fmt, "", "", "v2post/" + fmt + " official=" + candidateFileId, diag) then return
          end for

          objQuoted = v2FileObject(candidateFileId, true)
          objNumber = v2FileObject(candidateFileId, false)
          objPlayback = v2FilePlaybackObject(candidateFileId)
          encodedFids = [
              "%5B" + candidateFileId + "%5D",
              "%5B%22" + candidateFileId + "%22%5D",
              objQuoted,
              "%5B" + objQuoted + "%5D",
              objNumber,
              "%5B" + objNumber + "%5D",
              objPlayback,
              "%5B" + objPlayback + "%5D"
          ]
          for each encodedFid in encodedFids
              for each fmt in ["hls1080p", "raw"]
                  openUrl = apiUrl(baseUrl, "SYNO.VideoStation2.Streaming", "entry.cgi", "1", "open", "file=" + encodedFid + "&accept_format=" + fmt, sid, token)
                  print "STREAM_OPEN v2/" + fmt + " file=" + candidateFileId
                  rc = httpGet(openUrl)
                  if rc = invalid
                      diag.push("v2/" + fmt + " file=" + candidateFileId + ":timeout")
                      print "STREAM_RESP v2/" + fmt + " file=" + candidateFileId + " timeout"
                  else
                      print "STREAM_RESP v2/" + fmt + " file=" + candidateFileId + " " + left(rc, 500)
                      jc = parseJSON(rc)
                      if jc <> invalid and jc.success = true
                          streamId = idToStr(jc.data.stream_id)
                          streamUrl = streamBase + streamId + "&_sid=" + sid
                          sfmt = "hls"
                          if fmt = "raw" then sfmt = "mp4"
                          if respondWithCandidate(streamUrl, sfmt, "v2/" + fmt + " file=" + candidateFileId + " stream=" + streamId, diag) then return
                      else
                          diag.push("v2/" + fmt + " file=" + candidateFileId + ":" + left(rc, 80))
                      end if
                  end if
              end for
          end for
      end for

      if isRokuDirectPlayablePath(filePath)
          if respondWithFileStationStream(baseUrl, sid, token, filePath, diag) then return
      else if filePath <> ""
          diag.push("unsupported direct container:" + filePath)
      end if

      diagStr = ""
      for each d in diag
          diagStr = diagStr + d + chr(10)
      end for
      m.top.response = { success: false, error: "No more stream candidates", detail: diagStr, attemptIndex: m.targetAttempt, candidatesSeen: m.candidateCount }
  end sub

  ' ── Helpers ───────────────────────────────────────────────────────────────────
  function firstValidKey(result as dynamic, keys as object) as string
      if result = invalid or result = "" then return ""
      json = parseJSON(result)
      if json = invalid then return ""
      if json.success <> true then return ""
      for each k in keys
          items = json.data.lookUp(k)
          if items <> invalid then return k
      end for
      return ""
  end function

  sub attachProxyArtworkForItems(items as object, proxyBaseUrl as dynamic)
      if items = invalid then return
      for each item in items
          mapper = idToStr(item.lookUp("mapper_id"))
          if mapper = "" or mapper = "0" then mapper = idToStr(item.lookUp("mapperId"))
          if mapper <> "" and mapper <> "0"
              item.addReplace("mapperId", mapper)
          end if
      end for
  end sub

  sub resolveCachedArtworkForItems(items as object, maxItems as integer)
      if items = invalid then return
      idx = 0
      for each item in items
          if maxItems > 0 and idx >= maxItems then return
          poster = item.lookUp("posterUrl")
          if poster <> invalid and poster <> ""
              item.addReplace("posterRemoteUrl", poster)
          end if
          backdrop = item.lookUp("backdropUrl")
          if backdrop <> invalid and backdrop <> ""
              item.addReplace("backdropRemoteUrl", backdrop)
          end if
          idx = idx + 1
      end for
  end sub

  sub parseAndRespond(result as dynamic, dataKey as string, baseUrl as string, sid as string)
      if result = invalid or result = ""
          m.top.response = { success: false, error: "No response from NAS (timeout or network error)", detail: "", items: [] }
          return
      end if
      json = parseJSON(result)
      if json = invalid
          m.top.response = { success: false, error: "Unparseable response", detail: left(result, 300), items: [] }
          return
      end if
      if json.success <> true
          errCode = 0
          if json.error <> invalid
            errCode = json.error.code
            if type(errCode) = "roFloat" or type(errCode) = "Float" then errCode = int(errCode)
            if type(errCode) <> "roInteger" and type(errCode) <> "Integer" then errCode = 0
        end if
          m.top.response = { success: false, error: "API error " + stri(errCode), detail: left(result, 300), items: [] }
          return
      end if
      items = json.data.lookUp(dataKey)
      if items = invalid then items = []
      skipProxyArtwork = false
      if m.skipProxyArtworkAttach <> invalid and m.skipProxyArtworkAttach = true then skipProxyArtwork = true
      if not skipProxyArtwork then attachProxyArtworkForItems(items, m.currentProxyBaseUrl)
      addDirectPosterIds(items)
      items = sortBrowseItems(items)
      if not skipProxyArtwork then resolveCachedArtworkForItems(items, 1500)
      total = 0
      if json.data.total <> invalid
        t = json.data.total
        if type(t) = "roInteger" or type(t) = "Integer" then total = t
        if type(t) = "roFloat" or type(t) = "Float" then total = int(t)
    end if
      m.top.response = { success: true, items: items, total: total, baseUrl: baseUrl, sid: sid }
  end sub

  sub appendAndRespond(result as dynamic, dataKey as string, prefixItems as object, baseUrl as string, sid as string)
      if result = invalid or result = ""
          m.top.response = { success: true, items: prefixItems, total: prefixItems.count(), baseUrl: baseUrl, sid: sid }
          return
      end if
      json = parseJSON(result)
      if json = invalid or json.success <> true or json.data = invalid
          m.top.response = { success: true, items: prefixItems, total: prefixItems.count(), baseUrl: baseUrl, sid: sid }
          return
      end if
      items = json.data.lookUp(dataKey)
      if items = invalid then items = []
      merged = []
      for each p in prefixItems
          merged.push(p)
      end for
      for each item in items
          merged.push(item)
      end for
      m.top.response = { success: true, items: merged, total: merged.count(), baseUrl: baseUrl, sid: sid }
  end sub

  sub appendCollectionsAndRespond(result as dynamic, dataKey as string, prefixItems as object, baseUrl as string, sid as string)
      if result = invalid or result = ""
          m.top.response = { success: true, items: prefixItems, total: prefixItems.count(), baseUrl: baseUrl, sid: sid }
          return
      end if
      json = parseJSON(result)
      if json = invalid or json.success <> true or json.data = invalid
          m.top.response = { success: true, items: prefixItems, total: prefixItems.count(), baseUrl: baseUrl, sid: sid }
          return
      end if
      items = json.data.lookUp(dataKey)
      if items = invalid then items = []
      merged = []
      for each p in prefixItems
          merged.push(p)
      end for
      for each item in items
          normalized = normalizeCollectionItem(item)
          if normalized.playlistType = "" then merged.push(normalized)
      end for
      m.top.response = { success: true, items: merged, total: merged.count(), baseUrl: baseUrl, sid: sid }
  end sub

  function normalizeCollectionItem(item as object) as object
      title = idToStr(item.lookUp("title"))
      playlistType = ""
      displayTitle = title
      if title = "syno_favorite"
          playlistType = "favorites"
          displayTitle = "Favorites"
      else if title = "syno_watchlist"
          playlistType = "watchlist"
          displayTitle = "Watch List"
      else if title = "syno_default_shared"
          playlistType = "shared"
          displayTitle = "Shared Videos"
      end if
      id = idToStr(item.lookUp("id"))
      if playlistType <> "" then id = collectionIdForKey(playlistType)
      iconUrl = ""
      if playlistType = "favorites" then iconUrl = "pkg:/images/playlist-favorites.png"
      if playlistType = "watchlist" then iconUrl = "pkg:/images/playlist-watchlist.png"
      if playlistType = "shared" then iconUrl = "pkg:/images/playlist-shared.png"
      return { id: id, title: displayTitle, name: displayTitle, playlistType: playlistType, collectionId: id, iconUrl: iconUrl }
  end function

  function collectionIdForKey(key as string) as string
      if key = "favorites" then return "-1"
      if key = "watchlist" then return "-2"
      if key = "shared" then return "-3"
      return key
  end function

  function collectionVideoType(value as string) as string
      v = lcase(value)
      if v = "episode" then return "tvshow_episode"
      if v = "tvshow_episode" then return "tvshow_episode"
      if v = "homevideo" then return "home_video"
      if v = "home_video" then return "home_video"
      if v = "tvrecord" then return "tv_record"
      if v = "tv_record" then return "tv_record"
      return "movie"
  end function

  function resolveVideoStationItem(proxyBaseUrl as dynamic, filePath as dynamic) as dynamic
      if proxyBaseUrl = invalid or proxyBaseUrl = "" then return invalid
      if filePath = invalid or filePath = "" then return invalid
      enc = createObject("roUrlTransfer")
      result = httpGet(proxyBaseUrl + "/resolve?path=" + enc.escape(filePath))
      if result = invalid or result = "" then return invalid
      json = parseJSON(result)
      if json = invalid or json.success <> true then return invalid
      return json.lookUp("item")
  end function

  function updateProxyWatchStatus(proxyBaseUrl as dynamic, filePath as dynamic, position as integer) as dynamic
      if proxyBaseUrl = invalid or proxyBaseUrl = "" then return invalid
      if filePath = invalid or filePath = "" then return invalid
      enc = createObject("roUrlTransfer")
      url = proxyBaseUrl + "/watchstatus?path=" + enc.escape(filePath) + "&position=" + stri(position).trim()
      result = httpGet(url)
      if result = invalid or result = "" then return invalid
      json = parseJSON(result)
      return json
  end function

  sub respondWithCollectionVideos(result as dynamic, baseUrl as string, sid as string)
      if result = invalid or result = ""
          m.top.response = { success: false, error: "No response from Synology collection API", items: [] }
          return
      end if
      json = parseJSON(result)
      if json = invalid or json.success <> true or json.data = invalid
          m.top.response = { success: false, error: "Could not load Synology collection", detail: left(result, 300), items: [] }
          return
      end if
      dataKey = firstCollectionVideoKey(json.data)
      if dataKey = ""
          m.top.response = { success: true, items: [], total: 0, baseUrl: baseUrl, sid: sid }
          return
      end if
      items = json.data.lookUp(dataKey)
      if items = invalid then items = []
      mediaType = collectionItemTypeForKey(dataKey)
      normalized = []
      for each item in items
          normalizeCollectionVideo(item, mediaType)
          normalized.push(item)
      end for
      normalized = sortBrowseItems(normalized)
      resolveCachedArtworkForItems(normalized, 1500)
      m.top.response = { success: true, items: normalized, total: normalized.count(), baseUrl: baseUrl, sid: sid }
  end sub

  function sortBrowseItems(items as object) as object
      if items = invalid then return []
      sorted = []
      for each item in items
          sorted.push(item)
      end for
      i = 0
      while i < sorted.count()
          j = i + 1
          while j < sorted.count()
              if browseSortKey(sorted[j]) < browseSortKey(sorted[i])
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

  function browseSortKey(item as object) as string
      title = idToStr(item.lookUp("sort_title"))
      if title = "" or title = "0" then title = idToStr(item.lookUp("title"))
      if title = "" or title = "0" then title = idToStr(item.lookUp("name"))
      if title = "" or title = "0" then title = idToStr(item.lookUp("file_name"))
      normalized = lcase(title).trim()
      if left(normalized, 4) = "the " then normalized = mid(normalized, 5)
      if left(normalized, 3) = "an " then normalized = mid(normalized, 4)
      if left(normalized, 2) = "a " then normalized = mid(normalized, 3)
      return normalized + chr(0) + lcase(title)
  end function

  function firstCollectionVideoKey(data as object) as string
      keys = ["movies", "episodes", "videos", "tvshows", "recordings", "movie", "episode", "video", "tvshow", "recording"]
      for each k in keys
          v = data.lookUp(k)
          if v <> invalid then return k
      end for
      return ""
  end function

  function collectionItemTypeForKey(key as string) as string
      k = lcase(key)
      if k = "episodes" or k = "episode" then return "episode"
      if k = "videos" or k = "video" then return "homevideo"
      if k = "recordings" or k = "recording" then return "homevideo"
      if k = "tvshows" or k = "tvshow" then return "tvshow"
      return "movie"
  end function

  function directEpisodeListResult(baseUrl as string, sid as string, token as string, candidateId as string, showTitle as string, stopOnMetadata as boolean) as object
      emptyResult = { episodes: [], metadata: [], result: invalid, url: "", source: "" }
      id = idToStr(candidateId)
      if id = "" or id = "0" then return emptyResult

      richAdditional = "%5B%22file%22,%22summary%22,%22extra%22,%22watched_ratio%22,%22poster_mtime%22,%22backdrop_mtime%22,%22originally_available%22%5D"
      simpleAdditional = "%5B%22file%22,%22summary%22,%22watched_ratio%22,%22originally_available%22%5D"
      attempts = [
          { api: "SYNO.VideoStation.TVShowEpisode", path: "VideoStation/tvshow_episode.cgi", version: "1", idParam: "tvshow_id", keys: ["episodes", "episode"] },
          { api: "SYNO.VideoStation2.TVShowEpisode", path: "entry.cgi", version: "2", idParam: "tvshow_id", keys: ["episode", "episodes"] },
          { api: "SYNO.VideoStation2.TVShowEpisode", path: "entry.cgi", version: "1", idParam: "tvshow_id", keys: ["episode", "episodes"] },
          { api: "SYNO.VideoStation.TVShowEpisode", path: "VideoStation/tvshow_episode.cgi", version: "2", idParam: "tvshow_id", keys: ["episodes", "episode"] },
          { api: "SYNO.VideoStation.TVShowEpisode", path: "VideoStation/tvshow_episode.cgi", version: "1", idParam: "id", keys: ["episodes", "episode"] },
          { api: "SYNO.VideoStation2.TVShowEpisode", path: "entry.cgi", version: "2", idParam: "id", keys: ["episode", "episodes"] },
          { api: "SYNO.VideoStation.TVShowEpisode", path: "VideoStation/tvshow_episode.cgi", version: "1", idParam: "", keys: ["episodes", "episode"] },
          { api: "SYNO.VideoStation2.TVShowEpisode", path: "entry.cgi", version: "2", idParam: "", keys: ["episode", "episodes"] }
      ]
      additionals = [richAdditional, simpleAdditional, ""]

      best = emptyResult
      for each attempt in attempts
          for each additional in additionals
              limit = "500"
              if attempt.idParam = "" then limit = "10000"
              params = "offset=0&limit=" + limit + "&sort_by=ep_num&sort_direction=asc"
              if attempt.idParam <> "" then params = attempt.idParam + "=" + id + "&" + params
              if additional <> "" then params = params + "&additional=" + additional
              url = apiUrl(baseUrl, attempt.api, attempt.path, attempt.version, "list", params, sid, token)
              result = httpGet(url)
              key = firstValidKey(result, attempt.keys)
              if key <> ""
                  meta = parseEpisodeMetadata(result, key, id, showTitle)
                  parsed = parseEpisodes(result, key, id, showTitle)
                  source = attempt.api + "/" + attempt.version + "/" + attempt.idParam
                  print "EPISODE_DIRECT title="; showTitle; " source="; source; " metadata="; meta.count(); " playable="; parsed.count()
                  candidate = { episodes: parsed, metadata: meta, result: result, url: url, source: source }
                  if parsed.count() > best.episodes.count() then best = candidate
                  if best.episodes.count() = 0 and meta.count() > best.metadata.count() then best = candidate
                  if parsed.count() > 0 then return candidate
                  if stopOnMetadata and meta.count() > 0 then return candidate
              end if
              if best.url = "" then best = { episodes: [], metadata: [], result: result, url: url, source: "" }
          end for
      end for
      return best
  end function

  sub normalizeCollectionVideo(item as object, mediaType as string)
      savedType = idToStr(item.lookUp("type"))
      if savedType <> "0" and savedType <> ""
          mediaType = normalizedAppVideoType(savedType)
      end if
      item.addReplace("type", mediaType)
      mapper = idToStr(item.lookUp("mapper_id"))
      if mapper = "0" then mapper = idToStr(item.lookUp("mapperId"))
      if mapper <> "0"
          item.addReplace("mapperId", mapper)
          item.addReplace("mapper_id", mapper)
      end if
      additional = item.lookUp("additional")
      if additional <> invalid
          summary = idToStr(additional.lookUp("summary"))
          if summary <> "0" and summary <> "" then item.addReplace("summary", summary)
      end if
  end sub

  function normalizedAppVideoType(value as string) as string
      v = lcase(value)
      if v = "tvshow_episode" then return "episode"
      if v = "episode" then return "episode"
      if v = "home_video" then return "homevideo"
      if v = "homevideo" then return "homevideo"
      if v = "tv_record" then return "homevideo"
      if v = "movie" then return "movie"
      return value
  end function

  function parseEpisodesAndRespond(result as dynamic, dataKey as string, baseUrl as string, sid as string, tvId as string, showTitle as string) as boolean
      if result = invalid or result = ""
          m.top.response = { success: false, error: "No response from NAS (timeout or network error)", detail: "", items: [] }
          return false
      end if
      json = parseJSON(result)
      if json = invalid
          m.top.response = { success: false, error: "Unparseable response", detail: left(result, 300), items: [] }
          return false
      end if
      if json.success <> true
          errCode = 0
          if json.error <> invalid
              errCode = json.error.code
              if type(errCode) = "roFloat" or type(errCode) = "Float" then errCode = int(errCode)
              if type(errCode) <> "roInteger" and type(errCode) <> "Integer" then errCode = 0
          end if
          m.top.response = { success: false, error: "API error " + stri(errCode), detail: left(result, 300), items: [] }
          return false
      end if

      items = json.data.lookUp(dataKey)
      if items = invalid then items = []

      filtered = filterEpisodeItems(items, tvId, showTitle)

      if filtered.count() = 0 then return false

      m.top.response = { success: true, items: filtered, total: filtered.count(), baseUrl: baseUrl, sid: sid }
      return true
  end function

  function parseEpisodes(result as dynamic, dataKey as string, tvId as string, showTitle as string) as object
      if result = invalid or result = "" then return []
      json = parseJSON(result)
      if json = invalid or json.success <> true or json.data = invalid then return []
      items = json.data.lookUp(dataKey)
      if items = invalid then return []
      return filterEpisodeItems(items, tvId, showTitle)
  end function

  function parseEpisodeMetadata(result as dynamic, dataKey as string, tvId as string, showTitle as string) as object
      if result = invalid or result = "" then return []
      json = parseJSON(result)
      if json = invalid or json.success <> true or json.data = invalid then return []
      items = json.data.lookUp(dataKey)
      if items = invalid then return []

      filtered = []
      for each item in items
          itemShowId = itemTvShowId(item)
          season = itemInt(item, ["season", "season_number", "season_num", "season_index"])
          episode = itemInt(item, ["episode", "episode_number", "episode_num", "ep_num", "ep_index"])
          keep = true
          if isFolderLike(item) then keep = false
          if looksLikeShowFolder(item, showTitle) then keep = false
          if season = 0 and episode = 0 then keep = false
          if itemShowId <> "" and tvId <> "" and itemShowId <> tvId then keep = false
          if keep then filtered.push(item)
      end for
      return filtered
  end function

  sub normalizeEpisodeItems(items as object)
      if items = invalid then return
      for each item in items
          normalizeEpisodeItem(item)
      end for
  end sub

  sub normalizeEpisodeItem(item as object)
      if item = invalid then return

      episodeTitle = idToStr(item.lookUp("tag_line"))
      if episodeTitle = "" or episodeTitle = "0" then episodeTitle = idToStr(item.lookUp("tagline"))
      if episodeTitle <> "" and episodeTitle <> "0"
          item.addReplace("title", episodeTitle)
          item.addReplace("name", episodeTitle)
      end if

      season = itemInt(item, ["season", "season_number", "season_num", "season_index"])
      episode = itemInt(item, ["episode", "episode_number", "episode_num", "ep_num", "ep_index"])
      if season > 0
          item.addReplace("season", season)
          item.addReplace("season_number", season)
          item.addReplace("seasonNumber", season)
      end if
      if episode > 0
          item.addReplace("episode", episode)
          item.addReplace("episode_number", episode)
          item.addReplace("episodeNumber", episode)
          item.addReplace("episodeText", stri(episode).trim())
      end if

      summary = episodeSummaryText(item)
      if summary <> ""
          item.addReplace("summary", summary)
          item.addReplace("description", summary)
      end if

      directId = idToStr(item.lookUp("id"))
      if directId <> "" and directId <> "0"
          item.addReplace("posterId", directId)
          item.addReplace("videoStationId", directId)
      end if
      mapper = idToStr(item.lookUp("mapper_id"))
      if mapper = "" or mapper = "0" then mapper = idToStr(item.lookUp("mapperId"))
      if mapper <> "" and mapper <> "0"
          item.addReplace("mapperId", mapper)
          item.addReplace("mapper_id", mapper)
      end if
      item.addReplace("type", "episode")
  end sub

  function episodeSummaryText(item as object) as string
      if item = invalid then return ""
      summary = summaryTextFromValue(item.lookUp("summary"))
      if summary <> "" then return summary
      summary = summaryTextFromValue(item.lookUp("description"))
      if summary <> "" then return summary
      additional = item.lookUp("additional")
      if additional <> invalid
          summary = summaryTextFromValue(additional.lookUp("summary"))
          if summary <> "" then return summary
          extra = additional.lookUp("extra")
          if extra <> invalid
              summary = summaryTextFromValue(extra.lookUp("summary"))
              if summary <> "" then return summary
              summary = summaryTextFromValue(extra.lookUp("description"))
              if summary <> "" then return summary
          end if
      end if
      return ""
  end function

  function summaryTextFromValue(value as dynamic) as string
      if value = invalid then return ""
      t = type(value)
      if t = "roAssociativeArray"
          summary = idToStr(value.lookUp("summary"))
          if summary <> "" and summary <> "0" then return summary
          summary = idToStr(value.lookUp("description"))
          if summary <> "" and summary <> "0" then return summary
          return ""
      end if
      summary = idToStr(value)
      if summary = "" or summary = "0" then return ""
      return summary
  end function

  sub enrichEpisodeSummariesFromVsmeta(items as object, baseUrl as string, sid as string, token as string)
      if items = invalid then return
      checked = 0
      for each item in items
          if checked >= 16 then return
          if episodeSummaryText(item) = ""
              fileInfo = itemFileInfo(item)
              if fileInfo.path <> ""
                  summary = fetchVsmetaSummary(baseUrl, sid, token, fileInfo.path, idToStr(item.lookUp("title")))
                  if summary <> ""
                      item.addReplace("summary", summary)
                      item.addReplace("description", summary)
                  end if
                  checked = checked + 1
              end if
          end if
      end for
  end sub

  function fetchVsmetaSummary(baseUrl as string, sid as string, token as string, filePath as string, episodeTitle as string) as string
      if filePath = "" then return ""
      url = fileStationStreamUrl(baseUrl, sid, token, filePath + ".vsmeta")
      blob = httpGet(url)
      if blob = invalid or blob = "" then return ""
      summary = vsmetaSummaryFromBlob(blob, episodeTitle)
      if summary <> "" then print "VSMETA_SUMMARY title="; episodeTitle; " len="; len(summary)
      return summary
  end function

  function vsmetaSummaryFromBlob(blob as string, episodeTitle as string) as string
      if blob = "" then return ""
      searchStart = 1
      if episodeTitle <> ""
          found = instr(1, blob, episodeTitle)
          if found > 0 then searchStart = found + len(episodeTitle)
      end if

      jpgStart = instr(searchStart, blob, "/9j/")
      stopAt = len(blob)
      if jpgStart > 0 then stopAt = jpgStart - 1

      best = ""
      current = ""
      idx = searchStart
      while idx <= stopAt
          ch = asc(mid(blob, idx, 1))
          if ch >= 32 and ch <= 126
              current = current + mid(blob, idx, 1)
          else
              if len(cleanVsmetaSummary(current)) > len(best) then best = cleanVsmetaSummary(current)
              current = ""
          end if
          idx = idx + 1
      end while
      if len(cleanVsmetaSummary(current)) > len(best) then best = cleanVsmetaSummary(current)
      return best
  end function

  function cleanVsmetaSummary(value as string) as string
      text = value.trim()
      while len(text) > 0
          first = left(text, 1)
          code = asc(first)
          if (code >= 65 and code <= 90) or (code >= 97 and code <= 122) or (code >= 48 and code <= 57)
              exit while
          end if
          text = mid(text, 2).trim()
      end while
      if len(text) > 2 and left(text, 1) = "B"
          thirdCode = asc(mid(text, 3, 1))
          if thirdCode >= 65 and thirdCode <= 90 then text = mid(text, 3).trim()
      end if
      if len(text) < 12 then return ""
      if right(text, 1) = chr(34) then return ""
      if instr(1, text, "JFIF") > 0 then return ""
      if instr(1, text, "Exif") > 0 then return ""
      if instr(1, text, ".") = 0 and instr(1, text, "!") = 0 and instr(1, text, "?") = 0 then return ""
      return text
  end function

  function fetchProxyTvMetadata(proxyBaseUrl as dynamic, showTitle as string) as object
      if proxyBaseUrl = invalid or proxyBaseUrl = "" or showTitle = "" then return []
      enc = createObject("roUrlTransfer")
      url = proxyBaseUrl + "/tvmeta?title=" + enc.escape(showTitle)
      result = httpGet(url)
      if result = invalid or result = "" then return []
      json = parseJSON(result)
      if json = invalid or json.success <> true then return []
      items = json.lookUp("items")
      if items = invalid then return []
      return items
  end function

  function fetchProxyEpisodes(proxyBaseUrl as dynamic, tvShowId as string, showTitle as string) as object
      if proxyBaseUrl = invalid or proxyBaseUrl = "" then return []
      if tvShowId = "" and showTitle = "" then return []
      enc = createObject("roUrlTransfer")
      url = proxyBaseUrl + "/episodes?tvshow_id=" + enc.escape(tvShowId) + "&title=" + enc.escape(showTitle)
      result = httpGet(url)
      if result = invalid or result = "" then return []
      json = parseJSON(result)
      if json = invalid or json.success <> true then return []
      items = json.lookUp("items")
      if items = invalid then return []
      for each item in items
          season = itemInt(item, ["season", "season_number", "season_num", "season_index"])
          episode = itemInt(item, ["episode", "episode_number", "episode_num", "ep_index"])
          if season <= 0 or episode <= 0
              fileInfo = itemFileInfo(item)
              if fileInfo.path <> ""
                  parsed = episodeInfoFromPath(fileInfo.path)
                  if season <= 0 then season = parsed.season
                  if episode <= 0 then episode = parsed.episode
              end if
          end if
          if season > 0
              item.addReplace("season", season)
              item.addReplace("season_number", season)
              item.addReplace("seasonNumber", season)
              item.addReplace("seasonText", stri(season).trim())
          end if
          if episode > 0
              item.addReplace("episode", episode)
              item.addReplace("episode_number", episode)
              item.addReplace("episodeNumber", episode)
              item.addReplace("episodeText", stri(episode).trim())
          end if
          mapper = idToStr(item.lookUp("mapper_id"))
          if mapper <> "" and mapper <> "0"
              item.addReplace("mapperId", mapper)
          end if
      end for
      return items
  end function

  function fetchBestProxyEpisodes(proxyBaseUrl as dynamic, candidates as object, showTitle as string) as object
      best = []
      for each candidateId in candidates
          id = idToStr(candidateId)
          if id <> "" and id <> "0"
              items = fetchProxyEpisodes(proxyBaseUrl, id, showTitle)
              if isBetterProxyEpisodeList(items, best) then best = items
          end if
      end for
      if showTitle <> ""
          titleItems = fetchProxyEpisodes(proxyBaseUrl, "", showTitle)
          if isBetterProxyEpisodeList(titleItems, best) then best = titleItems
      end if
      return best
  end function

  function isBetterProxyEpisodeList(candidate as object, current as object) as boolean
      if candidate = invalid or candidate.count() = 0 then return false
      if current = invalid or current.count() = 0 then return true
      if candidate.count() > current.count() then return true
      if candidate.count() < current.count() then return false
      return proxyEpisodeListScore(candidate) > proxyEpisodeListScore(current)
  end function

  function proxyEpisodeListScore(items as object) as integer
      score = 0
      for each item in items
          if firstNumericField(item, ["resumePosition", "watch_position", "position"]) > 0 then score = score + 100
          if idToStr(item.lookUp("mapper_id")) <> "" then score = score + 8
          if idToStr(item.lookUp("show_mapper_id")) <> "" then score = score + 4
          if firstTextField(item, ["summary", "description"]) <> "" then score = score + 2
          path = firstTextField(item, ["path"])
          if left(path, 9) = "/volume1/" then score = score + 6
          if idToStr(item.lookUp("id")) <> "" and val(idToStr(item.lookUp("id"))) > 0 then score = score + 3
      end for
      return score
  end function

  function firstNumericField(item as object, keys as object) as integer
      if item = invalid then return 0
      for each key in keys
          value = item.lookUp(key)
          if value <> invalid
              t = type(value)
              if t = "roInteger" or t = "Integer" then return value
              if t = "roFloat" or t = "Float" then return int(value)
              if t = "roString" or t = "String" then return int(val(value))
          end if
      end for
      return 0
  end function

  function firstTextField(item as object, keys as object) as string
      if item = invalid then return ""
      for each key in keys
          value = item.lookUp(key)
          if value <> invalid
              text = idToStr(value)
              if text <> "" then return text
          end if
      end for
      return ""
  end function

  function playableEpisodeMetadata(items as object) as object
      playable = []
      if items = invalid then return playable
      for each item in items
          pathValue = item.lookUp("path")
          path = ""
          if pathValue <> invalid then path = idToStr(pathValue)
          if path <> "" and path <> "0"
              copy = {}
              for each key in item
                  copy[key] = item[key]
              end for
              fileId = item.lookUp("file_id")
              copy.additional = { file: [ { id: fileId, path: path } ] }
              playable.push(copy)
          end if
      end for
      return playable
  end function

  function uniqueEpisodeItems(items as object) as object
      unique = []
      for each item in items
          season = itemInt(item, ["season", "season_number", "season_num", "season_index"])
          episode = itemInt(item, ["episode", "episode_number", "episode_num", "ep_index"])
          key = stri(season).trim() + "x" + stri(episode).trim()
          existingIdx = -1
          i = 0
          while i < unique.count()
              uSeason = itemInt(unique[i], ["season", "season_number", "season_num", "season_index"])
              uEpisode = itemInt(unique[i], ["episode", "episode_number", "episode_num", "ep_index"])
              uKey = stri(uSeason).trim() + "x" + stri(uEpisode).trim()
              if uKey = key then existingIdx = i
              i = i + 1
          end while
          if existingIdx < 0
              unique.push(item)
          else if episodeItemScore(item) > episodeItemScore(unique[existingIdx])
              unique[existingIdx] = item
          end if
      end for
      return unique
  end function

  function episodeItemScore(item as object) as integer
      p = itemPath(item)
      lowerPath = lcase(p)
      score = 0
      if instr(1, lowerPath, "short") = 0 then score = score + 10
      if instr(1, lowerPath, "extra") = 0 then score = score + 10
      if instr(1, lowerPath, "/s") > 0 then score = score + 2
      if instr(1, lowerPath, ".s") > 0 then score = score + 2
      return score
  end function

  function itemPath(item as object) as string
      p = item.lookUp("path")
      if p <> invalid then return idToStr(p)
      additional = item.lookUp("additional")
      if additional <> invalid
          fileList = additional.lookUp("file")
          if fileList <> invalid and fileList.count() > 0
              fp = fileList[0].lookUp("path")
              if fp <> invalid then return idToStr(fp)
          end if
      end if
      return ""
  end function

  function mergeEpisodeMetadata(playableItems as object, metadataItems as object) as object
      merged = []
      for each playable in playableItems
          season = itemInt(playable, ["season", "season_number", "season_num", "season_index"])
          episode = itemInt(playable, ["episode", "episode_number", "episode_num", "ep_num", "ep_index"])
          meta = findEpisodeMetadataForItem(metadataItems, playable, season, episode)
          if meta <> invalid
              item = {}
              for each key in playable
                  item[key] = playable[key]
              end for
              copyEpisodeMetadataField(meta, item, "id")
              copyEpisodeMetadataField(meta, item, "mapper_id")
              copyEpisodeMetadataField(meta, item, "title")
              copyEpisodeMetadataField(meta, item, "name")
              copyEpisodeMetadataField(meta, item, "tagline")
              copyEpisodeMetadataField(meta, item, "summary")
              copyEpisodeMetadataField(meta, item, "description")
              copyEpisodeMetadataField(meta, item, "original_available")
              copyEpisodeMetadataField(meta, item, "originally_available")
              copyEpisodeMetadataField(meta, item, "year")
              copyEpisodeMetadataField(meta, item, "additional")
              summary = episodeSummaryText(meta)
              if summary <> ""
                  item.addReplace("summary", summary)
                  item.addReplace("description", summary)
              end if
              fallbackFile = itemFileInfo(playable)
              if fallbackFile.path <> ""
                  mergedAdditional = item.lookUp("additional")
                  if mergedAdditional = invalid then mergedAdditional = {}
                  mergedAdditional.addReplace("file", [ { id: fallbackFile.id, path: fallbackFile.path } ])
                  item.addReplace("additional", mergedAdditional)
              end if
              merged.push(item)
          else
              merged.push(playable)
          end if
      end for
      return merged
  end function

  function findEpisodeMetadata(metadataItems as object, season as integer, episode as integer) as dynamic
      for each item in metadataItems
          ms = itemInt(item, ["season", "season_number", "season_num", "season_index"])
          me = itemInt(item, ["episode", "episode_number", "episode_num", "ep_num", "ep_index"])
          if ms = season and me = episode then return item
      end for
      return invalid
  end function

  function findEpisodeMetadataForItem(metadataItems as object, playable as object, season as integer, episode as integer) as dynamic
      meta = findEpisodeMetadata(metadataItems, season, episode)
      if meta <> invalid then return meta

      playablePath = normalizedEpisodeMetadataPath(itemPath(playable))
      playableTitle = normalizedTitleKey(idToStr(playable.lookUp("title")))
      if playableTitle = "" then playableTitle = normalizedTitleKey(idToStr(playable.lookUp("name")))

      for each item in metadataItems
          itemPathText = normalizedEpisodeMetadataPath(itemPath(item))
          if playablePath <> "" and itemPathText <> "" and playablePath = itemPathText then return item

          itemTitle = normalizedTitleKey(idToStr(item.lookUp("title")))
          if itemTitle = "" then itemTitle = normalizedTitleKey(idToStr(item.lookUp("name")))
          if playableTitle <> "" and itemTitle <> "" and playableTitle = itemTitle
              ms = itemInt(item, ["season", "season_number", "season_num", "season_index"])
              if season <= 0 or ms <= 0 or ms = season then return item
          end if
      end for
      return invalid
  end function

  function normalizedEpisodeMetadataPath(path as string) as string
      p = lcase(path.trim())
      if left(p, 8) = "/volume"
          slash = instr(9, p, "/")
          if slash > 0 then p = mid(p, slash)
      end if
      return p
  end function

  sub copyEpisodeMetadataField(source as object, target as object, key as string)
      value = source.lookUp(key)
      if value <> invalid then target[key] = value
  end sub

  function filterEpisodeItems(items as object, tvId as string, showTitle as string) as object
      filtered = []
      for each item in items
          itemShowId = itemTvShowId(item)
          fileInfo = itemFileInfo(item)
          season = itemInt(item, ["season", "season_number", "season_num", "season_index"])
          episode = itemInt(item, ["episode", "episode_number", "episode_num", "ep_num", "ep_index"])

          keep = true
          if isFolderLike(item) then keep = false
          if looksLikeShowFolder(item, showTitle) then keep = false
          if season = 0 and episode = 0 then keep = false
          if itemShowId <> "" and tvId <> "" and itemShowId <> tvId then keep = false
          if fileInfo.id = invalid and fileInfo.path = "" then keep = false
          if keep then filtered.push(item)
      end for
      return filtered
  end function

  ' Async HTTP GET with 20-second timeout — prevents indefinite hangs
  function httpGet(url as string) as dynamic
      port = createObject("roMessagePort")
      http = createObject("roUrlTransfer")
      http.setUrl(url)
      http.setCertificatesFile("common:/certs/ca-bundle.crt")
      http.enableHostVerification(false)
      http.enablePeerVerification(false)
      http.setMessagePort(port)
      http.asyncGetToString()

      clock = createObject("roTimespan")
      clock.mark()

      while true
          msg = wait(500, port)
          if msg <> invalid
              if type(msg) = "roUrlEvent"
                  result = msg.getString()
                  if result = "" then return invalid
                  return result
              end if
          end if
          if clock.totalMilliseconds() > 20000
              http.asyncCancel()
              return invalid
          end if
      end while
  end function

  function httpPostJson(url as string, body as string) as dynamic
      port = createObject("roMessagePort")
      http = createObject("roUrlTransfer")
      http.setUrl(url)
      http.setCertificatesFile("common:/certs/ca-bundle.crt")
      http.enableHostVerification(false)
      http.enablePeerVerification(false)
      http.addHeader("Content-Type", "application/json")
      http.setMessagePort(port)
      http.asyncPostFromString(body)

      clock = createObject("roTimespan")
      clock.mark()

      while true
          msg = wait(500, port)
          if msg <> invalid
              if type(msg) = "roUrlEvent"
                  result = msg.getString()
                  if result = "" then return invalid
                  return result
              end if
          end if
          if clock.totalMilliseconds() > 20000
              http.asyncCancel()
              return invalid
          end if
      end while
  end function

  function httpPostForm(url as string, body as string) as dynamic
      port = createObject("roMessagePort")
      http = createObject("roUrlTransfer")
      http.setUrl(url)
      http.setCertificatesFile("common:/certs/ca-bundle.crt")
      http.enableHostVerification(false)
      http.enablePeerVerification(false)
      http.addHeader("Content-Type", "application/x-www-form-urlencoded")
      http.setMessagePort(port)
      http.asyncPostFromString(body)

      clock = createObject("roTimespan")
      clock.mark()

      while true
          msg = wait(500, port)
          if msg <> invalid
              if type(msg) = "roUrlEvent"
                  result = msg.getString()
                  if result = "" then return invalid
                  return result
              end if
          end if
          if clock.totalMilliseconds() > 20000
              http.asyncCancel()
              return invalid
          end if
      end while
  end function

  ' ─── FileStation browse helpers ──────────────────────────────────────────────────

  function isVideoFile(name as string) as boolean
      lname = lcase(name)
      if right(lname, 4) = ".mkv" then return true
      if right(lname, 4) = ".mp4" then return true
      if right(lname, 4) = ".avi" then return true
      if right(lname, 4) = ".m4v" then return true
      if right(lname, 5) = ".webm" then return true
      if right(lname, 5) = ".m2ts" then return true
      if right(lname, 4) = ".mov" then return true
      return false
  end function

  function yearFromString(value as string) as string
      if len(value) >= 4
          y = left(value, 4)
          n = val(y)
          if n >= 1900 and n <= 2100 then return y
      end if
      return ""
  end function

  function findExistingMoviePath(baseUrl as string, sid as string, basePathNoExt as string) as string
      extensions = [".avi", ".mp4", ".mkv", ".m4v", ".mov", ".webm", ".m2ts"]
      enc = createObject("roUrlTransfer")
      for each ext in extensions
          candidate = basePathNoExt + ext
          parent = left(candidate, len(candidate) - len(baseName(candidate)) - 1)
          url = baseUrl + "/webapi/entry.cgi?api=SYNO.FileStation.List&version=2&method=list&folder_path=" + enc.escape(parent) + "&filetype=file&limit=5000&_sid=" + sid
          r = httpGet(url)
          if r <> invalid
              j = parseJSON(r)
              if j <> invalid and j.success = true
                  files = j.data.lookUp("files")
                  if files <> invalid
                      for each f in files
                          fpath = f.lookUp("path")
                          if fpath <> invalid and fpath = candidate
                              print "FIND_MOVIE exact="; candidate
                              return candidate
                          end if
                      end for
                  end if
              end if
          end if
      end for
      return ""
  end function

  ' True if candidate folder/filename refers to the same title.
  ' "10 (1979)" matches title "10"; "9 to 5 (1980)" does NOT match "10".
  function baseName(path as string) as string
      lastSlash = 0
      idx = 1
      while idx <= len(path)
          if mid(path, idx, 1) = "/" then lastSlash = idx
          idx = idx + 1
      end while
      if lastSlash > 0 then return mid(path, lastSlash + 1)
      return path
  end function

  function titleMatch(title as string, candidate as string) as boolean
      lt = lcase(title)
      lc = lcase(baseName(candidate))
      if right(lc, 4) = ".mkv" then lc = left(lc, len(lc) - 4)
      if right(lc, 4) = ".mp4" then lc = left(lc, len(lc) - 4)
      if right(lc, 4) = ".avi" then lc = left(lc, len(lc) - 4)
      if right(lc, 4) = ".m4v" then lc = left(lc, len(lc) - 4)
      if right(lc, 5) = ".webm" then lc = left(lc, len(lc) - 5)
      if right(lc, 5) = ".m2ts" then lc = left(lc, len(lc) - 5)
      if right(lc, 4) = ".mov" then lc = left(lc, len(lc) - 4)
      if lt = lc then return true
      if len(lc) > len(lt)
          nextCh = mid(lc, len(lt) + 1, 1)
          if left(lc, len(lt)) = lt
              if nextCh = " " or nextCh = "(" or nextCh = "." or nextCh = "-" or nextCh = "_" then return true
          end if
      end if

      nt = normalizedTitleKey(lt)
      nc = normalizedTitleKey(lc)
      if nt <> "" and nt = nc then return true
      if nt <> "" and len(nc) > len(nt)
          if left(nc, len(nt)) = nt then return true
      end if
      return false
  end function

  function normalizedTitleKey(value as string) as string
      value = lcase(value)
      out = ""
      idx = 1
      while idx <= len(value)
          ch = mid(value, idx, 1)
          code = asc(ch)
          if (code >= 48 and code <= 57) or (code >= 97 and code <= 122)
              out = out + ch
          end if
          idx = idx + 1
      end while
      return out
  end function

  function fileNameNoExt(path as string) as string
      name = baseName(path)
      lname = lcase(name)
      extensions = [".mkv", ".mp4", ".avi", ".m4v", ".mov", ".webm", ".m2ts"]
      for each ext in extensions
          if right(lname, len(ext)) = ext then return left(name, len(name) - len(ext))
      end for
      return name
  end function

  function episodeInfoFromPath(path as string) as object
      name = fileNameNoExt(path)
      lower = lcase(name)
      season = 0
      episode = 0

      idx = 1
      while idx <= len(lower) - 5
          if mid(lower, idx, 1) = "s" and mid(lower, idx + 3, 1) = "e"
              season = int(val(mid(lower, idx + 1, 2)))
              episode = int(val(mid(lower, idx + 4, 2)))
              if season > 0 or episode > 0 then return { season: season, episode: episode, title: episodeTitleFromName(name, idx + 6, episode) }
          else if mid(lower, idx, 1) = "s" and mid(lower, idx + 4, 1) = "e"
              season = int(val(mid(lower, idx + 1, 2)))
              episode = int(val(mid(lower, idx + 5, 2)))
              if season > 0 or episode > 0 then return { season: season, episode: episode, title: episodeTitleFromName(name, idx + 7, episode) }
          end if
          idx = idx + 1
      end while

      idx = 1
      while idx <= len(lower) - 3
          ch = mid(lower, idx, 1)
          code = asc(ch)
          if code >= 48 and code <= 57 and mid(lower, idx + 2, 1) = "x"
              season = int(val(ch))
              episode = int(val(mid(lower, idx + 3, 2)))
              if season > 0 or episode > 0 then return { season: season, episode: episode, title: episodeTitleFromName(name, idx + 5, episode) }
          end if
          idx = idx + 1
      end while

      return { season: 0, episode: 0, title: name }
  end function

  function episodeTitleFromName(name as string, titleStart as integer, episode as integer) as string
      title = ""
      if titleStart <= len(name) then title = mid(name, titleStart)
      title = cleanFilenameTitle(title)
      if title <> "" then return title
      epText = stri(episode).trim()
      if episode < 10 then epText = "0" + epText
      return "Episode " + epText
  end function

  function cleanFilenameTitle(value as string) as string
      title = value
      while len(title) > 0
          ch = left(title, 1)
          if ch = " " or ch = "-" or ch = "_" or ch = "."
              title = mid(title, 2)
          else
              exit while
          end if
      end while
      title = title.trim()
      title = replaceAll(title, ".", " ")
      title = replaceAll(title, "_", " ")
      return title.trim()
  end function

  function replaceAll(value as string, findText as string, replacement as string) as string
      if findText = "" then return value
      output = ""
      idx = 1
      findLen = len(findText)
      while idx <= len(value)
          if mid(value, idx, findLen) = findText
              output = output + replacement
              idx = idx + findLen
          else
              output = output + mid(value, idx, 1)
              idx = idx + 1
          end if
      end while
      return output
  end function

  function episodeItemFromFile(fpath as string) as object
      info = episodeInfoFromPath(fpath)
      return {
          id: "0",
          title: info.title,
          season_number: info.season,
          episode_number: info.episode,
          additional: { file: [ { id: fpath, path: fpath } ] }
      }
  end function

  function fileStationListUrl(baseUrl as string, sid as string, token as string, folderPath as string, fileType as string) as string
      enc = createObject("roUrlTransfer")
      return apiUrl(baseUrl, "SYNO.FileStation.List", "entry.cgi", "2", "list", "folder_path=" + enc.escape(folderPath) + "&filetype=" + fileType + "&limit=5000", sid, token)
  end function

  sub collectEpisodeFiles(baseUrl as string, sid as string, token as string, dirPath as string, depth as integer, results as object)
      if depth < 0 then return

      fileUrl = fileStationListUrl(baseUrl, sid, token, dirPath, "file")
      rf = httpGet(fileUrl)
      if rf <> invalid
          jf = parseJSON(rf)
          if jf <> invalid and jf.success = true and jf.data <> invalid
              files = jf.data.lookUp("files")
              if files <> invalid
                  for each f in files
                      fname = f.lookUp("name")
                      fpath = f.lookUp("path")
                      if fname <> invalid and fpath <> invalid and isVideoFile(fname)
                          results.push(episodeItemFromFile(fpath))
                      end if
                  end for
              end if
          end if
      end if

      if depth = 0 then return

      dirUrl = fileStationListUrl(baseUrl, sid, token, dirPath, "dir")
      rd = httpGet(dirUrl)
      if rd = invalid then return
      jd = parseJSON(rd)
      if jd = invalid or jd.success <> true or jd.data = invalid then return
      dirs = jd.data.lookUp("files")
      if dirs = invalid then return
      for each d in dirs
          dpath = d.lookUp("path")
          dname = d.lookUp("name")
          if dpath <> invalid and dname <> "@eaDir" then collectEpisodeFiles(baseUrl, sid, token, dpath, depth - 1, results)
      end for
  end sub

  function findShowDirInTree(baseUrl as string, sid as string, token as string, title as string, dirPath as string, depth as integer) as string
      if depth < 0 then return ""
      url = fileStationListUrl(baseUrl, sid, token, dirPath, "dir")
      r = httpGet(url)
      if r = invalid then return ""
      j = parseJSON(r)
      if j = invalid or j.success <> true or j.data = invalid then return ""
      dirs = j.data.lookUp("files")
      if dirs = invalid then return ""

      for each d in dirs
          dname = d.lookUp("name")
          dpath = d.lookUp("path")
          if dname <> invalid and dpath <> invalid
              if dname <> "@eaDir" and titleMatch(title, dname) then return dpath
          end if
      end for

      if depth = 0 then return ""
      for each d in dirs
          dpath = d.lookUp("path")
          dname = d.lookUp("name")
          if dpath <> invalid and dname <> "@eaDir"
              found = findShowDirInTree(baseUrl, sid, token, title, dpath, depth - 1)
              if found <> "" then return found
          end if
      end for
      return ""
  end function

  function findEpisodesByShowTitle(baseUrl as string, sid as string, token as string, title as string) as object
      results = []
      if title = "" then return results
      print "FIND_EPISODES title="; title

      directPaths = ["/video/TV Shows/" + title, "/video/Ian's Shows/" + title, "/video/TV/" + title, "/video/Series/" + title]
      for each directPath in directPaths
          print "FIND_EPISODES direct="; directPath
          collectEpisodeFiles(baseUrl, sid, token, directPath, 2, results)
          if results.count() > 0 then return results
      end for

      searchPaths = ["/video/TV Shows", "/video/Ian's Shows", "/video/TV", "/video/Series"]
      for each basePath in searchPaths
          showDir = findShowDirInTree(baseUrl, sid, token, title, basePath, 1)
          if showDir <> ""
              print "FIND_EPISODES dir="; showDir
              collectEpisodeFiles(baseUrl, sid, token, showDir, 2, results)
              if results.count() > 0 then return results
          end if
      end for
      return results
  end function

  ' Return path of first video file in a FileStation directory.
  function findVideoInDir(baseUrl as string, sid as string, dirPath as string) as string
      enc = createObject("roUrlTransfer")
      url = baseUrl + "/webapi/entry.cgi?api=SYNO.FileStation.List&version=2&method=list&folder_path=" + enc.escape(dirPath) + "&filetype=file&limit=5000&_sid=" + sid
      r = httpGet(url)
      if r = invalid then return ""
      j = parseJSON(r)
      if j = invalid or j.success <> true then return ""
      files = j.data.lookUp("files")
      if files = invalid then return ""
      idx = 0
      while idx < files.count()
          f = files[idx]
          fname = f.lookUp("name")
          fpath = f.lookUp("path")
          if fname <> invalid and fpath <> invalid
              if isVideoFile(fname) then return fpath
          end if
          idx = idx + 1
      end while
      return ""
  end function

  function findMovieInTree(baseUrl as string, sid as string, title as string, dirPath as string, depth as integer) as string
      if depth < 0 then return ""

      direct = findVideoInDir(baseUrl, sid, dirPath)
      if direct <> "" and titleMatch(title, direct) then
          print "FIND_MOVIE matchFile="; direct
          return direct
      end if

      enc = createObject("roUrlTransfer")
      url = baseUrl + "/webapi/entry.cgi?api=SYNO.FileStation.List&version=2&method=list&folder_path=" + enc.escape(dirPath) + "&filetype=dir&limit=5000&_sid=" + sid
      r = httpGet(url)
      if r = invalid then return ""
      j = parseJSON(r)
      if j = invalid or j.success <> true then return ""
      dirs = j.data.lookUp("files")
      if dirs = invalid then return ""

      idx = 0
      while idx < dirs.count()
          d = dirs[idx]
          dname = d.lookUp("name")
          dpath = d.lookUp("path")
          if dname <> invalid and dpath <> invalid
              if titleMatch(title, dname)
                  vpath = findVideoInDir(baseUrl, sid, dpath)
                  if vpath <> "" then return vpath
                  vpath = findMovieInTree(baseUrl, sid, title, dpath, depth - 1)
                  if vpath <> "" then return vpath
              end if
          end if
          idx = idx + 1
      end while

      idx = 0
      while idx < dirs.count()
          d = dirs[idx]
          dpath = d.lookUp("path")
          if dpath <> invalid and depth > 0
              vpath = findMovieInTree(baseUrl, sid, title, dpath, depth - 1)
              if vpath <> "" then return vpath
          end if
          idx = idx + 1
      end while

      return ""
  end function

  function firstSearchWord(title as string) as string
      cleaned = ""
      idx = 1
      while idx <= len(title)
          ch = mid(title, idx, 1)
          code = asc(lcase(ch))
          if (code >= 48 and code <= 57) or (code >= 97 and code <= 122)
              cleaned = cleaned + ch
          else if cleaned <> ""
              return cleaned
          end if
          idx = idx + 1
      end while
      return cleaned
  end function

  function findMovieBySearch(baseUrl as string, sid as string, title as string, basePath as string) as string
      word = firstSearchWord(title)
      if word = "" then return ""

      enc = createObject("roUrlTransfer")
      patterns = [word + "*", "*" + word + "*", title]
      for each pattern in patterns
          folderParam = "%5B%22" + enc.escape(basePath) + "%22%5D"
          startUrl = baseUrl + "/webapi/entry.cgi?api=SYNO.FileStation.Search&version=2&method=start&folder_path=" + folderParam + "&pattern=" + enc.escape(pattern) + "&filetype=file&recursive=true&_sid=" + sid
          print "FIND_MOVIE searchStart="; pattern
          r = httpGet(startUrl)
          if r <> invalid
              j = parseJSON(r)
              if j <> invalid and j.success = true and j.data <> invalid
                  taskid = j.data.lookUp("taskid")
                  if taskid <> invalid and taskid <> ""
                      poll = 0
                      while poll < 8
                          listUrl = baseUrl + "/webapi/entry.cgi?api=SYNO.FileStation.Search&version=2&method=list&taskid=" + enc.escape(taskid) + "&limit=5000&_sid=" + sid
                          lr = httpGetLong(listUrl, 10000)
                          if lr <> invalid
                              lj = parseJSON(lr)
                              if lj <> invalid and lj.success = true and lj.data <> invalid
                                  files = lj.data.lookUp("files")
                                  if files <> invalid
                                      for each f in files
                                          fname = f.lookUp("name")
                                          fpath = f.lookUp("path")
                                          if fname <> invalid and fpath <> invalid
                                              if isVideoFile(fname) and titleMatch(title, fname)
                                                  print "FIND_MOVIE searchMatch="; fpath
                                                  cleanUrl = baseUrl + "/webapi/entry.cgi?api=SYNO.FileStation.Search&version=2&method=clean&taskid=" + enc.escape(taskid) + "&_sid=" + sid
                                                  httpGet(cleanUrl)
                                                  return fpath
                                              end if
                                          end if
                                      end for
                                  end if
                                  finished = lj.data.lookUp("finished")
                                  if finished = true then exit while
                              end if
                          end if
                          poll = poll + 1
                      end while
                      cleanUrl = baseUrl + "/webapi/entry.cgi?api=SYNO.FileStation.Search&version=2&method=clean&taskid=" + enc.escape(taskid) + "&_sid=" + sid
                      httpGet(cleanUrl)
                  end if
              end if
          end if
      end for
      return ""
  end function

  ' Browse /video/Movies then /video for a subfolder whose name matches title.
  ' Returns the path of the first video file inside the matching folder.
  function findMovieByTitle(baseUrl as string, sid as string, title as string) as string
      if title = "" then return ""
      print "FIND_MOVIE title="; title
      enc = createObject("roUrlTransfer")
      idx = 0
      searchPaths = ["/video/Movies", "/video"]
      while idx < 2
          basePath = searchPaths[idx]
          print "FIND_MOVIE scan="; basePath
          fileUrl = baseUrl + "/webapi/entry.cgi?api=SYNO.FileStation.List&version=2&method=list&folder_path=" + enc.escape(basePath) + "&filetype=file&limit=5000&_sid=" + sid
          rf = httpGet(fileUrl)
          if rf <> invalid
              jf = parseJSON(rf)
              if jf <> invalid and jf.success = true
                  files = jf.data.lookUp("files")
                  if files <> invalid
                      fidx = 0
                      while fidx < files.count()
                          f = files[fidx]
                          fname = f.lookUp("name")
                          fpath = f.lookUp("path")
                          if fname <> invalid and fpath <> invalid
                              if isVideoFile(fname) and titleMatch(title, fname) then return fpath
                          end if
                          fidx = fidx + 1
                      end while
                  end if
              end if
          end if

          url = baseUrl + "/webapi/entry.cgi?api=SYNO.FileStation.List&version=2&method=list&folder_path=" + enc.escape(basePath) + "&filetype=dir&limit=5000&_sid=" + sid
          r = httpGet(url)
          if r <> invalid
              j = parseJSON(r)
              if j <> invalid and j.success = true
                  dirs = j.data.lookUp("files")
                  if dirs <> invalid
                      didx = 0
                      while didx < dirs.count()
                          d = dirs[didx]
                          dname = d.lookUp("name")
                          dpath = d.lookUp("path")
                          if dname <> invalid and dpath <> invalid
                              if titleMatch(title, dname)
                                  print "FIND_MOVIE matchDir="; dpath
                                  vpath = findVideoInDir(baseUrl, sid, dpath)
                                  if vpath <> "" then return vpath
                              end if
                          end if
                          didx = didx + 1
                      end while
                  end if
              end if
          end if
          vpath = findMovieInTree(baseUrl, sid, title, basePath, 4)
          if vpath <> "" then return vpath
          vpath = findMovieBySearch(baseUrl, sid, title, basePath)
          if vpath <> "" then return vpath
          idx = idx + 1
      end while
      print "FIND_MOVIE none"
      return ""
  end function
  
