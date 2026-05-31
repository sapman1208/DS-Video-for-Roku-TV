sub init()
    m.top.observeField("itemContent", "onContentSet")
    m.top.observeField("focusPercent", "onFocusChange")
end sub

sub onContentSet(event as object)
    content = event.getData()
    if content = invalid then return
    m.top.findNode("titleLabel").text = content.title
    if content.description <> invalid
        m.top.findNode("episodeLabel").text = content.description
    else
        m.top.findNode("episodeLabel").text = ""
    end if

    poster = m.top.findNode("poster")
    if content.HDPosterUrl <> invalid and content.HDPosterUrl <> ""
        poster.uri = content.HDPosterUrl
        poster.visible = true
    else if content.SDPosterUrl <> invalid and content.SDPosterUrl <> ""
        poster.uri = content.SDPosterUrl
        poster.visible = true
    else
        poster.visible = false
    end if
end sub

sub onFocusChange(event as object)
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    content = m.top.itemContent
    if content = invalid then return false
    if key = "down" and content.preventWrapDown = "true" then return true
    return false
end function
