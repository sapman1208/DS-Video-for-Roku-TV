sub init()
    m.actions = ["Play", "Favorite", "Watch List", "Share"]
    m.actionOverrides = {}
    m.movieMetadataTask = invalid
    m.movieMetadataCache = {}
    m.detailStateTask = invalid
    m.detailData = invalid
    m.waitForDetailState = false
    m.waitForMovieMetadata = false
    m.pendingMovieSummary = ""
    grid = m.top.findNode("actionGrid")
    grid.observeField("itemSelected", "onActionSelected")
    grid.observeField("focus", "onActionFocus")
    ratingGrid = m.top.findNode("ratingGrid")
    ratingGrid.observeField("itemSelected", "onRatingSelected")
    ratingGrid.observeField("focus", "onRatingFocus")
    m.top.findNode("movieSummaryTimer").observeField("fire", "onMovieSummaryTimer")
    m.top.findNode("detailRevealTimer").observeField("fire", "onDetailRevealTimer")
    m.top.findNode("backdrop").observeField("loadStatus", "onBackdropLoadStatus")
    m.top.observeField("videoData", "onVideoDataSet")
    m.top.opacity = 0
end sub

sub populateActions()
    content = createObject("roSGNode", "ContentNode")
    idx = 0
    for each action in m.actions
        node = content.createChild("ContentNode")
        label = action
        checked = false
        if idx > 0
            checked = isActionChecked(idx)
        end if
        node.title = label
        checkedText = "false"
        if checked then checkedText = "true"
        node.addFields({ rawTitle: action, checked: checkedText })
        icon = actionIconUri(action)
        if icon <> "" then node.addFields({ iconUri: icon })
        idx = idx + 1
    end for
    grid = m.top.findNode("actionGrid")
    grid.content = invalid
    grid.content = content
end sub

function actionIconUri(action as string) as string
    if action = "Play" then return "pkg:/images/detail-play.png"
    if action = "Favorite" then return "pkg:/images/playlist-favorites.png"
    if action = "Watch List" then return "pkg:/images/playlist-watchlist.png"
    if action = "Share" then return "pkg:/images/playlist-shared.png"
    return ""
end function

sub onVideoDataSet(event as object)
    data = event.getData()
    if data = invalid then return
    m.detailData = data
    m.detailRevealed = false
    m.waitForBackdrop = false
    m.waitForDetailState = shouldWaitForDetailState(data)
    m.waitForMovieMetadata = false
    m.top.sourceListRemoved = false
    m.ratingOverride = invalid
    m.ratingFocusIndex = -1
    m.top.opacity = 0
    print "DETAIL_SET type="; data.lookUp("type"); " title="; data.lookUp("title"); " rating="; data.lookUp("rating")
    title = ""
    if data.title <> invalid then title = data.title
    if title = "" then title = "Video"
    m.top.findNode("titleLabel").text = title
    meta = ""
    if data.type <> invalid
        if data.type = "episode"
            meta = episodeMetaText(data)
        else if data.type = "movie"
            meta = ""
        else if data.type = "homevideo"
            if data.sourceCategory <> invalid and data.sourceCategory = "tvrecordings"
                meta = "TV Recording"
            else
                meta = "Home Video"
            end if
        else
            meta = data.type
        end if
    end if
    if data.originalAvailable <> invalid and data.originalAvailable <> ""
        if data.type <> invalid and (data.type = "episode" or data.type = "homevideo")
            m.top.findNode("dateLabel").text = data.originalAvailable
            m.top.findNode("dateLabel").visible = true
        else
            m.top.findNode("dateLabel").visible = false
            m.top.findNode("dateLabel").text = ""
            if meta <> "" then meta = meta + "   "
            meta = meta + data.originalAvailable
        end if
    else
        m.top.findNode("dateLabel").visible = false
        m.top.findNode("dateLabel").text = ""
    end if
    m.top.findNode("metaLabel").text = meta
    summary = ""
    if data.summary <> invalid then summary = data.summary
    if summary = "" and data.description <> invalid then summary = data.description
    if summary <> "" and title <> "" and lcase(summary.trim()) = lcase(title.trim()) then summary = ""
    currentRating = firstNumericField(data, ["rating", "rate", "user_rating", "userRating", "my_rating", "myRating"])
    movieDateNeedsMetadata = false
    if data.type <> invalid and data.type = "movie"
        currentDate = ""
        if data.originalAvailable <> invalid then currentDate = data.originalAvailable
        if currentDate = "" or len(currentDate) <= 4 then movieDateNeedsMetadata = true
    end if
    needsMovieMetadata = data.type <> invalid and data.type = "movie" and (len(summary) < 220 or currentRating <= 0 or movieDateNeedsMetadata)
    m.movieFallbackSummary = ""
    if needsMovieMetadata and summary <> ""
        m.movieFallbackSummary = summary
    end if
    if summary = "" and not needsMovieMetadata and not (data.type <> invalid and data.type = "homevideo") then summary = "No description available."
    m.pendingMovieSummary = ""
    poster = ""
	    if data.posterUrl <> invalid then poster = data.posterUrl
	    backdrop = ""
	    if data.backdropUrl <> invalid then backdrop = data.backdropUrl
    m.detailPosterFallbackUrl = poster
	    print "DETAIL_ARTWORK type="; data.lookUp("type"); " title="; title; " posterSource="; artworkSourceFromUrl(poster); " backdropSource="; artworkSourceFromUrl(backdrop); " backdropUrl="; left(backdrop, 120)
	    configurePosterFrame(data)
    if poster <> ""
        m.top.findNode("poster").uri = detailArtworkUrl(poster)
        m.top.findNode("poster").visible = true
        m.top.findNode("posterFallback").visible = false
    else
        m.top.findNode("poster").visible = false
        m.top.findNode("posterFallback").visible = true
    end if
    if backdrop <> ""
        m.waitForBackdrop = true
        m.top.findNode("backdrop").uri = detailArtworkUrl(backdrop)
        m.top.findNode("backdrop").visible = true
    else
        m.top.findNode("backdrop").visible = false
    end if
    m.top.findNode("summaryLabel").text = summary
    applySummaryFit(summary, data)
    if needsMovieMetadata
        startMovieMetadataFetch(data)
    end if
    populateRatingStars()
    if hasWatchedState(data)
        populateWatchedState()
    else
        hideWatchedState()
    end if
    populateActions()
    m.top.findNode("actionGrid").jumpToItem = 0
    m.top.findNode("actionGrid").setFocus(true)
    m.focusArea = "actions"
    startDetailStateFetch(data)
    startDetailRevealTimer()
