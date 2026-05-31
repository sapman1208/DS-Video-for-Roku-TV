sub init()
    m.top.observeField("itemContent", "onContentSet")
    m.top.observeField("focusPercent", "onFocusChange")
end sub

sub onContentSet(event as object)
    content = event.getData()
    if content = invalid then return
    m.top.findNode("titleLabel").text = content.title
end sub

sub onFocusChange(event as object)
    pct = event.getData()
    m.top.findNode("focusBg").opacity = pct * 0.18
    if pct > 0.5
        m.top.findNode("titleLabel").color = "#FFFFFF"
    else
        m.top.findNode("titleLabel").color = "#D8D8D8"
    end if
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if press and key = "back" then return true
    return false
end function
