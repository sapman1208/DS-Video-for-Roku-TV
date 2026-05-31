sub init()
    m.top.observeField("itemContent", "onContentSet")
    m.top.observeField("focusPercent", "onFocusChange")
end sub

sub onContentSet(event as object)
    content = event.getData()
    if content = invalid then return
    m.top.findNode("titleLabel").text = content.title
    desc = ""
    if content.description <> invalid then desc = content.description
    m.top.findNode("descLabel").text = desc
end sub

sub onFocusChange(event as object)
    pct = event.getData()
    m.top.findNode("focusBg").opacity = pct
    if pct > 0.5
        m.top.findNode("titleLabel").color = "#FFFFFF"
        m.top.findNode("descLabel").color = "#E4EEF8"
    else
        m.top.findNode("titleLabel").color = "#CCCCCC"
        m.top.findNode("descLabel").color = "#AFC4D8"
    end if
end sub