end sub

function shouldWaitForDetailState(data as object) as boolean
    if data = invalid then return false
    if data.authData = invalid then return false
    if data.type = invalid then return false
    if data.type = "movie" then return true
    if data.type = "episode" then return true
    if data.type = "tvshow" then return true
    return false
end function

function detailArtworkUrl(url as dynamic) as string
    if url = invalid then return ""
    if type(url) <> "roString" and type(url) <> "String" then return ""
    lower = lcase(url)
    if left(lower, 7) <> "http://" and left(lower, 8) <> "https://" then return url
    sep = "?"
    if instr(1, url, "?") > 0 then sep = "&"
    return url + sep + "roku_detail_img=1"
end function

sub startDetailRevealTimer()
    timer = m.top.findNode("detailRevealTimer")
    if timer = invalid then return
    timer.control = "stop"
    if m.waitForDetailState = true
        timer.duration = detailSettleDuration()
    else
        timer.duration = 0.32
    end if
    timer.control = "start"
end sub

function detailSettleDuration() as float
    return 0.75
end function

sub onDetailRevealTimer(event as object)
    if m.waitForDetailState = true then m.waitForDetailState = false
    if m.waitForBackdrop = true then m.waitForBackdrop = false
    revealDetail()
end sub

sub onBackdropLoadStatus(event as object)
    if event = invalid then return
    if m.waitForBackdrop <> true then return
    status = event.getData()
    if status = "ready"
        m.waitForBackdrop = false
        revealDetail()
    end if
    if status = "failed" or status = "invalid"
        fallback = ""
        if m.detailPosterFallbackUrl <> invalid then fallback = m.detailPosterFallbackUrl
        if fallback <> ""
            m.waitForBackdrop = false
            m.top.findNode("backdrop").uri = detailArtworkUrl(fallback)
            m.top.findNode("backdrop").visible = true
            revealDetail()
        end if
    end if
end sub

sub revealDetail()
    if m.detailRevealed = true then return
    if m.waitForDetailState = true then return
    if m.waitForBackdrop = true then return
    m.detailRevealed = true
    timer = m.top.findNode("detailRevealTimer")
    if timer <> invalid then timer.control = "stop"
    m.top.opacity = 1
end sub

sub startMovieMetadataFetch(data as object)
    if data = invalid or data.authData = invalid
        m.waitForMovieMetadata = false
        return
    end if
    movieId = ""
    if data.id <> invalid then movieId = safeIntText(data.id)
    if movieId = "" or movieId = "0"
        m.waitForMovieMetadata = false
        return
    end if
    cached = invalid
    if m.movieMetadataCache <> invalid then cached = m.movieMetadataCache.lookUp(movieId)
    if cached <> invalid
        print "MOVIE_METADATA_CACHE_HIT id="; movieId
        applyMovieMetadataResponse(cached)
        m.waitForMovieMetadata = false
        return
    end if
    ids = []
    addDetailStateId(ids, data.videoStationId)
    addDetailStateId(ids, data.id)
    addDetailStateId(ids, data.mapperId)
    addDetailStateId(ids, data.fileId)
    task = createObject("roSGNode", "APITask")
    task.observeField("response", "onMovieMetadata")
    task.request = {
        action: "movieMetadata",
        baseUrl: data.authData.baseUrl,
        sid: data.authData.sid,
        synoToken: data.authData.synoToken,
        id: movieId,
        ids: ids,
        title: data.title,
        filePath: data.filePath,
        originalAvailable: data.originalAvailable
    }
    m.movieMetadataTask = task
    print "MOVIE_METADATA_REQUEST id="; movieId; " candidates="; ids.count(); " title="; data.title
    task.control = "RUN"
end sub

sub onMovieMetadata(event as object)
    response = event.getData()
    if response = invalid
        m.waitForMovieMetadata = false
        revealDetail()
        return
    end if
    if m.detailData = invalid then m.detailData = m.top.videoData
    if not movieMetadataResponseMatchesDetail(response)
        print "MOVIE_METADATA_STALE responseId="; response.lookUp("id"); " currentId="; safeIntText(m.detailData.lookUp("id"))
        m.waitForMovieMetadata = false
        revealDetail()
        return
    end if
    applyMovieMetadataResponse(response)
    cacheMovieMetadataResponse(response)
    summary = ""
    if response.summary <> invalid then summary = response.summary
    if summary = "" and m.movieFallbackSummary <> invalid then summary = m.movieFallbackSummary
    releaseDate = ""
    if response.releaseDate <> invalid then releaseDate = response.releaseDate
    m.pendingMovieSummary = ""
    m.waitForMovieMetadata = false
    revealDetail()
    print "MOVIE_METADATA_APPLY id="; response.lookUp("id"); " source="; response.lookUp("source"); " summaryLen="; len(summary); " releaseDate="; releaseDate
end sub

sub applyMovieMetadataResponse(response as object)
    if response = invalid then return
    if m.detailData = invalid then m.detailData = m.top.videoData
    if m.detailData = invalid then return
    if response.rating <> invalid and response.rating > 0
        m.detailData.addReplace("rating", response.rating)
        populateRatingStars()
    end if
    releaseDate = ""
    if response.releaseDate <> invalid then releaseDate = response.releaseDate
    if releaseDate <> ""
        m.detailData.addReplace("originalAvailable", releaseDate)
        updateMovieMetaLine(releaseDate)
    end if
    summary = ""
    if response.summary <> invalid then summary = response.summary
    if summary = "" and m.movieFallbackSummary <> invalid then summary = m.movieFallbackSummary
    if summary <> ""
        m.detailData.addReplace("summary", summary)
        m.top.findNode("summaryLabel").text = summary
        applySummaryFit(summary, m.detailData)
    end if
end sub

sub cacheMovieMetadataResponse(response as object)
    if response = invalid then return
    if m.movieMetadataCache = invalid then m.movieMetadataCache = {}
    idText = safeIntText(response.lookUp("id"))
    if idText = "" or idText = "0" then return
    m.movieMetadataCache.addReplace(idText, response)
end sub

