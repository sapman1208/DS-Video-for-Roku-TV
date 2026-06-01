sub init()
      m.screenStack = []
      m.artworkCacheTasks = []
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

  function savedProxyBaseUrl(host as string, port as string, useHttps as boolean) as string
      if port = "" then port = "8099"
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
      transcodePort = "8099"
      if reg.exists("transcodePort") then transcodePort = readProtectedSetting(reg, "transcodePort")

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
      m.savedLogin = { host: host, transcodePort: transcodePort, useHttps: useHttps }
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
          m.authData = { sid: response.sid, synoToken: response.synoToken, baseUrl: response.baseUrl, proxyBaseUrl: savedProxyBaseUrl(m.savedLogin.host, m.savedLogin.transcodePort, m.savedLogin.useHttps) }
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
          innerIds = ["videoGrid", "episodeGrid", "categoryList"]
          innerIdx = 0
          while innerIdx < innerIds.count()
              inner = m.currentScreen.findNode(innerIds[innerIdx])
              if inner <> invalid
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

  sub startPrecacheAllArtwork()
      if m.authData = invalid then return
      if m.precacheAllTask <> invalid then return
      task = createObject("roSGNode", "APITask")
      task.request = {
          action: "precacheAllArtwork",
          proxyBaseUrl: m.authData.proxyBaseUrl
      }
      task.observeField("response", "onPrecacheAllDone")
      task.control = "RUN"
      m.precacheAllTask = task
  end sub

  sub onPrecacheAllDone(event as object)
      response = event.getData()
      if response <> invalid
          print "PRECACHE_ALL done downloaded="; response.lookUp("downloaded"); " totalItems="; response.lookUp("totalItems")
      end if
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
      videoGrid.observeField("artworkCacheRequest", "onArtworkCacheRequest")
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
      settingsScreen.observeField("backPressed", "onBackPressed")
      m.top.appendChild(settingsScreen)
      settingsScreen.setFocus(true)
      m.screenStack.push(settingsScreen)
      m.currentScreen = settingsScreen
  end sub

  sub onVideoSelected(event as object)
      data = event.getData()
      if data = invalid then return
      if data.type = "tvshow"
          episodeList = createObject("roSGNode", "EpisodeList")
          episodeList.authData = m.authData
          episodeList.showData = data
          if m.navCategories <> invalid then episodeList.navCategories = m.navCategories
          episodeList.observeField("selectedVideo", "onVideoSelected")
          episodeList.observeField("selectedCategory", "onCategorySelected")
          episodeList.observeField("artworkCacheRequest", "onArtworkCacheRequest")
          episodeList.observeField("backPressed", "onBackPressed")
          m.top.appendChild(episodeList)
          episodeList.setFocus(true)
          m.screenStack.push(episodeList)
          m.currentScreen = episodeList
      else if data.type = "homevideo"
          playVideo(data)
      else
          showVideoDetail(data)
      end if
  end sub

  sub showVideoDetail(videoData as object)
      if videoData <> invalid
          print "SHOW_DETAIL type="; videoData.lookUp("type"); " title="; videoData.lookUp("title")
          startArtworkCacheJob([videoData], 0, true, "detail")
      end if
      detail = createObject("roSGNode", "VideoDetail")
      detail.observeField("playVideo", "onDetailPlay")
      detail.observeField("backPressed", "onBackPressed")
      detail.observeField("listChanged", "onDetailListChanged")
      m.top.appendChild(detail)
      detail.videoData = videoData
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
      player = createObject("roSGNode", "VideoPlayer")
      player.authData = m.authData
      player.videoData = videoData
      player.observeField("playbackResult", "onPlaybackDone")
      m.top.appendChild(player)
      player.setFocus(true)
      m.screenStack.push(player)
      m.currentScreen = player
  end sub

  sub onPlaybackDone(event as object)
      if m.currentScreen = invalid then return
      if m.currentScreen.findNode("videoNode") = invalid then return
      result = event.getData()
      nextVideo = invalid
      if result <> invalid and result.lookUp("reason") = "finished"
          playedVideo = result.lookUp("videoData")
          nextVideo = nextAutoplayEpisode(playedVideo)
      end if
      doBack()
      if m.playStartedFromDetail = true
          if m.currentScreen <> invalid and m.currentScreen.subtype() = "VideoDetail"
              doBack()
          end if
          m.playStartedFromDetail = false
      end if
      if nextVideo <> invalid
          playVideo(nextVideo)
      end if
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
      nextVideo = episodes[nextIdx]
      nextVideo.autoplayEpisodes = episodes
      nextVideo.autoplayIndex = nextIdx
      return nextVideo
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

  sub onArtworkCacheRequest(event as object)
      req = event.getData()
      if req = invalid then return
      items = req.lookUp("items")
      if items = invalid or items.count() = 0 then return

      startArtworkCacheJob(items, req.lookUp("maxItems"), req.lookUp("includeBackdrops"), req.lookUp("source"))
  end sub

  sub startArtworkCacheJob(items as object, maxItems as dynamic, includeBackdrops as dynamic, source as dynamic)
      if items = invalid or items.count() = 0 then return
      sourceText = ""
      if source <> invalid then sourceText = source
      task = createObject("roSGNode", "APITask")
      task.request = {
          action: "cacheArtwork",
          items: items,
          maxItems: maxItems,
          includeBackdrops: includeBackdrops,
          source: sourceText
      }
      task.observeField("response", "onArtworkCacheDone")
      task.control = "RUN"
      m.artworkCacheTasks.push(task)
      pruneArtworkCacheTasks()
  end sub

  sub onArtworkCacheDone(event as object)
      response = event.getData()
      pruneArtworkCacheTasks()
      if response <> invalid and response.lookUp("action") = "cacheArtwork" and response.lookUp("source") = "episodes"
          if m.currentScreen <> invalid and m.currentScreen.subtype() = "EpisodeList"
              m.currentScreen.refreshArtwork = true
          end if
      end if
  end sub

  sub pruneArtworkCacheTasks()
      if m.artworkCacheTasks = invalid then m.artworkCacheTasks = []
      kept = []
      for each task in m.artworkCacheTasks
          if task <> invalid and task.state <> "done" and task.state <> "stop"
              kept.push(task)
          end if
      end for
      while kept.count() > 2
          oldTask = kept[0]
          if oldTask <> invalid then oldTask.control = "STOP"
          kept.delete(0)
      end while
      m.artworkCacheTasks = kept
  end sub
  
