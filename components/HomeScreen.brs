sub init()
    m.categories = []
    m.loaded = false

    list = m.top.findNode("categoryList")
    list.setFocus(true)
    list.observeField("itemSelected", "onCategorySelected")
    list.observeField("itemFocused", "onCategoryFocused")

    m.top.observeField("authData", "onAuthDataSet")
end sub

sub onAuthDataSet(event as object)
    if m.loaded then return
    authData = event.getData()
    if authData = invalid then return
    task = createObject("roSGNode", "APITask")
    task.request = {
        action: "listLibraries",
        baseUrl: authData.baseUrl,
        sid: authData.sid,
        synoToken: authData.synoToken
    }
    task.observeField("response", "onLibrariesLoaded")
    task.control = "RUN"
    m.loadTask = task
    m.loaded = true
end sub

sub onLibrariesLoaded(event as object)
    response = event.getData()
    items = invalid
    if response <> invalid and response.success = true then items = response.items
    if items = invalid or items.count() = 0
        items = [
            { title: "Playlist", category: "playlists", desc: "Browse Video Station playlists" },
            { title: "Movie", category: "movies", desc: "Browse your movie library" },
            { title: "TV Show", category: "tvshows", desc: "Browse TV series and episodes" },
            { title: "Home Video", category: "homevideos", desc: "Browse personal videos" },
            { title: "TV Recordings", category: "tvrecordings", desc: "Browse TV recordings" }
        ]
    end if

    m.categories = orderedCategories(items)
    m.categories.push({ title: "Settings", category: "settings", desc: "Edit NAS login and transcode settings" })
    m.top.navCategories = m.categories
    populateCategories()
end sub

function orderedCategories(items as object) as object
    ordered = []
    addCategoryByTitle(ordered, items, "Movie")
    addCategoryByTitle(ordered, items, "TV Show")
    addCategoryByTitle(ordered, items, "Home Video")
    addCategoryByTitle(ordered, items, "Ian's Shows")
    addCustomTvShowCategory(ordered, items)

    for each item in items
        title = item.lookUp("title")
        if title <> invalid and title <> "Settings"
            exists = false
            for each existing in ordered
                if existing.lookUp("title") = title then exists = true
            end for
            if not exists then ordered.push(item)
        end if
    end for
    return ordered
end function

sub addCategoryByTitle(target as object, items as object, wanted as string)
    for each item in items
        title = item.lookUp("title")
        if title <> invalid and lcase(title) = lcase(wanted)
            target.push(item)
            return
        end if
    end for
end sub

sub addCustomTvShowCategory(target as object, items as object)
    for each item in items
        title = item.lookUp("title")
        category = item.lookUp("category")
        libraryId = item.lookUp("libraryId")
        if category = "tvshows" and libraryId <> invalid and libraryId <> "" and libraryId <> "0"
            exists = false
            for each existing in target
                if existing.lookUp("title") = title then exists = true
                if existing.lookUp("libraryId") = libraryId then exists = true
            end for
            if not exists
                target.push(item)
                return
            end if
        end if
    end for
end sub

sub populateCategories()
    contentNode = createObject("roSGNode", "ContentNode")
    for each cat in m.categories
        item = contentNode.createChild("ContentNode")
        item.title = cat.title
    end for
    list = m.top.findNode("categoryList")
    list.content = contentNode
    list.numColumns = m.categories.count()
    list.setFocus(true)
    if m.categories.count() > 0 then m.top.findNode("categoryDesc").text = m.categories[0].desc
    if m.categories.count() > 0
        m.top.selectedCategory = categoryPayload(0)
    end if
end sub

sub onCategoryFocused(event as object)
    idx = event.getData()
    if idx >= 0 and idx < m.categories.count()
        m.top.findNode("categoryDesc").text = m.categories[idx].desc
    end if
end sub

sub onCategorySelected(event as object)
    idx = event.getData()
    if idx >= 0 and idx < m.categories.count()
        m.top.selectedCategory = categoryPayload(idx)
    end if
end sub

function categoryPayload(idx as integer) as object
    return {
        category: m.categories[idx].category,
        title: m.categories[idx].title,
        libraryId: m.categories[idx].lookUp("libraryId")
    }
end function

function onKeyEvent(key as string, press as boolean) as boolean
    if press and key = "back" then return false
    return false
end function
