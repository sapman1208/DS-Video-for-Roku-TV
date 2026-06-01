sub init()
      m.top.observeField("videoData", "onVideoDataSet")
      m.videoNode = m.top.findNode("videoNode")
      m.videoNode.observeField("state", "onVideoStateChange")
      m.videoNode.observeField("errorCode", "onVideoErrorDetail")
      m.videoNode.observeField("errorMsg", "onVideoErrorDetail")
      m.videoNode.observeField("bufferingStatus", "onVideoBuffering")
      m.hasError = false
      m.hasPlayed = false
      m.reportedDone = false
      m.userStopped = false
      m.top.setFocus(true)
  end sub

  sub onVideoDataSet(event as object)
      videoData = event.getData()
      if videoData = invalid then return

      m.hasPlayed = false
      m.reportedDone = false
      m.userStopped = false
      requestStreamUrl()
  end sub

  sub requestStreamUrl()
      videoData = m.top.videoData
      if videoData = invalid then return
      authData = videoData.authData
      if authData = invalid then return

      fileId = videoData.fileId
      filePath = videoData.filePath
      videoId = videoData.id
      if fileId = invalid and videoId = invalid and (filePath = invalid or filePath = "")
          showError("No file ID or file path for this video.")
          return
      end if

      m.top.findNode("loadingOverlay").visible = true
      m.top.findNode("loadingLabel").visible = false
      m.top.findNode("videoTitle").visible = false
      m.top.findNode("errorLabel").visible = false
      m.top.findNode("backgroundRect").visible = true
      m.hasError = false

      task = createObject("roSGNode", "APITask")
      task.request = {
          action: "getStreamUrl",
          baseUrl: authData.baseUrl,
          proxyBaseUrl: authData.proxyBaseUrl,
          sid: authData.sid,
          synoToken: authData.synoToken,
          fileId: fileId,
          mapperId: videoData.mapperId,
          filePath: videoData.filePath,
          id: videoData.id,
          title: videoData.title,
          originalAvailable: videoData.originalAvailable,
          mediaType: videoData.type
      }
      task.observeField("response", "onStreamUrlReady")
      task.control = "RUN"
      m.streamTask = task
  end sub

  sub onStreamUrlReady(event as object)
      response = event.getData()
      if response = invalid
          showError("No response from stream task.")
          return
      end if
      if response.success <> true
          errMsg = "Stream open failed."
          if response.error <> invalid then errMsg = response.error
          detail = ""
          if response.detail <> invalid then detail = chr(10) + left(response.detail, 1500)
          showError(errMsg + detail)
          return
      end if
      streamUrl = response.streamUrl
      if streamUrl = invalid or streamUrl = ""
          showError("Empty stream URL.")
          return
      end if
      fmt = response.streamFormat
      if fmt = invalid or fmt = "" then fmt = "mp4"
      isLive = false
      if response.isLive = true then isLive = true
      m.streamDebug = ""
      if response.debugInfo <> invalid then m.streamDebug = response.debugInfo
      startPlayback(streamUrl, fmt, isLive)
  end sub

  sub startPlayback(streamUrl as string, fmt as string, isLive as boolean)
      m.top.findNode("backgroundRect").visible = false
      m.top.findNode("loadingOverlay").visible = false
      m.top.findNode("loadingLabel").visible = false
      m.top.findNode("videoTitle").visible = false

      video = m.videoNode
      video.width = 1920
      video.height = 1080
      video.translation = [0, 0]
      video.visible = true
      video.enableUI = true

      content = createObject("roSGNode", "ContentNode")
      content.url = streamUrl
      content.streamFormat = fmt
      if fmt = "hls" and isLive
          content.Live = true
      end if
      content.addFields({
          HttpCertificatesFile: "common:/certs/ca-bundle.crt",
          HttpVerifyPeer: false,
          HttpVerifyHost: false
      })

      videoData = m.top.videoData
      if videoData <> invalid and videoData.title <> invalid
          content.title = videoData.title
      end if

      video.content = content
      video.setFocus(true)
      m.hasPlayed = false
      print "VIDEO_PLAY fmt="; fmt
      video.control = "play"
      m.streamUrl = streamUrl
      m.streamFmt = fmt
  end sub

  sub onVideoStateChange(event as object)
      state = event.getData()
      print "VIDEO_STATE "; state
      if state = "playing"
          m.hasPlayed = true
      else if state = "finished" or state = "stopped"
          ' Only exit if no error was shown — otherwise user reads the error and presses Back.
          if not m.hasError
              reason = "finished"
              if m.userStopped then reason = "back"
              reportPlaybackDone(reason)
          end if
      else if state = "error"
          m.hasError = true
          dbg = ""
          if m.streamDebug <> invalid and m.streamDebug <> "" then dbg = chr(10) + m.streamDebug
          showError("Playback error (fmt=" + m.streamFmt + ")." + dbg)
      end if
  end sub

  sub reportPlaybackDone(reason as string)
      if m.reportedDone then return
      m.reportedDone = true
      m.top.playbackResult = {
          reason: reason,
          videoData: m.top.videoData
      }
      m.top.playbackDone = true
  end sub

  sub onVideoErrorDetail(event as object)
      if event = invalid then return
      print "VIDEO_ERROR_DETAIL code="; m.videoNode.errorCode; " msg="; m.videoNode.errorMsg
  end sub

  sub onVideoBuffering(event as object)
      print "VIDEO_BUFFER "; event.getData()
  end sub

  sub showError(msg as string)
      m.hasError = true
      m.top.findNode("backgroundRect").visible = true
      m.top.findNode("loadingOverlay").visible = false
      m.top.findNode("loadingLabel").visible = false
      m.top.findNode("videoTitle").visible = false
      errLabel = m.top.findNode("errorLabel")
      errLabel.text = msg + chr(10) + chr(10) + "Press Back to return."
      errLabel.visible = true
      m.top.setFocus(true)
  end sub

  function onKeyEvent(key as string, press as boolean) as boolean
      if not press then return false
      if key = "back"
          m.userStopped = true
          m.videoNode.control = "stop"
          reportPlaybackDone("back")
          return true
      else if key = "OK" or key = "play"
          m.videoNode.setFocus(true)
          return false
      end if
      return false
  end function
  
