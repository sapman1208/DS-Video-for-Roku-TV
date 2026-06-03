sub init()
    m.top.observeField("itemContent", "onContentSet")
    m.top.observeField("focusPercent", "onFocusChange")
    m.top.findNode("poster").observeField("loadStatus", "onPosterLoadStatus")
    m.content = invalid
end sub

sub onContentSet(event as object)
    content = event.getData()
    if content = invalid then return
    m.content = content
    mode = "portrait"
    if content.layoutMode <> invalid and content.layoutMode <> "" then mode = content.layoutMode
    applyLayoutMode(mode)
    m.top.findNode("titleLabel").text = content.title
    adjustSecondaryLine(mode, content.title)
    poster = m.top.findNode("poster")
    iconPoster = m.top.findNode("iconPoster")
    iconPoster.visible = false
    if content.HDPosterUrl <> invalid and content.HDPosterUrl <> ""
        poster.uri = content.HDPosterUrl
        poster.visible = true
    else if content.iconUrl <> invalid and content.iconUrl <> ""
        poster.visible = false
        iconPoster.uri = content.iconUrl
        iconPoster.visible = true
    else
        setContentArtworkState("false")
        poster.visible = false
    end if
    if content.description <> invalid and content.description <> ""
        m.top.findNode("yearLabel").text = content.description
    else
        m.top.findNode("yearLabel").text = ""
    end if
end sub

sub onPosterLoadStatus(event as object)
    if m.content = invalid then return
    status = event.getData()
    if status = invalid then return
    if status = "ready"
        setContentArtworkState("true")
    else if status = "failed" or status = "failure"
        setContentArtworkState("false")
    end if
end sub

sub setContentArtworkState(value as string)
    if m.content = invalid then return
    if m.content.hasField("artworkLoaded")
        m.content.artworkLoaded = value
    else
        m.content.addFields({ artworkLoaded: value })
    end if
end sub

sub adjustSecondaryLine(mode as string, titleText as string)
    if mode <> "compactPortrait" and mode <> "moviePortrait" then return
    year = m.top.findNode("yearLabel")
    if titleText = invalid then titleText = ""
    if len(titleText) <= 18
        year.translation = [0, 374]
    else if len(titleText) <= 36
        year.translation = [0, 394]
    else
        year.translation = [0, 412]
    end if
end sub

sub applyLayoutMode(mode as string)
    bg = m.top.findNode("bg")
    poster = m.top.findNode("poster")
    title = m.top.findNode("titleLabel")
    year = m.top.findNode("yearLabel")
    title.font = "font:SmallSystemFont"
    title.maxLines = 2
    title.lineSpacing = 0
    year.font = "font:SmallSystemFont"
    year.maxLines = 1
    year.wrap = false
    year.height = 34

    if mode = "landscape" or mode = "homeLandscape" or mode = "showLandscape"
        bg.width = 520
        bg.height = 292
        poster.width = 520
        poster.height = 292
        poster.loadDisplayMode = "scaleToZoom"
        if mode = "showLandscape" then poster.loadDisplayMode = "scaleToFit"
        m.top.findNode("iconPoster").width = 132
        m.top.findNode("iconPoster").height = 132
        m.top.findNode("iconPoster").translation = [194, 80]
        title.translation = [0, 308]
        title.width = 520
        title.height = 48
        year.translation = [0, 360]
        year.width = 520
        if mode = "homeLandscape"
            title.font = "font:TinySystemFont"
            title.height = 78
            title.maxLines = 3
            title.lineSpacing = -1
            year.translation = [0, 386]
        else if mode = "showLandscape"
            title.height = 76
            title.maxLines = 3
            year.translation = [0, 386]
        end if
    else if mode = "icon"
        bg.width = 220
        bg.height = 220
        poster.width = 220
        poster.height = 220
        poster.loadDisplayMode = "scaleToFit"
        m.top.findNode("iconPoster").width = 118
        m.top.findNode("iconPoster").height = 118
        m.top.findNode("iconPoster").translation = [51, 51]
        title.translation = [0, 236]
        title.width = 220
        title.height = 74
        title.font = "font:TinySystemFont"
        title.maxLines = 3
        title.lineSpacing = -1
        year.translation = [0, 316]
        year.width = 220
        year.font = "font:TinySystemFont"
    else
        bg.width = 220
        bg.height = 330
        poster.width = 220
        poster.height = 330
        poster.loadDisplayMode = "scaleToFill"
        m.top.findNode("iconPoster").width = 112
        m.top.findNode("iconPoster").height = 112
        m.top.findNode("iconPoster").translation = [54, 109]
        title.translation = [0, 334]
        title.width = 220
        title.height = 48
        year.translation = [0, 394]
        year.width = 220
        if mode = "compactPortrait" or mode = "moviePortrait"
            title.font = "font:TinySystemFont"
            title.height = 76
            title.maxLines = 3
            title.lineSpacing = -1
            year.translation = [0, 412]
            year.font = "font:TinySystemFont"
            year.height = 78
            year.maxLines = 3
            year.wrap = true
        end if
    end if
end sub

sub onFocusChange(event as object)
    if event = invalid then return
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    return false
end function