function movieMetadataResponseMatchesDetail(response as object) as boolean
    if response = invalid then return false
    if m.detailData = invalid then return false
    responseId = safeIntText(response.lookUp("id"))
    if responseId = "" or responseId = "0" then return true
    ids = []
    addDetailStateId(ids, m.detailData.id)
    addDetailStateId(ids, m.detailData.videoStationId)
    addDetailStateId(ids, m.detailData.mapperId)
    addDetailStateId(ids, m.detailData.fileId)
    for each id in ids
        if id = responseId then return true
    end for
    return false
end function

sub updateMovieMetaLine(releaseDate as string)
    if releaseDate = "" then return
    if m.detailData = invalid then return
    if m.detailData.type = invalid or m.detailData.type <> "movie" then return
    m.top.findNode("dateLabel").visible = false
    m.top.findNode("dateLabel").text = ""
    m.top.findNode("metaLabel").text = releaseDate
end sub

sub onMovieSummaryTimer(event as object)
    if m.pendingMovieSummary = invalid or m.pendingMovieSummary = "" then return
    m.top.findNode("summaryLabel").text = m.pendingMovieSummary
    applySummaryFit(m.pendingMovieSummary, m.detailData)
    m.pendingMovieSummary = ""
end sub

sub startDetailStateFetch(data as object)
    if data = invalid or data.authData = invalid then return
    videoId = videoIdForSync(data)
    if videoId = "" or videoId = "0"
        m.waitForDetailState = false
        return
    end if
    ids = []
    addDetailStateId(ids, data.videoStationId)
    addDetailStateId(ids, data.id)
    addDetailStateId(ids, data.mapperId)
    addDetailStateId(ids, data.fileId)
    task = createObject("roSGNode", "APITask")
    task.observeField("response", "onDetailState")
    task.request = {
        action: "detailState",
        baseUrl: data.authData.baseUrl,
        sid: data.authData.sid,
        synoToken: data.authData.synoToken,
        videoType: data.type,
        videoId: videoId,
        videoIds: ids
    }
    m.detailStateTask = task
    print "DETAIL_STATE_REQUEST type="; data.lookUp("type"); " id="; videoId; " candidates="; ids.count()
    task.control = "RUN"
end sub

sub addDetailStateId(ids as object, value as dynamic)
    idText = safeIntText(value)
    if idText = "" or idText = "0" then return
    for each existing in ids
        if existing = idText then return
    end for
    ids.push(idText)
end sub

sub onDetailState(event as object)
    response = event.getData()
    if response = invalid
        m.waitForDetailState = false
        revealDetail()
        return
    end if
    print "DETAIL_STATE success="; response.lookUp("success"); " rating="; response.lookUp("rating"); " watchedRatio="; response.lookUp("watchedRatio"); " hasWatched="; response.lookUp("hasWatched"); " error="; response.lookUp("error")
    if response.success <> true
        m.waitForDetailState = false
        revealDetail()
        return
    end if
    if m.detailData = invalid then m.detailData = m.top.videoData
    if m.detailData = invalid then return
    if response.rating <> invalid and response.rating > 0
        m.detailData.addReplace("rating", response.rating)
        populateRatingStars()
    end if
    summary = ""
    if response.summary <> invalid then summary = response.summary
    if summary <> ""
        currentSummary = m.top.findNode("summaryLabel").text
        shouldApply = currentSummary = ""
        if currentSummary = "No description available." then shouldApply = true
        if len(summary) > len(currentSummary) then shouldApply = true
        if shouldApply
            m.detailData.addReplace("summary", summary)
            m.top.findNode("summaryLabel").text = summary
            applySummaryFit(summary, m.detailData)
        end if
    end if
    if response.showBackdropUrl <> invalid and response.showBackdropUrl <> ""
        m.detailData.addReplace("backdropUrl", response.showBackdropUrl)
        m.waitForBackdrop = true
        m.top.findNode("backdrop").uri = detailArtworkUrl(response.showBackdropUrl)
        m.top.findNode("backdrop").visible = true
        print "DETAIL_BACKDROP_REFRESH source="; artworkSourceFromUrl(response.showBackdropUrl)
    end if
    if response.hasWatched = true and response.watchedRatio <> invalid
        m.detailData.addReplace("watchedRatio", response.watchedRatio)
        if response.watchedRatio = 0 then m.detailData.addReplace("fileWatched", false)
        populateWatchedState()
    end if
    if m.actionOverrides <> invalid
        if response.favorite <> invalid and not hasPendingCollectionOverride("favorites") then m.actionOverrides.addReplace("favorites", response.favorite = true)
        if response.watchlist <> invalid and not hasPendingCollectionOverride("watchlist") then m.actionOverrides.addReplace("watchlist", response.watchlist = true)
        populateActions()
        restoreActionFocus(0)
    end if
    m.waitForDetailState = false
    revealDetail()
end sub

function episodeMetaText(data as object) as string
    if data.episodeMeta <> invalid and data.episodeMeta <> "" then return data.episodeMeta
    seasonText = firstIntText(data, ["seasonNumber", "season_number", "seasonText", "season", "season_num", "season_index"])
    episodeText = firstIntText(data, ["episodeNumber", "episode_number", "episodeText", "episode", "episode_num", "ep_num", "ep_index"])
    if seasonText <> "" and seasonText <> "0" and episodeText <> "" and episodeText <> "0"
        return "Season " + seasonText + " - Episode " + episodeText
    end if
    if episodeText <> "" and episodeText <> "0" then return "Episode " + episodeText
    return "Episode"
end function

function artworkSourceFromUrl(url as dynamic) as string
    if url = invalid or url = "" then return "none"
    if type(url) <> "roString" and type(url) <> "String" then return "none"
    lower = lcase(url)
    if left(lower, 9) = "cachefs:/" then return "cachefs"
    if instr(1, lower, "syno.videostation2.backdrop") > 0 then return "synology-backdrop"
    if instr(1, lower, "syno.videostation2.poster") > 0 then return "synology-v2-poster"
    if instr(1, lower, "poster.cgi") > 0 then return "synology-poster"
    if left(lower, 7) = "http://" or left(lower, 8) = "https://" then return "remote"
    return "saved"
end function

function firstIntText(item as object, keys as object) as string
    if item = invalid then return ""
    for each key in keys
        value = item.lookUp(key)
        text = safeIntText(value)
        if text <> "" and text <> "0" then return text
    end for
    return ""
end function

