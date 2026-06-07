sub init()
    m.nasAddress = ""
    m.nasPort = "5001"
    m.useHttps = true
    m.username = ""
    m.password = ""
    m.activeField = ""
    m.focusIndex = 0
    m.focusArea = "settings"
    m.fieldRowsActive = false
    m.pendingKeyboardFocus = 0
    m.pendingKeyboardClose = false
    m.pendingKeyboardRefocusPasses = 0
    m.pendingKeyboardReturnToNav = false
    m.categories = []
    m.rowYs = [190, 290, 390, 490, 590, 740]
    m.top.focusable = true

    nav = m.top.findNode("categoryList")
    nav.observeField("itemSelected", "onNavSelected")
    nav.observeField("itemFocused", "onNavItemFocused")
    nav.observeField("focus", "onNavFocus")
    m.top.findNode("keyboardFocusTimer").observeField("fire", "onKeyboardFocusTimer")
    m.top.observeField("navCategories", "onNavCategoriesSet")
    m.top.observeField("focusNavCategory", "onFocusNavCategory")
    m.top.observeField("keyInput", "onKeyInput")

    loadSavedCredentials()
    updateAllValues()
    hideFieldHighlight()
    loadNavCategories()
end sub

sub loadSavedCredentials()
    reg = createObject("roRegistrySection", "DSVideo")
    if reg.exists("nasAddress") then m.nasAddress = readProtectedSetting(reg, "nasAddress")
    if reg.exists("nasPort") then m.nasPort = readProtectedSetting(reg, "nasPort")
    if reg.exists("useHttps") then m.useHttps = (reg.read("useHttps") = "true")
    if reg.exists("username") then m.username = readProtectedSetting(reg, "username")
    if reg.exists("password") then m.password = readProtectedSetting(reg, "password")
end sub

sub saveCredentials()
    reg = createObject("roRegistrySection", "DSVideo")
    writeProtectedSetting(reg, "nasAddress", m.nasAddress)
    writeProtectedSetting(reg, "nasPort", m.nasPort)
    if m.useHttps
        reg.write("useHttps", "true")
    else
        reg.write("useHttps", "false")
    end if
    writeProtectedSetting(reg, "username", m.username)
    writeProtectedSetting(reg, "password", m.password)
    reg.flush()
end sub

sub updateAllValues()
    if m.nasAddress = ""
        m.top.findNode("row0value").text = "(not set)"
    else
        m.top.findNode("row0value").text = m.nasAddress
    end if
    m.top.findNode("row1value").text = m.nasPort
    if m.useHttps
        m.top.findNode("row2value").text = "HTTPS  (OK to toggle)"
    else
        m.top.findNode("row2value").text = "HTTP  (OK to toggle)"
    end if
    m.top.findNode("row3value").text = m.username
    if m.password = ""
        m.top.findNode("row4value").text = "(not set)"
    else
        m.top.findNode("row4value").text = "********"
    end if
end sub

function readProtectedSetting(reg as object, key as string) as string
    if reg = invalid then return ""
    if not reg.exists(key) then return ""
    return unprotectSetting(reg.read(key), key)
end function

sub writeProtectedSetting(reg as object, key as string, value as string)
    if reg = invalid then return
    reg.write(key, protectSetting(value, key))
end sub

function protectSetting(value as dynamic, key as string) as string
    if value = invalid then return ""
    if type(value) <> "roString" and type(value) <> "String" then return ""
    if value = "" then return ""
    secret = settingSecret(key)
    out = "enc:v1:"
    i = 1
    while i <= len(value)
        code = asc(mid(value, i, 1))
        secretIndex = ((i - 1) mod len(secret)) + 1
        salt = asc(mid(secret, secretIndex, 1)) + ((i * 17) mod 251)
        encoded = (code + salt) mod 256
        out = out + hexByte(encoded)
        i = i + 1
    end while
    return out
end function

