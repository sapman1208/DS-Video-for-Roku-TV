sub init()
    m.top.observeField("itemContent", "onContentSet")
    m.top.observeField("focusPercent", "onFocusChange")
end sub

sub onContentSet(event as object)
    content = event.getData()
    if content <> invalid
        title = content.title
        m.top.findNode("titleLabel").text = title
        bg = m.top.findNode("bg")
        if content.checked <> invalid and content.checked = "true"
            bg.color = "#2E8B57"
        else
            bg.color = "#DF3540"
        end if
    end if
end sub

sub onFocusChange(event as object)
    pct = event.getData()
    if pct > 0.5
        m.top.findNode("bg").opacity = 1
    else
        m.top.findNode("bg").opacity = 0.72
    end if
end sub