sub configurePosterFrame(data as object)
    poster = m.top.findNode("poster")
    fallback = m.top.findNode("posterFallback")

    useWideFrame = false
    if data <> invalid and data.type <> invalid
        if data.type = "episode" then useWideFrame = true
        if data.type = "homevideo" then useWideFrame = true
    end if

    if useWideFrame
        poster.width = 630
        poster.height = 354
        poster.translation = [70, 230]
        poster.loadDisplayMode = "scaleToFit"

        fallback.width = 630
        fallback.height = 354
        fallback.translation = [70, 230]

        m.top.findNode("titleLabel").translation = [760, 150]
        m.top.findNode("titleLabel").width = 1040
        m.top.findNode("metaLabel").translation = [760, 230]
        m.top.findNode("metaLabel").width = 1000
        m.top.findNode("dateLabel").translation = [760, 285]
        m.top.findNode("dateLabel").width = 1000
        m.top.findNode("ratingLabel").translation = [760, 336]
        m.top.findNode("ratingGrid").translation = [884, 330]
        m.top.findNode("summaryLabel").translation = [760, 410]
        m.top.findNode("summaryLabel").width = 1040
        m.top.findNode("summaryLabel").height = 390
        m.top.findNode("summaryLabel").font = "font:SmallSystemFont"
        m.top.findNode("actionGrid").translation = [760, 835]
        m.top.findNode("watchedStateLabel").translation = [70, 600]
        m.top.findNode("watchedStateLabel").width = 630
        m.top.findNode("statusLabel").translation = [760, 965]
    else
        poster.width = 360
        poster.height = 540
        poster.translation = [110, 150]
        poster.loadDisplayMode = "scaleToFill"

        fallback.width = 360
        fallback.height = 540
        fallback.translation = [110, 150]

        m.top.findNode("titleLabel").translation = [540, 150]
        m.top.findNode("titleLabel").width = 1180
        m.top.findNode("metaLabel").translation = [540, 230]
        m.top.findNode("metaLabel").width = 1100
        m.top.findNode("dateLabel").translation = [540, 285]
        m.top.findNode("dateLabel").width = 1100
        m.top.findNode("ratingLabel").translation = [540, 288]
        m.top.findNode("ratingGrid").translation = [664, 282]
        m.top.findNode("summaryLabel").translation = [540, 386]
        m.top.findNode("summaryLabel").width = 1180
        m.top.findNode("summaryLabel").height = 470
        m.top.findNode("summaryLabel").font = "font:SmallSystemFont"
        m.top.findNode("actionGrid").translation = [540, 870]
        m.top.findNode("watchedStateLabel").translation = [110, 708]
        m.top.findNode("watchedStateLabel").width = 360
        m.top.findNode("statusLabel").translation = [540, 985]
    end if
end sub

sub applySummaryFit(summary as string, data as dynamic)
    if data = invalid then return
    label = m.top.findNode("summaryLabel")
    actions = m.top.findNode("actionGrid")
    status = m.top.findNode("statusLabel")
    if label = invalid or actions = invalid then return

    textLen = len(summary)
    if data.type <> invalid and (data.type = "episode" or data.type = "homevideo")
        label.translation = [760, 410]
        label.width = 1040
        label.font = "font:SmallSystemFont"
        label.height = 390
        actions.translation = [760, 835]
        if status <> invalid then status.translation = [760, 965]
        if textLen > 760
            label.font = "font:TinySystemFont"
            label.height = 430
            actions.translation = [760, 875]
            if status <> invalid then status.translation = [760, 1010]
        end if
    else
        label.translation = [540, 386]
        label.width = 1180
        label.font = "font:SmallSystemFont"
        label.height = 470
        actions.translation = [540, 870]
        if status <> invalid then status.translation = [540, 1005]
        if textLen > 760
            label.font = "font:TinySystemFont"
            label.translation = [540, 374]
            label.height = 500
            actions.translation = [540, 890]
            if status <> invalid then status.translation = [540, 1015]
        end if
        if textLen > 1150
            label.translation = [540, 366]
            label.height = 510
            actions.translation = [540, 898]
            if status <> invalid then status.translation = [540, 1020]
        end if
    end if
end sub

sub onActionSelected(event as object)
    idx = event.getData()
    if idx = 0
        m.top.playVideo = m.top.videoData
    else if idx = 1
        checked = toggleAction(idx)
        notifyLocalListChange(idx, checked)
        syncSynologyCollection(idx, checked)
        m.top.findNode("statusLabel").text = ""
        populateActions()
        restoreActionFocus(idx)
    else if idx = 2
        checked = toggleAction(idx)
        notifyLocalListChange(idx, checked)
        syncSynologyCollection(idx, checked)
        m.top.findNode("statusLabel").text = ""
        populateActions()
        restoreActionFocus(idx)
    else if idx = 3
        checked = toggleAction(idx)
        notifyLocalListChange(idx, checked)
        syncSynologyCollection(idx, checked)
        m.top.findNode("statusLabel").text = ""
        populateActions()
        restoreActionFocus(idx)
    end if
end sub

sub notifyLocalListChange(idx as integer, checked as boolean)
    key = actionKey(idx)
    if key = "" then return
    m.top.listChanged = true
    if checked = false and isSourceListAction(key)
        m.top.sourceListRemoved = true
    end if
end sub

sub onRatingSelected(event as object)
    idx = event.getData()
    if idx < 0 then return
    current = selectedRatingStars()
    stars = idx + 1
    if stars = current then stars = 0
    rating = stars * 20
    m.ratingFocusIndex = idx
    print "RATING_SELECT idx="; idx; " currentStars="; current; " newRating="; rating
    setLocalRating(rating)
    populateRatingStars()
    syncRating(rating)
    grid = m.top.findNode("ratingGrid")
    grid.jumpToItem = idx
    grid.setFocus(true)
end sub

sub syncRating(rating as integer)
    data = m.top.videoData
    if data = invalid or data.authData = invalid then return
    videoId = videoIdForSync(data)
    if videoId = "" or videoId = "0" then return
    task = createObject("roSGNode", "APITask")
    task.request = {
        action: "setVideoRating",
        baseUrl: data.authData.baseUrl,
        sid: data.authData.sid,
        synoToken: data.authData.synoToken,
        videoType: data.type,
        videoId: videoId,
        rating: rating
    }
    task.observeField("response", "onDetailStateSyncResponse")
    task.control = "RUN"
    m.ratingSyncTask = task
end sub