function unprotectSetting(value as dynamic, key as string) as string
    if value = invalid then return ""
    if type(value) <> "roString" and type(value) <> "String" then return ""
    prefix = "enc:v1:"
    if left(value, len(prefix)) <> prefix then return value
    hexText = mid(value, len(prefix) + 1)
    secret = settingSecret(key)
    out = ""
    i = 1
    charIndex = 1
    while i <= len(hexText) - 1
        encoded = hexPairValue(mid(hexText, i, 2))
        secretIndex = ((charIndex - 1) mod len(secret)) + 1
        salt = asc(mid(secret, secretIndex, 1)) + ((charIndex * 17) mod 251)
        decoded = encoded - (salt mod 256)
        while decoded < 0
            decoded = decoded + 256
        end while
        out = out + chr(decoded)
        i = i + 2
        charIndex = charIndex + 1
    end while
    return out
end function

function settingSecret(key as string) as string
    return "DSVideo:Roku:" + key + ":2026"
end function

function hexByte(value as integer) as string
    high = int(value / 16)
    low = value - (high * 16)
    return hexDigit(high) + hexDigit(low)
end function

function hexDigit(value as integer) as string
    digits = "0123456789abcdef"
    return mid(digits, value + 1, 1)
end function

function hexPairValue(pair as string) as integer
    if len(pair) < 2 then return 0
    return hexDigitValue(left(pair, 1)) * 16 + hexDigitValue(mid(pair, 2, 1))
end function

function hexDigitValue(ch as string) as integer
    code = asc(lcase(ch))
    if code >= 48 and code <= 57 then return code - 48
    if code >= 97 and code <= 102 then return code - 87
    return 0
end function

sub setHighlight(idx as integer)
    m.focusIndex = idx
    m.top.findNode("rowHighlight").visible = true
    m.top.findNode("rowHighlight").translation = [580, m.rowYs[idx]]
    updateFocusBox(idx)
    setFocusBoxVisible(true)
    if idx = 5
        m.top.findNode("rowHighlight").color = "#6E737A"
    else
        m.top.findNode("rowHighlight").color = "#5F6670"
    end if
end sub

sub updateFocusBox(idx as integer)
    y = m.rowYs[idx]
    m.top.findNode("rowFocusTop").translation = [580, y]
    m.top.findNode("rowFocusBottom").translation = [580, y + 80]
    m.top.findNode("rowFocusLeft").translation = [580, y]
    m.top.findNode("rowFocusRight").translation = [1336, y]
end sub

sub setFocusBoxVisible(isVisible as boolean)
    m.top.findNode("rowFocusTop").visible = isVisible
    m.top.findNode("rowFocusBottom").visible = isVisible
    m.top.findNode("rowFocusLeft").visible = isVisible
    m.top.findNode("rowFocusRight").visible = isVisible
end sub

sub hideFieldHighlight()
    m.top.findNode("rowHighlight").visible = false
    setFocusBoxVisible(false)
end sub

sub enterFieldRows()
    nav = m.top.findNode("categoryList")
    if nav <> invalid
        nav.setFocus(false)
        nav.focusable = false
    end if
    setHighlight(0)
    m.fieldRowsActive = true
    m.focusArea = "settings"
    m.top.setFocus(true)
end sub

sub returnToNav()
    nav = m.top.findNode("categoryList")
    if nav <> invalid
        nav.focusable = true
        idx = settingsCategoryIndex()
        if idx >= 0 then nav.jumpToItem = idx
        nav.setFocus(true)
    end if
    m.focusArea = "nav"
    m.fieldRowsActive = false
    hideFieldHighlight()
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    print "SETTINGS_KEY key="; key; " focusArea="; m.focusArea; " fieldRows="; m.fieldRowsActive; " idx="; m.focusIndex
    if key = "back"
        if m.fieldRowsActive = true
            returnToNav()
            return true
        end if
        if m.fieldRowsActive = false then return false
        m.top.backPressed = true
        return true
    else if key = "down"
        if m.fieldRowsActive = false
            enterFieldRows()
            return true
        end if
        if m.focusIndex < 5 then setHighlight(m.focusIndex + 1)
        return true
    else if key = "up"
        if m.fieldRowsActive = true and m.focusIndex = 0
            returnToNav()
            return true
        end if
        if m.focusIndex > 0 then setHighlight(m.focusIndex - 1)
        return true
    else if key = "left" or key = "right"
        return true
    else if key = "OK"
        if m.fieldRowsActive = false then return true
        activateRow(m.focusIndex)
        return true
    end if
    return true
