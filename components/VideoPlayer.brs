sub init()
      m.top.observeField("videoData", "onVideoDataSet")
      m.videoNode = m.top.findNode("videoNode")
      m.videoNode.observeField("state", "onVideoStateChange")
      m.videoNode.observeField("errorCode", "onVideoErrorDetail")
      m.videoNode.observeField("errorMsg", "onVideoErrorDetail")
      m.videoNode.observeField("bufferingStatus", "onVideoBuffering")
      hasAvailableSubtitleTracks = m.videoNode.hasField("availableSubtitleTracks")
      hasCurrentSubtitleTrack = m.videoNode.hasField("currentSubtitleTrack")
      print "VIDEO_SUBTITLE_FIELDS available="; hasAvailableSubtitleTracks; " current="; hasCurrentSubtitleTrack
      if hasAvailableSubtitleTracks then m.videoNode.observeField("availableSubtitleTracks", "onAvailableSubtitleTracks")
      if hasCurrentSubtitleTrack then m.videoNode.observeField("currentSubtitleTrack", "onCurrentSubtitleTrack")
      m.top.findNode("progressTimer").observeField("fire", "onProgressTimer")
      m.top.findNode("overlayRefreshTimer").observeField("fire", "onOverlayRefreshTimer")
      m.top.findNode("overlayTimer").observeField("fire", "onOverlayTimer")
      m.top.findNode("resumeSeekTimer").observeField("fire", "onResumeSeekTimer")
      m.top.findNode("captionTimer").observeField("fire", "onCaptionTimer")
      m.hasError = false
      m.hasPlayed = false
      m.reportedDone = false
      m.userStopped = false
      m.captions = []
      m.top.setFocus(true)
  end sub

  sub onVideoDataSet(event as object)
      videoData = event.getData()
      if videoData = invalid then return

      m.hasPlayed = false
      m.reportedDone = false
      m.userStopped = false
      m.seekApplied = false
      m.seekAttempts = 0
      m.lastSyncedPosition = -1
      m.resumeSeekDoneAt = invalid
      m.captions = []
      hideCaptionOverlay()
      m.resumePosition = resumePositionForVideo(videoData)
      if (m.resumePosition = invalid or m.resumePosition <= 0) and m.top.resumePosition <> invalid
          m.resumePosition = int(m.top.resumePosition)
      end if
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
          resumePosition: m.resumePosition,
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
      m.isHlsStream = (fmt = "hls")
      m.streamDebug = ""
      if response.debugInfo <> invalid then m.streamDebug = response.debugInfo
      m.subtitleUrl = ""
      if response.subtitleUrl <> invalid then m.subtitleUrl = response.subtitleUrl
      if m.subtitleUrl <> invalid and m.subtitleUrl <> "" then print "VIDEO_SUBTITLE url="; m.subtitleUrl
      startPlayback(streamUrl, fmt, isLive)
  end sub

  sub fetchSubtitleOverlay()
      if m.subtitleUrl = invalid or m.subtitleUrl = "" then return
      task = createObject("roSGNode", "APITask")
      task.request = {
          action: "fetchTextUrl",
          url: m.subtitleUrl
      }
      task.observeField("response", "onSubtitleTextReady")
      task.control = "RUN"
      m.subtitleTask = task
  end sub

  sub onSubtitleTextReady(event as object)
      if event = invalid then return
      response = event.getData()
      if response = invalid or response.success <> true
          print "SUBTITLE_OVERLAY_FETCH failed"
          return
      end if
      m.captions = parseSrtCaptions(response.text)
      print "SUBTITLE_OVERLAY_LOADED count="; m.captions.count()
      if m.captions.count() > 0 and m.hasPlayed = true
          timer = m.top.findNode("captionTimer")
          if timer <> invalid then timer.control = "start"
      end if
  end sub

  sub startPlayback(streamUrl as string, fmt as string, isLive as boolean)
      m.top.findNode("backgroundRect").visible = false
      m.top.findNode("loadingOverlay").visible = false
      m.top.findNode("loadingLabel").visible = false
      m.top.findNode("videoTitle").visible = false
      m.top.findNode("resumeOverlay").visible = false
      m.resumeHoldActive = false

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
      if m.subtitleUrl <> invalid and m.subtitleUrl <> ""
          content.SubtitleTracks = [
              {
                  TrackName: m.subtitleUrl,
                  Language: "eng",
                  Description: "English"
              }
          ]
          print "VIDEO_SUBTITLE_METADATA count="; content.SubtitleTracks.count()
      end if
      if m.resumePosition <> invalid and m.resumePosition > 0 and fmt <> "hls"
          content.PlayStart = m.resumePosition
          content.playStart = m.resumePosition
      end if

      video.content = content
      if m.subtitleUrl <> invalid and m.subtitleUrl <> ""
          video.globalCaptionMode = "On"
          print "VIDEO_SUBTITLE_NATIVE_READY track="; m.subtitleUrl
      end if
      video.setFocus(true)
      m.hasPlayed = false
      print "VIDEO_PLAY fmt="; fmt
      if m.resumePosition <> invalid and m.resumePosition > 0 then print "VIDEO_RESUME position="; m.resumePosition
      pendingHlsResume = (fmt = "hls" and m.resumePosition <> invalid and m.resumePosition > 0)
      if fmt = "hls" and m.resumePosition <> invalid and m.resumePosition > 0
          beginResumeHold()
      else
          setVideoMuted(false)
      end if
      if m.resumePosition <> invalid and m.resumePosition > 0 and fmt <> "hls"
          video.control = "prebuffer"
      else
          video.control = "play"
      end if
      if pendingHlsResume then beginResumeHold()
      m.streamUrl = streamUrl
      m.streamFmt = fmt
  end sub

  sub beginResumeHold()
      m.resumeHoldActive = true
      m.videoNode.visible = false
      setVideoMuted(true)
      overlay = m.top.findNode("resumeOverlay")
      if overlay <> invalid then overlay.visible = true
  end sub

  sub endResumeHold()
      m.resumeHoldActive = false
      m.videoNode.visible = true
      setVideoMuted(false)
      overlay = m.top.findNode("resumeOverlay")
      if overlay <> invalid then overlay.visible = false
  end sub

  sub setVideoMuted(enabled as boolean)
      video = m.videoNode
      if video = invalid then return
      if video.hasField("mute") then video.mute = enabled
      if video.hasField("muted") then video.muted = enabled
  end sub

  sub onAvailableSubtitleTracks(event as object)
      if event = invalid then return
      tracks = event.getData()
      count = 0
      if tracks <> invalid then count = tracks.count()
      print "VIDEO_SUBTITLE_AVAILABLE count="; count
      if count <= 0 then return
      selected = ""
      for each track in tracks
          if track <> invalid
              trackName = track.lookUp("TrackName")
              if trackName = invalid then trackName = track.lookUp("trackName")
              if trackName = invalid then trackName = track.lookUp("Name")
              if trackName <> invalid and trackName <> ""
                  selected = trackName
                  exit for
              end if
          end if
      end for
      if selected = "" and m.subtitleUrl <> invalid then selected = m.subtitleUrl
      if selected <> ""
          m.videoNode.globalCaptionMode = "On"
          m.videoNode.subtitleTrack = selected
          print "VIDEO_SUBTITLE_SELECT_AVAILABLE track="; selected
      end if
  end sub

  sub onCurrentSubtitleTrack(event as object)
      if event = invalid then return
      print "VIDEO_SUBTITLE_CURRENT track="; event.getData()
  end sub

  sub onVideoStateChange(event as object)
      state = event.getData()
      print "VIDEO_STATE "; state
      if state = "playing"
          m.hasPlayed = true
          applyPendingSeek()
          startResumeSeekTimer()
          if m.captions <> invalid and m.captions.count() > 0
              captionTimer = m.top.findNode("captionTimer")
              if captionTimer <> invalid then captionTimer.control = "start"
          end if
          timer = m.top.findNode("progressTimer")
          if timer <> invalid then timer.control = "start"
      else if state = "buffering"
          if m.resumePosition <> invalid and m.resumePosition > 0 and m.hasPlayed <> true
              m.videoNode.control = "play"
          end if
      else if state = "finished" or state = "stopped"
          timer = m.top.findNode("progressTimer")
          if timer <> invalid then timer.control = "stop"
          captionTimer = m.top.findNode("captionTimer")
          if captionTimer <> invalid then captionTimer.control = "stop"
          seekTimer = m.top.findNode("resumeSeekTimer")
          if seekTimer <> invalid then seekTimer.control = "stop"
          endResumeHold()
          hideCaptionOverlay()
          if state = "finished" and not m.userStopped
              clearResumePosition()
          else
              saveResumePosition()
          end if
          ' Only exit if no error was shown — otherwise user reads the error and presses Back.
          if not m.hasError
              reason = "finished"
              if m.userStopped then reason = "back"
              reportPlaybackDone(reason)
          end if
      else if state = "error"
          m.hasError = true
          endResumeHold()
          hideCaptionOverlay()
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

  sub onProgressTimer(event as object)
      if event = invalid then return
      applyPendingSeek()
      updateCaptionOverlay()
      saveResumePosition()
      if m.top.findNode("controlOverlay").visible then updatePlaybackOverlay()
  end sub

  sub onCaptionTimer(event as object)
      if event = invalid then return
      updateCaptionOverlay()
  end sub

  sub updateCaptionOverlay()
      if m.captions = invalid or m.captions.count() = 0
          hideCaptionOverlay()
          return
      end if
      posMs = int(m.videoNode.position * 1000)
      text = ""
      for each cap in m.captions
          if posMs >= cap.startMs and posMs <= cap.endMs
              text = cap.text
              exit for
          end if
      end for
      overlay = m.top.findNode("captionOverlay")
      label = m.top.findNode("captionLabel")
      if text = ""
          if overlay <> invalid then overlay.visible = false
          return
      end if
      if label <> invalid then label.text = text
      if overlay <> invalid then overlay.visible = true
  end sub

  sub hideCaptionOverlay()
      overlay = m.top.findNode("captionOverlay")
      if overlay <> invalid then overlay.visible = false
      label = m.top.findNode("captionLabel")
      if label <> invalid then label.text = ""
  end sub

  function parseSrtCaptions(text as string) as object
      captions = []
      if text = invalid or text = "" then return captions
      newlineRx = createObject("roRegex", "\r\n|\n|\r", "")
      tagRx = createObject("roRegex", "<[^>]+>", "")
      lines = newlineRx.split(text)
      i = 0
      while i < lines.count()
          line = lines[i].trim()
          if line = ""
              i = i + 1
          else if instr(1, line, "-->") > 0
              timeLine = line
              arrow = instr(1, timeLine, "-->")
              startText = left(timeLine, arrow - 1).trim()
              endText = mid(timeLine, arrow + 3).trim()
              spaceAt = instr(1, endText, " ")
              if spaceAt > 0 then endText = left(endText, spaceAt - 1)
              i = i + 1
              captionText = ""
              while i < lines.count() and lines[i].trim() <> ""
                  cleanLine = tagRx.replaceAll(lines[i].trim(), "")
                  if captionText <> "" then captionText = captionText + chr(10)
                  captionText = captionText + cleanLine
                  i = i + 1
              end while
              if captionText <> ""
                  captions.push({
                      startMs: srtTimeToMs(startText),
                      endMs: srtTimeToMs(endText),
                      text: captionText
                  })
              end if
          else
              i = i + 1
          end if
      end while
      return captions
  end function

  function srtTimeToMs(value as string) as integer
      t = value.trim()
      if len(t) < 12 then return 0
      h = val(left(t, 2))
      m = val(mid(t, 4, 2))
      s = val(mid(t, 7, 2))
      ms = val(mid(t, 10, 3))
      return ((h * 3600) + (m * 60) + s) * 1000 + ms
  end function

  sub startResumeSeekTimer()
      if m.seekApplied = true then return
      if m.resumePosition = invalid or m.resumePosition <= 0 then return
      timer = m.top.findNode("resumeSeekTimer")
      if timer = invalid then return
      timer.control = "start"
  end sub

  sub onResumeSeekTimer(event as object)
      if event = invalid then return
      applyPendingSeek()
  end sub

  sub applyPendingSeek()
      if m.seekApplied = true then return
      if m.resumePosition = invalid or m.resumePosition <= 0 then return
      currentPos = int(m.videoNode.position)
      if currentPos >= m.resumePosition - 5
          m.seekApplied = true
          m.resumeSeekDoneAt = createObject("roTimespan")
          m.resumeSeekDoneAt.mark()
          timer = m.top.findNode("resumeSeekTimer")
          if timer <> invalid then timer.control = "stop"
          endResumeHold()
          print "VIDEO_SEEK_DONE position="; currentPos; " target="; m.resumePosition
          return
      end if
      maxSeekAttempts = 24
      if m.isHlsStream = true then maxSeekAttempts = 480
      if m.seekAttempts >= maxSeekAttempts
          m.seekApplied = true
          m.resumeSeekDoneAt = invalid
          timer = m.top.findNode("resumeSeekTimer")
          if timer <> invalid then timer.control = "stop"
          endResumeHold()
          print "VIDEO_SEEK_GIVEUP position="; currentPos; " target="; m.resumePosition
          return
      end if
      m.seekAttempts = m.seekAttempts + 1
      m.videoNode.seek = m.resumePosition
      print "VIDEO_SEEK attempt="; m.seekAttempts; " target="; m.resumePosition; " current="; currentPos
  end sub

  sub showPlaybackOverlay()
      updatePlaybackOverlay()
      overlay = m.top.findNode("controlOverlay")
      overlay.visible = true
      refreshTimer = m.top.findNode("overlayRefreshTimer")
      if refreshTimer <> invalid then refreshTimer.control = "start"
      timer = m.top.findNode("overlayTimer")
      timer.control = "stop"
      timer.control = "start"
  end sub

  sub onOverlayRefreshTimer(event as object)
      if event = invalid then return
      if m.top.findNode("controlOverlay").visible
          updatePlaybackOverlay()
      else
          timer = m.top.findNode("overlayRefreshTimer")
          if timer <> invalid then timer.control = "stop"
      end if
  end sub

  sub updatePlaybackOverlay()
      title = ""
      videoData = m.top.videoData
      if videoData <> invalid and videoData.title <> invalid then title = videoData.title
      m.top.findNode("overlayTitle").text = title

      playbackPos = int(m.videoNode.position)
      duration = int(m.videoNode.duration)
      timeText = formatPlaybackTime(playbackPos)
      if duration > 0 then timeText = timeText + " / " + formatPlaybackTime(duration)
      m.top.findNode("overlayTime").text = timeText

      progressWidth = 1
      if duration > 0
          progressWidth = int((playbackPos / duration) * 1720)
          if progressWidth < 1 then progressWidth = 1
          if progressWidth > 1720 then progressWidth = 1720
      end if
      m.top.findNode("overlayProgress").width = progressWidth
  end sub

  sub onOverlayTimer(event as object)
      if event = invalid then return
      m.top.findNode("controlOverlay").visible = false
      refreshTimer = m.top.findNode("overlayRefreshTimer")
      if refreshTimer <> invalid then refreshTimer.control = "stop"
  end sub

  function formatPlaybackTime(seconds as integer) as string
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

  function resumePositionForVideo(videoData as object) as integer
      if videoData = invalid then return 0
      value = videoData.lookUp("resumePosition")
      if value = invalid then return 0
      t = type(value)
      if t = "roInteger" or t = "Integer" then return value
      if t = "roFloat" or t = "Float" then return int(value)
      if t = "roString" or t = "String" then return val(value)
      return 0
  end function

  function resumeKeyForVideo(videoData as object) as string
      if videoData = invalid then return ""
      if videoData.filePath <> invalid and videoData.filePath <> "" then return "path:" + videoData.filePath
      if videoData.fileId <> invalid and videoData.fileId <> "" then return "file:" + safeDynamicString(videoData.fileId)
      if videoData.id <> invalid and videoData.id <> "" then return "id:" + safeDynamicString(videoData.id)
      return ""
  end function

  function safeDynamicString(value as dynamic) as string
      if value = invalid then return ""
      t = type(value)
      if t = "roString" or t = "String" then return value
      if t = "roInteger" or t = "Integer" then return stri(value).trim()
      if t = "roFloat" or t = "Float" then return stri(int(value)).trim()
      return ""
  end function

  sub saveResumePosition()
      if not m.hasPlayed then return
      if m.resumePosition <> invalid and m.resumePosition > 0 and m.seekApplied <> true then return
      key = resumeKeyForVideo(m.top.videoData)
      if key = "" then return
      playbackPos = effectivePlaybackPosition()
      if playbackPos < 30 then return
      duration = int(m.videoNode.duration)
      if duration > 0 and playbackPos > duration - 90
          clearResumePosition()
          return
      end if
      reg = createObject("roRegistrySection", "DSVideoResume")
      reg.write(key, stri(playbackPos).trim())
      reg.flush()
      syncWatchStatus(playbackPos)
  end sub

  function effectivePlaybackPosition() as integer
      playbackPos = int(m.videoNode.position)
      if m.isHlsStream = true and m.resumePosition <> invalid and m.resumePosition > 0 and m.seekApplied = true and m.resumeSeekDoneAt <> invalid
          elapsed = int(m.resumeSeekDoneAt.totalMilliseconds() / 1000)
          resumeBasedPos = int(m.resumePosition) + elapsed
          if resumeBasedPos > playbackPos then playbackPos = resumeBasedPos
      end if
      return playbackPos
  end function

  sub clearResumePosition()
      key = resumeKeyForVideo(m.top.videoData)
      if key = "" then return
      reg = createObject("roRegistrySection", "DSVideoResume")
      if reg.exists(key)
          reg.delete(key)
          reg.flush()
      end if
      syncWatchStatus(0)
  end sub

  sub syncWatchStatus(position as integer)
      videoData = m.top.videoData
      if videoData = invalid then return
      authData = videoData.authData
      if authData = invalid then authData = m.top.authData
      if authData = invalid then return

      if position > 0 and m.lastSyncedPosition <> invalid and m.lastSyncedPosition >= 0
          delta = position - m.lastSyncedPosition
          if delta < 0 then delta = -delta
          if delta < 10 then return
      end if
      m.lastSyncedPosition = position

      task = createObject("roSGNode", "APITask")
      task.request = {
          action: "updateWatchStatus",
          baseUrl: authData.baseUrl,
          proxyBaseUrl: authData.proxyBaseUrl,
          sid: authData.sid,
          synoToken: authData.synoToken,
          videoId: videoData.id,
          videoType: videoData.type,
          filePath: videoData.filePath,
          position: position
      }
      task.observeField("response", "onWatchStatusSynced")
      task.control = "RUN"
      m.watchStatusTask = task
  end sub

  sub onWatchStatusSynced(event as object)
      if event = invalid then return
      response = event.getData()
      if response = invalid then return
      if response.success = true
          print "WATCH_STATUS_SYNC ok"
      else if response.error <> invalid
          print "WATCH_STATUS_SYNC error="; response.error
          if response.detail <> invalid then print "WATCH_STATUS_SYNC detail="; response.detail
      end if
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
      else if key = "up" or key = "left" or key = "right" or key = "OK" or key = "play"
          showPlaybackOverlay()
          m.videoNode.setFocus(true)
          return false
      end if
      return false
  end function
  