sub onDetailStateSyncResponse(event as object)
    response = event.getData()
    if response = invalid then return
    print "DETAIL_STATE_SYNC success="; response.lookUp("success"); " rating="; response.lookUp("rating"); " error="; response.lookUp("error"); " detail="; response.lookUp("detail")
    if response.success = true and response.rating <> invalid
        setLocalRating(response.rating)
        populateRatingStars()
    end if
end sub

sub syncSynologyCollection(idx as integer, enabled as boolean)
    data = m.top.videoData
    if data = invalid or data.authData = invalid then return
    videoId = ""
    if data.videoStationId <> invalid then videoId = safeIntText(data.videoStationId)
    if videoId = "" or videoId = "0" then videoId = safeIntText(data.id)
    if videoId = "" or videoId = "0" then return
    proxyBaseUrl = invalid
    if data.authData.proxyBaseUrl <> invalid then proxyBaseUrl = data.authData.proxyBaseUrl
    filePath = invalid
    if data.filePath <> invalid then filePath = data.filePath
    mapperId = invalid
    if data.mapperId <> invalid then mapperId = data.mapperId
    videoType = data.type
    if data.collectionVideoType <> invalid and data.collectionVideoType <> "" then videoType = data.collectionVideoType
    print "COLLECTION_SYNC_REQUEST key="; actionKey(idx); " enabled="; enabled; " type="; videoType; " title="; data.lookUp("title"); " videoId="; videoId; " mapper="; mapperId
    m.pendingCollectionIdx = idx
    m.pendingCollectionEnabled = enabled
    m.pendingCollectionSourceListRemoval = isSourceListAction(actionKey(idx)) and enabled = false
    task = createObject("roSGNode", "APITask")
    task.request = {
        action: "toggleCollectionVideo",
        baseUrl: data.authData.baseUrl,
        proxyBaseUrl: proxyBaseUrl,
        sid: data.authData.sid,
        synoToken: data.authData.synoToken,
        localKey: actionKey(idx),
        collectionId: collectionIdForAction(idx),
        videoType: videoType,
        videoId: videoId,
        mapperId: mapperId,
        filePath: filePath,
        enabled: enabled
    }
    task.observeField("response", "onCollectionSyncResponse")
    task.control = "RUN"
    m.collectionSyncTask = task
end sub

sub onCollectionSyncResponse(event as object)
    response = event.getData()
    if response = invalid then return
    print "COLLECTION_SYNC success="; response.lookUp("success"); " error="; response.lookUp("error"); " detail="; response.lookUp("detail")
    if response.success = true
        m.top.listChanged = true
        if m.pendingCollectionIdx <> invalid and m.pendingCollectionIdx > 0
            restoreActionFocus(m.pendingCollectionIdx)
        end if
    else if m.pendingCollectionIdx <> invalid and m.pendingCollectionIdx > 0 and m.pendingCollectionEnabled <> false
        key = actionKey(m.pendingCollectionIdx)
        if key <> "" and m.pendingCollectionEnabled <> invalid and m.actionOverrides <> invalid
            m.actionOverrides.addReplace(key, not m.pendingCollectionEnabled)
            populateActions()
            restoreActionFocus(m.pendingCollectionIdx)
        end if
    end if
end sub

function hasPendingCollectionOverride(key as string) as boolean
    if key = "" then return false
    if m.pendingCollectionIdx = invalid then return false
    if m.pendingCollectionIdx <= 0 then return false
    pendingKey = actionKey(m.pendingCollectionIdx)
    return pendingKey = key
end function

function isSourceListAction(key as string) as boolean
    data = m.top.videoData
    if data = invalid then return false
    return data.sourceListKey <> invalid and data.sourceListKey = key
end function

function collectionIdForAction(idx as integer) as string
    if idx = 1 then return "-1"
    if idx = 2 then return "-2"
    if idx = 3 then return "-3"
    return ""
end function

sub restoreActionFocus(idx as integer)
    if idx < 0 then idx = 0
    if idx > 3 then idx = 3
    grid = m.top.findNode("actionGrid")
    if grid = invalid then return
    if grid.content = invalid then return
    grid.jumpToItem = idx
    grid.setFocus(true)
end sub

function safeIntText(value as dynamic) as string
    if value = invalid then return ""
    t = type(value)
    if t = "roString" or t = "String" then return value.trim()
    if t = "roInteger" or t = "Integer" or t = "roInt" or t = "roLongInteger" or t = "LongInteger" then return stri(value).trim()
    if t = "roFloat" or t = "Float" or t = "roDouble" or t = "Double" then return stri(int(value)).trim()
    return ""
end function

function videoIdForSync(data as object) as string
    if data = invalid then return ""
    if data.videoStationId <> invalid then return safeIntText(data.videoStationId)
    if data.id <> invalid then return safeIntText(data.id)
    return ""
end function

function numericField(data as object, key as string) as integer
    if data = invalid then return 0
    value = data.lookUp(key)
    if value = invalid then return 0
    t = type(value)
    if t = "roInteger" or t = "Integer" or t = "roInt" or t = "roLongInteger" or t = "LongInteger" then return value
    if t = "roFloat" or t = "Float" or t = "roDouble" or t = "Double" then return int(value)
    if t = "roString" or t = "String" then return int(val(value))
    return 0
end function

function firstNumericField(data as object, keys as object) as integer
    if data = invalid then return 0
    for each key in keys
        value = data.lookUp(key)
        if value <> invalid
            t = type(value)
            if t = "roInteger" or t = "Integer" or t = "roInt" or t = "roLongInteger" or t = "LongInteger"
                normalized = normalizeRatingValue(value)
                if normalized > 0 then return normalized
            end if
            if t = "roFloat" or t = "Float" or t = "roDouble" or t = "Double"
                normalized = normalizeRatingValue(value)
                if normalized > 0 then return normalized
            end if
            if t = "roString" or t = "String"
                trimmed = value.trim()
                if trimmed <> ""
                    normalized = normalizeRatingValue(val(trimmed))
                    if normalized > 0 then return normalized
                end if
            end if
        end if
    end for
    additional = data.lookUp("additional")
    if additional <> invalid
        for each key in keys
            value = additional.lookUp(key)
            if value <> invalid
                t = type(value)
                if t = "roInteger" or t = "Integer" or t = "roInt" or t = "roLongInteger" or t = "LongInteger"
                    normalized = normalizeRatingValue(value)
                    if normalized > 0 then return normalized
                end if
                if t = "roFloat" or t = "Float" or t = "roDouble" or t = "Double"
                    normalized = normalizeRatingValue(value)
                    if normalized > 0 then return normalized
                end if
                if t = "roString" or t = "String"
                    trimmed = value.trim()
                    if trimmed <> ""
                        normalized = normalizeRatingValue(val(trimmed))
                        if normalized > 0 then return normalized
                    end if
                end if
            end if
        end for
        extra = parsedObject(additional.lookUp("extra"))
        value = firstNumericFromObject(extra, keys)
        if value > 0 then return normalizeRatingValue(value)
    end if
    extra = parsedObject(data.lookUp("extra"))
    value = firstNumericFromObject(extra, keys)
    if value > 0 then return normalizeRatingValue(value)
    value = nestedDbRating(data)
    if value > 0 then return normalizeRatingValue(value)
    return 0