end function

sub onKeyInput(event as object)
    if event = invalid then return
    key = event.getData()
    if key = invalid or key = "" then return
    print "SETTINGS_KEY_INPUT key="; key
    onKeyEvent(key, true)
end sub

sub loadNavCategories()
    if m.top.navCategories <> invalid and m.top.navCategories.count() > 0
        m.categories = m.top.navCategories
        populateNavCategories()
    end if
end sub

sub onNavCategoriesSet(event as object)
    if event = invalid then return
    loadNavCategories()
end sub

sub populateNavCategories()
    contentNode = createObject("roSGNode", "ContentNode")
    for each cat in m.categories
        item = contentNode.createChild("ContentNode")
        item.title = cat.title
    end for
    nav = m.top.findNode("categoryList")
    nav.content = contentNode
    nav.numColumns = m.categories.count()
    focusSettingsNav()
end sub

sub focusSettingsNav()
    nav = m.top.findNode("categoryList")
    idx = settingsCategoryIndex()
    nav.focusable = true
    if idx >= 0 then nav.jumpToItem = idx
    nav.setFocus(true)
    m.focusIndex = 0
    m.focusArea = "nav"
    m.fieldRowsActive = false
    hideFieldHighlight()
end sub

function settingsCategoryIndex() as integer
    i = 0
    while i < m.categories.count()
        cat = m.categories[i]
        if cat.lookUp("category") = "settings" then return i
        i = i + 1
    end while
    return m.categories.count() - 1
end function

sub onNavFocus(event as object)
    if event.getData() = true and m.fieldRowsActive = false
        m.focusArea = "nav"
        hideFieldHighlight()
    end if
end sub

sub onNavItemFocused(event as object)
    if m.fieldRowsActive = true
        idx = settingsCategoryIndex()
        if idx >= 0 then m.top.findNode("categoryList").jumpToItem = idx
    end if
end sub

sub onNavSelected(event as object)
    idx = event.getData()
    if idx >= 0 and idx < m.categories.count()
        payload = categoryPayload(idx)
        if payload.category = "settings"
            focusSettingsNav()
            return
        end if
        m.top.selectedCategory = payload
    end if
end sub

function categoryPayload(idx as integer) as object
    return {
        category: m.categories[idx].category,
        title: m.categories[idx].title,
        libraryId: m.categories[idx].lookUp("libraryId")
    }
end function

sub onFocusNavCategory(event as object)
    if event.getData() = "settings"
        focusSettingsNav()
        m.top.findNode("categoryList").setFocus(true)
        m.focusArea = "nav"
    end if
end sub

sub activateRow(idx as integer)
    if idx = 0
        m.activeField = "address"
        showKeyboard("NAS Address (IP or hostname)", m.nasAddress)
    else if idx = 1
        m.activeField = "port"
        showKeyboard("Port", m.nasPort)
    else if idx = 2
        m.useHttps = not m.useHttps
        if m.useHttps
            if m.nasPort = "5000" then m.nasPort = "5001"
        else
            if m.nasPort = "5001" then m.nasPort = "5000"
        end if
        updateAllValues()
    else if idx = 3
        m.activeField = "username"
        showKeyboard("Username", m.username)
    else if idx = 4
        m.activeField = "password"
        showKeyboard("Password", "")
    else if idx = 5
        saveCredentials()
        showStatus("", false)
        returnToNav()
    end if
end sub

