sub init()
    m.actions = ["Play", "Favorite", "Watch List", "Share"]
    m.actionOverrides = {}
    grid = m.top.findNode("actionGrid")
    grid.observeField("itemSelected", "onActionSelected")
    m.top.observeField("videoData", "onVideoDataSet")
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
        idx = idx + 1
    end for
    grid = m.top.findNode("actionGrid")
    grid.content = invalid
    grid.content = content
end sub

sub onVideoDataSet(event as object)
    data = event.getData()
    if data = invalid then return
    print "DETAIL_SET type="; data.lookUp("type"); " title="; data.lookUp("title")
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
            meta = "Home Video"
        else
            meta = data.type
        end if
    end if
    if data.originalAvailable <> invalid and data.originalAvailable <> ""
        if meta <> "" then meta = meta + "   "
        meta = meta + data.originalAvailable
    end if
    m.top.findNode("metaLabel").text = meta
    summary = ""
    if data.summary <> invalid then summary = data.summary
    if summary = "" and data.description <> invalid then summary = data.description
    if summary <> "" and title <> "" and lcase(summary.trim()) = lcase(title.trim()) then summary = ""
    if summary = "" then summary = "No description available."
    m.top.findNode("summaryLabel").text = summary
    poster = ""
	    if data.posterUrl <> invalid then poster = data.posterUrl
	    backdrop = ""
	    if data.backdropUrl <> invalid then backdrop = data.backdropUrl
	    print "DETAIL_ARTWORK type="; data.lookUp("type"); " title="; title; " posterSource="; artworkSourceFromUrl(poster); " backdropSource="; artworkSourceFromUrl(backdrop); " backdropUrl="; left(backdrop, 120)
	    configurePosterFrame(data)
    if poster <> ""
        m.top.findNode("poster").uri = poster
        m.top.findNode("poster").visible = true
        m.top.findNode("posterFallback").visible = false
    else
        m.top.findNode("poster").visible = false
        m.top.findNode("posterFallback").visible = true
    end if
    if backdrop <> ""
        m.top.findNode("backdrop").uri = backdrop
        m.top.findNode("backdrop").visible = true
    else
        m.top.findNode("backdrop").visible = false
    end if
    populateActions()
    m.top.findNode("actionGrid").setFocus(true)
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

    if data <> invalid and data.type <> invalid and data.type = "episode"
        poster.width = 630
        poster.height = 354
        poster.translation = [70, 190]
        poster.loadDisplayMode = "scaleToFit"

        fallback.width = 630
        fallback.height = 354
        fallback.translation = [70, 190]

        m.top.findNode("titleLabel").translation = [760, 150]
        m.top.findNode("titleLabel").width = 1040
        m.top.findNode("metaLabel").translation = [760, 230]
        m.top.findNode("metaLabel").width = 1000
        m.top.findNode("summaryLabel").translation = [760, 310]
        m.top.findNode("summaryLabel").width = 1040
        m.top.findNode("actionGrid").translation = [760, 610]
        m.top.findNode("statusLabel").translation = [760, 710]
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
        m.top.findNode("summaryLabel").translation = [540, 310]
        m.top.findNode("summaryLabel").width = 1180
        m.top.findNode("actionGrid").translation = [540, 610]
        m.top.findNode("statusLabel").translation = [540, 710]
    end if
end sub

sub onActionSelected(event as object)
    idx = event.getData()
    if idx = 0
        m.top.playVideo = m.top.videoData
    else if idx = 1
        checked = toggleAction(idx)
        m.top.listChanged = true
        syncSynologyCollection(idx, checked)
        if checked
            m.top.findNode("statusLabel").text = "Added to Favorites."
        else
            m.top.findNode("statusLabel").text = "Removed from Favorites."
        end if
        populateActions()
        restoreActionFocus(idx)
    else if idx = 2
        checked = toggleAction(idx)
        m.top.listChanged = true
        syncSynologyCollection(idx, checked)
        if checked
            m.top.findNode("statusLabel").text = "Added to Watch List."
        else
            m.top.findNode("statusLabel").text = "Removed from Watch List."
        end if
        populateActions()
        restoreActionFocus(idx)
    else if idx = 3
        checked = toggleAction(idx)
        m.top.listChanged = true
        syncSynologyCollection(idx, checked)
        if checked
            m.top.findNode("statusLabel").text = "Added to Shared Videos."
        else
            m.top.findNode("statusLabel").text = "Removed from Shared Videos."
        end if
        populateActions()
        restoreActionFocus(idx)
    end if
end sub

sub syncSynologyCollection(idx as integer, enabled as boolean)
    data = m.top.videoData
    if data = invalid or data.authData = invalid then return
    videoId = safeIntText(data.id)
    if videoId = "" or videoId = "0" then return
    task = createObject("roSGNode", "APITask")
    task.request = {
        action: "toggleCollectionVideo",
        baseUrl: data.authData.baseUrl,
        sid: data.authData.sid,
        synoToken: data.authData.synoToken,
        localKey: actionKey(idx),
        collectionId: collectionIdForAction(idx),
        videoType: data.type,
        videoId: videoId,
        enabled: enabled
    }
    task.control = "RUN"
    m.collectionSyncTask = task
end sub

function collectionIdForAction(idx as integer) as string
    if idx = 1 then return "-1"
    if idx = 2 then return "-2"
    if idx = 3 then return "-3"
    return ""
end function

sub restoreActionFocus(idx as integer)
    grid = m.top.findNode("actionGrid")
    grid.jumpToItem = idx
    grid.setFocus(true)
end sub

function safeIntText(value as dynamic) as string
    if value = invalid then return ""
    t = type(value)
    if t = "roString" or t = "String" then return value.trim()
    if t = "roInteger" or t = "Integer" then return stri(value).trim()
    if t = "roFloat" or t = "Float" then return stri(int(value)).trim()
    return ""
end function

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
    if data.summary <> invalid then item.summary = data.summary
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
    if data.originalAvailable <> invalid then item.originalAvailable = data.originalAvailable
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
    if key = "back"
        m.top.backPressed = true
        return true
    end if
    return false
end function