end function

function firstNumericFromObject(item as dynamic, keys as object) as integer
    if item = invalid then return -1
    if type(item) <> "roAssociativeArray" then return -1
    for each key in keys
        value = item.lookUp(key)
        if value <> invalid
            t = type(value)
            if t = "roInteger" or t = "Integer" or t = "roInt" or t = "roLongInteger" or t = "LongInteger" then return value
            if t = "roFloat" or t = "Float" or t = "roDouble" or t = "Double" then return int(value)
            if t = "roString" or t = "String"
                trimmed = value.trim()
                if trimmed <> "" then return int(val(trimmed))
            end if
        end if
    end for
    return -1
end function

function numericValue(value as dynamic) as integer
    if value = invalid then return 0
    t = type(value)
    if t = "roInteger" or t = "Integer" or t = "roInt" or t = "roLongInteger" or t = "LongInteger" then return value
    if t = "roFloat" or t = "Float" or t = "roDouble" or t = "Double" then return int(value)
    if t = "roString" or t = "String"
        trimmed = value.trim()
        if trimmed <> "" then return int(val(trimmed))
    end if
    return 0
end function

function parsedObject(value as dynamic) as dynamic
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

function nestedDbRating(data as object) as integer
    candidates = []
    if data <> invalid
        ratingCandidate = data.lookUp("rating")
        if ratingCandidate <> invalid then candidates.push(ratingCandidate)
        extra = parsedObject(data.lookUp("extra"))
        if extra <> invalid then candidates.push(extra)
        additional = data.lookUp("additional")
        if additional <> invalid
            ratingCandidate = additional.lookUp("rating")
            if ratingCandidate <> invalid then candidates.push(ratingCandidate)
            extra = parsedObject(additional.lookUp("extra"))
            if extra <> invalid then candidates.push(extra)
        end if
    end if
    best = 0
    for each extraObj in candidates
        anyRating = anyNestedRating(extraObj, 0)
        if anyRating > best then best = anyRating
        if type(extraObj) = "roAssociativeArray"
            for each dbKey in ["synoVideoDb", "synovideodb", "theMovieDb", "themoviedb", "theTVDb", "thetvdb"]
                db = extraObj.lookUp(dbKey)
                if db <> invalid and type(db) = "roAssociativeArray"
                    ratingObj = db.lookUp("rating")
                    if ratingObj <> invalid and type(ratingObj) = "roAssociativeArray"
                        for each ratingKey in ["synovideodb", "synoVideoDb", "themoviedb", "theMovieDb", "thetvdb", "theTVDb", "rating"]
                            value = ratingObj.lookUp(ratingKey)
                            if value <> invalid
                                num = numericValue(value)
                                if num > 0 and num <= 10 then num = num * 10
                                if num > best then best = num
                            end if
                        end for
                    end if
                end if
            end for
        end if
    end for
    if best > 100 then best = 100
    return best
end function

function anyNestedRating(value as dynamic, depth as integer) as integer
    if value = invalid or depth > 4 then return 0
    t = type(value)
    if t = "roInteger" or t = "Integer" or t = "roInt" or t = "roLongInteger" or t = "LongInteger" or t = "roFloat" or t = "Float" or t = "roDouble" or t = "Double"
        return normalizeRatingValue(value)
    end if
    if t = "roString" or t = "String"
        trimmed = value.trim()
        if trimmed = "" then return 0
        parsed = parseJSON(trimmed)
        if parsed <> invalid then return anyNestedRating(parsed, depth + 1)
        return normalizeRatingValue(val(trimmed))
    end if
    if t = "roArray"
        best = 0
        for each child in value
            score = anyNestedRating(child, depth + 1)
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
                score = anyNestedRating(child, depth + 1)
            else if type(child) = "roAssociativeArray"
                score = anyNestedRating(child, depth + 1)
            end if
            if score > best then best = score
        end for
        return best
    end if
    return 0
end function

function hasNumericField(data as object, keys as object) as boolean
    if data = invalid then return false
    for each key in keys
        if data.lookUp(key) <> invalid then return true
    end for
    additional = data.lookUp("additional")
    if additional <> invalid
        for each key in keys
            if additional.lookUp(key) <> invalid then return true
        end for
        extra = parsedObject(additional.lookUp("extra"))
        if extra <> invalid
            for each key in keys
                if extra.lookUp(key) <> invalid then return true
            end for
        end if
    end if
    extra = parsedObject(data.lookUp("extra"))
    if extra <> invalid
        for each key in keys
            if extra.lookUp(key) <> invalid then return true
        end for
    end if
    return false
end function

function normalizeRatingValue(value as dynamic) as integer
    if value < 0 then return 0
    if value > 0 and value <= 10 then return int((value * 10) + 0.5)
    if value > 100 then return 100
    return int(value)
end function

function ratingValue() as integer
    if m.ratingOverride <> invalid then return m.ratingOverride
    return firstNumericField(m.detailData, ["rating", "rate", "user_rating", "userRating", "my_rating", "myRating"])
end function

function ratingStars() as integer
    return int(ratingHalfSteps() / 2)
end function

function selectedRatingStars() as integer
    halfSteps = ratingHalfSteps()
    if halfSteps mod 2 <> 0 then return -1
    return int(halfSteps / 2)
end function

function ratingHalfSteps() as integer
    rating = ratingValue()
    if rating <= 0 then return 0
    halfSteps = int((rating / 10) + 0.5)
    if halfSteps < 0 then halfSteps = 0
    if halfSteps > 10 then halfSteps = 10
    return halfSteps
end function

