sub init()
      m.screenStack = []
      m.top.findNode("playbackFocusTimer").observeField("fire", "onPlaybackFocusTimer")
      m.top.findNode("autoplayContextTimer").observeField("fire", "onAutoplayContextTimer")
      if hasSavedCredentials()
          autoLogin()
      else
          showLoginScreen()
      end if
  end sub

  function hasSavedCredentials() as boolean
      reg = createObject("roRegistrySection", "DSVideo")
      return reg.exists("nasAddress") and reg.exists("nasPort") and reg.exists("username") and reg.exists("password")
  end function

  function savedBaseUrl(host as string, port as string, useHttps as boolean) as string
      if port = "" then port = "5000"
      if useHttps then return "https://" + host + ":" + port
      return "http://" + host + ":" + port
  end function

  sub autoLogin()
      reg = createObject("roRegistrySection", "DSVideo")
      host = readProtectedSetting(reg, "nasAddress")
      port = readProtectedSetting(reg, "nasPort")
      username = readProtectedSetting(reg, "username")
      password = readProtectedSetting(reg, "password")
      useHttps = true
      if reg.exists("useHttps") then useHttps = (reg.read("useHttps") = "true")

      task = createObject("roSGNode", "APITask")
      task.request = {
          action: "login",
          baseUrl: savedBaseUrl(host, port, useHttps),
          username: username,
          password: password
      }
      task.observeField("response", "onAutoLoginResponse")
      task.control = "RUN"
      m.autoLoginTask = task
      m.savedLogin = { host: host, useHttps: useHttps, username: username, password: password }
  end sub

  function readProtectedSetting(reg as object, key as string) as string
      if reg = invalid then return ""
      if not reg.exists(key) then return ""
      return unprotectSetting(reg.read(key), key)
  end function

  function unprotectSetting(value as dynamic, key as string) as string
      if value = invalid then return ""
      if type(value) <> "roString" and type(value) <> "String" then return ""
      prefix = "enc:v1:"
      if left(value, len(prefix)) <> prefix then return value
      hexText = mid(value, len(prefix) + 1)
      secret = settingSecret(key)
      out = ""
      i = 1
      charIndex = 1
      while i <= len(hexText) - 1
          encoded = hexPairValue(mid(hexText, i, 2))
          secretIndex = ((charIndex - 1) mod len(secret)) + 1
          salt = asc(mid(secret, secretIndex, 1)) + ((charIndex * 17) mod 251)
          decoded = encoded - (salt mod 256)
          while decoded < 0
              decoded = decoded + 256
          end while
          out = out + chr(decoded)
          i = i + 2
          charIndex = charIndex + 1
      end while
      return out
  end function

  function settingSecret(key as string) as string
      return "DSVideo:Roku:" + key + ":2026"
  end function

  function hexPairValue(pair as string) as integer
      if len(pair) < 2 then return 0
      return hexDigitValue(left(pair, 1)) * 16 + hexDigitValue(mid(pair, 2, 1))
  end function

  function hexDigitValue(ch as string) as integer
      code = asc(lcase(ch))
      if code >= 48 and code <= 57 then return code - 48
      if code >= 97 and code <= 102 then return code - 87
      return 0
  end function

  sub onAutoLoginResponse(event as object)
      response = event.getData()
      if response <> invalid and response.success = true
          m.authData = { sid: response.sid, synoToken: response.synoToken, baseUrl: response.baseUrl, username: m.savedLogin.username, password: m.savedLogin.password }
          showHomeScreen(m.authData)
      else
          showLoginScreen()
      end if
  end sub

  sub showLoginScreen()
      loginScreen = createObject("roSGNode", "LoginScreen")
      loginScreen.observeField("authSuccess", "onAuthSuccess")
      loginScreen.observeField("keyInput", "onLoginKey")
      m.top.appendChild(loginScreen)
      loginScreen.setFocus(true)
      m.loginScreen = loginScreen
      m.currentScreen = loginScreen
  end sub

  ' Forward keys to LoginScreen via its keyInput field
  function onKeyEvent(key as string, press as boolean) as boolean
      if not press then return false

      ' Back from any screen except login — pop the stack
      if key = "back"
          if isLocalPlaylistGrid(m.currentScreen)
              doBack()
              return true
          end if
          if isTopNavFocused() then return false
          if m.screenStack.count() > 1
              doBack()
              return true
          end if
          if focusTopNavIfAvailable() then return true
          if m.currentScreen <> invalid and m.currentScreen.findNode("videoNode") = invalid then return true
          return false
      end if

      ' Forward all other keys to LoginScreen while it is active
      if m.loginScreen <> invalid and m.currentScreen = m.loginScreen
          m.loginScreen.keyInput = key
          return true
      end if

      if m.currentScreen <> invalid and m.currentScreen.findNode("videoNode") = invalid
          return true
      end if

      return false
  end function

  function isLocalPlaylistGrid(screen as dynamic) as boolean
      if screen = invalid then return false
      if screen.subtype() <> "VideoGrid" then return false
      category = screen.category
      if category = invalid then return false
      return left(category, 6) = "local_"
  end function

  function isTopNavFocused() as boolean
      if m.currentScreen = invalid then return false
      if m.currentScreen.findNode("videoNode") <> invalid then return false
      nav = m.currentScreen.findNode("categoryList")
      if nav = invalid then return false
      return nav.hasFocus()
  end function

  function focusTopNavIfAvailable() as boolean
      if m.currentScreen = invalid then return false
      if m.currentScreen.findNode("videoNode") <> invalid then return false
      nav = m.currentScreen.findNode("categoryList")
      if nav = invalid then return false
      nav.setFocus(true)
      return true
  end function

  sub doBack()
      if m.screenStack.count() > 1
          closeVideoIfNeeded(m.currentScreen)
          screenToRemove = m.currentScreen
          m.top.removeChild(screenToRemove)
          if screenToRemove = m.loginScreen then m.loginScreen = invalid
          m.screenStack.pop()
          m.currentScreen = m.screenStack[m.screenStack.count() - 1]
          while m.listsChanged = true and m.currentScreen <> invalid and m.currentScreen.subtype() = "VideoDetail" and m.screenStack.count() > 1
              staleDetail = m.currentScreen
              m.top.removeChild(staleDetail)
              m.screenStack.pop()
              m.currentScreen = m.screenStack[m.screenStack.count() - 1]
          end while
          if screenToRemove.subtype() = "SettingsScreen"
              m.currentScreen.setFocus(true)
              nav = m.currentScreen.findNode("categoryList")
              if nav <> invalid
                  m.currentScreen.focusNavCategory = "settings"
                  return
              end if
          end if
          ' Focus the Group first, then the actual inner navigable widget
          m.currentScreen.setFocus(true)
          if m.listsChanged = true and m.currentScreen.subtype() = "VideoGrid"
              m.currentScreen.refreshLists = true
              m.listsChanged = false
          end if
          innerIds = ["videoGrid", "playlistMovieGrid", "playlistEpisodeGrid", "episodeGrid", "categoryList"]
          innerIdx = 0
          while innerIdx < innerIds.count()
              inner = m.currentScreen.findNode(innerIds[innerIdx])
              if inner <> invalid and inner.visible <> false
                  inner.setFocus(true)
                  innerIdx = innerIds.count()
              end if
              innerIdx = innerIdx + 1
          end while
      end if
  end sub

  sub closeVideoIfNeeded(screen as object)
      if screen = invalid then return
      video = screen.findNode("videoNode")
      if video = invalid then return
      video.control = "stop"
      video.visible = false
      video.content = invalid
  end sub

  sub onLoginKey(event as object)
      if event = invalid then return
  end sub

  sub onAuthSuccess(event as object)
      authData = event.getData()
      if authData = invalid then return
      if authData.sid = invalid then return
      if authData.sid = "" then return
      m.authData = authData
      if m.loginScreen <> invalid then m.top.removeChild(m.loginScreen)
      m.loginScreen = invalid
      m.currentScreen = invalid
      m.screenStack = []
      showHomeScreen(authData)
  end sub

  sub showHomeScreen(authData as object)
      homeScreen = createObject("roSGNode", "HomeScreen")
      homeScreen.authData = authData
      homeScreen.observeField("selectedCategory", "onCategorySelected")
      homeScreen.observeField("navCategories", "onNavCategoriesLoaded")
      m.top.appendChild(homeScreen)
      homeScreen.setFocus(true)
      m.screenStack.push(homeScreen)
      m.currentScreen = homeScreen
  end sub

  sub onCategorySelected(event as object)
      data = event.getData()
      if data = invalid then return
      if data.category = "settings"
          showSettingsScreen()
          return
      end if
      videoGrid = createObject("roSGNode", "VideoGrid")
      videoGrid.authData = m.authData
      if data.libraryId <> invalid then videoGrid.libraryId = data.libraryId
      if m.navCategories <> invalid then videoGrid.navCategories = m.navCategories
      videoGrid.pageLabel = data.title
      videoGrid.category = data.category
      videoGrid.observeField("selectedVideo", "onVideoSelected")
      videoGrid.observeField("selectedCategory", "onCategorySelected")
      videoGrid.observeField("backPressed", "onBackPressed")
      keepCurrent = false
      if data.category <> invalid and left(data.category, 6) = "local_" and m.currentScreen <> invalid and m.currentScreen.subtype() = "VideoGrid"
          currentCategory = m.currentScreen.category
          if currentCategory = "playlists" then keepCurrent = true
      end if
      if m.currentScreen <> invalid and keepCurrent = false
          m.top.removeChild(m.currentScreen)
          m.screenStack = []
      end if
      m.top.appendChild(videoGrid)
      videoGrid.setFocus(true)
      m.screenStack.push(videoGrid)
      m.currentScreen = videoGrid
  end sub

  sub onNavCategoriesLoaded(event as object)
      cats = event.getData()
      if cats <> invalid then m.navCategories = cats
  end sub

  sub showSettingsScreen()
      settingsScreen = createObject("roSGNode", "SettingsScreen")
      settingsScreen.authData = m.authData
      if m.navCategories <> invalid then settingsScreen.navCategories = m.navCategories
      settingsScreen.observeField("selectedCategory", "onCategorySelected")
      settingsScreen.observeField("backPressed", "onBackPressed")
      settingsScreen.observeField("settingsSaved", "onSettingsSaved")
      m.top.appendChild(settingsScreen)
      settingsScreen.setFocus(true)
      m.screenStack.push(settingsScreen)
      m.currentScreen = settingsScreen
  end sub

  sub onSettingsSaved(event as object)
      if event = invalid then return
      if event.getData() <> true then return
      closeAllScreens()
      autoLogin()
  end sub

  sub closeAllScreens()
      while m.screenStack.count() > 0
          screenToRemove = m.screenStack.pop()
          closeVideoIfNeeded(screenToRemove)
          m.top.removeChild(screenToRemove)
      end while
      m.currentScreen = invalid
      m.loginScreen = invalid
  end sub

  sub onVideoSelected(event as object)
      data = event.getData()
      if data = invalid then return
      if data.type = "tvshow"
          episodeList = createObject("roSGNode", "EpisodeList")
          episodeList.authData = m.authData
          if m.navCategories <> invalid then episodeList.navCategories = m.navCategories
          episodeList.showData = data
          episodeList.observeField("selectedVideo", "onVideoSelected")
          episodeList.observeField("selectedCategory", "onCategorySelected")
          episodeList.observeField("backPressed", "onBackPressed")
          m.top.appendChild(episodeList)
          episodeList.setFocus(true)
          m.screenStack.push(episodeList)
          m.currentScreen = episodeList
      else
          showVideoDetail(data)
      end if
  end sub

  sub showVideoDetail(videoData as object)
      if videoData <> invalid
          print "SHOW_DETAIL type="; videoData.lookUp("type"); " title="; videoData.lookUp("title")
      end if
      detail = createObject("roSGNode", "VideoDetail")
      detail.observeField("playVideo", "onDetailPlay")
      detail.observeField("backPressed", "onBackPressed")
      detail.observeField("listChanged", "onDetailListChanged")
      detail.observeField("sourceListRemoved", "onDetailSourceListRemoved")
      detail.videoData = videoData
      m.top.appendChild(detail)
      detail.setFocus(true)
      m.screenStack.push(detail)
      m.currentScreen = detail
  end sub

  sub onDetailPlay(event as object)
      videoData = event.getData()
      if videoData = invalid then return
      m.playStartedFromDetail = true
      playVideo(videoData)
  end sub

  sub playVideo(videoData as object)
      resumePosition = savedResumePosition(videoData)
      if shouldRefreshResumePosition(videoData)
          startResumeRefresh(videoData)
          return
      end if
      if resumePosition > 30 and videoData.lookUp("resumeChoice") = invalid
          showResumePrompt(videoData, resumePosition)
          return
      end if
      player = createObject("roSGNode", "VideoPlayer")
      player.authData = m.authData
      if videoData.lookUp("resumeChoice") = "resume"
          videoData.resumePosition = resumePosition
      else
          videoData.resumePosition = 0
      end if
      if videoData.lookUp("resumeChoice") <> invalid then videoData.delete("resumeChoice")
      player.resumePosition = videoData.resumePosition
      player.videoData = videoData
      if videoData <> invalid and videoData.lookUp("type") = "episode"
          m.lastPlaybackVideo = videoData
      end if
      player.observeField("playbackResult", "onPlaybackDone")
      player.observeField("playbackStarted", "onPlaybackStarted")
      m.top.appendChild(player)
      player.setFocus(true)
      m.screenStack.push(player)
      m.currentScreen = player
      if videoData <> invalid and videoData.lookUp("type") = "episode" and videoData.lookUp("autoplayEpisodes") = invalid
          m.pendingAutoplayContextVideo = videoData
      end if
  end sub

  sub onPlaybackStarted(event as object)
      if event = invalid then return
      if m.pendingAutoplayContextVideo = invalid then return
      timer = m.top.findNode("autoplayContextTimer")
      if timer <> invalid
          timer.control = "stop"
          timer.control = "start"
      end if
  end sub

  sub onAutoplayContextTimer(event as object)
      if event = invalid then return
      if m.pendingAutoplayContextVideo = invalid then return
      attachEpisodeAutoplayContext(m.pendingAutoplayContextVideo)
      m.pendingAutoplayContextVideo = invalid
  end sub

  function shouldRefreshResumePosition(videoData as object) as boolean
      if videoData = invalid then return false
      if videoData.lookUp("type") <> "episode" then return false
      if videoData.lookUp("resumeChoice") <> invalid then return false
      if videoData.lookUp("resumeRefreshDone") = true then return false
      if m.authData = invalid then return false
      if m.authData.proxyBaseUrl = invalid or m.authData.proxyBaseUrl = "" then return false
      if videoData.lookUp("filePath") = invalid or videoData.lookUp("filePath") = "" then return false
      return true
  end function

  sub startResumeRefresh(videoData as object)
      videoData.resumeRefreshDone = true
      task = createObject("roSGNode", "APITask")
      task.request = {
          action: "latestResume",
          proxyBaseUrl: m.authData.proxyBaseUrl,
          filePath: videoData.lookUp("filePath"),
          showTitle: videoData.lookUp("showTitle"),
          showMapperId: videoData.lookUp("showMapperId")
      }
      task.observeField("response", "onResumeRefreshDone")
      task.control = "RUN"
      m.resumeRefreshVideo = videoData
      m.resumeRefreshTask = task
  end sub

  sub onResumeRefreshDone(event as object)
      response = event.getData()
      videoData = m.resumeRefreshVideo
      m.resumeRefreshVideo = invalid
      m.resumeRefreshTask = invalid
      if videoData = invalid then return
      if response <> invalid and response.success = true
          latest = 0
          if response.position <> invalid then latest = int(response.position)
          current = itemResumePosition(videoData)
          if latest > current then videoData.addReplace("resumePosition", latest)
          print "RESUME_REFRESH file="; videoData.lookUp("filePath"); " latest="; latest; " current="; current
      end if
      playVideo(videoData)
  end sub

  sub showResumePrompt(videoData as object, position as integer)
      dialog = createObject("roSGNode", "Dialog")
      dialog.title = "Resume Playback"
      dialog.message = "Resume from " + formatResumeTime(position) + "?"
      dialog.buttons = ["Resume", "Start Over"]
      dialog.observeField("buttonSelected", "onResumeDialogSelected")
      m.pendingResumeVideo = videoData
      m.pendingResumePosition = position
      m.top.dialog = dialog
  end sub

  sub onResumeDialogSelected(event as object)
      idx = event.getData()
      videoData = m.pendingResumeVideo
      m.pendingResumeVideo = invalid
      m.top.dialog = invalid
      if videoData = invalid then return
      print "RESUME_DIALOG idx="; idx; " saved="; m.pendingResumePosition
      if idx = 0
          videoData.resumeChoice = "resume"
          videoData.resumePosition = m.pendingResumePosition
      else
          clearResumePosition(videoData)
          videoData.resumeChoice = "start"
          videoData.resumePosition = 0
      end if
      playVideo(videoData)
  end sub

  function savedResumePosition(videoData as object) as integer
      key = resumeKeyForVideo(videoData)
      itemPosition = itemResumePosition(videoData)
      if key = "" then return itemPosition
      reg = createObject("roRegistrySection", "DSVideoResume")
      if reg.exists(key)
          localPosition = val(reg.read(key))
          if itemPosition > localPosition then return itemPosition
          return localPosition
      end if
      return itemPosition
  end function

  function itemResumePosition(videoData as object) as integer
      if videoData = invalid then return 0
      fields = ["resumePosition", "watch_position", "position"]
      for each field in fields
          value = videoData.lookUp(field)
          if value <> invalid
              t = type(value)
              if t = "roInteger" or t = "Integer" then return value
              if t = "roFloat" or t = "Float" then return int(value)
              if t = "roString" or t = "String" then return val(value)
          end if
      end for
      return 0
  end function

  sub clearResumePosition(videoData as object)
      key = resumeKeyForVideo(videoData)
      if key = "" then return
      reg = createObject("roRegistrySection", "DSVideoResume")
      if reg.exists(key)
          reg.delete(key)
          reg.flush()
      end if
  end sub

  function resumeKeyForVideo(videoData as object) as string
      if videoData = invalid then return ""
      if videoData.filePath <> invalid and videoData.filePath <> "" then return "path:" + videoData.filePath
      if videoData.fileId <> invalid and videoData.fileId <> "" then return "file:" + safeDynamicString(videoData.fileId)
      if videoData.id <> invalid and videoData.id <> "" then return "id:" + safeDynamicString(videoData.id)
      return ""
  end function

  function formatResumeTime(seconds as integer) as string
      total = int(seconds)
      hours = int(total / 3600)
      minutes = int((total - (hours * 3600)) / 60)
      secs = total - (hours * 3600) - (minutes * 60)
      if hours > 0
          return stri(hours).trim() + ":" + twoDigit(minutes) + ":" + twoDigit(secs)
      end if
      return stri(minutes).trim() + ":" + twoDigit(secs)
  end function

  function twoDigit(value as integer) as string
      text = stri(value).trim()
      if value < 10 then return "0" + text
      return text
  end function

  sub onPlaybackDone(event as object)
      if m.currentScreen = invalid then return
      if m.currentScreen.findNode("videoNode") = invalid then return
      result = event.getData()
      playedVideo = invalid
      nextVideo = invalid
      if result <> invalid
          playedVideo = result.lookUp("videoData")
      end if
      if playedVideo = invalid and m.lastPlaybackVideo <> invalid
          playedVideo = m.lastPlaybackVideo
      end if
      if playedVideo <> invalid and playedVideo.lookUp("autoplayEpisodes") = invalid and m.lastPlaybackVideo <> invalid and autoplayVideoKey(playedVideo) = autoplayVideoKey(m.lastPlaybackVideo)
          playedVideo = m.lastPlaybackVideo
      end if
      if result <> invalid and result.lookUp("reason") = "finished"
          if playedVideo <> invalid and playedVideo.lookUp("autoplayEpisodes") = invalid then attachEpisodeAutoplayContext(playedVideo)
          nextVideo = nextAutoplayEpisode(playedVideo)
      end if
      if playedVideo <> invalid and playedVideo.lookUp("type") = "episode"
          m.lastPlayedEpisode = playedVideo
      end if
      doBack()
      if m.playStartedFromDetail = true
          if m.currentScreen <> invalid and m.currentScreen.subtype() = "VideoDetail"
              doBack()
          end if
          m.playStartedFromDetail = false
      end if
      if nextVideo = invalid
          focusVideo = playedVideo
          if focusVideo = invalid and m.lastPlayedEpisode <> invalid then focusVideo = m.lastPlayedEpisode
          if focusVideo <> invalid then requestEpisodePlaybackFocus(focusVideo)
      end if
      if nextVideo <> invalid
          playVideo(nextVideo)
      end if
  end sub

  sub requestEpisodePlaybackFocus(videoData as object)
      if videoData = invalid then return
      print "PLAYBACK_FOCUS_REQUEST season="; safeDynamicString(videoData.lookUp("seasonNumber")); " episode="; safeDynamicString(videoData.lookUp("episodeNumber")); " title="; safeDynamicString(videoData.lookUp("title"))
      m.pendingPlaybackFocusVideo = videoData
      applyEpisodePlaybackFocus()
      timer = m.top.findNode("playbackFocusTimer")
      if timer <> invalid then timer.control = "start"
  end sub

  sub onPlaybackFocusTimer(event as object)
      if event = invalid then return
      applyEpisodePlaybackFocus()
  end sub

  sub applyEpisodePlaybackFocus()
      if m.pendingPlaybackFocusVideo = invalid then return
      if m.currentScreen = invalid then return
      if m.currentScreen.subtype() <> "EpisodeList" then return
      print "PLAYBACK_FOCUS_APPLY season="; safeDynamicString(m.pendingPlaybackFocusVideo.lookUp("seasonNumber")); " episode="; safeDynamicString(m.pendingPlaybackFocusVideo.lookUp("episodeNumber"))
      m.currentScreen.playbackFocusVideo = m.pendingPlaybackFocusVideo
      m.pendingPlaybackFocusVideo = invalid
  end sub

  function nextAutoplayEpisode(videoData as dynamic) as dynamic
      if videoData = invalid then return invalid
      if videoData.lookUp("type") <> "episode" then return invalid
      episodes = videoData.lookUp("autoplayEpisodes")
      if episodes = invalid or episodes.count() = 0 then return invalid
      idx = -1
      if videoData.lookUp("autoplayIndex") <> invalid then idx = int(videoData.lookUp("autoplayIndex"))
      if idx < 0 then idx = autoplayIndexForVideo(videoData, episodes)
      nextIdx = idx + 1
      if nextIdx < 0 or nextIdx >= episodes.count() then return invalid
      nextVideo = cloneAutoplayVideo(episodes[nextIdx])
      nextVideo.autoplayEpisodes = episodes
      nextVideo.autoplayIndex = nextIdx
      nextVideo.resumeChoice = "start"
      nextVideo.resumePosition = 0
      return nextVideo
  end function

  sub attachEpisodeAutoplayContext(videoData as object)
      if videoData = invalid then return
      if videoData.lookUp("autoplayEpisodes") <> invalid then return
      episodeScreen = activeEpisodeListScreen()
      if episodeScreen = invalid or episodeScreen.subtype() <> "EpisodeList" then return
      episodes = episodeScreen.episodeItems
      if episodes = invalid or episodes.count() = 0 then return
      playlist = autoplayEpisodeListForScene(episodes, episodeScreen.showData, m.authData)
      videoData.autoplayEpisodes = playlist
      videoData.autoplayIndex = autoplayIndexForVideo(videoData, playlist)
      print "AUTOPLAY_CONTEXT count="; playlist.count(); " index="; safeDynamicString(videoData.lookUp("autoplayIndex")); " title="; safeDynamicString(videoData.lookUp("title"))
  end sub

  function activeEpisodeListScreen() as dynamic
      if m.screenStack = invalid then return invalid
      idx = m.screenStack.count() - 1
      while idx >= 0
          screen = m.screenStack[idx]
          if screen <> invalid and screen.subtype() = "EpisodeList" then return screen
          idx = idx - 1
      end while
      return invalid
  end function

  function autoplayEpisodeListForScene(episodes as object, showData as dynamic, authData as dynamic) as object
      playlist = []
      sorted = sortEpisodesForAutoplayInScene(episodes)
      idx = 0
      while idx < sorted.count()
          playlist.push(autoplayEpisodePayloadForScene(sorted[idx], showData, authData, idx))
          idx = idx + 1
      end while
      return playlist
  end function

  function sortEpisodesForAutoplayInScene(episodes as object) as object
      sorted = []
      if episodes = invalid then return sorted
      for each ep in episodes
          sorted.push(ep)
      end for
      i = 0
      while i < sorted.count()
          j = i + 1
          while j < sorted.count()
              leftSeason = sceneEpisodeSeason(sorted[i])
              rightSeason = sceneEpisodeSeason(sorted[j])
              leftNum = sceneEpisodeNumber(sorted[i])
              rightNum = sceneEpisodeNumber(sorted[j])
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

  function autoplayEpisodePayloadForScene(ep as object, showData as dynamic, authData as dynamic, fallbackIndex as integer) as object
      epId = ep.lookUp("id")
      if epId = invalid then epId = "0"
      fileInfo = sceneFileInfoFromItem(ep)
      rawFileId = fileInfo.id
      if rawFileId = invalid then rawFileId = epId
      epNumber = sceneEpisodeNumber(ep)
      if epNumber <= 0 then epNumber = fallbackIndex + 1
      seasonNumber = sceneEpisodeSeason(ep)
      episodeMeta = "Episode"
      if seasonNumber > 0 and epNumber > 0
          episodeMeta = "Season " + stri(seasonNumber).trim() + " - Episode " + stri(epNumber).trim()
      else if epNumber > 0
          episodeMeta = "Episode " + stri(epNumber).trim()
      end if
      showMapperId = invalid
      showTitle = ""
      if showData <> invalid
          showMapperId = showData.lookUp("mapperId")
          showTitle = sceneSafeStr(showData, ["title", "name"])
      end if
      return {
          type: "episode",
          id: epId,
          fileId: rawFileId,
          mapperId: ep.lookUp("mapper_id"),
          showMapperId: showMapperId,
          showTitle: showTitle,
          filePath: fileInfo.path,
          seasonNumber: seasonNumber,
          episodeNumber: epNumber,
          episodeMeta: episodeMeta,
          originalAvailable: sceneSafeStr(ep, ["originalAvailable", "original_available", "originally_available", "air_date", "year", "date"]),
          resumePosition: sceneFirstNumber(ep, ["resumePosition", "watch_position", "position"]),
          title: sceneSafeStr(ep, ["title", "name"]),
          authData: authData
      }
  end function

  function sceneFileInfoFromItem(item as object) as object
      info = { id: invalid, path: "" }
      if item = invalid then return info
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

  function sceneEpisodeSeason(item as object) as integer
      return sceneFirstNumber(item, ["seasonNumber", "season_number", "season", "season_num", "season_index"])
  end function

  function sceneEpisodeNumber(item as object) as integer
      return sceneFirstNumber(item, ["episodeNumber", "episode_number", "episode", "episode_num", "ep_num", "ep_index"])
  end function

  function sceneFirstNumber(item as object, keys as object) as integer
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

  function sceneSafeStr(item as object, keys as object) as string
      if item = invalid then return ""
      for each key in keys
          value = item.lookUp(key)
          text = safeDynamicString(value)
          if text <> "" and text <> "0" then return text
      end for
      return ""
  end function

  function cloneAutoplayVideo(source as object) as object
      clone = {}
      if source = invalid then return clone
      for each key in source
          if key <> "autoplayEpisodes"
              clone[key] = source[key]
          end if
      end for
      return clone
  end function

  function autoplayIndexForVideo(videoData as object, episodes as object) as integer
      key = autoplayVideoKey(videoData)
      idx = 0
      while idx < episodes.count()
          if autoplayVideoKey(episodes[idx]) = key then return idx
          idx = idx + 1
      end while
      return -1
  end function

  function autoplayVideoKey(item as object) as string
      if item = invalid then return ""
      if item.filePath <> invalid and item.filePath <> "" then return "path:" + item.filePath
      if item.fileId <> invalid and item.fileId <> "" then return "file:" + safeDynamicString(item.fileId)
      if item.id <> invalid and item.id <> "" then return "id:" + safeDynamicString(item.id)
      return "se:" + safeDynamicString(item.lookUp("seasonNumber")) + "x" + safeDynamicString(item.lookUp("episodeNumber"))
  end function

  function safeDynamicString(value as dynamic) as string
      if value = invalid then return ""
      t = type(value)
      if t = "roString" or t = "String" then return value
      if t = "roInteger" or t = "Integer" then return stri(value).trim()
      if t = "roFloat" or t = "Float" then return stri(int(value)).trim()
      return ""
  end function

  sub onBackPressed(event as object)
      if event = invalid then return
      doBack()
  end sub

  sub onDetailListChanged(event as object)
      if event = invalid then return
      m.listsChanged = true
  end sub

  sub onDetailSourceListRemoved(event as object)
      if event = invalid then return
      if event.getData() <> true then return
      m.listsChanged = true
  end sub
