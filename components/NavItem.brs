sub init()
    m.top.observeField("itemContent", "onContentSet")
    m.top.observeField("focusPercent", "onFocusChange")
    m.active = false
    m.focused = false
end sub

sub onContentSet(event as object)
    content = event.getData()
    if content = invalid then return
    m.top.findNode("titleLabel").text = content.title
    m.active = false
    if content.isActiveNav <> invalid and content.isActiveNav = "true" then m.active = true
    updateVisual()
end sub

sub onFocusChange(event as object)
    pct = event.getData()
    m.focused = pct > 0.5
    updateVisual()
end sub

sub updateVisual()
    opacity = 0
    if m.active then opacity = 0.18
    if m.focused then opacity = 0.28
    m.top.findNode("focusBg").opacity = opacity
    if m.active or m.focused
        m.top.findNode("titleLabel").color = "#FFFFFF"
    else
        m.top.findNode("titleLabel").color = "#D8D8D8"
    end if
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if press and key = "back" then return true
    return false
end function