sub populateRatingStars()
    content = createObject("roSGNode", "ContentNode")
    halfSteps = ratingHalfSteps()
    print "RATING_RENDER type="; m.detailData.lookUp("type"); " title="; m.detailData.lookUp("title"); " rating="; ratingValue(); " halfSteps="; halfSteps
    i = 1
    while i <= 5
        node = content.createChild("ContentNode")
        fill = "empty"
        selected = "false"
        if halfSteps >= i * 2
            fill = "full"
            selected = "true"
        else if halfSteps = (i * 2) - 1
            fill = "half"
            selected = "true"
        end if
        node.title = stri(i).trim()
        node.addFields({ fill: fill, selected: selected })
        i = i + 1
    end while
    grid = m.top.findNode("ratingGrid")
    grid.content = invalid
    grid.content = content
    if m.ratingFocusIndex <> invalid and m.ratingFocusIndex >= 0
        grid.jumpToItem = m.ratingFocusIndex
        if m.focusArea = "rating" then grid.setFocus(true)
    end if
end sub

sub populateWatchedState()
    label = m.top.findNode("watchedStateLabel")
    if label = invalid then return
    watchedState = explicitWatchedState()
    print "WATCHED_RENDER state="; watchedState; " ratio="; watchedRatioValue()
    if watchedState = 0
        label.text = "Unwatched"
        label.color = "#D7DBDE"
        label.visible = true
    else
        hideWatchedState()
    end if
end sub

sub hideWatchedState()
    label = m.top.findNode("watchedStateLabel")
    if label = invalid then return
    label.text = ""
    label.visible = false
end sub

function watchedRatioValue() as integer
    return watchedPercentField(m.detailData, ["watched_ratio", "watchedRatio"])
end function

function hasWatchedState(data as object) as boolean
    if explicitWatchedStateFromData(data) >= 0 then return true
    if hasNumericField(data, ["watched_ratio", "watchedRatio"]) then return true
    return false
end function

function explicitWatchedState() as integer
    return explicitWatchedStateFromData(m.detailData)
end function

function explicitWatchedStateFromData(data as object) as integer
    if data = invalid then return -1
    value = firstRawField(data, ["fileWatched", "file_watched", "watched", "is_watched", "isWatched"])
    if value = invalid then return -1
    t = type(value)
    if t = "roBoolean" or t = "Boolean"
        if value then return 1
        return 0
    end if
    if t = "roInteger" or t = "Integer" or t = "roInt" or t = "roLongInteger" or t = "LongInteger"
        if value <> 0 then return 1
        return 0
    end if
    if t = "roFloat" or t = "Float" or t = "roDouble" or t = "Double"
        if value <> 0 then return 1
        return 0
    end if
    if t = "roString" or t = "String"
        trimmed = lcase(value.trim())
        if trimmed = "" then return -1
        if trimmed = "true" or trimmed = "yes" or trimmed = "watched" then return 1
        if trimmed = "false" or trimmed = "no" or trimmed = "unwatched" then return 0
        if val(trimmed) <> 0 then return 1
        return 0
    end if
    return -1
end function

function watchedPercentField(data as object, keys as object) as integer
    value = firstRawField(data, keys)
    if value = invalid then return 0
    return watchedValueToPercent(value)
end function

function firstRawField(data as object, keys as object) as dynamic
    if data = invalid then return invalid
    for each key in keys
        value = data.lookUp(key)
        if value <> invalid then return value
    end for
    additional = data.lookUp("additional")
    if additional <> invalid
        for each key in keys
            value = additional.lookUp(key)
            if value <> invalid then return value
        end for
        extra = parsedObject(additional.lookUp("extra"))
        if extra <> invalid
            for each key in keys
                value = extra.lookUp(key)
                if value <> invalid then return value
            end for
        end if
    end if
    extra = parsedObject(data.lookUp("extra"))
    if extra <> invalid
        for each key in keys
            value = extra.lookUp(key)
            if value <> invalid then return value
        end for
    end if
    return invalid
end function

function watchedValueToPercent(value as dynamic) as integer
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

function nextRatingValue() as integer
    stars = ratingStars() + 1
    if stars > 5 then stars = 0
    return stars * 20
end function

sub setLocalRating(rating as integer)
    m.ratingOverride = rating
    if m.detailData = invalid then return
    m.detailData.addReplace("rating", rating)
end sub

sub onActionFocus(event as object)
    if event <> invalid and event.getData() = true then m.focusArea = "actions"
end sub

sub onRatingFocus(event as object)
    if event <> invalid and event.getData() = true then m.focusArea = "rating"
end sub

function actionKey(idx as integer) as string
    if idx = 1 then return "favorites"
    if idx = 2 then return "watchlist"
    if idx = 3 then return "shared"
    return ""
end function

function videoKey(data as object) as string
    if data = invalid then return ""
    prefix = "video"
    if data.type <> invalid and data.type <> "" then prefix = data.type
    idValue = invalid
    if data.id <> invalid then idValue = data.id
    if idValue = invalid and data.fileId <> invalid then idValue = data.fileId
    idText = safeIntText(idValue)
    if idText <> "" and idText <> "0" then return prefix + ":" + idText
    if data.filePath <> invalid and data.filePath <> "" then return prefix + ":" + data.filePath
    if data.title <> invalid and data.title <> "" then return prefix + ":" + data.title
    return ""
end function

function loadList(key as string) as object
    reg = createObject("roRegistrySection", "DSVideoLists")
    if not reg.exists(key) then return []
    raw = reg.read(key)
    if raw = invalid or raw = "" then return []
    parsed = parseJson(raw)
    if parsed = invalid then return []
    return parsed
end function

sub saveList(key as string, items as object)
    reg = createObject("roRegistrySection", "DSVideoLists")
    reg.write(key, formatJson(items))
    reg.flush()
end sub

function isActionChecked(idx as integer) as boolean
    key = actionKey(idx)
    if key = "" then return false
    if m.actionOverrides <> invalid
        overridden = m.actionOverrides.lookUp(key)
        if overridden <> invalid then return overridden
    end if
    currentKey = videoKey(m.top.videoData)
    if currentKey = "" then return false
    items = loadList(key)
    for each item in items
        if savedItemKey(item) = currentKey then return true
    end for
    data = m.top.videoData
    if data <> invalid and data.sourceListKey <> invalid and data.sourceListKey = key then return true
    return false
end function

