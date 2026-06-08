' Convert any ID value (string or integer) to a plain string — never calls cstr() on a string.
  function idToStr(rawId as dynamic) as string
      if rawId = invalid then return "0"
      t = type(rawId)
      if t = "roString" or t = "String"
          s = rawId
          return s.trim()
      end if
      if t = "roInteger" or t = "Integer" or t = "roInt" or t = "roLongInteger" or t = "LongInteger"
          s = stri(rawId)
          return s.trim()
      end if
      if t = "roFloat" or t = "Float" or t = "roDouble" or t = "Double"
          s = stri(int(rawId))
          return s.trim()
      end if
      return "0"
  end function

sub init()
      m.top.functionName = "runTask"
      m.flattenBrowseFileFields = false
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
      if action = "setVideoWatched" then setVideoWatched(req)
      if action = "setVideoRating" then setVideoRating(req)
      if action = "detailState" then detailState(req)
      if action = "listLibraries" then listLibraries(req)
      if action = "listEpisodes" then listEpisodes(req)
      if action = "movieMetadata" then movieMetadata(req)
      if action = "latestResume" then latestResume(req)
      if action = "getStreamUrl" then getStreamUrl(req)
      if action = "refreshHomeVideoFilenameCache" then refreshHomeVideoFilenameCache(req)
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

  function refreshVideoStationSession(baseUrl as string, username as dynamic, password as dynamic) as dynamic
      if baseUrl = invalid or baseUrl = "" then return invalid
      if username = invalid or password = invalid then return invalid
      if username = "" then return invalid
      enc = createObject("roUrlTransfer")
      url = baseUrl + "/webapi/auth.cgi?api=SYNO.API.Auth&version=6&method=login&account=" + enc.escape(username) + "&passwd=" + enc.escape(password) + "&session=VideoStation&format=sid&enable_syno_token=yes"
      result = httpGet(url)
      if result = invalid or result = "" then
          print "SESSION_REFRESH failed empty"
          return invalid
      end if
      json = parseJSON(result)
      if json = invalid or json.success <> true or json.data = invalid or json.data.sid = invalid or json.data.sid = "" then
          print "SESSION_REFRESH failed resp="; left(result, 180)
          return invalid
      end if
      synoToken = ""
      if json.data.synotoken <> invalid then synoToken = json.data.synotoken
      print "SESSION_REFRESH ok sidLen="; len(json.data.sid); " tokenLen="; len(synoToken)
      return { sid: json.data.sid, synoToken: synoToken }
  end function

  ' ── Movies ───────────────────────────────────────────────────────────────────
  sub listMovies(req as object)
      baseUrl = req.baseUrl
      m.skipCachedArtworkResolve = false
      sid = req.sid
      token = ""
      if req.synoToken <> invalid then token = req.synoToken

      libraryParam = libraryParamFromReq(req)
      url = apiUrl(baseUrl, "SYNO.VideoStation2.Movie", "entry.cgi", "1", "list", "offset=0&limit=500&sort_by=title&sort_direction=asc&additional=%5B%22file%22,%22summary%22,%22extra%22,%22watched_ratio%22,%22rating%22,%22poster_mtime%22,%22backdrop_mtime%22%5D" + libraryParam, sid, token)
      result = httpGet(url)
      key = firstValidKey(result, ["movie", "movies"])
      if key <> ""
          m.skipCachedArtworkResolve = true
          parseAndRespond(result, key, baseUrl, sid)
          m.skipCachedArtworkResolve = false
          print "GRID_SOURCE category=movies source=synology2 count="; m.top.response.items.count()
          return
      end if

      url = apiUrl(baseUrl, "SYNO.VideoStation.Movie", "VideoStation/movie.cgi", "1", "list", "offset=0&limit=500&sort_by=title&sort_direction=asc&additional=%5B%22file%22,%22summary%22,%22extra%22,%22watched_ratio%22,%22rating%22,%22poster_mtime%22,%22backdrop_mtime%22%5D" + libraryParam, sid, token)
      result = httpGet(url)
      key = firstValidKey(result, ["movies", "movie"])
      if key <> ""
          m.skipCachedArtworkResolve = true
          parseAndRespond(result, key, baseUrl, sid)
          m.skipCachedArtworkResolve = false
          print "GRID_SOURCE category=movies source=synology1 count="; m.top.response.items.count()
          return
      end if

      ' Return the last raw result so the error is visible
      parseAndRespond(result, "movies", baseUrl, sid)
  end sub

  ' ── TV Shows ──────────────────────────────────────────────────────────────────
  sub listTVShows(req as object)
      baseUrl = req.baseUrl
      m.skipCachedArtworkResolve = false
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
          m.skipCachedArtworkResolve = true
          m.currentProxyPosterFallbackOnly = libraryParam = ""
          parseAndRespond(result, key, baseUrl, sid)
          m.skipCachedArtworkResolve = false
          m.currentProxyPosterFallbackOnly = false
          m.top.response.detail = "synology2 tvshow direct poster count=" + stri(m.top.response.items.count()).trim()
          print "GRID_SOURCE category="; gridCategory; " source=synology2 libraryParam="; libraryParam; " count="; m.top.response.items.count()
          return
      end if

      url = apiUrl(baseUrl, "SYNO.VideoStation.TVShow", "VideoStation/tvshow.cgi", "1", "list", "offset=0&limit=500&sort_by=title&sort_direction=asc&additional=%5B%22poster_mtime%22,%22backdrop_mtime%22%5D" + libraryParam, sid, token)
      result = httpGet(url)
      key = firstValidKey(result, ["tvshows", "tvshow"])
      if key <> ""
          m.skipCachedArtworkResolve = true
          m.currentProxyPosterFallbackOnly = libraryParam = ""
          parseAndRespond(result, key, baseUrl, sid)
          m.skipCachedArtworkResolve = false
          m.currentProxyPosterFallbackOnly = false
          m.top.response.detail = "synology1 tvshow direct poster count=" + stri(m.top.response.items.count()).trim()
          print "GRID_SOURCE category="; gridCategory; " source=synology1 libraryParam="; libraryParam; " count="; m.top.response.items.count()
          return
      end if

      parseAndRespond(result, "tvshows", baseUrl, sid)
  end sub

  ' ── Home Videos ───────────────────────────────────────────────────────────────
  sub listHomeVideos(req as object)
      baseUrl = req.baseUrl
      m.skipCachedArtworkResolve = false
      sid = req.sid
      token = ""
      if req.synoToken <> invalid then token = req.synoToken

      libraryParam = libraryParamFromReq(req)
      offset = 0
      limit = 500
      if req.offset <> invalid then offset = int(req.offset)
      if req.limit <> invalid then limit = int(req.limit)
      params = "offset=" + stri(offset).trim() + "&limit=" + stri(limit).trim() + "&sort_by=title&sort_direction=asc&additional=%5B%22file%22,%22watched_ratio%22,%22rating%22,%22poster_mtime%22,%22extra%22,%22originally_available%22,%22record_time%22,%22record_time_utc%22,%22date%22,%22create_time%22%5D" + libraryParam
      url = apiUrl(baseUrl, "SYNO.VideoStation2.HomeVideo", "entry.cgi", "1", "list", params, sid, token)
      result = httpGet(url)
      key = firstValidKey(result, ["video", "videos"])
      if key <> ""
          m.skipCachedArtworkResolve = true
          m.flattenBrowseFileFields = true
          parseAndRespond(result, key, baseUrl, sid)
          m.flattenBrowseFileFields = false
          m.skipCachedArtworkResolve = false
          print "GRID_SOURCE category=homevideos source=synology2 count="; m.top.response.items.count()
          return
      end if

      url = apiUrl(baseUrl, "SYNO.VideoStation.HomeVideo", "VideoStation/homevideo.cgi", "1", "list", params, sid, token)
      result = httpGet(url)
      key = firstValidKey(result, ["video", "videos"])
      if key <> ""
          m.skipCachedArtworkResolve = true
          m.flattenBrowseFileFields = true
          parseAndRespond(result, key, baseUrl, sid)
          m.flattenBrowseFileFields = false
          m.skipCachedArtworkResolve = false
          print "GRID_SOURCE category=homevideos source=synology1 count="; m.top.response.items.count()
          return
      end if

      m.flattenBrowseFileFields = true
      parseAndRespond(result, "video", baseUrl, sid)
      m.flattenBrowseFileFields = false
  end sub

  sub listTVRecordings(req as object)
      baseUrl = req.baseUrl
      m.skipCachedArtworkResolve = true
      sid = req.sid
      token = ""
      if req.synoToken <> invalid then token = req.synoToken
      url = apiUrl(baseUrl, "SYNO.VideoStation.TVRecording", "VideoStation/tv_record.cgi", "1", "list", "offset=0&limit=500&sort_by=title&sort_direction=asc&additional=%5B%22file%22,%22watched_ratio%22,%22rating%22,%22poster_mtime%22,%22date%22,%22create_time%22,%22start_time%22%5D" + libraryParamFromReq(req), sid, token)
      result = httpGet(url)
      key = firstValidKey(result, ["records", "record", "tv_record", "videos", "video"])
      if key <> ""
          m.flattenBrowseFileFields = true
          parseAndRespond(result, key, baseUrl, sid)
          m.flattenBrowseFileFields = false
          m.skipCachedArtworkResolve = false
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

      additional = "%5B%22watched_ratio%22,%22file_watched%22,%22last_watched%22,%22file%22,%22poster_mtime%22,%22backdrop_mtime%22,%22summary%22,%22extra%22,%22collection%22,%22rating%22,%22originally_available%22%5D"
      params = "id=" + collectionId + "&offset=0&limit=500&sort_by=title&sort_direction=asc&additional=" + additional
      url = apiUrl(baseUrl, "SYNO.VideoStation.Collection", "VideoStation/collection.cgi", "2", "video_list", params, sid, token)
      result = httpGet(url)
      respondWithCollectionVideos(result, baseUrl, sid, token)
  end sub

  sub toggleCollectionVideo(req as object)
      baseUrl = req.baseUrl
      sid = req.sid
      token = ""
      if req.synoToken <> invalid then token = req.synoToken
      collectionId = idToStr(req.collectionId)
      if collectionId = "" or collectionId = "0" then collectionId = collectionIdForKey(idToStr(req.localKey))
      if left(collectionId, 1) = "-"
          resolvedCollectionId = resolveCollectionId(baseUrl, sid, token, idToStr(req.localKey), collectionId)
          if resolvedCollectionId = "" or resolvedCollectionId = "0" or left(resolvedCollectionId, 1) = "-"
              resolvedCollectionId = defaultRealCollectionIdForKey(idToStr(req.localKey))
          end if
          if resolvedCollectionId <> "" and resolvedCollectionId <> "0" and left(resolvedCollectionId, 1) <> "-"
              print "COLLECTION_ID_RESOLVE key="; idToStr(req.localKey); " pseudo="; collectionId; " real="; resolvedCollectionId
              collectionId = resolvedCollectionId
          end if
      end if
      videoId = idToStr(req.videoId)
      videoType = collectionVideoType(idToStr(req.videoType))
      mapperId = ""
      if req.mapperId <> invalid then mapperId = idToStr(req.mapperId)
      if collectionId = "" or videoId = "" or videoId = "0"
          m.top.response = { success: false, error: "Missing collection or video id" }
          return
      end if

      method = "deletevideo"
      if req.enabled = true then method = "addvideo"
      enc = createObject("roUrlTransfer")
      videoTypes = collectionVideoTypeCandidates(videoType)
      lastResult = ""
      lastAttempt = ""

      for each candidateType in videoTypes
          v2Result = syncCollectionVideoV2(baseUrl, sid, token, collectionId, videoId, candidateType, req.enabled = true)
          if v2Result <> invalid
              v2Json = parseJSON(v2Result)
              if v2Json <> invalid and v2Json.success = true
                  m.top.response = { success: true, result: v2Json, attempt: "v2 " + candidateType }
                  return
              end if
              lastResult = v2Result
              lastAttempt = "v2 " + candidateType
          end if
      end for

      url = apiEndpoint(baseUrl, "SYNO.VideoStation.Collection", "VideoStation/collection.cgi", sid, token)

      for each candidateType in videoTypes
          typeParam = enc.escape(candidateType)
          attempts = [
              { version: "1", params: "id=" + collectionId + "&type=" + typeParam + "&video_id=" + videoId },
              { version: "1", params: "id=" + collectionId + "&video_type=" + typeParam + "&video_id=" + videoId },
              { version: "2", params: "id=" + collectionId + "&type=" + typeParam + "&video_id=" + videoId },
              { version: "2", params: "id=" + collectionId + "&video_type=" + typeParam + "&video_id=" + videoId },
              { version: "1", params: "id=" + collectionId + "&type=" + typeParam + "&video_ids=%5B" + videoId + "%5D" },
              { version: "1", params: "id=" + collectionId + "&video_type=" + typeParam + "&video_ids=%5B" + videoId + "%5D" },
              { version: "2", params: "id=" + collectionId + "&type=" + typeParam + "&video_ids=%5B" + videoId + "%5D" },
              { version: "2", params: "id=" + collectionId + "&video_type=" + typeParam + "&video_ids=%5B" + videoId + "%5D" }
          ]
          for each attempt in attempts
              lastAttempt = "v" + attempt.version + " " + method + " " + attempt.params
              body = "api=SYNO.VideoStation.Collection&version=" + attempt.version + "&method=" + method + "&" + attempt.params
              result = httpPostForm(url, body)
              if result <> invalid and result <> ""
                  lastResult = result
                  print "COLLECTION_SYNC_ATTEMPT "; lastAttempt; " resp="; left(result, 180)
                  json = parseJSON(result)
                  if json <> invalid and json.success = true
                      m.top.response = { success: true, result: json, attempt: lastAttempt }
                      return
                  end if
              else
                  print "COLLECTION_SYNC_ATTEMPT "; lastAttempt; " resp=<empty>"
              end if
          end for
      end for

      if lastResult = ""
          m.top.response = { success: false, error: "No response from Synology collection API", detail: lastAttempt }
      else
          m.top.response = { success: false, error: "Synology collection update failed", detail: left(lastResult, 300), attempt: lastAttempt }
      end if
  end sub

  function syncCollectionVideoV2(baseUrl as string, sid as string, token as string, collectionId as string, videoId as string, videoType as string, enabled as boolean) as dynamic
      methodName = "delete_video"
      if enabled then methodName = "add_video"
      enc = createObject("roUrlTransfer")
      url = apiEndpoint(baseUrl, "SYNO.VideoStation2.Collection", "entry.cgi", sid, token)
      videoJson = "[{""video_id"":" + videoId + ",""video_type"":""" + videoType + """}]"
      body = "api=SYNO.VideoStation2.Collection&version=1&method=" + methodName + "&id=" + enc.escape(collectionId) + "&video=" + enc.escape(videoJson)
      result = httpPostForm(url, body)
      if result <> invalid and result <> ""
          print "COLLECTION_V2_ATTEMPT method="; methodName; " id="; collectionId; " videoId="; videoId; " type="; videoType; " resp="; left(result, 180)
      else
          print "COLLECTION_V2_ATTEMPT method="; methodName; " id="; collectionId; " videoId="; videoId; " type="; videoType; " resp=<empty>"
      end if
      return result
  end function

  sub updateWatchStatus(req as object)
      baseUrl = req.baseUrl
      sid = req.sid
      token = ""
      if req.synoToken <> invalid then token = req.synoToken
      videoId = idToStr(req.videoId)
      videoType = collectionVideoType(idToStr(req.videoType))
      fileId = idToStr(req.fileId)
      mapperId = idToStr(req.mapperId)
      position = 0
      if req.position <> invalid then position = int(req.position)
      if videoId = "" or videoId = "0" or position < 0
          m.top.response = { success: false, error: "Missing watch status id" }
          return
      end if

      wrapperResult = updateWatchStatusViaRokuVteWrapper(baseUrl, sid, token, fileId, mapperId, position)
      if wrapperResult <> invalid
          wrapperJson = parseJSON(wrapperResult)
          if wrapperJson <> invalid and wrapperJson.success = true
              m.top.response = { success: true, result: wrapperJson, source: "rokuvte-wrapper" }
              return
          end if
          print "WATCH_STATUS_WRAPPER failed="; left(wrapperResult, 180)
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

  function updateWatchStatusViaRokuVteWrapper(baseUrl as string, sid as string, token as string, fileId as string, mapperId as string, position as integer) as dynamic
      if sid = "" then return invalid
      if (fileId = "" or fileId = "0") and (mapperId = "" or mapperId = "0") then return invalid
      enc = createObject("roUrlTransfer")
      url = localVideoBaseUrl(baseUrl) + "/webapi/VideoStation/rokuvte.cgi?action=watch_status&sid=" + enc.escape(sid) + "&position=" + stri(position).trim()
      if token <> "" then url = url + "&token=" + enc.escape(token)
      if fileId <> "" and fileId <> "0" then url = url + "&file_id=" + enc.escape(fileId)
      if mapperId <> "" and mapperId <> "0" then url = url + "&mapper_id=" + enc.escape(mapperId)
      return httpGet(url)
  end function

  sub setVideoWatched(req as object)
      baseUrl = req.baseUrl
      sid = req.sid
      token = ""
      if req.synoToken <> invalid then token = req.synoToken
      videoId = idToStr(req.videoId)
      mediaType = idToStr(req.videoType)
      watchedText = "false"
      if req.watched = true then watchedText = "true"
      if videoId = "" or videoId = "0"
          m.top.response = { success: false, error: "Missing watched id" }
          return
      end if

      apiName = v2InfoApiForMediaType(mediaType)
      url = apiEndpoint(baseUrl, apiName, "entry.cgi", sid, token)
      enc = createObject("roUrlTransfer")
      baseBody = "api=" + enc.escape(apiName) + "&version=1&method=set_watched&watched=" + watchedText + "&id="
      idForms = [
          "%5B%22" + enc.escape(videoId) + "%22%5D",
          "%5B" + enc.escape(videoId) + "%5D",
          enc.escape(videoId)
      ]
      lastResult = ""
      for each idForm in idForms
          body = baseBody + idForm
          result = httpPostForm(url, body)
          if result <> invalid and result <> ""
              lastResult = result
              json = parseJSON(result)
              if json <> invalid and json.success = true
                  m.top.response = { success: true, result: json, watched: req.watched = true, idForm: idForm }
                  return
              end if
          end if
      end for
      if lastResult = invalid or lastResult = ""
          m.top.response = { success: false, error: "No response from Synology watched API" }
      else
          m.top.response = { success: false, error: "Synology watched update failed", detail: left(lastResult, 300) }
      end if
  end sub

  sub setVideoRating(req as object)
      baseUrl = req.baseUrl
      sid = req.sid
      token = ""
      if req.synoToken <> invalid then token = req.synoToken
      videoId = idToStr(req.videoId)
      mediaType = idToStr(req.videoType)
      rating = 0
      if req.rating <> invalid then rating = int(req.rating)
      if rating < 0 then rating = 0
      if rating > 100 then rating = 100
      if videoId = "" or videoId = "0"
          m.top.response = { success: false, error: "Missing rating id" }
          return
      end if

      apiName = legacyVideoApiForMediaType(mediaType)
      enc = createObject("roUrlTransfer")
      params = "id=" + enc.escape(videoId) + "&rating=" + stri(rating).trim()
      result = httpGet(apiUrl(baseUrl, apiName, legacyVideoPathForMediaType(mediaType), "4", "set_rating", params, sid, token))
      if result = invalid or result = ""
          m.top.response = { success: false, error: "No response from Synology rating API" }
          return
      end if
      json = parseJSON(result)
      if json <> invalid and json.success = true
          m.top.response = { success: true, result: json, rating: rating }
      else
          m.top.response = { success: false, error: "Synology rating update failed", detail: left(result, 300) }
      end if
  end sub

  function legacyVideoApiForMediaType(mediaType as string) as string
      if mediaType = "movie" then return "SYNO.VideoStation.Movie"
      if mediaType = "homevideo" then return "SYNO.VideoStation.HomeVideo"
      if mediaType = "homeVideo" then return "SYNO.VideoStation.HomeVideo"
      if mediaType = "episode" then return "SYNO.VideoStation.TVShowEpisode"
      return v2InfoApiForMediaType(mediaType)
  end function

  function legacyVideoPathForMediaType(mediaType as string) as string
      if mediaType = "movie" then return "VideoStation/movie.cgi"
      if mediaType = "homevideo" then return "VideoStation/homevideo.cgi"
      if mediaType = "homeVideo" then return "VideoStation/homevideo.cgi"
      if mediaType = "episode" then return "VideoStation/tvshow_episode.cgi"
      return "entry.cgi"
  end function

  sub detailState(req as object)
      baseUrl = req.baseUrl
      sid = req.sid
      token = ""
      if req.synoToken <> invalid then token = req.synoToken
      videoId = idToStr(req.videoId)
      mediaType = idToStr(req.videoType)
      if videoId = "" or videoId = "0"
          m.top.response = { success: false, error: "Missing detail id" }
          return
      end if

      candidates = []
      if req.videoIds <> invalid
          for each candidate in req.videoIds
              pushUniqueString(candidates, candidate)
          end for
      end if
      pushUniqueString(candidates, videoId)

      item = invalid
      usedId = ""
      for each candidateId in candidates
          candidateItem = fetchCollectionInfoItem(baseUrl, sid, token, candidateId, mediaType)
          if candidateItem <> invalid
              if item = invalid
                  item = candidateItem
                  usedId = candidateId
              end if
              if detailStateRating(candidateItem) > 0
                  item = candidateItem
                  usedId = candidateId
                  exit for
              end if
              if detailStateHas(candidateItem, ["watched_ratio", "watchedRatio"]) and not detailStateHas(item, ["watched_ratio", "watchedRatio"])
                  item = candidateItem
                  usedId = candidateId
              end if
          end if
      end for
      if item = invalid
          m.top.response = { success: false, error: "No detail state response", id: videoId, candidates: candidates.count() }
          return
      end if

      rating = detailStateRating(item)
      summary = ""
      if mediaType = "movie"
          summary = movieSummaryText(item)
      else
          summary = episodeSummaryText(item)
      end if
      showBackdropUrl = ""
      if mediaType = "episode"
          showBackdropUrl = detailStateShowBackdropUrl(baseUrl, sid, token, item)
      end if
      watched = detailStateWatchedPercent(item)
      hasWatched = detailStateHas(item, ["watched_ratio", "watchedRatio"])
      favorite = detailStateCollectionHas(item, ["5"], ["syno_favorite", "favorite", "favorites"])
      watchlist = detailStateCollectionHas(item, ["4"], ["syno_watchlist", "watchlist", "watch list"])
      print "DETAIL_STATE_API type="; mediaType; " id="; usedId; " rating="; rating; " summaryLen="; len(summary); " showBackdrop="; len(showBackdropUrl); " watchedRatio="; watched; " hasWatched="; hasWatched; " favorite="; favorite; " watchlist="; watchlist
      m.top.response = { success: true, id: usedId, rating: rating, summary: summary, showBackdropUrl: showBackdropUrl, watchedRatio: watched, hasWatched: hasWatched, favorite: favorite, watchlist: watchlist }
  end sub

  function detailStateShowBackdropUrl(baseUrl as string, sid as string, token as string, item as object) as string
      if baseUrl = "" or sid = "" or item = invalid then return ""
      tvshow = invalid
      additional = item.lookUp("additional")
      if additional <> invalid then tvshow = additional.lookUp("tvshow")
      if tvshow = invalid then tvshow = item.lookUp("tvshow")
      if tvshow <> invalid and type(tvshow) = "roAssociativeArray"
          tvshowId = idToStr(tvshow.lookUp("id"))
          if tvshowId <> "" and tvshowId <> "0"
              url = baseUrl + "/webapi/entry.cgi?api=SYNO.VideoStation2.Backdrop&version=1&method=get"
              url = url + "&id=" + tvshowId + "&type=tvshow&_sid=" + sid
              if token <> "" then url = url + "&SynoToken=" + token
              return url
          end if
          mapper = idToStr(tvshow.lookUp("mapper_id"))
          if mapper = "" or mapper = "0" then mapper = idToStr(tvshow.lookUp("mapperId"))
          if mapper <> "" and mapper <> "0"
              url = baseUrl + "/webapi/VideoStation/backdrop.cgi?api=SYNO.VideoStation.Backdrop&version=1&method=get&mapper_id=" + mapper
              url = url + "&_sid=" + sid
              if token <> "" then url = url + "&SynoToken=" + token
              return url
          end if
      end if
      title = collectionDeepText(item, ["showTitle", "tvshow_title", "series_title", "parent_title"])
      if title = "" or title = "0" then title = collectionDeepText(item, ["title", "name"])
      show = tvShowByTitle(baseUrl, sid, token, title)
      if show <> invalid then return showBackdropUrlFromShow(baseUrl, sid, token, show)
      return ""
  end function

  function detailStateCollectionHas(item as object, ids as object, names as object) as boolean
      collection = detailStateValue(item, ["collection", "collections"])
      if detailStateCollectionValueHas(collection, ids, names) then return true
      additional = detailStateObject(item.lookUp("additional"))
      if additional <> invalid
          collection = detailStateValue(additional, ["collection", "collections"])
          if detailStateCollectionValueHas(collection, ids, names) then return true
      end if
      extra = detailStateObject(item.lookUp("extra"))
      if extra <> invalid
          collection = detailStateValue(extra, ["collection", "collections"])
          if detailStateCollectionValueHas(collection, ids, names) then return true
      end if
      return false
  end function

  function detailStateCollectionValueHas(value as dynamic, ids as object, names as object) as boolean
      if value = invalid then return false
      t = type(value)
      if t = "roArray"
          for each entry in value
              if detailStateCollectionEntryHas(entry, ids, names) then return true
          end for
          return false
      end if
      if t = "roAssociativeArray"
          return detailStateCollectionEntryHas(value, ids, names)
      end if
      if t = "roString" or t = "String"
          parsed = parseJSON(value)
          if parsed <> invalid then return detailStateCollectionValueHas(parsed, ids, names)
          lower = lcase(value)
          for each name in names
              if instr(1, lower, lcase(name)) > 0 then return true
          end for
          for each id in ids
              if instr(1, lower, """" + id + """") > 0 or instr(1, lower, ":" + id) > 0 then return true
          end for
      end if
      return false
  end function

  function detailStateCollectionEntryHas(entry as dynamic, ids as object, names as object) as boolean
      if entry = invalid then return false
      t = type(entry)
      if t = "roString" or t = "String"
          lower = lcase(entry)
          for each name in names
              if lower = lcase(name) or instr(1, lower, lcase(name)) > 0 then return true
          end for
          for each id in ids
              if entry = id then return true
          end for
          return false
      end if
      if t <> "roAssociativeArray" then return false

      idText = idToStr(entry.lookUp("id"))
      if idText = "" or idText = "0" then idText = idToStr(entry.lookUp("collection_id"))
      for each id in ids
          if idText = id then return true
      end for

      title = lcase(idToStr(entry.lookUp("title")))
      if title = "" or title = "0" then title = lcase(idToStr(entry.lookUp("name")))
      if title = "" or title = "0" then title = lcase(idToStr(entry.lookUp("type")))
      for each name in names
          if title = lcase(name) or instr(1, title, lcase(name)) > 0 then return true
      end for
      return false
  end function

  function detailStateRating(item as object) as integer
      rating = detailStateInt(item, ["rating", "rate", "user_rating", "userRating", "my_rating", "myRating"])
      if rating > 0 then return normalizeDetailStateRating(rating)
      return detailStateExtraRating(item)
  end function

  function detailStateExtraRating(item as object) as integer
      candidates = []
      if item <> invalid
          ratingValue = item.lookUp("rating")
          if ratingValue <> invalid then candidates.push(ratingValue)
          extra = item.lookUp("extra")
          if extra <> invalid then candidates.push(extra)
          additional = item.lookUp("additional")
          if additional <> invalid
              ratingValue = additional.lookUp("rating")
              if ratingValue <> invalid then candidates.push(ratingValue)
              extra = additional.lookUp("extra")
              if extra <> invalid then candidates.push(extra)
          end if
      end if
      for each candidate in candidates
          rating = detailStateAnyRating(candidate, 0)
          if rating <= 0
              extraObj = detailStateObject(candidate)
              rating = detailStateNestedDbRating(extraObj)
          end if
          if rating > 0 then return rating
      end for
      return 0
  end function

  function detailStateNestedDbRating(extraObj as dynamic) as integer
      if extraObj = invalid or type(extraObj) <> "roAssociativeArray" then return 0
      anyRating = detailStateAnyRating(extraObj, 0)
      if anyRating > 0 then return anyRating
      best = 0
      for each dbKey in ["synoVideoDb", "synovideodb", "theMovieDb", "themoviedb", "theTVDb", "thetvdb"]
          db = extraObj.lookUp(dbKey)
          if db <> invalid and type(db) = "roAssociativeArray"
              ratingObj = db.lookUp("rating")
              if ratingObj <> invalid and type(ratingObj) = "roAssociativeArray"
                  for each ratingKey in ["synovideodb", "synoVideoDb", "themoviedb", "theMovieDb", "thetvdb", "theTVDb", "rating"]
                      value = ratingObj.lookUp(ratingKey)
                      if value <> invalid
                          num = detailStateValueToInt(value)
                          if num > 0 and num <= 10 then num = num * 10
                          if num > best then best = num
                      end if
                  end for
              end if
          end if
      end for
      if best > 100 then best = 100
      return best
  end function

  function detailStateAnyRating(value as dynamic, depth as integer) as integer
      if value = invalid or depth > 4 then return 0
      t = type(value)
      if t = "roInteger" or t = "Integer" or t = "roInt" or t = "roLongInteger" or t = "LongInteger" or t = "roFloat" or t = "Float" or t = "roDouble" or t = "Double"
          return normalizeDetailStateRating(value)
      end if
      if t = "roString" or t = "String"
          trimmed = value.trim()
          if trimmed = "" then return 0
          parsed = parseJSON(trimmed)
          if parsed <> invalid then return detailStateAnyRating(parsed, depth + 1)
          return normalizeDetailStateRating(val(trimmed))
      end if
      if t = "roArray"
          best = 0
          for each child in value
              score = detailStateAnyRating(child, depth + 1)
              if score > best then best = score
          end for
          return best
      end if
      if t = "roAssociativeArray"
          best = 0
          for each key in value
              lower = lcase(key)
              child = value.lookUp(key)
              score = 0
              if lower = "rating" or lower = "rate" or instr(1, lower, "rating") > 0 or lower = "imdb" or lower = "tmdb" or lower = "themoviedb" or lower = "thetvdb" or lower = "synovideodb"
                  score = detailStateAnyRating(child, depth + 1)
              else if type(child) = "roAssociativeArray"
                  score = detailStateAnyRating(child, depth + 1)
              end if
              if score > best then best = score
          end for
          return best
      end if
      return 0
  end function

  function normalizeDetailStateRating(value as dynamic) as integer
      num = detailStateValueToInt(value)
      if num <= 0 then return 0
      if num <= 10 then num = num * 10
      if num > 100 then num = 100
      return num
  end function

  function detailStateWatchedPercent(item as object) as integer
      raw = detailStateValue(item, ["watched_ratio", "watchedRatio"])
      if raw = invalid then return 0
      return detailStateWatchedValueToPercent(raw)
  end function

  function detailStateValue(item as object, keys as object) as dynamic
      if item = invalid then return invalid
      for each key in keys
          value = item.lookUp(key)
          if value <> invalid then return value
      end for
      additional = item.lookUp("additional")
      if additional <> invalid
          for each key in keys
              value = additional.lookUp(key)
              if value <> invalid then return value
          end for
          extra = detailStateObject(additional.lookUp("extra"))
          if extra <> invalid
              for each key in keys
                  value = extra.lookUp(key)
                  if value <> invalid then return value
              end for
          end if
      end if
      extra = detailStateObject(item.lookUp("extra"))
      if extra <> invalid
          for each key in keys
              value = extra.lookUp(key)
              if value <> invalid then return value
          end for
      end if
      return invalid
  end function

  function detailStateInt(item as object, keys as object) as integer
      if item = invalid then return 0
      for each key in keys
          value = item.lookUp(key)
          if value <> invalid then return detailStateValueToInt(value)
      end for
      additional = item.lookUp("additional")
      if additional <> invalid
          for each key in keys
              value = additional.lookUp(key)
              if value <> invalid then return detailStateValueToInt(value)
          end for
          extra = additional.lookUp("extra")
          nested = detailStateIntFromObject(extra, keys)
          if nested >= 0 then return nested
      end if
      extra = item.lookUp("extra")
      nested = detailStateIntFromObject(extra, keys)
      if nested >= 0 then return nested
      return 0
  end function

  function detailStateIntFromObject(item as dynamic, keys as object) as integer
      item = detailStateObject(item)
      if item = invalid then return -1
      for each key in keys
          value = item.lookUp(key)
          if value <> invalid then return detailStateValueToInt(value)
      end for
      return -1
  end function

  function detailStateHasInObject(item as dynamic, keys as object) as boolean
      item = detailStateObject(item)
      if item = invalid then return false
      for each key in keys
          if item.lookUp(key) <> invalid then return true
      end for
      return false
  end function

  function detailStateHasNested(item as object, keys as object) as boolean
      if item = invalid then return false
      additional = item.lookUp("additional")
      if additional <> invalid
          extra = additional.lookUp("extra")
          if detailStateHasInObject(extra, keys) then return true
      end if
      extra = item.lookUp("extra")
      return detailStateHasInObject(extra, keys)
  end function

  function detailStateHas(item as object, keys as object) as boolean
      if item = invalid then return false
      for each key in keys
          if item.lookUp(key) <> invalid then return true
      end for
      additional = item.lookUp("additional")
      if additional <> invalid
          for each key in keys
              if additional.lookUp(key) <> invalid then return true
          end for
      end if
      if detailStateHasNested(item, keys) then return true
      return false
  end function

  function detailStateValueToInt(value as dynamic) as integer
      if value = invalid then return 0
      t = type(value)
      if t = "roInteger" or t = "Integer" or t = "roInt" or t = "roLongInteger" or t = "LongInteger" then return value
      if t = "roFloat" or t = "Float" or t = "roDouble" or t = "Double" then return int(value)
      if t = "roString" or t = "String"
          trimmed = value.trim()
          if trimmed = "" then return 0
          return int(val(trimmed))
      end if
      return 0
  end function

  function detailStateWatchedValueToPercent(value as dynamic) as integer
      if value = invalid then return 0
      t = type(value)
      if t = "roFloat" or t = "Float" or t = "roDouble" or t = "Double"
          if value >= 0 and value <= 1 then return int((value * 100) + 0.5)
          return int(value)
      end if
      if t = "roInteger" or t = "Integer" or t = "roInt" or t = "roLongInteger" or t = "LongInteger"
          if value = 1 then return 100
          return value
      end if
      if t = "roString" or t = "String"
          trimmed = value.trim()
          if trimmed = "" then return 0
          numberValue = val(trimmed)
          if numberValue >= 0 and numberValue <= 1 then return int((numberValue * 100) + 0.5)
          return int(numberValue)
      end if
      return 0
  end function

  function detailStateObject(value as dynamic) as dynamic
      if value = invalid then return invalid
      if type(value) = "roAssociativeArray" then return value
      if type(value) = "roString" or type(value) = "String"
          trimmed = value.trim()
          if trimmed = "" then return invalid
          parsed = parseJSON(trimmed)
          if parsed <> invalid and type(parsed) = "roAssociativeArray" then return parsed
      end if
      return invalid
  end function

  sub listLibraries(req as object)
      baseUrl = req.baseUrl
      sid = req.sid
      token = ""
      if req.synoToken <> invalid then token = req.synoToken
      items = defaultLibraries()

      custom = fetchDirectLibraries(baseUrl, sid, token)

      appendCustomLibraries(items, custom)
      print "LIBRARY_SOURCE source=synology customCount="; custom.count(); " total="; items.count()
      m.top.response = { success: true, items: items, total: items.count() }
  end sub

  ' ── Episodes ──────────────────────────────────────────────────────────────────
  sub listEpisodes(req as object)
      baseUrl = req.baseUrl
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

      lastResult = invalid
      lastUrl = ""
      bestEpisodes = []
      bestMetadata = []
      loadClock = createObject("roTimespan")
      loadClock.mark()
      bestSource = ""
      directMs = 0
      directCandidate = ""

      for each candidateId in candidates
          direct = directEpisodeListResult(baseUrl, sid, token, candidateId, showTitle, libraryId)
          directMs = int(loadClock.totalMilliseconds())
          directCandidate = idToStr(candidateId)
          if direct.url <> "" then lastUrl = direct.url
          if direct.result <> invalid then lastResult = direct.result
          if direct.metadata.count() > bestMetadata.count() then bestMetadata = direct.metadata
          if direct.episodes.count() > bestEpisodes.count()
              bestEpisodes = direct.episodes
              bestSource = direct.source
          end if
          if direct.episodes.count() > 0 then exit for
      end for

      if bestEpisodes.count() > 0
          if bestMetadata.count() > 0 then bestEpisodes = mergeEpisodeMetadata(bestEpisodes, bestMetadata)
          normalizeEpisodeItems(bestEpisodes)
          addDirectPosterIds(bestEpisodes)
          bestEpisodes = uniqueEpisodeItems(bestEpisodes)
          totalMs = int(loadClock.totalMilliseconds())
          postMs = totalMs - directMs
          print "EPISODE_SOURCE source=synology-direct count="; bestEpisodes.count(); " totalMs="; totalMs; " directMs="; directMs; " postMs="; postMs
          m.top.response = { success: true, items: bestEpisodes, total: bestEpisodes.count(), baseUrl: baseUrl, sid: sid }
          return
      end if

      fallbackStartMs = int(loadClock.totalMilliseconds())
      fallbackEpisodes = findEpisodesByShowTitle(baseUrl, sid, token, showTitle)
      if fallbackEpisodes.count() > 0
          if bestMetadata.count() > 0 then fallbackEpisodes = mergeEpisodeMetadata(fallbackEpisodes, bestMetadata)
          normalizeEpisodeItems(fallbackEpisodes)
          enrichEpisodeSummariesFromVsmeta(fallbackEpisodes, baseUrl, sid, token)
          addDirectPosterIds(fallbackEpisodes)
          addFileStationSidecarPosterUrls(fallbackEpisodes, baseUrl, sid, token)
          fallbackEpisodes = uniqueEpisodeItems(fallbackEpisodes)
          totalMs = int(loadClock.totalMilliseconds())
          fallbackMs = totalMs - fallbackStartMs
          print "EPISODE_SOURCE source=filestation-fallback count="; fallbackEpisodes.count(); " totalMs="; totalMs; " directMs="; directMs; " fallbackMs="; fallbackMs
          m.top.response = { success: true, items: fallbackEpisodes, total: fallbackEpisodes.count(), baseUrl: baseUrl, sid: sid }
          return
      end if

      detail = "No playable episode records after filtering." + chr(10) + "Title: " + showTitle + chr(10) + "Candidates: " + stri(candidates.count()).trim() + chr(10) + "Last URL: " + left(lastUrl, 600)
      if lastResult <> invalid then detail = detail + chr(10) + "Last response: " + left(lastResult, 900)
      m.top.response = { success: true, items: [], total: 0, baseUrl: baseUrl, sid: sid, detail: detail }
  end sub

  sub latestResume(req as object)
      filePath = ""
      if req.filePath <> invalid then filePath = idToStr(req.filePath)
      m.top.response = { success: true, action: "latestResume", position: 0, filePath: filePath }
  end sub

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
          if fileList = invalid then fileList = additional.lookUp("files")
          if fileList <> invalid and fileList.count() > 0
              f = fileList[0]
              p = f.lookUp("path")
              if p = invalid then p = f.lookUp("sharepath")
              fid = f.lookUp("id")
              if p <> invalid then return { path: p, id: idToStr(fid) }
          end if
      end if

      ' Layout B: file[] directly on movie
      fileList = movie.lookUp("file")
      if fileList = invalid then fileList = movie.lookUp("files")
      if fileList <> invalid
          if type(fileList) = "roArray" and fileList.count() > 0
              f = fileList[0]
              p = f.lookUp("path")
              if p = invalid then p = f.lookUp("sharepath")
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

  sub movieMetadata(req as object)
      baseUrl = req.baseUrl
      sid = req.sid
      token = ""
      if req.synoToken <> invalid then token = req.synoToken
      videoId = idToStr(req.id)
      title = ""
      if req.title <> invalid then title = req.title
      filePath = ""
      if req.filePath <> invalid then filePath = req.filePath
      originalAvailable = ""
      if req.originalAvailable <> invalid then originalAvailable = idToStr(req.originalAvailable)
      if videoId = "" or videoId = "0"
          m.top.response = { success: false, error: "missing movie id", summary: "" }
          return
      end if

      candidates = []
      if req.ids <> invalid
          for each candidate in req.ids
              pushUniqueString(candidates, candidate)
          end for
      end if
      pushUniqueString(candidates, videoId)

      summary = ""
      rating = 0
      releaseDate = ""
      source = "synology2"
      usedId = videoId
      fallbackSummary = ""
      for each candidateId in candidates
          metadata = movieMetadataV2(baseUrl, sid, token, candidateId)
          if fallbackSummary = "" and metadata.summary <> "" then fallbackSummary = metadata.summary
          if metadata.rating > rating then rating = metadata.rating
          if releaseDate = "" and metadata.releaseDate <> invalid and metadata.releaseDate <> "" then releaseDate = metadata.releaseDate
          if metadata.summary <> "" and metadata.rating > 0
              summary = metadata.summary
              source = "synology2"
              usedId = candidateId
              exit for
          end if
      end for
      if summary = "" then summary = fallbackSummary
      if summary = "" or rating <= 0
          for each candidateId in candidates
              metadata = movieMetadataV1(baseUrl, sid, candidateId)
              if summary = "" and metadata.summary <> ""
                  summary = metadata.summary
                  source = "synology1"
                  usedId = candidateId
              end if
              if metadata.rating > rating then rating = metadata.rating
              if releaseDate = "" and metadata.releaseDate <> invalid and metadata.releaseDate <> "" then releaseDate = metadata.releaseDate
              if summary <> "" and rating > 0 then exit for
          end for
      end if
      if filePath = ""
          resolved = resolveMovieFilePathForMetadata(baseUrl, sid, token, videoId, candidates, title, releaseDate, originalAvailable)
          if resolved.path <> ""
              filePath = resolved.path
              print "MOVIE_METADATA_PATH source="; resolved.source; " path="; filePath
          else
              print "MOVIE_METADATA_PATH missing title="; title; " id="; videoId
          end if
      end if
      if (summary = "" or rating <= 0 or releaseDate = "") and filePath <> ""
          vsmeta = fetchVsmetaMetadata(baseUrl, sid, token, filePath, title)
          if summary = "" and vsmeta.summary <> "" then summary = vsmeta.summary
          if rating <= 0 and vsmeta.rating > 0 then rating = vsmeta.rating
          if releaseDate = "" and vsmeta.releaseDate <> "" then releaseDate = vsmeta.releaseDate
          if vsmeta.summary <> "" or vsmeta.rating > 0 or vsmeta.releaseDate <> ""
              source = "vsmeta"
              usedId = videoId
          end if
      end if
      if summary <> "" and title <> "" and lcase(summary.trim()) = lcase(title.trim()) then summary = ""
      print "MOVIE_METADATA id="; videoId; " used="; usedId; " source="; source; " summaryLen="; len(summary); " rating="; rating; " releaseDate="; releaseDate
      m.top.response = { success: summary <> "" or rating > 0 or releaseDate <> "", summary: summary, rating: rating, releaseDate: releaseDate, id: videoId, usedId: usedId, source: source }
  end sub

  function resolveMovieFilePathForMetadata(baseUrl as string, sid as string, token as string, videoId as string, candidates as object, title as string, releaseDate as string, originalAvailable as string) as object
      year = yearFromString(releaseDate)
      if year = "" then year = yearFromString(originalAvailable)
      if year <> "" and title <> ""
          guessedBase = "/video/Movies/" + title + " (" + year + ")"
          guessedPath = findExistingMoviePath(baseUrl, sid, guessedBase)
          if guessedPath <> "" then return { path: guessedPath, source: "guess-year" }
      end if
      for each candidateId in candidates
          if candidateId <> "" and candidateId <> "0"
              fileInfoV2 = getFileInfoV2(baseUrl, sid, token, candidateId, "movie")
              if fileInfoV2.path <> invalid and fileInfoV2.path <> "" then return { path: fileInfoV2.path, source: "v2:" + candidateId }
          end if
      end for
      for each candidateId in candidates
          if candidateId <> "" and candidateId <> "0"
              fileInfo = getFilePathV1(baseUrl, candidateId, "", sid)
              if fileInfo.path <> invalid and fileInfo.path <> "" then return { path: fileInfo.path, source: "v1:" + candidateId }
          end if
      end for
      if title <> ""
          guessedPath = findMovieByFolderPrefix(baseUrl, sid, title)
          if guessedPath <> "" then return { path: guessedPath, source: "guess-prefix" }
      end if
      return { path: "", source: "" }
  end function

  function movieMetadataSummaryV2(baseUrl as string, sid as string, token as string, videoId as string) as string
      metadata = movieMetadataV2(baseUrl, sid, token, videoId)
      return metadata.summary
  end function

  function movieMetadataV2(baseUrl as string, sid as string, token as string, videoId as string) as object
      apiName = "SYNO.VideoStation2.Movie"
      url = apiEndpoint(baseUrl, apiName, "entry.cgi", sid, token)
      enc = createObject("roUrlTransfer")
      addlForms = [
          "%5B%22summary%22,%22extra%22,%22file%22,%22watched_ratio%22,%22rating%22,%22poster_mtime%22,%22backdrop_mtime%22%5D",
          "%5B%22summary%22,%22extra%22,%22rating%22%5D",
          "%5B%22summary%22,%22rating%22%5D"
      ]
      idForms = [
          "%5B%22" + enc.escape(videoId) + "%22%5D",
          "%5B" + enc.escape(videoId) + "%5D",
          enc.escape(videoId)
      ]
      best = { summary: "", rating: 0, releaseDate: "" }
      for each idForm in idForms
          for each additional in addlForms
              body = "api=" + enc.escape(apiName) + "&version=1&method=getinfo&id=" + idForm + "&additional=" + additional
              r = httpPostForm(url, body)
              if r <> invalid and r <> ""
                  j = parseJSON(r)
                  if j <> invalid and j.success = true and j.data <> invalid
                      item = firstV2InfoItem(j.data, "movie")
                      if item <> invalid
                          summary = movieSummaryText(item)
                          rating = detailStateRating(item)
                          releaseDate = movieReleaseDateText(item)
                          if best.summary = "" and summary <> "" then best.summary = summary
                          if rating > best.rating then best.rating = rating
                          if best.releaseDate = "" and releaseDate <> "" then best.releaseDate = releaseDate
                          if summary <> "" or rating > 0 or releaseDate <> "" then return { summary: summary, rating: rating, releaseDate: releaseDate }
                      end if
                  end if
              end if
          end for
      end for
      return best
  end function

  function movieMetadataSummaryV1(baseUrl as string, sid as string, videoId as string) as string
      metadata = movieMetadataV1(baseUrl, sid, videoId)
      return metadata.summary
  end function

  function movieMetadataV1(baseUrl as string, sid as string, videoId as string) as object
      addlFormats = ["additional=%5B%22summary%22,%22extra%22,%22file%22,%22watched_ratio%22,%22rating%22%5D", "additional=%5B%22summary%22,%22extra%22,%22rating%22%5D", "additional=summary", "additional=%22summary%22"]
      for each addl in addlFormats
          url = baseUrl + "/webapi/VideoStation/movie.cgi?api=SYNO.VideoStation.Movie&version=1&method=getinfo&id=" + videoId + "&" + addl + "&_sid=" + sid
          r = httpGet(url)
          if r <> invalid and r <> ""
              j = parseJSON(r)
              if j <> invalid and j.success = true and j.data <> invalid
                  movies = j.data.lookUp("movies")
                  if movies = invalid then movies = j.data.lookUp("movie")
                  if movies <> invalid
                      if type(movies) = "roArray" and movies.count() > 0
                          summary = movieSummaryText(movies[0])
                          rating = detailStateRating(movies[0])
                          releaseDate = movieReleaseDateText(movies[0])
                          if summary <> "" or rating > 0 or releaseDate <> "" then return { summary: summary, rating: rating, releaseDate: releaseDate }
                      else if type(movies) = "roAssociativeArray"
                          summary = movieSummaryText(movies)
                          rating = detailStateRating(movies)
                          releaseDate = movieReleaseDateText(movies)
                          if summary <> "" or rating > 0 or releaseDate <> "" then return { summary: summary, rating: rating, releaseDate: releaseDate }
                      end if
                  end if
              end if
          end if
      end for
      return { summary: "", rating: 0, releaseDate: "" }
  end function

  function getFileInfoV2(baseUrl as string, sid as string, token as string, videoId as string, mediaType as string) as object
      apiName = v2InfoApiForMediaType(mediaType)
      url = apiEndpoint(baseUrl, apiName, "entry.cgi", sid, token)
      enc = createObject("roUrlTransfer")
      addlFormats = [
          "%5B%22file%22%5D",
          "%5B%22summary%22,%22file%22,%22watched_ratio%22%5D",
          "%5B%22extra%22,%22summary%22,%22file%22,%22actor%22,%22writer%22,%22director%22,%22genre%22,%22collection%22,%22watched_ratio%22,%22rating%22,%22conversion_produced%22,%22backdrop_mtime%22,%22poster_mtime%22%5D"
      ]
      idFormats = [
          "%5B" + enc.escape(videoId) + "%5D",
          "%5B%22" + enc.escape(videoId) + "%22%5D",
          enc.escape(videoId)
      ]

      print "V2_GETINFO api="; apiName; " id="; videoId
      lastRaw = ""
      for each idParam in idFormats
          for each additional in addlFormats
              body = "api=" + enc.escape(apiName) + "&version=1&method=getinfo&id=" + idParam + "&additional=" + additional
              r = httpPostForm(url, body)
              if r = invalid
                  lastRaw = "timeout"
              else
                  lastRaw = left(r, 260)
                  print "V2_GETINFO_RESP "; left(r, 500)
                  j = parseJSON(r)
                  if j <> invalid and j.success = true and j.data <> invalid
                      item = firstV2InfoItem(j.data, mediaType)
                      if item <> invalid
                          fi = extractRealFileInfo(item)
                          keysStr = ""
                          if fi.keys <> invalid and fi.keys <> "" then keysStr = " KEYS:" + fi.keys
                          if (fi.path <> invalid and fi.path <> "") or (fi.id <> invalid and idToStr(fi.id) <> "" and idToStr(fi.id) <> "0")
                              return { path: fi.path, id: fi.id, raw: "id=" + idParam + " addl=" + additional + " " + left(r, 180) + keysStr }
                          end if
                          lastRaw = "id=" + idParam + " addl=" + additional + " " + left(r, 180) + keysStr
                      end if
                  end if
              end if
          end for
      end for
      return { path: invalid, id: invalid, raw: lastRaw }
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

  function shouldTryFileStationDirectPath(path as string) as boolean
      lp = lcase(path)
      if right(lp, 5) = ".m3u8" then return true
      if right(lp, 4) = ".mkv" then return true
      if right(lp, 4) = ".mp4" then return true
      if right(lp, 4) = ".m4v" then return true
      if right(lp, 4) = ".mov" then return true
      return false
  end function

  function isRokuDirectPlayablePath(path as string) as boolean
      return shouldTryFileStationDirectPath(path)
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

  function vteRelayStreamUrl(baseUrl as string, proxyBaseUrl as dynamic, sid as string, token as string, fileId as string) as string
      enc = createObject("roUrlTransfer")
      url = ffmpegProxyBaseUrl(baseUrl, proxyBaseUrl) + "/vte-relay?base=" + enc.escape(localVideoBaseUrl(baseUrl)) + "&sid=" + enc.escape(sid) + "&file_id=" + enc.escape(fileId) + "&profile=sd_high&audio_track=-1"
      if token <> "" then url = url + "&token=" + enc.escape(token)
      return url
  end function

  function vtePlaylistStreamUrl(baseUrl as string, proxyBaseUrl as dynamic, sid as string, token as string, fileId as string) as string
      enc = createObject("roUrlTransfer")
      url = ffmpegProxyBaseUrl(baseUrl, proxyBaseUrl) + "/vte-playlist?base=" + enc.escape(localVideoBaseUrl(baseUrl)) + "&sid=" + enc.escape(sid) + "&file_id=" + enc.escape(fileId) + "&profile=sd_high&audio_track=-1"
      if token <> "" then url = url + "&token=" + enc.escape(token)
      return url
  end function

  function rokuVteWrapperStreamUrl(baseUrl as string, sid as string, token as string, fileId as string, resumePosition as integer) as string
      enc = createObject("roUrlTransfer")
      url = localVideoBaseUrl(baseUrl) + "/webapi/VideoStation/rokuvte.cgi?sid=" + enc.escape(sid) + "&file_id=" + enc.escape(fileId) + "&profile=sd_high&audio_track=-1"
      if resumePosition > 0
          url = url + "&resume=" + stri(resumePosition).trim()
      else
          url = url + "&start_over=1"
      end if
      if token <> "" then url = url + "&token=" + enc.escape(token)
      return url
  end function

  function vteDirectStreamOpen(baseUrl as string, sid as string, token as string, fileId as string) as dynamic
      enc = createObject("roUrlTransfer")
      url = apiEndpoint(localVideoBaseUrl(baseUrl), "SYNO.VideoStation2.Streaming", "entry.cgi", sid, token)
      hlsParam = "{""force_open_vte"":false,""profile"":""sd_high"",""audio_track"":-1}"
      fileParam = "{""id"":" + fileId + ",""path"":""""}"
      body = "api=SYNO.VideoStation2.Streaming&version=1&method=open&hls=" + enc.escape(hlsParam) + "&file=" + enc.escape(fileParam)
      print "VTE_DIRECT_OPEN fileId="; fileId
      result = httpPostForm(url, body)
      if result = invalid or result = "" then
          print "VTE_DIRECT_OPEN_RESP empty"
          return invalid
      end if
      print "VTE_DIRECT_OPEN_RESP "; left(result, 300)
      json = parseJSON(result)
      if json = invalid or json.success <> true then return invalid
      streamId = streamIdFromResponse(json)
      if streamId = "" then return invalid
      fmt = "hls"
      if json.data <> invalid
          responseFmt = json.data.lookUp("format")
          if responseFmt <> invalid and responseFmt <> "" then fmt = responseFmt
      end if
      streamUrl = apiUrl(localVideoBaseUrl(baseUrl), "SYNO.VideoStation2.Streaming", "entry.cgi", "1", "stream", "stream_id=" + streamId + "&format=" + fmt, sid, token)
      cookie = "id=" + sid
      if token <> "" then cookie = cookie + "; SynoToken=" + token
      headers = { Cookie: cookie }
      if token <> "" then headers.addReplace("X-SYNO-TOKEN", token)
      return { streamUrl: streamUrl, headers: headers, streamId: streamId, format: fmt }
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

  function fileStationSidecarPosterPath(videoPath as string) as string
      if videoPath = "" then return ""
      lastSlash = 0
      idx = 1
      while idx <= len(videoPath)
          if mid(videoPath, idx, 1) = "/" then lastSlash = idx
          idx = idx + 1
      end while
      if lastSlash <= 0 or lastSlash >= len(videoPath) then return ""
      dirPath = left(videoPath, lastSlash - 1)
      fileName = mid(videoPath, lastSlash + 1)
      return dirPath + "/@eaDir/" + fileName + "/SYNOVIDEO_VIDEO_POSTER.jpg"
  end function

  sub addFileStationSidecarPosterUrls(items as object, baseUrl as string, sid as string, token as string)
      if items = invalid then return
      for each item in items
          savedPoster = idToStr(item.lookUp("posterUrl"))
          if savedPoster = "" or savedPoster = "0"
              fileInfo = itemFileInfo(item)
              sidecarPath = fileStationSidecarPosterPath(fileInfo.path)
              if sidecarPath <> ""
                  item.addReplace("posterUrl", fileStationStreamUrl(baseUrl, sid, token, sidecarPath))
              end if
          end if
      end for
  end sub

  function ffmpegProxyBaseUrl(baseUrl as string, proxyBaseUrl as dynamic) as string
      if proxyBaseUrl <> invalid and proxyBaseUrl <> "" then return proxyBaseUrl
      return ""
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

  sub appendCustomLibraries(items as object, custom as object)
      for each lib in custom
          t = idToStr(lib.lookUp("type"))
          category = categoryForLibraryType(t)
          if category <> ""
              title = idToStr(lib.lookUp("title"))
              if title = "" or title = "0" then title = idToStr(lib.lookUp("name"))
              id = idToStr(lib.lookUp("id"))
              if id = "" or id = "0" then id = idToStr(lib.lookUp("library_id"))
              if title <> "" and title <> "0" and id <> "" and id <> "0"
                  items.push({ title: title, category: category, libraryId: id, desc: "Browse " + title })
              end if
          end if
      end for
  end sub

  function fetchDirectLibraries(baseUrl as string, sid as string, token as string) as object
      items = fetchDirectLibraryList(baseUrl, sid, token, "SYNO.VideoStation2.Library", "list", "synology2-library")
      if items.count() > 0 then return items
      items = fetchDirectLibraryList(baseUrl, sid, token, "SYNO.VideoStation2.AcrossLibrary", "list_library", "synology2-across")
      if items.count() > 0 then return items
      items = fetchDirectLibraryList(baseUrl, sid, token, "SYNO.VideoStation.Library", "list", "synology1-library")
      if items.count() > 0 then return items
      return fetchDirectLibraryList(baseUrl, sid, token, "SYNO.VideoStation.AcrossLibrary", "list_library", "synology1-across")
  end function

  function fetchDirectLibraryList(baseUrl as string, sid as string, token as string, apiName as string, methodName as string, label as string) as object
      if baseUrl = invalid or baseUrl = "" then return []
      url = apiUrl(baseUrl, apiName, "entry.cgi", "1", methodName, "", sid, token)
      result = httpGet(url)
      items = libraryItemsFromResult(result)
      print "LIBRARY_DIRECT_ATTEMPT source="; label; " count="; items.count()
      return items
  end function

  function libraryItemsFromResult(result as dynamic) as object
      if result = invalid or result = "" then return []
      json = parseJSON(result)
      if json = invalid or json.success <> true then return []
      if json.data = invalid then return []
      dataType = type(json.data)
      if dataType = "roArray" then return normalizeLibraryItems(json.data)
      if dataType <> "roAssociativeArray" then return []

      for each key in ["library", "libraries", "items", "list"]
          value = json.data.lookUp(key)
          if value <> invalid and type(value) = "roArray" then return normalizeLibraryItems(value)
      end for
      return []
  end function

  function normalizeLibraryItems(items as object) as object
      normalized = []
      for each item in items
          if item <> invalid and type(item) = "roAssociativeArray"
              title = idToStr(item.lookUp("title"))
              if title = "" or title = "0" then title = idToStr(item.lookUp("name"))
              id = idToStr(item.lookUp("id"))
              if id = "" or id = "0" then id = idToStr(item.lookUp("library_id"))
              t = idToStr(item.lookUp("type"))
              if t = "" or t = "0" then t = idToStr(item.lookUp("library_type"))
              if title <> "" and title <> "0" and id <> "" and id <> "0" and categoryForLibraryType(t) <> ""
                  normalized.push({ id: id, title: title, type: t })
              end if
          end if
      end for
      return normalized
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

  function localVideoBaseUrl(baseUrl as string) as string
      return baseUrl
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

  function tryAndroidStyleStreamOpen(baseUrl as string, sid as string, token as string, candidateId as string, version as string, forceOpenVte as string, debugName as string, diag as object) as boolean
      enc = createObject("roUrlTransfer")
      acceptFormats = "hls, hls_remux, raw, mp4, ts, dash, webm"
      params = "id=" + candidateId + "&accept_format=" + enc.escape(acceptFormats)
      if forceOpenVte <> "" then params = params + "&force_open_vte=" + forceOpenVte
      params = params + "&audio_format=ac3_copy"

      openUrl = apiUrl(baseUrl, "SYNO.VideoStation.Streaming", "VideoStation/streaming.cgi", version, "open", params, sid, token)
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
      if j = invalid or j.success <> true then return false

      directUrl = invalid
      if j.data <> invalid then directUrl = j.data.lookUp("url")
      responseFmt = "hls"
      if j.data <> invalid
          f = j.data.lookUp("format")
          if f <> invalid and f <> "" then responseFmt = lcase(idToStr(f))
      end if

      streamFormat = "hls"
      if responseFmt = "raw" or responseFmt = "mp4" then streamFormat = "mp4"
      if responseFmt = "dash" or responseFmt = "webm" then return false

      if directUrl <> invalid and directUrl <> ""
          return respondWithCandidate(directUrl, streamFormat, debugName + " url fmt=" + responseFmt, diag)
      end if

      streamId = streamIdFromResponse(j)
      if streamId <> ""
          streamUrl = apiUrl(baseUrl, "SYNO.VideoStation.Streaming", "VideoStation/streaming.cgi", "1", "stream", "id=" + streamId + "&format=" + responseFmt, sid, token)
          return respondWithCandidate(streamUrl, streamFormat, debugName + " stream=" + streamId + " fmt=" + responseFmt, diag)
      end if

      return false
  end function

  function tryAndroidExactStreamOpen(baseUrl as string, sid as string, token as string, candidateId as string, version as string, debugName as string, diag as object) as boolean
      enc = createObject("roUrlTransfer")
      params = "id=" + candidateId + "&accept_format=" + enc.escape("raw, mp4, ts, hls, hls_remux, dash, webm") + "&audio_format=ac3_copy"
      openUrl = apiUrl(baseUrl, "SYNO.VideoStation.Streaming", "VideoStation/streaming.cgi", version, "open", params, sid, token)
      streamBase = apiUrl(baseUrl, "SYNO.VideoStation.Streaming", "VideoStation/streaming.cgi", "1", "stream", "id=", "", token)
      return tryStreamOpen(openUrl, streamBase, sid, token, "hls", debugName, diag)
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
              streamUrl = apiUrl(localVideoBaseUrl(baseUrl), "SYNO.VideoStation2.Streaming", "entry.cgi", "1", "stream", "stream_id=" + streamId + "&format=" + responseFmt, sid, token)
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
              if t = "roInteger" or t = "Integer" or t = "roInt" or t = "roLongInteger" or t = "LongInteger" then return v
              if t = "roFloat" or t = "Float" or t = "roDouble" or t = "Double" then return int(v)
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
  function getFilePathV1(baseUrl as string, videoId as string, mapperId as string, sid as string) as object
      addlFormats = ["additional=%5B%22file%22%5D", "additional=file", "additional=files", "additional=%22file%22"]
      idCandidates = []
      pushUniqueString(idCandidates, videoId)
      pushUniqueString(idCandidates, mapperId)
      idParamNames = ["id", "video_id"]
      lastRaw = "not tried"
      for each idVal in idCandidates
      for each idParamName in idParamNames
      for each addl in addlFormats
          url = baseUrl + "/webapi/VideoStation/movie.cgi?api=SYNO.VideoStation.Movie&version=1&method=getinfo&" + idParamName + "=" + idVal + "&" + addl + "&_sid=" + sid
          print "V1_GETINFO "; idParamName; "="; idVal; " "; addl
          r = httpGet(url)
          if r = invalid then
              lastRaw = "[" + idParamName + "=" + idVal + " " + addl + "] timeout"
          else
              print "V1_GETINFO_RESP "; left(r, 500)
              j = parseJSON(r)
              if j <> invalid and j.success = true
                  movies = j.data.lookUp("movies")
                  if movies = invalid then movies = j.data.lookUp("movie")
                  if movies = invalid then movies = j.data.lookUp("videos")
                  if movies = invalid then movies = j.data.lookUp("video")
                  if movies <> invalid
                      movie = invalid
                      if type(movies) = "roArray" and movies.count() > 0
                          movie = movies[0]
                      else if type(movies) = "roAssociativeArray"
                          movie = movies
                      end if
                      if movie <> invalid
                          fi = extractFileInfoV1(movie)
                          keysStr = ""
                          if fi.lookUp("keys") <> invalid
                              keysStr = " KEYS:" + fi.lookUp("keys")
                          end if
                          lastRaw = "[" + idParamName + "=" + idVal + " " + addl + "] " + left(r, 200) + keysStr
                          if (fi.path <> invalid and fi.path <> "") or (fi.id <> invalid and fi.id <> "" and fi.id <> "0")
                              return { path: fi.path, id: fi.id, raw: lastRaw }
                          end if
                      end if
                  end if
              end if
              lastRaw = "[" + idParamName + "=" + idVal + " " + addl + "] " + left(r, 200)
          end if
      end for
      end for
      end for
      return { path: invalid, id: invalid, raw: lastRaw }
  end function

  sub getStreamUrl(req as object)
      beginCandidateSelection(req)
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
          fileInfo = getFilePathV1(baseUrl, videoId, mapperId, sid)
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
              guessedPath = findMovieByFolderPrefix(baseUrl, sid, videoTitle)
              if guessedPath <> "" then filePath = guessedPath
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

      if filePath = "" and videoTitle <> "" and mediaType <> "episode" and mediaType <> "tvshow_episode"
          foundPath = findMovieByFolderPrefix(baseUrl, sid, videoTitle)
          if foundPath = "" then foundPath = findMovieByTitle(baseUrl, sid, videoTitle)
          if foundPath <> ""
              filePath = foundPath
              diag.push("moviePathRecovered=" + filePath)
          end if
      end if

      ' Try the raw FileStation URL first. Direct MKV works on current Roku
      ' firmware, and this keeps short-title movies like "10" on the direct path.
      if shouldTryFileStationDirectPath(filePath)
          if respondWithFileStationStream(baseUrl, sid, token, filePath, diag) then return
      else if filePath <> ""
          diag.push("direct deferred for transcode:" + filePath)
      end if

      if filePath <> ""
          if shouldTryVideoStationTranscode(filePath)
              fsPath = fileStationPath(filePath)
              if fileId <> "" and fileId <> "0"
                  relaySid = sid
                  relayToken = token
                  refreshed = refreshVideoStationSession(baseUrl, req.username, req.password)
                  if refreshed <> invalid
                      relaySid = refreshed.sid
                      relayToken = refreshed.synoToken
                      print "VTE_RELAY_SESSION refreshed"
                  else
                      print "VTE_RELAY_SESSION using existing"
                  end if
                  if m.targetAttempt = 0
                      streamUrl = rokuVteWrapperStreamUrl(baseUrl, relaySid, relayToken, fileId, resumePosition)
                      print "ROKUVTE_WRAPPER_PLAY "; fsPath; " fileId="; fileId; " resume="; resumePosition
                      nativeHlsResume = resumePosition > 0
                      m.top.response = { success: true, streamUrl: streamUrl, streamFormat: "hls", isLive: false, subtitleUrl: fileStationSubtitleUrl(baseUrl, relaySid, relayToken, filePath), debugInfo: "Video Station RokuVTE wrapper " + left(fsPath, 120), directVte: true, nativeHlsResume: nativeHlsResume, resumePosition: resumePosition }
                      return
                  end if
                  m.top.response = { success: false, error: "Video Station wrapper playback failed.", detail: "Path: " + fsPath, attemptIndex: m.targetAttempt }
              else
                  m.top.response = { success: false, error: "Video Station wrapper needs a file id for this video.", detail: "Path: " + fsPath }
              end if
              return
          else
              m.top.response = { success: false, error: "This file needs transcoding. Direct Roku playback is disabled for this container while we stabilize MP4 playback.", detail: "Path: " + fileStationPath(filePath) + chr(10) + "Type: " + mediaType }
              return
          end if
      end if

      needsVideoStationTranscode = shouldTryVideoStationTranscode(filePath)
      legacyType = videoStationStreamType(mediaType)
      if filePath <> "" and not shouldTryFileStationDirectPath(filePath) and not needsVideoStationTranscode
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

      if not needsVideoStationTranscode
          ' ── B: Legacy streaming.cgi with the selected media type ──────────────
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

          streamBase = apiUrl(baseUrl, "SYNO.VideoStation2.Streaming", "entry.cgi", "1", "stream", "stream_id=", "", token)
          for each candidateVideoId in videoIds
              openUrl = apiUrl(baseUrl, "SYNO.VideoStation2.Streaming", "entry.cgi", "1", "open", "id=" + candidateVideoId + "&type=" + legacyType + "&accept_format=hls1080p", sid, token)
              if tryStreamOpen(openUrl, streamBase, sid, token, "hls", "v2/id-hls id=" + candidateVideoId, diag) then return
              openUrl = apiUrl(baseUrl, "SYNO.VideoStation2.Streaming", "entry.cgi", "1", "open", "id=" + candidateVideoId + "&type=" + legacyType + "&accept_format=raw", sid, token)
              if tryStreamOpen(openUrl, streamBase, sid, token, "mp4", "v2/id-raw id=" + candidateVideoId, diag) then return
          end for
      end if

      for each candidateFileId in fileIds
          diag.push(summarizeV2FileInfo(baseUrl, sid, token, candidateFileId))

          officialFile = "{""id"":" + candidateFileId + ",""path"":""""}"
          if not shouldTryVideoStationTranscode(filePath)
              for each fmt in ["hls_remux", "raw"]
                  if tryV2StreamPost(baseUrl, sid, token, officialFile, fmt, "", "", "v2post/" + fmt + " official=" + candidateFileId, diag) then return
              end for
          else
              if tryV2StreamPost(baseUrl, sid, token, officialFile, "hls_remux", "", "", "v2post/hls_remux official=" + candidateFileId, diag) then return
          end if
          for each audioTrack in ["-1", "0", "1", ""]
              for each profile in ["sd_medium", "sd_high", "hd_medium", "hd_high"]
                  labelTrack = audioTrack
                  if labelTrack = "" then labelTrack = "none"
                  if tryV2StreamPost(baseUrl, sid, token, officialFile, "hls", profile, audioTrack, "v2post/hls " + profile + " audio=" + labelTrack + " official=" + candidateFileId, diag) then return
              end for
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

      if shouldTryFileStationDirectPath(filePath)
          if respondWithFileStationStream(baseUrl, sid, token, filePath, diag) then return
      else if filePath <> ""
          diag.push("unsupported direct container:" + filePath)
          if shouldTryVideoStationTranscode(filePath)
              fsPath = fileStationPath(filePath)
              m.top.response = { success: false, error: "This file needs Video Station wrapper playback, but no wrapper candidate succeeded.", detail: "Path: " + fsPath }
              return
          end if
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

  sub normalizeMapperIdsForItems(items as object)
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
      skipCachedArtwork = false
      if m.skipCachedArtworkResolve <> invalid and m.skipCachedArtworkResolve = true then skipCachedArtwork = true
      if not skipCachedArtwork then normalizeMapperIdsForItems(items)
      normalizeBrowseSummaries(items)
      if m.flattenBrowseFileFields <> invalid and m.flattenBrowseFileFields = true then normalizeHomeVideoFields(items, baseUrl, sid)
      addDirectPosterIds(items)
      items = sortBrowseItems(items)
      if not skipCachedArtwork then resolveCachedArtworkForItems(items, 1500)
      total = 0
      if json.data.total <> invalid
        t = json.data.total
        if type(t) = "roInteger" or type(t) = "Integer" then total = t
        if type(t) = "roFloat" or type(t) = "Float" then total = int(t)
    end if
      m.top.response = { success: true, items: items, total: total, baseUrl: baseUrl, sid: sid }
  end sub

  sub normalizeHomeVideoFields(items as object, baseUrl as string, sid as string)
      if items = invalid then return
      token = ""
      if m.top.request <> invalid and m.top.request.synoToken <> invalid then token = m.top.request.synoToken
      fileMap = { byId: {}, byMapper: {}, byTitle: {}, rows: [], changed: false }
      dateMap = homeVideoDateMap(baseUrl, sid, token)
      missing = []
      for each item in items
          additional = item.lookUp("additional")
          if additional <> invalid
              flattenBrowseTextField(item, additional, "record_time")
              flattenBrowseTextField(item, additional, "record_time_utc")
              flattenBrowseTextField(item, additional, "originally_available")
              flattenBrowseTextField(item, additional, "date")
              flattenBrowseTextField(item, additional, "create_time")
              extraValue = additional.lookUp("extra")
              flattenHomeVideoExtraDateFields(item, extraValue)
              fileValue = additional.lookUp("file")
              flattenBrowseFileField(item, fileValue)
              filesValue = additional.lookUp("files")
              flattenBrowseFileField(item, filesValue)
          end if
          fileValue = item.lookUp("file")
          flattenBrowseFileField(item, fileValue)
          filesValue = item.lookUp("files")
          flattenBrowseFileField(item, filesValue)
          applyHomeVideoFilenameMap(item, fileMap)
          applyHomeVideoDateMap(item, dateMap)
          path = idToStr(item.lookUp("path"))
          if path = "" or path = "0" then path = idToStr(item.lookUp("filePath"))
          if path <> "" and path <> "0"
              mergeHomeVideoFilenameMapEntry(fileMap, item, path)
          else
              missing.push(item)
          end if
      end for
      resolved = 0
      ' Keep Home Video browsing fast: never rebuild or upload the cache while the grid is loading.
      ' Missing entries simply fall back to dates already present in the list item.
      if resolved > 0 then print "HOMEVIDEO_FILENAME_CACHE resolvedNew="; resolved
  end sub

  function homeVideoDateMap(baseUrl as string, sid as string, token as string) as object
      maps = { byId: {}, byMapper: {}, byTitle: {} }
      if baseUrl = invalid or baseUrl = "" or sid = invalid or sid = "" then return maps
      raw = httpGet(fileStationStreamUrl(baseUrl, sid, token, "/video/Home/roku-home-video-dates.json"))
      if raw = invalid or raw = "" then return maps
      rows = parseJSON(raw)
      if rows = invalid or type(rows) <> "roArray" then return maps
      for each row in rows
          if row <> invalid and type(row) = "roAssociativeArray"
              entry = {
                  date: idToStr(row.lookUp("date")),
                  title: idToStr(row.lookUp("title"))
              }
              if entry.date <> "" and entry.date <> "0"
                  id = idToStr(row.lookUp("id"))
                  if id <> "" and id <> "0" then maps.byId.addReplace(id, entry)
                  mapper = idToStr(row.lookUp("mapper_id"))
                  if mapper = "" or mapper = "0" then mapper = idToStr(row.lookUp("mapperId"))
                  if mapper <> "" and mapper <> "0" then maps.byMapper.addReplace(mapper, entry)
                  title = idToStr(row.lookUp("title"))
                  if title <> "" and title <> "0" then maps.byTitle.addReplace(normalizedTitleKey(title), entry)
                  rawTitle = idToStr(row.lookUp("rawTitle"))
                  if rawTitle <> "" and rawTitle <> "0" then maps.byTitle.addReplace(normalizedTitleKey(rawTitle), entry)
              end if
          end if
      end for
      print "HOMEVIDEO_DATE_MAP count="; rows.count()
      return maps
  end function

  sub applyHomeVideoDateMap(item as object, dateMap as object)
      if item = invalid or dateMap = invalid then return
      entry = invalid
      id = idToStr(item.lookUp("id"))
      if id <> "" and id <> "0" then entry = dateMap.byId.lookUp(id)
      if entry = invalid
          mapper = idToStr(item.lookUp("mapper_id"))
          if mapper = "" or mapper = "0" then mapper = idToStr(item.lookUp("mapperId"))
          if mapper <> "" and mapper <> "0" then entry = dateMap.byMapper.lookUp(mapper)
      end if
      if entry = invalid
          title = idToStr(item.lookUp("title"))
          if title = "" or title = "0" then title = idToStr(item.lookUp("name"))
          if title <> "" and title <> "0" then entry = dateMap.byTitle.lookUp(normalizedTitleKey(title))
      end if
      if entry = invalid then return
      dateText = idToStr(entry.lookUp("date"))
      if dateText <> "" and dateText <> "0"
          item.addReplace("rokuDate", dateText)
          item.addReplace("originalAvailable", dateText)
          item.addReplace("original_available", dateText)
      end if
      displayTitle = idToStr(entry.lookUp("title"))
      if displayTitle <> "" and displayTitle <> "0" then item.addReplace("rokuDisplayTitle", displayTitle)
  end sub

  sub flattenHomeVideoExtraDateFields(item as object, value as dynamic)
      if item = invalid or value = invalid then return
      extraObj = invalid
      valueType = type(value)
      if valueType = "roAssociativeArray"
          extraObj = value
      else if valueType = "roString" or valueType = "String"
          extraObj = parseJSON(value)
      end if
      if extraObj = invalid or type(extraObj) <> "roAssociativeArray" then return
      flattenBrowseTextField(item, extraObj, "record_time")
      flattenBrowseTextField(item, extraObj, "record_time_utc")
      flattenBrowseTextField(item, extraObj, "originally_available")
      flattenBrowseTextField(item, extraObj, "date")
      flattenBrowseTextField(item, extraObj, "create_time")
  end sub

  function homeVideoFilenameMap(baseUrl as string, sid as string, token as string) as object
      maps = { byId: {}, byMapper: {}, byTitle: {}, rows: [], changed: false }
      raw = homeVideoFilenameRegistryCache()
      if raw = "" then return maps
      rows = parseJSON(raw)
      if rows = invalid or type(rows) <> "roArray" then return maps

      for each row in rows
          if row <> invalid and type(row) = "roAssociativeArray"
              path = idToStr(row.lookUp("path"))
              if path <> "" and path <> "0"
                  entry = { path: path, row: row }
                  id = idToStr(row.lookUp("id"))
                  if id <> "" and id <> "0" then maps.byId.addReplace(id, entry)
                  mapper = idToStr(row.lookUp("mapper_id"))
                  if mapper = "" or mapper = "0" then mapper = idToStr(row.lookUp("mapperId"))
                  if mapper <> "" and mapper <> "0" then maps.byMapper.addReplace(mapper, entry)
                  title = idToStr(row.lookUp("title"))
                  if title <> "" and title <> "0"
                      key = normalizedTitleKey(title)
                      if key <> "" and maps.byTitle.lookUp(key) = invalid then maps.byTitle.addReplace(key, entry)
                  end if
                  maps.rows.push(row)
              end if
          end if
      end for
      print "HOMEVIDEO_FILENAME_MAP count="; rows.count()
      return maps
  end function

  function homeVideoFilenameRegistryCache() as string
      reg = createObject("roRegistrySection", "DSVideoHomeVideo")
      if reg.exists("filenameMapChunks")
          count = val(reg.read("filenameMapChunks"))
          raw = ""
          i = 0
          while i < count
              key = "filenameMap" + stri(i).trim()
              if reg.exists(key) then raw = raw + reg.read(key)
              i = i + 1
          end while
          if raw <> "" then return raw
      end if
      if reg.exists("filenameMap") then return reg.read("filenameMap")
      return ""
  end function

  sub writeHomeVideoFilenameRegistryCache(raw as string)
      reg = createObject("roRegistrySection", "DSVideoHomeVideo")
      chunkSize = 900
      total = len(raw)
      count = int((total + chunkSize - 1) / chunkSize)
      i = 0
      while i < count
          start = i * chunkSize + 1
          chunk = mid(raw, start, chunkSize)
          reg.write("filenameMap" + stri(i).trim(), chunk)
          i = i + 1
      end while
      reg.write("filenameMapChunks", stri(count).trim())
      reg.flush()
  end sub

  sub refreshHomeVideoFilenameCache(req as object)
      baseUrl = req.baseUrl
      sid = req.sid
      token = ""
      if req.synoToken <> invalid then token = req.synoToken
      if baseUrl = invalid or baseUrl = "" or sid = invalid or sid = ""
          m.top.response = { success: false, error: "Missing Synology session" }
          return
      end if
      raw = httpGet(fileStationStreamUrl(baseUrl, sid, token, "/video/Home/roku-home-video-files.json"))
      if raw = invalid or raw = ""
          m.top.response = { success: false, error: "No filename cache found" }
          return
      end if
      rows = parseJSON(raw)
      if rows = invalid or type(rows) <> "roArray"
          m.top.response = { success: false, error: "Invalid filename cache" }
          return
      end if
      fileMap = homeVideoFilenameMapFromRows(rows)
      patches = homeVideoFilenamePatchesForItems(req.items, fileMap)
      m.top.response = { success: true, changed: patches.count() > 0, count: rows.count(), patches: patches }
  end sub

  function homeVideoFilenameMapFromRows(rows as object) as object
      maps = { byId: {}, byMapper: {}, byTitle: {} }
      for each row in rows
          if row <> invalid and type(row) = "roAssociativeArray"
              path = idToStr(row.lookUp("path"))
              if path <> "" and path <> "0"
                  entry = { path: path }
                  id = idToStr(row.lookUp("id"))
                  if id <> "" and id <> "0" then maps.byId.addReplace(id, entry)
                  mapper = idToStr(row.lookUp("mapper_id"))
                  if mapper = "" or mapper = "0" then mapper = idToStr(row.lookUp("mapperId"))
                  if mapper <> "" and mapper <> "0" then maps.byMapper.addReplace(mapper, entry)
                  title = idToStr(row.lookUp("title"))
                  if title <> "" and title <> "0"
                      key = normalizedTitleKey(title)
                      if key <> "" and maps.byTitle.lookUp(key) = invalid then maps.byTitle.addReplace(key, entry)
                  end if
              end if
          end if
      end for
      return maps
  end function

  function homeVideoFilenamePatchesForItems(items as dynamic, fileMap as object) as object
      patches = []
      if items = invalid or type(items) <> "roArray" then return patches
      for each item in items
          if item <> invalid and type(item) = "roAssociativeArray"
              entry = invalid
              id = idToStr(item.lookUp("id"))
              if id <> "" and id <> "0" then entry = fileMap.byId.lookUp(id)
              if entry = invalid
                  mapper = idToStr(item.lookUp("mapper_id"))
                  if mapper = "" or mapper = "0" then mapper = idToStr(item.lookUp("mapperId"))
                  if mapper <> "" and mapper <> "0" then entry = fileMap.byMapper.lookUp(mapper)
              end if
              if entry = invalid
                  title = idToStr(item.lookUp("title"))
                  if title <> "" and title <> "0" then entry = fileMap.byTitle.lookUp(normalizedTitleKey(title))
              end if
              if entry <> invalid
                  path = idToStr(entry.lookUp("path"))
                  if path <> "" and path <> "0"
                      patches.push({ index: item.lookUp("index"), path: path })
                  end if
              end if
          end if
      end for
      return patches
  end function

  sub applyHomeVideoFilenameMap(item as object, fileMap as object)
      if item = invalid or fileMap = invalid then return
      existingPath = idToStr(item.lookUp("path"))
      if existingPath = "" or existingPath = "0" then existingPath = idToStr(item.lookUp("filePath"))
      if existingPath <> "" and existingPath <> "0" then return

      entry = invalid
      id = idToStr(item.lookUp("id"))
      if id <> "" and id <> "0" then entry = fileMap.byId.lookUp(id)
      if entry = invalid
          mapper = idToStr(item.lookUp("mapper_id"))
          if mapper = "" or mapper = "0" then mapper = idToStr(item.lookUp("mapperId"))
          if mapper <> "" and mapper <> "0" then entry = fileMap.byMapper.lookUp(mapper)
      end if
      if entry = invalid
          title = idToStr(item.lookUp("title"))
          if title = "" or title = "0" then title = idToStr(item.lookUp("name"))
          if title <> "" and title <> "0" then entry = fileMap.byTitle.lookUp(normalizedTitleKey(title))
      end if
      if entry = invalid then return

      path = idToStr(entry.lookUp("path"))
      if path = "" or path = "0" then return
      item.addReplace("path", path)
      item.addReplace("filePath", path)
      item.addReplace("file_name", baseName(path))
  end sub

  function resolveMissingHomeVideoFilenames(items as object, fileMap as object, baseUrl as string, sid as string, token as string) as integer
      if items = invalid or fileMap = invalid then return 0
      resolved = 0
      attempts = 0
      maxAttempts = 4
      for each item in items
          if attempts >= maxAttempts then exit for
          title = idToStr(item.lookUp("title"))
          if title = "" or title = "0" then title = idToStr(item.lookUp("name"))
          if title <> "" and title <> "0"
              attempts = attempts + 1
              path = findHomeVideoPathByTitle(baseUrl, sid, token, title)
              if path <> "" and path <> "0"
                  item.addReplace("path", path)
                  item.addReplace("filePath", path)
                  item.addReplace("file_name", baseName(path))
                  mergeHomeVideoFilenameMapEntry(fileMap, item, path)
                  resolved = resolved + 1
              end if
          end if
      end for
      if items.count() > maxAttempts
          print "HOMEVIDEO_FILENAME_CACHE missingDeferred="; items.count() - maxAttempts
      end if
      return resolved
  end function

  sub mergeHomeVideoFilenameMapEntry(fileMap as object, item as object, path as string)
      if fileMap = invalid or item = invalid or path = "" or path = "0" then return
      id = idToStr(item.lookUp("id"))
      mapper = idToStr(item.lookUp("mapper_id"))
      if mapper = "" or mapper = "0" then mapper = idToStr(item.lookUp("mapperId"))
      title = idToStr(item.lookUp("title"))
      if title = "" or title = "0" then title = idToStr(item.lookUp("name"))

      entry = invalid
      if id <> "" and id <> "0" then entry = fileMap.byId.lookUp(id)
      if entry = invalid and mapper <> "" and mapper <> "0" then entry = fileMap.byMapper.lookUp(mapper)
      if entry = invalid and title <> "" and title <> "0" then entry = fileMap.byTitle.lookUp(normalizedTitleKey(title))

      if entry <> invalid
          oldPath = idToStr(entry.lookUp("path"))
          if oldPath = path then return
          row = entry.lookUp("row")
          if row <> invalid
              row.addReplace("path", path)
              entry.addReplace("path", path)
              fileMap.changed = true
          end if
          return
      end if

      row = { path: path }
      if id <> "" and id <> "0" then row.addReplace("id", id)
      if mapper <> "" and mapper <> "0" then row.addReplace("mapper_id", mapper)
      if title <> "" and title <> "0" then row.addReplace("title", title)
      entry = { path: path, row: row }
      if id <> "" and id <> "0" then fileMap.byId.addReplace(id, entry)
      if mapper <> "" and mapper <> "0" then fileMap.byMapper.addReplace(mapper, entry)
      if title <> "" and title <> "0"
          key = normalizedTitleKey(title)
          if key <> "" and fileMap.byTitle.lookUp(key) = invalid then fileMap.byTitle.addReplace(key, entry)
      end if
      fileMap.rows.push(row)
      fileMap.changed = true
  end sub

  sub saveHomeVideoFilenameMap(fileMap as object, baseUrl as string, sid as string, token as string)
      if fileMap = invalid or baseUrl = "" or sid = "" then return
      json = homeVideoFilenameMapJson(fileMap)
      if json = "" then return
      ok = uploadTextFileToFileStation(baseUrl, sid, token, "/video/Home", "roku-home-video-files.json", json)
      if ok
          fileMap.changed = false
          print "HOMEVIDEO_FILENAME_CACHE saved count="; fileMap.rows.count()
      else
          print "HOMEVIDEO_FILENAME_CACHE saveFailed"
      end if
  end sub

  function homeVideoFilenameMapJson(fileMap as object) as string
      if fileMap = invalid or fileMap.rows = invalid then return ""
      json = "["
      first = true
      for each row in fileMap.rows
          path = idToStr(row.lookUp("path"))
          if path <> "" and path <> "0"
              if not first then json = json + ","
              first = false
              json = json + "{"
              fieldFirst = true
              for each key in ["id", "mapper_id", "title", "path"]
                  value = idToStr(row.lookUp(key))
                  if value <> "" and value <> "0"
                      if not fieldFirst then json = json + ","
                      fieldFirst = false
                      json = json + chr(34) + key + chr(34) + ":" + chr(34) + jsonEscape(value) + chr(34)
                  end if
              end for
              json = json + "}"
          end if
      end for
      return json + "]"
  end function

  function uploadTextFileToFileStation(baseUrl as string, sid as string, token as string, folderPath as string, fileName as string, contents as string) as boolean
      enc = createObject("roUrlTransfer")
      url = apiEndpoint(baseUrl, "SYNO.FileStation.Upload", "entry.cgi", sid, token)
      boundary = "----RokuDsVideoBoundary"
      body = "--" + boundary + chr(13) + chr(10)
      body = body + "Content-Disposition: form-data; name=" + chr(34) + "api" + chr(34) + chr(13) + chr(10) + chr(13) + chr(10) + "SYNO.FileStation.Upload" + chr(13) + chr(10)
      body = body + "--" + boundary + chr(13) + chr(10)
      body = body + "Content-Disposition: form-data; name=" + chr(34) + "version" + chr(34) + chr(13) + chr(10) + chr(13) + chr(10) + "2" + chr(13) + chr(10)
      body = body + "--" + boundary + chr(13) + chr(10)
      body = body + "Content-Disposition: form-data; name=" + chr(34) + "method" + chr(34) + chr(13) + chr(10) + chr(13) + chr(10) + "upload" + chr(13) + chr(10)
      body = body + "--" + boundary + chr(13) + chr(10)
      body = body + "Content-Disposition: form-data; name=" + chr(34) + "path" + chr(34) + chr(13) + chr(10) + chr(13) + chr(10) + fileStationPath(folderPath) + chr(13) + chr(10)
      body = body + "--" + boundary + chr(13) + chr(10)
      body = body + "Content-Disposition: form-data; name=" + chr(34) + "create_parents" + chr(34) + chr(13) + chr(10) + chr(13) + chr(10) + "true" + chr(13) + chr(10)
      body = body + "--" + boundary + chr(13) + chr(10)
      body = body + "Content-Disposition: form-data; name=" + chr(34) + "overwrite" + chr(34) + chr(13) + chr(10) + chr(13) + chr(10) + "true" + chr(13) + chr(10)
      body = body + "--" + boundary + chr(13) + chr(10)
      body = body + "Content-Disposition: form-data; name=" + chr(34) + "file" + chr(34) + "; filename=" + chr(34) + fileName + chr(34) + chr(13) + chr(10)
      body = body + "Content-Type: application/json" + chr(13) + chr(10) + chr(13) + chr(10)
      body = body + contents + chr(13) + chr(10)
      body = body + "--" + boundary + "--" + chr(13) + chr(10)
      result = httpPostMultipart(url, body, boundary)
      if result = invalid or result = "" then return false
      parsed = parseJSON(result)
      if parsed <> invalid and parsed.success = true then return true
      return false
  end function

  function jsonEscape(value as string) as string
      out = ""
      i = 1
      while i <= len(value)
          ch = mid(value, i, 1)
          if ch = chr(34)
              out = out + "\" + chr(34)
          else if ch = "\"
              out = out + "\\"
          else if ch = chr(13) or ch = chr(10)
              out = out + " "
          else
              out = out + ch
          end if
          i = i + 1
      end while
      return out
  end function

  function findHomeVideoPathByTitle(baseUrl as string, sid as string, token as string, title as string) as string
      if title = "" then return ""
      direct = findMovieBySearch(baseUrl, sid, title, "/video/Home")
      if direct <> "" then return direct
      return findMovieInTree(baseUrl, sid, title, "/video/Home", 2)
  end function

  sub flattenBrowseTextField(item as object, source as object, key as string)
      value = source.lookUp(key)
      if value = invalid then return
      current = item.lookUp(key)
      if current = invalid
          item.addReplace(key, value)
          return
      end if
      currentType = type(current)
      if currentType = "roAssociativeArray" or currentType = "AssociativeArray" or currentType = "roArray" or currentType = "Array"
          item.addReplace(key, value)
          return
      end if
      currentText = idToStr(current)
      if currentText = "" or currentText = "0" then item.addReplace(key, value)
  end sub

  sub flattenBrowseFileField(item as object, value as dynamic)
      fileObj = invalid
      if value = invalid then return
      valueType = type(value)
      if valueType = "roArray"
          if value.count() > 0 then fileObj = value[0]
      else if valueType = "roAssociativeArray"
          fileObj = value
      end if
      if fileObj = invalid then return
      if item.lookUp("file_id") = invalid
          fid = fileObj.lookUp("id")
          if fid = invalid then fid = fileObj.lookUp("file_id")
          if fid <> invalid then item.addReplace("file_id", fid)
      end if
      path = fileObj.lookUp("path")
      if path = invalid then path = fileObj.lookUp("sharepath")
      if path = invalid then path = fileObj.lookUp("file_path")
      if path <> invalid
          if item.lookUp("path") = invalid then item.addReplace("path", path)
          if item.lookUp("filePath") = invalid then item.addReplace("filePath", path)
      end if
  end sub

  sub normalizeBrowseSummaries(items as object)
      if items = invalid then return
      for each item in items
          summary = episodeSummaryText(item)
          if summary <> ""
              item.addReplace("summary", summary)
              item.addReplace("description", summary)
          end if
          rating = detailStateRating(item)
          if rating > 0 then item.addReplace("rating", rating)
      end for
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

  function collectionTitleForKey(key as string) as string
      if key = "favorites" then return "syno_favorite"
      if key = "watchlist" then return "syno_watchlist"
      if key = "shared" then return "syno_default_shared"
      return ""
  end function

  function defaultRealCollectionIdForKey(key as string) as string
      if key = "watchlist" then return "4"
      if key = "favorites" then return "5"
      return ""
  end function

  function resolveCollectionId(baseUrl as string, sid as string, token as string, key as string, fallbackId as string) as string
      targetTitle = collectionTitleForKey(key)
      if targetTitle = "" then return fallbackId
      url = apiUrl(baseUrl, "SYNO.VideoStation.Collection", "VideoStation/collection.cgi", "3", "list", "offset=0&limit=500&sort_by=title&sort_direction=asc", sid, token)
      result = httpGet(url)
      if result = invalid or result = "" then return fallbackId
      json = parseJSON(result)
      if json = invalid or json.success <> true or json.data = invalid then return fallbackId
      dataKey = firstValidKey(result, ["collections", "collection", "playlists", "playlist"])
      if dataKey = "" then return fallbackId
      items = json.data.lookUp(dataKey)
      if items = invalid then return fallbackId
      for each item in items
          title = idToStr(item.lookUp("title"))
          if title = targetTitle
              id = idToStr(item.lookUp("id"))
              if id <> "" and id <> "0" and left(id, 1) <> "-" then return id
          end if
      end for
      return fallbackId
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

  function collectionVideoTypeCandidates(value as string) as object
      v = collectionVideoType(value)
      if v = "tvshow_episode" then return ["tvshow_episode", "episode"]
      if v = "home_video" then return ["home_video", "homevideo"]
      if v = "tv_record" then return ["tv_record", "tvrecord"]
      return [v]
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

  sub respondWithCollectionVideos(result as dynamic, baseUrl as string, sid as string, token as string)
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
      dateMap = homeVideoDateMap(baseUrl, sid, token)
      normalized = []
      for each item in items
          normalizeCollectionVideo(item, mediaType)
          if normalizedAppVideoType(idToStr(item.lookUp("type"))) = "homevideo" then applyHomeVideoDateMap(item, dateMap)
          enrichCollectionVideoMetadata(item, baseUrl, sid, token)
          normalized.push(item)
      end for
      normalized = uniqueCollectionVideos(normalized)
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

  function directEpisodeListResult(baseUrl as string, sid as string, token as string, candidateId as string, showTitle as string, libraryId as string) as object
      emptyResult = { episodes: [], metadata: [], result: invalid, url: "", source: "" }
      id = idToStr(candidateId)
      if id = "" or id = "0" then return emptyResult
      libraryParam = ""
      if libraryId <> "" and libraryId <> "0" then libraryParam = "&library_id=" + libraryId

      richAdditional = "%5B%22file%22,%22summary%22,%22extra%22,%22watched_ratio%22,%22file_watched%22,%22last_watched%22,%22rating%22,%22poster_mtime%22,%22backdrop_mtime%22,%22originally_available%22%5D"
      simpleAdditional = "%5B%22file%22,%22summary%22,%22watched_ratio%22,%22file_watched%22,%22last_watched%22,%22rating%22,%22originally_available%22%5D"
      attempts = [
          { api: "SYNO.VideoStation.TVShowEpisode", path: "VideoStation/tvshow_episode.cgi", version: "2", idParam: "tvshow_id", keys: ["episodes", "episode"] },
          { api: "SYNO.VideoStation2.TVShowEpisode", path: "entry.cgi", version: "2", idParam: "tvshow_id", keys: ["episode", "episodes"] },
          { api: "SYNO.VideoStation2.TVShowEpisode", path: "entry.cgi", version: "1", idParam: "tvshow_id", keys: ["episode", "episodes"] },
          { api: "SYNO.VideoStation.TVShowEpisode", path: "VideoStation/tvshow_episode.cgi", version: "1", idParam: "tvshow_id", keys: ["episodes", "episode"] },
          { api: "SYNO.VideoStation2.TVShowEpisode", path: "entry.cgi", version: "2", idParam: "id", keys: ["episode", "episodes"] },
          { api: "SYNO.VideoStation.TVShowEpisode", path: "VideoStation/tvshow_episode.cgi", version: "1", idParam: "id", keys: ["episodes", "episode"] },
          { api: "SYNO.VideoStation2.TVShowEpisode", path: "entry.cgi", version: "2", idParam: "", keys: ["episode", "episodes"] },
          { api: "SYNO.VideoStation.TVShowEpisode", path: "VideoStation/tvshow_episode.cgi", version: "1", idParam: "", keys: ["episodes", "episode"] }
      ]
      additionals = [richAdditional, simpleAdditional, ""]

      best = emptyResult
      for each attempt in attempts
          for each additional in additionals
              limit = "500"
              if attempt.idParam = "" then limit = "10000"
              params = "offset=0&limit=" + limit + "&sort_by=ep_num&sort_direction=asc"
              if attempt.idParam <> "" then params = attempt.idParam + "=" + id + "&" + params
              params = params + libraryParam
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
                  if parsed.count() = 0 and meta.count() = 0 then exit for
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
      mapper = idToStr(item.lookUp("mapper_id"))
      if mapper = "0" then mapper = idToStr(item.lookUp("mapperId"))
      showMapper = collectionDeepText(item, ["showMapperId", "show_mapper_id", "tvshow_mapper_id"])
      if showMapper <> "" and showMapper <> "0"
          item.addReplace("showMapperId", showMapper)
          item.addReplace("show_mapper_id", showMapper)
      end if
      showBackdropMtime = collectionDeepText(item, ["showBackdropMtime", "show_backdrop_mtime", "tvshow_backdrop_mtime"])
      if showBackdropMtime <> "" and showBackdropMtime <> "0"
          item.addReplace("showBackdropMtime", showBackdropMtime)
          item.addReplace("show_backdrop_mtime", showBackdropMtime)
      end if
      id = idToStr(item.lookUp("id"))
      if id = "" or id = "0" then id = idToStr(item.lookUp("videoStationId"))
      if id <> "" and id <> "0"
          item.addReplace("id", id)
          item.addReplace("videoStationId", id)
          item.addReplace("posterId", id)
      end if
      if mediaType = "tvshow" and (id = "" or id = "0") and mapper <> "" and mapper <> "0"
          mediaType = "episode"
          print "COLLECTION_TYPE_FIX tvshow-with-mapper title="; idToStr(item.lookUp("title")); " mapper="; mapper; " -> episode"
      end if
      item.addReplace("type", mediaType)
      if mapper <> "0"
          item.addReplace("mapperId", mapper)
          item.addReplace("mapper_id", mapper)
      end if
      additional = item.lookUp("additional")
      if additional <> invalid
          summary = idToStr(additional.lookUp("summary"))
          if summary <> "0" and summary <> "" then item.addReplace("summary", summary)
          rating = detailStateRating(additional)
          if rating > 0 then item.addReplace("rating", rating)
          tvshow = additional.lookUp("tvshow")
          if tvshow <> invalid and type(tvshow) = "roAssociativeArray"
              showMapper = idToStr(tvshow.lookUp("mapper_id"))
              if showMapper = "" or showMapper = "0" then showMapper = idToStr(tvshow.lookUp("mapperId"))
              if showMapper = "" or showMapper = "0" then showMapper = idToStr(tvshow.lookUp("id"))
              if showMapper <> "" and showMapper <> "0"
                  item.addReplace("showMapperId", showMapper)
                  item.addReplace("show_mapper_id", showMapper)
              end if
              showBackdropMtime = idToStr(tvshow.lookUp("backdrop_mtime"))
              if showBackdropMtime <> "" and showBackdropMtime <> "0"
                  item.addReplace("showBackdropMtime", showBackdropMtime)
                  item.addReplace("show_backdrop_mtime", showBackdropMtime)
              end if
          end if
          posterMtime = idToStr(additional.lookUp("poster_mtime"))
          if posterMtime <> "" and posterMtime <> "0" then item.addReplace("poster_mtime", posterMtime)
          backdropMtime = idToStr(additional.lookUp("backdrop_mtime"))
          if backdropMtime <> "" and backdropMtime <> "0" then item.addReplace("backdrop_mtime", backdropMtime)
      end if
  end sub

  function uniqueCollectionVideos(items as object) as object
      unique = []
      if items = invalid then return unique
      for each item in items
          key = collectionVideoUniqueKey(item)
          existingIdx = -1
          i = 0
          while i < unique.count()
              if collectionVideoUniqueKey(unique[i]) = key
                  existingIdx = i
                  exit while
              end if
              i = i + 1
          end while
          if existingIdx < 0
              unique.push(item)
          else if collectionVideoScore(item) > collectionVideoScore(unique[existingIdx])
              print "COLLECTION_DEDUPE replace key="; key; " old="; idToStr(unique[existingIdx].lookUp("title")); " new="; idToStr(item.lookUp("title"))
              unique[existingIdx] = item
          else
              print "COLLECTION_DEDUPE keep key="; key; " kept="; idToStr(unique[existingIdx].lookUp("title")); " skipped="; idToStr(item.lookUp("title"))
          end if
      end for
      return unique
  end function

  function collectionVideoUniqueKey(item as object) as string
      if item = invalid then return "invalid"
      mapper = idToStr(item.lookUp("mapper_id"))
      if mapper = "" or mapper = "0" then mapper = idToStr(item.lookUp("mapperId"))
      if mapper <> "" and mapper <> "0" then return "mapper:" + mapper
      id = idToStr(item.lookUp("id"))
      if id = "" or id = "0" then id = idToStr(item.lookUp("videoStationId"))
      mediaType = normalizedAppVideoType(idToStr(item.lookUp("type")))
      if id <> "" and id <> "0" then return mediaType + ":" + id
      title = lcase(idToStr(item.lookUp("title")))
      if title = "" or title = "0" then title = lcase(idToStr(item.lookUp("name")))
      return "title:" + title
  end function

  function collectionVideoScore(item as object) as integer
      if item = invalid then return 0
      score = 0
      mediaType = normalizedAppVideoType(idToStr(item.lookUp("type")))
      if mediaType = "episode" then score = score + 60
      if mediaType = "movie" then score = score + 40
      if mediaType = "homevideo" then score = score + 30
      id = idToStr(item.lookUp("id"))
      if id = "" or id = "0" then id = idToStr(item.lookUp("videoStationId"))
      if id <> "" and id <> "0" and val(id) > 0 then score = score + 80
      mapper = idToStr(item.lookUp("mapper_id"))
      if mapper = "" or mapper = "0" then mapper = idToStr(item.lookUp("mapperId"))
      if mapper <> "" and mapper <> "0" then score = score + 20
      if mediaType = "episode"
          if collectionDeepText(item, ["showTitle", "tvshow_title", "series_title", "parent_title"]) <> "" then score = score + 15
          if itemInt(item, ["seasonNumber", "season_number", "season", "season_num", "season_index"]) > 0 then score = score + 10
          if itemInt(item, ["episodeNumber", "episode_number", "episode", "episode_num", "ep_num", "ep_index"]) > 0 then score = score + 10
      end if
      if collectionDeepText(item, ["summary", "description"]) <> "" then score = score + 5
      if itemFileInfo(item).path <> "" then score = score + 5
      return score
  end function

  sub enrichCollectionVideoMetadata(item as object, baseUrl as string, sid as string, token as string)
      if item = invalid then return
      mediaType = normalizedAppVideoType(idToStr(item.lookUp("type")))
      if mediaType = "" or mediaType = "0" then return
      if mediaType = "episode" then enrichPlaylistShowBackdrop(item, baseUrl, sid, token)
      if not collectionNeedsMetadata(item, mediaType) then return

      candidateIds = []
      pushUniqueString(candidateIds, idToStr(item.lookUp("id")))
      pushUniqueString(candidateIds, idToStr(item.lookUp("videoStationId")))
      pushUniqueString(candidateIds, idToStr(item.lookUp("mapper_id")))
      pushUniqueString(candidateIds, idToStr(item.lookUp("mapperId")))
      fileInfo = itemFileInfo(item)
      pushUniqueString(candidateIds, idToStr(fileInfo.id))

      meta = invalid
      videoId = ""
      for each candidateId in candidateIds
          if candidateId <> "" and candidateId <> "0"
              candidateMeta = fetchCollectionInfoItem(baseUrl, sid, token, candidateId, mediaType)
              if candidateMeta <> invalid
                  if meta = invalid
                      meta = candidateMeta
                      videoId = candidateId
                  end if
                  if detailStateRating(candidateMeta) > 0
                      meta = candidateMeta
                      videoId = candidateId
                      exit for
                  end if
              end if
          end if
      end for
      if meta = invalid then return
      copyCollectionMetadata(meta, item, mediaType)
      print "COLLECTION_METADATA type="; mediaType; " id="; videoId; " title="; idToStr(item.lookUp("title")); " rating="; detailStateRating(item); " show="; idToStr(item.lookUp("showTitle")); " season="; idToStr(item.lookUp("seasonNumber")); " episode="; idToStr(item.lookUp("episodeNumber")); " date="; idToStr(item.lookUp("original_available"))
  end sub

  sub enrichPlaylistShowBackdrop(item as object, baseUrl as string, sid as string, token as string)
      if item = invalid then return
      if collectionDeepText(item, ["showBackdropUrl", "show_backdrop_url", "tvshowBackdropUrl"]) <> "" then return
      if firstNonZeroText(item, ["tvshow_id", "tvshowId", "showId", "show_id"]) <> "" then return
      title = collectionDeepText(item, ["showTitle", "tvshow_title", "series_title", "parent_title"])
      if title = "" then title = showTitleFromCollectionPath(item)
      if title = "" or title = "0" then title = collectionDeepText(item, ["title", "name"])
      if title = "" then return
      show = tvShowByTitle(baseUrl, sid, token, title)
      if show = invalid then return
      showId = idToStr(show.lookUp("id"))
      if showId <> "" and showId <> "0"
          item.addReplace("tvshow_id", showId)
          item.addReplace("tvshowId", showId)
      end if
      mapper = idToStr(show.lookUp("mapper_id"))
      if mapper = "" or mapper = "0" then mapper = idToStr(show.lookUp("mapperId"))
      if mapper <> "" and mapper <> "0"
          item.addReplace("showMapperId", mapper)
          item.addReplace("show_mapper_id", mapper)
      end if
      mtime = idToStr(show.lookUp("backdrop_mtime"))
      if mtime <> "" and mtime <> "0"
          item.addReplace("showBackdropMtime", mtime)
          item.addReplace("show_backdrop_mtime", mtime)
      end if
      backdrop = showBackdropUrlFromShow(baseUrl, sid, token, show)
      if backdrop <> ""
          item.addReplace("showBackdropUrl", backdrop)
          item.addReplace("show_backdrop_url", backdrop)
      end if
      print "PLAYLIST_SHOW_MATCH title="; title; " showId="; showId; " mapper="; mapper; " backdropLen="; len(backdrop)
  end sub

  function showBackdropUrlFromShow(baseUrl as string, sid as string, token as string, show as object) as string
      if show = invalid or baseUrl = "" or sid = "" then return ""
      saved = collectionDeepText(show, ["backdropUrl", "backdrop_url"])
      if saved <> "" and saved <> "0" then return saved
      mapper = idToStr(show.lookUp("mapper_id"))
      if mapper = "" or mapper = "0" then mapper = idToStr(show.lookUp("mapperId"))
      if mapper = "" or mapper = "0" then mapper = idToStr(show.lookUp("id"))
      if mapper = "" or mapper = "0" then return ""
      url = baseUrl + "/webapi/entry.cgi?mapper_id=" + mapper
      mtime = idToStr(show.lookUp("backdrop_mtime"))
      if mtime <> "" and mtime <> "0" then url = url + "&mtime=" + escapeUrlValue(mtime)
      url = url + "&api=SYNO.VideoStation2.Backdrop&method=get&version=1"
      url = url + "&_sid=" + sid
      if token <> "" then url = url + "&SynoToken=" + token
      return url
  end function

  function escapeUrlValue(value as string) as string
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

  function firstNonZeroText(item as object, keys as object) as string
      if item = invalid then return ""
      for each key in keys
          text = idToStr(item.lookUp(key))
          if text <> "" and text <> "0" then return text
      end for
      return ""
  end function

  function collectionPathText(item as object) as string
      if item = invalid then return ""
      text = collectionDeepText(item, ["filePath", "path", "sharepath", "file_path"])
      if text <> "" and text <> "0" then return text
      info = itemFileInfo(item)
      if info.path <> invalid and info.path <> "" then return info.path
      return collectionDeepText(item, ["file_name", "filename", "title", "name"])
  end function

  function showTitleFromCollectionPath(item as object) as string
      text = collectionPathText(item)
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

  function tvShowByTitle(baseUrl as string, sid as string, token as string, title as string) as dynamic
      if title = "" then return invalid
      if m.tvShowLookupItems = invalid
          m.tvShowLookupItems = loadTVShowLookupItems(baseUrl, sid, token)
      end if
      target = normalizedTitleKey(title)
      for each show in m.tvShowLookupItems
          showTitle = collectionDeepText(show, ["title", "name"])
          if normalizedTitleKey(showTitle) = target then return show
      end for
      return invalid
  end function

  function loadTVShowLookupItems(baseUrl as string, sid as string, token as string) as object
      items = []
      appendTVShowLookupItems(items, baseUrl, sid, token, "")
      libs = fetchDirectLibraries(baseUrl, sid, token)
      for each lib in libs
          if categoryForLibraryType(idToStr(lib.lookUp("type"))) = "tvshows"
              id = idToStr(lib.lookUp("id"))
              if id = "" or id = "0" then id = idToStr(lib.lookUp("library_id"))
              if id <> "" and id <> "0" then appendTVShowLookupItems(items, baseUrl, sid, token, id)
          end if
      end for
      return items
  end function

  sub appendTVShowLookupItems(items as object, baseUrl as string, sid as string, token as string, libraryId as string)
      additional = "%5B%22poster_mtime%22,%22backdrop_mtime%22%5D"
      params = "offset=0&limit=1000&sort_by=title&sort_direction=asc&additional=" + additional
      if libraryId <> "" and libraryId <> "0" then params = params + "&library_id=" + libraryId
      result = httpGet(apiUrl(baseUrl, "SYNO.VideoStation2.TVShow", "entry.cgi", "1", "list", params, sid, token))
      key = firstValidKey(result, ["tvshow", "tvshows"])
      if key = ""
          result = httpGet(apiUrl(baseUrl, "SYNO.VideoStation.TVShow", "VideoStation/tvshow.cgi", "1", "list", params, sid, token))
          key = firstValidKey(result, ["tvshows", "tvshow"])
      end if
      if key = "" then return
      json = parseJSON(result)
      if json = invalid or json.success <> true or json.data = invalid then return
      found = json.data.lookUp(key)
      if found = invalid then return
      if type(found) = "roArray"
          for each show in found
              appendUniqueTvShowLookupItem(items, show)
          end for
      else if type(found) = "roAssociativeArray"
          appendUniqueTvShowLookupItem(items, found)
      end if
  end sub

  sub appendUniqueTvShowLookupItem(items as object, show as dynamic)
      if show = invalid or type(show) <> "roAssociativeArray" then return
      id = idToStr(show.lookUp("id"))
      if id = "" or id = "0" then id = idToStr(show.lookUp("tvshow_id"))
      mapper = idToStr(show.lookUp("mapper_id"))
      if mapper = "" or mapper = "0" then mapper = idToStr(show.lookUp("mapperId"))
      for each existing in items
          existingId = idToStr(existing.lookUp("id"))
          if existingId = "" or existingId = "0" then existingId = idToStr(existing.lookUp("tvshow_id"))
          existingMapper = idToStr(existing.lookUp("mapper_id"))
          if existingMapper = "" or existingMapper = "0" then existingMapper = idToStr(existing.lookUp("mapperId"))
          if id <> "" and id <> "0" and existingId = id then return
          if mapper <> "" and mapper <> "0" and existingMapper = mapper then return
      end for
      items.push(show)
  end sub

  function collectionNeedsMetadata(item as object, mediaType as string) as boolean
      missingRating = detailStateRating(item) <= 0
      if mediaType = "movie"
          dateText = collectionDeepText(item, ["original_available", "originally_available", "year", "date"])
          return dateText = "" or missingRating
      end if
      if mediaType = "episode"
          showTitle = collectionDeepText(item, ["showTitle", "tvshow_title", "series_title", "parent_title"])
          season = collectionDeepText(item, ["seasonNumber", "season_number", "season", "season_num", "season_index"])
          episode = collectionDeepText(item, ["episodeNumber", "episode_number", "episode", "episode_num", "ep_num", "ep_index"])
          episodeTitle = collectionDeepText(item, ["episodeTitle", "episode_title"])
          if episodeTitle = ""
              itemTitle = collectionDeepText(item, ["title", "name"])
              if itemTitle <> "" and lcase(itemTitle.trim()) <> lcase(showTitle.trim()) then episodeTitle = itemTitle
          end if
          return showTitle = "" or season = "" or season = "0" or episode = "" or episode = "0" or episodeTitle = "" or missingRating
      end if
      return false
  end function

  function fetchCollectionInfoItem(baseUrl as string, sid as string, token as string, videoId as string, mediaType as string) as dynamic
      enc = createObject("roUrlTransfer")
      additionalForms = [
          "%5B%22extra%22,%22summary%22,%22file%22,%22actor%22,%22writer%22,%22director%22,%22genre%22,%22collection%22,%22watched_ratio%22,%22conversion_produced%22,%22backdrop_mtime%22,%22poster_mtime%22%5D",
          "%5B%22summary%22,%22file%22,%22collection%22,%22watched_ratio%22,%22backdrop_mtime%22,%22poster_mtime%22%5D",
          "%5B%22watched_ratio%22,%22file%22,%22backdrop_mtime%22,%22poster_mtime%22%5D",
          "%5B%22watched_ratio%22%5D"
      ]
      idForms = [
          "%5B%22" + enc.escape(videoId) + "%22%5D",
          "%5B" + enc.escape(videoId) + "%5D",
          enc.escape(videoId)
      ]
      requests = []
      apiName = v2InfoApiForMediaType(mediaType)
      requests.push({ api: apiName, path: "entry.cgi", version: "1", method: "getinfo", ids: idForms })
      if mediaType = "movie"
          requests.push({ api: "SYNO.VideoStation.Movie", path: "VideoStation/movie.cgi", version: "1", method: "getinfo", ids: idForms })
      end if
      if mediaType = "episode"
          requests.push({ api: "SYNO.VideoStation.TVShowEpisode", path: "VideoStation/tvshow_episode.cgi", version: "2", method: "getinfo", ids: idForms })
          requests.push({ api: "SYNO.VideoStation.TVShowEpisode", path: "VideoStation/tvshow_episode.cgi", version: "2", method: "list", ids: [enc.escape(videoId)] })
          requests.push({ api: "SYNO.VideoStation.TVShowEpisode", path: "VideoStation/tvshow_episode.cgi", version: "1", method: "list", ids: [enc.escape(videoId)] })
      end if
      fallbackItem = invalid
      for each req in requests
          url = apiEndpoint(baseUrl, req.api, req.path, sid, token)
          for each idForm in req.ids
              for each additional in additionalForms
                  body = "api=" + enc.escape(req.api) + "&version=" + req.version + "&method=" + req.method + "&id=" + idForm + "&additional=" + additional
                  if req.method = "list" then body = "api=" + enc.escape(req.api) + "&version=" + req.version + "&method=list&offset=0&limit=1&id=" + idForm + "&additional=" + additional
                  r = httpPostForm(url, body)
                  item = collectionInfoItemFromResponse(r, mediaType)
                  if item <> invalid
                      if fallbackItem = invalid then fallbackItem = item
                      if detailStateRating(item) > 0 then return item
                  end if
              end for
          end for
      end for
      return fallbackItem
  end function

  function collectionInfoItemFromResponse(r as dynamic, mediaType as string) as dynamic
      if r = invalid or r = "" then return invalid
      j = parseJSON(r)
      if j <> invalid and j.success = true and j.data <> invalid
          item = firstV2InfoItem(j.data, mediaType)
          if item <> invalid then return item
      end if
      return invalid
  end function

  sub copyCollectionMetadata(meta as object, item as object, mediaType as string)
      copyEpisodeMetadataField(meta, item, "title")
      copyEpisodeMetadataField(meta, item, "name")
      copyEpisodeMetadataField(meta, item, "summary")
      copyEpisodeMetadataField(meta, item, "description")
      copyEpisodeMetadataField(meta, item, "original_available")
      copyEpisodeMetadataField(meta, item, "originally_available")
      copyEpisodeMetadataField(meta, item, "year")
      copyEpisodeMetadataField(meta, item, "rating")
      copyEpisodeMetadataField(meta, item, "rate")
      copyEpisodeMetadataField(meta, item, "user_rating")
      copyEpisodeMetadataField(meta, item, "additional")
      copyEpisodeMetadataField(meta, item, "mapper_id")
      copyEpisodeMetadataField(meta, item, "mapperId")
      copyEpisodeMetadataField(meta, item, "tvshow_mapper_id")
      copyEpisodeMetadataField(meta, item, "tvshow_backdrop_mtime")

      if mediaType = "episode"
          copyEpisodeMetadataField(meta, item, "season")
          copyEpisodeMetadataField(meta, item, "season_number")
          copyEpisodeMetadataField(meta, item, "season_num")
          copyEpisodeMetadataField(meta, item, "season_index")
          copyEpisodeMetadataField(meta, item, "episode")
          copyEpisodeMetadataField(meta, item, "episode_number")
          copyEpisodeMetadataField(meta, item, "episode_num")
          copyEpisodeMetadataField(meta, item, "ep_num")
          copyEpisodeMetadataField(meta, item, "ep_index")
          showTitle = collectionDeepText(meta, ["showTitle", "tvshow_title", "series_title", "parent_title"])
          if showTitle = ""
              tvshow = meta.lookUp("tvshow")
              if tvshow <> invalid
                  showTitle = collectionDeepText(tvshow, ["title", "name"])
                  showMapper = collectionDeepText(tvshow, ["mapper_id", "mapperId", "id"])
                  if showMapper <> "" and showMapper <> "0"
                      item.addReplace("showMapperId", showMapper)
                      item.addReplace("show_mapper_id", showMapper)
                  end if
                  showBackdropMtime = collectionDeepText(tvshow, ["backdrop_mtime", "backdropMtime"])
                  if showBackdropMtime <> "" and showBackdropMtime <> "0"
                      item.addReplace("showBackdropMtime", showBackdropMtime)
                      item.addReplace("show_backdrop_mtime", showBackdropMtime)
                  end if
              end if
          end if
          if showTitle = ""
              additional = meta.lookUp("additional")
              if additional <> invalid
                  showTitle = collectionDeepText(additional, ["showTitle", "tvshow_title", "series_title", "parent_title"])
                  tvshow = additional.lookUp("tvshow")
                  if tvshow <> invalid
                      if showTitle = "" then showTitle = collectionDeepText(tvshow, ["title", "name"])
                      showMapper = collectionDeepText(tvshow, ["mapper_id", "mapperId", "id"])
                      if showMapper <> "" and showMapper <> "0"
                          item.addReplace("showMapperId", showMapper)
                          item.addReplace("show_mapper_id", showMapper)
                      end if
                      showBackdropMtime = collectionDeepText(tvshow, ["backdrop_mtime", "backdropMtime"])
                      if showBackdropMtime <> "" and showBackdropMtime <> "0"
                          item.addReplace("showBackdropMtime", showBackdropMtime)
                          item.addReplace("show_backdrop_mtime", showBackdropMtime)
                      end if
                  end if
              end if
          end if
          showMapper = collectionDeepText(meta, ["showMapperId", "show_mapper_id", "tvshow_mapper_id"])
          if showMapper <> "" and showMapper <> "0"
              item.addReplace("showMapperId", showMapper)
              item.addReplace("show_mapper_id", showMapper)
          end if
          showBackdropMtime = collectionDeepText(meta, ["showBackdropMtime", "show_backdrop_mtime", "tvshow_backdrop_mtime"])
          if showBackdropMtime <> "" and showBackdropMtime <> "0"
              item.addReplace("showBackdropMtime", showBackdropMtime)
              item.addReplace("show_backdrop_mtime", showBackdropMtime)
          end if
          if showTitle <> "" then item.addReplace("showTitle", showTitle)
          seasonText = collectionDeepText(meta, ["seasonNumber", "season_number", "season", "season_num", "season_index"])
          if seasonText <> "" and seasonText <> "0" then item.addReplace("seasonNumber", seasonText)
          episodeText = collectionDeepText(meta, ["episodeNumber", "episode_number", "episode", "episode_num", "ep_num", "ep_index"])
          if episodeText <> "" and episodeText <> "0" then item.addReplace("episodeNumber", episodeText)
          episodeTitle = collectionDeepText(meta, ["episodeTitle", "episode_title", "title", "name", "tagline"])
          if episodeTitle <> "" and lcase(episodeTitle.trim()) <> lcase(showTitle.trim())
              item.addReplace("episodeTitle", episodeTitle)
          end if
      end if

      dateText = collectionDeepText(meta, ["original_available", "originally_available", "year", "date"])
      if dateText <> "" and dateText <> "0" then item.addReplace("original_available", dateText)
      summary = episodeSummaryText(meta)
      if summary <> ""
          item.addReplace("summary", summary)
          item.addReplace("description", summary)
      end if
  end sub

  function collectionDeepText(item as dynamic, keys as object) as string
      if item = invalid then return ""
      if type(item) <> "roAssociativeArray"
          textValue = idToStr(item)
          trimmed = textValue.trim()
          if left(trimmed, 1) = "{" or left(trimmed, 1) = "["
              parsed = parseJSON(trimmed)
              if parsed <> invalid
                  parsedText = collectionDeepText(parsed, keys)
                  if parsedText <> "" and parsedText <> "0" then return parsedText
              end if
          end if
          return textValue
      end if
      for each key in keys
          value = item.lookUp(key)
          if value <> invalid
              if type(value) = "roAssociativeArray"
                  text = collectionDeepText(value, ["title", "name", "value", "summary", "description"])
                  if text <> "" and text <> "0" then return text
              else
                  text = idToStr(value)
                  if text <> "" and text <> "0" then return text
              end if
          end if
      end for
      additional = item.lookUp("additional")
      if additional <> invalid
          text = collectionDeepText(additional, keys)
          if text <> "" and text <> "0" then return text
      end if
      extra = item.lookUp("extra")
      if extra <> invalid
          text = collectionDeepText(extra, keys)
          if text <> "" and text <> "0" then return text
      end if
      return ""
  end function

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

  function movieSummaryText(item as object) as string
      if item = invalid then return ""
      summary = summaryTextFromValue(item.lookUp("summary"))
      if summary <> "" then return summary
      additional = item.lookUp("additional")
      if additional <> invalid
          summary = summaryTextFromValue(additional.lookUp("summary"))
          if summary <> "" then return summary
          extra = additional.lookUp("extra")
          extraObj = detailStateObject(extra)
          if extraObj <> invalid
              summary = summaryTextFromValue(extraObj.lookUp("summary"))
              if summary <> "" then return summary
          end if
      end if
      extra = item.lookUp("extra")
      extraObj = detailStateObject(extra)
      if extraObj <> invalid
          summary = summaryTextFromValue(extraObj.lookUp("summary"))
          if summary <> "" then return summary
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
      metadata = fetchVsmetaMetadata(baseUrl, sid, token, filePath, episodeTitle)
      return metadata.summary
  end function

  function fetchVsmetaMetadata(baseUrl as string, sid as string, token as string, filePath as string, episodeTitle as string) as object
      if filePath = "" then return { summary: "", rating: 0, releaseDate: "" }
      url = fileStationStreamUrl(baseUrl, sid, token, filePath + ".vsmeta")
      blob = httpGet(url)
      if blob = invalid or blob = "" then return { summary: "", rating: 0, releaseDate: "" }
      summary = vsmetaSummaryFromBlob(blob, episodeTitle)
      releaseDate = vsmetaReleaseDateFromBlob(blob)
      rating = vsmetaRatingFromBlob(blob)
      if summary <> "" or releaseDate <> "" or rating > 0 then print "VSMETA_METADATA title="; episodeTitle; " len="; len(summary); " rating="; rating; " releaseDate="; releaseDate
      return { summary: summary, rating: rating, releaseDate: releaseDate }
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
      text = trimVsmetaTrailingTag(text)
      if instr(1, text, "JFIF") > 0 then return ""
      if instr(1, text, "Exif") > 0 then return ""
      if instr(1, text, ".") = 0 and instr(1, text, "!") = 0 and instr(1, text, "?") = 0 then return ""
      return text
  end function

  function trimVsmetaTrailingTag(text as string) as string
      if len(text) < 3 then return text
      lastChar = right(text, 1)
      prevChar = mid(text, len(text) - 1, 1)
      if len(lastChar) = 1
          code = asc(lastChar)
          if code >= 65 and code <= 90
              if prevChar = "." or prevChar = "!" or prevChar = "?" then return left(text, len(text) - 1).trim()
          end if
      end if
      return text
  end function

  function movieReleaseDateText(item as object) as string
      if item = invalid then return ""
      for each key in ["originalAvailable", "original_available", "originally_available", "original_available_date", "originally_available_date", "release_date", "premiered", "date"]
          value = idToStr(item.lookUp(key))
          dateText = fullDateFromText(value)
          if dateText <> "" then return dateText
      end for
      additional = item.lookUp("additional")
      if additional <> invalid
          for each key in ["originalAvailable", "original_available", "originally_available", "original_available_date", "originally_available_date", "release_date", "premiered", "date"]
              value = idToStr(additional.lookUp(key))
              dateText = fullDateFromText(value)
              if dateText <> "" then return dateText
          end for
          extra = detailStateObject(additional.lookUp("extra"))
          if extra <> invalid
              for each key in ["originalAvailable", "original_available", "originally_available", "original_available_date", "originally_available_date", "release_date", "premiered", "date"]
                  value = idToStr(extra.lookUp(key))
                  dateText = fullDateFromText(value)
                  if dateText <> "" then return dateText
              end for
          end if
      end if
      extra = detailStateObject(item.lookUp("extra"))
      if extra <> invalid
          for each key in ["originalAvailable", "original_available", "originally_available", "original_available_date", "originally_available_date", "release_date", "premiered", "date"]
              value = idToStr(extra.lookUp(key))
              dateText = fullDateFromText(value)
              if dateText <> "" then return dateText
          end for
      end if
      return ""
  end function

  function vsmetaReleaseDateFromBlob(blob as string) as string
      return fullDateFromText(blob)
  end function

  function fullDateFromText(text as string) as string
      if text = "" then return ""
      idx = 1
      while idx <= len(text) - 9
          candidate = mid(text, idx, 10)
          if fullDateCandidate(candidate) then return candidate
          idx = idx + 1
      end while
      return ""
  end function

  function fullDateCandidate(value as string) as boolean
      if len(value) <> 10 then return false
      if mid(value, 5, 1) <> "-" or mid(value, 8, 1) <> "-" then return false
      if not decimalText(left(value, 4)) then return false
      if not decimalText(mid(value, 6, 2)) then return false
      if not decimalText(right(value, 2)) then return false
      year = val(left(value, 4))
      month = val(mid(value, 6, 2))
      day = val(right(value, 2))
      if year < 1900 or year > 2100 then return false
      if month < 1 or month > 12 then return false
      if day < 1 or day > 31 then return false
      return true
  end function

  function decimalText(text as string) as boolean
      if text = "" then return false
      idx = 1
      while idx <= len(text)
          ch = mid(text, idx, 1)
          if ch < "0" or ch > "9" then return false
          idx = idx + 1
      end while
      return true
  end function

  function vsmetaRatingFromBlob(blob as string) as integer
      best = 0
      for each marker in [chr(34) + "rating" + chr(34), "rating"]
          searchAt = 1
          while searchAt > 0
              found = instr(searchAt, blob, marker)
              if found <= 0 then exit while
              chunk = mid(blob, found, 140)
              rating = ratingFromTextChunk(chunk)
              if rating > best then best = rating
              searchAt = found + len(marker)
          end while
      end for
      return best
  end function

  function ratingFromTextChunk(text as string) as integer
      idx = 1
      while idx <= len(text)
          ch = mid(text, idx, 1)
          if (ch >= "0" and ch <= "9") or ch = "."
              valueText = ""
              dotSeen = false
              while idx <= len(text)
                  ch2 = mid(text, idx, 1)
                  if ch2 >= "0" and ch2 <= "9"
                      valueText = valueText + ch2
                  else if ch2 = "." and dotSeen = false
                      valueText = valueText + ch2
                      dotSeen = true
                  else
                      exit while
                  end if
                  idx = idx + 1
              end while
              if valueText <> ""
                  raw = val(valueText)
                  if raw > 0 and raw <= 10 then return int((raw * 10) + 0.5)
                  if raw > 10 and raw <= 100 then return int(raw)
              end if
          end if
          idx = idx + 1
      end while
      return 0
  end function

  function firstNumericField(item as object, keys as object) as integer
      if item = invalid then return 0
      for each key in keys
          value = item.lookUp(key)
          if value <> invalid
              t = type(value)
              if t = "roInteger" or t = "Integer" or t = "roInt" or t = "roLongInteger" or t = "LongInteger" then return value
              if t = "roFloat" or t = "Float" or t = "roDouble" or t = "Double" then return int(value)
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
              copyEpisodeMetadataField(meta, item, "rating")
              copyEpisodeMetadataField(meta, item, "rate")
              copyEpisodeMetadataField(meta, item, "user_rating")
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
          if fileInfo.id = invalid and fileInfo.path = ""
              episodeId = idToStr(item.lookUp("id"))
              if episodeId = "" or episodeId = "0" then keep = false
          end if
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

  function httpPostMultipart(url as string, body as string, boundary as string) as dynamic
      port = createObject("roMessagePort")
      http = createObject("roUrlTransfer")
      http.setUrl(url)
      http.setCertificatesFile("common:/certs/ca-bundle.crt")
      http.enableHostVerification(false)
      http.enablePeerVerification(false)
      http.addHeader("Content-Type", "multipart/form-data; boundary=" + boundary)
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
      extensions = [".mp4", ".mkv", ".m4v", ".mov", ".avi", ".webm", ".m2ts"]
      enc = createObject("roUrlTransfer")
      firstCandidate = basePathNoExt + ".mp4"
      parent = left(firstCandidate, len(firstCandidate) - len(baseName(firstCandidate)) - 1)
      url = baseUrl + "/webapi/entry.cgi?api=SYNO.FileStation.List&version=2&method=list&folder_path=" + enc.escape(parent) + "&filetype=file&limit=5000&_sid=" + sid
      r = httpGet(url)
      if r <> invalid
          j = parseJSON(r)
          if j <> invalid and j.success = true
              files = j.data.lookUp("files")
              if files <> invalid
                  for each ext in extensions
                      candidate = basePathNoExt + ext
                      for each f in files
                          fpath = f.lookUp("path")
                          if fpath <> invalid and fpath = candidate
                              print "FIND_MOVIE exact="; candidate
                              return candidate
                          end if
                      end for
                  end for
              end if
          end if
      end if
      return ""
  end function

  function findMovieByFolderPrefix(baseUrl as string, sid as string, title as string) as string
      if title = "" then return ""
      enc = createObject("roUrlTransfer")
      bases = ["/video/Movies", "/video"]
      for each basePath in bases
          url = baseUrl + "/webapi/entry.cgi?api=SYNO.FileStation.List&version=2&method=list&folder_path=" + enc.escape(basePath) + "&filetype=all&limit=5000&_sid=" + sid
          r = httpGetLong(url, 15000)
          if r <> invalid
              j = parseJSON(r)
              if j <> invalid and j.success = true and j.data <> invalid
                  dirs = j.data.lookUp("files")
                  if dirs <> invalid
                      for each d in dirs
                          if not isFolderLike(d) then goto nextPrefixDir
                          dname = d.lookUp("name")
                          dpath = d.lookUp("path")
                          if dname <> invalid and dpath <> invalid
                              if titleMatch(title, dname)
                                  vpath = findVideoInDir(baseUrl, sid, dpath)
                                  if vpath <> ""
                                      print "FIND_MOVIE prefixDir="; dpath; " file="; vpath
                                      return vpath
                                  end if
                              end if
                          end if
nextPrefixDir:
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
      lt = stripTrailingYearParen(lcase(title))
      lc = stripTrailingYearParen(lcase(baseName(candidate)))
      if right(lc, 4) = ".mkv" then lc = left(lc, len(lc) - 4)
      if right(lc, 4) = ".mp4" then lc = left(lc, len(lc) - 4)
      if right(lc, 4) = ".avi" then lc = left(lc, len(lc) - 4)
      if right(lc, 4) = ".m4v" then lc = left(lc, len(lc) - 4)
      if right(lc, 5) = ".webm" then lc = left(lc, len(lc) - 5)
      if right(lc, 5) = ".m2ts" then lc = left(lc, len(lc) - 5)
      if right(lc, 4) = ".mov" then lc = left(lc, len(lc) - 4)
      lc = stripTrailingYearParen(lc)
      if lt = lc then return true
      if isAllDigits(lt)
          if len(lc) > len(lt) and left(lc, len(lt)) = lt
              rest = mid(lc, len(lt) + 1).trim()
              if left(rest, 1) = "(" then return true
          end if
          return false
      end if
      if len(lc) > len(lt)
          nextCh = mid(lc, len(lt) + 1, 1)
          if left(lc, len(lt)) = lt
              if nextCh = " " or nextCh = "(" or nextCh = "." or nextCh = "-" or nextCh = "_" then return true
          end if
      end if

      nt = normalizedTitleKey(lt)
      nc = normalizedTitleKey(lc)
      if nt <> "" and nt = nc then return true
      if isAllDigits(nt) then return false
      if nt <> "" and len(nc) > len(nt)
          if left(nc, len(nt)) = nt then return true
      end if
      return false
  end function

  function stripTrailingYearParen(value as string) as string
      text = value.trim()
      if len(text) < 7 then return text
      if right(text, 1) <> ")" then return text
      openIdx = 0
      idx = len(text)
      while idx >= 1
          if mid(text, idx, 1) = "("
              openIdx = idx
              exit while
          end if
          idx = idx - 1
      end while
      if openIdx <= 1 then return text
      yearText = mid(text, openIdx + 1, len(text) - openIdx - 1)
      if len(yearText) <> 4 then return text
      if not isAllDigits(yearText) then return text
      return left(text, openIdx - 1).trim()
  end function

  function isAllDigits(value as string) as boolean
      if value = "" then return false
      idx = 1
      while idx <= len(value)
          code = asc(mid(value, idx, 1))
          if code < 48 or code > 57 then return false
          idx = idx + 1
      end while
      return true
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

      cleanTitle = stripTrailingYearParen(title)
      titleVariants = [title]
      if cleanTitle <> "" and cleanTitle <> title then titleVariants.push(cleanTitle)

      for each titleVariant in titleVariants
          directPaths = ["/video/TV Shows/" + titleVariant, "/video/Ian's Shows/" + titleVariant, "/video/TV/" + titleVariant, "/video/Series/" + titleVariant]
          for each directPath in directPaths
              print "FIND_EPISODES direct="; directPath
              collectEpisodeFiles(baseUrl, sid, token, directPath, 2, results)
              if results.count() > 0 then return results
          end for
      end for

      searchPaths = ["/video/TV Shows", "/video/Ian's Shows", "/video/TV", "/video/Series"]
      for each titleVariant in titleVariants
          for each basePath in searchPaths
              showDir = findShowDirInTree(baseUrl, sid, token, titleVariant, basePath, 2)
              if showDir <> ""
                  print "FIND_EPISODES dir="; showDir
                  collectEpisodeFiles(baseUrl, sid, token, showDir, 2, results)
                  if results.count() > 0 then return results
              end if
          end for
      end for

      return results
  end function

  function findEpisodeFilesBySearch(baseUrl as string, sid as string, token as string, title as string, basePath as string) as object
      results = []
      word = firstSearchWord(title)
      if word = "" then return results
      enc = createObject("roUrlTransfer")
      patterns = [word + "*", "*" + word + "*", title]
      for each pattern in patterns
          folderParam = "%5B%22" + enc.escape(basePath) + "%22%5D"
          startUrl = apiUrl(baseUrl, "SYNO.FileStation.Search", "entry.cgi", "2", "start", "folder_path=" + folderParam + "&pattern=" + enc.escape(pattern) + "&filetype=file&recursive=true", sid, token)
          print "FIND_EPISODES searchStart="; basePath; " pattern="; pattern
          r = httpGet(startUrl)
          if r <> invalid
              j = parseJSON(r)
              if j <> invalid and j.success = true and j.data <> invalid
                  taskid = j.data.lookUp("taskid")
                  if taskid <> invalid and taskid <> ""
                      poll = 0
                      while poll < 10
                          listUrl = apiUrl(baseUrl, "SYNO.FileStation.Search", "entry.cgi", "2", "list", "taskid=" + enc.escape(taskid) + "&limit=5000", sid, token)
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
                                              if isVideoFile(fname) and not pathContainsEaDir(fpath) and episodePathMatchesTitle(title, fpath)
                                                  results.push(episodeItemFromFile(fpath))
                                              end if
                                          end if
                                      end for
                                      if results.count() > 0
                                          cleanFileStationSearch(baseUrl, sid, token, taskid)
                                          print "FIND_EPISODES searchCount="; results.count()
                                          return results
                                      end if
                                  end if
                                  finished = lj.data.lookUp("finished")
                                  if finished = true then exit while
                              end if
                          end if
                          poll = poll + 1
                      end while
                      cleanFileStationSearch(baseUrl, sid, token, taskid)
                  end if
              end if
          end if
      end for
      return results
  end function

  sub cleanFileStationSearch(baseUrl as string, sid as string, token as string, taskid as string)
      enc = createObject("roUrlTransfer")
      cleanUrl = apiUrl(baseUrl, "SYNO.FileStation.Search", "entry.cgi", "2", "clean", "taskid=" + enc.escape(taskid), sid, token)
      httpGet(cleanUrl)
  end sub

  function pathContainsEaDir(path as string) as boolean
      return instr(1, lcase(path), "/@eadir/") > 0
  end function

  function episodePathMatchesTitle(title as string, path as string) as boolean
      if titleMatch(title, fileNameNoExt(path)) then return true
      key = normalizedTitleKey(stripTrailingYearParen(title))
      if key = "" then return false
      pathKey = normalizedTitleKey(path)
      return instr(1, pathKey, key) > 0
  end function

  ' Return path of first video file in a FileStation directory.
  function findVideoInDir(baseUrl as string, sid as string, dirPath as string) as string
      enc = createObject("roUrlTransfer")
      url = baseUrl + "/webapi/entry.cgi?api=SYNO.FileStation.List&version=2&method=list&folder_path=" + enc.escape(dirPath) + "&filetype=all&limit=5000&_sid=" + sid
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
              if not isFolderLike(f) and isVideoFile(fname) then return fpath
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
      url = baseUrl + "/webapi/entry.cgi?api=SYNO.FileStation.List&version=2&method=list&folder_path=" + enc.escape(dirPath) + "&filetype=all&limit=5000&_sid=" + sid
      r = httpGet(url)
      if r = invalid then return ""
      j = parseJSON(r)
      if j = invalid or j.success <> true then return ""
      dirs = j.data.lookUp("files")
      if dirs = invalid then return ""

      idx = 0
      while idx < dirs.count()
          d = dirs[idx]
          if not isFolderLike(d) then goto nextTreeMatchedDir
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
nextTreeMatchedDir:
          idx = idx + 1
      end while

      idx = 0
      while idx < dirs.count()
          d = dirs[idx]
          if not isFolderLike(d) then goto nextTreeDir
          dpath = d.lookUp("path")
          if dpath <> invalid and depth > 0
              vpath = findMovieInTree(baseUrl, sid, title, dpath, depth - 1)
              if vpath <> "" then return vpath
          end if
nextTreeDir:
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
          fileUrl = baseUrl + "/webapi/entry.cgi?api=SYNO.FileStation.List&version=2&method=list&folder_path=" + enc.escape(basePath) + "&filetype=all&limit=5000&_sid=" + sid
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
                              if not isFolderLike(f) and isVideoFile(fname) and titleMatch(title, fname) then return fpath
                          end if
                          fidx = fidx + 1
                      end while
                  end if
              end if
          end if

          url = baseUrl + "/webapi/entry.cgi?api=SYNO.FileStation.List&version=2&method=list&folder_path=" + enc.escape(basePath) + "&filetype=all&limit=5000&_sid=" + sid
          r = httpGet(url)
          if r <> invalid
              j = parseJSON(r)
              if j <> invalid and j.success = true
                  dirs = j.data.lookUp("files")
                  if dirs <> invalid
                      didx = 0
                      while didx < dirs.count()
                          d = dirs[didx]
                          if not isFolderLike(d) then goto nextMovieDir
                          dname = d.lookUp("name")
                          dpath = d.lookUp("path")
                          if dname <> invalid and dpath <> invalid
                              if titleMatch(title, dname)
                                  print "FIND_MOVIE matchDir="; dpath
                                  vpath = findVideoInDir(baseUrl, sid, dpath)
                                  if vpath <> "" then return vpath
                              end if
                          end if
nextMovieDir:
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
  
