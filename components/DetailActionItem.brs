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
        icon = m.top.findNode("icon")
        glyph = m.top.findNode("playGlyph")
        label = m.top.findNode("titleLabel")

        icon.visible = false
        glyph.visible = false
        bg.color = "#2A2F33"
        bg.opacity = 0
        label.opacity = 0.82

        if content.iconUri <> invalid and content.iconUri <> ""
            icon.uri = content.iconUri
            icon.opacity = 1
            icon.visible = true
        else
            glyph.visible = true
        end if

        if content.rawTitle <> invalid and content.rawTitle <> "Play"
            icon.opacity = 0.34
            if content.checked <> invalid and content.checked = "true"
                icon.opacity = 1
            end if
        end if
    end if
end sub

sub onFocusChange(event as object)
    pct = event.getData()
    bg = m.top.findNode("bg")
    label = m.top.findNode("titleLabel")
    if pct > 0.5
        bg.opacity = 0
        bg.color = "#2A2F33"
        label.opacity = 1
    else
        bg.opacity = 0
        bg.color = "#2A2F33"
        label.opacity = 0.82
    end if
end sub