sub showKeyboard(title as string, currentText as string)
    dialog = createObject("roSGNode", "StandardKeyboardDialog")
    dialog.title = title
    dialog.text = currentText
    dialog.buttons = ["OK", "Cancel"]
    dialog.observeField("buttonSelected", "onKeyboardDone")
    m.currentDialog = dialog
    m.top.getScene().dialog = dialog
end sub

sub onKeyboardDone(event as object)
    if m.currentDialog = invalid
        m.activeField = ""
        queueKeyboardFocusRestore(0)
        return
    end if
    btnIdx = event.getData()
    entered = m.currentDialog.text
    completedField = m.activeField
    print "SETTINGS_KEYBOARD_DONE button="; btnIdx; " field="; completedField
    if btnIdx = 0
        if m.activeField = "address"
            m.nasAddress = entered
        else if m.activeField = "port"
            if entered <> "" then m.nasPort = entered
        else if m.activeField = "username"
            if entered <> "" then m.username = entered
        else if m.activeField = "password"
            m.password = entered
        end if
        updateAllValues()
    end if
    m.activeField = ""
    m.pendingKeyboardClose = true
    m.pendingKeyboardReturnToNav = false
    queueKeyboardFocusRestore(m.focusIndex)
end sub

sub queueKeyboardFocusRestore(rowIndex as integer)
    if rowIndex < 0 then rowIndex = 0
    if rowIndex > 5 then rowIndex = 5
    m.pendingKeyboardFocus = rowIndex
    m.pendingKeyboardRefocusPasses = 2
    timer = m.top.findNode("keyboardFocusTimer")
    if timer <> invalid
        timer.control = "stop"
        timer.control = "start"
    else
        restoreKeyboardFocus(rowIndex)
    end if
end sub

sub onKeyboardFocusTimer(event as object)
    print "SETTINGS_KEYBOARD_REFOCUS row="; m.pendingKeyboardFocus
    if m.pendingKeyboardClose = true
        print "SETTINGS_KEYBOARD_CLOSE_DELAYED"
        if m.currentDialog <> invalid
            m.currentDialog.close = true
            m.currentDialog.unobserveField("buttonSelected")
        end if
        m.top.getScene().dialog = invalid
        m.currentDialog = invalid
        m.pendingKeyboardClose = false
    end if
    if m.pendingKeyboardReturnToNav = true
        restoreSettingsNavFocus()
        m.pendingKeyboardReturnToNav = false
        m.pendingKeyboardRefocusPasses = 0
    else
        restoreKeyboardFocus(m.pendingKeyboardFocus)
    end if
    if m.pendingKeyboardRefocusPasses > 0
        m.pendingKeyboardRefocusPasses = m.pendingKeyboardRefocusPasses - 1
        timer = m.top.findNode("keyboardFocusTimer")
        if timer <> invalid
            timer.control = "stop"
            timer.control = "start"
        end if
    end if
end sub

sub restoreSettingsNavFocus()
    nav = m.top.findNode("categoryList")
    hasNavFocus = false
    if nav <> invalid
        idx = settingsCategoryIndex()
        if idx >= 0 then nav.jumpToItem = idx
        nav.setFocus(true)
        hasNavFocus = nav.hasFocus()
    end if
    m.focusArea = "nav"
    m.fieldRowsActive = false
    hideFieldHighlight()
    print "SETTINGS_RETURN_NAV hasNavFocus="; hasNavFocus
end sub

sub restoreKeyboardFocus(rowIndex as integer)
    if rowIndex < 0 then rowIndex = 0
    if rowIndex > 5 then rowIndex = 5
    m.focusArea = "settings"
    m.top.findNode("rowHighlight").visible = true
    setHighlight(rowIndex)
    m.top.setFocus(true)
    print "SETTINGS_FOCUS_RESTORED hasFocus="; m.top.hasFocus()
end sub

sub showStatus(msg as string, isError as boolean)
    lbl = m.top.findNode("statusLabel")
    lbl.text = msg
    lbl.visible = msg <> ""
    if isError
        lbl.color = "#FF6B6B"
    else
        lbl.color = "#44AAFF"
    end if
end sub