function savedItemKey(item as object) as string
    if item = invalid then return ""
    key = item.lookUp("listKey")
    if key = invalid then key = item.lookUp("listkey")
    if key = invalid then key = item.lookUp("key")
    if key <> invalid and key <> "" then return key
    return videoKey(item)
end function

function serializableVideo(data as object) as object
    item = {}
    item.listKey = videoKey(data)
    item.key = item.listKey
    item.pendingAdd = "true"
    if data.type <> invalid then item.type = data.type
    if data.id <> invalid then item.id = data.id
    if data.fileId <> invalid then item.fileId = data.fileId
    if data.mapperId <> invalid
        item.mapperId = data.mapperId
        item.mapper_id = data.mapperId
    end if
    if data.showMapperId <> invalid
        item.showMapperId = data.showMapperId
        item.show_mapper_id = data.showMapperId
    end if
    if data.filePath <> invalid then item.filePath = data.filePath
    if data.title <> invalid then item.title = data.title
    if data.showTitle <> invalid then item.showTitle = data.showTitle
    if data.summary <> invalid then item.summary = data.summary
    if data.watchedRatio <> invalid then item.watchedRatio = data.watchedRatio
    if data.rating <> invalid then item.rating = data.rating
    if data.posterRemoteUrl <> invalid and data.posterRemoteUrl <> ""
        item.posterUrl = data.posterRemoteUrl
        item.posterRemoteUrl = data.posterRemoteUrl
    else if data.posterUrl <> invalid
        item.posterUrl = data.posterUrl
    end if
    if data.backdropRemoteUrl <> invalid and data.backdropRemoteUrl <> ""
        item.backdropUrl = data.backdropRemoteUrl
        item.backdropRemoteUrl = data.backdropRemoteUrl
    else if data.backdropUrl <> invalid
        item.backdropUrl = data.backdropUrl
    end if
    if data.originalAvailable <> invalid
        item.originalAvailable = data.originalAvailable
        item.original_available = data.originalAvailable
    end if
    if data.seasonNumber <> invalid then item.seasonNumber = data.seasonNumber
    if data.episodeNumber <> invalid then item.episodeNumber = data.episodeNumber
    if data.episodeMeta <> invalid then item.episodeMeta = data.episodeMeta
    return item
end function

function toggleAction(idx as integer) as boolean
    key = actionKey(idx)
    if key = "" then return false
    currentKey = videoKey(m.top.videoData)
    if currentKey = "" then return false
    print "TOGGLE_LIST key="; key; " videoKey="; currentKey

    items = loadList(key)
    updated = []
    found = false
    for each item in items
        if savedItemKey(item) = currentKey
            found = true
        else
            updated.push(item)
        end if
    end for

    if found
        saveList(key, updated)
        rememberRemovedListItem(key, currentKey)
        rememberRemovedVideoKeys(key, m.top.videoData)
        if m.actionOverrides <> invalid then m.actionOverrides.addReplace(key, false)
        print "TOGGLE_LIST removed count="; updated.count()
        return false
    end if

    data = m.top.videoData
    if data <> invalid and data.sourceListKey <> invalid and data.sourceListKey = key
        saveList(key, updated)
        rememberRemovedListItem(key, currentKey)
        rememberRemovedVideoKeys(key, data)
        if m.actionOverrides <> invalid then m.actionOverrides.addReplace(key, false)
        print "TOGGLE_LIST removed remote-only count="; updated.count()
        return false
    end if

    updated.push(serializableVideo(m.top.videoData))
    saveList(key, updated)
    forgetRemovedListItem(key, currentKey)
    forgetRemovedVideoKeys(key, m.top.videoData)
    if m.actionOverrides <> invalid then m.actionOverrides.addReplace(key, true)
    print "TOGGLE_LIST added count="; updated.count()
    return true
end function

function removedListKey(key as string) as string
    return key + "_removed"
end function

sub rememberRemovedListItem(key as string, itemKey as string)
    if key = "" or itemKey = "" then return
    items = loadList(removedListKey(key))
    for each existing in items
        if existing = itemKey then return
    end for
    items.push(itemKey)
    saveList(removedListKey(key), items)
end sub

sub rememberRemovedVideoKeys(key as string, data as object)
    if data = invalid then return
    keys = videoMatchKeys(data)
    for each itemKey in keys
        rememberRemovedListItem(key, itemKey)
    end for
end sub

sub forgetRemovedListItem(key as string, itemKey as string)
    if key = "" or itemKey = "" then return
    items = loadList(removedListKey(key))
    updated = []
    for each existing in items
        if existing <> itemKey then updated.push(existing)
    end for
    saveList(removedListKey(key), updated)
end sub

sub forgetRemovedVideoKeys(key as string, data as object)
    if data = invalid then return
    keys = videoMatchKeys(data)
    for each itemKey in keys
        forgetRemovedListItem(key, itemKey)
    end for
end sub

function videoMatchKeys(data as object) as object
    keys = []
    mainKey = videoKey(data)
    if mainKey <> "" then keys.push(mainKey)
    if data.sourceItemKey <> invalid and data.sourceItemKey <> "" then keys.push(data.sourceItemKey)
    itemType = "video"
    if data.type <> invalid and data.type <> "" then itemType = data.type
    if data.id <> invalid
        idText = safeIntText(data.id)
        if idText <> "" and idText <> "0" then keys.push(itemType + ":" + idText)
    end if
    if data.fileId <> invalid
        fileId = safeIntText(data.fileId)
        if fileId <> "" and fileId <> "0" then keys.push(itemType + ":file:" + fileId)
    end if
    if data.mapperId <> invalid
        mapper = safeIntText(data.mapperId)
        if mapper <> "" and mapper <> "0" then keys.push(itemType + ":mapper:" + mapper)
    end if
    if data.title <> invalid and data.title <> "" then keys.push(itemType + ":title:" + lcase(data.title))
    return keys
end function

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    if key = "up" and m.focusArea = "actions"
        grid = m.top.findNode("ratingGrid")
        idx = int((ratingHalfSteps() + 1) / 2) - 1
        if idx < 0 then idx = 0
        grid.jumpToItem = idx
        grid.setFocus(true)
        m.focusArea = "rating"
        return true
    end if
    if key = "down" and m.focusArea = "rating"
        grid = m.top.findNode("actionGrid")
        grid.jumpToItem = 0
        grid.setFocus(true)
        m.focusArea = "actions"
        return true
    end if
    if key = "back"
        m.top.backPressed = true
        return true
    end if
    return false
end function
