sub init()
    m.top.observeField("itemContent", "onContentSet")
    m.top.observeField("focusPercent", "onFocusChange")
end sub

sub onContentSet(event as object)
    applyStarContent(event.getData())
end sub

sub onFocusChange(event as object)
    applyStarContent(m.top.itemContent)
end sub

sub applyStarContent(content as dynamic)
    base = m.top.findNode("starBase")
    fill = m.top.findNode("starFill")
    if base <> invalid then base.opacity = 0.25
    if fill = invalid then return
    fill.opacity = 0
    fill.uri = "pkg:/images/detail-star.png"
    if content = invalid then return
    if content.fill = "full"
        fill.uri = "pkg:/images/detail-star.png"
        fill.opacity = 1
    else if content.fill = "half"
        fill.uri = "pkg:/images/detail-star-half.png"
        fill.opacity = 1
    else if content.fillOpacity <> invalid
        fill.opacity = val(content.fillOpacity)
    else if content.selected = "true"
        fill.opacity = 1
    end if
end sub
