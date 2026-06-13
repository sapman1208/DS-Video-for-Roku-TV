sub init()
      m.screenStack = []
      m.videoBackExit = false
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
          if m.currentScreen <> invalid and m.currentScreen.findNode("videoNode") <> invalid
              m.videoBackExit = true
          end if
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
          screenToRemove = m.screenStack[m.screenStack.count() - 1]
          closeVideoIfNeeded(screenToRemove)
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
          restoreCurrentScreenFocus()
          if m.listsChanged = true and m.currentScreen.subtype() = "VideoGrid"
              m.currentScreen.refreshLists = true
              m.listsChanged = false
          end if
      end if
  end sub

  sub restoreCurrentScreenFocus()
      if m.currentScreen = invalid then return
      innerIds = ["videoGrid", "playlistMovieGrid", "playlistEpisodeGrid", "episodeGrid", "categoryList", "actionGrid"]
      innerIdx = 0
      while innerIdx < innerIds.count()
          inner = m.currentScreen.findNode(innerIds[innerIdx])
          if inner <> invalid and inner.visible <> false
              inner.setFocus(true)
              return
          end if
          innerIdx = innerIdx + 1
      end while
      m.currentScreen.setFocus(true)
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
          videoData.addReplace("resumePosition", resumePosition)
      else
          videoData.addReplace("resumePosition", 0)
      end if
      if videoData.lookUp("resumeChoice") <> invalid then videoData.delete("resumeChoice")
      player.resumePosition = videoData.resumePosition
      player.videoData = videoData
      if videoData <> invalid and (videoData.lookUp("type") = "episode" or videoData.lookUp("type") = "movie")
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
          videoData.addReplace("resumeChoice", "resume")
          videoData.addReplace("resumePosition", m.pendingResumePosition)
      else
          clearResumePosition(videoData)
          videoData.addReplace("resumeChoice", "start")
          videoData.addReplace("resumePosition", 0)
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
      wasBackExit = m.videoBackExit
      m.videoBackExit = false
      if result <> invalid and result.lookUp("reason") = "finished" and wasBackExit <> true
          if playedVideo <> invalid and playedVideo.lookUp("autoplayEpisodes") = invalid then attachEpisodeAutoplayContext(playedVideo)
          nextVideo = nextAutoplayEpisode(playedVideo)
          if nextVideo = invalid then nextVideo = nextAutoplayMovie(playedVideo)
          if nextVideo = invalid then nextVideo = nextAutoplayHomeVideo(playedVideo)
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
          if focusVideo <> invalid then requestPlaybackFocus(focusVideo)
      end if
      if nextVideo <> invalid
          playVideo(nextVideo)
      end if
  end sub

  sub requestPlaybackFocus(videoData as object)
      if videoData = invalid then return
      if videoData.lookUp("type") = "homevideo" or videoData.lookUp("type") = "movie"
          requestGridPlaybackFocus(videoData)
      else
          requestEpisodePlaybackFocus(videoData)
      end if
  end sub

  sub requestGridPlaybackFocus(videoData as object)
      if videoData = invalid then return
      if m.currentScreen = invalid then return
      if m.currentScreen.subtype() <> "VideoGrid" then return
      print "GRID_PLAYBACK_FOCUS_REQUEST title="; safeDynamicString(videoData.lookUp("title"))
      m.currentScreen.playbackFocusVideo = videoData
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

  function nextAutoplayHomeVideo(videoData as dynamic) as dynamic
      if videoData = invalid then return invalid
      if videoData.lookUp("type") <> "homevideo" then return invalid
      grid = activeVideoGridScreen()
      if grid = invalid then return invalid
      items = grid.videoItems
      if items = invalid or items.count() = 0 then return invalid
      currentId = safeDynamicString(videoData.lookUp("id"))
      currentKey = autoplayVideoKey(videoData)
      idx = -1
      i = 0
      while i < items.count()
          candidate = homeVideoPayloadForScene(items[i], grid, i)
          candidateId = safeDynamicString(candidate.lookUp("id"))
          if (currentId <> "" and currentId <> "0" and candidateId = currentId) or autoplayVideoKey(candidate) = currentKey
              idx = i
              i = items.count()
          end if
          i = i + 1
      end while
      nextIdx = idx + 1
      if idx < 0 or nextIdx >= items.count() then return invalid
      nextVideo = homeVideoPayloadForScene(items[nextIdx], grid, nextIdx)
      nextVideo.resumeChoice = "start"
      nextVideo.resumePosition = 0
      print "HOMEVIDEO_AUTOPLAY_NEXT index="; nextIdx; " title="; safeDynamicString(nextVideo.lookUp("title"))
      return nextVideo
  end function

  function nextAutoplayMovie(videoData as dynamic) as dynamic
      if videoData = invalid then return invalid
      if videoData.lookUp("type") <> "movie" then return invalid
      seriesKey = movieSeriesKeyForScene(videoData)
      if seriesKey = "" then return invalid
      grid = activeVideoGridScreen()
      if grid = invalid then return invalid
      items = grid.videoItems
      if items = invalid or items.count() = 0 then return invalid
      currentKey = autoplayVideoKey(videoData)
      idx = -1
      i = 0
      while i < items.count()
          candidate = moviePayloadForScene(items[i], grid, i)
          if movieSeriesKeyForScene(candidate) = seriesKey
              if autoplayVideoKey(candidate) = currentKey
                  idx = i
                  i = items.count()
              end if
          end if
          i = i + 1
      end while
      nextIdx = idx + 1
      if idx < 0 or nextIdx >= items.count() then return invalid
      nextVideo = moviePayloadForScene(items[nextIdx], grid, nextIdx)
      if movieSeriesKeyForScene(nextVideo) <> seriesKey then return invalid
      nextVideo.resumeChoice = "start"
      nextVideo.resumePosition = 0
      print "MOVIE_AUTOPLAY_NEXT series="; seriesKey; " index="; nextIdx; " title="; safeDynamicString(nextVideo.lookUp("title"))
      return nextVideo
  end function

  function activeVideoGridScreen() as dynamic
      if m.screenStack = invalid then return invalid
      idx = m.screenStack.count() - 1
      while idx >= 0
          screen = m.screenStack[idx]
          if screen <> invalid and screen.subtype() = "VideoGrid" then return screen
          idx = idx - 1
      end while
      return invalid
  end function

  function homeVideoPayloadForScene(item as object, grid as object, fallbackIndex as integer) as object
      title = sceneSafeStr(item, ["title", "name", "file_name"])
      displayTitle = stripSingleDateParenForScene(title)
      if displayTitle = "" then displayTitle = title
      fileInfo = sceneFileInfoFromItem(item)
      rawId = item.lookUp("id")
      if rawId = invalid then rawId = "0"
      rawFileId = fileInfo.id
      if rawFileId = invalid then rawFileId = rawId
      category = "homevideos"
      if grid <> invalid and grid.category <> invalid then category = grid.category
      return {
          type: "homevideo",
          id: rawId,
          fileId: rawFileId,
          mapperId: sceneSafeStr(item, ["mapper_id", "mapperId"]),
          sourceCategory: category,
          collectionVideoType: "homevideo",
          filePath: fileInfo.path,
          originalAvailable: sceneSafeStr(item, ["rokuDisplayDate", "originalAvailable", "original_available", "originally_available", "date", "year"]),
          title: displayTitle,
          summary: sceneSafeStr(item, ["summary", "description", "tagline"]),
          watchedRatio: 0,
          fileWatched: fileInfo.watched,
          rating: sceneNumberForItem(item, ["rating", "rate"]),
          posterUrl: sceneSafeStr(item, ["posterUrl", "posterRemoteUrl"]),
          posterRemoteUrl: sceneSafeStr(item, ["posterRemoteUrl", "posterUrl"]),
          backdropUrl: sceneSafeStr(item, ["backdropUrl", "backdropRemoteUrl"]),
          backdropRemoteUrl: sceneSafeStr(item, ["backdropRemoteUrl", "backdropUrl"]),
          autoplayIndex: fallbackIndex,
          authData: m.authData
      }
  end function

  function moviePayloadForScene(item as object, grid as object, fallbackIndex as integer) as object
      fileInfo = sceneFileInfoFromItem(item)
      rawId = item.lookUp("id")
      if rawId = invalid then rawId = "0"
      rawFileId = fileInfo.id
      if rawFileId = invalid then rawFileId = rawId
      category = "movies"
      if grid <> invalid and grid.category <> invalid then category = grid.category
      return {
          type: "movie",
          id: rawId,
          videoStationId: sceneSafeStr(item, ["videoStationId", "video_station_id", "posterId"]),
          fileId: rawFileId,
          mapperId: sceneSafeStr(item, ["mapper_id", "mapperId"]),
          sourceCategory: category,
          collectionVideoType: "movie",
          filePath: fileInfo.path,
          originalAvailable: sceneSafeStr(item, ["originalAvailable", "original_available", "originally_available", "release_date", "date", "year", "create_time"]),
          title: sceneSafeStr(item, ["title", "name", "file_name"]),
          summary: sceneSafeStr(item, ["summary", "description", "tagline"]),
          watchedRatio: sceneNumberForItem(item, ["watched_ratio", "watchedRatio"]),
          fileWatched: fileInfo.watched,
          rating: sceneNumberForItem(item, ["rating", "rate"]),
          posterUrl: sceneSafeStr(item, ["posterUrl", "posterRemoteUrl"]),
          posterRemoteUrl: sceneSafeStr(item, ["posterRemoteUrl", "posterUrl"]),
          backdropUrl: sceneSafeStr(item, ["backdropUrl", "backdropRemoteUrl"]),
          backdropRemoteUrl: sceneSafeStr(item, ["backdropRemoteUrl", "backdropUrl"]),
          autoplayIndex: fallbackIndex,
          authData: m.authData
      }
  end function

  function sceneNumberForItem(item as object, keys as object) as integer
      text = sceneSafeStr(item, keys)
      if text = "" then return 0
      return val(text)
  end function

  function stripSingleDateParenForScene(title as string) as string
      openIdx = 0
      closeIdx = 0
      i = 1
      while i <= len(title)
          ch = mid(title, i, 1)
          if ch = "(" then openIdx = i
          if ch = ")" and openIdx > 0
              closeIdx = i
              inner = mid(title, openIdx + 1, closeIdx - openIdx - 1).trim()
              if sceneLooksLikeDate(inner)
                  before = left(title, openIdx - 1).trim()
                  after = mid(title, closeIdx + 1).trim()
                  if before <> "" and after = "" then return before
              end if
          end if
          i = i + 1
      end while
      return title
  end function

  function sceneLooksLikeDate(value as string) as boolean
      if value = "" then return false
      hasDigit = false
      i = 1
      while i <= len(value)
          code = asc(mid(value, i, 1))
          if code >= 48 and code <= 57 then hasDigit = true
          i = i + 1
      end while
      return hasDigit
  end function

  function movieSeriesKeyForScene(item as dynamic) as string
      title = normalizedMovieTitleForScene(sceneSafeStr(item, ["title", "name", "file_name"]))
      if title = "" then return ""
      if instr(1, title, "back to the future") > 0 then return "back to the future"
      if instr(1, title, "final destination") > 0 then return "final destination"
      if instr(1, title, "dont breathe") > 0 then return "dont breathe"
      if instr(1, title, "amazing spider man") > 0 or instr(1, title, "spider man") > 0 then return "spider man"
      if instr(1, title, "star wars") > 0 or instr(1, title, "empire strikes back") > 0 then return "star wars"
      if instr(1, title, "star trek") > 0 then return "star trek"
      if instr(1, title, "stargate") > 0 then return "stargate"
      if instr(1, title, "scream") = 1 then return "scream"
      if instr(1, title, "scary movie") = 1 then return "scary movie"
      if instr(1, title, "john wick") > 0 then return "john wick"
      if instr(1, title, "harry potter") > 0 then return "harry potter"
      if instr(1, title, "hunger games") > 0 then return "hunger games"
      if instr(1, title, "toy story") > 0 then return "toy story"
      if instr(1, title, "transformers") > 0 then return "transformers"
      if instr(1, title, "twilight") > 0 then return "twilight"
      if instr(1, title, "ice age") > 0 then return "ice age"
      if instr(1, title, "fear street") > 0 then return "fear street"
      if instr(1, title, "futurama") > 0 then return "futurama"
      if instr(1, title, "south park") > 0 then return "south park"
      if instr(1, title, "home alone") > 0 then return "home alone"
      if instr(1, title, "hocus pocus") > 0 then return "hocus pocus"
      if instr(1, title, "hurricane bianca") > 0 then return "hurricane bianca"
      if title = "finding nemo" or title = "finding dory" then return "finding"
      if instr(1, title, "pooh") > 0 and instr(1, title, "heffalump") > 0 then return "pooh heffalump"
      if title = "quarantine" or instr(1, title, "quarantine ") = 1 or title = "quarentine" or instr(1, title, "quarentine ") = 1 then return "quarantine"
      if title = "shrek" or instr(1, title, "shrek ") = 1 then return "shrek"
      if instr(1, title, "terrifier") > 0 then return "terrifier"
      if instr(1, title, "the strangers") > 0 or instr(1, title, "strangers") = 1 then return "strangers"
      if instr(1, title, "texas chain saw massacre") > 0 or instr(1, title, "texas chainsaw massacre") > 0 then return "texas chainsaw massacre"
      if instr(1, title, "naked gun") > 0 then return "naked gun"
      if instr(1, title, "lion king") > 0 or instr(1, title, "lion guard") > 0 then return "lion king"
      if instr(1, title, "underworld") > 0 then return "underworld"
      if instr(1, title, "sherlock holmes") > 0 then return "sherlock holmes"
      if instr(1, title, "wrong turn") > 0 then return "wrong turn"
      if instr(1, title, "venom") > 0 then return "venom"
      if title = "halloween" or instr(1, title, "halloween ii") = 1 or instr(1, title, "halloween 4") = 1 or instr(1, title, "halloween kills") = 1 or instr(1, title, "halloween ends") = 1 then return "halloween"
      if title = "friday the 13th" or instr(1, title, "friday the 13th part") = 1 then return "friday the 13th"
      return ""
  end function

  function normalizedMovieTitleForScene(title as string) as string
      lower = lcase(title)
      out = ""
      lastSpace = true
      i = 1
      while i <= len(lower)
          ch = mid(lower, i, 1)
          code = asc(ch)
          isWord = (code >= 48 and code <= 57) or (code >= 97 and code <= 122)
          if isWord
              out = out + ch
              lastSpace = false
          else if ch = "'"
              ' Keep contractions together: Don't -> dont.
          else if code = 226
              ' Curly apostrophes are UTF-8; dropping this byte avoids splitting contractions.
          else if not lastSpace
              out = out + " "
              lastSpace = true
          end if
          i = i + 1
      end while
      out = out.trim()
      if left(out, 4) = "the " then out = mid(out, 5)
      if left(out, 2) = "a " then out = mid(out, 3)
      if left(out, 3) = "an " then out = mid(out, 4)
      return out
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
          if ep <> invalid
              season = sceneEpisodeSeason(ep)
              episode = sceneEpisodeNumber(ep)
              if season <= 0 then season = 9999
              if episode <= 0 then episode = 99999
              item = {}
              for each key in ep
                  item[key] = ep[key]
              end for
              item.autoplaySortKey = scenePadAutoplayNumber(season, 4) + ":" + scenePadAutoplayNumber(episode, 5) + ":" + lcase(sceneSafeStr(ep, ["title", "name", "file_name"]))
              sorted.push(item)
          end if
      end for
      sorted.sortBy("autoplaySortKey")
      return sorted
  end function

  function scenePadAutoplayNumber(value as integer, width as integer) as string
      text = stri(value).trim()
      while len(text) < width
          text = "0" + text
      end while
      return text
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
      value = sceneFirstNumber(item, ["seasonNumber", "season_number", "season", "season_num", "season_index"])
      if value > 0 then return value
      info = sceneEpisodeInfoFromItem(item)
      return info.season
  end function

  function sceneEpisodeNumber(item as object) as integer
      value = sceneFirstNumber(item, ["episodeNumber", "episode_number", "episode", "episode_num", "ep_num", "ep_index"])
      if value > 0 then return value
      info = sceneEpisodeInfoFromItem(item)
      return info.episode
  end function

  function sceneEpisodeInfoFromItem(item as object) as object
      fileInfo = sceneFileInfoFromItem(item)
      if fileInfo.path <> "" then return sceneEpisodeInfoFromPath(fileInfo.path)
      title = sceneSafeStr(item, ["title", "name", "file_name"])
      return sceneEpisodeInfoFromPath(title)
  end function

  function sceneEpisodeInfoFromPath(path as string) as object
      name = sceneBaseNameNoExt(path)
      lower = lcase(name)
      season = 0
      episode = 0

      idx = 1
      while idx <= len(lower) - 5
          if mid(lower, idx, 1) = "s" and mid(lower, idx + 3, 1) = "e"
              season = int(val(mid(lower, idx + 1, 2)))
              episode = int(val(mid(lower, idx + 4, 2)))
              if season > 0 or episode > 0 then return { season: season, episode: episode }
          else if mid(lower, idx, 1) = "s" and mid(lower, idx + 4, 1) = "e"
              season = int(val(mid(lower, idx + 1, 2)))
              episode = int(val(mid(lower, idx + 5, 2)))
              if season > 0 or episode > 0 then return { season: season, episode: episode }
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
              if season > 0 or episode > 0 then return { season: season, episode: episode }
          end if
          idx = idx + 1
      end while

      return { season: 0, episode: 0 }
  end function

  function sceneBaseNameNoExt(path as string) as string
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
