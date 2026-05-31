sub init()
    m.top.observeField("itemContent", "onContentSet")
    m.top.observeField("focusPercent", "onFocusChange")
    m.selected = false
    m.focused = false
end sub

sub onContentSet(event as object)
    content = event.getData()
    if content = invalid then return
    m.top.findNode("titleLabel").text = content.title
    m.selected = false
    if content.isSelectedSeason <> invalid and content.isSelectedSeason = "true" then m.selected = true
    updateVisual()
end sub

sub onFocusChange(event as object)
    pct = event.getData()
    m.focused = pct > 0.5
    updateVisual()
end sub

sub updateVisual()
    opacity = 0
    if m.selected or m.focused then opacity = 0.18
    if m.focused then opacity = 0.28
    m.top.findNode("focusBg").opacity = opacity
    if m.selected or m.focused
        m.top.findNode("titleLabel").color = "#FFFFFF"
    else
        m.top.findNode("titleLabel").color = "#C8C8C8"
    end if
end sub
